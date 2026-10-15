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
    // outside the hole and so survives the window region.
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
    bool EnsureCapacity(int rows);
    std::vector<uint64_t> TailSignatures() const;
    void ShowStatus(const wchar_t* text);
    void StopPolling();
    void Repaint();

    CaptureSession* m_session;
    bool m_active = false;
    CRect m_sel{};     // overlay client coords: the hole
    CRect m_hole{};    // screen coords: what gets grabbed
    CRect m_caret{};   // overlay client coords, as last painted

    int m_w = 0;       // == m_sel.Width(); every frame is this wide
    std::vector<uint32_t> m_px;
    int m_rows = 0, m_cap = 0, m_maxRows = 0;
    int m_tail = 0, m_maxStep = 0;

    bool m_preview = true;
    bool m_showTip = true;
    bool m_stopped = false;

    std::unique_ptr<CBarWnd> m_bar;
    std::unique_ptr<CTipWnd> m_tipWnd;
};

}  // namespace ls
