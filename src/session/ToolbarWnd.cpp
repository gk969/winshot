#include "stdafx.h"
#include "ToolbarWnd.h"
#include "Glyphs.h"
#include "CaptureSession.h"
#include "Dpi.h"

namespace {

const wchar_t kFontFace[] = L"Microsoft YaHei UI";

const UINT_PTR kTipTimer = 1;
const int kTipDelay = 120;   // ms of hover before the card appears

struct Slot {
    tb::Id id;
    const wchar_t* tip;
    const wchar_t* label;
    bool sep;
};

// Slot order straight from 工具栏.png, minus the two icons no reference
// demonstrates and with the reference's two OCR glyphs merged into one.
const Slot kSlots[] = {
    { tb::Id::Rect,     L"矩形工具",        nullptr,   false },
    { tb::Id::Ellipse,  L"椭圆工具",        nullptr,   false },
    { tb::Id::Arrow,    L"箭头工具",        nullptr,   false },
    { tb::Id::Pen,      L"画笔工具",        nullptr,   false },
    { tb::Id::Mosaic,   L"马赛克工具",      nullptr,   false },
    { tb::Id::Text,     L"文字工具",        nullptr,   false },
    { tb::Id::Badge,    L"序号工具",        nullptr,   false },
    { tb::Id::None,     nullptr,           nullptr,   true  },
    { tb::Id::Undo,     L"撤销编辑 Ctrl+Z", nullptr,   false },
    { tb::Id::LongShot, L"长截图",          nullptr,   false },
    { tb::Id::Ocr,      L"OCR 识字",        nullptr,   false },
    { tb::Id::Pin,      L"钉在桌面上",      nullptr,   false },
    { tb::Id::Record,   L"屏幕录制",        nullptr,   false },
    { tb::Id::Save,     L"保存 Ctrl+S",     nullptr,   false },
    { tb::Id::None,     nullptr,           nullptr,   true  },
    { tb::Id::Cancel,   L"退出截图",        nullptr,   false },
    { tb::Id::Done,     L"完成截图",        L"完成",   false },
};

bool IsEnabled(CaptureSession* session, tb::Id id) {
    if (id == tb::Id::Record) return false;  // recording is out of scope this round
    // A second OCR while the first is still running only queues more work.
    return id != tb::Id::Ocr || !(session && session->OcrBusy());
}

}  // namespace

BEGIN_MESSAGE_MAP(CToolbarWnd, CWnd)
    ON_WM_PAINT()
    ON_WM_ERASEBKGND()
    ON_WM_LBUTTONDOWN()
    ON_WM_LBUTTONUP()
    ON_WM_MOUSEMOVE()
    ON_WM_MOUSELEAVE()
    ON_WM_TIMER()
END_MESSAGE_MAP()

BOOL CToolbarWnd::Create(CWnd* parent, CaptureSession* session) {
    m_session = session;

    LPCTSTR cls = AfxRegisterWndClass(0, ::LoadCursor(nullptr, IDC_ARROW),
                                      nullptr, nullptr);
    if (!cls) return FALSE;

    if (!CreateEx(0, cls, L"WinShotToolbar", WS_CHILD | WS_VISIBLE,
                  0, 0, 0, 0, parent->GetSafeHwnd(), nullptr))
        return FALSE;

    BuildLayout();
    return TRUE;
}

void CToolbarWnd::BuildLayout() {
    const HWND hwnd = GetSafeHwnd();
    m_h = Dpi::S(hwnd, tb::kHeight);
    m_cell = Dpi::S(hwnd, tb::kCell);
    m_glyph = Dpi::S(hwnd, tb::kGlyph);
    m_pad = Dpi::S(hwnd, tb::kPad);
    const int sepW = Dpi::S(hwnd, tb::kSep);

    Gdiplus::Bitmap tmp(1, 1, PixelFormat32bppARGB);
    Gdiplus::Graphics mg(&tmp);
    Gdiplus::FontFamily family(kFontFace);
    Gdiplus::Font font(&family, (Gdiplus::REAL)Dpi::S(hwnd, 12),
                       Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);

    m_items.clear();
    m_seps.clear();
    int x = m_pad;
    for (const Slot& s : kSlots) {
        if (s.sep) {
            m_seps.push_back(x + sepW / 2);
            x += sepW;
            continue;
        }
        Item it{ s.id, s.tip, s.label, x, m_cell };
        if (s.label) {
            Gdiplus::RectF r;
            mg.MeasureString(s.label, -1, &font, Gdiplus::PointF(0, 0), &r);
            it.w = m_cell + (int)std::ceil(r.Width) + Dpi::S(hwnd, 4);
        }
        m_items.push_back(it);
        x += it.w;
    }
    m_w = x + m_pad;
}

void CToolbarWnd::Place(int belowHeight) {
    CWnd* parent = GetParent();
    if (!parent || !m_session) return;

    CRect cl;
    parent->GetClientRect(&cl);
    const RECT s = m_session->Sel().Rect();
    const int gap = Dpi::S(GetSafeHwnd(), tb::kGap);
    const int block = m_h + (belowHeight > 0 ? gap + belowHeight : 0);

    int y = s.bottom + gap;
    if (y + block > cl.bottom) y = s.top - gap - block;
    if (y < cl.top) y = cl.bottom - block - gap;

    int x = s.left;
    if (x + m_w > cl.right) x = cl.right - m_w;
    if (x < cl.left) x = cl.left;

    CRect cur;
    GetWindowRect(&cur);
    parent->ScreenToClient(cur);
    if (cur.left == x && cur.top == y) return;
    // The card is anchored to the old position.
    ::KillTimer(GetSafeHwnd(), kTipTimer);
    HideTip();
    MoveWindow(x, y, m_w, m_h);
}

void CToolbarWnd::Refresh() {
    if (GetSafeHwnd()) Invalidate();
}

int CToolbarWnd::HitTest(CPoint pt) const {
    for (size_t i = 0; i < m_items.size(); ++i) {
        const Item& it = m_items[i];
        if (pt.x >= it.x && pt.x < it.x + it.w && pt.y >= 0 && pt.y < m_h)
            return (int)i;
    }
    return -1;
}

void CToolbarWnd::SetHot(int idx) {
    if (idx == m_hot) return;
    m_hot = idx;
    Invalidate();

    ::KillTimer(GetSafeHwnd(), kTipTimer);
    HideTip();
    if (idx >= 0 && m_items[idx].tip)
        ::SetTimer(GetSafeHwnd(), kTipTimer, kTipDelay, nullptr);
}

void CToolbarWnd::OnTimer(UINT_PTR id) {
    if (id != kTipTimer) {
        CWnd::OnTimer(id);
        return;
    }
    ::KillTimer(GetSafeHwnd(), kTipTimer);
    ShowTip(m_hot);
}

void CToolbarWnd::ShowTip(int idx) {
    if (!m_session || idx < 0 || idx >= (int)m_items.size()) return;

    CRect wr;
    GetWindowRect(&wr);
    const Item& it = m_items[idx];
    m_session->ShowTip(it.tip, CPoint(wr.left + it.x + it.w / 2,
                                      wr.bottom + Dpi::S(GetSafeHwnd(), 4)));
}

void CToolbarWnd::HideTip() {
    if (m_session) m_session->HideTip();
}

void CToolbarWnd::OnPaint() {
    CPaintDC dc(this);
    CRect cl;
    GetClientRect(&cl);
    if (cl.Width() <= 0 || cl.Height() <= 0) return;

    const tb::Id active = m_session ? m_session->ActiveTool() : tb::Id::None;

    Gdiplus::Bitmap back(cl.Width(), cl.Height(), PixelFormat32bppARGB);
    {
        Gdiplus::Graphics g(&back);
        g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
        g.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);

        Gdiplus::SolidBrush bg(tb::kBack);
        g.FillRectangle(&bg, 0.0f, 0.0f, (Gdiplus::REAL)cl.Width(),
                        (Gdiplus::REAL)cl.Height());
        Gdiplus::Pen border(tb::kBorder, 1.0f);
        g.DrawRectangle(&border, 0.5f, 0.5f, (Gdiplus::REAL)cl.Width() - 1.0f,
                        (Gdiplus::REAL)cl.Height() - 1.0f);

        Gdiplus::Pen sep(tb::kSepLine, 1.0f);
        for (int sx : m_seps)
            g.DrawLine(&sep, (Gdiplus::REAL)sx + 0.5f, 6.0f,
                       (Gdiplus::REAL)sx + 0.5f, (Gdiplus::REAL)cl.Height() - 6.0f);

        for (const Item& it : m_items) DrawButton(g, it, active);
    }
    {
        Gdiplus::Graphics g(dc.GetSafeHdc());
        g.SetInterpolationMode(Gdiplus::InterpolationModeNearestNeighbor);
        g.DrawImage(&back, 0, 0, cl.Width(), cl.Height());
    }
}

void CToolbarWnd::DrawButton(Gdiplus::Graphics& g, const Item& it, tb::Id active) {
    int idx = (int)(&it - m_items.data());
    const bool enabled = IsEnabled(m_session, it.id);
    const bool isActive = enabled && it.id == active;
    const bool isHot = enabled && idx == m_hot;
    const bool isDown = enabled && idx == m_pressed;

    const Gdiplus::REAL bx = (Gdiplus::REAL)it.x + 1.0f;
    const Gdiplus::REAL bw = (Gdiplus::REAL)it.w - 2.0f;
    const Gdiplus::REAL by = 2.0f;
    const Gdiplus::REAL bh = (Gdiplus::REAL)m_h - 4.0f;

    if (isActive) {
        Gdiplus::SolidBrush f(tb::kActive);
        g.FillRectangle(&f, bx, by, bw, bh);
        Gdiplus::Pen p(tb::kActiveBorder, 1.0f);
        g.DrawRectangle(&p, bx + 0.5f, by + 0.5f, bw - 1.0f, bh - 1.0f);
    } else if (isDown || isHot) {
        Gdiplus::SolidBrush f(isDown ? tb::kPressed : tb::kHot);
        g.FillRectangle(&f, bx, by, bw, bh);
    }

    const int gx = it.x + (m_cell - m_glyph) / 2;
    Gdiplus::RectF box((Gdiplus::REAL)gx, (Gdiplus::REAL)((m_h - m_glyph) / 2),
                       (Gdiplus::REAL)m_glyph, (Gdiplus::REAL)m_glyph);
    const Gdiplus::Color ink = enabled ? tb::kInk : tb::kDisabled;
    glyph::Draw(g, it.id, box, (Gdiplus::REAL)m_glyph * 0.095f, ink);

    if (it.label) {
        Gdiplus::FontFamily family(kFontFace);
        Gdiplus::Font font(&family, (Gdiplus::REAL)Dpi::S(GetSafeHwnd(), 12),
                           Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
        Gdiplus::SolidBrush fg(ink);
        Gdiplus::RectF area((Gdiplus::REAL)(it.x + m_cell), 0.0f,
                            (Gdiplus::REAL)(it.w - m_cell), (Gdiplus::REAL)m_h);
        Gdiplus::StringFormat fmt;
        fmt.SetAlignment(Gdiplus::StringAlignmentCenter);
        fmt.SetLineAlignment(Gdiplus::StringAlignmentCenter);
        g.DrawString(it.label, -1, &font, area, &fmt, &fg);
    }
}

BOOL CToolbarWnd::OnEraseBkgnd(CDC*) {
    return TRUE;
}

void CToolbarWnd::OnMouseMove(UINT, CPoint pt) {
    // Our mouse moves never reach the overlay, so it would keep the magnifier
    // drawn under us; tell it the cursor is here instead.
    if (m_session) m_session->Overlay().CursorMoved();
    // m_pressed is -1 when nothing is down, so a plain ! test would be false.
    if (m_pressed < 0) SetHot(HitTest(pt));

    TRACKMOUSEEVENT tme{ sizeof(tme), TME_LEAVE, GetSafeHwnd(), 0 };
    ::TrackMouseEvent(&tme);
}

void CToolbarWnd::OnMouseLeave() {
    ::KillTimer(GetSafeHwnd(), kTipTimer);
    HideTip();
    m_hot = -1;
    Invalidate();
}

void CToolbarWnd::OnLButtonDown(UINT, CPoint pt) {
    ::KillTimer(GetSafeHwnd(), kTipTimer);
    HideTip();
    m_pressed = HitTest(pt);
    if (m_pressed >= 0 && IsEnabled(m_session, m_items[m_pressed].id)) {
        ::SetCapture(GetSafeHwnd());
        Invalidate();
    } else {
        m_pressed = -1;
    }
}

void CToolbarWnd::OnLButtonUp(UINT, CPoint pt) {
    const int idx = m_pressed;
    m_pressed = -1;
    ::ReleaseCapture();
    if (idx < 0) return;

    Invalidate();
    if (HitTest(pt) == idx) m_session->OnToolbar(m_items[idx].id);
}
