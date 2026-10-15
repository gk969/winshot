#include "stdafx.h"
#include "WinshotApp.h"
#include "HiddenWnd.h"
#include "AppMessages.h"
#include "session/CaptureSession.h"
#include "pin/PinWnd.h"
#include "ocr/OcrResultWnd.h"

BEGIN_MESSAGE_MAP(CWinshotApp, CWinApp)
END_MESSAGE_MAP()

CWinshotApp theApp;

BOOL CWinshotApp::InitInstance() {
    m_singleInstanceMutex =
        CreateMutexW(nullptr, FALSE, L"Global\\winshot.single.instance");
    if (!m_singleInstanceMutex)
        m_singleInstanceMutex =
            CreateMutexW(nullptr, FALSE, L"winshot.single.instance");
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        MessageBoxW(nullptr, L"WinShot 已经在运行。", L"WinShot", MB_ICONINFORMATION);
        return FALSE;
    }

    m_sink = new CHiddenWnd();
    if (!m_sink->Create()) {
        AfxMessageBox(L"WinShot 启动失败：无法创建托盘图标。");
        return FALSE;
    }

    // CWinApp::Run() returns 0 immediately if m_pMainWnd is null, so the
    // always-present sink owns that slot. It is destroyed only at shutdown, so
    // the overlay and pin windows coming later can come and go without ending
    // the message loop.
    m_pMainWnd = m_sink;

    m_hotkeyRegistered = RegisterHotKey(m_sink->GetSafeHwnd(), HOTKEY_CAPTURE,
                                        MOD_CONTROL | MOD_SHIFT, 'A');
    m_sink->SetHotkeyAvailable(m_hotkeyRegistered != 0);

    return TRUE;
}

int CWinshotApp::ExitInstance() {
    m_session.reset();
    if (m_ocrWnd && m_ocrWnd->GetSafeHwnd()) m_ocrWnd->DestroyWindow();
    m_ocrWnd.reset();
    for (auto& pin : m_pins)
        if (pin->GetSafeHwnd()) pin->DestroyWindow();
    m_pins.clear();

    if (m_hotkeyRegistered && m_sink)
        UnregisterHotKey(m_sink->GetSafeHwnd(), HOTKEY_CAPTURE);
    if (m_sink) {
        m_sink->Tray().Remove();
        m_sink->DestroyWindow();
        delete m_sink;
        m_sink = nullptr;
    }
    if (m_singleInstanceMutex) {
        CloseHandle(m_singleInstanceMutex);
        m_singleInstanceMutex = nullptr;
    }
    return CWinApp::ExitInstance();
}

void CWinshotApp::StartCapture() {
    if (m_session) return;
    m_session = CaptureSession::Start();
}

void CWinshotApp::RequestEndCapture(bool accepted) {
    if (!m_session || !m_sink) return;
    ::PostMessageW(m_sink->GetSafeHwnd(), WM_APP_ENDCAPTURE, accepted ? 1 : 0, 0);
}

void CWinshotApp::EndCapture(bool accepted) {
    if (!m_session) return;
    m_session.reset();
    PruneWindows();

    // The result window only had to out-rank the overlay; once the capture is
    // gone it should not float above everything else on the desktop.
    if (m_ocrWnd) m_ocrWnd->SetOnTop(false);

    // The overlay held the focus, and it is gone now: without this the pin
    // never sees Esc.
    if (m_focusPin && m_focusPin->GetSafeHwnd()) {
        ::SetForegroundWindow(m_focusPin->GetSafeHwnd());
        ::SetFocus(m_focusPin->GetSafeHwnd());
    }
    m_focusPin = nullptr;
    (void)accepted;
}

void CWinshotApp::AddPin(std::unique_ptr<Gdiplus::Bitmap> bmp, const CRect& screenRect) {
    auto pin = std::make_unique<CPinWnd>();
    if (!pin->Create(bmp.get(), screenRect)) return;
    m_focusPin = pin.get();
    m_pins.push_back(std::move(pin));
}

void CWinshotApp::OnOcrDone(std::wstring* text) {
    std::unique_ptr<std::wstring> guard(text);
    if (m_session) m_session->OcrDone();

    if (!text || text->empty()) {
        if (m_sink) m_sink->Tray().ShowBalloon(L"WinShot", L"没有识别到文字。");
        return;
    }
    // One result window at a time; a second OCR replaces the first. ~CWnd does
    // not destroy the window, so it has to go first.
    if (m_ocrWnd && m_ocrWnd->GetSafeHwnd()) m_ocrWnd->DestroyWindow();
    m_ocrWnd.reset();
    auto wnd = std::make_unique<COcrResultWnd>();
    if (!wnd->Create(*text, m_session != nullptr)) return;
    m_ocrWnd = std::move(wnd);
}

void CWinshotApp::PruneWindows() {
    std::erase_if(m_pins,
                  [](const std::unique_ptr<CPinWnd>& pin) { return !pin->GetSafeHwnd(); });
}
