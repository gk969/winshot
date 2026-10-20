#pragma once

namespace annot {

enum class Kind { Rect, Ellipse, Arrow, Pen, Mosaic, Text, Badge };

// The 选区 draws its own frame as a 2px pen centred on the selection edge, which
// means the frame owns the first pixel *inside* the selection. An annotation that
// stops at the edge shares that pixel and gets painted over, so the box that has
// to stay inside the 选区 clears the frame and leaves one more pixel empty.
constexpr Gdiplus::REAL kFrameClearance = 2.0f;

// The red frame a 文字 label is shown in is stroked outside the label's own box
// (COverlayWnd::DrawEditFrame inflates it by 2 and strokes a 1px pen on the
// half pixel), so for a label the box that needs the clearance is not the text
// box but the text box plus this. Measured on screen: the frame's outermost
// pixel is 3 columns left of the box and 2 rows above it, because the pen lands
// one pixel outside the rect it is given. The left side is the tight one.
constexpr Gdiplus::REAL kEditFramePad = 3.0f;

// How far ink reaches past the geometry that produced it: half the pen for a
// stroke, and the 1.5px an anti-aliased edge feathers when the pen is thinner
// than that. Shapes.h's InkBBox overrides and the drawing bounds both use it.
inline Gdiplus::REAL InkPadForPen(Gdiplus::REAL pen) {
    const Gdiplus::REAL half = pen / 2.0f;
    return half > 1.5f ? half : 1.5f;
}

// Geometry is stored in overlay-client pixels — the same space as the frozen
// still and the selection — so moving the selection carries the drawing with it
// and compositing is only a clip plus a translate.
class Annotation {
public:
    virtual ~Annotation() = default;

    virtual Kind GetKind() const = 0;
    virtual void Draw(Gdiplus::Graphics& g) const = 0;

    virtual Gdiplus::RectF BBox() const = 0;
    // What the drawing covers once the ink is down. BBox() is the geometry the
    // handles sit on, which for an outline is its centre line; this is the box
    // that has to stay inside the 选区.
    virtual Gdiplus::RectF InkBBox() const { return BBox(); }
    virtual bool HitTest(Gdiplus::PointF pt) const = 0;

    // Selection chrome. Handles are indexed 0..HandleCount()-1 in the same
    // order as the selection handles: TL, T, TR, R, BR, B, BL, L.
    // Whether the selection chrome draws a dashed-free box around BBox(). A rect
    // skips it because its own outline is the box; an arrow skips it because
    // 箭头-点击已画箭头可调整方向 位置 长短.png shows only the two endpoint rings.
    virtual bool NeedsBBoxGuide() const { return true; }

    // The stroke the shape is drawn with, in device px, or 0 for shapes that
    // have none. The selection chrome sizes its handles from it, so a thick
    // outline is not left with a marker thinner than the line it grabs.
    virtual Gdiplus::REAL PenWidth() const { return 0.0f; }

    virtual int HandleCount() const = 0;
    virtual Gdiplus::PointF HandleAt(int i) const = 0;
    virtual void MoveHandle(int i, Gdiplus::PointF pt) = 0;
    virtual void Translate(Gdiplus::REAL dx, Gdiplus::REAL dy) = 0;

    // Tool drag in progress: `to` is the current pointer position, `shift` the
    // Shift key state. Shapes dragged out from the press point update here;
    // shapes placed by a single click (the badge) ignore it.
    virtual void UpdateDrag(Gdiplus::PointF /*to*/, bool /*shift*/) {}

    // Called once when the drag ends, for shapes that want to tidy what the
    // pointer produced (a stroke drops the points a straight line already
    // implies).
    virtual void Commit() {}

    // The property bar's 粗细 and colour pickers. A shape that is already drawn
    // and selected changes with them, so every kind that has an ink or a stroke
    // width takes it; the ones that have neither ignore it.
    virtual void SetStyle(Gdiplus::Color /*ink*/, Gdiplus::REAL /*pen*/) {}
    // The 字号 picker, in design px: the shape scales it by its own dpiScale, so
    // this is the one place a logical size becomes a physical one. Only the 文字
    // label has a font; the rest ignore the picker.
    virtual void SetFontSize(int /*designPx*/) {}

    // Discarded on button up when true, so a stray click does not leave a
    // degenerate shape behind.
    virtual bool IsEmpty() const = 0;

    virtual std::unique_ptr<Annotation> Clone() const = 0;
};

}  // namespace annot
