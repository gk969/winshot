#pragma once

// The OCR result. Non-modal on purpose: the capture session stays usable while
// the text is being read, and the window outlives it.
class COcrResultWnd : public CWnd {
public:
    // `onTop` is for the capture overlay, which is topmost and stays up while
    // the engine runs; a window below it would be invisible.
    BOOL Create(const std::wstring& text, bool onTop);
    void SetOnTop(bool onTop);

protected:
    afx_msg void OnSize(UINT nType, int cx, int cy);
    BOOL OnCommand(WPARAM wParam, LPARAM lParam) override;
    DECLARE_MESSAGE_MAP()

private:
    enum { kIdEdit = 100, kIdCopy = 101, kIdClose = 102 };

    void Layout();

    CEdit m_edit;
    CButton m_copy, m_close;
    CFont m_font;
};
