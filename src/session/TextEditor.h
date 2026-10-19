#pragma once

namespace annot { class ShapeText; }
class CaptureSession;

// The caret, the text selection and the IME. Enter inserts a newline, Ctrl+Enter
// commits and Esc cancels, which ES_WANTRETURN alone cannot do — it only stops
// the dialog manager from eating the key.
class CTextEditBox : public CEdit {
public:
    // The second click of the double-click that opened the edit lands on a
    // control that has only just been created, and the control then puts the
    // caret where it was clicked rather than at the end of the text. One-shot, so
    // the next click is the user aiming somewhere on purpose.
    void PlaceCaretAtEnd() { m_placeAtEnd = true; }

protected:
    DECLARE_MESSAGE_MAP()
    afx_msg void OnChar(UINT nChar, UINT nRepCnt, UINT nFlags);
    afx_msg void OnLButtonUp(UINT nFlags, CPoint pt);

private:
    bool m_placeAtEnd = false;
};

// The 文字 tool's input surface. It owns no geometry and draws no text of its
// own: it is a transparent edit control placed inside the label's box, which is
// the only box on screen — the red frame and the eight square markers are drawn
// by the overlay from the same rect the label carries, so re-editing a label
// opens on the box it was left on and dragging a handle moves the text with it.
// A real edit control rather than a hand drawn caret because the IME then paints
// its own composition string inside the box and parks its candidate window at
// the caret, which is what 文字-点击位置-输入时红色文本框.png shows.
//
// The box follows the 选区 rather than the screen: it grows right until the
// frame's right edge while the text has no width of its own, then wraps into
// more lines, and it stops growing down at the frame's bottom edge.
class CTextEditor : public CWnd {
public:
    // `label` is the annotation being typed into; it already carries the box the
    // editor opens on. `back` is the colour the fallback brush uses.
    BOOL Create(CWnd* parent, CaptureSession* session, annot::ShapeText* label,
                COLORREF back);
    ~CTextEditor();

    // Ends the edit. Safe from a notification handler of this window, because it
    // only posts — the overlay does the teardown.
    void Finish(bool commit);

    annot::ShapeText* Label() const { return m_label; }
    int FontPx() const { return m_fontPx; }
    Gdiplus::Color Ink() const { return m_ink; }
    CString Text() const;

    // Moves this window onto the label's box and re-samples the pixels behind it.
    // Called when the edit opens and after every move or resize of the label, so
    // the caret and the typed glyphs always sit where the committed label will
    // draw them.
    void SyncToBox();

    // False when `text` would need more room below the box than the 选区 has. The
    // box cannot scroll, so a change that does not fit is refused.
    bool FitsText(const CString& text) const;

private:
    DECLARE_MESSAGE_MAP()
    afx_msg HBRUSH OnCtlColor(CDC* dc, CWnd* wnd, UINT nCtlColor);
    afx_msg BOOL OnEraseBkgnd(CDC*);
    afx_msg void OnEnKillFocus();
    afx_msg void OnEnChange();

    // The 选区, in the parent's client space — the same space this window lives
    // in. The frame is what the text must stay inside, not the screen.
    CRect Limit() const;
    // The label's box grown to hold `text`: never narrower or shorter than it is
    // now, wider only while the text has no width of its own, and never past the
    // 选区's right or bottom edge.
    Gdiplus::RectF BoxFor(const CString& text) const;
    // How tall a box `width` wide has to be to show all of `text`. BoxFor caps at
    // the 选区, so this is what says whether the cap bit.
    Gdiplus::REAL NeededHeight(const CString& text, Gdiplus::REAL width) const;
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
    annot::ShapeText* m_label = nullptr;
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
