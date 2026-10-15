#pragma once

#include "TrayIcon.h"

// A real hidden top-level window, deliberately NOT message-only: HWND_MESSAGE
// windows never receive broadcast messages, so WM_TASKBARCREATED (Explorer
// restart) would be lost and the tray icon would vanish permanently.
class CHiddenWnd : public CWnd {
public:
    BOOL Create();
    void SetHotkeyAvailable(bool ok);

    CTrayIcon& Tray() { return m_tray; }

protected:
    afx_msg LRESULT WindowProc(UINT message, WPARAM wParam, LPARAM lParam) override;
    afx_msg LRESULT OnTrayNotify(WPARAM wParam, LPARAM lParam);
    afx_msg void OnHotKey(UINT nHotKeyId, UINT nKey1, UINT nKey2);
    afx_msg LRESULT OnStartCapture(WPARAM wParam, LPARAM lParam);
    afx_msg LRESULT OnEndCapture(WPARAM wParam, LPARAM lParam);
    afx_msg LRESULT OnOcrDone(WPARAM wParam, LPARAM lParam);
    DECLARE_MESSAGE_MAP()

private:
    // Handled directly in WindowProc: MFC has no ON_WM_COMMAND here and
    // CWnd::OnCommand is a BOOL virtual we don't want to shadow.
    void OnTrayCommand(WPARAM wParam);
    void ShowTrayMenu(POINT ptScreen);
    void ToggleRunOnStartup();
    BOOL IsRunOnStartup();
    void ReinstallTrayIcon();

    CTrayIcon m_tray;
    bool m_hotkeyAvailable = true;
    static UINT WM_TASKBARCREATED;
};
