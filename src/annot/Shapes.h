#pragma once

#include "Annotation.h"
#include "HandleGeom.h"

#include <vector>

namespace tb { enum class Id : int; struct Style; }

namespace annot {

class MosaicSource;

// The face the 文字 tool draws and edits with; shared so the inline editor and
// the committed annotation agree on metrics.
extern const wchar_t kTextFace[];

// The 文字 box padding and floor. Shared so the red frame the editor strokes and
// the box the committed label carries are the same rect — the frame must not
// jump when the edit commits. Both are unscaled design px; a shape scales them
// by its own dpiScale.
inline constexpr int kTextPadX = 4;
inline constexpr int kTextPadY = 20;
inline constexpr int kTextMinW = 40;
// The red frame the overlay strokes 2px outside the box, plus the pixel the line
// lands on. Part of the label to the pointer: it is the only band of the box the
// overlay can be asked about while the input control covers the inside.
inline constexpr int kTextFramePad = 3;

// The 数字标 disc for a given stroke width: the three 粗细 dots pick three discs,
// the middle one the size the tool had before the dots meant anything to it.
// Design px; the shape scales it by its own dpiScale.
Gdiplus::REAL BadgeRadiusForPen(Gdiplus::REAL pen);

// The 马赛克 band's diameter for a given 粗细 dot. Four times the dot: the band is
// what has to cover the thing being redacted, and at twice the dot the widest
// setting was a 16px stripe against 18px text, so a band could not hide a line.
// Design px.
Gdiplus::REAL MosaicBandForPen(Gdiplus::REAL pen);

// The 矩形's stroke for a given 粗细 dot — the one tool that reads the thin dot as
// 1px. Both the fresh shape and a re-styled one go through it, or the two would
// disagree. Design px.
Gdiplus::REAL RectPen(Gdiplus::REAL pen);

// Rect and ellipse share a bounding box and its eight handles; only the paint
// and the hit test differ.
class ShapeBox : public Annotation {
public:
    ShapeBox(Gdiplus::PointF from, Gdiplus::Color ink, Gdiplus::REAL pen)
        : m_origin(from), m_box(from.X, from.Y, 0.0f, 0.0f), m_ink(ink), m_pen(pen) {}

    void UpdateDrag(Gdiplus::PointF to, bool) override;
    bool IsEmpty() const override {
        return m_box.Width < 3.0f || m_box.Height < 3.0f;
    }

    Gdiplus::RectF BBox() const override { return m_box; }
    // The outline is painted centred on the box, so half the pen hangs outside
    // it — the only shape whose drawn box is not its handle box.
    Gdiplus::RectF InkBBox() const override {
        const Gdiplus::REAL pad = m_pen / 2.0f;
        return Gdiplus::RectF(m_box.X - pad, m_box.Y - pad,
                              m_box.Width + pad * 2.0f, m_box.Height + pad * 2.0f);
    }
    Gdiplus::REAL PenWidth() const override { return m_pen; }
    int HandleCount() const override { return kBoxHandles; }
    Gdiplus::PointF HandleAt(int i) const override { return BoxHandleAt(m_box, i); }
    void MoveHandle(int i, Gdiplus::PointF pt) override { BoxResize(m_box, i, pt); }
    void Translate(Gdiplus::REAL dx, Gdiplus::REAL dy) override {
        m_box.X += dx;
        m_box.Y += dy;
    }
    void SetStyle(Gdiplus::Color ink, Gdiplus::REAL pen) override {
        m_ink = ink;
        m_pen = pen;
    }

protected:
    // Distance from pt to the drawn outline, for the hit test.
    Gdiplus::REAL OutlineDistance(Gdiplus::PointF pt) const;

    Gdiplus::PointF m_origin;
    Gdiplus::RectF m_box;
    Gdiplus::Color m_ink;
    Gdiplus::REAL m_pen;
};

class ShapeRect : public ShapeBox {
public:
    ShapeRect(Gdiplus::PointF from, Gdiplus::Color ink, Gdiplus::REAL pen)
        : ShapeBox(from, ink, RectPen(pen)) {}
    // The width the 粗细 dot asks for is not the width this shape draws with, so
    // both assignment paths map it. Without this one a rect redrawn from the bar
    // would come back a pixel thicker than one just drawn.
    void SetStyle(Gdiplus::Color ink, Gdiplus::REAL pen) override {
        ShapeBox::SetStyle(ink, RectPen(pen));
    }
    Kind GetKind() const override { return Kind::Rect; }
    bool NeedsBBoxGuide() const override { return false; }
    void Draw(Gdiplus::Graphics& g) const override;
    bool HitTest(Gdiplus::PointF pt) const override;
    std::unique_ptr<Annotation> Clone() const override;
};

class ShapeEllipse : public ShapeBox {
public:
    using ShapeBox::ShapeBox;
    Kind GetKind() const override { return Kind::Ellipse; }
    void Draw(Gdiplus::Graphics& g) const override;
    bool HitTest(Gdiplus::PointF pt) const override;
    std::unique_ptr<Annotation> Clone() const override;
};

// Freehand geometry. Resizing a scribble has no useful meaning, so strokes are
// moved as a whole and expose no handles.
class ShapeStroke : public Annotation {
public:
    ShapeStroke(Gdiplus::PointF from, Gdiplus::Color ink, Gdiplus::REAL pen)
        : m_ink(ink), m_pen(pen) {
        m_pts.push_back(from);
    }

    void UpdateDrag(Gdiplus::PointF to, bool) override { Append(to); }
    void Commit() override { Simplify(); }
    bool IsEmpty() const override { return m_pts.size() < 2; }

    Gdiplus::RectF BBox() const override;
    // Anti-aliasing feathers the edge about a pixel past the geometric outline,
    // and BBox() already carries only half a pixel of slack. Without the extra
    // room the fringe lands outside the rect the overlay clears before it
    // redraws, and the previous frame's stroke bleeds through next to it.
    Gdiplus::RectF InkBBox() const override {
        const Gdiplus::RectF b = BBox();
        return Gdiplus::RectF(b.X - 1.5f, b.Y - 1.5f, b.Width + 3.0f,
                              b.Height + 3.0f);
    }
    bool HitTest(Gdiplus::PointF pt) const override;
    Gdiplus::REAL PenWidth() const override { return m_pen; }
    int HandleCount() const override { return 0; }
    Gdiplus::PointF HandleAt(int) const override { return Gdiplus::PointF(); }
    void MoveHandle(int, Gdiplus::PointF) override {}
    void Translate(Gdiplus::REAL dx, Gdiplus::REAL dy) override;
    void SetStyle(Gdiplus::Color ink, Gdiplus::REAL pen) override {
        m_ink = ink;
        m_pen = pen;
    }

protected:
    void Append(Gdiplus::PointF p);
    void Simplify();
    void BuildPath(Gdiplus::GraphicsPath& path) const;
    // The stroke outline as a fillable region — what the mosaic clips to.
    void StrokeRegion(Gdiplus::GraphicsPath& path) const;
    Gdiplus::REAL PathDistance(Gdiplus::PointF pt) const;

    std::vector<Gdiplus::PointF> m_pts;
    Gdiplus::Color m_ink;
    Gdiplus::REAL m_pen;
};

class ShapePen : public ShapeStroke {
public:
    using ShapeStroke::ShapeStroke;
    Kind GetKind() const override { return Kind::Pen; }
    void Draw(Gdiplus::Graphics& g) const override;
    std::unique_ptr<Annotation> Clone() const override;
};

// 马赛克-鼠标拖动变模糊.png: a round-capped band filled with the content under
// it, averaged into squares of `block`. The band samples the still plus the
// other annotations, so ink drawn before it pixelates inside the band. Ink
// drawn after it pixelates too — the one place the shared cache shows, and a
// redaction brush is drawn last in practice.
class ShapeMosaic : public ShapeStroke {
public:
    ShapeMosaic(Gdiplus::PointF from, MosaicSource* src, Gdiplus::REAL pen, int block)
        : ShapeStroke(from, Gdiplus::Color(0xFF000000), pen), m_src(src), m_block(block) {}

    Kind GetKind() const override { return Kind::Mosaic; }
    void Draw(Gdiplus::Graphics& g) const override;
    std::unique_ptr<Annotation> Clone() const override;
    // The band is filled with the blurred content, so only the width of it is
    // the picker's to change; the inherited ink is a placeholder nothing draws.
    // The dot resolves through the same function the tool used to lay the band
    // down, so re-picking a width cannot shrink a band to the dot itself.
    void SetStyle(Gdiplus::Color, Gdiplus::REAL pen) override {
        m_pen = MosaicBandForPen(pen);
    }

private:
    MosaicSource* m_src;
    int m_block;
};

// 箭头-点击已画箭头可调整方向 位置 长短.png: selected, an arrow shows a ring on
// each endpoint and nothing else — no bounding box.
class ShapeArrow : public Annotation {
public:
    ShapeArrow(Gdiplus::PointF from, Gdiplus::Color ink, Gdiplus::REAL pen)
        : m_p0(from), m_p1(from), m_ink(ink), m_pen(pen) {}

    Kind GetKind() const override { return Kind::Arrow; }
    void Draw(Gdiplus::Graphics& g) const override;
    bool HitTest(Gdiplus::PointF pt) const override;
    Gdiplus::RectF BBox() const override;
    bool NeedsBBoxGuide() const override { return false; }
    Gdiplus::REAL PenWidth() const override { return m_pen; }
    int HandleCount() const override { return 2; }
    Gdiplus::PointF HandleAt(int i) const override { return i == 0 ? m_p0 : m_p1; }
    void MoveHandle(int i, Gdiplus::PointF pt) override {
        (i == 0 ? m_p0 : m_p1) = pt;
    }
    void Translate(Gdiplus::REAL dx, Gdiplus::REAL dy) override {
        m_p0.X += dx; m_p0.Y += dy;
        m_p1.X += dx; m_p1.Y += dy;
    }
    void UpdateDrag(Gdiplus::PointF to, bool shift) override;
    bool IsEmpty() const override;
    std::unique_ptr<Annotation> Clone() const override;
    void SetStyle(Gdiplus::Color ink, Gdiplus::REAL pen) override {
        m_ink = ink;
        m_pen = pen;
    }

    Gdiplus::REAL HeadLen() const;

private:
    Gdiplus::PointF m_p0, m_p1;
    Gdiplus::Color m_ink;
    Gdiplus::REAL m_pen;
};

// The ① tool: a filled disc with the ordinal in white, placed with one click.
class ShapeBadge : public Annotation {
public:
    ShapeBadge(Gdiplus::PointF center, int number, Gdiplus::Color ink,
               Gdiplus::REAL radius, Gdiplus::REAL dpiScale)
        : m_center(center), m_number(number), m_ink(ink), m_r(radius),
          m_dpiScale(dpiScale) {}

    Kind GetKind() const override { return Kind::Badge; }
    void Draw(Gdiplus::Graphics& g) const override;
    bool HitTest(Gdiplus::PointF pt) const override;
    Gdiplus::RectF BBox() const override;
    // The disc is anti-aliased, so its edge feathers about a pixel past the
    // geometry; without the slack a moved badge leaves its old fringe behind.
    Gdiplus::RectF InkBBox() const override {
        const Gdiplus::RectF b = BBox();
        return Gdiplus::RectF(b.X - 1.5f, b.Y - 1.5f, b.Width + 3.0f,
                              b.Height + 3.0f);
    }
    int HandleCount() const override { return 0; }
    Gdiplus::PointF HandleAt(int) const override { return Gdiplus::PointF(); }
    void MoveHandle(int, Gdiplus::PointF) override {}
    void Translate(Gdiplus::REAL dx, Gdiplus::REAL dy) override {
        m_center.X += dx;
        m_center.Y += dy;
    }
    bool IsEmpty() const override { return false; }
    std::unique_ptr<Annotation> Clone() const override;
    // The 粗细 dots are the badge's size picker: three widths, three discs.
    void SetStyle(Gdiplus::Color ink, Gdiplus::REAL pen) override {
        m_ink = ink;
        m_r = BadgeRadiusForPen(pen) * m_dpiScale;
    }

    int Number() const { return m_number; }

private:
    Gdiplus::PointF m_center;
    int m_number;
    Gdiplus::Color m_ink;
    Gdiplus::REAL m_r;
    Gdiplus::REAL m_dpiScale;
};

// The 文字 tool: text at a fixed size inside a box the user owns. Committed from
// an inline edit control, which hands over the box it ended on; the box then
// drives the wrap width, and lines that no longer fit inside it are hidden
// rather than growing the box. 文字-已添加.png shows it with no frame until it is
// selected, when it picks up the same eight handles a rectangle has.
class ShapeText : public Annotation {
public:
    ShapeText(const Gdiplus::RectF& box, CString text, Gdiplus::Color ink,
              Gdiplus::REAL fontPx, Gdiplus::REAL dpiScale)
        : m_box(box), m_text(std::move(text)), m_ink(ink), m_fontPx(fontPx),
          m_dpiScale(dpiScale) {}

    Kind GetKind() const override { return Kind::Text; }
    void Draw(Gdiplus::Graphics& g) const override;
    bool HitTest(Gdiplus::PointF pt) const override;
    // The ink is clipped to the box, so the box is both the handle geometry and
    // what has to stay inside the 选区.
    Gdiplus::RectF BBox() const override { return m_box; }
    // The box is drawn for this kind by the overlay — the same red frame whether
    // the label is merely selected or being edited — rather than as a selection
    // guide, so the input surface can sit inside it without covering it.
    bool NeedsBBoxGuide() const override { return false; }
    int HandleCount() const override { return kBoxHandles; }
    Gdiplus::PointF HandleAt(int i) const override { return BoxHandleAt(m_box, i); }
    void MoveHandle(int i, Gdiplus::PointF pt) override;
    void Translate(Gdiplus::REAL dx, Gdiplus::REAL dy) override {
        m_box.X += dx;
        m_box.Y += dy;
    }
    bool IsEmpty() const override { return m_text.IsEmpty(); }
    std::unique_ptr<Annotation> Clone() const override;
    // Size comes from the font, not the stroke width.
    void SetStyle(Gdiplus::Color ink, Gdiplus::REAL) override { m_ink = ink; }
    // The one place the 字号 picker's design px becomes the device px the box is
    // measured in; the inline editor reads the result back through FontPx().
    void SetFontSize(int designPx) override;

    const CString& Text() const { return m_text; }
    void SetText(const CString& t);
    Gdiplus::Color Ink() const { return m_ink; }
    Gdiplus::REAL FontPx() const { return m_fontPx; }
    Gdiplus::PointF At() const { return Gdiplus::PointF(m_box.X, m_box.Y); }
    Gdiplus::RectF Box() const { return m_box; }
    // The box the inline editor is typing into: it owns the geometry while the
    // edit is open, and the label keeps it afterwards.
    void AdoptBox(const Gdiplus::RectF& box);
    // Once a handle has moved, the width is the user's and typing stops growing
    // it — re-editing a label that was narrowed has to re-open at that width.
    bool UserSized() const { return m_userSized; }

    // The metrics the inline editor has to agree with, or the text jumps when
    // the edit closes.
    Gdiplus::REAL PadX() const;
    Gdiplus::REAL PadY() const;
    Gdiplus::REAL LineHeight() const;
    // The wrap width: the box less the padding kept around the text.
    Gdiplus::REAL TextWidth() const;

private:
    // Wrapped to TextWidth(), rebuilt whenever the text or the width changes —
    // BBox() and HitTest() run several times per mouse move.
    const std::vector<CString>& Lines() const;
    void InvalidateLayout() const;

    mutable CString m_src;        // the text m_lines was built from
    mutable Gdiplus::REAL m_srcW = -1.0f;  // ...and the width it was built for
    mutable std::vector<CString> m_lines;

    Gdiplus::RectF m_box;
    CString m_text;
    Gdiplus::Color m_ink;
    Gdiplus::REAL m_fontPx;
    Gdiplus::REAL m_dpiScale;
    bool m_userSized = false;
};

// Width `text` takes in the 文字 face at `fontPx`, so the inline editor can grow
// its box with what is typed.
Gdiplus::REAL MeasureTextWidth(const CString& text, Gdiplus::REAL fontPx);

// The line pitch the 文字 face uses at `fontPx`, in px. The editor needs it to
// know how tall to grow and the label needs it to place each line.
Gdiplus::REAL MeasureTextLineHeight(Gdiplus::REAL fontPx);

// `text` broken to fit `maxW`: Latin at the last space that fits, CJK between
// any two characters. Shared by the editor and the committed label so the two
// break in exactly the same place and the text does not move on commit.
std::vector<CString> WrapLines(const CString& text, Gdiplus::REAL fontPx,
                               Gdiplus::REAL maxW);

// Starts the shape for the active tool at the press point; the drag then grows
// it through Annotation::UpdateDrag. `ordinal` numbers the badge tool, `mosaic`
// feeds the 马赛克 brush.
std::unique_ptr<Annotation> MakeShape(tb::Id tool, Gdiplus::PointF from,
                                      const tb::Style& style, int ordinal,
                                      MosaicSource* mosaic);

}  // namespace annot
