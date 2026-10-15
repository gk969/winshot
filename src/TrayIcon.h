#pragma once

class CTrayIcon {
public:
    BOOL Install(HWND owner, UINT callbackMessage);
    void Remove();
    void SetTooltip(LPCWSTR text);
    void ShowBalloon(LPCWSTR title, LPCWSTR text);
    HICON Icon() const { return m_icon; }

private:
    static HICON CreateIcon(int size);

    NOTIFYICONDATAW m_nid = {};
    HICON m_icon = nullptr;
    bool m_installed = false;
};
