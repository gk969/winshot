#include "stdafx.h"
#include "CaptureSession.h"
#include "DesktopCapture.h"
#include "SelectionModel.h"
#include "WinshotApp.h"
#include "../HiddenWnd.h"
#include "AppMessages.h"
#include "Compositor.h"
#include "ClipboardImage.h"
#include "ExportPng.h"
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
    case tb::Id::Save:     SavePng(); break;
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
}

void CaptureSession::Undo() {
    if (m_undo.empty()) return;

    annot::Edit e = std::move(m_undo.back());
    m_undo.pop_back();
    m_selIdx = annot::ApplyUndo(m_annos, std::move(e));
    m_mosaic.Invalidate();
    if (m_overlay.GetSafeHwnd()) m_overlay.InvalidateRect(nullptr, FALSE);
}

void CaptureSession::Accept() {
    std::unique_ptr<Gdiplus::Bitmap> bmp = out::RenderSelection(
        *m_capture, m_sel->Rect(), m_annos, CapOff());
    if (bmp) out::SetClipboard(*bmp);
    Finish(true);
}

void CaptureSession::SavePng() {
    std::unique_ptr<Gdiplus::Bitmap> bmp =
        out::RenderSelection(*m_capture, m_sel->Rect(), m_annos, CapOff());
    if (!bmp) return;

    // The common dialog is not topmost, so the overlay has to step down for it.
    m_overlay.SetTopmost(false);
    out::SavePngWithDialog(*bmp, m_overlay.GetSafeHwnd());
    m_overlay.SetTopmost(true);
}

void CaptureSession::Pin() {
    std::unique_ptr<Gdiplus::Bitmap> bmp =
        out::RenderSelection(*m_capture, m_sel->Rect(), m_annos, CapOff());
    if (!bmp) return;

    // The selection lives in the overlay's client space, which starts at the
    // virtual screen's top-left; the pin window wants screen coordinates.
    const POINT org = m_overlay.Origin();
    const RECT r = m_sel->Rect();
    const CRect screen(r.left + org.x, r.top + org.y, r.right + org.x, r.bottom + org.y);

    theApp.AddPin(std::move(bmp), screen);
    Finish(true);
}

void CaptureSession::StartOcr() {
    if (m_ocrBusy) return;
    std::unique_ptr<Gdiplus::Bitmap> bmp =
        out::RenderSelection(*m_capture, m_sel->Rect(), m_annos, CapOff());
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

    CPoint origin = at;
    CString text;
    Gdiplus::Color ink = m_style.Color();
    if (target) {
        origin = CPoint((LONG)target->At().X, (LONG)target->At().Y);
        text = target->Text();
        ink = target->Ink();
    }
    const int fontPx = (int)std::lround(m_style.fontSize * m_style.dpiScale);

    auto ed = std::make_unique<CTextEditor>();
    const CRect box(origin.x, origin.y,
                    origin.x + Dpi::S(m_overlay.GetSafeHwnd(), 40),
                    origin.y + fontPx + Dpi::S(m_overlay.GetSafeHwnd(), 20));
    if (!ed->Create(&m_overlay, this, origin, text, fontPx, ink, SampleBack(box),
                    target))
        return;
    m_editor = std::move(ed);
    m_overlay.InvalidateRect(nullptr, FALSE);
}

void CaptureSession::EndTextEdit(bool commit) {
    if (!m_editor) return;

    const CString text = m_editor->Text();
    annot::ShapeText* target = m_editor->Target();
    const CPoint at = m_editor->At();
    const int fontPx = m_editor->FontPx();
    const Gdiplus::Color ink = target ? target->Ink() : m_style.Color();
    m_editor.reset();
    // Killing the edit leaves focus nowhere; the keyboard shortcuts live on the
    // overlay, so take it back.
    m_overlay.SetFocus();

    if (commit && !text.IsEmpty()) {
        if (target) {
            // Re-editing keeps the object: undo puts the old string back rather
            // than deleting the whole label.
            const int idx = m_annos.IndexOf(target);
            std::unique_ptr<annot::Annotation> before = target->Clone();
            target->SetText(text);
            RecordMove(idx, std::move(before));
        } else {
            AddAnnotation(std::make_unique<annot::ShapeText>(
                Gdiplus::PointF((Gdiplus::REAL)at.x, (Gdiplus::REAL)at.y), text,
                ink, (Gdiplus::REAL)fontPx));
        }
    }
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
    const int h = row * (int)(sizeof(tb::kFontSizes) / sizeof(int));

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
    if (m_overlay.GetSafeHwnd()) m_overlay.InvalidateRect(nullptr, FALSE);
}

void CaptureSession::HideTip() {
    if (m_tip.text.IsEmpty()) return;
    m_tip.text.Empty();
    if (m_overlay.GetSafeHwnd()) m_overlay.InvalidateRect(nullptr, FALSE);
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

void CaptureSession::EndLongShot(std::unique_ptr<Gdiplus::Bitmap> bmp, POINT anchor) {
    if (!bmp) return;
    m_capture->Adopt(std::move(bmp), anchor);

    // The stitched document starts at the hole's corner and runs past the
    // bottom of the screen. The selection covers all of it — ✓ and 保存 have to
    // keep the whole document — and the model's bounds widen to match, so what
    // hangs below the screen is out of view rather than cut off.
    const POINT off = CapOff();
    m_sel->Reset(RECT{ off.x, off.y, off.x + m_capture->Width(),
                       off.y + m_capture->Height() });
    m_mosaic.Invalidate();
    // ChromeChanged, not Invalidate: the selection just grew, so the toolbar has
    // to move to its new bottom edge.
    m_overlay.ChromeChanged();
}

bool CaptureSession::LongShotSizeText(CString& text) const {
    return m_longShot && m_longShot->Active() && m_longShot->SizeText(&text);
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

void CaptureSession::SetLongShotCaret(const CRect& r) {
    if (m_longShot) m_longShot->SetCaretRect(r);
}
