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

BOOL COverlayWnd::OnEraseBkgnd(CDC*) {
    return TRUE;  // OnPaint covers every pixel
}

void COverlayWnd::OnPaint() {
    CPaintDC dc(this);
    CRect cl;
    GetClientRect(&cl);
    if (cl.Width() <= 0 || cl.Height() <= 0) return;

    Gdiplus::Bitmap back(cl.Width(), cl.Height(), PixelFormat32bppARGB);
    {
        Gdiplus::Graphics g(&back);
        DrawScene(g);
    }
    {
        Gdiplus::Graphics g(dc.GetSafeHdc());
        g.SetInterpolationMode(Gdiplus::InterpolationModeNearestNeighbor);
        g.DrawImage(&back, 0, 0, cl.Width(), cl.Height());
    }
}

void COverlayWnd::DrawScene(Gdiplus::Graphics& g) {
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

    RECT s = m_session->Sel().Rect();
    CRect cl;
    GetClientRect(&cl);

    const Gdiplus::REAL l = (Gdiplus::REAL)cl.left, t = (Gdiplus::REAL)cl.top;
    const Gdiplus::REAL rr = (Gdiplus::REAL)cl.right, b = (Gdiplus::REAL)cl.bottom;
    const Gdiplus::REAL sl = (Gdiplus::REAL)s.left, st = (Gdiplus::REAL)s.top;
    const Gdiplus::REAL sr = (Gdiplus::REAL)s.right, sb = (Gdiplus::REAL)s.bottom;

    Gdiplus::SolidBrush dim(kDim);
    if (st > t)
        g.FillRectangle(&dim, l, t, rr - l, st - t);
    if (sb < b)
        g.FillRectangle(&dim, l, sb, rr - l, b - sb);
    if (sl > l)
        g.FillRectangle(&dim, l, st, sl - l, sb - st);
    if (sr < rr)
        g.FillRectangle(&dim, sr, st, rr - sr, sb - st);

    // Annotations live in the same space as the still, so they need only a clip
    // to the selection — and they sit above the dim, as in 矩形-鼠标拖动画矩形.png.
    const Gdiplus::GraphicsState gs = g.Save();
    g.SetClip(Gdiplus::RectF(sl, st, sr - sl, sb - st));
    m_session->Annos().DrawAll(g);
    if (m_pending) m_pending->Draw(g);
    if (annot::Annotation* a = m_session->Selected())
        annot::DrawSelection(g, *a, (Gdiplus::REAL)AnnoHandleRadius());
    g.Restore(gs);

    DrawSelectionFrame(g);
    // The stitched tail hangs beside the hole, which is the one part of the
    // selection area this window still paints.
    if (InLongShot()) m_session->PaintLongShot(g);
    DrawSizeLabel(g);
    DrawTip(g);
    DrawEditFrame(g);
    DrawFontDropdown(g);
    DrawLoupe(g);
}

// 默认选择全屏,周围有蓝框.png: the magnifier rides with the cursor while no tool
// is armed, and hides under the bars — they are child windows, so their own
// mouse moves never reach this window.
bool COverlayWnd::LoupeCursor(CPoint* at) const {
    if (InLongShot()) return false;
    if (m_session->ActiveTool() != tb::Id::None || m_session->Editor()) return false;
    if (m_mode == Mode::MoveAnno || m_mode == Mode::DragHandle) return false;

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
    if (!m_loupeShown) return;
    CRect cl;
    GetClientRect(&cl);
    loupe::Draw(*m_session, at, g, cl);
}

void COverlayWnd::CursorMoved() {
    CPoint at;
    if (LoupeCursor(&at) || m_loupeShown) InvalidateRect(nullptr, FALSE);
}

// 文字-点击位置-输入时红色文本框.png: the live edit is a bare CEdit and the
// parent strokes a red frame 2px outside it.
void COverlayWnd::DrawEditFrame(Gdiplus::Graphics& g) {
    const CTextEditor* ed = m_session->Editor();
    if (!ed) return;

    CRect r = ed->Frame();
    const int pad = Dpi::S(GetSafeHwnd(), 2);
    r.InflateRect(pad, pad);

    Gdiplus::Pen pen(kEditFrame, 1.0f);
    g.DrawRectangle(&pen, (Gdiplus::REAL)r.left + 0.5f, (Gdiplus::REAL)r.top + 0.5f,
                    (Gdiplus::REAL)r.Width() - 1.0f, (Gdiplus::REAL)r.Height() - 1.0f);
}

// 文字-字体大小.png: a flat white card under the 字号 box, the current size
// filled blue with white digits.
void COverlayWnd::DrawFontDropdown(Gdiplus::Graphics& g) {
    const CRect* d = m_session->FontDropdown();
    if (!d) return;

    const HWND hwnd = GetSafeHwnd();
    const int row = Dpi::S(hwnd, tb::kFontRow);
    const int n = (int)(sizeof(tb::kFontSizes) / sizeof(int));
    const int cur = m_session->Style().fontSize;

    Gdiplus::SolidBrush back(Gdiplus::Color(0xFFFFFFFF));
    g.FillRectangle(&back, (Gdiplus::REAL)d->left, (Gdiplus::REAL)d->top,
                    (Gdiplus::REAL)d->Width(), (Gdiplus::REAL)d->Height());

    Gdiplus::FontFamily family(kFontFace);
    Gdiplus::Font font(&family, (Gdiplus::REAL)Dpi::S(hwnd, 13),
                       Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
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
        g.DrawString(s, -1, &font,
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

    int hs = Dpi::S(GetSafeHwnd(), 7);
    if ((hs & 1) == 0) ++hs;
    const int off = hs / 2;  // odd size + integer offset centres the square

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

    Gdiplus::FontFamily family(kFontFace);
    Gdiplus::REAL px = (Gdiplus::REAL)(-Dpi::FontHeightForPoint(GetSafeHwnd(), 9));
    Gdiplus::Font font(&family, px, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
    g.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);

    Gdiplus::RectF measured;
    g.MeasureString(text.GetString(), text.GetLength(), &font,
                    Gdiplus::PointF(0, 0), &measured);

    Gdiplus::REAL pad = (Gdiplus::REAL)Dpi::S(GetSafeHwnd(), 4);
    Gdiplus::REAL bw = measured.Width + pad * 2;
    Gdiplus::REAL bh = measured.Height + pad;
    Gdiplus::REAL bx = (Gdiplus::REAL)sel.Rect().left;
    Gdiplus::REAL by = (Gdiplus::REAL)sel.Rect().top - bh - 2;

    CRect cl;
    GetClientRect(&cl);
    if (by < cl.top) by = (Gdiplus::REAL)sel.Rect().top + 2;

    Gdiplus::SolidBrush back(kLabelBack);
    g.FillRectangle(&back, bx, by, bw, bh);
    Gdiplus::SolidBrush fg(kLabelText);
    g.DrawString(text.GetString(), text.GetLength(), &font,
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
    if (!tip) return;

    Gdiplus::FontFamily family(kFontFace);
    Gdiplus::Font font(&family, (Gdiplus::REAL)Dpi::S(GetSafeHwnd(), 12),
                       Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
    g.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);

    Gdiplus::RectF m;
    g.MeasureString(tip->text.GetString(), tip->text.GetLength(), &font,
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
    Gdiplus::SolidBrush sh1(0x22000000);
    g.FillRectangle(&sh1, bx + so / 2, by + so / 2, bw, bh);
    Gdiplus::SolidBrush sh2(0x33000000);
    g.FillRectangle(&sh2, bx + so, by + so, bw, bh);

    Gdiplus::SolidBrush back(kTipBack);
    g.FillRectangle(&back, bx, by, bw, bh);
    Gdiplus::SolidBrush fg(kTipText);
    g.DrawString(tip->text.GetString(), tip->text.GetLength(), &font,
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
    if (m_session->ActiveTool() == tb::Id::Text) {
        // Clicking an existing label re-edits it in place rather than stacking a
        // second one on top.
        m_session->BeginTextEdit(pt, TextAt(pt));
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

    const tb::Id tool = m_session->ActiveTool();
    m_pending = annot::MakeShape(
        tool, Gdiplus::PointF((Gdiplus::REAL)pt.x, (Gdiplus::REAL)pt.y),
        m_session->Style(), m_session->NextBadgeNumber(), &m_session->Mosaic());
    if (m_pending) {
        m_mode = Mode::Drawing;
        m_session->Select(-1);
        Invalidate();
        return;
    }

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
        }
    }

    if (m_mode == Mode::Idle) {
        if (annot::Annotation* a =
                m_session->Annos().TopAt(Gdiplus::PointF((Gdiplus::REAL)pt.x,
                                                         (Gdiplus::REAL)pt.y))) {
            m_mode = Mode::MoveAnno;
            m_anno = a;
            m_annoIdx = m_session->Annos().IndexOf(a);
            m_annoBefore = a->Clone();
            m_session->Select(m_annoIdx);
        } else if (!sel.IsDefault() && sel.Contains(POINT{ pt.x, pt.y })) {
            m_mode = Mode::Moving;
        } else {
            m_mode = Mode::Creating;
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
    if (InLongShot()) return;
    SelectionModel& sel = m_session->Sel();
    switch (m_mode) {
    case Mode::Creating:
        sel.UpdateCreate(POINT{ pt.x, pt.y });
        LayoutChrome();
        Invalidate();
        break;
    case Mode::Moving: {
        RECT r = m_startRect;
        int dx = pt.x - m_dragStart.x;
        int dy = pt.y - m_dragStart.y;
        r.left += dx; r.top += dy; r.right += dx; r.bottom += dy;
        sel.MoveTo(r);
        LayoutChrome();
        Invalidate();
        break;
    }
    case Mode::Sizing:
        sel.Resize(m_handle, POINT{ pt.x, pt.y });
        LayoutChrome();
        Invalidate();
        break;
    case Mode::Drawing:
        if (m_pending)
            m_pending->UpdateDrag(
                Gdiplus::PointF((Gdiplus::REAL)pt.x, (Gdiplus::REAL)pt.y),
                (::GetKeyState(VK_SHIFT) & 0x8000) != 0);
        Invalidate();
        break;
    case Mode::MoveAnno:
        if (m_anno) {
            m_anno->Translate((Gdiplus::REAL)(pt.x - m_dragStart.x),
                              (Gdiplus::REAL)(pt.y - m_dragStart.y));
            m_dragStart = pt;  // the next delta is relative to this move
        }
        Invalidate();
        break;
    case Mode::DragHandle:
        if (m_anno)
            m_anno->MoveHandle(m_annoHandle,
                               Gdiplus::PointF((Gdiplus::REAL)pt.x, (Gdiplus::REAL)pt.y));
        Invalidate();
        break;
    case Mode::Idle:
        CursorMoved();
        break;
    }
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
        if (m_anno && m_annoBefore && !SameBox(m_annoBefore->BBox(), m_anno->BBox()))
            m_session->RecordMove(m_annoIdx, std::move(m_annoBefore));
        m_annoBefore.reset();
        m_anno = nullptr;
        m_annoIdx = m_annoHandle = -1;
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
        if (id == IDC_CROSS &&
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
