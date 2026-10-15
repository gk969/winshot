#pragma once

#include "Toolbar.h"

class CaptureSession;
class CToolbarWnd;

// The second row under the toolbar: stroke widths and the colour palette.
class CPropertyBarWnd : public CWnd {
public:
    BOOL Create(CWnd* parent, CaptureSession* session);

    void Show(bool visible);
    bool Visible() const;
    void PlaceBelow(const CToolbarWnd* toolbar);
    void Refresh();

    int BarHeight() const { return m_h; }

protected:
    afx_msg void OnPaint();
    afx_msg BOOL OnEraseBkgnd(CDC* dc);
    afx_msg void OnLButtonDown(UINT nFlags, CPoint pt);
    afx_msg void OnLButtonUp(UINT nFlags, CPoint pt);
    afx_msg void OnMouseMove(UINT nFlags, CPoint pt);
    DECLARE_MESSAGE_MAP()

private:
    enum class Kind { Dot, Swatch, FontBox, Slider };
    enum class Layout { Shape, Text, Mosaic };

    struct Target {
        Kind kind = Kind::Dot;
        int index = 0;
        RECT rc = {};
    };

    void BuildLayout();
    void DrawFontBox(Gdiplus::Graphics& g, const tb::Style& st) const;
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
};
