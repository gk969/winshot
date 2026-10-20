#include "stdafx.h"
#include "PropertyBarWnd.h"
#include "ToolbarWnd.h"
#include "Glyphs.h"
#include "CaptureSession.h"
#include "Dpi.h"

#include <algorithm>

const wchar_t kFontFace[] = L"Microsoft YaHei UI";

namespace {

constexpr int kFontEditId = 91;

void RoundRectPath(Gdiplus::GraphicsPath& p, Gdiplus::REAL x, Gdiplus::REAL y,
                   Gdiplus::REAL w, Gdiplus::REAL h, Gdiplus::REAL r) {
    const Gdiplus::REAL d = 2 * r;
    p.AddArc(x, y, d, d, 180.0f, 90.0f);
    p.AddArc(x + w - d, y, d, d, 270.0f, 90.0f);
    p.AddArc(x + w - d, y + h - d, d, d, 0.0f, 90.0f);
    p.AddArc(x, y + h - d, d, d, 90.0f, 90.0f);
    p.CloseFigure();
}

}  // namespace

BEGIN_MESSAGE_MAP(CFontEdit, CEdit)
    ON_WM_CHAR()
END_MESSAGE_MAP()

void CFontEdit::OnChar(UINT nChar, UINT nRepCnt, UINT nFlags) {
    // ES_WANTRETURN is what gets the key here at all; without it a single-line
    // EDIT swallows Enter and the box can only ever be left to commit.
    if (nChar == VK_ESCAPE) {
        m_bar->FinishFontSizeEdit(false);
        return;
    }
    if (nChar == VK_RETURN || nChar == 10) {
        m_bar->FinishFontSizeEdit(true);
        return;
    }
    CEdit::OnChar(nChar, nRepCnt, nFlags);
}

// EN_KILLFOCUS goes to the control's parent, not to the control itself, so the
// bar — not CFontEdit — is the one that learns the number was left.
BEGIN_MESSAGE_MAP(CPropertyBarWnd, CWnd)
    ON_WM_PAINT()
    ON_WM_ERASEBKGND()
    ON_WM_LBUTTONDOWN()
    ON_WM_LBUTTONUP()
    ON_WM_MOUSEMOVE()
    ON_EN_KILLFOCUS(kFontEditId, &CPropertyBarWnd::OnEnKillFocus)
END_MESSAGE_MAP()

void CPropertyBarWnd::OnEnKillFocus() { FinishFontSizeEdit(true); }

BOOL CPropertyBarWnd::Create(CWnd* parent, CaptureSession* session) {
    m_session = session;

    LPCTSTR cls = AfxRegisterWndClass(0, ::LoadCursor(nullptr, IDC_ARROW),
                                      nullptr, nullptr);
    if (!cls) return FALSE;

    // Created hidden; the toolbar shows it when a tool becomes active.
    if (!CreateEx(0, cls, L"WinShotPropBar", WS_CHILD,
                  0, 0, 0, 0, parent->GetSafeHwnd(), nullptr))
        return FALSE;

    BuildLayout();
    return TRUE;
}

void CPropertyBarWnd::BuildLayout() {
    const HWND hwnd = GetSafeHwnd();
    m_h = Dpi::S(hwnd, tb::kPropHeight);

    const int box = Dpi::S(hwnd, tb::kDotBox);
    const int gridX = Dpi::S(hwnd, 119);
    const int sw = Dpi::S(hwnd, tb::kSwatch);
    const int swPitch = Dpi::S(hwnd, tb::kSwatchPitch);
    const int rowY = Dpi::S(hwnd, 5);
    const int rowPitch = Dpi::S(hwnd, 16);
    const int boxH = m_h - Dpi::S(hwnd, 7);

    m_layout = Layout::Shape;
    if (m_session) {
        const tb::Id tool = m_session->ActiveTool();
        if (tool == tb::Id::Text) m_layout = Layout::Text;
        else if (tool == tb::Id::Mosaic) m_layout = Layout::Mosaic;
    }

    m_targets.clear();
    if (m_layout == Layout::Text) {
        // 文字-字体大小.png: an A, then the 字号 box with its dropdown arrow.
        const int bx = Dpi::S(hwnd, tb::kFontBoxX);
        const int bw = Dpi::S(hwnd, tb::kFontBoxW);
        const int bh = Dpi::S(hwnd, tb::kFontBoxH);
        const int top = (m_h - bh) / 2;
        // One box, two targets. The ▼ strip opens the list the overlay draws;
        // the rest of the box is typed into. Splitting them is what lets a press
        // on the digits mean "type a size" rather than "toggle the list" — the
        // list only offers the even sizes, so the odd ones have to be typed.
        const int ax = bx + bw - Dpi::S(hwnd, tb::kFontArrowW);
        m_fontBox = RECT{ bx, top, bx + bw, top + bh };
        m_targets.push_back({ Kind::FontBox, 0, RECT{ bx, top, ax, top + bh } });
        m_targets.push_back({ Kind::FontArrow, 0, RECT{ ax, top, bx + bw, top + bh } });
    } else {
        for (int i = 0; i < 3; ++i) {
            const int cx = DotCentre(i);
            m_targets.push_back({ Kind::Dot, i,
                                  RECT{ cx - box / 2, (m_h - boxH) / 2,
                                        cx - box / 2 + box, (m_h - boxH) / 2 + boxH } });
        }
    }
    if (m_layout == Layout::Mosaic) {
        // 马赛克-鼠标拖动变模糊.png: the 模糊度 rail stands in for the palette.
        // The width dots stay — the band's width still comes from them.
        const int tx = Dpi::S(hwnd, tb::kMosaicTrackX);
        // The hit area is the whole bar height, not just the 14px the thumb
        // draws at — a 14px strip in a 37px bar is fiddly to grab.
        m_targets.push_back({ Kind::Slider, 0,
                              RECT{ tx, 0, tx + Dpi::S(hwnd, tb::kMosaicTrackW), m_h } });
        m_w = tx + Dpi::S(hwnd, tb::kMosaicTrackW) + Dpi::S(hwnd, 8);
        return;
    }

    for (int i = 0; i < 16; ++i) {
        const int x = gridX + (i % 8) * swPitch;
        const int y = rowY + (i / 8) * rowPitch;
        m_targets.push_back({ Kind::Swatch, i, RECT{ x, y, x + sw, y + sw } });
    }

    m_w = gridX + 7 * swPitch + sw + Dpi::S(hwnd, 9);
}

int CPropertyBarWnd::DotCentre(int i) const {
    return Dpi::S(GetSafeHwnd(), tb::kPropPad) +
           i * Dpi::S(GetSafeHwnd(), tb::kDotPitch);
}

int CPropertyBarWnd::SliderIndex() const {
    for (size_t i = 0; i < m_targets.size(); ++i)
        if (m_targets[i].kind == Kind::Slider) return (int)i;
    return -1;
}

void CPropertyBarWnd::Show(bool visible) {
    if (!GetSafeHwnd()) return;
    // A size typed but never committed is not one the user asked for, and the
    // box it was being typed into is going away with the tool.
    if (m_fonting && !visible) FinishFontSizeEdit(false);
    if (Visible() != visible) ShowWindow(visible ? SW_SHOWNA : SW_HIDE);
    m_sliding = false;
    // Rebuilt even when already shown: switching 矩形 -> 文字 keeps the bar
    // visible but swaps the width dots for the 字号 box.
    if (visible) BuildLayout();
}

bool CPropertyBarWnd::Visible() const {
    return GetSafeHwnd() ? ::IsWindowVisible(GetSafeHwnd()) != FALSE : false;
}

void CPropertyBarWnd::PlaceBelow(const CToolbarWnd* toolbar) {
    CWnd* parent = GetParent();
    if (!parent || !toolbar) return;

    CRect tb;
    toolbar->GetWindowRect(&tb);
    parent->ScreenToClient(tb);

    const int gap = Dpi::S(GetSafeHwnd(), tb::kGap);
    int x = tb.left;
    int y = tb.bottom + gap;

    CRect cl;
    parent->GetClientRect(&cl);
    if (x + m_w > cl.right) x = cl.right - m_w;
    if (x < cl.left) x = cl.left;

    MoveWindow(x, y, m_w, m_h);
}

void CPropertyBarWnd::Refresh() {
    if (GetSafeHwnd()) Invalidate();
}

void CPropertyBarWnd::BeginFontSizeEdit() {
    if (m_fonting || !m_session) return;
    // The input box takes keyboard focus, and taking it commits a text edit that
    // is running — which ends by deselecting its label. So the session has to be
    // told which label this size is for before any of that happens.
    m_session->BeginFontSizeEdit();
    OpenFontEdit(m_fontBox);
}

void CPropertyBarWnd::OpenFontEdit(const RECT& box) {
    const HWND hwnd = GetSafeHwnd();
    // Inside the box's own 1px edge so that border stays visible, and stopping
    // short of the ▼ so the list can still be opened while a size is being typed.
    CRect r(box.left + Dpi::S(hwnd, tb::kFontPad), box.top + 1,
            box.right - Dpi::S(hwnd, tb::kFontArrowW), box.bottom - 1);

    LOGFONT lf{};
    lf.lfHeight = -Dpi::S(hwnd, 12);
    lf.lfWeight = FW_NORMAL;
    lf.lfCharSet = DEFAULT_CHARSET;
    wcscpy_s(lf.lfFaceName, kFontFace);
    m_editFont.DeleteObject();
    if (!m_editFont.CreateFontIndirect(&lf)) return;

    CString s;
    s.Format(L"%d", m_session->Style().fontSize);

    m_fonting = true;
    m_fontEdit.Open(this);
    // ES_NUMBER so there is no sign, space or letter to reject afterwards; two
    // digits is as far as kFontMax reaches. Left-aligned at the same inset the
    // drawn digits use, so the number does not jump as it is typed.
    if (!m_fontEdit.CreateEx(0, L"EDIT", s,
                             WS_CHILD | WS_VISIBLE | ES_NUMBER | ES_AUTOHSCROLL |
                                 ES_WANTRETURN,
                             r, this, kFontEditId)) {
        m_fonting = false;
        return;
    }
    m_fontEdit.SetLimitText(2);
    m_fontEdit.SetFont(&m_editFont, TRUE);
    m_fontEdit.SetSel(0, -1);
    m_fontEdit.SetFocus();
    // The box takes the focused border the open list gets.
    Refresh();
}

void CPropertyBarWnd::FinishFontSizeEdit(bool commit) {
    if (!m_fonting) return;
    m_fonting = false;

    CString s;
    if (commit) m_fontEdit.GetWindowText(s);
    // Torn down before the session repaints: the control is what covers the box,
    // and the bar's own drawing of the number has to come back under it.
    m_fontEdit.DestroyWindow();

    // An empty box is the user having selected the number and typed nothing, not
    // a request for size zero: it leaves the size alone rather than clamping to
    // the bottom of the range.
    const bool has = commit && !s.IsEmpty();
    int px = m_session->Style().fontSize;
    if (has) px = std::clamp(_ttoi(s), tb::kFontMin, tb::kFontMax);
    m_session->EndFontSizeEdit(px, has);
    Refresh();
}

// 文字-字体大小.png: `A`, then the current 字号 in a box whose ▼ opens the list
// the overlay draws. While the list is open the box takes the blue focused
// border and the ▼ flips to ▲; a size being typed in gets the same border.
void CPropertyBarWnd::DrawFontBox(Gdiplus::Graphics& g, const tb::Style& st) const {
    const HWND hwnd = GetSafeHwnd();
    const RECT& b = m_fontBox;
    const bool open = m_session->FontDropdown() != nullptr;

    const int gs = Dpi::S(hwnd, tb::kGlyph);
    glyph::Draw(g, tb::Id::Text,
                Gdiplus::RectF((Gdiplus::REAL)(Dpi::S(hwnd, tb::kPropPad) - gs / 2),
                               (Gdiplus::REAL)((m_h - gs) / 2), (Gdiplus::REAL)gs,
                               (Gdiplus::REAL)gs),
                1.4f, tb::kInk);

    Gdiplus::SolidBrush fill(Gdiplus::Color(0xFFFFFFFF));
    g.FillRectangle(&fill, (Gdiplus::REAL)b.left, (Gdiplus::REAL)b.top,
                    (Gdiplus::REAL)(b.right - b.left), (Gdiplus::REAL)(b.bottom - b.top));
    Gdiplus::Pen edge(open || m_fonting ? Gdiplus::Color(0xFF4279A6)
                                        : tb::kActiveBorder,
                      1.0f);
    g.DrawRectangle(&edge, (Gdiplus::REAL)b.left + 0.5f, (Gdiplus::REAL)b.top + 0.5f,
                    (Gdiplus::REAL)(b.right - b.left) - 1.0f,
                    (Gdiplus::REAL)(b.bottom - b.top) - 1.0f);

    Gdiplus::FontFamily family(kFontFace);
    Gdiplus::Font font(&family, (Gdiplus::REAL)Dpi::S(hwnd, 12),
                       Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
    Gdiplus::SolidBrush fg(tb::kInk);
    Gdiplus::StringFormat fmt;
    fmt.SetAlignment(Gdiplus::StringAlignmentNear);
    fmt.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    CString s;
    s.Format(L"%d", st.fontSize);
    const int pad = Dpi::S(hwnd, tb::kFontPad);
    g.DrawString(s, -1, &font,
                 Gdiplus::RectF((Gdiplus::REAL)(b.left + pad),
                                (Gdiplus::REAL)b.top,
                                (Gdiplus::REAL)(b.right - b.left) - 2 * pad,
                                (Gdiplus::REAL)(b.bottom - b.top)),
                 &fmt, &fg);

    const int aw = Dpi::S(hwnd, 7);
    const int ah = Dpi::S(hwnd, 5);
    const int ax = b.right - Dpi::S(hwnd, tb::kFontArrow);
    const int ay = (m_h - ah) / 2;
    const Gdiplus::PointF tri[3] = {
        Gdiplus::PointF((Gdiplus::REAL)(ax - aw / 2), (Gdiplus::REAL)(open ? ay + ah : ay)),
        Gdiplus::PointF((Gdiplus::REAL)(ax + aw / 2), (Gdiplus::REAL)(open ? ay + ah : ay)),
        Gdiplus::PointF((Gdiplus::REAL)ax, (Gdiplus::REAL)(open ? ay : ay + ah)),
    };
    Gdiplus::SolidBrush ink(tb::kInk);
    g.FillPolygon(&ink, tri, 3);
}

// 马赛克-鼠标拖动变模糊.png: `模糊度` then a rail whose filled part ends at a
// white thumb; the block size the mosaic brush averages with rides on it.
void CPropertyBarWnd::DrawMosaicBar(Gdiplus::Graphics& g, const tb::Style& st) const {
    const HWND hwnd = GetSafeHwnd();
    const int si = SliderIndex();
    if (si < 0) return;
    const RECT& t = m_targets[si].rc;

    Gdiplus::FontFamily family(kFontFace);
    Gdiplus::Font font(&family, (Gdiplus::REAL)Dpi::S(hwnd, 13),
                       Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
    Gdiplus::SolidBrush ink(tb::kInk);
    Gdiplus::StringFormat fmt;
    fmt.SetAlignment(Gdiplus::StringAlignmentNear);
    fmt.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    g.DrawString(L"模糊度", 3, &font,
                 Gdiplus::RectF((Gdiplus::REAL)Dpi::S(hwnd, tb::kMosaicLabelX),
                                0.0f, (Gdiplus::REAL)(t.left - Dpi::S(hwnd, tb::kMosaicLabelX)),
                                (Gdiplus::REAL)m_h),
                 &fmt, &ink);

    const int trackH = Dpi::S(hwnd, tb::kMosaicTrackH);
    const int top = (m_h - trackH) / 2;
    const Gdiplus::REAL trackW = (Gdiplus::REAL)(t.right - t.left);
    const float f = (float)(st.blurBlockSize - tb::kBlurMin) /
                    (float)(tb::kBlurMax - tb::kBlurMin);
    const Gdiplus::REAL fillW = trackW * f;

    Gdiplus::SolidBrush rest(tb::kTrackRest);
    g.FillRectangle(&rest, (Gdiplus::REAL)t.left, (Gdiplus::REAL)top, trackW,
                    (Gdiplus::REAL)trackH);
    if (fillW > 0.5f) {
        Gdiplus::SolidBrush fill(tb::kTrackFill);
        g.FillRectangle(&fill, (Gdiplus::REAL)t.left, (Gdiplus::REAL)top, fillW,
                        (Gdiplus::REAL)trackH);
    }

    const int tw = Dpi::S(hwnd, tb::kMosaicThumbW);
    const int th = Dpi::S(hwnd, tb::kMosaicThumbH);
    const Gdiplus::REAL cx = (Gdiplus::REAL)t.left + fillW;
    Gdiplus::GraphicsPath thumb;
    RoundRectPath(thumb, cx - tw / 2.0f, (Gdiplus::REAL)((m_h - th) / 2),
                  (Gdiplus::REAL)tw, (Gdiplus::REAL)th,
                  (Gdiplus::REAL)Dpi::S(hwnd, 3));
    Gdiplus::SolidBrush white(0xFFFFFFFF);
    g.FillPath(&white, &thumb);
    Gdiplus::Pen edge(tb::kThumbEdge, 1.0f);
    g.DrawPath(&edge, &thumb);
}

void CPropertyBarWnd::OnPaint() {
    CPaintDC dc(this);
    CRect cl;
    GetClientRect(&cl);
    if (cl.Width() <= 0 || cl.Height() <= 0) return;

    const tb::Style& st = m_session->Style();

    Gdiplus::Bitmap back(cl.Width(), cl.Height(), PixelFormat32bppARGB);
    {
        Gdiplus::Graphics g(&back);
        g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);

        Gdiplus::SolidBrush bg(tb::kBack);
        g.FillRectangle(&bg, 0.0f, 0.0f, (Gdiplus::REAL)cl.Width(),
                        (Gdiplus::REAL)cl.Height());
        Gdiplus::Pen border(tb::kBorder, 1.0f);
        g.DrawRectangle(&border, 0.5f, 0.5f, (Gdiplus::REAL)cl.Width() - 1.0f,
                        (Gdiplus::REAL)cl.Height() - 1.0f);

        Gdiplus::Pen sep(tb::kSepLine, 1.0f);
        const int sepX = Dpi::S(GetSafeHwnd(), tb::kSepX);
        g.DrawLine(&sep, (Gdiplus::REAL)sepX + 0.5f, 6.0f,
                   (Gdiplus::REAL)sepX + 0.5f, (Gdiplus::REAL)cl.Height() - 6.0f);

        if (m_layout == Layout::Text) {
            DrawFontBox(g, st);
        } else {
            // Selected stroke width gets a frame, like the reference. The hit
            // target is a taller strip; the frame itself is square.
            const int box = Dpi::S(GetSafeHwnd(), tb::kDotBox);
            const int fx = DotCentre(st.widthIndex) - box / 2;
            const int fy = (m_h - box) / 2;
            Gdiplus::SolidBrush f(tb::kActive);
            g.FillRectangle(&f, (Gdiplus::REAL)fx, (Gdiplus::REAL)fy,
                            (Gdiplus::REAL)box, (Gdiplus::REAL)box);
            Gdiplus::Pen p(tb::kActiveBorder, 1.0f);
            g.DrawRectangle(&p, (Gdiplus::REAL)fx + 0.5f, (Gdiplus::REAL)fy + 0.5f,
                            (Gdiplus::REAL)box - 1.0f, (Gdiplus::REAL)box - 1.0f);

            Gdiplus::SolidBrush accent(tb::kAccent);
            for (int i = 0; i < 3; ++i) {
                const int d = Dpi::S(GetSafeHwnd(), tb::kDotDraw[i]);
                const int cx = DotCentre(i);
                g.FillEllipse(&accent, (Gdiplus::REAL)(cx - d / 2),
                              (Gdiplus::REAL)((m_h - d) / 2), (Gdiplus::REAL)d, (Gdiplus::REAL)d);
            }
        }

        if (m_layout == Layout::Mosaic) DrawMosaicBar(g, st);

        // Current colour, drawn large at the head of the palette. The mosaic
        // brush has no ink colour, so its bar has neither swatch nor palette.
        if (m_layout != Layout::Mosaic) {
            const int curX = Dpi::S(GetSafeHwnd(), tb::kCurrentX);
            const int cur = Dpi::S(GetSafeHwnd(), tb::kCurrentSwatch);
            const int rowY = Dpi::S(GetSafeHwnd(), 5);
            Gdiplus::SolidBrush c(st.Color());
            g.FillRectangle(&c, (Gdiplus::REAL)curX, (Gdiplus::REAL)rowY,
                            (Gdiplus::REAL)cur, (Gdiplus::REAL)cur);
            Gdiplus::Pen p(tb::kActiveBorder, 1.0f);
            g.DrawRectangle(&p, (Gdiplus::REAL)curX + 0.5f, (Gdiplus::REAL)rowY + 0.5f,
                            (Gdiplus::REAL)cur - 1.0f, (Gdiplus::REAL)cur - 1.0f);
        }

        Gdiplus::Pen ring(tb::kInk, 1.0f);
        for (const Target& t : m_targets) {
            if (t.kind != Kind::Swatch) continue;
            const RECT& r = t.rc;
            Gdiplus::SolidBrush c(tb::kPalette[t.index]);
            g.FillRectangle(&c, (Gdiplus::REAL)r.left, (Gdiplus::REAL)r.top,
                            (Gdiplus::REAL)(r.right - r.left),
                            (Gdiplus::REAL)(r.bottom - r.top));
            Gdiplus::Pen edge(tb::kBorder, 1.0f);
            g.DrawRectangle(&edge, (Gdiplus::REAL)r.left + 0.5f, (Gdiplus::REAL)r.top + 0.5f,
                            (Gdiplus::REAL)(r.right - r.left) - 1.0f,
                            (Gdiplus::REAL)(r.bottom - r.top) - 1.0f);
            if (t.index == st.colorIndex)
                g.DrawRectangle(&ring, (Gdiplus::REAL)r.left - 1.5f, (Gdiplus::REAL)r.top - 1.5f,
                                (Gdiplus::REAL)(r.right - r.left) + 2.0f,
                                (Gdiplus::REAL)(r.bottom - r.top) + 2.0f);
        }

        if (m_hot >= 0 && m_hot < (int)m_targets.size() &&
            m_targets[m_hot].kind != Kind::Slider) {
            const RECT& r = m_targets[m_hot].rc;
            Gdiplus::Pen hot(tb::kInk, 1.0f);
            g.DrawRectangle(&hot, (Gdiplus::REAL)r.left - 0.5f, (Gdiplus::REAL)r.top - 0.5f,
                            (Gdiplus::REAL)(r.right - r.left) + 1.0f,
                            (Gdiplus::REAL)(r.bottom - r.top) + 1.0f);
        }
    }
    {
        Gdiplus::Graphics g(dc.GetSafeHdc());
        g.SetInterpolationMode(Gdiplus::InterpolationModeNearestNeighbor);
        g.DrawImage(&back, 0, 0, cl.Width(), cl.Height());
    }
}

BOOL CPropertyBarWnd::OnEraseBkgnd(CDC*) {
    return TRUE;
}

void CPropertyBarWnd::SetBlurFromX(int x) {
    const int si = SliderIndex();
    if (si < 0 || !m_session) return;
    const RECT& t = m_targets[si].rc;
    const int span = t.right - t.left;
    if (span <= 0) return;

    const int at = std::clamp<int>(x - t.left, 0, span);
    const int blur = tb::kBlurMin +
                     (int)((double)at * (tb::kBlurMax - tb::kBlurMin) / span + 0.5);
    tb::Style& st = m_session->Style();
    if (st.blurBlockSize == blur) return;
    st.blurBlockSize = blur;
    Refresh();
}

void CPropertyBarWnd::OnMouseMove(UINT, CPoint pt) {
    if (m_session) m_session->Overlay().CursorMoved();
    if (m_sliding) {
        SetBlurFromX(pt.x);
        return;
    }
    int hit = -1;
    for (size_t i = 0; i < m_targets.size(); ++i) {
        const RECT& r = m_targets[i].rc;
        if (pt.x >= r.left && pt.x < r.right && pt.y >= r.top && pt.y < r.bottom) {
            hit = (int)i;
            break;
        }
    }
    if (hit != m_hot) {
        m_hot = hit;
        Invalidate();
    }
}

void CPropertyBarWnd::OnLButtonDown(UINT, CPoint pt) {
    int hit = -1;
    for (size_t i = 0; i < m_targets.size(); ++i) {
        const RECT& r = m_targets[i].rc;
        if (pt.x >= r.left && pt.x < r.right && pt.y >= r.top && pt.y < r.bottom) {
            hit = (int)i;
            break;
        }
    }
    if (hit < 0) return;
    // Copied, not referenced: a handler below can rebuild m_targets (the bar is
    // re-shown as the chrome settles), which would leave a reference dangling.
    const Target t = m_targets[hit];
    // A press anywhere in the bar means the user has moved on from the number;
    // it is taken as committed, the same as leaving the box.
    if (m_fonting) FinishFontSizeEdit(true);

    if (t.kind == Kind::Slider) {
        // Grabbing the rail anywhere jumps the thumb there, then the drag
        // follows the pointer even past the bar's edges.
        m_sliding = true;
        ::SetCapture(GetSafeHwnd());
        SetBlurFromX(pt.x);
        return;
    }
    if (t.kind == Kind::FontArrow) {
        // The list is the overlay's, so it can sit over the selection; the bar
        // only hands over where its own box ended — the whole box, not the strip.
        CRect box = m_fontBox;
        ClientToScreen(&box);
        m_session->ToggleFontDropdown(&box);
        return;
    }
    if (t.kind == Kind::FontBox) {
        BeginFontSizeEdit();
        return;
    }
    tb::Style& st = m_session->Style();
    if (t.kind == Kind::Dot) st.widthIndex = t.index;
    else st.colorIndex = t.index;
    // A shape already on the canvas and selected takes the pick with it;
    // with nothing selected this only sets what the next shape is drawn with.
    m_session->ApplyStyleToSelected();
    m_session->HideFontDropdown();
    Refresh();
}

void CPropertyBarWnd::OnLButtonUp(UINT, CPoint) {
    if (!m_sliding) return;
    m_sliding = false;
    if (::GetCapture() == GetSafeHwnd()) ::ReleaseCapture();
}
