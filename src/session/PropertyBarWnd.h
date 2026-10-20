#pragma once

#include "Toolbar.h"

class CaptureSession;
class CToolbarWnd;
class CPropertyBarWnd;

// The 字号 box typed into. The list under the box only offers the even sizes, so
// this is how any size at all gets set without hunting thirteen rows: digits
// only, Enter or leaving the box commits, Esc throws the edit away.
class CFontEdit : public CEdit {
public:
    void Open(CPropertyBarWnd* bar) { m_bar = bar; }

protected:
    DECLARE_MESSAGE_MAP()
    afx_msg void OnChar(UINT nChar, UINT nRepCnt, UINT nFlags);

private:
    CPropertyBarWnd* m_bar = nullptr;
};

// The second row under the toolbar: stroke widths and the colour palette.
class CPropertyBarWnd : public CWnd {
public:
    BOOL Create(CWnd* parent, CaptureSession* session);

    void Show(bool visible);
    bool Visible() const;
    void PlaceBelow(const CToolbarWnd* toolbar);
    void Refresh();

    int BarHeight() const { return m_h; }
    // The 字号 box was pressed: hand the session the target before focus moves
    // (taking it ends a text edit that was running), then open the input box.
    void BeginFontSizeEdit();
    // Ends the typed size. `commit` is false for Esc and for the bar going away
    // with the edit still open, which both leave the number as it was.
    void FinishFontSizeEdit(bool commit);

protected:
    afx_msg void OnPaint();
    afx_msg BOOL OnEraseBkgnd(CDC* dc);
    afx_msg void OnLButtonDown(UINT nFlags, CPoint pt);
    afx_msg void OnLButtonUp(UINT nFlags, CPoint pt);
    afx_msg void OnMouseMove(UINT nFlags, CPoint pt);
    afx_msg void OnEnKillFocus();
    DECLARE_MESSAGE_MAP()

private:
    // The box splits in two: the ▼ strip opens the list, the rest is typed into.
    enum class Kind { Dot, Swatch, FontBox, FontArrow, Slider };
    enum class Layout { Shape, Text, Mosaic };

    struct Target {
        Kind kind = Kind::Dot;
        int index = 0;
        RECT rc = {};
    };

    void BuildLayout();
    void DrawFontBox(Gdiplus::Graphics& g, const tb::Style& st) const;
    void OpenFontEdit(const RECT& box);
    void DrawMosaicBar(Gdiplus::Graphics& g, const tb::Style& st) const;
    // The 模糊度 rail maps its x onto tb::kBlurMin..kBlurMax.
    void SetBlurFromX(int x);
    int SliderIndex() const;
    // Centre x of the i-th stroke-width dot, in window pixels.
    int DotCentre(int i) const;

    CaptureSession* m_session = nullptr;
    std::vector<Target> m_targets;
    int m_w = 0, m_h = 0;
    int m_hot = -1;
    Layout m_layout = Layout::Shape;
    bool m_sliding = false;
    // The 字号 box whole, box edge to box edge. The two hit targets under it are
    // halves of this, and the drawing wants the whole of it.
    RECT m_fontBox = {};
    CFontEdit m_fontEdit;
    // Kept alive while the input box is using it: WM_SETFONT does not copy.
    CFont m_editFont;
    bool m_fonting = false;
};
