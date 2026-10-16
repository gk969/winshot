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
#include "AppMessages.h"

#include <emmintrin.h>

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

const Gdiplus::Color kFrame(0xFF1E9FD4);
const Gdiplus::Color kDim(0x99000000);
const Gdiplus::Color kLabelBack(0xE0232323);
const Gdiplus::Color kLabelText(0xFFFFFFFF);
const Gdiplus::Color kCaretInk(0xFF232323);
const Gdiplus::Color kTipBack(0xFFFFFFFF);
const Gdiplus::Color kTipText(0xFF1F2328);
// 文字-点击位置-输入时红色文本框.png strokes the live edit in the annotation
// red whatever the chosen ink is.
const Gdiplus::Color kEditFrame(0xFFF73840);
// 文字-字体大小.png: the 字号 list is a white card with a blue edge.
const Gdiplus::Color kDropEdge(0xFF367EAA);
const wchar_t kFontFace[] = L"Microsoft YaHei UI";

}  // namespace

BEGIN_MESSAGE_MAP(COverlayWnd, CWnd)
    ON_WM_PAINT()
    ON_WM_ERASEBKGND()
    ON_WM_LBUTTONDOWN()
    ON_WM_LBUTTONDBLCLK()
    ON_WM_LBUTTONUP()
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

COverlayWnd::~COverlayWnd() {
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
        static FILE* log = []() -> FILE* {
            FILE* f = nullptr;
            if (::fopen_s(&f, "D:\\Project\\winshot\\obj\\paint.log", "w") != 0)
                return nullptr;
            return f;
        }();
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
    g.DrawImage(cap.Image(), off.x, off.y, cap.Width(), cap.Height());

    // Half-pixel offsets are what make the 1:1 blit land exactly, but they shift
    // every rectangle and pen below by half a pixel, which puts the 2px frame
    // 2px outside the selection instead of straddling its edge.
    g.SetPixelOffsetMode(Gdiplus::PixelOffsetModeNone);

    // Not clipped to the selection: the selection is what changes most often,
    // and tying the cache to it would rebuild the screen on every drag. Ink
    // outside the selection still gets dimmed below, and the export crops it.
    m_session->Annos().DrawAll(g, MovingAnno());
}

// Each chrome element takes a clip of its own. The clip is also the rect its ink
// can reach, which is what lets ClipTo clear and register only that much of the
// buffer instead of the whole update region — 3.5M pixels of clear and blend to
// move ink that fits in two cards, a ring and a magnifier.
namespace {
// Where an annotation can put ink down, plus the ring of selection handles drawn
// around it.
Gdiplus::RectF InkedBox(const annot::Annotation* a, Gdiplus::REAL pad) {
    if (!a) return Gdiplus::RectF(0, 0, 0, 0);
    const Gdiplus::RectF b = a->BBox();
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
        const Gdiplus::CompositingMode cm = g.GetCompositingMode();
        g.SetCompositingMode(Gdiplus::CompositingModeSourceCopy);
        Gdiplus::SolidBrush clear(0x00000000);
        g.FillRectangle(&clear, r.X, r.Y, r.Width, r.Height);
        g.SetCompositingMode(cm);
        ink->push_back(CRect((int)std::floor(r.X), (int)std::floor(r.Y),
                             (int)std::ceil(r.X + r.Width),
                             (int)std::ceil(r.Y + r.Height)));
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
        const Gdiplus::CompositingMode cm = g.GetCompositingMode();
        g.SetCompositingMode(Gdiplus::CompositingModeSourceCopy);
        Gdiplus::SolidBrush clear(0x00000000);
        for (const Gdiplus::RectF& q : strip) {
            if (q.Width <= 0.0f || q.Height <= 0.0f) continue;
            g.FillRectangle(&clear, q.X, q.Y, q.Width, q.Height);
            if (ink)
                ink->push_back(CRect((int)std::floor(q.X), (int)std::floor(q.Y),
                                     (int)std::ceil(q.X + q.Width),
                                     (int)std::ceil(q.Y + q.Height)));
        }
        g.SetCompositingMode(cm);
    }
    ~ClipBand() { m_g.Restore(m_state); }

private:
    Gdiplus::Graphics& m_g;
    Gdiplus::GraphicsState m_state;
};
}  // namespace

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
    annot::Annotation* inked[3] = { moving, m_pending.get(), sel };
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
        if (moving) moving->Draw(g);
        if (m_pending) m_pending->Draw(g);
        if (sel) annot::DrawSelection(g, *sel, (Gdiplus::REAL)AnnoHandleRadius());
    }
    g.Restore(gs);
    ProbeMark(4);

    DrawSelectionFrame(g);
    // The stitched tail hangs beside the hole, which is the one part of the
    // selection area this window still paints. It has no rect of its own to
    // offer, so 长截图 keeps paying for the whole region.
    if (InLongShot()) {
        CRect cl;
        GetClientRect(&cl);
        m_chromeInk.push_back(cl);
        m_session->PaintLongShot(g);
    }
    DrawSizeLabel(g);
    DrawTip(g);
    DrawEditFrame(g);
    DrawFontDropdown(g);
    ProbeMark(5);
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

std::unique_ptr<Gdiplus::Font> COverlayWnd::UiFont(int px) const {
    Gdiplus::FontFamily family(kFontFace);
    return std::make_unique<Gdiplus::Font>(
        &family, (Gdiplus::REAL)px, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
}

// ------------------------------------------------------------- dirty regions

CRect COverlayWnd::AnnoRect(const annot::Annotation* a) {
    if (!a) return CRect(0, 0, 0, 0);
    const Gdiplus::RectF b = a->BBox();
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
    dirty.InflateRect(2, 2);
    InvalidatePart(dirty);
}

void COverlayWnd::CursorMoved() {
    CPoint at;
    if (!LoupeCursor(&at) && !m_loupeShown) return;
    InvalidateLoupe();
}

void COverlayWnd::TipChanged(const CPoint* anchor) {
    // The card that was there has to be repainted over, and the new one has room
    // to land either side of its anchor (it flips above when the bottom would
    // cut it off). Its exact size needs the text measured, which is a paint-time
    // job, so this is a box wide enough for any of the bar's tips instead.
    CRect dirty = m_tipRect;
    if (anchor) {
        const int w = Dpi::S(GetSafeHwnd(), 440);
        const int h = Dpi::S(GetSafeHwnd(), 90);
        dirty.UnionRect(dirty, CRect(anchor->x - w / 2, anchor->y - h,
                                     anchor->x + w / 2, anchor->y + h));
    }
    if (!dirty.IsRectEmpty()) InvalidatePart(dirty);
}

// 文字-点击位置-输入时红色文本框.png: the live edit is a bare CEdit and the
// parent strokes a red frame 2px outside it.
void COverlayWnd::DrawEditFrame(Gdiplus::Graphics& g) {
    const CTextEditor* ed = m_session->Editor();
    if (!ed) return;

    CRect r = ed->Frame();
    const int pad = Dpi::S(GetSafeHwnd(), 2);
    r.InflateRect(pad, pad);
    ClipTo frame(g, Gdiplus::RectF((Gdiplus::REAL)(r.left - 1),
                                   (Gdiplus::REAL)(r.top - 1),
                                   (Gdiplus::REAL)(r.Width() + 2),
                                   (Gdiplus::REAL)(r.Height() + 2)),
                        &m_chromeInk);

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
    const int n = (int)(sizeof(tb::kFontSizes) / sizeof(int));
    const int cur = m_session->Style().fontSize;

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
        const bool on = tb::kFontSizes[i] == cur;
        if (on) {
            Gdiplus::SolidBrush hi(tb::kAccent);
            g.FillRectangle(&hi, (Gdiplus::REAL)d->left, y,
                            (Gdiplus::REAL)d->Width(), (Gdiplus::REAL)row);
        }
        CString s;
        s.Format(L"%d", tb::kFontSizes[i]);
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
    const int n = (int)(sizeof(tb::kFontSizes) / sizeof(int));
    return i >= 0 && i < n ? i : -1;
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

void COverlayWnd::DrawTip(Gdiplus::Graphics& g) {
    const CaptureSession::TipCard* tip = m_session->Tip();
    if (!tip) {
        m_tipRect.SetRectEmpty();
        return;
    }

    if (!m_tipFont) m_tipFont = UiFont(Dpi::S(GetSafeHwnd(), 12));
    if (!m_tipFont) {
        m_tipRect.SetRectEmpty();
        return;
    }
    g.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);

    Gdiplus::RectF m;
    g.MeasureString(tip->text.GetString(), tip->text.GetLength(), m_tipFont.get(),
                    Gdiplus::PointF(0, 0), &m);

    const Gdiplus::REAL padX = (Gdiplus::REAL)Dpi::S(GetSafeHwnd(), 5);
    const Gdiplus::REAL padY = (Gdiplus::REAL)Dpi::S(GetSafeHwnd(), 3);
    const Gdiplus::REAL bw = m.Width + padX * 2;
    const Gdiplus::REAL bh = m.Height + padY * 2;

    CRect cl;
    GetClientRect(&cl);
    Gdiplus::REAL bx = (Gdiplus::REAL)tip->anchor.x - bw / 2;
    Gdiplus::REAL by = (Gdiplus::REAL)tip->anchor.y;
    if (bx < cl.left) bx = (Gdiplus::REAL)cl.left;
    if (bx + bw > cl.right) bx = (Gdiplus::REAL)cl.right - bw;
    if (by + bh > cl.bottom)
        by = (Gdiplus::REAL)tip->anchor.y - bh - Dpi::S(GetSafeHwnd(), 8);

    // 工具栏-矩形-提示.png shows a borderless white card with a soft shadow
    // falling down and to the right.
    const Gdiplus::REAL so = (Gdiplus::REAL)Dpi::S(GetSafeHwnd(), 2);
    const Gdiplus::RectF card(bx, by, bw + so, bh + so);
    m_tipRect = CRect((int)std::floor(card.X), (int)std::floor(card.Y),
                      (int)std::ceil(card.X + card.Width),
                      (int)std::ceil(card.Y + card.Height));
    ClipTo clip(g, card, &m_chromeInk);
    Gdiplus::SolidBrush sh1(0x22000000);
    g.FillRectangle(&sh1, bx + so / 2, by + so / 2, bw, bh);
    Gdiplus::SolidBrush sh2(0x33000000);
    g.FillRectangle(&sh2, bx + so, by + so, bw, bh);

    Gdiplus::SolidBrush back(kTipBack);
    g.FillRectangle(&back, bx, by, bw, bh);
    Gdiplus::SolidBrush fg(kTipText);
    g.DrawString(tip->text.GetString(), tip->text.GetLength(), m_tipFont.get(),
                 Gdiplus::PointF(bx + padX, by + padY), &fg);
}

int COverlayWnd::HandleRadius() const {
    return Dpi::S(GetSafeHwnd(), 8);
}

int COverlayWnd::AnnoHandleRadius() const {
    return Dpi::S(GetSafeHwnd(), 5);
}

int COverlayWnd::HitAnnoHandle(const annot::Annotation& a, CPoint pt) const {
    const Gdiplus::REAL r = (Gdiplus::REAL)(AnnoHandleRadius() + 2);
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
            m_session->Style().fontSize = tb::kFontSizes[row];
            m_session->HideFontDropdown();  // ChromeChanged repaints bar and list
        } else
            m_session->HideFontDropdown();
        return true;
    }
    if (m_session->Editor()) {
        // Anywhere outside the edit commits it. The press is swallowed so the
        // click that commits does not also start a shape underneath.
        m_session->EndTextEdit(true);
        return true;
    }
    return false;
}

void COverlayWnd::OnLButtonDown(UINT, CPoint pt) {
    // Presses inside the hole never reach us — that is the point of the hole.
    // What is left is the chrome, and the only thing on it is the caret.
    if (InLongShot()) {
        if (m_session->HitLongShotCaret(pt)) m_session->ToggleLongShotPreview();
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

    SelHandle h = sel.HitTest(POINT{ pt.x, pt.y }, HandleRadius());
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
            m_session->BeginTextEdit(pt, nullptr);
            m_session->Select(-1);
        } else if ((m_pending = annot::MakeShape(
                        tool, Gdiplus::PointF((Gdiplus::REAL)pt.x,
                                              (Gdiplus::REAL)pt.y),
                        m_session->Style(), m_session->NextBadgeNumber(),
                        &m_session->Mosaic()))) {
            m_mode = Mode::Drawing;
            m_session->Select(-1);
        } else if (!sel.IsDefault() && sel.Contains(POINT{ pt.x, pt.y })) {
            m_mode = Mode::Moving;
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
        sel.MoveTo(r);
        LayoutChrome();
        InvalidateSelChange(before);
        break;
    }
    case Mode::Sizing: {
        const RECT before = sel.Rect();
        sel.Resize(m_handle, POINT{ pt.x, pt.y });
        LayoutChrome();
        InvalidateSelChange(before);
        break;
    }
    case Mode::Drawing:
        if (m_pending) {
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
            m_anno->Translate((Gdiplus::REAL)(pt.x - m_dragStart.x),
                              (Gdiplus::REAL)(pt.y - m_dragStart.y));
            m_dragStart = pt;  // the next delta is relative to this move
            InvalidateAnnoChange(m_anno, before);
        }
        break;
    case Mode::DragHandle:
        if (m_anno) {
            const CRect before = AnnoRect(m_anno);
            m_anno->MoveHandle(m_annoHandle,
                               Gdiplus::PointF((Gdiplus::REAL)pt.x, (Gdiplus::REAL)pt.y));
            InvalidateAnnoChange(m_anno, before);
        }
        break;
    case Mode::Idle:
        CursorMoved();
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
        if (sel.Width() < 3 || sel.Height() < 3) sel.Set(m_prevRect);
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

// Windows sends the wheel to the focus window, and in 长截图 that is us rather
// than the window the hole is showing. Pass it on to whatever is underneath.
BOOL COverlayWnd::OnMouseWheel(UINT nFlags, short zDelta, CPoint pt) {
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
    SelHandle h = m_mode == Mode::Idle
                      ? sel.HitTest(POINT{ pt.x, pt.y }, HandleRadius())
                      : m_handle;

    LPCTSTR id = IDC_CROSS;
    switch (h) {
    case SelHandle::TopLeft:
    case SelHandle::BottomRight: id = IDC_SIZENWSE; break;
    case SelHandle::TopRight:
    case SelHandle::BottomLeft:  id = IDC_SIZENESW; break;
    case SelHandle::Top:
    case SelHandle::Bottom:      id = IDC_SIZENS; break;
    case SelHandle::Left:
    case SelHandle::Right:       id = IDC_SIZEWE; break;
    case SelHandle::None:
        if (m_mode == Mode::Idle && !sel.IsDefault() &&
            sel.Contains(POINT{ pt.x, pt.y }))
            id = IDC_SIZEALL;
        break;
    }

    if (h == SelHandle::None && m_mode == Mode::Idle) {
        if (annot::Annotation* a = m_session->Selected()) {
            const int hi = HitAnnoHandle(*a, pt);
            if (hi >= 0) id = kBoxCursors[hi];
        }
        // The 画笔 and 马赛克 press is a stroke even on top of old ink, so the
        // grab cursor would promise a move that does not happen.
        const tb::Id tool = m_session->ActiveTool();
        if (id == IDC_CROSS && tool != tb::Id::Pen && tool != tb::Id::Mosaic &&
            m_session->Annos().TopAt(Gdiplus::PointF((Gdiplus::REAL)pt.x,
                                                     (Gdiplus::REAL)pt.y)))
            id = IDC_SIZEALL;
    }

    ::SetCursor(::LoadCursor(nullptr, id));
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
        if (LoupeCursor(&at))
            loupe::CopyColor(m_session->Capture(), at, m_session->CapOff());
        return;
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

    m_session->Sel().Nudge(dx, dy, false);
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
