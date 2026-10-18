#pragma once

// Shared vocabulary for the capture chrome: slot identity, metrics and colours.
// Metrics are logical (96 dpi) pixels measured from 工具栏.png / 工具栏-矩形-点击后.png,
// both 1:1: the toolbar band is 32px tall on a 27px button pitch, the property
// bar under it is 37px tall with 13px colour swatches on a 15px pitch.
namespace tb {

enum class Id : int {
    None = -1,
    // Tools, contiguous so the active-tool test is a range check.
    Rect, Ellipse, Arrow, Pen, Mosaic, Text, Badge,
    // Commands.
    Undo, LongShot, Ocr, Pin, Record, Save,
    Cancel, Done,
};

inline bool IsTool(Id id) { return id >= Id::Rect && id <= Id::Badge; }

inline constexpr int kHeight = 32;
inline constexpr int kCell = 27;
inline constexpr int kGlyph = 16;
inline constexpr int kSep = 14;
inline constexpr int kPad = 4;
inline constexpr int kGap = 2;      // chrome-to-chrome and chrome-to-selection gap

// Property bar.
inline constexpr int kPropHeight = 37;
inline constexpr int kPropPad = 13;      // bar edge -> first dot centre
inline constexpr int kDotPitch = 25;
inline constexpr int kDotSizes[3] = { 2, 4, 8 };
inline constexpr int kDotBox = 24;       // frame around the selected dot
inline constexpr int kSwatch = 13;
inline constexpr int kSwatchPitch = 15;
inline constexpr int kSwatchRows = 2;
inline constexpr int kCurrentSwatch = 26;

// Both property bars put the divider 76..77px in from the bar edge and the
// large current-colour chip just after it; the palette grid follows at 119.
inline constexpr int kSepX = 77;
inline constexpr int kCurrentX = 85;

// Text property bar: the 字号 box and the list it drops down (文字-字体大小.png).
// Measured off that reference: the box is 46x23 centred in the 37px bar, 30px in
// from its left edge; the list hangs 2px under it, same width, 20px per row.
inline constexpr int kFontSizes[6] = { 12, 14, 16, 18, 20, 22 };
inline constexpr int kFontBoxX = 30;      // bar edge -> box left
inline constexpr int kFontBoxW = 46;
inline constexpr int kFontBoxH = 23;
inline constexpr int kFontRow = 20;       // one row of the dropdown list
inline constexpr int kFontPad = 7;        // box edge -> the digits
inline constexpr int kFontArrow = 9;      // box right edge -> the ▼ centre

// Mosaic property bar: 模糊度 and the slider that sets the block size
// (马赛克-鼠标拖动变模糊.png). Measured off that reference: the label runs
// 86..121, the track 125..235 — 110px of 4px-tall rail with an 11x14 white
// thumb. The thumb there sits at 64%, which is 17 on the 4..24 block scale the
// band's measured ~15px squares agree with.
inline constexpr int kBlurMin = 4, kBlurMax = 24;
inline constexpr int kMosaicLabelX = 86;
inline constexpr int kMosaicTrackX = 125;
inline constexpr int kMosaicTrackW = 110;
inline constexpr int kMosaicTrackH = 4;
inline constexpr int kMosaicThumbW = 11;
inline constexpr int kMosaicThumbH = 14;

inline const Gdiplus::Color kTrackFill(0xFF66AFEA);
inline const Gdiplus::Color kTrackRest(0xFFD3D3D3);
inline const Gdiplus::Color kThumbEdge(0xFFA8A8A8);

inline const Gdiplus::Color kBack(0xFFEBEFF3);
inline const Gdiplus::Color kBorder(0xFFC9CDD2);
inline const Gdiplus::Color kInk(0xFF1F2328);
inline const Gdiplus::Color kDisabled(0x661F2328);
inline const Gdiplus::Color kSepLine(0xFFBCC5C9);
inline const Gdiplus::Color kHot(0x1A000000);
inline const Gdiplus::Color kPressed(0x2E000000);
inline const Gdiplus::Color kActive(0x14000000);
inline const Gdiplus::Color kActiveBorder(0xFFA9B0B6);
inline const Gdiplus::Color kAccent(0xFF2E92E1);

// The palette sampled from the reference property bar, 2 rows x 8 columns.
inline const Gdiplus::Color kPalette[16] = {
    Gdiplus::Color(0xFF000000), Gdiplus::Color(0xFF808080), Gdiplus::Color(0xFF7A0103),
    Gdiplus::Color(0xFFF8883C), Gdiplus::Color(0xFF338431), Gdiplus::Color(0xFF365CD1),
    Gdiplus::Color(0xFF7F027C), Gdiplus::Color(0xFF039A9A),
    Gdiplus::Color(0xFFFFFFFF), Gdiplus::Color(0xFFC0C0C0), Gdiplus::Color(0xFFF73840),
    Gdiplus::Color(0xFFFFFF00), Gdiplus::Color(0xFF9ACA08), Gdiplus::Color(0xFF3795DF),
    Gdiplus::Color(0xFFFF00FF), Gdiplus::Color(0xFF17DDD9),
};

inline constexpr int kDefaultColor = 10;  // the red the reference starts on

// What the property bar edits and the annotations read. Pen width is an index
// into kDotSizes; the shape tools resolve it to pixels when they draw.
struct Style {
    int colorIndex = kDefaultColor;
    int widthIndex = 1;   // the middle dot: the widest one covers what is under it
    int fontSize = 18;
    int blurBlockSize = 12;
    // Logical→physical factor, set once per capture. Tools whose size is a
    // design constant rather than a pen width (the badge circle) scale by it.
    float dpiScale = 1.0f;

    Gdiplus::Color Color() const { return kPalette[colorIndex]; }
    int PenWidth() const { return kDotSizes[widthIndex]; }
};

}  // namespace tb
