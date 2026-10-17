#pragma once

#include "FrameGrab.h"
#include "Stitcher.h"

#include <memory>
#include <vector>

class CaptureSession;
class CBarWnd;
class CTipWnd;

namespace ls {

// 长截图.png / 长截图-点击后.png / 长截图滚动合成.png. The selection stops being
// a region of the frozen still and becomes a hole in the overlay: the live
// window shows through it, the wheel reaches that window, and every frame that
// differs from what is already accumulated gets stitched onto the bottom.
//
// The bar and the tip card are top-level popups rather than overlay children
// because a window region clips child windows too, and both have to sit where
// the region has been cut away.
class Controller {
public:
    explicit Controller(CaptureSession* session);
    ~Controller();

    // Cuts the hole and opens the popups. False when the selection is too
    // small to leave an overlap band to match against.
    bool Start();
    // Only the popups: the caller decides what happens to the overlay.
    void Stop();

    bool Active() const { return m_active; }

    // Bar actions, in bar order: 编辑 ↓ ✕ ✓完成.
    void OnEdit();
    void OnSave();
    void OnCancel();
    void OnDone();
    // 编辑 runs here, one message turn after the bar's own handler.
    void RunEdit();

    // The stitched tail beside the hole. The overlay draws it because it lives
    // outside the hole and so survives the window region. PreviewRect is the
    // same box Paint inks, so the overlay can clear and blend just that.
    CRect PreviewRect() const;
    void Paint(Gdiplus::Graphics& g);
    void SetCaretRect(const CRect& r) { m_caret = r; }
    bool HitCaret(CPoint pt) const;
    void TogglePreview();

    // The size label counts what has been stitched, not the hole.
    bool SizeText(CString* out) const;

    // An owning copy of the whole stitched image.
    std::unique_ptr<Gdiplus::Bitmap> TakeResult();

private:
    friend class CBarWnd;
    friend class CTipWnd;

    void Tick();
    void PlacePopups();
    bool AppendRows(const Frame& f, int from, int count);
    bool PrependRows(const Frame& f, int from, int count);
    // Makes room for `before` rows above and `after` rows below the document,
    // moving it into a bigger buffer with slack at both ends when there is none.
    bool GrowFor(int before, int after);
    const uint32_t* Row(int r) const { return m_px.data() + (size_t)(m_first + r) * m_w; }
    uint32_t* Row(int r) { return m_px.data() + (size_t)(m_first + r) * m_w; }
    // The same rows hashed, laid out exactly like m_px, so a scroll back over
    // ground already stitched can be looked up in the whole document.
    const uint64_t* SigRow(int r) const { return m_sigs.data() + m_first + r; }
    uint64_t* SigRow(int r) { return m_sigs.data() + m_first + r; }
    std::vector<uint64_t> TailSignatures() const;
    std::vector<uint64_t> HeadSignatures() const;
    // Which way the content moved: rows > 0 is new content below, rows < 0 above.
    Shift Match(const std::vector<uint64_t>& sigs) const;
    void ShowStatus(const wchar_t* text);
    void StopPolling();
    void Repaint();

    CaptureSession* m_session;
    bool m_active = false;
    CRect m_sel{};     // overlay client coords: the hole
    CRect m_hole{};    // screen coords: what gets grabbed
    CRect m_caret{};   // overlay client coords, as last painted

    int m_w = 0;       // == m_sel.Width(); every frame is this wide
    // The document's rows, contiguous so the preview can wrap them directly.
    // They start at m_first: a scroll up grows the document at the top, and the
    // slack on that side is what keeps that from copying the whole image.
    std::vector<uint32_t> m_px;
    std::vector<uint64_t> m_sigs;
    int m_first = 0, m_rows = 0, m_cap = 0, m_maxRows = 0;
    int m_tail = 0, m_maxStep = 0;

    bool m_preview = true;
    bool m_showTip = true;
    bool m_stopped = false;

    std::unique_ptr<CBarWnd> m_bar;
    std::unique_ptr<CTipWnd> m_tipWnd;
};

}  // namespace ls
