#include "stdafx.h"
#include "Shapes.h"
#include "MosaicSource.h"
#include "Toolbar.h"

#include <algorithm>
#include <cmath>

namespace annot {
namespace {

Gdiplus::REAL DistToSeg(Gdiplus::PointF q, Gdiplus::PointF a, Gdiplus::PointF b) {
    const Gdiplus::REAL vx = b.X - a.X, vy = b.Y - a.Y;
    const Gdiplus::REAL len2 = vx * vx + vy * vy;
    if (len2 <= 0.0f) return std::hypot(q.X - a.X, q.Y - a.Y);
    Gdiplus::REAL t = ((q.X - a.X) * vx + (q.Y - a.Y) * vy) / len2;
    t = std::max(Gdiplus::REAL(0), std::min(Gdiplus::REAL(1), t));
    return std::hypot(q.X - (a.X + t * vx), q.Y - (a.Y + t * vy));
}

Gdiplus::REAL Side(Gdiplus::PointF u, Gdiplus::PointF v, Gdiplus::PointF w) {
    return (v.X - u.X) * (w.Y - u.Y) - (v.Y - u.Y) * (w.X - u.X);
}

bool InTriangle(Gdiplus::PointF p, Gdiplus::PointF a, Gdiplus::PointF b,
                Gdiplus::PointF c) {
    const Gdiplus::REAL s1 = Side(a, b, p), s2 = Side(b, c, p), s3 = Side(c, a, p);
    const bool neg = s1 < 0.0f || s2 < 0.0f || s3 < 0.0f;
    const bool pos = s1 > 0.0f || s2 > 0.0f || s3 > 0.0f;
    return !(neg && pos);
}

void RoundPen(Gdiplus::Pen& pen) {
    pen.SetStartCap(Gdiplus::LineCapRound);
    pen.SetEndCap(Gdiplus::LineCapRound);
    pen.SetLineJoin(Gdiplus::LineJoinRound);
}

void NoWrap(Gdiplus::StringFormat& fmt) {
    fmt.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);
    fmt.SetLineAlignment(Gdiplus::StringAlignmentNear);
}

}  // namespace

// The face the 文字 tool draws with; the inline editor uses the same one so the
// committed text lands exactly where the caret was.
const wchar_t kTextFace[] = L"Microsoft YaHei UI";

Gdiplus::REAL MeasureTextWidth(const CString& text, Gdiplus::REAL fontPx) {
    if (text.IsEmpty()) return 0.0f;
    Gdiplus::Bitmap tmp(1, 1, PixelFormat32bppARGB);
    Gdiplus::Graphics g(&tmp);
    Gdiplus::FontFamily family(kTextFace);
    Gdiplus::Font font(&family, fontPx, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
    Gdiplus::StringFormat fmt;
    NoWrap(fmt);
    Gdiplus::RectF box(0.0f, 0.0f, 100000.0f, 100000.0f), out{};
    g.MeasureString(text, text.GetLength(), &font, box, &fmt, &out);
    return out.Width;
}

// ---------------------------------------------------------------- box shapes

void ShapeBox::UpdateDrag(Gdiplus::PointF to, bool) {
    m_box = Gdiplus::RectF(std::min(m_origin.X, to.X), std::min(m_origin.Y, to.Y),
                           std::fabs(to.X - m_origin.X),
                           std::fabs(to.Y - m_origin.Y));
}

Gdiplus::REAL ShapeBox::OutlineDistance(Gdiplus::PointF pt) const {
    const Gdiplus::REAL l = m_box.X, t = m_box.Y;
    const Gdiplus::REAL r = m_box.X + m_box.Width, bo = m_box.Y + m_box.Height;

    if (m_box.Width <= 0.0f || m_box.Height <= 0.0f)
        return std::hypot(pt.X - l, pt.Y - t);

    if (pt.X >= l && pt.X <= r && pt.Y >= t && pt.Y <= bo) {
        // Inside: how far in from the nearest edge.
        return std::min({ pt.X - l, r - pt.X, pt.Y - t, bo - pt.Y });
    }
    const Gdiplus::REAL dx = std::max(Gdiplus::REAL(0), std::max(l - pt.X, pt.X - r));
    const Gdiplus::REAL dy = std::max(Gdiplus::REAL(0), std::max(t - pt.Y, pt.Y - bo));
    return std::hypot(dx, dy);
}

bool ShapeRect::HitTest(Gdiplus::PointF pt) const {
    const Gdiplus::REAL tol = std::max(m_pen, 6.0f) + 2.0f;
    return OutlineDistance(pt) <= tol;
}

bool ShapeEllipse::HitTest(Gdiplus::PointF pt) const {
    const Gdiplus::REAL rx = m_box.Width / 2.0f, ry = m_box.Height / 2.0f;
    if (rx <= 0.0f || ry <= 0.0f) return false;

    const Gdiplus::REAL nx = (pt.X - (m_box.X + rx)) / rx;
    const Gdiplus::REAL ny = (pt.Y - (m_box.Y + ry)) / ry;
    // Scaling the unit-circle offset by the smaller radius keeps the tolerance
    // roughly circular for a squashed ellipse.
    const Gdiplus::REAL d = (std::hypot(nx, ny) - 1.0f) * std::min(rx, ry);
    return std::fabs(d) <= std::max(m_pen, 6.0f) + 2.0f;
}

void ShapeRect::Draw(Gdiplus::Graphics& g) const {
    Gdiplus::Pen pen(m_ink, m_pen);
    g.DrawRectangle(&pen, m_box);
}

void ShapeEllipse::Draw(Gdiplus::Graphics& g) const {
    Gdiplus::Pen pen(m_ink, m_pen);
    g.DrawEllipse(&pen, m_box);
}

std::unique_ptr<Annotation> ShapeRect::Clone() const {
    return std::make_unique<ShapeRect>(*this);
}

std::unique_ptr<Annotation> ShapeEllipse::Clone() const {
    return std::make_unique<ShapeEllipse>(*this);
}

// ------------------------------------------------------------------- strokes

void ShapeStroke::Append(Gdiplus::PointF p) {
    const Gdiplus::PointF& last = m_pts.back();
    // The pointer reports at 60Hz; most of those samples are sub-pixel and only
    // slow every later hit test and widen down.
    if (std::hypot(p.X - last.X, p.Y - last.Y) < 3.0f) return;
    m_pts.push_back(p);
}

void ShapeStroke::Simplify() {
    if (m_pts.size() < 3) return;

    // Ramer-Douglas-Peucker, iteratively: the recursion depth of the textbook
    // version is the point count, which is exactly what a long stroke has.
    const Gdiplus::REAL eps = std::max(m_pen * 0.25f, 1.2f);
    std::vector<char> keep(m_pts.size(), 0);
    keep.front() = keep.back() = 1;

    std::vector<std::pair<size_t, size_t>> spans{{0, m_pts.size() - 1}};
    while (!spans.empty()) {
        const auto [i, j] = spans.back();
        spans.pop_back();

        Gdiplus::REAL worst = -1.0f;
        size_t at = i;
        for (size_t k = i + 1; k < j; ++k) {
            const Gdiplus::REAL d = DistToSeg(m_pts[k], m_pts[i], m_pts[j]);
            if (d > worst) {
                worst = d;
                at = k;
            }
        }
        if (worst <= eps) continue;

        keep[at] = 1;
        spans.push_back({i, at});
        spans.push_back({at, j});
    }

    std::vector<Gdiplus::PointF> out;
    out.reserve(m_pts.size());
    for (size_t k = 0; k < m_pts.size(); ++k)
        if (keep[k]) out.push_back(m_pts[k]);
    m_pts.swap(out);
}

void ShapeStroke::BuildPath(Gdiplus::GraphicsPath& path) const {
    if (m_pts.size() < 2) return;
    path.AddLines(m_pts.data(), (INT)m_pts.size());
}

void ShapeStroke::StrokeRegion(Gdiplus::GraphicsPath& path) const {
    if (m_pts.size() < 2) {
        const Gdiplus::REAL r = m_pen / 2.0f;
        path.AddEllipse(m_pts.front().X - r, m_pts.front().Y - r, m_pen, m_pen);
        return;
    }
    BuildPath(path);
    Gdiplus::Pen pen(m_ink, m_pen);
    RoundPen(pen);
    // Widen rather than dotting circles along the line: circles abut with a
    // visible notch at high speed, and the region ends up thousands of shapes.
    path.Widen(&pen);
}

Gdiplus::REAL ShapeStroke::PathDistance(Gdiplus::PointF pt) const {
    if (m_pts.size() < 2) return 0.0f;
    Gdiplus::REAL best = 1e18f;
    for (size_t i = 1; i < m_pts.size(); ++i)
        best = std::min(best, DistToSeg(pt, m_pts[i - 1], m_pts[i]));
    return best;
}

Gdiplus::RectF ShapeStroke::BBox() const {
    Gdiplus::REAL l = m_pts.front().X, t = m_pts.front().Y;
    Gdiplus::REAL r = l, b = t;
    for (const auto& p : m_pts) {
        l = std::min(l, p.X); t = std::min(t, p.Y);
        r = std::max(r, p.X); b = std::max(b, p.Y);
    }
    const Gdiplus::REAL pad = m_pen / 2.0f + 0.5f;
    return Gdiplus::RectF(l - pad, t - pad, (r - l) + 2.0f * pad,
                          (b - t) + 2.0f * pad);
}

bool ShapeStroke::HitTest(Gdiplus::PointF pt) const {
    return PathDistance(pt) <= std::max(m_pen, 6.0f) / 2.0f + 2.0f;
}

void ShapeStroke::Translate(Gdiplus::REAL dx, Gdiplus::REAL dy) {
    for (auto& p : m_pts) {
        p.X += dx;
        p.Y += dy;
    }
}

void ShapePen::Draw(Gdiplus::Graphics& g) const {
    if (m_pts.size() < 2) {
        const Gdiplus::REAL r = m_pen / 2.0f;
        Gdiplus::SolidBrush brush(m_ink);
        g.FillEllipse(&brush, m_pts.front().X - r, m_pts.front().Y - r, m_pen,
                      m_pen);
        return;
    }
    Gdiplus::Pen pen(m_ink, m_pen);
    RoundPen(pen);
    Gdiplus::GraphicsPath path;
    BuildPath(path);
    g.DrawPath(&pen, &path);
}

std::unique_ptr<Annotation> ShapePen::Clone() const {
    return std::make_unique<ShapePen>(*this);
}

void ShapeMosaic::Draw(Gdiplus::Graphics& g) const {
    Gdiplus::PointF at{};
    const Gdiplus::Bitmap* src = m_src ? m_src->Pixels(m_block, &at) : nullptr;
    if (!src) return;

    // Intersect rather than replace: the caller's clip to the selection has to
    // survive, or a band dragged across its edge would spill outside.
    Gdiplus::GraphicsPath band;
    StrokeRegion(band);
    const Gdiplus::GraphicsState state = g.Save();
    g.SetClip(&band, Gdiplus::CombineModeIntersect);
    g.SetInterpolationMode(Gdiplus::InterpolationModeNearestNeighbor);
    // DrawImage insists on a non-const Image*; the cache stays read-only here.
    g.DrawImage(const_cast<Gdiplus::Bitmap*>(src), at);
    g.Restore(state);
}

std::unique_ptr<Annotation> ShapeMosaic::Clone() const {
    return std::make_unique<ShapeMosaic>(*this);
}

// -------------------------------------------------------------------- arrows

namespace {
// The head has a floor well above the thinnest pen: scaled only from the stroke
// it is a speck at the end of a long shaft, which is what made the old one read
// as a line with no head at all.
Gdiplus::REAL HeadLenFor(Gdiplus::REAL pen) { return std::max(24.0f, pen * 4.0f); }
}  // namespace

Gdiplus::REAL ShapeArrow::HeadLen() const { return HeadLenFor(m_pen); }

bool ShapeArrow::IsEmpty() const {
    return std::hypot(m_p1.X - m_p0.X, m_p1.Y - m_p0.Y) < 3.0f;
}

void ShapeArrow::UpdateDrag(Gdiplus::PointF to, bool shift) {
    if (shift) {
        // Snap to the nearest 15°, which is how the reference keeps horizontal,
        // vertical and 45° arrows exact.
        const Gdiplus::REAL dx = to.X - m_p0.X, dy = to.Y - m_p0.Y;
        const Gdiplus::REAL len = std::hypot(dx, dy);
        if (len > 0.0f) {
            constexpr double kStep = 3.14159265358979323846 / 12.0;
            const double a = std::round(std::atan2((double)dy, (double)dx) / kStep) * kStep;
            m_p1 = Gdiplus::PointF(m_p0.X + (Gdiplus::REAL)(len * std::cos(a)),
                                   m_p0.Y + (Gdiplus::REAL)(len * std::sin(a)));
            return;
        }
    }
    m_p1 = to;
}

// The head as three points, shared by the paint and the hit test so the two can
// never disagree about where the arrow ends.
namespace {

void HeadTriangle(Gdiplus::PointF p0, Gdiplus::PointF p1, Gdiplus::REAL pen,
                  Gdiplus::PointF& tip, Gdiplus::PointF base[3]) {
    const Gdiplus::REAL dx = p1.X - p0.X, dy = p1.Y - p0.Y;
    const Gdiplus::REAL len = std::hypot(dx, dy);
    const Gdiplus::REAL hl = std::min(HeadLenFor(pen), len);
    const Gdiplus::REAL ux = dx / len, uy = dy / len;
    const Gdiplus::PointF neck(p1.X - ux * hl, p1.Y - uy * hl);
    const Gdiplus::REAL hw = hl * 0.42f;

    base[0] = p1;
    base[1] = Gdiplus::PointF(neck.X - uy * hw, neck.Y + ux * hw);
    base[2] = Gdiplus::PointF(neck.X + uy * hw, neck.Y - ux * hw);
    tip = neck;
}

}  // namespace

void ShapeArrow::Draw(Gdiplus::Graphics& g) const {
    const Gdiplus::REAL len = std::hypot(m_p1.X - m_p0.X, m_p1.Y - m_p0.Y);
    if (len < 0.5f) return;

    Gdiplus::PointF head[3], neck;
    HeadTriangle(m_p0, m_p1, m_pen, neck, head);

    Gdiplus::Pen pen(m_ink, m_pen);
    pen.SetEndCap(Gdiplus::LineCapRound);
    g.DrawLine(&pen, m_p0, neck);

    Gdiplus::SolidBrush brush(m_ink);
    g.FillPolygon(&brush, head, 3);
}

bool ShapeArrow::HitTest(Gdiplus::PointF pt) const {
    const Gdiplus::REAL len = std::hypot(m_p1.X - m_p0.X, m_p1.Y - m_p0.Y);
    if (len < 0.5f) return std::hypot(pt.X - m_p0.X, pt.Y - m_p0.Y) <= 4.0f;

    if (DistToSeg(pt, m_p0, m_p1) <= std::max(m_pen, 6.0f) / 2.0f + 2.0f)
        return true;

    Gdiplus::PointF head[3], neck;
    HeadTriangle(m_p0, m_p1, m_pen, neck, head);
    return InTriangle(pt, head[0], head[1], head[2]);
}

Gdiplus::RectF ShapeArrow::BBox() const {
    const Gdiplus::REAL pad = HeadLen() + m_pen;
    const Gdiplus::REAL l = std::min(m_p0.X, m_p1.X), t = std::min(m_p0.Y, m_p1.Y);
    const Gdiplus::REAL r = std::max(m_p0.X, m_p1.X), b = std::max(m_p0.Y, m_p1.Y);
    return Gdiplus::RectF(l - pad, t - pad, (r - l) + 2.0f * pad,
                          (b - t) + 2.0f * pad);
}

std::unique_ptr<Annotation> ShapeArrow::Clone() const {
    return std::make_unique<ShapeArrow>(*this);
}

// ------------------------------------------------------------------- badges

Gdiplus::RectF ShapeBadge::BBox() const {
    return Gdiplus::RectF(m_center.X - m_r, m_center.Y - m_r, m_r * 2.0f,
                          m_r * 2.0f);
}

bool ShapeBadge::HitTest(Gdiplus::PointF pt) const {
    return std::hypot(pt.X - m_center.X, pt.Y - m_center.Y) <= m_r + 2.0f;
}

void ShapeBadge::Draw(Gdiplus::Graphics& g) const {
    const Gdiplus::RectF disc(m_center.X - m_r, m_center.Y - m_r, m_r * 2.0f,
                              m_r * 2.0f);
    Gdiplus::SolidBrush ink(m_ink);
    g.FillEllipse(&ink, disc);

    CString text;
    text.Format(L"%d", m_number);
    Gdiplus::FontFamily family(L"Segoe UI");
    Gdiplus::Font font(&family, m_r * 1.25f, Gdiplus::FontStyleBold,
                       Gdiplus::UnitPixel);
    Gdiplus::StringFormat fmt;
    fmt.SetAlignment(Gdiplus::StringAlignmentCenter);
    fmt.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    fmt.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);

    Gdiplus::SolidBrush white(Gdiplus::Color(255, 255, 255));
    g.DrawString(text, -1, &font, disc, &fmt, &white);
}

std::unique_ptr<Annotation> ShapeBadge::Clone() const {
    return std::make_unique<ShapeBadge>(*this);
}

// --------------------------------------------------------------------- text

Gdiplus::RectF ShapeText::Layout() const {
    Gdiplus::Bitmap tmp(1, 1, PixelFormat32bppARGB);
    Gdiplus::Graphics g(&tmp);
    Gdiplus::FontFamily family(kTextFace);
    Gdiplus::Font font(&family, m_fontPx, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
    Gdiplus::StringFormat fmt;
    NoWrap(fmt);
    Gdiplus::RectF box(m_at.X, m_at.Y, 100000.0f, 100000.0f), out{};
    g.MeasureString(m_text, m_text.GetLength(), &font, box, &fmt, &out);
    return out;
}

void ShapeText::Draw(Gdiplus::Graphics& g) const {
    if (m_text.IsEmpty()) return;

    Gdiplus::FontFamily family(kTextFace);
    Gdiplus::Font font(&family, m_fontPx, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
    Gdiplus::StringFormat fmt;
    NoWrap(fmt);
    Gdiplus::SolidBrush ink(m_ink);
    g.DrawString(m_text, m_text.GetLength(), &font, Layout(), &fmt, &ink);
}

Gdiplus::RectF ShapeText::BBox() const { return Layout(); }

bool ShapeText::HitTest(Gdiplus::PointF pt) const {
    const Gdiplus::RectF r = Layout();
    return pt.X >= r.X && pt.X <= r.X + r.Width && pt.Y >= r.Y &&
           pt.Y <= r.Y + r.Height;
}

std::unique_ptr<Annotation> ShapeText::Clone() const {
    return std::make_unique<ShapeText>(*this);
}

// ------------------------------------------------------------------ factory

std::unique_ptr<Annotation> MakeShape(tb::Id tool, Gdiplus::PointF from,
                                      const tb::Style& style, int ordinal,
                                      MosaicSource* mosaic) {
    const Gdiplus::Color ink = style.Color();
    const Gdiplus::REAL pen = (Gdiplus::REAL)style.PenWidth();

    switch (tool) {
    case tb::Id::Rect:
        return std::make_unique<ShapeRect>(from, ink, pen);
    case tb::Id::Ellipse:
        return std::make_unique<ShapeEllipse>(from, ink, pen);
    case tb::Id::Arrow:
        return std::make_unique<ShapeArrow>(from, ink, pen);
    case tb::Id::Pen:
        return std::make_unique<ShapePen>(from, ink, pen);
    case tb::Id::Mosaic:
        // The band is twice the dot the width picker shows: the reference's
        // widest dot gives a 16px band, and the dots are 2/4/8.
        return std::make_unique<ShapeMosaic>(from, mosaic, 2.0f * pen,
                                             style.blurBlockSize);
    case tb::Id::Badge:
        return std::make_unique<ShapeBadge>(from, ordinal, ink,
                                            13.0f * style.dpiScale);
    default:
        return nullptr;
    }
}

}  // namespace annot
