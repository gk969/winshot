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
    using ShapeBox::ShapeBox;
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
    bool HitTest(Gdiplus::PointF pt) const override;
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
    void SetStyle(Gdiplus::Color, Gdiplus::REAL pen) override { m_pen = pen; }

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
               Gdiplus::REAL radius)
        : m_center(center), m_number(number), m_ink(ink), m_r(radius) {}

    Kind GetKind() const override { return Kind::Badge; }
    void Draw(Gdiplus::Graphics& g) const override;
    bool HitTest(Gdiplus::PointF pt) const override;
    Gdiplus::RectF BBox() const override;
    int HandleCount() const override { return 0; }
    Gdiplus::PointF HandleAt(int) const override { return Gdiplus::PointF(); }
    void MoveHandle(int, Gdiplus::PointF) override {}
    void Translate(Gdiplus::REAL dx, Gdiplus::REAL dy) override {
        m_center.X += dx;
        m_center.Y += dy;
    }
    bool IsEmpty() const override { return false; }
    std::unique_ptr<Annotation> Clone() const override;
    // The disc's size comes from its own radius, not the stroke width.
    void SetStyle(Gdiplus::Color ink, Gdiplus::REAL) override { m_ink = ink; }

    int Number() const { return m_number; }

private:
    Gdiplus::PointF m_center;
    int m_number;
    Gdiplus::Color m_ink;
    Gdiplus::REAL m_r;
};

// The 文字 tool: one line of text at a fixed size, committed from an inline edit
// control. 文字-已添加.png shows it with no frame and no selection chrome.
class ShapeText : public Annotation {
public:
    ShapeText(Gdiplus::PointF at, CString text, Gdiplus::Color ink, Gdiplus::REAL fontPx)
        : m_at(at), m_text(std::move(text)), m_ink(ink), m_fontPx(fontPx) {}

    Kind GetKind() const override { return Kind::Text; }
    void Draw(Gdiplus::Graphics& g) const override;
    bool HitTest(Gdiplus::PointF pt) const override;
    Gdiplus::RectF BBox() const override;
    int HandleCount() const override { return 0; }
    Gdiplus::PointF HandleAt(int) const override { return Gdiplus::PointF(); }
    void MoveHandle(int, Gdiplus::PointF) override {}
    void Translate(Gdiplus::REAL dx, Gdiplus::REAL dy) override {
        m_at.X += dx;
        m_at.Y += dy;
    }
    bool IsEmpty() const override { return m_text.IsEmpty(); }
    std::unique_ptr<Annotation> Clone() const override;
    // Size comes from the font, not the stroke width.
    void SetStyle(Gdiplus::Color ink, Gdiplus::REAL) override { m_ink = ink; }

    const CString& Text() const { return m_text; }
    void SetText(const CString& t) { m_text = t; }
    Gdiplus::Color Ink() const { return m_ink; }
    Gdiplus::REAL FontPx() const { return m_fontPx; }
    Gdiplus::PointF At() const { return m_at; }

private:
    Gdiplus::RectF Layout() const;  // the DrawString box, in client px

    Gdiplus::PointF m_at;
    CString m_text;
    Gdiplus::Color m_ink;
    Gdiplus::REAL m_fontPx;
};

// Width `text` takes in the 文字 face at `fontPx`, so the inline editor can grow
// its box with what is typed.
Gdiplus::REAL MeasureTextWidth(const CString& text, Gdiplus::REAL fontPx);

// Starts the shape for the active tool at the press point; the drag then grows
// it through Annotation::UpdateDrag. `ordinal` numbers the badge tool, `mosaic`
// feeds the 马赛克 brush.
std::unique_ptr<Annotation> MakeShape(tb::Id tool, Gdiplus::PointF from,
                                      const tb::Style& style, int ordinal,
                                      MosaicSource* mosaic);

}  // namespace annot
