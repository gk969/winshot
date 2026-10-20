#include "stdafx.h"
#include "PinWnd.h"

#include "../Dpi.h"
#include "../out/ClipboardImage.h"
#include "../out/Export.h"

namespace {

const Gdiplus::Color kEdge(0xFF9AA0A6);

constexpr double kMinScale = 0.05, kMaxScale = 8.0;

}  // namespace

BEGIN_MESSAGE_MAP(CPinWnd, CWnd)
    ON_WM_PAINT()
    ON_WM_ERASEBKGND()
    ON_WM_NCHITTEST()
    ON_WM_NCLBUTTONDBLCLK()
    ON_WM_MOUSEWHEEL()
    ON_WM_LBUTTONDOWN()
    ON_WM_MBUTTONDOWN()
    ON_WM_RBUTTONDOWN()
    ON_WM_KEYDOWN()
END_MESSAGE_MAP()

BOOL CPinWnd::Create(Gdiplus::Bitmap* bmp, const CRect& screenRect) {
    if (!bmp) return FALSE;
    // Bitmap's copy constructor is protected; Clone over the whole rect is the
    // documented way to get an independent copy.
    m_bmp.reset(bmp->Clone(0, 0, (INT)bmp->GetWidth(), (INT)bmp->GetHeight(),
                           PixelFormat32bppARGB));
    m_natural = CSize((int)m_bmp->GetWidth(), (int)m_bmp->GetHeight());
    if (m_natural.cx <= 0 || m_natural.cy <= 0) return FALSE;

    LPCTSTR cls = AfxRegisterWndClass(CS_HREDRAW | CS_VREDRAW,
                                      ::LoadCursor(nullptr, IDC_ARROW));
    if (!cls) return FALSE;

    // TOOLWINDOW keeps a pile of pins out of Alt-Tab; the window has no caption
    // of its own, so nothing else about it changes.
    if (!CreateEx(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, cls, L"WinShotPin", WS_POPUP,
                  screenRect.left, screenRect.top, screenRect.Width(), screenRect.Height(),
                  nullptr, nullptr))
        return FALSE;

    ShowWindow(SW_SHOW);
    return TRUE;
}

void CPinWnd::OnPaint() {
    CPaintDC dc(this);
    if (!m_bmp) return;
    CRect cl;
    GetClientRect(&cl);

    Gdiplus::Graphics g(dc.GetSafeHdc());
    // Shrinking with nearest neighbour throws away whole strokes; growing with
    // it would show blocks the capture never had.
    g.SetInterpolationMode(m_scale < 1.0 ? Gdiplus::InterpolationModeBicubic
                                         : Gdiplus::InterpolationModeNearestNeighbor);
    g.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);
    g.DrawImage(m_bmp.get(), Gdiplus::Rect(0, 0, cl.Width(), cl.Height()));

    // A white capture on a white page is invisible without some edge.
    Gdiplus::Pen edge(kEdge, 1.0f);
    g.DrawRectangle(&edge, 0, 0, cl.Width() - 1, cl.Height() - 1);

    const CRect x = CloseRect();
    if (x.IsRectEmpty()) return;
    Gdiplus::SolidBrush bg(Gdiplus::Color(0xCC202124));
    g.FillRectangle(&bg, (Gdiplus::REAL)x.left, (Gdiplus::REAL)x.top,
                    (Gdiplus::REAL)x.Width(), (Gdiplus::REAL)x.Height());
    Gdiplus::Pen cross(Gdiplus::Color(0xFFFFFFFF),
                       std::max(1.5f, (Gdiplus::REAL)x.Width() * 0.07f));
    cross.SetStartCap(Gdiplus::LineCapRound);
    cross.SetEndCap(Gdiplus::LineCapRound);
    const Gdiplus::REAL m = (Gdiplus::REAL)x.Width() * 0.28f;
    g.DrawLine(&cross, (Gdiplus::REAL)x.left + m, (Gdiplus::REAL)x.top + m,
               (Gdiplus::REAL)x.right - m, (Gdiplus::REAL)x.bottom - m);
    g.DrawLine(&cross, (Gdiplus::REAL)x.right - m, (Gdiplus::REAL)x.top + m,
               (Gdiplus::REAL)x.left + m, (Gdiplus::REAL)x.bottom - m);
}

// The ✕ badge in the top-right corner. It shrinks with a pin zoomed far down so
// it never swallows the whole image, and gives up entirely on a pin too small to
// aim at.
CRect CPinWnd::CloseRect() const {
    CRect cl;
    GetClientRect(&cl);
    const int pad = Dpi::S(GetSafeHwnd(), 5);
    const int cap = std::min(cl.Width(), cl.Height()) / 3;
    int s = Dpi::S(GetSafeHwnd(), 22);
    if (s > cap) s = cap;
    if (s < 10) return CRect(0, 0, 0, 0);
    return CRect(cl.right - pad - s, cl.top + pad, cl.right - pad, cl.top + pad + s);
}

BOOL CPinWnd::OnEraseBkgnd(CDC*) {
    return TRUE;
}

// Everything but the ✕ drags the window. The ✕ is the one HTCLIENT spot, which
// is what lets OnLButtonDown see the click at all.
LRESULT CPinWnd::OnNcHitTest(CPoint pt) {
    CRect r;
    GetWindowRect(&r);
    CRect x = CloseRect();
    x.OffsetRect(r.TopLeft());
    return x.PtInRect(pt) ? HTCLIENT : HTCAPTION;
}

void CPinWnd::OnLButtonDown(UINT, CPoint pt) {
    if (CloseRect().PtInRect(pt)) ClosePin();
}

void CPinWnd::OnNcLButtonDblClk(UINT, CPoint) {
    // Swallowed: HTCAPTION would otherwise send SC_MAXIMIZE.
}

void CPinWnd::ApplySize(int w, int h) {
    if (w < 16) w = 16;
    if (h < 16) h = 16;
    CRect r;
    GetWindowRect(&r);
    const CPoint c = r.CenterPoint();
    ::SetWindowPos(GetSafeHwnd(), nullptr, c.x - w / 2, c.y - h / 2, w, h,
                   SWP_NOZORDER | SWP_NOACTIVATE);
    Invalidate();
}

void CPinWnd::Zoom(double factor) {
    double s = m_scale * factor;
    if (s < kMinScale) s = kMinScale;
    if (s > kMaxScale) s = kMaxScale;
    if (s == m_scale) return;
    m_scale = s;
    ApplySize((int)(m_natural.cx * m_scale + 0.5), (int)(m_natural.cy * m_scale + 0.5));
}

BOOL CPinWnd::OnMouseWheel(UINT, short zDelta, CPoint) {
    Zoom(zDelta > 0 ? 1.1 : 1.0 / 1.1);
    return TRUE;
}

void CPinWnd::OnMButtonDown(UINT, CPoint) {
    ClosePin();
}

void CPinWnd::OnKeyDown(UINT nChar, UINT, UINT) {
    if (nChar == VK_ESCAPE) ClosePin();
}

void CPinWnd::ShowMenu(CPoint screenPt) {
    CMenu menu;
    if (!menu.CreatePopupMenu()) return;
    menu.AppendMenu(MF_STRING, kCmdCopy, L"复制到剪贴板");
    menu.AppendMenu(MF_STRING, kCmdSave, L"保存为 PNG…");
    menu.AppendMenu(MF_SEPARATOR);
    menu.AppendMenu(MF_STRING, kCmdClose, L"关闭");

    const int cmd = (int)::TrackPopupMenu(menu.GetSafeHmenu(),
                                          TPM_BOTTOMALIGN | TPM_LEFTALIGN | TPM_RIGHTBUTTON |
                                              TPM_RETURNCMD,
                                          screenPt.x, screenPt.y, 0, GetSafeHwnd(), nullptr);
    // Same as the tray menu: without this the menu stays up on an outside click.
    ::PostMessageW(GetSafeHwnd(), WM_NULL, 0, 0);

    switch (cmd) {
    case kCmdCopy:
        if (m_bmp) out::SetClipboard(*m_bmp);
        break;
    case kCmdSave:
        if (m_bmp) {
            // The common dialog is not topmost and this window is.
            ::SetWindowPos(GetSafeHwnd(), HWND_NOTOPMOST, 0, 0, 0, 0,
                           SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            out::SaveWithDialog(*m_bmp, GetSafeHwnd());
            ::SetWindowPos(GetSafeHwnd(), HWND_TOPMOST, 0, 0, 0, 0,
                           SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
        break;
    case kCmdClose:
        ClosePin();
        break;
    }
}

void CPinWnd::OnRButtonDown(UINT, CPoint pt) {
    ClientToScreen(&pt);
    ShowMenu(pt);
}

void CPinWnd::ClosePin() {
    if (GetSafeHwnd()) DestroyWindow();
}
