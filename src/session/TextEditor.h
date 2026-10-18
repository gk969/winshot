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
//
// The box follows the 选区 rather than the screen: it grows right until the
// frame's right edge, then wraps into more lines, and it stops growing down at
// the frame's bottom edge.
class CTextEditor : public CWnd {
public:
    // `at` is the press point in overlay-client px. `target` is the annotation
    // being re-edited, or null when a new one is being typed.
    BOOL Create(CWnd* parent, CaptureSession* session, CPoint at,
                const CString& text, int fontPx, Gdiplus::Color ink,
                COLORREF back, annot::ShapeText* target);
    ~CTextEditor();

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

    // False when `text` would need more room below the press point than the
    // 选区 has. The box cannot scroll, so a change that does not fit is refused.
    bool FitsText(const CString& text) const;

private:
    DECLARE_MESSAGE_MAP()
    afx_msg HBRUSH OnCtlColor(CDC* dc, CWnd* wnd, UINT nCtlColor);
    afx_msg BOOL OnEraseBkgnd(CDC*);
    afx_msg void OnEnKillFocus();
    afx_msg void OnEnChange();

    // The edit grows with what is typed, as the reference box does, up to the
    // frame's right edge; past it the text wraps and the box grows down.
    void FitToText();
    // The 选区, in the parent's client space, clipped to what we can draw on.
    CRect Limit() const;
    // The box `text` needs: as wide as the text up to `maxW`, then one line
    // pitch per wrapped line.
    CSize BoxFor(const CString& text, int maxW) const;
    // The base pixels behind this window, as a tile for the inner edit. The
    // overlay is WS_CLIPCHILDREN and never paints under a child, so the edit has
    // to carry its own background or it shows an opaque swatch instead.
    void RebuildBackdrop();

    CTextEditBox m_edit;
    // Only the fallback: the pattern brush is what the edit normally paints with.
    CBrush m_back;
    CBrush m_pattern;
    // Kept alive while m_pattern refers to it.
    HBITMAP m_backBmp = nullptr;
    CFont m_font;
    CaptureSession* m_session = nullptr;
    annot::ShapeText* m_target = nullptr;
    CPoint m_at = { 0, 0 };
    int m_fontPx = 18;
    Gdiplus::Color m_ink;
    COLORREF m_backColor = RGB(255, 255, 255);
    bool m_finishing = false;
    // Set while OnEnChange undoes a change that did not fit, so the notification
    // that restoring the text raises does not undo itself.
    bool m_restoring = false;
    // The text and caret as of the last change that fitted: what a change that
    // did not fit is put back to.
    CString m_lastGood;
    int m_lastSelStart = 0, m_lastSelEnd = 0;
};
