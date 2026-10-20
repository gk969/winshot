#pragma once

class CTrayIcon {
public:
    BOOL Install(HWND owner, UINT callbackMessage);
    void Remove();
    void SetTooltip(LPCWSTR text);
    void ShowBalloon(LPCWSTR title, LPCWSTR text);

private:
    NOTIFYICONDATAW m_nid = {};
    bool m_installed = false;
};
