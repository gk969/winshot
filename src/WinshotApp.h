#pragma once

#include <vector>

class CHiddenWnd;
class CaptureSession;
class CPinWnd;
class COcrResultWnd;

class CWinshotApp : public CWinApp {
public:
    BOOL InitInstance() override;
    int ExitInstance() override;

    void StartCapture();
    void RequestEndCapture(bool accepted);
    void EndCapture(bool accepted);

    // Pinned cut-outs and OCR results are owned here, not by the session, so
    // they survive the capture that made them.
    void AddPin(std::unique_ptr<Gdiplus::Bitmap> bmp, const CRect& screenRect);
    // Takes ownership of the string the OCR worker allocated.
    void OnOcrDone(std::wstring* text);

    CHiddenWnd* Sink() { return m_sink; }

    DECLARE_MESSAGE_MAP()

private:
    // Drops the windows that have already destroyed themselves.
    void PruneWindows();

    HANDLE m_singleInstanceMutex = nullptr;
    CHiddenWnd* m_sink = nullptr;
    bool m_hotkeyRegistered = false;
    std::unique_ptr<CaptureSession> m_session;
    std::vector<std::unique_ptr<CPinWnd>> m_pins;
    std::unique_ptr<COcrResultWnd> m_ocrWnd;
    // The pin the current capture just made, focused once the overlay is gone
    // so Esc reaches it.
    CPinWnd* m_focusPin = nullptr;
};

extern CWinshotApp theApp;
