#pragma once

#include "OverlayWnd.h"
#include "Toolbar.h"
#include "AnnotationList.h"
#include "Commands.h"
#include "MosaicCache.h"

class DesktopCapture;
class SelectionModel;
class CTextEditor;
namespace ls { class Controller; }

// One capture: the frozen still, the selection, the annotations on it, and the
// overlay that shows them. Owned by CWinshotApp for the lifetime of a capture.
class CaptureSession {
public:
    struct TipCard {
        CString text;
        CPoint anchor{};  // overlay client px: card centre x, the y to hang it at
    };

    // Grabs the desktop first, then opens the overlay — the other order lets
    // the overlay land in its own background.
    static std::unique_ptr<CaptureSession> Start();
    ~CaptureSession();

    const DesktopCapture& Capture() const { return *m_capture; }
    SelectionModel& Sel() { return *m_sel; }
    COverlayWnd& Overlay() { return m_overlay; }

    tb::Id ActiveTool() const { return m_activeTool; }
    tb::Style& Style() { return m_style; }

    void OnToolbar(tb::Id id);
    void SetActiveTool(tb::Id id);

    // Annotations. Every edit goes through the Push*/Record* pair below so the
    // undo stack cannot drift away from the list.
    annot::AnnotationList& Annos() { return m_annos; }
    // What the 马赛克 brush samples; handed to every ShapeMosaic it makes.
    annot::MosaicSource& Mosaic() { return m_mosaic; }
    int SelectedIndex() const { return m_selIdx; }
    annot::Annotation* Selected() const { return m_annos.At((size_t)m_selIdx); }
    void Select(int idx) { m_selIdx = idx; }

    // The ① tool numbers itself off what is already on the canvas.
    int NextBadgeNumber() const;
    annot::Annotation* AddAnnotation(std::unique_ptr<annot::Annotation> a);
    void RemoveAnnotation(int idx);
    // For a drag that mutated an annotation in place: `before` is the clone
    // taken when the drag started.
    void RecordMove(int idx, std::unique_ptr<annot::Annotation> before);
    // The property bar's 粗细 / colour pickers, applied to whatever is selected
    // now. Not recorded on the undo stack — the pickers are live controls, and
    // the last one clicked is not something a user expects to step back through.
    void ApplyStyleToSelected();
    void Undo();
    // 框外右键: everything since the capture opened is withdrawn — the drawings,
    // the undo history that could bring them back, and the armed tool — and the
    // region goes back to the whole screen.
    void ResetCanvas();

    // The 文字 tool's inline editor. It lives here rather than on the overlay so
    // the toolbar, the property bar and the overlay can all reach it. `target`
    // null means a fresh label, which is added to the list at `at` before the
    // edit opens: the box on screen while typing is the label's own, so there is
    // one geometry and dragging a handle while editing moves the text with it.
    void BeginTextEdit(CPoint at, annot::ShapeText* target = nullptr);
    void EndTextEdit(bool commit);
    CTextEditor* Editor() const { return m_editor.get(); }
    // Follow the input surface onto the label's box, after a move or a resize of
    // it. The label owns the geometry; the editor only sits inside it.
    void SyncEditor();
    // The label the editor is rewriting, or null for a fresh one. The overlay
    // leaves it out of its cached canvas for the whole edit: the editor paints
    // its own background out of that canvas, so the committed glyphs left in
    // there show through behind the text being typed as a double image.
    annot::Annotation* EditingAnno() const { return m_editSkip; }

    // The 字号 dropdown, drawn on the overlay under the property bar's box.
    // `fontBoxScreen` is that box's rect in screen coords.
    void ToggleFontDropdown(const RECT* fontBoxScreen);
    void HideFontDropdown();
    const CRect* FontDropdown() const {
        return m_fontDrop.IsRectEmpty() ? nullptr : &m_fontDrop;
    }

    // The 字号 box typed into. The input box takes keyboard focus, and taking it
    // commits a text edit that is running — which ends by deselecting its label.
    // So the label this size is for has to be remembered here, before focus
    // moves, and found again by index when the number comes back.
    void BeginFontSizeEdit();
    // `px` arrives already clamped: the bar owns the input parsing. `commit` is
    // false for Esc and for the bar going away mid-edit, which change nothing.
    void EndFontSizeEdit(int px, bool commit);

    // Composites the selection to the clipboard, then closes the capture.
    void Accept();
    void SavePng();

    // OCR runs on a worker thread; its toolbar slot stays grey until the text
    // comes back, which may be after the capture itself is gone.
    bool OcrBusy() const { return m_ocrBusy; }
    void OcrDone() {
        m_ocrBusy = false;
        if (m_overlay.GetSafeHwnd()) m_overlay.ChromeChanged();
    }

    // Hover card for a toolbar slot. Drawn by the overlay rather than by
    // CToolTipCtrl: the card has to sit above a topmost fullscreen window and
    // land below the bar, which the common control would not do.
    void ShowTip(const wchar_t* text, CPoint anchor);
    void HideTip();
    const TipCard* Tip() const { return m_tip.text.IsEmpty() ? nullptr : &m_tip; }

    // Called by the overlay; defers teardown out of the overlay's own message
    // handler.
    void Finish(bool accepted);

    // ---- 长截图 ----

    // Where the capture starts inside the overlay's client space: (0,0) for the
    // frozen still, and the selection's corner once 编辑 has adopted a stitched
    // image that only covers part of that space.
    POINT CapOff() const;

    void ToggleLongShot();
    // The overlay's queue runs this after the long-shot bar's own click.
    void RunLongShotEdit();
    // Adopts the stitched image as this session's still and turns the selection
    // into a viewport onto it, centred on the screen.
    void EndLongShot(std::unique_ptr<Gdiplus::Bitmap> bmp);

    // ---- 长截图 编辑 ----

    // True once 编辑 has taken over: the selection is then the frame the user
    // edits through, not a region of the still.
    bool LongShotEdit() const { return m_lsEdit; }
    // Moves the document under that frame by `delta` rows (positive shows rows
    // further down the page), taking the annotations with it. False when the
    // document cannot move that way, so the caller can leave the wheel alone.
    bool ScrollLongShot(int delta);
    // What the frame's scrollbar is drawn from: rows hidden above the top edge,
    // and the largest that count can be.
    int LongShotScroll() const { return m_lsScroll; }
    int LongShotMaxScroll() const;
    // The desktop still the document replaced, kept so the area outside the
    // locked frame still reads as the screen rather than as bare dim.
    Gdiplus::Bitmap* Backdrop() const { return m_backdrop.get(); }
    POINT BackdropOff() const { return m_backdropOff; }
    // What ✓ / 保存 / 钉住 / OCR render. Normally the selection; while the 编辑
    // frame is open the whole stitched document, since the frame only selects
    // which part of it is on screen to be edited.
    CRect ExportRect() const;

    // Reached through the overlay, which is what draws both.
    bool LongShotSizeText(CString& text) const;
    bool HitLongShotCaret(CPoint pt) const;
    void ToggleLongShotPreview();
    void PaintLongShot(Gdiplus::Graphics& g);
    CRect LongShotPreviewRect() const;
    void SetLongShotCaret(const CRect& r);

    // The colour the edit box is filled with: the average of the still under it.
    // A white page and a transparent box are indistinguishable, so the box has
    // to paint something.
    COLORREF SampleBack(CRect box) const;

private:
    // 钉在桌面上 and OCR 识字, both of which outlive the overlay.
    void Pin();
    void StartOcr();

    std::unique_ptr<DesktopCapture> m_capture;
    std::unique_ptr<SelectionModel> m_sel;
    COverlayWnd m_overlay;
    // Declared after the overlay so it goes first in the destructor: its popups
    // and its hole have to go away while the overlay is still there to take the
    // region back.
    std::unique_ptr<ls::Controller> m_longShot;
    tb::Id m_activeTool = tb::Id::None;
    tb::Style m_style;
    // Last-used widthIndex per tool, indexed by tb::Id (Rect..Badge, contiguous).
    // Every tool opens on the middle dot; SetActiveTool overwrites Style's copy
    // from here, so the default has to live in both places.
    int m_widthByTool[7] = { 1, 1, 1, 1, 1, 1, 1 };
    TipCard m_tip;
    annot::AnnotationList m_annos;
    MosaicCache m_mosaic{ this };
    annot::UndoStack m_undo;
    int m_selIdx = -1;
    std::unique_ptr<CTextEditor> m_editor;
    annot::Annotation* m_editSkip = nullptr;
    // The label as the edit found it, for ESC and for a cancel that throws away
    // a label nothing was typed into.
    std::unique_ptr<annot::Annotation> m_editBefore;
    // Index into m_annos of the label this edit created, or -1 for a re-edit.
    int m_newText = -1;
    bool m_ocrBusy = false;
    // 长截图 编辑: the still is a stitched document taller than the frame that
    // shows it, and m_lsScroll is how many of its rows are above the top edge.
    bool m_lsEdit = false;
    int m_lsScroll = 0;
    // The still EndLongShot replaced, and where it started in client space at
    // the time. The overlay's own origin moves as the document scrolls, so the
    // backdrop has to remember its own.
    std::unique_ptr<Gdiplus::Bitmap> m_backdrop;
    POINT m_backdropOff = {};
    // Overlay-client rect of the open 字号 list, empty when it is closed.
    CRect m_fontDrop;
    // Index into m_annos of the label a typed 字号 is for, -1 with no edit open.
    int m_fontTarget = -1;
};
