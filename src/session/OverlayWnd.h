#pragma once

#include "SelectionModel.h"
#include "ToolbarWnd.h"
#include "PropertyBarWnd.h"

class CaptureSession;
namespace annot { class Annotation; class ShapeText; }

// A 32bpp DIB section with a GDI+ face over it: GDI+ draws into it and BitBlt
// presents it. At 3840x2160 a fresh Gdiplus::Bitmap per paint plus a GDI+
// DrawImage onto the window DC cost more than everything else in a frame.
struct DibCanvas {
    HBITMAP bmp = nullptr;
    HDC dc = nullptr;
    void* bits = nullptr;
    std::unique_ptr<Gdiplus::Bitmap> gx;
    CSize size = { 0, 0 };

    bool Reset(CSize s);
    void Free();
};

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

    // The still or the annotation set changed somewhere, so the whole client has
    // to be repainted: a shape added or removed anywhere changes what is drawn
    // and the caller has no tight rect to offer.
    void TouchBase();
    // Same, for a change confined to one rectangle.
    void TouchBaseIn(const CRect& r);

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
    // A tooltip card appearing, moving, or being withdrawn; `anchor` is the new
    // card's anchor in client coordinates, null when it is only going away. The
    // card it replaces and the box the new one can land in are what get
    // repainted — the whole client on every button the pointer crosses is what
    // made the frame and the dim flash together.
    void TipChanged(const CPoint* anchor);

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

    // The bottom of the frame: the still with the committed annotations
    // composited over it. It deliberately ignores the selection, so dragging the
    // selection only repaints the band it swept.
    void DrawBase(Gdiplus::Graphics& g);
    // Everything above the dim: the frames, the cards, the magnifier. Drawn into
    // m_chrome, never onto the window.
    void DrawChrome(Gdiplus::Graphics& g);
    void DrawDim(const DibCanvas& out, const CRect& lim);
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

    // Repainting the whole 3840x2160 client on every mouse move is what made
    // dragging feel like ten frames a second; these name the band a change can
    // actually have altered.
    void InvalidatePart(const CRect& r);
    // A change of box damages the ring around each edge and the ground one box
    // covers that the other does not — never its whole interior.
    void InvalidateRing(const CRect& r, int pad);
    void InvalidateOutside(const CRect& a, const CRect& b);
    void InvalidateSelChange(const RECT& before);
    void InvalidateAnnoChange(const annot::Annotation* a, const CRect& before);
    // Wherever the magnifier card is now and was last. It rides the cursor
    // through a selection drag, so it lands in that band too.
    void InvalidateLoupe();
    static CRect AnnoRect(const annot::Annotation* a);
    // The shape under an in-place drag. It is drawn in the chrome rather than in
    // the base while it moves, so it follows the cursor instead of being redrawn
    // at its old place under the dim.
    annot::Annotation* MovingAnno() const;
    // Takes a shape out of the base at the moment it becomes the drag target.
    void DropFromBase(const annot::Annotation& a);
    std::unique_ptr<Gdiplus::Font> UiFont(int px) const;

    CaptureSession* m_session = nullptr;
    // The still plus the annotations, in client space. Presented with a BitBlt;
    // rebuilt only where it is repainted and only when something under the dim
    // actually changed.
    DibCanvas m_base;
    bool m_baseDirty = true;
    // The chrome, in client space, cleared and redrawn every frame and blended
    // over the window one inked rect at a time. GDI+ charges ~0.35ms per call
    // onto a window DC whatever it draws — 7ms for the twenty-odd calls of one
    // frame — and an order of magnitude less onto a memory DIB.
    DibCanvas m_chrome;
    // The rects the chrome is inking this frame, filled as it clips to each one.
    // Only these are cleared and blended, instead of the whole update region.
    std::vector<CRect> m_chromeInk;
    // Where the three are assembled before they reach the window. DWM reads a
    // GDI window's surface at whatever moment the vsync lands, including in the
    // middle of a paint, so anything the window is given in more than one step
    // can be seen half done. One blit out of here cannot.
    DibCanvas m_out;
    // Where the magnifier was painted last, so the next move knows what to clear.
    CRect m_loupeRect{};
    // The same for the tooltip card.
    CRect m_tipRect{};
    // Fonts and the size card's measurement, rebuilt on every paint otherwise.
    std::unique_ptr<Gdiplus::Font> m_labelFont, m_tipFont, m_dropFont, m_loupeFont;
    CString m_labelText;
    CSize m_labelSize = { 0, 0 };
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
    // Set once the user has dragged a 选区 out themselves. The magnifier is
    // there to help pick where that starts and to read a colour; after that it
    // is only in the way.
    bool m_selPicked = false;
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
