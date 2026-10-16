#include "stdafx.h"
#include "TrayIcon.h"

BOOL CTrayIcon::Install(HWND owner, UINT callbackMessage) {
    int size = GetSystemMetrics(SM_CXSMICON);
    if (size <= 0) size = 16;

    m_icon = CreateIcon(size);
    if (!m_icon) return FALSE;

    m_nid = {};
    m_nid.cbSize = sizeof(m_nid);
    m_nid.hWnd = owner;
    m_nid.uID = 1;
    m_nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    m_nid.uCallbackMessage = callbackMessage;
    m_nid.hIcon = m_icon;
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
    if (!m_installed) {
        DestroyIcon(m_icon);
        m_icon = nullptr;
    }
    return m_installed;
}

void CTrayIcon::Remove() {
    if (!m_installed) return;
    Shell_NotifyIconW(NIM_DELETE, &m_nid);
    m_installed = false;
    if (m_icon) {
        DestroyIcon(m_icon);
        m_icon = nullptr;
    }
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

HICON CTrayIcon::CreateIcon(int size) {
    using namespace Gdiplus;
    Bitmap bmp(size, size, PixelFormat32bppARGB);
    Graphics g(&bmp);
    g.SetSmoothingMode(SmoothingModeAntiAlias);

    REAL s = (REAL)size;
    REAL pad = s * 0.14f;
    REAL pen = std::max((REAL)1.0f, s * 0.10f);
    REAL arm = s * 0.24f;

    SolidBrush white(0xFFFFFFFFu);
    g.FillRectangle(&white, 0.0f, 0.0f, s, s);

    Pen frame(0xFF1E9FD4, pen);
    frame.SetStartCap(LineCapRound);
    frame.SetEndCap(LineCapRound);

    // Four viewfinder corner brackets.
    struct Corner { REAL x, y, dx, dy; } corners[4] = {
        { pad, pad, 1, 1 },
        { s - pad, pad, -1, 1 },
        { pad, s - pad, 1, -1 },
        { s - pad, s - pad, -1, -1 },
    };
    for (auto& c : corners) {
        g.DrawLine(&frame, c.x, c.y, c.x + c.dx * arm, c.y);
        g.DrawLine(&frame, c.x, c.y, c.x, c.y + c.dy * arm);
    }

    SolidBrush dot(0xFFFA373A);
    REAL d = s * 0.30f;
    g.FillEllipse(&dot, (s - d) / 2, (s - d) / 2, d, d);

    HICON icon = nullptr;
    if (bmp.GetHICON(&icon) != Ok) return nullptr;
    return icon;
}
