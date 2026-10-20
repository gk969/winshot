#include "stdafx.h"
#include "Shapes.h"
#include "MosaicSource.h"
#include "Toolbar.h"

#include <algorithm>
#include <cmath>
#include <map>

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

// Curves and diagonals only. Set per shape rather than on the caller's Graphics
// because the same Graphics also strokes the 1px selection frame, the size label
// and the scrollbar, and those have to stay sharp; an axis-aligned rectangle is
// left out too, where anti-aliasing can only soften an edge that is already
// straight.
class Smooth {
public:
    explicit Smooth(Gdiplus::Graphics& g)
        : m_g(g), m_old(g.GetSmoothingMode()) {
        g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    }
    ~Smooth() { m_g.SetSmoothingMode(m_old); }

private:
    Gdiplus::Graphics& m_g;
    Gdiplus::SmoothingMode m_old;
};

}  // namespace

// The face the 文字 tool draws with; the inline editor uses the same one so the
// committed text lands exactly where the caret was.
const wchar_t kTextFace[] = L"Microsoft YaHei UI";

namespace {

// Wrapping measures a string per character, and building the face each time is
// what would put that cost in every keystroke.
//
// The measurement is GDI's rather than GDI+'s. MeasureString returns the ink box
// of the whole string, which for this face carries about 0.4em of cell padding
// however long the string is — a single character and a whole paragraph are both
// over-measured by the same amount — so a line reads as needing half a character
// more room than it takes and the wrap lands early. GetTextExtentPoint32W
// returns the advance width, which is what the drawn glyphs occupy (measured
// against the ink: equal for CJK, within 2px for Latin), and it is the same
// measurement the EDIT control wraps on, so the inline editor and the committed
// label break in the same place.
class TextMeasurer {
public:
    explicit TextMeasurer(Gdiplus::REAL fontPx) : m_font(FontFor(fontPx)) {}

    Gdiplus::REAL Width(const CString& s) const {
        if (s.IsEmpty()) return 0.0f;
        HDC dc = MemDc();
        HGDIOBJ prev = SelectObject(dc, m_font);
        SIZE sz{};
        GetTextExtentPoint32W(dc, s, s.GetLength(), &sz);
        SelectObject(dc, prev);
        return (Gdiplus::REAL)sz.cx;
    }

    // The line pitch GDI lays out with for this face. The inline editor's glyphs
    // are drawn by a classic EDIT control on these metrics while the committed
    // label uses GDI+'s, and GDI rounds its ascent and descent separately, so the
    // two need not agree. Static because the editor asks before any label exists.
    static int LineHeight(Gdiplus::REAL fontPx) {
        static std::map<int, int> heights;
        const int px = std::max(1, (int)std::lround((double)fontPx));
        const auto it = heights.find(px);
        if (it != heights.end()) return it->second;

        HDC dc = MemDc();
        HGDIOBJ prev = SelectObject(dc, FontFor(fontPx));
        TEXTMETRICW tm{};
        GetTextMetricsW(dc, &tm);
        SelectObject(dc, prev);
        const int height = tm.tmHeight + tm.tmExternalLeading;
        heights.emplace(px, height);
        return height;
    }

private:
    static HDC MemDc() {
        // One DC for the process: it is only ever a carrier for the font, and the
        // UI thread is the only caller.
        static HDC dc = CreateCompatibleDC(nullptr);
        return dc;
    }

    static HFONT FontFor(Gdiplus::REAL fontPx) {
        static std::map<int, HFONT> fonts;
        // -fontPx is the em height, which is what GDI+'s UnitPixel size means, so
        // the two engines render the same glyphs at the same size.
        const int px = std::max(1, (int)std::lround((double)fontPx));
        const auto it = fonts.find(px);
        if (it != fonts.end()) return it->second;
        LOGFONTW lf{};
        lf.lfHeight = -px;
        lf.lfCharSet = DEFAULT_CHARSET;
        wcscpy_s(lf.lfFaceName, kTextFace);
        HFONT font = CreateFontIndirectW(&lf);
        fonts.emplace(px, font);
        return font;
    }

    HFONT m_font;
};

// GDI+ lays a string out inside the rect it is handed with about a fifth of an
// em of cell padding on each side, and the ink starts there rather than at the
// rect edge; GDI's advance width counts neither. Measuring one reference string
// both ways gives the difference, so the label can put its ink a known distance
// inside the box and hold the same distance open on the right — which is what
// decides when a line wraps. A full-width CJK glyph is the cleanest probe: its
// advance and its ink are the same width.
Gdiplus::REAL CellPadding(Gdiplus::REAL fontPx) {
    static std::map<int, Gdiplus::REAL> pads;
    const int px = std::max(1, (int)std::lround((double)fontPx));
    const auto it = pads.find(px);
    if (it != pads.end()) return it->second;

    const wchar_t probe[] = L"\x6587";  // 文
    Gdiplus::Bitmap tmp(1, 1, PixelFormat32bppARGB);
    Gdiplus::Graphics g(&tmp);
    Gdiplus::FontFamily family(kTextFace);
    Gdiplus::Font font(&family, fontPx, Gdiplus::FontStyleRegular,
                       Gdiplus::UnitPixel);
    Gdiplus::StringFormat fmt;
    NoWrap(fmt);
    Gdiplus::RectF box(0.0f, 0.0f, 100000.0f, 100000.0f), out{};
    g.MeasureString(probe, 1, &font, box, &fmt, &out);
    const Gdiplus::REAL pad =
        std::max((out.Width - TextMeasurer(fontPx).Width(probe)) / 2.0f, 0.0f);
    pads.emplace(px, pad);
    return pad;
}

}  // namespace

Gdiplus::REAL MeasureTextWidth(const CString& text, Gdiplus::REAL fontPx) {
    if (text.IsEmpty()) return 0.0f;
    const TextMeasurer m(fontPx);
    return m.Width(text);
}

Gdiplus::REAL MeasureTextLineHeight(Gdiplus::REAL fontPx) {
    Gdiplus::FontFamily family(kTextFace);
    const int em = family.GetEmHeight(Gdiplus::FontStyleRegular);
    const int pitch = family.GetLineSpacing(Gdiplus::FontStyleRegular);
    // A face with no metrics at all still needs a pitch, and rounding up keeps
    // the lines from overlapping into one smudge.
    const Gdiplus::REAL gdiPlus = (em <= 0 || pitch <= 0)
                                      ? std::ceil(fontPx * 1.3f)
                                      : std::ceil(fontPx * (Gdiplus::REAL)pitch /
                                                  (Gdiplus::REAL)em);
    // The box is one cell per line, so the cell has to be big enough for
    // whichever engine lays lines out. The EDIT control answers a line that no
    // longer fits by cutting it off rather than by growing, and it only ever
    // does that while editing, where nothing is comparing it to the commit.
    return std::max(gdiPlus, (Gdiplus::REAL)TextMeasurer::LineHeight(fontPx));
}

Gdiplus::REAL TextHeight(Gdiplus::REAL fontPx, Gdiplus::REAL padY, int lines) {
    return (Gdiplus::REAL)lines * MeasureTextLineHeight(fontPx) + padY;
}

std::vector<CString> WrapLines(const CString& text, Gdiplus::REAL fontPx,
                               Gdiplus::REAL maxW) {
    std::vector<CString> out;
    const TextMeasurer m(fontPx);
    const Gdiplus::REAL limit = std::max(maxW, 1.0f);

    // Greedy, and never breaking inside a run of CJK: breaking Latin at a space
    // keeps words whole, and a CJK run has no spaces to reach for, so the break
    // goes wherever the width runs out. `breakAt` remembers the last space on
    // the line being built, which is where the line ends when the next
    // character no longer fits.
    CString cur;
    int breakAt = -1;
    const int n = text.GetLength();
    for (int i = 0; i <= n; ++i) {
        const wchar_t c = i < n ? text[i] : L'\n';
        if (c == L'\n' || c == L'\r') {
            out.push_back(cur);
            cur.Empty();
            breakAt = -1;
            if (c == L'\r' && i + 1 < n && text[i + 1] == L'\n') ++i;
            continue;
        }
        const CString trial = cur + c;
        if (cur.IsEmpty() || m.Width(trial) <= limit) {
            cur = trial;
            if (c == L' ') breakAt = cur.GetLength();
            continue;
        }
        if (breakAt > 0) {
            out.push_back(cur.Left(breakAt));
            cur = cur.Mid(breakAt);
        } else {
            out.push_back(cur);
            cur.Empty();
        }
        cur += c;
        breakAt = c == L' ' ? cur.GetLength() : -1;
    }
    if (out.empty()) out.push_back(CString());
    return out;
}

// ---------------------------------------------------------------- box shapes

Gdiplus::REAL RectPen(Gdiplus::REAL pen) {
    // The thin dot means 1px for a rectangle and 2px for every other tool, so one
    // dot on the 粗细 bar stands for two widths. Only this shape can take it: the
    // rect is the one outline drawn without smoothing, so 1px binarizes to a single
    // crisp column, while an anti-aliased 1px pen feathers across two half-lit ones.
    return pen <= 2.0f ? 1.0f : pen;
}

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
    const Smooth smooth(g);
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
    const Smooth smooth(g);
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
// The head is sized from the width the property bar offers (2, 4 and 8 px)
// rather than scaled off the stroke: scaled off the stroke it is a speck at the
// end of a long shaft, which is what made the old one read as a line with no
// head at all. The widest setting keeps the reference size and the two thinner
// ones are two thirds and a half of it, so the three read as three different
// triangles instead of one floor reached three ways.
Gdiplus::REAL HeadLenFor(Gdiplus::REAL pen) {
    if (pen >= 6.0f) return 32.0f;
    return pen >= 3.0f ? 32.0f * 2.0f / 3.0f : 16.0f;
}
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
    const Gdiplus::REAL dx = m_p1.X - m_p0.X, dy = m_p1.Y - m_p0.Y;
    const Gdiplus::REAL len = std::hypot(dx, dy);
    if (len < 0.5f) return;

    const Smooth smooth(g);

    Gdiplus::PointF head[3], neck;
    HeadTriangle(m_p0, m_p1, m_pen, neck, head);

    // The shaft is a quad that starts 1px wide and opens to the full width at
    // the head: drawn at a constant width the arrow reads as a line with a
    // triangle on the end, and the taper is what makes it point.
    const Gdiplus::REAL ux = dx / len, uy = dy / len;
    const Gdiplus::REAL tailHw = std::min(m_pen / 2.0f, 0.5f);
    const Gdiplus::REAL headHw = m_pen / 2.0f;
    const Gdiplus::PointF shaft[4] = {
        Gdiplus::PointF(m_p0.X - uy * tailHw, m_p0.Y + ux * tailHw),
        Gdiplus::PointF(neck.X - uy * headHw, neck.Y + ux * headHw),
        Gdiplus::PointF(neck.X + uy * headHw, neck.Y - ux * headHw),
        Gdiplus::PointF(m_p0.X + uy * tailHw, m_p0.Y - ux * tailHw),
    };

    Gdiplus::SolidBrush brush(m_ink);
    g.FillPolygon(&brush, shaft, 4);
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

Gdiplus::REAL BadgeRadiusForPen(Gdiplus::REAL pen) {
    // The three dots are 2, 4 and 8 px, a 4x span that would be absurd for a
    // disc, so the sizes step by about 1.3x instead and the middle one stays
    // where the tool always was.
    if (pen <= 3.0f) return 10.0f;
    if (pen <= 6.0f) return 13.0f;
    return 17.0f;
}

Gdiplus::REAL MosaicBandForPen(Gdiplus::REAL pen) {
    return 4.0f * pen;
}

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
    const Smooth smooth(g);
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

Gdiplus::REAL ShapeText::PadX() const {
    return (Gdiplus::REAL)std::lround((double)kTextPadX * m_dpiScale);
}

Gdiplus::REAL ShapeText::PadY() const {
    return (Gdiplus::REAL)std::lround((double)kTextPadY * m_dpiScale);
}

Gdiplus::REAL ShapeText::LineHeight() const {
    return MeasureTextLineHeight(m_fontPx);
}

Gdiplus::REAL ShapeText::TextWidth() const {
    // The padding is the editor's, so the label wraps at the width the editor
    // wrapped at rather than at the width of its own frame. It is also the ink's
    // inset on both sides — Draw() lands the ink PadX inside the left edge, and
    // wrapping on the advance width at this limit holds the same PadX open on the
    // right, so a line only breaks when the right gap falls below the left one.
    return std::max(m_box.Width - 2.0f * PadX(), 1.0f);
}

void ShapeText::InvalidateLayout() const {
    m_srcW = -1.0f;
}

void ShapeText::SetText(const CString& t) {
    m_text = t;
    InvalidateLayout();
}

void ShapeText::AdoptBox(const Gdiplus::RectF& box) {
    m_box = box;
    InvalidateLayout();
}

// The width is the user's and stays exactly as they left it; only the height
// follows the font, so a bigger size cannot clip its own last line and a smaller
// one does not throw away room a handle was dragged out. A label that was never
// resized by hand re-fits both ways, because its height was never the user's.
void ShapeText::SetFontSize(int designPx) {
    m_fontPx = (Gdiplus::REAL)designPx * m_dpiScale;
    // After the size changes: the lines are wrapped at this font, at this width.
    InvalidateLayout();
    const Gdiplus::REAL need = TextHeight(m_fontPx, PadY(), (int)Lines().size());
    m_box.Height = m_userSized ? std::max(m_box.Height, need) : need;
}

void ShapeText::MoveHandle(int i, Gdiplus::PointF pt) {
    BoxResize(m_box, i, pt);
    // The box is the user's from here on: it never grows wider to fit the text, so
    // a narrower box re-wraps into more lines. The floors keep one line visible.
    m_box.Width = std::max(m_box.Width, (Gdiplus::REAL)kTextMinW);
    m_box.Height = std::max(m_box.Height, TextHeight(m_fontPx, PadY(), 1));
    m_userSized = true;
    InvalidateLayout();

    // But it does grow taller, because the lines the new width asked for are not
    // optional: Draw() stops at the box's bottom edge, so a box left at its old
    // height would drop the new lines off the bottom and the gesture that was only
    // meant to re-wrap the text would silently delete the end of it. Growing only,
    // never shrinking, so dragging the bottom edge up still trims.
    const Gdiplus::REAL need = TextHeight(m_fontPx, PadY(), (int)Lines().size());
    m_box.Height = std::max(m_box.Height, need);
}

const std::vector<CString>& ShapeText::Lines() const {
    if (m_srcW != m_box.Width || m_src != m_text) {
        m_lines = WrapLines(m_text, m_fontPx, TextWidth());
        m_src = m_text;
        m_srcW = m_box.Width;
    }
    return m_lines;
}

void ShapeText::Draw(Gdiplus::Graphics& g) const {
    if (m_text.IsEmpty()) return;

    Gdiplus::FontFamily family(kTextFace);
    Gdiplus::Font font(&family, m_fontPx, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
    Gdiplus::StringFormat fmt;
    NoWrap(fmt);
    Gdiplus::SolidBrush ink(m_ink);

    // Intersect rather than replace: the caller's clip to the 选区 has to
    // survive, or a label at the edge would spill outside it.
    const Gdiplus::GraphicsState state = g.Save();
    g.SetClip(m_box, Gdiplus::CombineModeIntersect);

    // One DrawString per wrapped line, at the same pitch the editor used to grow
    // its box, so committing does not move the text. The layout rect starts a
    // cell padding left of where the ink should land, because that is where GDI+
    // puts the ink inside the rect it is given.
    const Gdiplus::REAL lh = LineHeight();
    const Gdiplus::REAL x = m_box.X + PadX() - CellPadding(m_fontPx);
    Gdiplus::REAL y = m_box.Y;
    for (const CString& line : Lines()) {
        if (y + lh > m_box.Y + m_box.Height) break;
        g.DrawString(line, line.GetLength(), &font,
                     Gdiplus::RectF(x, y, 100000.0f, 100000.0f), &fmt, &ink);
        y += lh;
    }
    g.Restore(state);
}

bool ShapeText::HitTest(Gdiplus::PointF pt) const {
    // Out to the frame line, which is the box's edge as far as the pointer is
    // concerned: while the edit is open the input control covers everything
    // inside, and 文本框双击编辑 asks for that line to move the box.
    const Gdiplus::REAL pad =
        (Gdiplus::REAL)std::lround((double)kTextFramePad * m_dpiScale);
    return pt.X >= m_box.X - pad && pt.X <= m_box.X + m_box.Width + pad &&
           pt.Y >= m_box.Y - pad && pt.Y <= m_box.Y + m_box.Height + pad;
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
        return std::make_unique<ShapeMosaic>(from, mosaic, MosaicBandForPen(pen),
                                             style.blurBlockSize);
    case tb::Id::Badge:
        return std::make_unique<ShapeBadge>(
            from, ordinal, ink, BadgeRadiusForPen(pen) * style.dpiScale,
            style.dpiScale);
    default:
        return nullptr;
    }
}

}  // namespace annot
