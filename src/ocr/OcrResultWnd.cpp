#include "stdafx.h"
#include "OcrResultWnd.h"

#include "../Dpi.h"
#include "../out/ClipboardText.h"

BEGIN_MESSAGE_MAP(COcrResultWnd, CWnd)
    ON_WM_SIZE()
END_MESSAGE_MAP()

BOOL COcrResultWnd::Create(const std::wstring& text, bool onTop) {
    // A tool window: the app has no taskbar button of its own, and a pile of
    // result windows should not clutter Alt-Tab either.
    LPCTSTR cls = AfxRegisterWndClass(CS_HREDRAW | CS_VREDRAW,
                                      ::LoadCursor(nullptr, IDC_ARROW),
                                      (HBRUSH)(COLOR_BTNFACE + 1));
    if (!cls) return FALSE;

    const RECT vs = Dpi::VirtualScreen();
    const CPoint centre((vs.left + vs.right) / 2, (vs.top + vs.bottom) / 2);
    // There is no HWND to ask for a DPI yet, so take the monitor's own.
    const UINT dpi = Dpi::ForMonitorOfPoint(centre);
    const int w = MulDiv(560, (int)dpi, 96), h = MulDiv(420, (int)dpi, 96);
    if (!CreateEx((onTop ? WS_EX_TOPMOST : 0) | WS_EX_TOOLWINDOW, cls, L"OCR 识字结果",
                  WS_CAPTION | WS_SYSMENU | WS_THICKFRAME,
                  centre.x - w / 2, centre.y - h / 2, w, h, nullptr, nullptr))
        return FALSE;

    LOGFONTW lf{};
    lf.lfHeight = Dpi::FontHeightForPoint(GetSafeHwnd(), 9);
    lf.lfCharSet = DEFAULT_CHARSET;
    lstrcpynW(lf.lfFaceName, L"Microsoft YaHei UI", (int)std::size(lf.lfFaceName));
    m_font.CreateFontIndirect(&lf);

    if (!m_edit.CreateEx(WS_EX_CLIENTEDGE, L"EDIT", L"",
                         WS_CHILD | WS_VISIBLE | ES_MULTILINE | ES_READONLY |
                             ES_AUTOVSCROLL | WS_VSCROLL,
                         CRect(0, 0, 0, 0), this, kIdEdit))
        return FALSE;
    if (!m_copy.Create(L"复制到剪贴板", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                       CRect(0, 0, 0, 0), this, kIdCopy))
        return FALSE;
    if (!m_close.Create(L"关闭", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                        CRect(0, 0, 0, 0), this, kIdClose))
        return FALSE;
    m_edit.SetFont(&m_font);
    m_copy.SetFont(&m_font);
    m_close.SetFont(&m_font);

    m_edit.SetWindowText(text.c_str());
    // Pre-selected so Ctrl+C works without another click.
    m_edit.SetSel(0, -1);
    Layout();

    ShowWindow(SW_SHOW);
    ::SetForegroundWindow(GetSafeHwnd());
    m_edit.SetFocus();
    return TRUE;
}

void COcrResultWnd::SetOnTop(bool onTop) {
    if (!GetSafeHwnd()) return;
    ::SetWindowPos(GetSafeHwnd(), onTop ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

void COcrResultWnd::OnSize(UINT, int, int) {
    Layout();
}

void COcrResultWnd::Layout() {
    if (!m_edit.GetSafeHwnd()) return;
    CRect cl;
    GetClientRect(&cl);

    const HWND hwnd = GetSafeHwnd();
    const int margin = Dpi::S(hwnd, 10);
    const int gap = Dpi::S(hwnd, 6);
    const int barH = Dpi::S(hwnd, 26);

    CRect bar(cl.left, cl.bottom - barH - margin, cl.right, cl.bottom - margin);
    CRect rcClose(bar.right - Dpi::S(hwnd, 72), bar.top, bar.right, bar.bottom);
    CRect rcCopy(rcClose.left - gap - Dpi::S(hwnd, 132), bar.top, rcClose.left - gap,
                 bar.bottom);
    m_close.MoveWindow(rcClose);
    m_copy.MoveWindow(rcCopy);

    m_edit.MoveWindow(cl.left + margin, cl.top + margin, cl.Width() - margin * 2,
                      cl.Height() - margin * 2 - barH - gap);
}

BOOL COcrResultWnd::OnCommand(WPARAM wParam, LPARAM lParam) {
    switch (LOWORD(wParam)) {
    case kIdCopy: {
        CString text;
        m_edit.GetWindowText(text);
        out::SetText(text.GetString());
        return TRUE;
    }
    case kIdClose:
        DestroyWindow();
        return TRUE;
    }
    return CWnd::OnCommand(wParam, lParam);
}
