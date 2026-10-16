#pragma once

namespace annot {

enum class Kind { Rect, Ellipse, Arrow, Pen, Mosaic, Text, Badge };

// Geometry is stored in overlay-client pixels — the same space as the frozen
// still and the selection — so moving the selection carries the drawing with it
// and compositing is only a clip plus a translate.
class Annotation {
public:
    virtual ~Annotation() = default;

    virtual Kind GetKind() const = 0;
    virtual void Draw(Gdiplus::Graphics& g) const = 0;

    virtual Gdiplus::RectF BBox() const = 0;
    virtual bool HitTest(Gdiplus::PointF pt) const = 0;

    // Selection chrome. Handles are indexed 0..HandleCount()-1 in the same
    // order as the selection handles: TL, T, TR, R, BR, B, BL, L.
    // Whether the selection chrome draws a dashed-free box around BBox(). A rect
    // skips it because its own outline is the box; an arrow skips it because
    // 箭头-点击已画箭头可调整方向 位置 长短.png shows only the two endpoint rings.
    virtual bool NeedsBBoxGuide() const { return true; }

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

    // Discarded on button up when true, so a stray click does not leave a
    // degenerate shape behind.
    virtual bool IsEmpty() const = 0;

    virtual std::unique_ptr<Annotation> Clone() const = 0;
};

}  // namespace annot
