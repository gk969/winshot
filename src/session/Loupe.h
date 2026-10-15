#pragma once

class CaptureSession;
class DesktopCapture;

// 默认选择全屏,周围有蓝框.png: the magnifier that rides with the cursor while
// no annotation tool is armed — the still at 5x with a crosshair on the sampled
// pixel, and a four-line readout hanging under it.
namespace loupe {

// Logical px, measured off that reference: a 117x85 card with a 1px frame and a
// 115x83 field, and a 62px readout whose top edge is the frame's bottom one.
inline constexpr int kBoxW = 117, kBoxH = 85;
inline constexpr int kFieldW = 115, kFieldH = 83;
inline constexpr int kScale = 5;
inline constexpr int kInfoH = 62;
inline constexpr int kInfoPad = 6, kInfoLine = 14, kInfoFont = 12;

inline const Gdiplus::Color kFrame(0xFF343434);
inline const Gdiplus::Color kCross(0xFF4DCAFA);
inline const Gdiplus::Color kInfoBack(0xFF333333);
inline const Gdiplus::Color kInfoText(0xFFFFFFFF);

// Whole card — magnifier plus readout — for a cursor at `at`, clamped into
// `bounds`. The card is centred on the cursor, so the crosshair lands on it.
RECT CardRect(HWND hwnd, CPoint at, const CRect& bounds);

// The still's colour under the cursor, as the readout prints it. `off` is where
// the capture starts in cursor space — see out::RenderSelection.
COLORREF Sampled(const DesktopCapture& cap, CPoint at, POINT off);

void Draw(CaptureSession& session, CPoint at, Gdiplus::Graphics& g, const CRect& bounds);

// 按c复制色号: the readout's RGB line, onto the clipboard as text.
bool CopyColor(const DesktopCapture& cap, CPoint at, POINT off);

}  // namespace loupe
