#pragma once

// 钉在桌面上: the cut-out stays on the screen after the capture itself is gone,
// as its own borderless topmost window. Drag it anywhere, wheel to scale, and
// dismiss it with the ✕ in its corner, the middle button, Esc or the right-button
// menu. Its size comes from the wheel alone — dragging an edge to resize a
// borderless rectangle turned out to be easier to hit by accident than on
// purpose.
class CPinWnd : public CWnd {
public:
    // `screenRect` is where the selection sat; the image is shown there at 1:1.
    BOOL Create(Gdiplus::Bitmap* bmp, const CRect& screenRect);

    void Zoom(double factor);
    void ClosePin();

protected:
    afx_msg void OnPaint();
    afx_msg BOOL OnEraseBkgnd(CDC*);
    afx_msg LRESULT OnNcHitTest(CPoint pt);
    // The client area is HTCAPTION, so a double click would otherwise maximize.
    afx_msg void OnNcLButtonDblClk(UINT hitTest, CPoint pt);
    afx_msg BOOL OnMouseWheel(UINT nFlags, short zDelta, CPoint pt);
    // Only the ✕ is HTCLIENT, so this fires for that square and nothing else.
    afx_msg void OnLButtonDown(UINT nFlags, CPoint pt);
    afx_msg void OnMButtonDown(UINT nFlags, CPoint pt);
    afx_msg void OnRButtonDown(UINT nFlags, CPoint pt);
    afx_msg void OnKeyDown(UINT nChar, UINT nRepCnt, UINT nFlags);
    DECLARE_MESSAGE_MAP()

private:
    enum { kCmdCopy = 1, kCmdSave = 2, kCmdClose = 3 };

    void ShowMenu(CPoint screenPt);
    void ApplySize(int w, int h);
    // The ✕ badge, in client coordinates. Shared by the paint and the hit test.
    CRect CloseRect() const;

    // Stored at its natural size; the window is that times m_scale, so scaling
    // back up never resamples what was captured.
    std::unique_ptr<Gdiplus::Bitmap> m_bmp;
    CSize m_natural{ 0, 0 };
    double m_scale = 1.0;
};
