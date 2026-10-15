#pragma once

#include "SelectionModel.h"
#include "ToolbarWnd.h"
#include "PropertyBarWnd.h"

class CaptureSession;
namespace annot { class Annotation; class ShapeText; }

// Fullscreen overlay covering the whole virtual desktop, showing the frozen
// still with everything outside the selection dimmed.
class COverlayWnd : public CWnd {
public:
    BOOL Create(CaptureSession* session);
    ~COverlayWnd();

    CToolbarWnd& Toolbar() { return m_toolbar; }
    CPropertyBarWnd& PropBar() { return m_propbar; }

    // Repositions the toolbar and property bar against the selection.
    void LayoutChrome();
    void ChromeChanged();

    // Off while a modal common dialog has to sit above us; the WM_WINDOWPOS-
    // CHANGING guard below would otherwise undo the demotion itself.
    void SetTopmost(bool on);

    // 长截图: the selection becomes a hole cut out of this window, so the live
    // desktop shows through it and the wheel reaches the window underneath.
    // An empty rect closes the hole again.
    void SetHole(CRect clientRect);
    bool InLongShot() const { return !m_hole.IsRectEmpty(); }

    // Top-left of this window in physical virtual-screen coordinates. The
    // frozen still starts there, but after 编辑 the capture does not.
    POINT Origin() const { return m_origin; }

    // The bars are child windows, so their mouse moves never reach us; they
    // call this so the magnifier can get out of the way.
    void CursorMoved();

protected:
    afx_msg void OnPaint();
    afx_msg BOOL OnEraseBkgnd(CDC* dc);
    afx_msg void OnLButtonDown(UINT nFlags, CPoint pt);
    afx_msg void OnLButtonDblClk(UINT nFlags, CPoint pt);
    afx_msg void OnLButtonUp(UINT nFlags, CPoint pt);
    afx_msg void OnMouseMove(UINT nFlags, CPoint pt);
    afx_msg BOOL OnMouseWheel(UINT nFlags, short zDelta, CPoint pt);
    afx_msg BOOL OnSetCursor(CWnd* pWnd, UINT nHitTest, UINT message);
    afx_msg void OnKeyDown(UINT nChar, UINT nRepCnt, UINT nFlags);
    afx_msg void OnWindowPosChanging(WINDOWPOS* pos);
    // The text editor posts this instead of committing from its own
    // notification handler, which would destroy the edit mid-message.
    afx_msg LRESULT OnEditDone(WPARAM wParam, LPARAM lParam);
    // The 长截图 bar posts this so 编辑 does not tear the bar down from inside
    // its own mouse-up handler.
    afx_msg LRESULT OnLsEdit(WPARAM wParam, LPARAM lParam);
    DECLARE_MESSAGE_MAP()

private:
    enum class Mode { Idle, Creating, Moving, Sizing, Drawing, MoveAnno, DragHandle };

    void DrawScene(Gdiplus::Graphics& g);
    void DrawSelectionFrame(Gdiplus::Graphics& g);
    void DrawSizeLabel(Gdiplus::Graphics& g);
    void DrawTip(Gdiplus::Graphics& g);
    void DrawEditFrame(Gdiplus::Graphics& g);
    void DrawFontDropdown(Gdiplus::Graphics& g);
    void DrawLoupe(Gdiplus::Graphics& g);
    // The ^ that folds the stitched preview away, hung off the size card.
    void DrawLongShotCaret(Gdiplus::Graphics& g, const CRect& card);
    // Cursor position in client coords when the magnifier belongs on screen.
    bool LoupeCursor(CPoint* at) const;
    // Row of the open 字号 list under `pt`, or -1.
    int HitFontRow(CPoint pt) const;
    annot::ShapeText* TextAt(CPoint pt) const;
    bool ResolvePopup(CPoint pt);
    void ApplyCursor(CPoint pt);
    int HandleRadius() const;
    int AnnoHandleRadius() const;
    int HitAnnoHandle(const annot::Annotation& a, CPoint pt) const;

    CaptureSession* m_session = nullptr;
    // Empty unless 长截图 has the hole open. Client coordinates.
    CRect m_hole{};
    POINT m_origin = {};
    CToolbarWnd m_toolbar;
    CPropertyBarWnd m_propbar;
    Mode m_mode = Mode::Idle;
    SelHandle m_handle = SelHandle::None;
    bool m_topmost = true;
    // Whether the last paint drew the magnifier, so the next mouse move knows it
    // has to repaint to clear it.
    bool m_loupeShown = false;
    CPoint m_dragStart = { 0, 0 };
    RECT m_startRect = {};
    RECT m_prevRect = {};

    // Shape being dragged out with a tool active; committed on button up.
    std::unique_ptr<annot::Annotation> m_pending;
    // Annotation under an in-place drag, plus the clone taken at drag start for
    // the undo record.
    annot::Annotation* m_anno = nullptr;
    std::unique_ptr<annot::Annotation> m_annoBefore;
    int m_annoIdx = -1, m_annoHandle = -1;
};
