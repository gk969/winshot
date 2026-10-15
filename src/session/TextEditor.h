#pragma once

namespace annot { class ShapeText; }
class CaptureSession;

// The edit itself. Enter commits and Esc cancels, which ES_WANTRETURN alone
// cannot do — it only stops the dialog manager from eating the key.
class CTextEditBox : public CEdit {
protected:
    DECLARE_MESSAGE_MAP()
    afx_msg void OnChar(UINT nChar, UINT nRepCnt, UINT nFlags);
};

// The inline editor for the 文字 tool. A real edit control rather than a hand
// drawn caret: the IME then paints its own composition string inside the box and
// parks its candidate window at the caret, which is exactly what
// 文字-点击位置-输入时红色文本框.png shows. The red frame is the overlay's job.
class CTextEditor : public CWnd {
public:
    // `at` is the press point in overlay-client px. `target` is the annotation
    // being re-edited, or null when a new one is being typed.
    BOOL Create(CWnd* parent, CaptureSession* session, CPoint at,
                const CString& text, int fontPx, Gdiplus::Color ink,
                COLORREF back, annot::ShapeText* target);

    // The box the overlay strokes in red, in overlay-client px.
    CRect Frame() const;

    // Ends the edit. Safe from a notification handler of this window, because it
    // only posts — the overlay does the teardown.
    void Finish(bool commit);

    annot::ShapeText* Target() const { return m_target; }
    CPoint At() const { return m_at; }
    int FontPx() const { return m_fontPx; }
    Gdiplus::Color Ink() const { return m_ink; }
    CString Text() const;

private:
    DECLARE_MESSAGE_MAP()
    afx_msg HBRUSH OnCtlColor(CDC* dc, CWnd* wnd, UINT nCtlColor);
    afx_msg BOOL OnEraseBkgnd(CDC*);
    afx_msg void OnEnKillFocus();
    afx_msg void OnEnChange();

    // The edit grows with what is typed, as the reference box does.
    void FitToText();

    CTextEditBox m_edit;
    CBrush m_back;
    COLORREF m_backColor = RGB(255, 255, 255);
    CFont m_font;
    CaptureSession* m_session = nullptr;
    annot::ShapeText* m_target = nullptr;
    CPoint m_at = { 0, 0 };
    int m_fontPx = 18;
    Gdiplus::Color m_ink;
    bool m_finishing = false;
};
