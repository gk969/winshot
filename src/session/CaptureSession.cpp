#include "stdafx.h"
#include "CaptureSession.h"
#include "DesktopCapture.h"
#include "SelectionModel.h"
#include "WinshotApp.h"
#include "../HiddenWnd.h"
#include "AppMessages.h"
#include "Compositor.h"
#include "ClipboardImage.h"
#include "Export.h"
#include "Shapes.h"
#include "TextEditor.h"
#include "../ocr/OcrService.h"
#include "../longshot/LongShot.h"
#include "Dpi.h"

#include <algorithm>

std::unique_ptr<CaptureSession> CaptureSession::Start() {
    auto session = std::make_unique<CaptureSession>();

    session->m_capture = std::make_unique<DesktopCapture>();
    if (!session->m_capture->Grab()) return nullptr;

    session->m_sel = std::make_unique<SelectionModel>();
    if (!session->m_overlay.Create(session.get())) return nullptr;

    session->m_style.dpiScale =
        Dpi::ForWindow(session->m_overlay.GetSafeHwnd()) / 96.0f;

    // The hotkey usually lands with the cursor already over the window the user
    // means, so the pre-selection has to be there on the first frame rather than
    // only after they move the mouse.
    session->m_overlay.UpdateHover();

    return session;
}

CaptureSession::~CaptureSession() {
    if (m_overlay.GetSafeHwnd()) m_overlay.DestroyWindow();
}

void CaptureSession::OnToolbar(tb::Id id) {
    if (tb::IsTool(id)) {
        // Clicking the active tool again drops back to plain selection.
        SetActiveTool(id == m_activeTool ? tb::Id::None : id);
        return;
    }
    switch (id) {
    case tb::Id::Undo:     Undo(); break;
    case tb::Id::LongShot: ToggleLongShot(); break;
    case tb::Id::Save:     Save(); break;
    case tb::Id::Pin:      Pin(); break;
    case tb::Id::Ocr:      StartOcr(); break;
    case tb::Id::Cancel:   Finish(false); break;
    case tb::Id::Done:     Accept(); break;
    default: break;
    }
}

annot::Annotation* CaptureSession::AddAnnotation(
    std::unique_ptr<annot::Annotation> a) {
    annot::Annotation* raw = a.get();

    annot::Edit e;
    e.op = annot::Edit::Op::Add;
    e.index = m_annos.Count();
    m_annos.Add(std::move(a));
    m_undo.push_back(std::move(e));
    m_mosaic.Invalidate();
    m_overlay.TouchBase();
    return raw;
}

void CaptureSession::RemoveAnnotation(int idx) {
    if (idx < 0) return;

    annot::Edit e;
    e.op = annot::Edit::Op::Remove;
    e.index = (size_t)idx;
    e.item = m_annos.RemoveAt((size_t)idx);
    if (!e.item) return;
    m_undo.push_back(std::move(e));

    m_mosaic.Invalidate();
    m_overlay.TouchBase();
    if (m_selIdx == idx) m_selIdx = -1;
    else if (m_selIdx > idx) --m_selIdx;
}

void CaptureSession::RecordMove(int idx, std::unique_ptr<annot::Annotation> before) {
    if (idx < 0 || !before) return;

    annot::Edit e;
    e.op = annot::Edit::Op::Replace;
    e.index = (size_t)idx;
    e.item = std::move(before);
    m_undo.push_back(std::move(e));
    m_mosaic.Invalidate();
    m_overlay.TouchBase();
}

void CaptureSession::ApplyStyleToSelected() {
    annot::Annotation* a = Selected();
    if (!a) return;
    const tb::Style& st = m_style;
    a->SetStyle(st.Color(), (Gdiplus::REAL)st.PenWidth());
    // A label being typed into is drawn by its input control, not by the base
    // canvas, which skips it, so the shape's own ink and font are not enough to
    // make the change visible: both have to go into the editor as well, or the
    // click reads as doing nothing until the edit loses focus.
    CTextEditor* ed = Editor();
    if (ed && ed->Label() == a) {
        ed->SetInk(st.Color());
        // Sets the label's font too, then rebuilds the control's and moves it
        // onto the box the new size needs.
        ed->ApplyFontSize(st.fontSize);
    } else {
        a->SetFontSize(st.fontSize);
    }
    // A mosaic band is filled from the still plus the other shapes, so changing
    // any shape's ink can change what a neighbouring band shows.
    m_mosaic.Invalidate();
    m_overlay.TouchBase();
}

void CaptureSession::Undo() {
    if (m_undo.empty()) return;

    annot::Edit e = std::move(m_undo.back());
    m_undo.pop_back();
    m_selIdx = annot::ApplyUndo(m_annos, std::move(e));
    m_mosaic.Invalidate();
    m_overlay.TouchBase();
}

void CaptureSession::ResetCanvas() {
    // An open 文字 edit points at a shape this is about to delete, so close it
    // first. Nothing is committed: the label goes with the rest of the canvas.
    if (m_editor) EndTextEdit(false);
    // The history goes with the drawings: undoing after this would put back
    // shapes the region no longer covers, which is exactly what the reset is
    // meant to clear.
    m_annos.Clear();
    m_undo.clear();
    m_selIdx = -1;
    SetActiveTool(tb::Id::None);
    m_sel->Set(m_sel->Bounds());
    m_mosaic.Invalidate();
    m_overlay.ResetPicked();
    m_overlay.TouchBase();
    // The bars hang off the region's bottom edge, and the property bar just
    // went away with the tool, so both have to move.
    m_overlay.LayoutChrome();
}

void CaptureSession::Accept() {
    std::unique_ptr<Gdiplus::Bitmap> bmp = out::RenderSelection(
        *m_capture, ExportRect(), m_annos, CapOff());
    if (bmp) out::SetClipboard(*bmp);
    Finish(true);
}

void CaptureSession::Save() {
    std::unique_ptr<Gdiplus::Bitmap> bmp =
        out::RenderSelection(*m_capture, ExportRect(), m_annos, CapOff());
    if (!bmp) return;

    // The common dialog is not topmost, so the overlay has to step down for it.
    m_overlay.SetTopmost(false);
    if (out::SaveWithDialog(*bmp, m_overlay.GetSafeHwnd())) {
        // The file is on disk, so this capture is over -- the same way 完成 ends
        // it. Nothing is put back on top: Finish only posts to the sink window,
        // and the sink tears the overlay down outside this message handler.
        Finish(true);
        return;
    }
    m_overlay.SetTopmost(true);  // 取消 the dialog: nothing happened.
}

void CaptureSession::Pin() {
    const CRect box = ExportRect();
    std::unique_ptr<Gdiplus::Bitmap> bmp =
        out::RenderSelection(*m_capture, box, m_annos, CapOff());
    if (!bmp) return;

    // The selection lives in the overlay's client space, which starts at the
    // virtual screen's top-left; the pin window wants screen coordinates.
    const POINT org = m_overlay.Origin();
    const RECT r = box;
    const CRect screen(r.left + org.x, r.top + org.y, r.right + org.x, r.bottom + org.y);

    theApp.AddPin(std::move(bmp), screen);
    Finish(true);
}

void CaptureSession::StartOcr() {
    if (m_ocrBusy) return;
    std::unique_ptr<Gdiplus::Bitmap> bmp =
        out::RenderSelection(*m_capture, ExportRect(), m_annos, CapOff());
    if (!bmp) return;

    // The overlay stays up: the user may keep working on the selection while
    // the engine runs, and the result window is owned by the app, not here.
    if (!ocr::StartAsync(std::move(bmp), theApp.Sink()->GetSafeHwnd())) return;
    m_ocrBusy = true;
    m_overlay.ChromeChanged();
}

void CaptureSession::SetActiveTool(tb::Id id) {
    // Each tool keeps the line width it was last left on: 箭头-鼠标拖动画箭头.png
    // opens on the thin dot while 画笔 and 马赛克 open on the wide one, and
    // switching back and forth should not lose what the user picked.
    if (tb::IsTool(m_activeTool)) m_widthByTool[(int)m_activeTool] = m_style.widthIndex;
    m_activeTool = id;
    if (tb::IsTool(id)) m_style.widthIndex = m_widthByTool[(int)id];
    HideFontDropdown();
    m_overlay.ChromeChanged();
}

COLORREF CaptureSession::SampleBack(CRect box) const {
    Gdiplus::Bitmap* img = m_capture->Image();
    if (!img) return RGB(255, 255, 255);

    // `box` is in overlay-client space; the still does not always start there.
    const POINT off = CapOff();
    box.OffsetRect(-off.x, -off.y);

    // CRect members are LONG, so the literals have to be LONG too or the
    // template argument is ambiguous.
    RECT v{ std::max<LONG>(0, box.left), std::max<LONG>(0, box.top),
            std::min<LONG>((LONG)img->GetWidth(), box.right),
            std::min<LONG>((LONG)img->GetHeight(), box.bottom) };
    if (v.right <= v.left || v.bottom <= v.top) return RGB(255, 255, 255);

    // A 5x5 grid is enough to ride out text and rules under the caret, and
    // GetPixel on 25 samples costs nothing once per edit.
    long r = 0, g = 0, b = 0;
    for (int i = 0; i < 5; ++i)
        for (int j = 0; j < 5; ++j) {
            const int x = v.left + (v.right - v.left) * i / 4;
            const int y = v.top + (v.bottom - v.top) * j / 4;
            Gdiplus::Color c;
            if (img->GetPixel(x, y, &c) != Gdiplus::Ok) continue;
            r += c.GetRed();
            g += c.GetGreen();
            b += c.GetBlue();
        }
    return RGB(r / 25, g / 25, b / 25);
}

void CaptureSession::BeginTextEdit(CPoint at, annot::ShapeText* target) {
    if (m_editor) EndTextEdit(true);
    HideFontDropdown();

    const int fontPx = (int)std::lround(m_style.fontSize * m_style.dpiScale);
    const HWND hw = m_overlay.GetSafeHwnd();

    if (!target) {
        // The box grows right and down from the press point, so a click near the
        // frame's right or bottom edge has to start back far enough for its first
        // line to be inside the 选区 at all. The other two edges need the room the
        // two frames take up between them: a label created on the edge would carry
        // its red frame under the 选区's own until it was dragged.
        CPoint origin = at;
        const CRect sel(m_sel->Rect());
        const int pad = (int)(annot::kFrameClearance + annot::kEditFramePad);
        const Gdiplus::REAL oneLine = annot::TextHeight(
            (Gdiplus::REAL)fontPx, (Gdiplus::REAL)Dpi::S(hw, annot::kTextPadY), 1);
        origin.x = std::max<LONG>(origin.x, sel.left + pad);
        origin.y = std::max<LONG>(origin.y, sel.top + pad);
        origin.x = std::min<LONG>(origin.x,
                                  sel.right - pad - Dpi::S(hw, annot::kTextMinW));
        origin.y = std::min<LONG>(origin.y, sel.bottom - pad - (LONG)oneLine);
        // The label joins the list before the edit opens, so the box on screen
        // while typing is the label's own — frame, markers and all. There is then
        // one geometry for the text, and resizing it mid-edit moves the caret with
        // it instead of leaving a second box behind.
        target = static_cast<annot::ShapeText*>(AddAnnotation(
            std::make_unique<annot::ShapeText>(
                Gdiplus::RectF((Gdiplus::REAL)origin.x, (Gdiplus::REAL)origin.y,
                               (Gdiplus::REAL)Dpi::S(hw, annot::kTextMinW),
                               oneLine),
                CString(), m_style.Color(), (Gdiplus::REAL)fontPx,
                m_style.dpiScale)));
        m_newText = m_annos.IndexOf(target);
    } else {
        m_editBefore = target->Clone();
    }
    Select(m_annos.IndexOf(target));

    // The editor paints its own background out of the overlay's base buffer, so
    // that buffer has to be current before the child gets its first paint — the
    // child is above us in z-order and paints first. Current, and current
    // without this label's own committed glyphs: they would come back through
    // the transparent backdrop as a ghost behind what is being typed.
    m_editSkip = target;
    m_overlay.DropFromBase(*target);
    m_overlay.UpdateWindow();

    auto ed = std::make_unique<CTextEditor>();
    const Gdiplus::RectF lb = target->Box();
    const CRect host((int)lb.X, (int)lb.Y, (int)(lb.X + lb.Width),
                     (int)(lb.Y + lb.Height));
    if (!ed->Create(&m_overlay, this, target, SampleBack(host))) {
        m_editSkip = nullptr;
        m_overlay.TouchBase();
        return;
    }
    m_editor = std::move(ed);
    m_overlay.InvalidateRect(nullptr, FALSE);
}

void CaptureSession::SyncEditor() {
    if (m_editor) m_editor->SyncToBox();
}

void CaptureSession::EndTextEdit(bool commit) {
    if (!m_editor) return;

    const CString text = m_editor->Text();
    annot::ShapeText* target = m_editor->Label();
    const int newIdx = m_newText;
    m_newText = -1;
    m_editor.reset();
    // Killing the edit leaves focus nowhere; the keyboard shortcuts live on the
    // overlay, so take it back.
    m_overlay.SetFocus();

    // A label that was never typed into is not an annotation: it goes back out
    // with the undo record that came with it, so one cancel does not cost two
    // Ctrl+Z.
    const bool discard = newIdx >= 0 && (text.IsEmpty() || !commit);
    if (discard) {
        m_annos.RemoveAt((size_t)newIdx);
        if (!m_undo.empty()) m_undo.pop_back();
        m_editBefore.reset();
    } else if (commit) {
        // The box is already the label's — the editor typed into it as it went.
        // Re-editing keeps the object, so undo puts the old string back rather
        // than deleting the whole label; a new one is covered by the Add record.
        target->SetText(text);
        if (newIdx < 0)
            RecordMove(m_annos.IndexOf(target), std::move(m_editBefore));
    } else if (m_editBefore) {
        // ESC: the label goes back exactly as the double click found it.
        m_annos.ReplaceAt((size_t)m_annos.IndexOf(target), std::move(m_editBefore));
    }

    // The base has been holding the canvas without this label for the whole edit;
    // it is the list's to draw again, and only once the list settled — otherwise
    // a cancel repaints the text that was just withdrawn.
    m_editSkip = nullptr;
    m_overlay.TouchBase();
    // 文字-已添加.png: a label that is merely committed shows its text and
    // nothing else. The frame and the markers come back when it is next clicked.
    Select(-1);
    m_overlay.InvalidateRect(nullptr, FALSE);
}

void CaptureSession::ToggleFontDropdown(const RECT* fontBoxScreen) {
    if (!m_fontDrop.IsRectEmpty()) {
        HideFontDropdown();
        return;
    }
    CRect r(*fontBoxScreen);
    m_overlay.ScreenToClient(r);
    const int gap = Dpi::S(m_overlay.GetSafeHwnd(), tb::kGap);
    const int row = Dpi::S(m_overlay.GetSafeHwnd(), tb::kFontRow);
    const int h = row * tb::kFontRowCount;

    // The reference hangs the list below the box; near the bottom edge that
    // would put it off screen, so it goes above instead.
    CRect cl;
    m_overlay.GetClientRect(&cl);
    const int top = r.bottom + gap + h > cl.bottom ? r.top - gap - h : r.bottom + gap;
    m_fontDrop = CRect(r.left, top, r.right, top + h);
    // ChromeChanged rather than Invalidate: the box's own border and ▼ change
    // with the list, and those live on the property bar.
    m_overlay.ChromeChanged();
}

void CaptureSession::HideFontDropdown() {
    if (m_fontDrop.IsRectEmpty()) return;
    m_fontDrop.SetRectEmpty();
    if (m_overlay.GetSafeHwnd()) m_overlay.ChromeChanged();
}

void CaptureSession::BeginFontSizeEdit() {
    // With a tool armed a press on existing ink selects it, so a label the user
    // means to resize is normally already selected. The editor case is the one
    // that needs the extra look-up: a label being typed into is selected too, but
    // the focus the input box is about to take ends that edit and clears the
    // selection, so the index has to be captured now.
    m_fontTarget = SelectedIndex();
    if (m_fontTarget < 0 && m_editSkip) m_fontTarget = m_annos.IndexOf(m_editSkip);
    HideFontDropdown();
}

void CaptureSession::EndFontSizeEdit(int px, bool commit) {
    const int idx = m_fontTarget;
    m_fontTarget = -1;
    if (!commit) return;
    m_style.fontSize = px;
    // Resolved by index rather than by pointer: the text edit that was running
    // when the box was pressed may have been committed and replaced in between.
    annot::Annotation* a = m_annos.At((size_t)idx);
    if (!a) return;
    // A label being typed into is drawn by its input control, which the base
    // canvas skips, so the control has to change size as well as the shape.
    CTextEditor* ed = Editor();
    if (ed && ed->Label() == a) ed->ApplyFontSize(px);
    else a->SetFontSize(px);
    m_mosaic.Invalidate();
    m_overlay.TouchBase();
}

int CaptureSession::NextBadgeNumber() const {
    int top = 0;
    for (size_t i = 0; i < m_annos.Count(); ++i)
        if (const auto* b = dynamic_cast<const annot::ShapeBadge*>(m_annos.At(i)))
            top = std::max(top, b->Number());
    return top + 1;
}

void CaptureSession::ShowTip(const wchar_t* text, CPoint anchor) {
    m_overlay.ScreenToClient(&anchor);
    m_tip.text = text;
    m_tip.anchor = anchor;
    if (m_overlay.GetSafeHwnd()) m_overlay.TipChanged(&anchor);
}

void CaptureSession::HideTip() {
    if (m_tip.text.IsEmpty()) return;
    m_tip.text.Empty();
    if (m_overlay.GetSafeHwnd()) m_overlay.TipChanged(nullptr);
}

void CaptureSession::Finish(bool accepted) {
    // Tearing the session down here would delete the overlay from inside its
    // own message handler, so bounce through the sink window instead.
    theApp.RequestEndCapture(accepted);
}

// ------------------------------------------------------------------- 长截图

POINT CaptureSession::CapOff() const {
    const POINT a = m_capture ? m_capture->Origin() : POINT{ 0, 0 };
    const POINT b = m_overlay.Origin();
    return POINT{ a.x - b.x, a.y - b.y };
}

void CaptureSession::ToggleLongShot() {
    // The bar's own ✕ is the way back out; the toolbar is hidden meanwhile.
    if (m_longShot) return;
    if (m_editor) EndTextEdit(true);
    HideTip();
    HideFontDropdown();
    m_activeTool = tb::Id::None;

    m_longShot = std::make_unique<ls::Controller>(this);
    if (!m_longShot->Start()) m_longShot.reset();
    m_overlay.ChromeChanged();
}

void CaptureSession::RunLongShotEdit() {
    if (!m_longShot) return;
    m_longShot->RunEdit();
    m_longShot.reset();  // RunEdit has already closed the hole and the popups
}

void CaptureSession::EndLongShot(std::unique_ptr<Gdiplus::Bitmap> bmp) {
    if (!bmp) return;
    // The screen outside the frame stays the screen, dimmed, as the reference
    // shows it, so the still the document replaces is kept rather than dropped.
    m_backdropOff = CapOff();
    m_backdrop = m_capture->Detach();
    // Any origin will do: the frame is placed below and SetOrigin puts the
    // document exactly where that frame wants it.
    m_capture->Adopt(std::move(bmp), m_overlay.Origin());
    m_lsEdit = true;
    m_lsScroll = 0;

    // The document outgrows the screen, so it cannot be shown whole. The
    // selection becomes a frame over it: as wide as the document, as tall as the
    // document when that fits, and otherwise 80% of the screen with the wheel
    // moving it. Centred, because the frame is where the work happens and the
    // toolbar hangs off its bottom edge.
    CRect cl;
    m_overlay.GetClientRect(&cl);
    const int w = (std::min)(m_capture->Width(), cl.Width());
    const int maxH = MulDiv(cl.Height(), 80, 100);
    const int h = (std::min)((std::min)(m_capture->Height(), maxH), cl.Height());
    CRect frame(0, 0, (std::max)(w, 1), (std::max)(h, 1));
    frame.OffsetRect((cl.Width() - frame.Width()) / 2,
                     (cl.Height() - frame.Height()) / 2);

    m_capture->SetOrigin(POINT{ m_overlay.Origin().x + frame.left,
                                m_overlay.Origin().y + frame.top });
    // The frame is a viewport, not a selection: it is fixed here, and the wheel
    // or its scrollbar moves the page instead of it.
    m_sel->Reset(cl);
    m_sel->Set(frame);
    m_mosaic.Invalidate();
    // The still itself was replaced by the stitched document.
    m_overlay.TouchBase();
    // ChromeChanged, not Invalidate: the selection just moved, so the toolbar has
    // to move to its new bottom edge.
    m_overlay.ChromeChanged();
}

// The wheel moves the document under the frame. The still follows through the
// capture's origin, which CapOff() reads, so the base, the mosaic, the loupe and
// the export all move together; the annotations live in client space and have to
// be carried by hand or they would slide off the page they were drawn on.
bool CaptureSession::ScrollLongShot(int delta) {
    if (!m_lsEdit) return false;
    const CRect frame = m_sel->Rect();
    const int maxScroll = (std::max)(0, m_capture->Height() - frame.Height());
    const int to = std::clamp(m_lsScroll + delta, 0, maxScroll);
    if (to == m_lsScroll) return false;
    const Gdiplus::REAL dy = (Gdiplus::REAL)(m_lsScroll - to);  // rows fall as we go down
    m_lsScroll = to;

    m_capture->SetOrigin(POINT{ m_overlay.Origin().x + frame.left,
                                m_overlay.Origin().y + frame.top - m_lsScroll });
    // Ink is pinned to the page, not to the viewport — and so is the copy each
    // undo step holds, or stepping back would drop the shape at the row it was
    // drawn on rather than the one it is on now.
    for (size_t i = 0; i < m_annos.Count(); ++i) m_annos.At(i)->Translate(0, dy);
    for (annot::Edit& e : m_undo)
        if (e.item) e.item->Translate(0, dy);
    m_mosaic.Invalidate();
    // Only the frame's ground moves: the backdrop outside it is a still, and the
    // frame itself is locked, so nothing beyond that rect is out of date.
    m_overlay.TouchBaseIn(frame);
    return true;
}

int CaptureSession::LongShotMaxScroll() const {
    if (!m_lsEdit) return 0;
    const CRect frame = m_sel->Rect();
    return (std::max)(0, m_capture->Height() - frame.Height());
}

CRect CaptureSession::ExportRect() const {
    if (!m_lsEdit) return m_sel->Rect();
    // The frame only picks which part of the page is on screen; ✓ still owes the
    // user the whole page.
    const POINT off = CapOff();
    return CRect(off.x, off.y, off.x + m_capture->Width(),
                 off.y + m_capture->Height());
}

bool CaptureSession::LongShotSizeText(CString& text) const {
    if (m_longShot && m_longShot->Active() && m_longShot->SizeText(&text)) return true;
    // 编辑 frames part of the page, but the page is still what is being made, so
    // the label keeps counting that rather than the window onto it.
    if (!m_lsEdit) return false;
    text.Format(L"%d x %d", m_capture->Width(), m_capture->Height());
    return true;
}

bool CaptureSession::HitLongShotCaret(CPoint pt) const {
    return m_longShot && m_longShot->HitCaret(pt);
}

void CaptureSession::ToggleLongShotPreview() {
    if (m_longShot) m_longShot->TogglePreview();
}

void CaptureSession::PaintLongShot(Gdiplus::Graphics& g) {
    if (m_longShot) m_longShot->Paint(g);
}

CRect CaptureSession::LongShotPreviewRect() const {
    return m_longShot ? m_longShot->PreviewRect() : CRect();
}

void CaptureSession::SetLongShotCaret(const CRect& r) {
    if (m_longShot) m_longShot->SetCaretRect(r);
}
