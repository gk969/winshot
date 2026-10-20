#include "stdafx.h"
#include "LongShot.h"

#include "AppMessages.h"
#include "CaptureSession.h"
#include "Dpi.h"
#include "Glyphs.h"
#include "OverlayWnd.h"
#include "out/ClipboardImage.h"
#include "out/Export.h"

#include <algorithm>
#include <cstring>

namespace {

const wchar_t kFontFace[] = L"Microsoft YaHei UI";

const UINT_PTR kPollTimer = 1;
const int kPollMs = 150;

// How far one wheel notch moves an ordinary page, in px. The allowance is
// measured in notches against m_maxStep, the largest shift one Tick can still
// match, so a short selection — where m_maxStep is small — gets a smaller
// allowance rather than the same fixed number that overshoots it.
constexpr int kNotchPx = 140;

// Bar geometry measured off 长截图-点击后.png: 161x32, the 编辑 label, a
// divider at 40, three 28px icon slots, then the 完成 label.
constexpr int kBarW = 161, kBarH = 32;
constexpr int kTipW = 260, kTipH = 50;

// Below these the overlap band is too short for the row signatures to tell a
// scroll from a repaint.
constexpr int kMinW = 60, kMinH = 120;
constexpr int kMaxTail = 160;
constexpr int kMaxHeight = 30000;
constexpr size_t kMaxBytes = 256ull << 20;

const Gdiplus::Color kFrame(0xFF1E9FD4);

struct BarSlot {
    tb::Id id;
    const wchar_t* label;
    int x, w;
    int glyphX;        // -1 when the slot is text only
    int labelX, labelW;
};

const BarSlot kSlots[] = {
    { tb::Id::None,   L"编辑", 4,  36, -1,  4,   36 },
    { tb::Id::Save,   nullptr, 41, 28, 47,  0,   0  },
    { tb::Id::Cancel, nullptr, 69, 28, 75,  0,   0  },
    { tb::Id::Done,   L"完成", 97, 64, 103, 125, 36 },
};

constexpr int kSepX = 40;

}  // namespace

// ---------------------------------------------------------------- 长截图 bar

class CBarWnd : public CWnd {
public:
    BOOL Create(ls::Controller* ctl);
    // hole is in screen coordinates; the bar is a top-level window.
    void Place(const CRect& hole);
    void SetPolling(bool on);

protected:
    afx_msg void OnPaint();
    afx_msg BOOL OnEraseBkgnd(CDC* dc);
    afx_msg void OnLButtonDown(UINT nFlags, CPoint pt);
    afx_msg void OnLButtonUp(UINT nFlags, CPoint pt);
    afx_msg void OnMouseMove(UINT nFlags, CPoint pt);
    afx_msg void OnMouseLeave();
    afx_msg void OnTimer(UINT_PTR nIDEvent);
    // A top-level window managed by a smart pointer: the default deletes this.
    void PostNcDestroy() override {}
    DECLARE_MESSAGE_MAP()

private:
    struct Slot {
        tb::Id id = tb::Id::None;
        const wchar_t* label = nullptr;
        int x = 0, w = 0;
        int glyphX = -1;
        int labelX = 0, labelW = 0;
    };

    void BuildLayout();
    int HitTest(CPoint pt) const;
    void SetHot(int idx);
    void DrawSlot(Gdiplus::Graphics& g, int idx);

    ls::Controller* m_ctl = nullptr;
    std::vector<Slot> m_slots;
    int m_w = 0, m_h = 0, m_glyph = 0, m_sepX = 0;
    int m_hot = -1, m_pressed = -1;
};

BEGIN_MESSAGE_MAP(CBarWnd, CWnd)
    ON_WM_PAINT()
    ON_WM_ERASEBKGND()
    ON_WM_LBUTTONDOWN()
    ON_WM_LBUTTONUP()
    ON_WM_MOUSEMOVE()
    ON_WM_MOUSELEAVE()
    ON_WM_TIMER()
END_MESSAGE_MAP()

BOOL CBarWnd::Create(ls::Controller* ctl) {
    m_ctl = ctl;

    LPCTSTR cls = AfxRegisterWndClass(0, ::LoadCursor(nullptr, IDC_ARROW),
                                      nullptr, nullptr);
    if (!cls) return FALSE;

    // A top-level popup rather than an overlay child: the overlay's window
    // region clips children, and the bar hangs below the hole.
    if (!CreateEx(WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW, cls,
                  L"WinShotLongBar", WS_POPUP, 0, 0, 0, 0, nullptr, nullptr))
        return FALSE;

    BuildLayout();
    ShowWindow(SW_SHOWNA);
    return TRUE;
}

void CBarWnd::BuildLayout() {
    const HWND hwnd = GetSafeHwnd();
    m_h = Dpi::S(hwnd, kBarH);
    m_w = Dpi::S(hwnd, kBarW);
    m_glyph = Dpi::S(hwnd, tb::kGlyph);
    m_sepX = Dpi::S(hwnd, kSepX);

    m_slots.clear();
    for (const BarSlot& s : kSlots) {
        Slot it{};
        it.id = s.id;
        it.label = s.label;
        it.x = Dpi::S(hwnd, s.x);
        it.w = Dpi::S(hwnd, s.w);
        it.glyphX = s.glyphX < 0 ? -1 : Dpi::S(hwnd, s.glyphX);
        it.labelX = Dpi::S(hwnd, s.labelX);
        it.labelW = Dpi::S(hwnd, s.labelW);
        m_slots.push_back(it);
    }
}

void CBarWnd::Place(const CRect& hole) {
    if (!GetSafeHwnd()) return;

    const RECT vs = Dpi::VirtualScreen();
    int x = hole.right - Dpi::S(GetSafeHwnd(), 2) - m_w;
    int y = hole.bottom + Dpi::S(GetSafeHwnd(), 5);
    if (y + m_h > vs.bottom) y = hole.top - Dpi::S(GetSafeHwnd(), 5) - m_h;
    if (y < vs.top) y = vs.bottom - m_h - Dpi::S(GetSafeHwnd(), 5);
    if (x < vs.left) x = vs.left;

    CRect cur;
    GetWindowRect(&cur);
    if (cur.left == x && cur.top == y) return;
    MoveWindow(x, y, m_w, m_h);
}

void CBarWnd::SetPolling(bool on) {
    const HWND hwnd = GetSafeHwnd();
    if (!hwnd) return;
    if (on) ::SetTimer(hwnd, kPollTimer, kPollMs, nullptr);
    else ::KillTimer(hwnd, kPollTimer);
}

int CBarWnd::HitTest(CPoint pt) const {
    for (size_t i = 0; i < m_slots.size(); ++i) {
        const Slot& it = m_slots[i];
        if (pt.x >= it.x && pt.x < it.x + it.w && pt.y >= 0 && pt.y < m_h)
            return (int)i;
    }
    return -1;
}

void CBarWnd::SetHot(int idx) {
    if (idx == m_hot) return;
    m_hot = idx;
    Invalidate();
}

void CBarWnd::OnPaint() {
    CPaintDC dc(this);
    CRect cl;
    GetClientRect(&cl);
    if (cl.Width() <= 0 || cl.Height() <= 0) return;

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
        g.DrawLine(&sep, (Gdiplus::REAL)m_sepX + 0.5f, 6.0f,
                   (Gdiplus::REAL)m_sepX + 0.5f, (Gdiplus::REAL)cl.Height() - 6.0f);

        for (int i = 0; i < (int)m_slots.size(); ++i) DrawSlot(g, i);
    }
    {
        Gdiplus::Graphics g(dc.GetSafeHdc());
        g.SetInterpolationMode(Gdiplus::InterpolationModeNearestNeighbor);
        g.DrawImage(&back, 0, 0, cl.Width(), cl.Height());
    }
}

void CBarWnd::DrawSlot(Gdiplus::Graphics& g, int idx) {
    const Slot& it = m_slots[idx];

    if (idx == m_pressed || idx == m_hot) {
        Gdiplus::SolidBrush f(idx == m_pressed ? tb::kPressed : tb::kHot);
        g.FillRectangle(&f, (Gdiplus::REAL)it.x + 1.0f, 2.0f,
                        (Gdiplus::REAL)it.w - 2.0f, (Gdiplus::REAL)m_h - 4.0f);
    }

    if (it.glyphX >= 0) {
        Gdiplus::RectF box((Gdiplus::REAL)it.glyphX,
                           (Gdiplus::REAL)((m_h - m_glyph) / 2),
                           (Gdiplus::REAL)m_glyph, (Gdiplus::REAL)m_glyph);
        glyph::Draw(g, it.id, box, (Gdiplus::REAL)m_glyph * 0.095f, tb::kInk);
    }

    if (it.label) {
        Gdiplus::FontFamily family(kFontFace);
        Gdiplus::Font font(&family, (Gdiplus::REAL)Dpi::S(GetSafeHwnd(), 12),
                           Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
        Gdiplus::SolidBrush ink(tb::kInk);
        Gdiplus::RectF area((Gdiplus::REAL)it.labelX, 0.0f,
                            (Gdiplus::REAL)it.labelW, (Gdiplus::REAL)m_h);
        Gdiplus::StringFormat fmt;
        fmt.SetAlignment(Gdiplus::StringAlignmentCenter);
        fmt.SetLineAlignment(Gdiplus::StringAlignmentCenter);
        g.DrawString(it.label, -1, &font, area, &fmt, &ink);
    }
}

BOOL CBarWnd::OnEraseBkgnd(CDC*) {
    return TRUE;
}

void CBarWnd::OnMouseMove(UINT, CPoint pt) {
    if (m_pressed < 0) SetHot(HitTest(pt));
    TRACKMOUSEEVENT tme{ sizeof(tme), TME_LEAVE, GetSafeHwnd(), 0 };
    ::TrackMouseEvent(&tme);
}

void CBarWnd::OnMouseLeave() {
    m_hot = -1;
    Invalidate();
}

void CBarWnd::OnLButtonDown(UINT, CPoint pt) {
    m_pressed = HitTest(pt);
    if (m_pressed >= 0) {
        ::SetCapture(GetSafeHwnd());
        Invalidate();
    }
}

void CBarWnd::OnLButtonUp(UINT, CPoint pt) {
    const int idx = m_pressed;
    m_pressed = -1;
    ::ReleaseCapture();
    if (idx < 0 || HitTest(pt) != idx) return;

    Invalidate();
    switch (m_slots[idx].id) {
    case tb::Id::Save:   m_ctl->OnSave(); break;
    case tb::Id::Cancel: m_ctl->OnCancel(); break;
    case tb::Id::Done:   m_ctl->OnDone(); break;
    default:             m_ctl->OnEdit(); break;  // 编辑
    }
}

void CBarWnd::OnTimer(UINT_PTR id) {
    if (id != kPollTimer) {
        CWnd::OnTimer(id);
        return;
    }
    m_ctl->Tick();
}

// ------------------------------------------------------- the 提示 card in the hole

class CTipWnd : public CWnd {
public:
    BOOL Create();
    void Place(const CRect& hole);
    void SetText(const wchar_t* text);
    void HideForGrab();
    void ShowAgain();

protected:
    afx_msg void OnPaint();
    afx_msg BOOL OnEraseBkgnd(CDC* dc);
    void PostNcDestroy() override {}
    DECLARE_MESSAGE_MAP()

private:
    CString m_text;
    int m_w = 0, m_h = 0;
    bool m_wasShown = false;
};

BEGIN_MESSAGE_MAP(CTipWnd, CWnd)
    ON_WM_PAINT()
    ON_WM_ERASEBKGND()
END_MESSAGE_MAP()

BOOL CTipWnd::Create() {
    LPCTSTR cls = AfxRegisterWndClass(0, nullptr, nullptr, nullptr);
    if (!cls) return FALSE;

    // WS_EX_TRANSPARENT so the card never eats the wheel or the click the tip
    // itself is telling the user to send to the window underneath.
    if (!CreateEx(WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TRANSPARENT,
                  cls, L"WinShotLongTip", WS_POPUP, 0, 0, 0, 0, nullptr, nullptr))
        return FALSE;

    m_w = Dpi::S(GetSafeHwnd(), kTipW);
    m_h = Dpi::S(GetSafeHwnd(), kTipH);
    return TRUE;
}

void CTipWnd::SetText(const wchar_t* text) {
    m_text = text;
    if (GetSafeHwnd()) Invalidate();
}

void CTipWnd::Place(const CRect& hole) {
    if (!GetSafeHwnd()) return;

    const CPoint c = hole.CenterPoint();
    // CRect/CPoint members are LONG; the literals are int.
    int x = (int)c.x - m_w / 2, y = (int)c.y - m_h / 2;
    x = (std::max)((int)hole.left, (std::min)(x, (int)hole.right - m_w));
    y = (std::max)((int)hole.top, (std::min)(y, (int)hole.bottom - m_h));
    if (hole.Width() < m_w) x = hole.left;
    if (hole.Height() < m_h) y = hole.top;

    MoveWindow(x, y, m_w, m_h);
    ShowWindow(SW_SHOWNA);
}

// The card sits inside the hole, so a grab would stitch it into the document.
// Hiding it is not enough on its own: the pixels it covered stay on screen
// until the window below repaints them, which is exactly what we then copy.
void CTipWnd::HideForGrab() {
    const HWND hwnd = GetSafeHwnd();
    m_wasShown = hwnd && ::IsWindowVisible(hwnd);
    if (!m_wasShown) return;

    CRect wr;
    GetWindowRect(&wr);
    ShowWindow(SW_HIDE);

    POINT mid = { wr.CenterPoint().x, wr.CenterPoint().y };
    HWND under = ::WindowFromPoint(mid);
    ::RedrawWindow(under && under != hwnd ? under : nullptr, &wr, nullptr,
                   RDW_INVALIDATE | RDW_UPDATENOW | RDW_ALLCHILDREN);
}

void CTipWnd::ShowAgain() {
    if (m_wasShown && GetSafeHwnd()) ShowWindow(SW_SHOWNA);
}

void CTipWnd::OnPaint() {
    CPaintDC dc(this);
    CRect cl;
    GetClientRect(&cl);
    if (cl.Width() <= 0 || cl.Height() <= 0) return;

    Gdiplus::Bitmap back(cl.Width(), cl.Height(), PixelFormat32bppARGB);
    {
        Gdiplus::Graphics g(&back);
        g.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);

        // The card in 长截图.png is a dark card that gets slightly lighter
        // towards its bottom edge.
        Gdiplus::RectF r(0.0f, 0.0f, (Gdiplus::REAL)cl.Width(), (Gdiplus::REAL)cl.Height());
        Gdiplus::LinearGradientBrush bg(r, Gdiplus::Color(0xFF252525),
                                        Gdiplus::Color(0xFF4A4A4A),
                                        Gdiplus::LinearGradientModeVertical);
        g.FillRectangle(&bg, r);

        Gdiplus::FontFamily family(kFontFace);
        Gdiplus::Font font(&family, (Gdiplus::REAL)Dpi::S(GetSafeHwnd(), 15),
                           Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
        Gdiplus::SolidBrush ink(Gdiplus::Color(0xFFFFFFFF));
        Gdiplus::StringFormat fmt;
        fmt.SetAlignment(Gdiplus::StringAlignmentCenter);
        fmt.SetLineAlignment(Gdiplus::StringAlignmentCenter);
        g.DrawString(m_text, -1, &font, r, &fmt, &ink);
    }
    {
        Gdiplus::Graphics g(dc.GetSafeHdc());
        g.SetInterpolationMode(Gdiplus::InterpolationModeNearestNeighbor);
        g.DrawImage(&back, 0, 0, cl.Width(), cl.Height());
    }
}

BOOL CTipWnd::OnEraseBkgnd(CDC*) {
    return TRUE;
}

// --------------------------------------------------------------- the controller

namespace ls {

Controller::Controller(CaptureSession* session) : m_session(session) {}

Controller* Controller::s_ctl = nullptr;
HHOOK Controller::s_hook = nullptr;

LRESULT CALLBACK Controller::WheelHook(int code, WPARAM wp, LPARAM lp) {
    // Windows 10 sends the wheel to whatever the cursor is over, not to the
    // focused window, and inside the hole the overlay is hit-test transparent —
    // so a notch aimed at the page never reaches any handler of ours and cannot
    // be throttled from inside the message map. A low-level hook runs before the
    // routing, which makes it the one place the notch can be refused.
    if (code >= 0 && wp == WM_MOUSEWHEEL && s_ctl &&
        ::PtInRect(&s_ctl->m_hole, ((const MSLLHOOKSTRUCT*)lp)->pt) != FALSE &&
        !s_ctl->AllowWheel())
        return 1;  // refused: the page does not move for this one
    return ::CallNextHookEx(s_hook, code, wp, lp);
}

Controller::~Controller() {
    Stop();
}

bool Controller::Start() {
    if (m_active) return false;

    COverlayWnd& ov = m_session->Overlay();
    if (!ov.GetSafeHwnd()) return false;

    CRect cl, sel = m_session->Sel().Rect();
    ov.GetClientRect(&cl);
    sel.IntersectRect(&sel, &cl);
    const int w = sel.Width(), h = sel.Height();
    if (w < kMinW || h < kMinH) return false;

    m_sel = sel;
    m_hole = sel;
    m_hole.OffsetRect(ov.Origin().x, ov.Origin().y);
    m_w = w;
    m_first = m_rows = m_cap = 0;
    m_px = std::vector<uint32_t>();
    m_sigs = std::vector<uint64_t>();
    m_tail = (std::min)(kMaxTail, h / 2);
    m_maxStep = h - m_tail;
    m_maxRows = (std::min)(kMaxHeight, (int)(kMaxBytes / (4ull * (size_t)w)));
    m_preview = true;
    m_showTip = true;
    m_stopped = false;
    // Notches that fit in one sample's worth of travel, with one notch of slack
    // for the sample landing between two. A 600px hole allows 2, a 400px hole 1
    // — where 2 would be 282px against a 240px ceiling and read as a jump.
    m_wheelGrant = (std::max)(1, (m_maxStep - kNotchPx) / kNotchPx);
    m_wheelCredit = m_wheelGrant;
    m_caret.SetRectEmpty();

    // The wheel has to be refused before Windows routes it, so the hook goes in
    // with the hole: from that moment on the cursor is over the page, not us.
    if (!s_hook) {
        s_ctl = this;
        s_hook = ::SetWindowsHookExW(WH_MOUSE_LL, WheelHook,
                                     ::GetModuleHandleW(nullptr), 0);
    }

    // Cut the hole before the first grab: until then the overlay covers the
    // region and the seed frame would be our own dimmed copy of it.
    ov.SetHole(m_sel);
    m_active = true;

    Frame f;
    if (!GrabFrame(m_hole, f) || !AppendRows(f, 0, f.height)) {
        Stop();
        return false;
    }

    m_bar = std::make_unique<CBarWnd>();
    m_tipWnd = std::make_unique<CTipWnd>();
    if (!m_bar->Create(this) || !m_tipWnd->Create()) {
        Stop();
        return false;
    }
    m_bar->Place(m_hole);
    m_tipWnd->SetText(L"滚动鼠标轴或单击，开始截长图");
    m_tipWnd->Place(m_hole);

    m_bar->SetPolling(true);
    Repaint();
    return true;
}

void Controller::Stop() {
    if (s_hook) {
        ::UnhookWindowsHookEx(s_hook);
        s_hook = nullptr;
        s_ctl = nullptr;
    }
    if (m_bar) {
        if (m_bar->GetSafeHwnd()) m_bar->SetPolling(false);
        if (HWND h = m_bar->GetSafeHwnd()) m_bar->DestroyWindow();
        m_bar.reset();
    }
    if (m_tipWnd) {
        if (HWND h = m_tipWnd->GetSafeHwnd()) m_tipWnd->DestroyWindow();
        m_tipWnd.reset();
    }
    if (m_active && m_session && m_session->Overlay().GetSafeHwnd())
        m_session->Overlay().SetHole(CRect());
    m_active = false;
}

bool Controller::AllowWheel() {
    // Once the stitcher has stopped the user is scrolling for themselves and
    // nothing is being matched any more.
    if (m_stopped) return true;
    if (m_wheelCredit <= 0) return false;
    --m_wheelCredit;
    return true;
}

void Controller::Tick() {
    if (!m_active || m_stopped) return;

    // The card sits inside the hole, so a grab would stitch it into the
    // document and hiding it is the only way out. Hiding it on every grab is
    // what made it blink six times a second, though: it is only ever in the way
    // of a grab that appends rows, so the probe runs with it up and only a frame
    // that has actually moved gets a second, clean grab. That happens once — the
    // first append takes the card away for good.
    const bool probe = m_showTip && m_tipWnd &&
                       ::IsWindowVisible(m_tipWnd->GetSafeHwnd());
    Frame f;
    if (!GrabFrame(m_hole, f)) return;
    if (f.width != m_w || f.height != m_sel.Height()) return;
    Shift sh = Match(f.sigs);
    // A short hole puts the card inside the band the match reads, so a shift or
    // a jump there has to be confirmed the same way rather than acted on.
    if (probe && (sh.rows != 0 || sh.jump)) {
        m_tipWnd->HideForGrab();
        if (GrabFrame(m_hole, f)) sh = Match(f.sigs);
        else sh = Shift{};
        if (sh.rows == 0 && !sh.jump) m_tipWnd->ShowAgain();
    }
    if (sh.jump) {
        m_stopped = true;
        StopPolling();
        ShowStatus(L"画面变化过大，已停止自动拼接");
        return;
    }
    // The page is accounted for: from here the queue starts over, so the wheel
    // is worth the allowance again until the next sample.
    m_wheelCredit = m_wheelGrant;
    if (sh.rows == 0) return;

    // Negative rows means the pointer scrolled up, and the new content is at the
    // top of the frame rather than the bottom.
    const int n = abs(sh.rows);
    const bool added = sh.rows > 0 ? AppendRows(f, f.height - n, n)
                                   : PrependRows(f, 0, n);
    if (!added) {
        m_stopped = true;
        StopPolling();
        ShowStatus(L"已达到最大长度");
        return;
    }

    // The card only explains how to start; once content is moving it would
    // just be in the way of every later grab.
    if (m_showTip) {
        m_showTip = false;
        if (m_tipWnd) m_tipWnd->ShowWindow(SW_HIDE);
    }
    Repaint();
}

bool Controller::AppendRows(const Frame& f, int from, int count) {
    if (count <= 0) return true;
    if (f.width != m_w || from < 0 || from + count > f.height) return false;
    if (!GrowFor(0, count)) return false;

    const uint32_t* src = f.px.data() + (size_t)from * (size_t)m_w;
    uint32_t* dst = Row(m_rows);
    std::memcpy(dst, src, (size_t)count * (size_t)m_w * sizeof(uint32_t));
    for (int i = 0; i < count; ++i)
        *SigRow(m_rows + i) = RowSignature(src + (size_t)i * (size_t)m_w, m_w);
    m_rows += count;
    return true;
}

// Scrolling up brings the new rows in at the top of the frame and above the
// document, which is the direction the buffer used to have no room for.
bool Controller::PrependRows(const Frame& f, int from, int count) {
    if (count <= 0) return true;
    if (f.width != m_w || from < 0 || from + count > f.height) return false;
    if (!GrowFor(count, 0)) return false;

    const uint32_t* src = f.px.data() + (size_t)from * (size_t)m_w;
    m_first -= count;
    std::memcpy(Row(0), src, (size_t)count * (size_t)m_w * sizeof(uint32_t));
    for (int i = 0; i < count; ++i)
        *SigRow(i) = RowSignature(src + (size_t)i * (size_t)m_w, m_w);
    m_rows += count;
    return true;
}

bool Controller::GrowFor(int before, int after) {
    const int need = m_rows + before + after;
    if (need > m_maxRows) return false;
    if (m_first >= before && m_first + need <= m_cap) return true;

    int want = m_cap > 0 ? m_cap * 2 : need;
    if (want < need) want = need;
    if (want > m_maxRows) want = m_maxRows;
    std::vector<uint32_t> next;
    std::vector<uint64_t> nextSigs;
    try {
        next.resize((size_t)want * (size_t)m_w);
        nextSigs.resize((size_t)want);
    } catch (const std::bad_alloc&) {
        return false;
    }
    // The document moves to the middle of the new buffer, which is what leaves
    // both ends free to grow; the clamp keeps it clear of the rows being added.
    int first = (want - m_rows) / 2;
    first = std::clamp(first, before, want - m_rows - after);
    std::memcpy(next.data() + (size_t)first * (size_t)m_w, Row(0),
                (size_t)m_rows * (size_t)m_w * sizeof(uint32_t));
    if (m_rows > 0)
        std::memcpy(nextSigs.data() + first, SigRow(0),
                    (size_t)m_rows * sizeof(uint64_t));
    m_px.swap(next);
    m_sigs.swap(nextSigs);
    m_cap = want;
    m_first = first;
    return true;
}

std::vector<uint64_t> Controller::TailSignatures() const {
    const int n = (std::min)(m_tail, m_rows);
    std::vector<uint64_t> out;
    out.reserve((size_t)n);
    for (int i = 0; i < n; ++i) out.push_back(RowSignature(Row(m_rows - n + i), m_w));
    return out;
}

std::vector<uint64_t> Controller::HeadSignatures() const {
    const int n = (std::min)(m_tail, m_rows);
    std::vector<uint64_t> out;
    out.reserve((size_t)n);
    for (int i = 0; i < n; ++i) out.push_back(RowSignature(Row(i), m_w));
    return out;
}

// A scroll can go either way: the tail lines up when new content appeared below,
// the head when it appeared above. Asking the tail first and taking whatever it
// returns is wrong in both directions — once the document has grown past one
// frame, the end that is off screen still lines up on the blank rows between
// lines of text, and the tolerance that lets a blinking caret through is loose
// enough to call that a match. So both ends are asked and the better-evidenced
// one decides.
Shift Controller::Match(const std::vector<uint64_t>& sigs) const {
    const Shift down = FindShift(TailSignatures(), sigs, m_maxStep);
    if (down.rows == 0 && !down.jump) return down;  // the page did not move

    const Shift up = FindUpShift(HeadSignatures(), sigs, m_maxStep);
    if (up.rows == 0 && !up.jump) return up;  // a repaint the tail alone misread

    if (!down.jump && (up.jump || down.matches >= up.matches)) return down;
    if (!up.jump) {
        Shift s{};
        s.rows = -up.rows;
        s.matches = up.matches;
        return s;
    }
    if (!down.jump) return down;

    // Neither end lines up, which is what a scroll back over the middle of the
    // document looks like: the frame is already part of the image, so there is
    // nothing to add and no page turn to stop for. Only a frame that is nowhere
    // in the document is a real jump.
    const std::vector<uint64_t> all(m_sigs.begin() + m_first,
                                    m_sigs.begin() + m_first + m_rows);
    if (FindInside(all, sigs) >= 0) return Shift{};

    Shift s{};
    s.jump = true;
    return s;
}

// The stitched document beside the hole, as the overlay has to ink it. It shows
// the whole document, shrunk to the screen's height once the document outgrows
// the screen — only the drawing shrinks, the rows and the export keep their
// real size.
CRect Controller::PreviewRect() const {
    if (!m_active || !m_preview || m_rows <= 0) return CRect();

    CRect cl;
    m_session->Overlay().GetClientRect(&cl);
    const HWND hwnd = m_session->Overlay().GetSafeHwnd();
    const int pad = Dpi::S(hwnd, 9);

    int x = m_sel.right + pad;
    if (x + m_w > cl.right) x = m_sel.left - pad - m_w;
    if (x < cl.left) return CRect();  // neither side of the hole has room

    const int budget = (std::max)(1, cl.Height() - pad * 2);
    const int h = (std::min)(m_rows, budget);
    const int w = (std::max)(1, MulDiv(m_w, h, m_rows));
    int y = m_sel.bottom - h;
    if (y < cl.top + pad) y = cl.top + pad;
    if (x + w > cl.right) x = cl.right - w;
    return CRect(x, y, x + w, y + h);
}

void Controller::Paint(Gdiplus::Graphics& g) {
    const CRect r = PreviewRect();
    if (r.IsRectEmpty()) return;

    Gdiplus::Bitmap bmp(m_w, m_rows, m_w * (int)sizeof(uint32_t),
                        PixelFormat32bppARGB, (BYTE*)Row(0));
    const Gdiplus::GraphicsState gs = g.Save();
    // Nearest neighbour drops whole rows on a shrink and leaves the preview
    // looking torn; it is only right when the preview is 1:1.
    g.SetInterpolationMode(r.Height() < m_rows
                               ? Gdiplus::InterpolationModeBilinear
                               : Gdiplus::InterpolationModeNearestNeighbor);
    g.DrawImage(&bmp, Gdiplus::Rect(r.left, r.top, r.Width(), r.Height()),
                0, 0, m_w, m_rows, Gdiplus::UnitPixel);
    g.Restore(gs);

    Gdiplus::Pen ring(kFrame, 2.0f);
    g.DrawRectangle(&ring, (Gdiplus::REAL)r.left - 1.0f, (Gdiplus::REAL)r.top - 1.0f,
                    (Gdiplus::REAL)r.Width() + 2.0f, (Gdiplus::REAL)r.Height() + 2.0f);
}

bool Controller::SizeText(CString* text) const {
    if (!m_active || m_rows <= 0) return false;
    text->Format(L"%d x %d", m_w, m_rows);
    return true;
}

std::unique_ptr<Gdiplus::Bitmap> Controller::TakeResult() {
    if (m_rows <= 0) return nullptr;

    // Clone in the source's own format shares its pixel buffer, and the source
    // here is only a view over m_px — the controller is gone moments later, so
    // the result has to own its rows.
    auto bmp = std::make_unique<Gdiplus::Bitmap>(m_w, m_rows, PixelFormat32bppARGB);
    Gdiplus::Rect r(0, 0, m_w, m_rows);
    Gdiplus::BitmapData d{};
    if (bmp->LockBits(&r, Gdiplus::ImageLockModeWrite, PixelFormat32bppARGB, &d) !=
        Gdiplus::Ok)
        return nullptr;
    const size_t bytes = (size_t)m_w * sizeof(uint32_t);
    for (int y = 0; y < m_rows; ++y)
        memcpy((unsigned char*)d.Scan0 + (size_t)y * d.Stride, Row(y), bytes);
    bmp->UnlockBits(&d);
    return bmp;
}

void Controller::TogglePreview() {
    m_preview = !m_preview;
    Repaint();
}

bool Controller::HitCaret(CPoint pt) const {
    return m_active && !m_caret.IsRectEmpty() && m_caret.PtInRect(pt) != FALSE;
}

void Controller::ShowStatus(const wchar_t* text) {
    if (m_tipWnd) {
        m_tipWnd->SetText(text);
        m_tipWnd->ShowWindow(SW_SHOWNA);
    }
    Repaint();
}

void Controller::StopPolling() {
    if (m_bar) m_bar->SetPolling(false);
}

void Controller::Repaint() {
    if (m_session->Overlay().GetSafeHwnd()) m_session->Overlay().Invalidate();
}

// The bar cannot tear itself down from inside its own WM_LBUTTONUP, so 编辑
// bounces through the overlay's queue like the text editor does.
void Controller::OnEdit() {
    const HWND oh = m_session->Overlay().GetSafeHwnd();
    if (oh) ::PostMessage(oh, WM_APP_LSEDIT, 0, 0);
}

void Controller::RunEdit() {
    if (!m_active) return;
    std::unique_ptr<Gdiplus::Bitmap> bmp = TakeResult();
    Stop();
    if (bmp) m_session->EndLongShot(std::move(bmp));
}

void Controller::OnSave() {
    if (!m_active) return;
    StopPolling();

    std::unique_ptr<Gdiplus::Bitmap> bmp = TakeResult();
    if (bmp) {
        const HWND bar = m_bar->GetSafeHwnd();
        const HWND tip = m_tipWnd ? m_tipWnd->GetSafeHwnd() : nullptr;
        // The common dialog is not topmost and the overlay would sit over it.
        m_session->Overlay().SetTopmost(false);
        if (bar) ::SetWindowPos(bar, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        if (tip) ::SetWindowPos(tip, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);

        if (out::SaveWithDialog(*bmp, bar)) {
            // The stitched image is on disk, which ends the capture just as 完成
            // does. Nothing is put back on top and polling is not re-armed:
            // Finish posts to the sink window, which tears all of this down.
            m_session->Finish(true);
            return;
        }

        if (bar) ::SetWindowPos(bar, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        if (tip) ::SetWindowPos(tip, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        m_session->Overlay().SetTopmost(true);
    }
    if (!m_stopped) m_bar->SetPolling(true);
}

void Controller::OnCancel() {
    if (!m_active) return;
    StopPolling();
    m_session->Finish(false);
}

void Controller::OnDone() {
    if (!m_active) return;
    StopPolling();
    std::unique_ptr<Gdiplus::Bitmap> bmp = TakeResult();
    if (bmp) out::SetClipboard(*bmp);
    m_session->Finish(true);
}

}  // namespace ls
