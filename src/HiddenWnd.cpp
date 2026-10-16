#include "stdafx.h"
#include "HiddenWnd.h"
#include "AppMessages.h"
#include "WinshotApp.h"

UINT CHiddenWnd::WM_TASKBARCREATED = 0;

BEGIN_MESSAGE_MAP(CHiddenWnd, CWnd)
    ON_MESSAGE(WM_APP_TRAY, &CHiddenWnd::OnTrayNotify)
    ON_MESSAGE(WM_APP_STARTCAPTURE, &CHiddenWnd::OnStartCapture)
    ON_MESSAGE(WM_APP_ENDCAPTURE, &CHiddenWnd::OnEndCapture)
    ON_MESSAGE(WM_APP_OCR_DONE, &CHiddenWnd::OnOcrDone)
    ON_WM_HOTKEY()
END_MESSAGE_MAP()

BOOL CHiddenWnd::Create() {
    WM_TASKBARCREATED = RegisterWindowMessageW(L"TaskbarCreated");

    LPCTSTR cls = AfxRegisterWndClass(0, nullptr, nullptr, nullptr);
    if (!cls) return FALSE;

    // WS_POPUP, invisible, zero size, off-screen. Parentless so it is a real
    // top-level window and therefore receives broadcast messages.
    if (!CreateEx(0, cls, L"WinShotSink", WS_POPUP, -32000, -32000, 0, 0,
                  nullptr, nullptr))
        return FALSE;

    return m_tray.Install(GetSafeHwnd(), WM_APP_TRAY);
}

void CHiddenWnd::SetHotkeyAvailable(bool ok) {
    m_hotkeyAvailable = ok;
    if (!ok)
        m_tray.ShowBalloon(L"WinShot",
                           L"快捷键 Ctrl+Shift+A 已被其他程序占用，"
                           L"请从托盘菜单中选择“开始截图”。");
}

LRESULT CHiddenWnd::WindowProc(UINT message, WPARAM wParam, LPARAM lParam) {
    if (WM_TASKBARCREATED && message == WM_TASKBARCREATED) {
        ReinstallTrayIcon();
        return 0;
    }
    if (message == WM_COMMAND) {
        OnTrayCommand(wParam);
        return 0;
    }
    return CWnd::WindowProc(message, wParam, lParam);
}

void CHiddenWnd::ReinstallTrayIcon() {
    m_tray.Remove();
    m_tray.Install(GetSafeHwnd(), WM_APP_TRAY);
}

LRESULT CHiddenWnd::OnTrayNotify(WPARAM wParam, LPARAM lParam) {
    // Version 4 hands the event in the low word of lParam with the icon id above
    // it, and the icon's screen point in wParam. Reading the event from the high
    // word instead — which is the icon id — matches no case, so a real right
    // click did nothing while a posted one looked fine.
    switch (LOWORD(lParam)) {
    case NIN_SELECT:            // left single click
        ::PostMessageW(GetSafeHwnd(), WM_APP_STARTCAPTURE, 0, 0);
        break;
    case WM_CONTEXTMENU: {      // right click, and the menu key
        POINT pt = { (SHORT)LOWORD(wParam), (SHORT)HIWORD(wParam) };
        // wParam is 0 when the event has no point, i.e. keyboard activation.
        if (!wParam) ::GetCursorPos(&pt);
        ShowTrayMenu(pt);
        break;
    }
    }
    return 0;
}

void CHiddenWnd::OnHotKey(UINT nHotKeyId, UINT, UINT) {
    if (nHotKeyId == HOTKEY_CAPTURE)
        ::PostMessageW(GetSafeHwnd(), WM_APP_STARTCAPTURE, 0, 0);
}

LRESULT CHiddenWnd::OnStartCapture(WPARAM, LPARAM) {
    theApp.StartCapture();
    return 0;
}

LRESULT CHiddenWnd::OnEndCapture(WPARAM wParam, LPARAM) {
    theApp.EndCapture(wParam != 0);
    return 0;
}

// The OCR worker's hand-off; wParam owns the string it allocated.
LRESULT CHiddenWnd::OnOcrDone(WPARAM wParam, LPARAM) {
    theApp.OnOcrDone((std::wstring*)wParam);
    return 0;
}

void CHiddenWnd::ShowTrayMenu(POINT ptScreen) {
    // TrackPopupMenu runs its own modal loop and pumps another right click
    // straight back into this handler, which would stack a second menu on the
    // first and throw it back up the moment the choice came out.
    if (m_menuUp) return;
    m_menuUp = true;
    struct Guard {
        bool& f;
        ~Guard() { f = false; }
    } guard{ m_menuUp };

    CMenu menu;
    if (!menu.CreatePopupMenu()) return;

    CString captureLabel = m_hotkeyAvailable
        ? CString(L"开始截图\tCtrl+Shift+A")
        : CString(L"开始截图");
    menu.AppendMenu(MF_STRING, IDM_TRAY_CAPTURE, captureLabel);

    menu.AppendMenu(MF_STRING | (IsRunOnStartup() ? MFS_CHECKED : MFS_UNCHECKED),
                    IDM_TRAY_RUNONSTARTUP, L"开机启动");

    menu.AppendMenu(MF_SEPARATOR);
    menu.AppendMenu(MF_STRING, IDM_TRAY_ABOUT, L"关于");
    menu.AppendMenu(MF_SEPARATOR);
    menu.AppendMenu(MF_STRING, IDM_TRAY_EXIT, L"退出");

    // Without this the menu never dismisses on an outside click.
    ::SetForegroundWindow(GetSafeHwnd());
    // TrackPopupMenu does not send these itself, and a window that never sees
    // them has no menu loop for DefWindowProc to set up: the menu then draws
    // itself but does not behave like a menu, which on a hidden window is
    // exactly what a real right click produced while a posted event did not.
    ::SendMessageW(GetSafeHwnd(), WM_ENTERMENULOOP, 0, 0);
    ::SendMessageW(GetSafeHwnd(), WM_INITMENU, (WPARAM)menu.GetSafeHmenu(), 0);
    // TPM_RETURNCMD means the choice comes back from the call rather than as a
    // WM_COMMAND, so it has to be routed by hand; dropping it leaves every item
    // inert. -1 is "dismissed without choosing", 0 is an error.
    const int cmd = (int)::TrackPopupMenu(
        menu.GetSafeHmenu(),
        TPM_BOTTOMALIGN | TPM_LEFTALIGN | TPM_RIGHTBUTTON | TPM_RETURNCMD,
        ptScreen.x, ptScreen.y, 0, GetSafeHwnd(), nullptr);
    ::SendMessageW(GetSafeHwnd(), WM_EXITMENULOOP, 0, 0);
    if (cmd > 0) OnTrayCommand((WPARAM)cmd);
    ::PostMessageW(GetSafeHwnd(), WM_NULL, 0, 0);
}

void CHiddenWnd::OnTrayCommand(WPARAM wParam) {
    switch (LOWORD(wParam)) {
    case IDM_TRAY_CAPTURE:
        ::PostMessageW(GetSafeHwnd(), WM_APP_STARTCAPTURE, 0, 0);
        break;
    case IDM_TRAY_RUNONSTARTUP:
        ToggleRunOnStartup();
        break;
    case IDM_TRAY_ABOUT:
        AfxMessageBox(L"WinShot — 屏幕截图工具\n快捷键 Ctrl+Shift+A",
                      MB_ICONINFORMATION);
        break;
    case IDM_TRAY_EXIT:
        PostQuitMessage(0);
        break;
    }
}

BOOL CHiddenWnd::IsRunOnStartup() {
    HKEY hk;
    if (RegOpenKeyExW(HKEY_CURRENT_USER,
                      L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                      0, KEY_READ, &hk) != ERROR_SUCCESS)
        return FALSE;
    BOOL found = FALSE;
    if (RegQueryValueExW(hk, L"WinShot", nullptr, nullptr, nullptr, nullptr) == ERROR_SUCCESS)
        found = TRUE;
    RegCloseKey(hk);
    return found;
}

void CHiddenWnd::ToggleRunOnStartup() {
    HKEY hk;
    if (RegOpenKeyExW(HKEY_CURRENT_USER,
                      L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                      0, KEY_SET_VALUE, &hk) != ERROR_SUCCESS)
        return;
    if (IsRunOnStartup()) {
        RegDeleteValueW(hk, L"WinShot");
    } else {
        wchar_t path[MAX_PATH];
        GetModuleFileNameW(nullptr, path, MAX_PATH);
        RegSetValueExW(hk, L"WinShot", 0, REG_SZ,
                       (const BYTE*)path, (DWORD)((lstrlenW(path) + 1) * sizeof(wchar_t)));
    }
    RegCloseKey(hk);
}
