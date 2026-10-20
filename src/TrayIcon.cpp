#include "stdafx.h"
#include "TrayIcon.h"
#include "../resource.h"

BOOL CTrayIcon::Install(HWND owner, UINT callbackMessage) {
    int size = GetSystemMetrics(SM_CXSMICON);
    if (size <= 0) size = 16;

    // The same resource the shell shows as the exe's file icon, so the tray and the
    // file cannot drift apart. Asked for a size, LoadImage picks the closest entry in
    // the .ico's group -- SM_CXSMICON is 16 here and the group has one.
    //
    // LR_SHARED hands back a handle the module owns rather than ours, which is what
    // HiddenWnd's ReinstallTrayIcon needs: it removes and re-adds the icon on every
    // TaskbarCreated message, and destroying a shared handle would take it out from
    // under whoever else holds it.
    HICON icon = (HICON)::LoadImageW(AfxGetResourceHandle(), MAKEINTRESOURCE(IDI_APP_ICON),
                                     IMAGE_ICON, size, size, LR_SHARED);
    if (!icon) return FALSE;

    m_nid = {};
    m_nid.cbSize = sizeof(m_nid);
    m_nid.hWnd = owner;
    m_nid.uID = 1;
    m_nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    m_nid.uCallbackMessage = callbackMessage;
    m_nid.hIcon = icon;
    lstrcpynW(m_nid.szTip, L"WinShot  (Ctrl+Shift+A)", _countof(m_nid.szTip));

    // uVersion has to be carried in the struct: NIM_SETVERSION reads it from
    // there, so leaving it zero asks the shell for version 0 back and the icon
    // keeps reporting mouse messages in the old layout. It also only takes
    // effect on an icon that already exists, so it has to follow NIM_ADD.
    m_installed = !!Shell_NotifyIconW(NIM_ADD, &m_nid);
    if (m_installed) {
        m_nid.uFlags = NIF_MESSAGE;
        m_nid.uVersion = NOTIFYICON_VERSION_4;
        Shell_NotifyIconW(NIM_SETVERSION, &m_nid);
    }
    return m_installed;
}

void CTrayIcon::Remove() {
    if (!m_installed) return;
    Shell_NotifyIconW(NIM_DELETE, &m_nid);
    m_installed = false;
}

void CTrayIcon::SetTooltip(LPCWSTR text) {
    if (!m_installed) return;
    lstrcpynW(m_nid.szTip, text, _countof(m_nid.szTip));
    m_nid.uFlags = NIF_TIP;
    Shell_NotifyIconW(NIM_MODIFY, &m_nid);
}

void CTrayIcon::ShowBalloon(LPCWSTR title, LPCWSTR text) {
    if (!m_installed) return;
    m_nid.uFlags = NIF_INFO;
    m_nid.dwInfoFlags = NIIF_INFO;
    lstrcpynW(m_nid.szInfoTitle, title, _countof(m_nid.szInfoTitle));
    lstrcpynW(m_nid.szInfo, text, _countof(m_nid.szInfo));
    Shell_NotifyIconW(NIM_MODIFY, &m_nid);
    m_nid.uFlags = 0;
    m_nid.szInfo[0] = 0;
}
