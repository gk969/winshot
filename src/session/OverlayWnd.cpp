#include "stdafx.h"
#include "OverlayWnd.h"
#include "CaptureSession.h"
#include "SelectionModel.h"
#include "DesktopCapture.h"
#include "Dpi.h"
#include "AnnotationList.h"
#include "Shapes.h"
#include "TextEditor.h"
#include "Loupe.h"
#include "WindowPick.h"
#include "AppMessages.h"

#include <emmintrin.h>
#include <share.h>

namespace {

// Indexed by the eight-box handle order (top-left, top, top-right, right, ...),
// which is what annot::BoxHandleAt uses.
LPCTSTR kBoxCursors[] = {
    IDC_SIZENWSE, IDC_SIZENS, IDC_SIZENESW, IDC_SIZEWE,
    IDC_SIZENWSE, IDC_SIZENS, IDC_SIZENESW, IDC_SIZEWE,
};

bool SameBox(const Gdiplus::RectF& a, const Gdiplus::RectF& b) {
    return a.X == b.X && a.Y == b.Y && a.Width == b.Width && a.Height == b.Height;
}

// Inclusive, unlike CRect::PtInRect, which drops the bottom and right edges —
// and the frame's own edge is as far as a drag is allowed to reach.
bool InRegion(const RECT& s, CPoint pt) {
    return pt.x >= s.left && pt.x <= s.right && pt.y >= s.top && pt.y <= s.bottom;
}

// A box that lies wholly inside the region, edges touching allowed.
bool InRegion(const RECT& s, const Gdiplus::RectF& b) {
    return b.X >= s.left && b.Y >= s.top && b.X + b.Width <= s.right &&
           b.Y + b.Height <= s.bottom;
}

// The crosshair a drawing tool shows inside the region: a plain cross with a
// small square at its centre and no arrowheads, so it reads as "press and drag
// to start a shape" rather than as a pointer. IDC_CROSS has no centre square,
// and the region behind it is dimmed to near black, so the figure is white with
// a dark rim to survive a light ground as well as a dark one.
HCURSOR CrossCursor() {
    static const HCURSOR cursor = [] {
        // 32px is the cursor canvas at 100%; the system does not scale a cursor
        // an app made itself, and the figure is symmetric about both axes so the
        // mask's row order cannot show through.
        constexpr int k = 32;
        constexpr int c = 15;
        bool on[k][k]{};
        for (int i = 0; i < k; ++i) {
            on[c][i] = on[c + 1][i] = true;
            on[i][c] = on[i][c + 1] = true;
        }
        for (int j = c - 3; j <= c + 4; ++j)
            for (int i = c - 3; i <= c + 4; ++i)
                if (j == c - 3 || j == c + 4 || i == c - 3 || i == c + 4)
                    on[j][i] = true;

        unsigned char xorBits[k * k * 4]{};
        unsigned char andBits[k * 4]{};  // a set bit is transparent
        for (int row = 0; row < k; ++row) {
            for (int col = 0; col < k; ++col) {
                const bool ink = on[row][col];
                const bool rim = !ink && ((row > 0 && on[row - 1][col]) ||
                                          (row + 1 < k && on[row + 1][col]) ||
                                          (col > 0 && on[row][col - 1]) ||
                                          (col + 1 < k && on[row][col + 1]));
                unsigned char* px = &xorBits[(row * k + col) * 4];
                if (ink) {
                    px[0] = px[1] = px[2] = 0xFF;
                    px[3] = 0xFF;
                } else if (rim) {
                    px[3] = 0xFF;
                } else {
                    andBits[row * 4 + col / 8] |= (unsigned char)(0x80 >> col % 8);
                }
            }
        }

        BITMAPINFO bi{};
        bi.bmiHeader.biSize = sizeof(bi.bmiHeader);
        bi.bmiHeader.biWidth = k;
        bi.bmiHeader.biHeight = -k;  // top-down, so row 0 is the top row
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        bi.bmiHeader.biCompression = BI_RGB;
        void* bits = nullptr;
        HDC screen = ::GetDC(nullptr);
        HBITMAP color =
            ::CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
        ::ReleaseDC(nullptr, screen);
        HBITMAP mask = ::CreateBitmap(k, k, 1, 1, andBits);
        if (!color || !bits || !mask) {
            if (color) ::DeleteObject(color);
            if (mask) ::DeleteObject(mask);
            return (HCURSOR)nullptr;
        }
        memcpy(bits, xorBits, sizeof(xorBits));
        ICONINFO ii{};
        ii.fIcon = FALSE;
        ii.xHotspot = c + 1;
        ii.yHotspot = c + 1;
        ii.hbmColor = color;
        ii.hbmMask = mask;
        HCURSOR made = (HCURSOR)::CreateIconIndirect(&ii);
        ::DeleteObject(color);
        ::DeleteObject(mask);
        return made;
    }();
    return cursor;
}

const Gdiplus::Color kFrame(0xFF1E9FD4);
const Gdiplus::Color kDim(0x99000000);
const Gdiplus::Color kLabelBack(0xE0232323);
const Gdiplus::Color kLabelText(0xFFFFFFFF);
const Gdiplus::Color kCaretInk(0xFF232323);
const Gdiplus::Color kTipBack(0xFFFFFFFF);
const Gdiplus::Color kTipText(0xFF1F2328);
const Gdiplus::Color kTipEdge(0xFFC9CCD1);
// The 编辑 frame's scrollbar, over the page rather than beside it, as in
// 参考UI图/编辑长图.png.
const Gdiplus::Color kTrackBack(0x40FFFFFF);
const Gdiplus::Color kThumb(0xFF9AA0A6);
// 文字-点击位置-输入时红色文本框.png strokes the live edit in the annotation
// red whatever the chosen ink is.
const Gdiplus::Color kEditFrame(0xFFF73840);
// 文字-字体大小.png: the 字号 list is a white card with a blue edge.
const Gdiplus::Color kDropEdge(0xFF367EAA);
const wchar_t kFontFace[] = L"Microsoft YaHei UI";

}  // namespace

// ------------------------------------------------------------- the hover card
//
// 工具栏-矩形-提示.png: a white card hanging under the slot the pointer rests
// on. It has to cover the 粗细/颜色 bar, which opens directly below the toolbar,
// and a child window always paints above its parent's client area — so the card
// cannot be painted by the overlay at all, however it is positioned. It is its
// own top-level popup, in front of the overlay, as the 长截图 prompt card is.
class CTipCardWnd : public CWnd {
public:
    bool Create();
    // Screen coordinates: where the card's top edge centre goes, and the box it
    // has to stay inside.
    void Show(const CString& text, CPoint anchor, const CRect& limit);
    void Hide();

protected:
    afx_msg void OnPaint();
    afx_msg BOOL OnEraseBkgnd(CDC* dc);
    void PostNcDestroy() override {}
    DECLARE_MESSAGE_MAP()

private:
    CString m_text;
    std::unique_ptr<Gdiplus::Font> m_font;
};

BEGIN_MESSAGE_MAP(CTipCardWnd, CWnd)
    ON_WM_PAINT()
    ON_WM_ERASEBKGND()
END_MESSAGE_MAP()

bool CTipCardWnd::Create() {
    LPCTSTR cls = AfxRegisterWndClass(0, nullptr, nullptr, nullptr);
    if (!cls) return false;

    // TOPMOST to outrank the topmost overlay, NOACTIVATE so the card never takes
    // the keyboard from it. TRANSPARENT is what lets the click a tip is
    // describing reach the slot underneath — but only alongside LAYERED, which
    // is also what makes DWM composite a window that has no owner to draw it.
    if (!CreateEx(WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW |
                  WS_EX_TRANSPARENT | WS_EX_LAYERED,
                  cls, L"WinShotTipCard", WS_POPUP, 0, 0, 0, 0, nullptr, nullptr))
        return false;
    // A layered window shows nothing at all until it is given a layer: opaque
    // here, since the card paints its own paper and the click passes through on
    // the extended style rather than on a colour key.
    ::SetLayeredWindowAttributes(GetSafeHwnd(), 0, 255, LWA_ALPHA);

    Gdiplus::FontFamily family(kFontFace);
    m_font = std::make_unique<Gdiplus::Font>(
        &family, (Gdiplus::REAL)Dpi::S(GetSafeHwnd(), 12),
        Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
    return true;
}

void CTipCardWnd::Show(const CString& text, CPoint anchor, const CRect& limit) {
    m_text = text;

    // The window has to be the card's exact size before it paints, so the text
    // is measured here rather than left to OnPaint.
    Gdiplus::Bitmap probe(1, 1, PixelFormat32bppARGB);
    Gdiplus::Graphics m(&probe);
    m.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
    Gdiplus::RectF box;
    m.MeasureString(text.GetString(), text.GetLength(), m_font.get(),
                    Gdiplus::PointF(0, 0), &box);
    const int padX = Dpi::S(GetSafeHwnd(), 5), padY = Dpi::S(GetSafeHwnd(), 3);
    const int w = (int)std::ceil(box.Width) + padX * 2;
    const int h = (int)std::ceil(box.Height) + padY * 2;

    int x = anchor.x - w / 2;
    int y = anchor.y;
    if (x + w > limit.right) x = limit.right - w;
    if (x < limit.left) x = limit.left;
    // The card hangs below its anchor, which is what puts it over the property
    // bar. Only the bottom edge of the screen can push it up, and then it goes
    // above the anchor as it always has.
    if (y + h > limit.bottom) y = anchor.y - h - Dpi::S(GetSafeHwnd(), 8);
    if (y < limit.top) y = limit.top;

    MoveWindow(x, y, w, h, FALSE);
    ShowWindow(SW_SHOWNA);
    // A hover is answered with a paint straight away; waiting for the queue to
    // drain would leave the card a frame or two behind the pointer.
    InvalidateRect(nullptr, FALSE);
    ::UpdateWindow(GetSafeHwnd());
}

void CTipCardWnd::Hide() {
    if (GetSafeHwnd() && ::IsWindowVisible(GetSafeHwnd()))
        ShowWindow(SW_HIDE);
}

void CTipCardWnd::OnPaint() {
    CPaintDC dc(this);
    CRect cl;
    GetClientRect(&cl);
    if (cl.Width() <= 0 || cl.Height() <= 0) return;

    Gdiplus::Bitmap back(cl.Width(), cl.Height(), PixelFormat32bppARGB);
    {
        Gdiplus::Graphics g(&back);
        g.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);

        const Gdiplus::RectF r(0.0f, 0.0f, (Gdiplus::REAL)cl.Width(),
                               (Gdiplus::REAL)cl.Height());
        Gdiplus::SolidBrush paper(kTipBack);
        g.FillRectangle(&paper, r);
        Gdiplus::Pen edge(kTipEdge, 1.0f);
        g.DrawRectangle(&edge, 0.5f, 0.5f, (Gdiplus::REAL)cl.Width() - 1.0f,
                        (Gdiplus::REAL)cl.Height() - 1.0f);

        Gdiplus::SolidBrush ink(kTipText);
        g.DrawString(m_text, -1, m_font.get(),
                     Gdiplus::PointF((Gdiplus::REAL)Dpi::S(GetSafeHwnd(), 5),
                                     (Gdiplus::REAL)Dpi::S(GetSafeHwnd(), 3)),
                     &ink);
    }
    {
        Gdiplus::Graphics g(dc.GetSafeHdc());
        g.SetInterpolationMode(Gdiplus::InterpolationModeNearestNeighbor);
        g.DrawImage(&back, 0, 0, cl.Width(), cl.Height());
    }
}

BOOL CTipCardWnd::OnEraseBkgnd(CDC*) {
    return TRUE;
}

BEGIN_MESSAGE_MAP(COverlayWnd, CWnd)
    ON_WM_PAINT()
    ON_WM_ERASEBKGND()
    ON_WM_LBUTTONDOWN()
    ON_WM_LBUTTONDBLCLK()
    ON_WM_LBUTTONUP()
    ON_WM_RBUTTONDOWN()
    ON_WM_RBUTTONUP()
    ON_WM_RBUTTONDBLCLK()
    ON_WM_CONTEXTMENU()
    ON_WM_MOUSEMOVE()
    ON_WM_MOUSEWHEEL()
    ON_WM_SETCURSOR()
    ON_WM_KEYDOWN()
    ON_WM_WINDOWPOSCHANGING()
    ON_MESSAGE(WM_APP_EDITDONE, &COverlayWnd::OnEditDone)
    ON_MESSAGE(WM_APP_LSEDIT, &COverlayWnd::OnLsEdit)
END_MESSAGE_MAP()

BOOL COverlayWnd::Create(CaptureSession* session) {
    m_session = session;
    const DesktopCapture& cap = session->Capture();
    POINT org = cap.Origin();

    // CS_DBLCLKS for the double-click that re-edits a text annotation.
    LPCTSTR cls = AfxRegisterWndClass(CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS,
                                      ::LoadCursor(nullptr, IDC_ARROW),
                                      nullptr, nullptr);
    if (!cls) return FALSE;

    // WS_CLIPCHILDREN is not optional: OnPaint blits a full-client back buffer,
    // and without it that blit lands on top of the toolbar and property bar.
    if (!CreateEx(WS_EX_TOPMOST, cls, L"WinShotOverlay",
                  WS_POPUP | WS_VISIBLE | WS_CLIPCHILDREN,
                  org.x, org.y, cap.Width(), cap.Height(), nullptr, nullptr))
        return FALSE;

    m_origin = org;
    m_session->Sel().Reset(RECT{ 0, 0, cap.Width(), cap.Height() });

    if (!m_toolbar.Create(this, session)) return FALSE;
    if (!m_propbar.Create(this, session)) return FALSE;
    LayoutChrome();

    ::SetForegroundWindow(GetSafeHwnd());
    ::SetFocus(GetSafeHwnd());
    return TRUE;
}

COverlayWnd::COverlayWnd() = default;

COverlayWnd::~COverlayWnd() {
    // A top-level of its own, so nothing would take it down with this window.
    m_tipWnd.reset();
    if (m_propbar.GetSafeHwnd()) m_propbar.DestroyWindow();
    if (m_toolbar.GetSafeHwnd()) m_toolbar.DestroyWindow();
    m_base.Free();
    m_chrome.Free();
    m_out.Free();
}

void COverlayWnd::LayoutChrome() {
    if (!m_toolbar.GetSafeHwnd()) return;
    // In 长截图 the bars are hidden and the long-shot bar places itself.
    if (InLongShot()) return;
    const int pb = m_propbar.Visible() ? m_propbar.BarHeight() : 0;
    m_toolbar.Place(pb);
    if (pb) m_propbar.PlaceBelow(&m_toolbar);
}

void COverlayWnd::ChromeChanged() {
    m_propbar.Show(tb::IsTool(m_session->ActiveTool()));
    m_toolbar.Refresh();
    m_propbar.Refresh();
    LayoutChrome();
    Invalidate();
}

// ---------------------------------------------------------------- DibCanvas

bool DibCanvas::Reset(CSize s) {
    if (bmp && size.cx == s.cx && size.cy == s.cy) return true;
    Free();
    if (s.cx <= 0 || s.cy <= 0) return false;

    BITMAPINFO bi{};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = s.cx;
    bi.bmiHeader.biHeight = -s.cy;  // top-down, which is GDI+'s row order
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    bmp = ::CreateDIBSection(nullptr, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    dc = ::CreateCompatibleDC(nullptr);
    if (!bmp || !bits || !dc) {
        Free();
        return false;
    }
    ::SelectObject(dc, bmp);
    gx = std::make_unique<Gdiplus::Bitmap>(s.cx, s.cy, s.cx * 4,
                                           PixelFormat32bppARGB, (BYTE*)bits);
    if (!gx || gx->GetLastStatus() != Gdiplus::Ok) {
        Free();
        return false;
    }
    size = s;
    return true;
}

void DibCanvas::Free() {
    gx.reset();  // the GDI+ face reads the bits, so it goes first
    if (dc) ::DeleteDC(dc);
    if (bmp) ::DeleteObject(bmp);
    dc = nullptr;
    bmp = nullptr;
    bits = nullptr;
    size = CSize(0, 0);
}

// ------------------------------------------------------------------- painting

BOOL COverlayWnd::OnEraseBkgnd(CDC*) {
    return TRUE;  // OnPaint covers every pixel
}

void COverlayWnd::TouchBase() {
    m_baseDirty = true;
    if (GetSafeHwnd()) InvalidateRect(nullptr, FALSE);
}

void COverlayWnd::TouchBaseIn(const CRect& r) {
    m_baseDirty = true;
    InvalidatePart(r);
}

void COverlayWnd::BltBase(CDC* dc, const CRect& src, CPoint dst) {
    if (!m_base.dc || src.IsRectEmpty() || !dc) return;
    ::BitBlt(dc->GetSafeHdc(), dst.x, dst.y, src.Width(), src.Height(),
             m_base.dc, src.left, src.top, SRCCOPY);
}

// An in-place drag draws its shape in the chrome instead of under the dim, so
// the base has to stop drawing it the moment the drag starts. Without this the
// old position sits under the moving copy for the whole drag and only goes away
// when the button comes up.
void COverlayWnd::DropFromBase(const annot::Annotation& a) {
    m_baseDirty = true;
    InvalidateAnnoChange(&a, AnnoRect(&a));
}

namespace {
// Costs one getenv the first time and nothing after that; the probe run sets the
// variable and every other run pays a branch.
bool ProbeOn() {
    static const bool on =
        ::GetEnvironmentVariableW(L"WINSHOT_PAINTLOG", nullptr, 0) > 0;
    return on;
}
LONGLONG ProbeTicks() {
    LARGE_INTEGER t;
    ::QueryPerformanceCounter(&t);
    return t.QuadPart;
}
LONGLONG ProbeFreq() {
    static LARGE_INTEGER f = [] {
        LARGE_INTEGER r;
        ::QueryPerformanceFrequency(&r);
        return r;
    }();
    return f.QuadPart;
}
// Start/stop stamps for one paint: duration, update-region area, the gap since
// the previous paint started, and the wait from the last mouse move to this paint.
LONGLONG g_probeStart = 0, g_probePaintStart = 0, g_probeLastMove = 0;
class PaintProbe;
PaintProbe* g_probeCur = nullptr;
class PaintProbe {
public:
    PaintProbe() {
        if (!ProbeOn()) return;
        on = true;
        g_probeCur = this;
        t0 = ProbeTicks();
        gap = g_probeStart ? t0 - g_probeStart : 0;
        wait = g_probeLastMove ? t0 - g_probeLastMove : 0;
        g_probeStart = t0;
        g_probePaintStart = t0;
    }
    ~PaintProbe() {
        if (!on) return;
        // _SH_DENYNO: the default locks the file against readers, and a test that
        // wants to know where in the log its own actions start has to be able to
        // count the lines while the capture is still up.
        static FILE* log = ::_fsopen(
            "D:\\Project\\winshot\\obj\\paint.log", "w", _SH_DENYNO);
        if (!log) return;
        g_probeCur = nullptr;
        std::fprintf(log,
                     "%lld %ld %ld %lld %lld %d"
                     " %lld %lld %lld %lld %lld %lld %lld %lld %lld\n",
                     ProbeTicks() - t0, area.cx, area.cy, gap, wait, base ? 1 : 0,
                     mark[0], mark[1], mark[2], mark[3], mark[4],
                     mark[5], mark[6], mark[7], mark[8]);
        std::fflush(log);
    }
    CSize area{};
    bool base = false;
    // Absolute offsets from the paint's start, in chronological order; the report
    // differences them: begin, base, blit, dim, annos, frame+labels, loupe,
    // blend, end.
    void Mark(int i) {
        if (!on) return;
        mark[i] = ProbeTicks() - t0;
    }

private:
    bool on = false;
    LONGLONG t0 = 0, gap = 0, wait = 0;
    LONGLONG mark[9]{};
};
void ProbeMark(int i) {
    if (g_probeCur) g_probeCur->Mark(i);
}
}  // namespace

void COverlayWnd::OnPaint() {
    // BeginPaint/EndPaint rather than CPaintDC: rcPaint is the only way to learn
    // the update region once BeginPaint has validated it. BeginPaint empties the
    // region, so its actual shape — which for a selection drag is a thin ring
    // whose bounding rect is nearly the whole screen — has to be taken first.
    PaintProbe probe;
    HRGN upd = ::CreateRectRgn(0, 0, 0, 0);
    const BOOL haveUpd = upd && ::GetUpdateRgn(GetSafeHwnd(), upd, FALSE);
    PAINTSTRUCT ps;
    HDC hdc = ::BeginPaint(GetSafeHwnd(), &ps);
    if (!hdc) {
        if (upd) ::DeleteObject(upd);
        return;
    }
    probe.area = CSize(ps.rcPaint.right - ps.rcPaint.left,
                       ps.rcPaint.bottom - ps.rcPaint.top);
    probe.Mark(0);

    CRect cl;
    GetClientRect(&cl);
    if (m_base.Reset(cl.Size()) && m_chrome.Reset(cl.Size()) &&
        m_out.Reset(cl.Size())) {
        // The DC is clipped to the update region; its bounding rect is the only
        // part of the cache that can be out of date.
        const CRect up(ps.rcPaint.left, ps.rcPaint.top, ps.rcPaint.right,
                       ps.rcPaint.bottom);
        const Gdiplus::Rect uc(up.left, up.top, up.Width(), up.Height());
        probe.base = m_baseDirty;
        if (m_baseDirty) {
            {
                Gdiplus::Graphics bg(m_base.gx.get());
                bg.SetClip(uc);
                DrawBase(bg);
            }
            m_baseDirty = false;
        }
        probe.Mark(1);
        // DWM composites a GDI window's surface whenever the vsync lands, and a
        // paint that hands the window its parts one at a time can be caught
        // between them: the still up, the dim and the chrome not yet, which is
        // the whole screen flashing for a frame. The base alone is a fifth of a
        // full repaint, so there is a real window for that. Everything below
        // therefore assembles the frame in m_out, and one blit carries it.
        ::SelectClipRgn(m_out.dc, haveUpd ? upd : nullptr);
        ::BitBlt(m_out.dc, up.left, up.top, up.Width(), up.Height(), m_base.dc,
                 up.left, up.top, SRCCOPY);
        probe.Mark(2);
        DrawDim(m_out, up);
        probe.Mark(3);
        // The ink of a shape still under the mouse is drawn here, on the frame
        // that already carries the still and the dim, rather than in the chrome
        // buffer below. See DrawLiveInk.
        DrawLiveInk(m_out.gx.get(), uc);

        // The chrome goes through a memory DIB and reaches the frame as a blend.
        // GDI+ charges ~0.35ms per call onto a window DC whatever it draws — the
        // frame, the two cards and the magnifier were 7ms of twenty-odd calls on
        // a small repaint and 28ms on a full-screen one — against 0.2ms for the
        // same calls here. Each element clears and registers its own rect as it
        // clips to it, so only the ground it can actually ink is blended.
        m_chromeInk.clear();
        {
            Gdiplus::Graphics g(m_chrome.gx.get());
            g.SetClip(uc);
            DrawChrome(g);
        }
        BLENDFUNCTION fn{};
        fn.BlendOp = AC_SRC_OVER;
        fn.SourceConstantAlpha = 0xFF;
        fn.AlphaFormat = AC_SRC_ALPHA;
        for (const CRect& r : m_chromeInk) {
            CRect q;
            if (q.IntersectRect(r, up) == FALSE || q.IsRectEmpty()) continue;
            ::AlphaBlend(m_out.dc, q.left, q.top, q.Width(), q.Height(),
                         m_chrome.dc, q.left, q.top, q.Width(), q.Height(), fn);
        }
        probe.Mark(7);
        // The window's own clip is the same region, so this writes exactly the
        // pixels that were asked for and nothing else — and it writes them once,
        // with the dim and the chrome already in them.
        ::SelectClipRgn(m_out.dc, nullptr);
        ::BitBlt(hdc, up.left, up.top, up.Width(), up.Height(), m_out.dc,
                 up.left, up.top, SRCCOPY);
    }
    ::EndPaint(GetSafeHwnd(), &ps);
    if (upd) ::DeleteObject(upd);
    probe.Mark(8);
}

void COverlayWnd::DrawBase(Gdiplus::Graphics& g) {
    const DesktopCapture& cap = m_session->Capture();
    // The still normally starts at this window's own corner; after 编辑 hands
    // back a stitched image it starts at the selection instead.
    const POINT off = m_session->CapOff();
    g.SetInterpolationMode(Gdiplus::InterpolationModeNearestNeighbor);
    g.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);

    Gdiplus::GraphicsState st = 0;
    bool clipped = false;
    if (m_session->LongShotEdit()) {
        // The frame is a viewport, not a window: the page stops at its edges and
        // what lies outside them is the desktop the page was made from, which is
        // how 参考UI图/编辑长图.png reads.
        if (Gdiplus::Bitmap* back = m_session->Backdrop()) {
            const POINT bo = m_session->BackdropOff();
            g.DrawImage(back, (int)bo.x, (int)bo.y, (int)back->GetWidth(),
                        (int)back->GetHeight());
        }
        const CRect f = m_session->Sel().Rect();
        st = g.Save();
        g.SetClip(Gdiplus::Rect(f.left, f.top, f.Width(), f.Height()),
                  Gdiplus::CombineModeIntersect);
        clipped = true;
    }
    g.DrawImage(cap.Image(), off.x, off.y, cap.Width(), cap.Height());

    // Half-pixel offsets are what make the 1:1 blit land exactly, but they shift
    // every rectangle and pen below by half a pixel, which puts the 2px frame
    // 2px outside the selection instead of straddling its edge.
    g.SetPixelOffsetMode(Gdiplus::PixelOffsetModeNone);

    // Not clipped to the selection: the selection is what changes most often,
    // and tying the cache to it would rebuild the screen on every drag. Ink
    // outside the selection still gets dimmed below, and the export crops it.
    // The 编辑 frame is the exception — it never moves, and the page has to stop
    // at its edges.
    m_session->Annos().DrawAll(g, SkipAnno());
    if (clipped) g.Restore(st);
}

// Each chrome element takes a clip of its own. The clip is also the rect its ink
// can reach, which is what lets ClipTo clear and register only that much of the
// buffer instead of the whole update region — 3.5M pixels of clear and blend to
// move ink that fits in two cards, a ring and a magnifier.
namespace {

// The pixels a rect really covers under PixelOffsetModeNone: pixel i is sampled
// at its own top-left corner, so the run is [ceil(X), ceil(X+W)). Rounding the
// same rect down for the clear and up for the blend — which is what this did
// first — leaves one column and one row of the previous frame's ink standing
// inside the rect that then gets blended: the fringe above and to the left of a
// moving shape.
CRect Covered(Gdiplus::RectF r) {
    return CRect((int)std::ceil(r.X), (int)std::ceil(r.Y),
                 (int)std::ceil(r.X + r.Width), (int)std::ceil(r.Y + r.Height));
}

// Filling an integer rect with integer coordinates covers exactly those pixels,
// which is what makes the clear and the blend agree pixel for pixel.
void FillPixels(Gdiplus::Graphics& g, const CRect& q, const Gdiplus::Brush& b) {
    g.FillRectangle(&b, (Gdiplus::REAL)q.left, (Gdiplus::REAL)q.top,
                    (Gdiplus::REAL)q.Width(), (Gdiplus::REAL)q.Height());
}

// The current clip as pixels. Every clip here is a rectangle, so its bounds are
// the clip; false when the clip is unbounded, which reports a sentinel too wide
// to fit an int.
bool ClipPixels(Gdiplus::Graphics& g, CRect* out) {
    Gdiplus::Region rgn;
    Gdiplus::RectF b;
    if (g.GetClip(&rgn) != Gdiplus::Ok) return false;
    if (rgn.GetBounds(&b, &g) != Gdiplus::Ok) return false;
    if (b.X < -1e7f || b.Y < -1e7f || b.Width > 1e7f || b.Height > 1e7f)
        return false;
    *out = Covered(b);
    return true;
}

// Where an annotation can put ink down, plus the ring of selection handles drawn
// around it. InkBBox rather than BBox: an anti-aliased stroke feathers about a
// pixel past the geometric outline, and ink the clear misses is ink that stays.
Gdiplus::RectF InkedBox(const annot::Annotation* a, Gdiplus::REAL pad) {
    if (!a) return Gdiplus::RectF(0, 0, 0, 0);
    const Gdiplus::RectF b = a->InkBBox();
    return Gdiplus::RectF(b.X - pad, b.Y - pad, b.Width + 2 * pad,
                          b.Height + 2 * pad);
}

class ClipTo {
public:
    // The rect is where the element can put ink, so it is both the clip and the
    // only part of the chrome buffer the blend has to carry. Clearing and
    // blending the whole update region instead costs 5.5ms a frame to move ink
    // that fits in two cards, a ring and a magnifier: the region is 3.5M pixels
    // and the chrome's own ink is well under a tenth of it.
    ClipTo(Gdiplus::Graphics& g, const Gdiplus::RectF& r, std::vector<CRect>* ink)
        : m_g(g), m_state(g.Save()) {
        g.SetClip(r, Gdiplus::CombineModeIntersect);
        if (!ink) return;
        // The buffer still holds this rect's ink from whenever it was last
        // drawn, and anything outside the element's new position would show
        // through as a ghost. SourceCopy with a transparent colour zeroes alpha
        // along with the colour, which is what drops the untouched pixels of the
        // rect out of the blend.
        //
        // What gets cleared, what gets blended and what the clip lets the
        // element ink have to be the same set of pixels: the clip is read back
        // and intersected here so a rect that reaches past it cannot carry
        // stale ink from the part the fill never reached.
        CRect q = Covered(r);
        CRect clip;
        if (ClipPixels(g, &clip)) q.IntersectRect(&q, &clip);
        if (q.IsRectEmpty()) return;

        const Gdiplus::CompositingMode cm = g.GetCompositingMode();
        g.SetCompositingMode(Gdiplus::CompositingModeSourceCopy);
        Gdiplus::SolidBrush clear(0x00000000);
        FillPixels(g, q, clear);
        g.SetCompositingMode(cm);
        ink->push_back(q);
    }
    ~ClipTo() { m_g.Restore(m_state); }

private:
    Gdiplus::Graphics& m_g;
    Gdiplus::GraphicsState m_state;
};

// For an element whose ink is a band rather than a box: the selection frame. Its
// clip has to be the box the band fits in, but the clear and the blend are the
// four strips themselves. Clearing the box wipes the annotations drawn inside it
// a moment earlier, and blending the box drags their stale ink out of the buffer
// wherever they no longer are — which is how a dragged shape loses its selection
// ring, how a shape being drawn stays invisible until the button comes up, and
// how a ghost reappears at the spot a shape was dragged away from.
class ClipBand {
public:
    ClipBand(Gdiplus::Graphics& g, const Gdiplus::RectF& outer,
             const Gdiplus::RectF& inner, std::vector<CRect>* ink)
        : m_g(g), m_state(g.Save()) {
        g.SetClip(outer, Gdiplus::CombineModeIntersect);
        const float ol = outer.X, ot = outer.Y;
        const float orr = outer.X + outer.Width, ob = outer.Y + outer.Height;
        const float il = inner.X, it = inner.Y;
        const float ir = inner.X + inner.Width, ib = inner.Y + inner.Height;
        const Gdiplus::RectF strip[4] = {
            Gdiplus::RectF(ol, ot, orr - ol, it - ot),
            Gdiplus::RectF(ol, ib, orr - ol, ob - ib),
            Gdiplus::RectF(ol, it, il - ol, ib - it),
            Gdiplus::RectF(ir, it, orr - ir, ib - it),
        };
        CRect clip;
        const bool bounded = ClipPixels(g, &clip);
        const Gdiplus::CompositingMode cm = g.GetCompositingMode();
        g.SetCompositingMode(Gdiplus::CompositingModeSourceCopy);
        Gdiplus::SolidBrush clear(0x00000000);
        for (const Gdiplus::RectF& q : strip) {
            if (q.Width <= 0.0f || q.Height <= 0.0f) continue;
            CRect px = Covered(q);
            if (bounded) px.IntersectRect(&px, &clip);
            if (px.IsRectEmpty()) continue;
            FillPixels(g, px, clear);
            if (ink) ink->push_back(px);
        }
        g.SetCompositingMode(cm);
    }
    ~ClipBand() { m_g.Restore(m_state); }

private:
    Gdiplus::Graphics& m_g;
    Gdiplus::GraphicsState m_state;
};
}  // namespace

// The ink of a shape still under the mouse goes onto the assembled frame, not
// into the chrome buffer, and the reason is the ground. GDI+ resolves an
// anti-aliased edge against the colour already on the surface and writes the
// result premultiplied, so over the still a pixel at coverage a reads
// ink*a + ground*(1-a) — which is what a soft edge means. Over the chrome
// buffer's cleared 0x00000000 it reads ink*a with the colour pulled toward black
// and the alpha multiplied in a second time, so a partial pixel below the dim's
// own 0.4 comes out darker than the ground beside it: the dark fringe a dragged
// arrow or ellipse carried, and why the committed one, which DrawBase blends
// over the still, looked right. Only the shapes that ask for smoothing can show
// it, which is why the rectangle and the 马赛克 band never seemed wrong.
void COverlayWnd::DrawLiveInk(Gdiplus::Bitmap* out, const Gdiplus::Rect& uc) {
    annot::Annotation* moving = MovingAnno();
    if (!moving && !m_pending) return;

    Gdiplus::Graphics g(out);
    g.SetClip(uc);
    g.SetInterpolationMode(Gdiplus::InterpolationModeNearestNeighbor);
    g.SetPixelOffsetMode(Gdiplus::PixelOffsetModeNone);
    // The same clip DrawChrome gives the ink: annotations live in the still's
    // space, and only the selection is shown.
    const RECT s = m_session->Sel().Rect();
    g.SetClip(Gdiplus::RectF((Gdiplus::REAL)s.left, (Gdiplus::REAL)s.top,
                             (Gdiplus::REAL)(s.right - s.left),
                             (Gdiplus::REAL)(s.bottom - s.top)),
              Gdiplus::CombineModeIntersect);
    // The label being typed into draws no ink of its own while the edit is open:
    // the input control sits on its box and shows the text.
    if (moving && moving != m_session->EditingAnno()) moving->Draw(g);
    if (m_pending) m_pending->Draw(g);
}

void COverlayWnd::DrawChrome(Gdiplus::Graphics& g) {
    g.SetInterpolationMode(Gdiplus::InterpolationModeNearestNeighbor);
    g.SetPixelOffsetMode(Gdiplus::PixelOffsetModeNone);

    // The dim went on with GDI before this Graphics existed; everything from
    // here is GDI+.

    // Annotations live in the same space as the still, so they need only a clip
    // to the selection — and they sit above the dim, as in 矩形-鼠标拖动画矩形.png.
    RECT s = m_session->Sel().Rect();
    const Gdiplus::GraphicsState gs = g.Save();
    g.SetClip(Gdiplus::RectF((Gdiplus::REAL)s.left, (Gdiplus::REAL)s.top,
                             (Gdiplus::REAL)(s.right - s.left),
                             (Gdiplus::REAL)(s.bottom - s.top)));
    const Gdiplus::REAL hpad = (Gdiplus::REAL)(AnnoHandleRadius() + 3);
    // The shape being dragged and the ring that marks it selected are the same
    // annotation, and a shape still being drawn may sit out beside them. They
    // share one clip: ClipTo clears the rect it clips, so clipping each on its
    // own would have the ring's clear drop the shape it belongs to.
    annot::Annotation* moving = MovingAnno();
    annot::Annotation* sel = m_session->Selected();
    // The ring's ground only: both shapes' ink is DrawLiveInk's now. A shape
    // still being drawn has no ring and no selection, so it leaves this empty and
    // the whole clip below is skipped — which is right, since it has nothing left
    // in here to blend.
    annot::Annotation* inked[2] = { moving, sel };
    float il = 0, it = 0, ir = 0, ib = 0;
    bool any = false;
    for (annot::Annotation* a : inked) {
        if (!a) continue;
        const Gdiplus::RectF q = InkedBox(a, hpad);
        if (!any) {
            il = q.X; it = q.Y; ir = q.X + q.Width; ib = q.Y + q.Height;
            any = true;
            continue;
        }
        il = std::min(il, q.X);
        it = std::min(it, q.Y);
        ir = std::max(ir, q.X + q.Width);
        ib = std::max(ib, q.Y + q.Height);
    }
    if (any) {
        ClipTo c(g, Gdiplus::RectF(il, it, ir - il, ib - it), &m_chromeInk);
        // The ink is already on m_out under here, and the blend leaves those
        // pixels alone wherever this buffer is still transparent — so the frame
        // and the ring land on top of the ink rather than replacing it, which is
        // the order the committed shape has too.
        // Under the markers, so a corner marker reads as one square rather than
        // as a square with a line run through it.
        DrawEditFrame(g);
        if (sel)
            annot::DrawSelection(g, *sel, (Gdiplus::REAL)AnnoHandleRadius(),
                                 HasMarkers(*sel));
    }
    g.Restore(gs);
    ProbeMark(4);

    DrawSelectionFrame(g);
    DrawHoverFrame(g);
    // The stitched tail hangs beside the hole, which is the one part of the
    // selection area this window still paints. It has no rect of its own to
    // offer, so 长截图 keeps paying for the whole region.
    if (InLongShot()) {
        // The preview's own box, not the whole client. Blending the whole client
        // drags back every card the chrome buffer has ever held — the buffer is
        // only cleared where a frame clips to it — and that is the trail of
        // magnifiers and 提示 cards 长截图 left stacked beside the hole.
        CRect pr = m_session->LongShotPreviewRect();
        if (!pr.IsRectEmpty()) {
            pr.InflateRect(2, 2);  // the ring is drawn outside the image
            ClipTo clip(g, Gdiplus::RectF((Gdiplus::REAL)pr.left, (Gdiplus::REAL)pr.top,
                                          (Gdiplus::REAL)pr.Width(),
                                          (Gdiplus::REAL)pr.Height()),
                        &m_chromeInk);
            m_session->PaintLongShot(g);
        }
    }
    DrawSizeLabel(g);
    DrawFontDropdown(g);
    ProbeMark(5);
    DrawScrollBar(g);
    DrawLoupe(g);
    ProbeMark(6);
}

// Blending opaque black at alpha a over the ground leaves ground*(255-a)/255,
// which is a scale of each colour byte. Doing that with AlphaBlend would be the
// obvious move and was, until the frame had to be assembled in memory: GDI
// accelerates the blend onto a window DC and not onto a DIB section, and the
// same full-screen dim costs 0.1ms on one against 40ms on the other. So it runs
// over the bits here instead. The alpha byte is left alone.
static void DimBits(void* base, int stride, const CRect& r, int a) {
    const unsigned k = ((255 - a) << 16) / 255 + 1;  // v*k>>16 == v*(255-a)/255
    const __m128i mk = _mm_set1_epi16((short)k);
    const __m128i zero = _mm_setzero_si128();
    const __m128i alpha = _mm_set1_epi32((int)0xFF000000);

    BYTE* row = (BYTE*)base + (size_t)r.top * stride;
    for (int y = r.top; y < r.bottom; ++y, row += stride) {
        BYTE* p = row + (size_t)r.left * 4;
        for (int n = r.Width(); n >= 4; n -= 4, p += 16) {
            const __m128i src = _mm_loadu_si128((const __m128i*)p);
            const __m128i lo = _mm_mulhi_epu16(_mm_unpacklo_epi8(src, zero), mk);
            const __m128i hi = _mm_mulhi_epu16(_mm_unpackhi_epi8(src, zero), mk);
            const __m128i dim = _mm_packus_epi16(lo, hi);
            _mm_storeu_si128((__m128i*)p, _mm_or_si128(_mm_andnot_si128(alpha, dim),
                                                       _mm_and_si128(alpha, src)));
        }
        for (int n = r.Width() & 3; n > 0; --n, p += 4)
            for (int c = 0; c < 3; ++c) p[c] = (BYTE)((p[c] * k) >> 16);
    }
}

void COverlayWnd::DrawDim(const DibCanvas& out, const CRect& lim) {
    RECT s = m_session->Sel().Rect();
    CRect cl;
    GetClientRect(&cl);

    CRect strips[4];
    int n = 0;
    // The default selection is the whole screen, so the four strips below all
    // collapse and the summoned screen would look undimmed until the first
    // drag. Until the user has picked something the dim covers the selection
    // too, so the hotkey visibly darkens the desktop at once.
    if (!InLongShot() && m_session->Sel().IsDefault()) {
        strips[n++] = cl;
    } else {
        if (s.top > cl.top) strips[n++] = CRect(cl.left, cl.top, cl.right, s.top);
        if (s.bottom < cl.bottom)
            strips[n++] = CRect(cl.left, s.bottom, cl.right, cl.bottom);
        if (s.left > cl.left) strips[n++] = CRect(cl.left, s.top, s.left, s.bottom);
        if (s.right < cl.right)
            strips[n++] = CRect(s.right, s.top, cl.right, s.bottom);
    }

    // Clipped to the update rect rather than to the region: the parts of a strip
    // outside it are read by the blit out but never reach the window, so writing
    // them costs a little time and nothing else.
    for (int i = 0; i < n; ++i) {
        CRect q;
        if (q.IntersectRect(strips[i], lim) == FALSE) continue;
        DimBits(out.bits, out.size.cx * 4, q, kDim.GetA());
    }
}

annot::Annotation* COverlayWnd::MovingAnno() const {
    return (m_mode == Mode::MoveAnno || m_mode == Mode::DragHandle) ? m_anno
                                                                    : nullptr;
}

annot::Annotation* COverlayWnd::SkipAnno() const {
    return MovingAnno() ? MovingAnno() : m_session->EditingAnno();
}

std::unique_ptr<Gdiplus::Font> COverlayWnd::UiFont(int px) const {
    Gdiplus::FontFamily family(kFontFace);
    return std::make_unique<Gdiplus::Font>(
        &family, (Gdiplus::REAL)px, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
}

// ------------------------------------------------------------- dirty regions

CRect COverlayWnd::AnnoRect(const annot::Annotation* a) {
    if (!a) return CRect(0, 0, 0, 0);
    // InkBBox, not BBox: over-invalidating costs a few more pixels of repaint,
    // while missing the anti-aliased fringe or the outer half of a pen leaves
    // them on screen.
    const Gdiplus::RectF b = a->InkBBox();
    return CRect((int)std::floor(b.X), (int)std::floor(b.Y),
                 (int)std::ceil(b.X + b.Width), (int)std::ceil(b.Y + b.Height));
}

void COverlayWnd::InvalidatePart(const CRect& r) {
    CRect cl, w(r);
    GetClientRect(&cl);
    if (w.IntersectRect(w, cl) == FALSE || w.IsRectEmpty()) return;
    InvalidateRect(&w, FALSE);
}

// The ring of pixels just inside and outside the edge of `r`. Filling the whole
// box instead charges its interior to every frame: a 30px step of a 2000x1500
// selection unioned to 3.6M pixels of blit, dim and blend per mouse move, which
// is what left the frame two moves behind the cursor and made it flicker.
void COverlayWnd::InvalidateRing(const CRect& r, int pad) {
    InvalidatePart(CRect(r.left - pad, r.top - pad, r.right + pad, r.top + pad));
    InvalidatePart(CRect(r.left - pad, r.bottom - pad, r.right + pad,
                         r.bottom + pad));
    InvalidatePart(CRect(r.left - pad, r.top + pad, r.left + pad, r.bottom - pad));
    InvalidatePart(CRect(r.right - pad, r.top + pad, r.right + pad,
                         r.bottom - pad));
}

// The part of `a` that `b` does not cover, as up to four strips. Anything that
// inked in there has to be painted back, and a dim hole that `a` cut but `b` no
// longer does has to go dark again.
void COverlayWnd::InvalidateOutside(const CRect& a, const CRect& b) {
    InvalidatePart(CRect(a.left, a.top, a.right, std::min(a.bottom, b.top)));
    InvalidatePart(CRect(a.left, std::max(a.top, b.bottom), a.right, a.bottom));
    const int t = std::max(a.top, b.top), btm = std::min(a.bottom, b.bottom);
    InvalidatePart(CRect(a.left, t, std::min(a.right, b.left), btm));
    InvalidatePart(CRect(std::max(a.left, b.right), t, a.right, btm));
}

void COverlayWnd::InvalidateSelChange(const RECT& before) {
    const CRect was(before);
    const CRect now(m_session->Sel().Rect());
    // The 2px frame and the squares on its edges and corners, and the size card
    // that hangs 24px above the top edge — all of them within this ring.
    const int pad = Dpi::S(GetSafeHwnd(), 26);
    InvalidateRing(was, pad);
    InvalidateRing(now, pad);
    // The hole the selection cuts in the dim: only the strip where it opened or
    // closed changed brightness.
    InvalidateOutside(was, now);
    InvalidateOutside(now, was);
}

void COverlayWnd::InvalidateAnnoChange(const annot::Annotation* a,
                                       const CRect& before) {
    const CRect now = AnnoRect(a);
    // Pen width and the handle rings, which the bounding box does not cover.
    const int pad = Dpi::S(GetSafeHwnd(), 12);
    // A shape's ink can be anywhere inside its box, not just on its edge: an
    // ellipse's curve sweeps the interior, an arrow's shaft is a diagonal across
    // it, a pen stroke is wherever the hand went. So the ground a change can
    // have altered is both boxes entire. Rings plus the strips outside them —
    // what the selection's band-shaped ink needs — leave each box's interior
    // unblended, which is how an arrow loses its head and a curve its middle
    // while the button is down, and how a dragged ellipse smears along the path.
    CRect dirty(before);
    dirty.UnionRect(dirty, now);
    dirty.InflateRect(pad, pad);
    InvalidatePart(dirty);
}

// 默认选择全屏,周围有蓝框.png: the magnifier rides with the cursor while no tool
// is armed, and hides under the bars — they are child windows, so their own
// mouse moves never reach this window.
bool COverlayWnd::LoupeCursor(CPoint* at) const {
    if (InLongShot()) return false;
    if (m_session->ActiveTool() != tb::Id::None || m_session->Editor()) return false;
    // The card is there to help pick where the 选区 starts and to read a colour
    // off the still. Once the user has dragged one out it has done its job, and
    // while a button is down it follows the drag across the region being drawn.
    if (m_selPicked || m_mode != Mode::Idle) return false;

    CPoint p;
    if (!::GetCursorPos(&p)) return false;
    ::ScreenToClient(GetSafeHwnd(), &p);
    CRect cl;
    GetClientRect(&cl);
    if (!cl.PtInRect(p)) return false;

    CRect r;
    m_toolbar.GetWindowRect(&r);
    ScreenToClient(&r);
    if (r.PtInRect(p)) return false;
    if (m_propbar.Visible()) {
        m_propbar.GetWindowRect(&r);
        ScreenToClient(&r);
        if (r.PtInRect(p)) return false;
    }

    *at = p;
    return true;
}

void COverlayWnd::DrawLoupe(Gdiplus::Graphics& g) {
    CPoint at;
    m_loupeShown = LoupeCursor(&at);
    if (!m_loupeShown) {
        m_loupeRect.SetRectEmpty();
        return;
    }
    CRect cl;
    GetClientRect(&cl);
    const RECT card = loupe::CardRect(GetSafeHwnd(), at, cl);
    m_loupeRect = CRect(card.left, card.top, card.right, card.bottom);
    if (!m_loupeFont)
        m_loupeFont = UiFont(Dpi::S(GetSafeHwnd(), loupe::kInfoFont));
    if (m_loupeFont) {
        ClipTo clip(g, Gdiplus::RectF((Gdiplus::REAL)m_loupeRect.left - 1,
                                      (Gdiplus::REAL)m_loupeRect.top - 1,
                                      (Gdiplus::REAL)(m_loupeRect.Width() + 2),
                                      (Gdiplus::REAL)(m_loupeRect.Height() + 2)),
                           &m_chromeInk);
        loupe::Draw(*m_session, at, g, cl, *m_loupeFont);
    }
}

void COverlayWnd::InvalidateLoupe() {
    CPoint at;
    const bool show = LoupeCursor(&at);

    // Both the card's old place, which the blit has to put the scene back over,
    // and its new one.
    CRect dirty = m_loupeRect;
    if (show) {
        CRect cl;
        GetClientRect(&cl);
        const RECT card = loupe::CardRect(GetSafeHwnd(), at, cl);
        dirty.UnionRect(dirty, CRect(card.left, card.top, card.right, card.bottom));
    }
    // Nothing was drawn and nothing is: inflating the empty rect would give a
    // 2x2 at the client origin, which every selection drag would then carry as
    // the corner of its update region's bounding rect.
    if (dirty.IsRectEmpty()) return;
    dirty.InflateRect(2, 2);
    InvalidatePart(dirty);
}

void COverlayWnd::CursorMoved() {
    CPoint at;
    if (!LoupeCursor(&at) && !m_loupeShown) return;
    InvalidateLoupe();
}

void COverlayWnd::TipChanged(const CPoint* anchor) {
    const CaptureSession::TipCard* tip = anchor ? m_session->Tip() : nullptr;
    if (!tip) {
        if (m_tipWnd) m_tipWnd->Hide();
        return;
    }
    // Made on the first hover rather than at Create: a top-level that exists all
    // the time is one more window every probe of the screen has to step over.
    if (!m_tipWnd) {
        m_tipWnd = std::make_unique<CTipCardWnd>();
        if (!m_tipWnd->Create()) {
            m_tipWnd.reset();
            return;
        }
    }

    CPoint at = *anchor;
    ::ClientToScreen(GetSafeHwnd(), &at);
    CRect limit;
    GetClientRect(&limit);
    ::MapWindowRect(GetSafeHwnd(), HWND_DESKTOP, &limit);
    m_tipWnd->Show(tip->text, at, limit);
}

// 文字-点击位置-输入时红色文本框.png: the label's box carries a red frame 2px
// outside it, in the selected state and in the editing state alike — the frame is
// what says the text is a box, and the eight square markers on it are what says
// whether it can be resized. Called from inside the selection chrome's clip,
// which clears this same rect: a ClipTo of its own would drop the markers.
void COverlayWnd::DrawEditFrame(Gdiplus::Graphics& g) {
    annot::ShapeText* t = FrameText();
    if (!t) return;

    const Gdiplus::RectF b = t->Box();
    CRect r((int)b.X, (int)b.Y, (int)std::ceil(b.X + b.Width),
            (int)std::ceil(b.Y + b.Height));
    r.InflateRect(Dpi::S(GetSafeHwnd(), 2), Dpi::S(GetSafeHwnd(), 2));

    Gdiplus::Pen pen(kEditFrame, 1.0f);
    g.DrawRectangle(&pen, (Gdiplus::REAL)r.left + 0.5f, (Gdiplus::REAL)r.top + 0.5f,
                    (Gdiplus::REAL)r.Width() - 1.0f, (Gdiplus::REAL)r.Height() - 1.0f);
}

// 文字-字体大小.png: a flat white card under the 字号 box, the current size
// filled blue with white digits.
void COverlayWnd::DrawFontDropdown(Gdiplus::Graphics& g) {
    const CRect* d = m_session->FontDropdown();
    if (!d) return;
    ClipTo drop(g, Gdiplus::RectF((Gdiplus::REAL)d->left - 1,
                                  (Gdiplus::REAL)d->top - 1,
                                  (Gdiplus::REAL)(d->Width() + 2),
                                  (Gdiplus::REAL)(d->Height() + 2)),
                       &m_chromeInk);

    const HWND hwnd = GetSafeHwnd();
    const int row = Dpi::S(hwnd, tb::kFontRow);
    const int n = tb::kFontRowCount;
    const int cur = tb::FontRowForSize(m_session->Style().fontSize);

    Gdiplus::SolidBrush back(Gdiplus::Color(0xFFFFFFFF));
    g.FillRectangle(&back, (Gdiplus::REAL)d->left, (Gdiplus::REAL)d->top,
                    (Gdiplus::REAL)d->Width(), (Gdiplus::REAL)d->Height());

    if (!m_dropFont) m_dropFont = UiFont(Dpi::S(hwnd, 13));
    if (!m_dropFont) return;
    g.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
    Gdiplus::StringFormat fmt;
    fmt.SetAlignment(Gdiplus::StringAlignmentNear);
    fmt.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    const int pad = Dpi::S(hwnd, 8);

    for (int i = 0; i < n; ++i) {
        const Gdiplus::REAL y = (Gdiplus::REAL)(d->top + i * row);
        const bool on = i == cur;
        if (on) {
            Gdiplus::SolidBrush hi(tb::kAccent);
            g.FillRectangle(&hi, (Gdiplus::REAL)d->left, y,
                            (Gdiplus::REAL)d->Width(), (Gdiplus::REAL)row);
        }
        CString s;
        s.Format(L"%d", tb::FontSizeForRow(i));
        Gdiplus::SolidBrush fg(on ? Gdiplus::Color(0xFFFFFFFF) : tb::kInk);
        g.DrawString(s, -1, m_dropFont.get(),
                     Gdiplus::RectF((Gdiplus::REAL)(d->left + pad), y,
                                    (Gdiplus::REAL)d->Width() - 2 * pad,
                                    (Gdiplus::REAL)row),
                     &fmt, &fg);
    }

    Gdiplus::Pen edge(kDropEdge, 1.0f);
    g.DrawRectangle(&edge, (Gdiplus::REAL)d->left + 0.5f, (Gdiplus::REAL)d->top + 0.5f,
                    (Gdiplus::REAL)d->Width() - 1.0f, (Gdiplus::REAL)d->Height() - 1.0f);
}

int COverlayWnd::HitFontRow(CPoint pt) const {
    const CRect* d = m_session->FontDropdown();
    if (!d || !::PtInRect(*d, pt)) return -1;
    const int i = (pt.y - d->top) / Dpi::S(GetSafeHwnd(), tb::kFontRow);
    return i >= 0 && i < tb::kFontRowCount ? i : -1;
}

// The pre-selection belongs to the gesture of choosing a region and to nothing
// else. Once a region is picked, a shape is being drawn or dragged, the 长截图
// hole is open, or a popup is up, a frame around some other window would be
// commenting on a decision already made.
bool COverlayWnd::HoverActive() const {
    if (m_mode != Mode::Idle || m_selPicked || InLongShot()) return false;
    if (m_session->LongShotEdit() || m_session->Editor() ||
        m_session->FontDropdown())
        return false;
    // IsDefault() is the same fact m_selPicked records, from the other side; both
    // have to hold or a region set from outside (a restored one, say) gets a
    // frame chasing it.
    return m_session->Sel().IsDefault();
}

void COverlayWnd::UpdateHover() {
    CRect next;
    POINT cur{};
    CRect cl;
    GetClientRect(&cl);
    if (HoverActive() && ::GetCursorPos(&cur)) {
        // GetCursorPos out of a PerMonitorV2 process already gives physical
        // virtual-screen pixels, which is the space WindowPick both asks and
        // answers in; no scale factor belongs anywhere here.
        CPoint client(cur);
        ScreenToClient(&client);
        if (cl.PtInRect(client)) {
            CRect r = winpick::TopWindowUnder(cur);
            if (!r.IsRectEmpty()) ScreenToClient(&r);
            next = r;
        }
    }
    if (EqualRect(&next, &m_hover)) return;
    const CRect was = m_hover;
    m_hover = next;
    // The frame is 2px on the window's edge, so only the two rings it could have
    // changed need repainting — never the interior, which is the mistake that
    // made selection drags two frames behind the cursor.
    const int hs = Dpi::S(GetSafeHwnd(), 8);
    if (!was.IsRectEmpty()) InvalidateRing(was, hs);
    if (!m_hover.IsRectEmpty()) InvalidateRing(m_hover, hs);
}

void COverlayWnd::DrawHoverFrame(Gdiplus::Graphics& g) {
    if (!HoverActive() || m_hover.IsRectEmpty()) return;
    const RECT s = m_hover;
    const int w = s.right - s.left, h = s.bottom - s.top;
    if (w <= 0 || h <= 0) return;

    // The same band the 选区's frame damages, and for the same reason: the 2px
    // pen straddles the edge.
    const int hs = Dpi::S(GetSafeHwnd(), 7);
    ClipBand band(g, Gdiplus::RectF((Gdiplus::REAL)(s.left - hs),
                                    (Gdiplus::REAL)(s.top - hs),
                                    (Gdiplus::REAL)(w + 2 * hs),
                                    (Gdiplus::REAL)(h + 2 * hs)),
                  Gdiplus::RectF((Gdiplus::REAL)(s.left + 1),
                                 (Gdiplus::REAL)(s.top + 1),
                                 (Gdiplus::REAL)(w - 2),
                                 (Gdiplus::REAL)(h - 2)),
                  &m_chromeInk);
    // The blue only — no squares on the edges and corners. There is nothing to
    // drag yet: the frame is a promise about the click, not a set of grips.
    Gdiplus::Pen pen(kFrame, 2.0f);
    g.DrawRectangle(&pen, (Gdiplus::REAL)s.left, (Gdiplus::REAL)s.top,
                    (Gdiplus::REAL)w, (Gdiplus::REAL)h);
}

void COverlayWnd::DrawSelectionFrame(Gdiplus::Graphics& g) {
    RECT s = m_session->Sel().Rect();
    int w = s.right - s.left;
    int h = s.bottom - s.top;
    if (w <= 0 || h <= 0) return;

    int hs = Dpi::S(GetSafeHwnd(), 7);
    if ((hs & 1) == 0) ++hs;
    const int off = hs / 2;  // odd size + integer offset centres the square
    // The 2px pen straddles the edge and the handle squares stick out by off, so
    // the frame's own damage is a band this wide around the selection.
    ClipBand band(g, Gdiplus::RectF((Gdiplus::REAL)(s.left - hs),
                                    (Gdiplus::REAL)(s.top - hs),
                                    (Gdiplus::REAL)(w + 2 * hs),
                                    (Gdiplus::REAL)(h + 2 * hs)),
                  Gdiplus::RectF((Gdiplus::REAL)(s.left + off),
                                 (Gdiplus::REAL)(s.top + off),
                                 (Gdiplus::REAL)(w - 2 * off),
                                 (Gdiplus::REAL)(h - 2 * off)),
                  &m_chromeInk);

    if (InLongShot()) {
        // The hole is not part of this window, so a pen straddling its edge
        // would be clipped away: fill four strips just outside it instead.
        // 长截图.png has no handles either — there is nothing to drag.
        const int t = Dpi::S(GetSafeHwnd(), 2);
        Gdiplus::SolidBrush ink(kFrame);
        g.FillRectangle(&ink, (Gdiplus::REAL)(s.left - t), (Gdiplus::REAL)(s.top - t),
                        (Gdiplus::REAL)(w + 2 * t), (Gdiplus::REAL)t);
        g.FillRectangle(&ink, (Gdiplus::REAL)(s.left - t), (Gdiplus::REAL)s.bottom,
                        (Gdiplus::REAL)(w + 2 * t), (Gdiplus::REAL)t);
        g.FillRectangle(&ink, (Gdiplus::REAL)(s.left - t), (Gdiplus::REAL)(s.top - t),
                        (Gdiplus::REAL)t, (Gdiplus::REAL)(h + 2 * t));
        g.FillRectangle(&ink, (Gdiplus::REAL)s.right, (Gdiplus::REAL)(s.top - t),
                        (Gdiplus::REAL)t, (Gdiplus::REAL)(h + 2 * t));
        return;
    }

    Gdiplus::Pen pen(kFrame, 2.0f);
    g.DrawRectangle(&pen, (Gdiplus::REAL)s.left, (Gdiplus::REAL)s.top,
                    (Gdiplus::REAL)w, (Gdiplus::REAL)h);

    // The 编辑 frame is a viewport, not a region: it is fixed, so the grips would
    // promise a resize that cannot happen.
    if (m_session->LongShotEdit()) return;

    POINT pts[8] = {
        { s.left, s.top },
        { (s.left + s.right) / 2, s.top },
        { s.right, s.top },
        { s.right, (s.top + s.bottom) / 2 },
        { s.right, s.bottom },
        { (s.left + s.right) / 2, s.bottom },
        { s.left, s.bottom },
        { s.left, (s.top + s.bottom) / 2 },
    };
    Gdiplus::SolidBrush fill(kFrame);
    for (const POINT& p : pts)
        g.FillRectangle(&fill, (Gdiplus::REAL)(p.x - off), (Gdiplus::REAL)(p.y - off),
                        (Gdiplus::REAL)hs, (Gdiplus::REAL)hs);
}

void COverlayWnd::DrawSizeLabel(Gdiplus::Graphics& g) {
    const SelectionModel& sel = m_session->Sel();
    CString text;
    // 长截图滚动合成.png counts the whole stitched document, not the hole.
    if (!m_session->LongShotSizeText(text))
        text.Format(L"%d x %d", sel.Width(), sel.Height());

    if (!m_labelFont)
        m_labelFont = UiFont((int)(-Dpi::FontHeightForPoint(GetSafeHwnd(), 9)));
    if (!m_labelFont) return;
    g.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);

    // The digits change with every pixel of a drag and measuring them is the
    // expensive half of this card, so it is keyed on the text.
    if (text != m_labelText) {
        Gdiplus::RectF measured;
        g.MeasureString(text.GetString(), text.GetLength(), m_labelFont.get(),
                        Gdiplus::PointF(0, 0), &measured);
        m_labelText = text;
        m_labelSize = CSize((int)std::ceil(measured.Width),
                            (int)std::ceil(measured.Height));
    }

    Gdiplus::REAL pad = (Gdiplus::REAL)Dpi::S(GetSafeHwnd(), 4);
    Gdiplus::REAL bw = (Gdiplus::REAL)m_labelSize.cx + pad * 2;
    Gdiplus::REAL bh = (Gdiplus::REAL)m_labelSize.cy + pad;
    Gdiplus::REAL bx = (Gdiplus::REAL)sel.Rect().left;
    Gdiplus::REAL by = (Gdiplus::REAL)sel.Rect().top - bh - 2;

    CRect cl;
    GetClientRect(&cl);
    if (by < cl.top) by = (Gdiplus::REAL)sel.Rect().top + 2;

    // The card is a small fixed rect, and the caret beside it only exists in
    // 长截图, so the clip grows only when one is actually drawn.
    Gdiplus::REAL cw = bw, ch = bh, ct = by;
    if (InLongShot()) {
        const int m = Dpi::S(GetSafeHwnd(), 12);
        cw += (Gdiplus::REAL)m * 2;
        ch += (Gdiplus::REAL)m * 2;
        ct -= (Gdiplus::REAL)m;
    }
    ClipTo card(g, Gdiplus::RectF(bx, ct, cw, ch), &m_chromeInk);

    Gdiplus::SolidBrush back(kLabelBack);
    g.FillRectangle(&back, bx, by, bw, bh);
    Gdiplus::SolidBrush fg(kLabelText);
    g.DrawString(text.GetString(), text.GetLength(), m_labelFont.get(),
                 Gdiplus::PointF(bx + pad, by + pad / 2), &fg);

    if (InLongShot())
        DrawLongShotCaret(g, CRect((int)bx, (int)by, (int)(bx + bw), (int)(by + bh)));
}

// 长截图-点击后.png: a small dark chevron above the card's right edge folds the
// stitched preview away.
void COverlayWnd::DrawLongShotCaret(Gdiplus::Graphics& g, const CRect& card) {
    const HWND hwnd = GetSafeHwnd();
    const int cx = card.right + Dpi::S(hwnd, 12);
    const int cy = card.top - Dpi::S(hwnd, 5);
    const int a = Dpi::S(hwnd, 4), b = Dpi::S(hwnd, 3);

    g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    Gdiplus::Pen pen(kCaretInk, (Gdiplus::REAL)Dpi::S(hwnd, 2));
    pen.SetStartCap(Gdiplus::LineCapRound);
    pen.SetEndCap(Gdiplus::LineCapRound);
    pen.SetLineJoin(Gdiplus::LineJoinRound);
    const Gdiplus::PointF pts[3] = {
        Gdiplus::PointF((Gdiplus::REAL)(cx - a), (Gdiplus::REAL)(cy + b)),
        Gdiplus::PointF((Gdiplus::REAL)cx, (Gdiplus::REAL)(cy - b)),
        Gdiplus::PointF((Gdiplus::REAL)(cx + a), (Gdiplus::REAL)(cy + b)),
    };
    g.DrawLines(&pen, pts, 3);
    g.SetSmoothingMode(Gdiplus::SmoothingModeDefault);

    const int hit = Dpi::S(hwnd, 8);
    m_session->SetLongShotCaret(CRect(cx - hit, cy - hit, cx + hit, cy + hit));
}

// 参考UI图/编辑长图.png: the page is taller than the frame that shows it, so a
// light track with a grey thumb just inside the frame's right edge says how much
// of the page is on screen and which part that is.
bool COverlayWnd::ThumbRect(CRect* track, CRect* thumb) const {
    if (!m_session->LongShotEdit()) return false;
    const int maxScroll = m_session->LongShotMaxScroll();
    if (maxScroll <= 0) return false;

    const CRect f = m_session->Sel().Rect();
    const HWND hwnd = GetSafeHwnd();
    const int w = Dpi::S(hwnd, 8), pad = Dpi::S(hwnd, 3);
    *track = CRect(f.right - w - pad, f.top, f.right - pad, f.bottom);
    if (track->Width() <= 0 || track->Height() <= 0) return false;

    // The thumb is the frame as a share of the page, floored so that a page much
    // taller than the frame still leaves something to hold on to.
    const int th = (std::max)(Dpi::S(hwnd, 30),
                              MulDiv(f.Height(), f.Height(),
                                     m_session->Capture().Height()));
    const int travel = (std::max)(0, track->Height() - th);
    const int y = track->top +
                  MulDiv(travel, m_session->LongShotScroll(), maxScroll);
    *thumb = CRect(track->left, y, track->right, y + th);
    return true;
}

void COverlayWnd::DrawScrollBar(Gdiplus::Graphics& g) {
    CRect track, thumb;
    if (!ThumbRect(&track, &thumb)) return;

    // Clipping to the track is also what clears the thumb's last position, so a
    // scroll leaves no ghost behind it.
    ClipTo clip(g, Gdiplus::RectF((Gdiplus::REAL)track.left,
                                  (Gdiplus::REAL)track.top,
                                  (Gdiplus::REAL)track.Width(),
                                  (Gdiplus::REAL)track.Height()),
                &m_chromeInk);
    Gdiplus::SolidBrush back(kTrackBack);
    g.FillRectangle(&back, (Gdiplus::REAL)track.left, (Gdiplus::REAL)track.top,
                    (Gdiplus::REAL)track.Width(), (Gdiplus::REAL)track.Height());
    Gdiplus::SolidBrush ink(kThumb);
    g.FillRectangle(&ink, (Gdiplus::REAL)thumb.left, (Gdiplus::REAL)thumb.top,
                    (Gdiplus::REAL)thumb.Width(), (Gdiplus::REAL)thumb.Height());
}

int COverlayWnd::HandleRadius() const {
    return Dpi::S(GetSafeHwnd(), 8);
}

int COverlayWnd::AnnoHandleRadius() const {
    return Dpi::S(GetSafeHwnd(), 5);
}

bool COverlayWnd::HasMarkers(const annot::Annotation& a) const {
    return a.GetKind() != annot::Kind::Text || &a == m_session->EditingAnno();
}

annot::ShapeText* COverlayWnd::FrameText() const {
    annot::Annotation* a = m_session->Selected();
    return a && a->GetKind() == annot::Kind::Text
               ? static_cast<annot::ShapeText*>(a)
               : nullptr;
}

int COverlayWnd::HitAnnoHandle(const annot::Annotation& a, CPoint pt) const {
    // A grab for a marker that was never drawn would offer a resize the cursor
    // never showed: a label that is not being edited moves as a whole.
    if (!HasMarkers(a)) return -1;

    // The grab area is not the marker. An ellipse's or a label's marker draws at
    // half the default and still has to be catchable, while the big markers a
    // thick rect or arrow draws have to be catchable whole — so the floor stays
    // at the old radius plus 2 and only ever grows from there.
    const Gdiplus::REAL drawn =
        annot::HandleSize(a, (Gdiplus::REAL)AnnoHandleRadius());
    const Gdiplus::REAL r =
        (std::max)((Gdiplus::REAL)(AnnoHandleRadius() + 2), drawn + 2.0f);
    for (int i = 0; i < a.HandleCount(); ++i) {
        const Gdiplus::PointF c = a.HandleAt(i);
        if (std::hypot((double)pt.x - c.X, (double)pt.y - c.Y) <= r) return i;
    }
    return -1;
}

annot::ShapeText* COverlayWnd::TextAt(CPoint pt) const {
    annot::Annotation* a =
        m_session->Annos().TopAt(Gdiplus::PointF((Gdiplus::REAL)pt.x, (Gdiplus::REAL)pt.y));
    return a ? dynamic_cast<annot::ShapeText*>(a) : nullptr;
}

// The 字号 list and the inline editor sit over the canvas, so the press that
// lands on either of them resolves it instead of starting a drag behind it.
// Returns true when the press is consumed.
bool COverlayWnd::ResolvePopup(CPoint pt) {
    if (const CRect* d = m_session->FontDropdown()) {
        const int row = HitFontRow(pt);
        if (row >= 0) {
            m_session->Style().fontSize = tb::FontSizeForRow(row);
            // A row picked while a label is selected or being typed into changes
            // that label now, not the next one — the list is the size picker for
            // the box on screen. The press landed on this overlay, so the input
            // control never lost focus and the edit is still open.
            m_session->ApplyStyleToSelected();
        }
        m_session->HideFontDropdown();  // ChromeChanged repaints bar and list
        return true;
    }
    if (m_session->Editor()) {
        // The input control covers the box's inside, so a press the overlay sees
        // near the box is on its markers or its frame line: that resizes or moves
        // the box being typed into, so the edit stays open and the press runs as
        // the drag it looks like. Anywhere else the press commits the edit and is
        // swallowed, so the click that commits does not also start a shape.
        annot::ShapeText* t = m_session->Editor()->Label();
        if (t && (t->HitTest(Gdiplus::PointF((Gdiplus::REAL)pt.x,
                                             (Gdiplus::REAL)pt.y)) ||
                  HitAnnoHandle(*t, pt) >= 0))
            return false;
        m_session->EndTextEdit(true);
        return true;
    }
    return false;
}

// The 编辑 thumb follows the pointer, less whatever part of it the press landed
// on. ScrollLongShot clamps the target itself, so only the difference is handed
// over.
void COverlayWnd::ScrollToThumb(CPoint pt) {
    CRect track, thumb;
    if (!ThumbRect(&track, &thumb)) return;
    const int travel = track.Height() - thumb.Height();
    if (travel <= 0) return;
    const int y = std::clamp(pt.y - m_thumbGrab, track.top, track.top + travel);
    m_session->ScrollLongShot(
        MulDiv(m_session->LongShotMaxScroll(), y - track.top, travel) -
        m_session->LongShotScroll());
}

namespace {
// The box everything drawn on the canvas covers, in client px; empty when there
// is nothing on it. InkBBox rather than BBox — the anti-aliased fringe and the
// outer half of a pen are ink the region has to keep holding.
RECT InkBounds(const annot::AnnotationList& annos) {
    RECT box = {};
    for (size_t i = 0; i < annos.Count(); ++i) {
        const annot::Annotation* a = annos.At(i);
        if (!a) continue;
        const Gdiplus::RectF b = a->InkBBox();
        const RECT r{ (int)std::floor(b.X), (int)std::floor(b.Y),
                      (int)std::ceil(b.X + b.Width),
                      (int)std::ceil(b.Y + b.Height) };
        if (IsRectEmpty(&box)) box = r;
        else UnionRect(&box, &box, &r);
    }
    return box;
}
}  // namespace

bool COverlayWnd::OutsideRegion(CPoint pt) const {
    // While the region is still the whole screen there is no outside to be
    // outside of.
    const SelectionModel& sel = m_session->Sel();
    if (sel.IsDefault()) return false;
    const POINT p{ pt.x, pt.y };
    if (sel.Contains(p)) return false;
    return sel.HitTest(p, HandleRadius()) == SelHandle::None;
}

void COverlayWnd::MoveSelTo(RECT r) {
    SelectionModel& sel = m_session->Sel();
    const RECT keep = InkBounds(m_session->Annos());
    sel.SetKeepIn(&keep);
    sel.MoveTo(r);
    sel.SetKeepIn(nullptr);
}

void COverlayWnd::ResizeSel(SelHandle h, POINT pt) {
    SelectionModel& sel = m_session->Sel();
    const RECT keep = InkBounds(m_session->Annos());
    sel.SetKeepIn(&keep);
    sel.Resize(h, pt);
    sel.SetKeepIn(nullptr);
}

void COverlayWnd::NudgeSel(int dx, int dy, bool resizeEdges) {
    SelectionModel& sel = m_session->Sel();
    const RECT keep = InkBounds(m_session->Annos());
    sel.SetKeepIn(&keep);
    sel.Nudge(dx, dy, resizeEdges);
    sel.SetKeepIn(nullptr);
}

void COverlayWnd::OnLButtonDown(UINT, CPoint pt) {
    // Presses inside the hole never reach us — that is the point of the hole.
    // What is left is the chrome, and the only thing on it is the caret.
    if (InLongShot()) {
        if (m_session->HitLongShotCaret(pt)) m_session->ToggleLongShotPreview();
        return;
    }
    CRect track, thumb;
    if (ThumbRect(&track, &thumb) && track.PtInRect(pt) != FALSE) {
        ::SetCapture(GetSafeHwnd());
        m_mode = Mode::ScrollThumb;
        // How far into the thumb the press landed, so holding it there does not
        // jump; anywhere else in the track the thumb's top comes to the pointer.
        m_thumbGrab = pt.y - thumb.top;
        ScrollToThumb(pt);
        return;
    }
    if (ResolvePopup(pt)) return;

    ::SetCapture(GetSafeHwnd());
    SelectionModel& sel = m_session->Sel();
    m_dragStart = pt;
    m_startRect = sel.Rect();
    // A second press inside the same drag (the WM_LBUTTONDOWN of a double click)
    // must not overwrite the rect the release falls back to, or a double click
    // on empty canvas would collapse the selection.
    if (m_mode != Mode::Creating) m_prevRect = sel.Rect();
    m_anno = nullptr;
    m_annoBefore.reset();
    m_annoIdx = m_annoHandle = -1;
    m_pending.reset();

    // The 编辑 frame cannot be sized, so its edges are not handles there.
    SelHandle h = m_session->LongShotEdit()
                      ? SelHandle::None
                      : sel.HitTest(POINT{ pt.x, pt.y }, HandleRadius());
    if (h != SelHandle::None) {
        m_mode = Mode::Sizing;
        m_handle = h;
    } else if (annot::Annotation* a = m_session->Selected()) {
        const int hi = HitAnnoHandle(*a, pt);
        if (hi >= 0) {
            m_mode = Mode::DragHandle;
            m_anno = a;
            m_annoIdx = m_session->SelectedIndex();
            m_annoHandle = hi;
            m_annoBefore = a->Clone();
            DropFromBase(*a);
        }
    }

    if (m_mode == Mode::Idle) {
        // 矩形-点击已画矩形.png, 椭圆-点击已画椭圆可调整大小位置.png and
        // 箭头-点击已画箭头可调整方向 位置 长短.png all show the tool still armed
        // with the shape drawn earlier selected and adjustable, so a press that
        // lands on existing ink grabs it rather than starting another shape.
        // 画笔 and 马赛克 are the exception: there a press is the first point of
        // a stroke, and a stroke that begins on old ink must not drag it along.
        const tb::Id tool = m_session->ActiveTool();
        const bool freehand = tool == tb::Id::Pen || tool == tb::Id::Mosaic;
        annot::Annotation* a = freehand
                                   ? nullptr
                                   : m_session->Annos().TopAt(
                                         Gdiplus::PointF((Gdiplus::REAL)pt.x,
                                                         (Gdiplus::REAL)pt.y));
        if (a) {
            m_mode = Mode::MoveAnno;
            m_anno = a;
            m_annoIdx = m_session->Annos().IndexOf(a);
            m_annoBefore = a->Clone();
            m_session->Select(m_annoIdx);
            DropFromBase(*a);
        } else if (tool == tb::Id::Text) {
            // A press on bare canvas with the text tool arms a new label; one on
            // existing ink was handled above, so a label can always be picked up
            // again. Re-editing stays on the double click, as in 文字-双击编辑.png.
            // The call selects the label it just added — the box on screen while
            // typing is that label's own, frame and markers included.
            m_session->BeginTextEdit(pt, nullptr);
        } else if ((m_pending = annot::MakeShape(
                        tool, Gdiplus::PointF((Gdiplus::REAL)pt.x,
                                              (Gdiplus::REAL)pt.y),
                        m_session->Style(), m_session->NextBadgeNumber(),
                        &m_session->Mosaic()))) {
            m_mode = Mode::Drawing;
            m_session->Select(-1);
        } else if (m_session->LongShotEdit()) {
            // The frame is a viewport and it is fixed: a press that neither grabs
            // ink nor arms a shape has nothing to do.
        } else if (!sel.IsDefault() && !tb::IsTool(tool)) {
            // The region is already picked, so outside it there is nothing this
            // press could work on: dragging a new one there was a way to lose the
            // one you had. Inside, it moves the region. A drawing tool armed is
            // the exception — there the press is the first point of a stroke, and
            // a stroke that starts outside is held at the frame.
            m_mode = sel.Contains(POINT{ pt.x, pt.y }) ? Mode::Moving
                                                       : Mode::Ignored;
        } else {
            m_mode = Mode::Creating;
            m_selPicked = true;
            sel.BeginCreate(POINT{ pt.x, pt.y });
            m_session->Select(-1);
        }
    }
    Invalidate();
}

// 文字-已添加.png: double-clicking a label re-opens it for editing. The first
// press of the double click already ran, so whatever it started is dropped.
void COverlayWnd::OnLButtonDblClk(UINT nFlags, CPoint pt) {
    if (InLongShot()) return;
    if (m_session->Editor() || m_session->FontDropdown()) return;

    annot::ShapeText* t = TextAt(pt);
    if (!t) {
        // 框外双击: the capture is over. Outside a region that is already picked
        // there is nothing else a double click could mean, and the first press of
        // it did nothing either.
        if (OutsideRegion(pt) && !tb::IsTool(m_session->ActiveTool())) {
            m_session->Finish(false);
            return;
        }
        OnLButtonDown(nFlags, pt);
        return;
    }

    m_annoBefore.reset();
    m_anno = nullptr;
    m_annoIdx = m_annoHandle = -1;
    m_mode = Mode::Idle;
    ::ReleaseCapture();

    m_session->Select(m_session->Annos().IndexOf(t));
    m_session->BeginTextEdit(pt, t);
}

LRESULT COverlayWnd::OnEditDone(WPARAM wParam, LPARAM) {
    m_session->EndTextEdit(wParam != 0);
    return 0;
}

void COverlayWnd::OnMouseMove(UINT, CPoint pt) {
    if (ProbeOn()) g_probeLastMove = ProbeTicks();
    if (InLongShot()) return;
    SelectionModel& sel = m_session->Sel();
    switch (m_mode) {
    case Mode::Creating: {
        const RECT before = sel.Rect();
        sel.UpdateCreate(POINT{ pt.x, pt.y });
        LayoutChrome();
        InvalidateSelChange(before);
        break;
    }
    case Mode::Moving: {
        const RECT before = sel.Rect();
        RECT r = m_startRect;
        int dx = pt.x - m_dragStart.x;
        int dy = pt.y - m_dragStart.y;
        r.left += dx; r.top += dy; r.right += dx; r.bottom += dy;
        MoveSelTo(r);
        LayoutChrome();
        InvalidateSelChange(before);
        break;
    }
    case Mode::Sizing: {
        const RECT before = sel.Rect();
        ResizeSel(m_handle, POINT{ pt.x, pt.y });
        LayoutChrome();
        InvalidateSelChange(before);
        break;
    }
    case Mode::Drawing:
        // Past the frame the shape keeps the result of the last position inside:
        // the box and the arrow recompute from a fixed start, so not being called
        // holds them there, and the freehand tools append, so not being called
        // stops sampling at the last point that was inside. Releasing outside
        // commits what is there, which is what ends the drag.
        if (m_pending && InRegion(sel.Rect(), pt)) {
            const CRect before = AnnoRect(m_pending.get());
            m_pending->UpdateDrag(
                Gdiplus::PointF((Gdiplus::REAL)pt.x, (Gdiplus::REAL)pt.y),
                (::GetKeyState(VK_SHIFT) & 0x8000) != 0);
            InvalidateAnnoChange(m_pending.get(), before);
        }
        break;
    case Mode::MoveAnno:
        if (m_anno) {
            const CRect before = AnnoRect(m_anno);
            // What falls outside the frame is not in the export, so an element
            // dragged past it reads as having vanished. Each axis stops at the
            // frame on its own and starts again from there when the pointer comes
            // back, so dragging off the bottom-right corner parks the element in
            // the corner rather than stopping it short of both edges. A shape
            // wider or taller than the frame cannot move on that axis at all.
            const RECT s = sel.Rect();
            const Gdiplus::RectF bb = m_anno->InkBBox();
            const Gdiplus::REAL dx = (Gdiplus::REAL)(pt.x - m_dragStart.x);
            const Gdiplus::REAL dy = (Gdiplus::REAL)(pt.y - m_dragStart.y);
            const Gdiplus::REAL ax =
                InRegion(s, Gdiplus::RectF(bb.X + dx, bb.Y, bb.Width, bb.Height))
                    ? dx : 0;
            const Gdiplus::REAL ay =
                InRegion(s, Gdiplus::RectF(bb.X, bb.Y + dy, bb.Width, bb.Height))
                    ? dy : 0;
            if (ax != 0 || ay != 0) m_anno->Translate(ax, ay);
            // Only the part that landed counts as the pointer's position; the
            // rest of the excursion is forgotten, as the request asks.
            m_dragStart.x += (LONG)ax;
            m_dragStart.y += (LONG)ay;
            InvalidateAnnoChange(m_anno, before);
            // Typing into a label and dragging it are the same object now, so the
            // caret and the glyphs have to come along with the box.
            m_session->SyncEditor();
        }
        break;
    case Mode::DragHandle:
        if (m_anno) {
            const CRect before = AnnoRect(m_anno);
            // The same limit on a resize, axis by axis: a corner dragged off the
            // bottom-right of the frame ends up in the corner. MoveHandle cannot
            // be undone, so each candidate goes onto a clone first and only one
            // that keeps the ink inside the frame is applied to the real shape.
            const RECT s = sel.Rect();
            const Gdiplus::REAL x = (Gdiplus::REAL)pt.x, y = (Gdiplus::REAL)pt.y;
            for (int pass = 0; pass < 2; ++pass) {
                const Gdiplus::PointF at = m_anno->HandleAt(m_annoHandle);
                const Gdiplus::PointF cand =
                    pass ? Gdiplus::PointF(at.X, y) : Gdiplus::PointF(x, at.Y);
                auto trial = m_anno->Clone();
                trial->MoveHandle(m_annoHandle, cand);
                if (InRegion(s, trial->InkBBox()))
                    m_anno->MoveHandle(m_annoHandle, cand);
            }
            InvalidateAnnoChange(m_anno, before);
            // A resize re-wraps the text, so the input surface follows the new
            // box rather than leaving the caret behind in the old one.
            m_session->SyncEditor();
        }
        break;
    case Mode::ScrollThumb:
        ScrollToThumb(pt);
        break;
    case Mode::Ignored:
        break;
    case Mode::Idle:
        CursorMoved();
        // The desktop under this window is live, so the pre-selection has to be
        // re-read from the real window stack on every move rather than from a
        // list taken at summon: anything could open or move underneath.
        UpdateHover();
        break;
    }
    // The magnifier rides the cursor through a selection drag, so its card is
    // part of that band too; it is absent during a stroke, where this is free.
    if (m_mode != Mode::Idle) InvalidateLoupe();
}

void COverlayWnd::OnLButtonUp(UINT, CPoint) {
    if (InLongShot()) return;
    if (m_mode == Mode::Creating) {
        SelectionModel& sel = m_session->Sel();
        if (sel.Width() < 3 || sel.Height() < 3) {
            // A press without a drag is still a decision. Over a program window
            // it takes that window, which is what the frame hovering there
            // promised; over the desktop itself, where no window was eligible, it
            // is still the whole screen. Either way the region is now picked, so
            // the next press moves it or draws in it instead of starting the same
            // gesture over.
            sel.Set(m_hover.IsRectEmpty() ? m_prevRect : m_hover);
            sel.MarkPicked();
            m_hover.SetRectEmpty();
        }
    } else if (m_mode == Mode::Drawing) {
        if (m_pending) {
            m_pending->Commit();
            // A click without a drag is not a shape; it leaves the tool armed
            // so the next press starts one, as in 矩形-鼠标拖动画矩形.png.
            if (!m_pending->IsEmpty())
                m_session->AddAnnotation(std::move(m_pending));
            m_pending.reset();
        }
    } else if (m_mode == Mode::MoveAnno || m_mode == Mode::DragHandle) {
        const bool moved =
            m_anno && m_annoBefore && !SameBox(m_annoBefore->BBox(), m_anno->BBox());
        const CRect was = m_anno ? AnnoRect(m_anno) : CRect(0, 0, 0, 0);
        if (moved) m_session->RecordMove(m_annoIdx, std::move(m_annoBefore));
        m_annoBefore.reset();
        m_anno = nullptr;
        m_annoIdx = m_annoHandle = -1;
        // RecordMove rebuilds the cache with the shape back in it. A drag that
        // went nowhere records nothing, so the shape has to be put back here or
        // it would vanish along with the button.
        m_mode = Mode::Idle;  // MovingAnno() has to be null for the rebuild
        if (!moved && !was.IsRectEmpty()) TouchBaseIn(was);
    }
    m_mode = Mode::Idle;
    m_handle = SelHandle::None;
    ::ReleaseCapture();
    LayoutChrome();
    Invalidate();
}

// 鼠标右键自由截图, which is what the magnifier card promises. Before a region
// has been picked the region is the whole screen, so a right click there takes
// that, copies it and is done — the fastest way out for anyone who only wanted
// the desktop. Once a region or some ink exists the click would throw work away,
// so it is left inert.
// The action is on the release, and every right-button message is swallowed
// rather than passed to DefWindowProc. Accept ends the capture, and the overlay
// used to be gone by the time the physical WM_RBUTTONUP arrived — the release
// then reached the window underneath, and the desktop or the file browser opened
// its own context menu under a hand that had just asked for a screenshot.
void COverlayWnd::OnRButtonDown(UINT, CPoint) {}

void COverlayWnd::OnRButtonUp(UINT, CPoint pt) {
    if (InLongShot()) return;
    if (m_session->Sel().IsDefault() && m_session->Annos().Count() == 0) {
        m_session->Accept();
        return;
    }
    // 框外右键: everything since the hotkey opened is withdrawn — the drawings,
    // the history that could bring them back, the armed tool, and the region,
    // which goes back to the whole screen with the magnifier. The 编辑 frame is
    // a viewport rather than a picked region, so it is not what this cancels.
    if (OutsideRegion(pt) && !m_session->LongShotEdit())
        m_session->ResetCanvas();
}

void COverlayWnd::OnRButtonDblClk(UINT, CPoint) {}

// With the release handled here, DefWindowProc never sees it and has no reason
// to generate this; the keyboard route (Shift+F10) still does, and gets no menu
// either.
void COverlayWnd::OnContextMenu(CWnd*, CPoint) {}

// The wheel goes to whatever the cursor is over, so inside the hole it normally
// reaches the page without ever coming here — and the low-level hook in the
// long-shot controller is what refuses a notch that gets ahead of the stitcher.
// This handler is the fallback for when hover-scrolling is switched off and the
// message comes to the focus window instead; the notch is already accounted for
// by then, so pass it on and leave the allowance alone.
BOOL COverlayWnd::OnMouseWheel(UINT nFlags, short zDelta, CPoint pt) {
    // 长截图 编辑: the page is taller than the frame that shows it, and the
    // wheel is how the rest of it is reached. Any pointer position counts — the
    // overlay owns the wheel here and there is nothing else it could mean.
    if (m_session->LongShotEdit()) {
        // Rolling forward brings the top of the page down to the top of the
        // frame, which is the opposite way to ScrollLongShot's rows: positive
        // there means further down the document.
        const int step = (zDelta / WHEEL_DELTA) * Dpi::S(GetSafeHwnd(), 100);
        if (step) m_session->ScrollLongShot(-step);
        return TRUE;
    }
    if (!m_hole.IsRectEmpty()) {
        CPoint cl = pt;
        ScreenToClient(&cl);
        if (m_hole.PtInRect(cl) != FALSE) {
            HWND target = ::WindowFromPoint(pt);
            if (target && target != m_hWnd) {
                ::PostMessage(target, WM_MOUSEWHEEL,
                              MAKEWPARAM(nFlags, (WPARAM)(WORD)zDelta),
                              MAKELPARAM(pt.x, pt.y));
                return TRUE;
            }
        }
    }
    return CWnd::OnMouseWheel(nFlags, zDelta, pt);
}

BOOL COverlayWnd::OnSetCursor(CWnd*, UINT, UINT) {
    if (InLongShot()) {
        ::SetCursor(::LoadCursor(nullptr, IDC_ARROW));
        return TRUE;
    }
    CPoint pt;
    ::GetCursorPos(&pt);
    ::ScreenToClient(GetSafeHwnd(), &pt);

    const SelectionModel& sel = m_session->Sel();
    const POINT p{ pt.x, pt.y };
    // The 编辑 frame has no edges to grab, so it offers no handles either.
    SelHandle h = m_mode == Mode::Idle && !m_session->LongShotEdit()
                      ? sel.HitTest(p, HandleRadius())
                      : m_handle;

    // Each shape says what a press here would do. The eight grips the frame draws
    // resize it; ink moves the element under it; the frame away from a grip moves
    // the whole region; the crosshair starts a shape inside the region; the arrow
    // is everywhere a press would do nothing, which includes the two bars, whose
    // own class cursors already are the arrow.
    LPCTSTR id = nullptr;
    switch (h) {
    case SelHandle::TopLeft:
    case SelHandle::BottomRight: id = IDC_SIZENWSE; break;
    case SelHandle::TopRight:
    case SelHandle::BottomLeft:  id = IDC_SIZENESW; break;
    case SelHandle::Top:
    case SelHandle::Bottom:      id = IDC_SIZENS; break;
    case SelHandle::Left:
    case SelHandle::Right:       id = IDC_SIZEWE; break;
    }

    // A selection handle has already claimed the pointer, so ink is only worth
    // asking about where the crosshair or the arrow would otherwise sit.
    if (!id && m_mode == Mode::Idle) {
        if (annot::Annotation* a = m_session->Selected()) {
            const int hi = HitAnnoHandle(*a, pt);
            if (hi >= 0) id = kBoxCursors[hi];
        }
        // Inside the text of the label being edited, a press puts the caret there.
        // The input control's class cursor is the I-beam, but MFC hands a child's
        // WM_SETCURSOR to the parent, so that cursor never runs and the overlay has
        // to answer for it — over the control's own rectangle and no further, since
        // the ring between it and the box edge is a press on the box, not in the
        // text.
        if (!id) {
            if (annot::Annotation* e = m_session->EditingAnno();
                e && e->GetKind() == annot::Kind::Text) {
                annot::ShapeText* t = static_cast<annot::ShapeText*>(e);
                const Gdiplus::RectF b = t->Box();
                const Gdiplus::REAL pad = t->PadX();
                if (pt.x >= b.X + pad && pt.x < b.X + b.Width - pad &&
                    pt.y >= b.Y + pad && pt.y < b.Y + b.Height - pad)
                    id = IDC_IBEAM;
            }
        }
        // The 画笔 and 马赛克 press is a stroke even on top of old ink, so the
        // move cursor would promise a move that does not happen.
        const tb::Id tool = m_session->ActiveTool();
        if (!id && tool != tb::Id::Pen && tool != tb::Id::Mosaic &&
            m_session->Annos().TopAt(Gdiplus::PointF((Gdiplus::REAL)pt.x,
                                                     (Gdiplus::REAL)pt.y)))
            id = IDC_SIZEALL;
    }

    if (!id) {
        if (m_mode == Mode::Moving || m_mode == Mode::MoveAnno)
            id = IDC_SIZEALL;
        else if (m_mode == Mode::ScrollThumb)
            id = IDC_ARROW;
        else if (m_mode != Mode::Idle)
            id = IDC_CROSS;
        else if (m_session->ActiveTool() != tb::Id::None)
            // A drawing tool is armed, so the crosshair is what the shape starts
            // from. This is the one case the plain cross is right for.
            id = sel.Contains(p) ? IDC_CROSS : IDC_ARROW;
        // The 编辑 frame is a viewport that cannot be moved or resized, so away
        // from the ink on it the pointer is only a pointer.
        else if (m_session->LongShotEdit())
            id = IDC_ARROW;
        // With no tool armed a press anywhere inside a region the user picked
        // moves that region, so the pointer says so across the whole of it and
        // not only near the edge. Outside the frame a press does nothing at all,
        // and the arrow below is what says so; the grips on the frame were
        // claimed above, so they keep their resize cursors out there.
        else if (!sel.IsDefault() && sel.Contains(p))
            id = IDC_SIZEALL;
        else
            id = sel.Contains(p) ? IDC_CROSS : IDC_ARROW;
    }

    HCURSOR cursor = id == IDC_CROSS ? CrossCursor()
                                     : ::LoadCursor(nullptr, id);
    ::SetCursor(cursor ? cursor : ::LoadCursor(nullptr, IDC_ARROW));
    return TRUE;
}

void COverlayWnd::OnKeyDown(UINT nChar, UINT nRepCnt, UINT nFlags) {
    // 长截图 has no selection to nudge and no annotations to undo; the bar owns
    // everything else and Esc is the bar's ✕.
    if (InLongShot()) {
        if (nChar == VK_ESCAPE) m_session->Finish(false);
        return;
    }
    if (::GetKeyState(VK_CONTROL) & 0x8000) {
        if (nChar == 'Z') {
            m_session->Undo();
            return;
        }
        if (nChar == 'S') {
            m_session->SavePng();
            return;
        }
    }
    if (nChar == VK_DELETE && m_session->SelectedIndex() >= 0) {
        m_session->RemoveAnnotation(m_session->SelectedIndex());
        Invalidate();
        return;
    }
    // 按c复制色号: only while the magnifier is up, which is what the readout
    // promises — with a tool armed there is no sampled pixel to copy.
    if (nChar == 'C') {
        CPoint at;
        if (LoupeCursor(&at)) {
            loupe::CopyColor(m_session->Capture(), at, m_session->CapOff());
            // The colour was the whole request; the capture ends here rather
            // than waiting for a region that was never going to be picked.
            m_session->Finish(false);
        }
        return;
    }

    if (m_session->LongShotEdit()) {
        // The frame cannot be nudged, so the arrows move the page through it —
        // one notch, the same as one wheel click.
        const int notch = Dpi::S(GetSafeHwnd(), 100);
        switch (nChar) {
        case VK_UP:
        case VK_LEFT:  m_session->ScrollLongShot(-notch); return;
        case VK_DOWN:
        case VK_RIGHT: m_session->ScrollLongShot(notch); return;
        }
    }

    int step = (::GetKeyState(VK_SHIFT) & 0x8000) ? 10 : 1;
    int dx = 0, dy = 0;
    switch (nChar) {
    case VK_LEFT:  dx = -step; break;
    case VK_RIGHT: dx = step; break;
    case VK_UP:    dy = -step; break;
    case VK_DOWN:  dy = step; break;
    case VK_ESCAPE:
        m_session->Finish(false);
        return;
    case VK_RETURN:
        m_session->Accept();
        return;
    default:
        CWnd::OnKeyDown(nChar, nRepCnt, nFlags);
        return;
    }

    NudgeSel(dx, dy, false);
    LayoutChrome();
    Invalidate();
}

// A window region alone — no WS_EX_LAYERED needed — both lets the live desktop
// show through the hole and passes the mouse through to the window underneath,
// which is how the wheel reaches the page being scrolled. It also clips child
// windows, which is why the long-shot bar and card are separate top-levels.
void COverlayWnd::SetHole(CRect hole) {
    const HWND hwnd = GetSafeHwnd();
    if (!hwnd) return;
    if (hole.left == m_hole.left && hole.top == m_hole.top &&
        hole.right == m_hole.right && hole.bottom == m_hole.bottom)
        return;
    m_hole = hole;

    if (hole.IsRectEmpty()) {
        ::SetWindowRgn(hwnd, nullptr, TRUE);
        m_toolbar.ShowWindow(SW_SHOW);
        m_propbar.ShowWindow(SW_SHOW);
        LayoutChrome();
    } else {
        CRect cl;
        GetClientRect(&cl);
        HRGN all = ::CreateRectRgn(cl.left, cl.top, cl.right, cl.bottom);
        HRGN cut = ::CreateRectRgn(hole.left, hole.top, hole.right, hole.bottom);
        if (all && cut) {
            if (::CombineRgn(all, all, cut, RGN_DIFF) == ERROR)
                ::DeleteObject(all);
            else if (::SetWindowRgn(hwnd, all, TRUE) == ERROR)
                ::DeleteObject(all);  // only on failure: success takes ownership
        }
        ::DeleteObject(cut);
        m_toolbar.ShowWindow(SW_HIDE);
        m_propbar.ShowWindow(SW_HIDE);
    }
    Invalidate();
}

LRESULT COverlayWnd::OnLsEdit(WPARAM, LPARAM) {
    m_session->RunLongShotEdit();
    return 0;
}

void COverlayWnd::SetTopmost(bool on) {
    m_topmost = on;
    ::SetWindowPos(GetSafeHwnd(), on ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

void COverlayWnd::OnWindowPosChanging(WINDOWPOS* pos) {
    // The taskbar, IME candidate windows and pinned captures all compete for
    // the top; keep our own slot without dragging anyone else along.
    if (m_topmost && pos->hwnd == GetSafeHwnd()) pos->hwndInsertAfter = HWND_TOPMOST;
    CWnd::OnWindowPosChanging(pos);
}
