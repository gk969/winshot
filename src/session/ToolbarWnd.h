#pragma once

#include "Toolbar.h"

class CaptureSession;

// The capture toolbar: flat self-drawn buttons with vector glyphs, parented to
// the overlay so it inherits its topmost slot and dies with the session.
class CToolbarWnd : public CWnd {
public:
    BOOL Create(CWnd* parent, CaptureSession* session);

    // Moves next to the selection. belowHeight is the property bar hanging
    // underneath; the flip-above decision has to cover the whole block.
    void Place(int belowHeight);
    void Refresh();

    int BarHeight() const { return m_h; }

protected:
    afx_msg void OnPaint();
    afx_msg BOOL OnEraseBkgnd(CDC* dc);
    afx_msg void OnLButtonDown(UINT nFlags, CPoint pt);
    afx_msg void OnLButtonUp(UINT nFlags, CPoint pt);
    afx_msg void OnMouseMove(UINT nFlags, CPoint pt);
    afx_msg void OnMouseLeave();
    afx_msg void OnTimer(UINT_PTR nIDEvent);
    DECLARE_MESSAGE_MAP()

private:
    struct Item {
        tb::Id id = tb::Id::None;
        const wchar_t* tip = nullptr;
        const wchar_t* label = nullptr;
        int x = 0, w = 0;
    };

    void BuildLayout();
    int HitTest(CPoint pt) const;
    void SetHot(int idx);
    void ShowTip(int idx);
    void HideTip();
    void DrawButton(Gdiplus::Graphics& g, const Item& it, tb::Id active);

    CaptureSession* m_session = nullptr;
    std::vector<Item> m_items;
    std::vector<int> m_seps;
    int m_w = 0, m_h = 0;
    int m_cell = 0, m_glyph = 0, m_pad = 0;
    int m_hot = -1, m_pressed = -1;
};
