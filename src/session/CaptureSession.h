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

    // The 文字 tool's inline editor. It lives here rather than on the overlay so
    // the toolbar, the property bar and the overlay can all reach it; the
    // overlay only draws the red frame around Editor()->Frame().
    void BeginTextEdit(CPoint at, annot::ShapeText* target = nullptr);
    void EndTextEdit(bool commit);
    CTextEditor* Editor() const { return m_editor.get(); }

    // The 字号 dropdown, drawn on the overlay under the property bar's box.
    // `fontBoxScreen` is that box's rect in screen coords.
    void ToggleFontDropdown(const RECT* fontBoxScreen);
    void HideFontDropdown();
    const CRect* FontDropdown() const {
        return m_fontDrop.IsRectEmpty() ? nullptr : &m_fontDrop;
    }

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
    // Adopts the stitched image as this session's still, anchored at `anchor`
    // (screen coordinates), and makes the selection cover all of it.
    void EndLongShot(std::unique_ptr<Gdiplus::Bitmap> bmp, POINT anchor);

    // Reached through the overlay, which is what draws both.
    bool LongShotSizeText(CString& text) const;
    bool HitLongShotCaret(CPoint pt) const;
    void ToggleLongShotPreview();
    void PaintLongShot(Gdiplus::Graphics& g);
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
    int m_widthByTool[7] = { 2, 2, 0, 2, 2, 2, 2 };
    TipCard m_tip;
    annot::AnnotationList m_annos;
    MosaicCache m_mosaic{ this };
    annot::UndoStack m_undo;
    int m_selIdx = -1;
    std::unique_ptr<CTextEditor> m_editor;
    bool m_ocrBusy = false;
    // Overlay-client rect of the open 字号 list, empty when it is closed.
    CRect m_fontDrop;
};
