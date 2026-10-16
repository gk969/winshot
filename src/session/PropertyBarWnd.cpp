#include "stdafx.h"
#include "PropertyBarWnd.h"
#include "ToolbarWnd.h"
#include "Glyphs.h"
#include "CaptureSession.h"
#include "Dpi.h"

#include <algorithm>

const wchar_t kFontFace[] = L"Microsoft YaHei UI";

namespace {

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

BEGIN_MESSAGE_MAP(CPropertyBarWnd, CWnd)
    ON_WM_PAINT()
    ON_WM_ERASEBKGND()
    ON_WM_LBUTTONDOWN()
    ON_WM_LBUTTONUP()
    ON_WM_MOUSEMOVE()
END_MESSAGE_MAP()

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
        const int bh = Dpi::S(hwnd, tb::kFontBoxH);
        m_targets.push_back({ Kind::FontBox, 0,
                              RECT{ bx, (m_h - bh) / 2,
                                    bx + Dpi::S(hwnd, tb::kFontBoxW),
                                    (m_h - bh) / 2 + bh } });
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

// 文字-字体大小.png: `A`, then the current 字号 in a box whose ▼ opens the list
// the overlay draws. While the list is open the box takes the blue focused
// border and the ▼ flips to ▲.
void CPropertyBarWnd::DrawFontBox(Gdiplus::Graphics& g, const tb::Style& st) const {
    const HWND hwnd = GetSafeHwnd();
    const RECT& b = m_targets.front().rc;
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
    Gdiplus::Pen edge(open ? Gdiplus::Color(0xFF4279A6) : tb::kActiveBorder, 1.0f);
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
                const int d = Dpi::S(GetSafeHwnd(), tb::kDotSizes[i]);
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
    for (const Target& t : m_targets) {
        const RECT& r = t.rc;
        if (pt.x < r.left || pt.x >= r.right || pt.y < r.top || pt.y >= r.bottom)
            continue;
        if (t.kind == Kind::Slider) {
            // Grabbing the rail anywhere jumps the thumb there, then the drag
            // follows the pointer even past the bar's edges.
            m_sliding = true;
            ::SetCapture(GetSafeHwnd());
            SetBlurFromX(pt.x);
            return;
        }
        if (t.kind == Kind::FontBox) {
            // The list is the overlay's, so it can sit over the selection; the
            // bar only hands over where its own box ended.
            CRect box = t.rc;
            ClientToScreen(&box);
            m_session->ToggleFontDropdown(&box);
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
        return;
    }
}

void CPropertyBarWnd::OnLButtonUp(UINT, CPoint) {
    if (!m_sliding) return;
    m_sliding = false;
    if (::GetCapture() == GetSafeHwnd()) ::ReleaseCapture();
}
