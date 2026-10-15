#include "stdafx.h"
#include "Glyphs.h"

namespace {

using Gdiplus::REAL;

// Unit-square -> box mapping, so every glyph below is written in 0..1 space.
struct Map {
    REAL x0, y0, sx, sy;

    Gdiplus::PointF operator()(REAL u, REAL v) const {
        return Gdiplus::PointF(x0 + u * sx, y0 + v * sy);
    }
    Gdiplus::RectF rect(REAL u0, REAL v0, REAL u1, REAL v1) const {
        return Gdiplus::RectF(x0 + u0 * sx, y0 + v0 * sy, (u1 - u0) * sx, (v1 - v0) * sy);
    }
};

// The reference icons use open corner heads, not filled triangles: two barbs
// leaving the tip at 45 deg either side of the direction of travel.
void Barbs(Gdiplus::Graphics& g, const Gdiplus::Pen& pen, Gdiplus::PointF tip,
           REAL tx, REAL ty, REAL len) {
    const REAL ca = 0.707f, sa = 0.707f;
    g.DrawLine(&pen, tip, Gdiplus::PointF(tip.X - (tx * ca - ty * sa) * len,
                                          tip.Y - (ty * ca + tx * sa) * len));
    g.DrawLine(&pen, tip, Gdiplus::PointF(tip.X - (tx * ca + ty * sa) * len,
                                          tip.Y - (ty * ca - tx * sa) * len));
}

void DrawTextGlyph(Gdiplus::Graphics& g, const wchar_t* text, const Map& m,
                   const Gdiplus::Color& ink, REAL sizeFactor) {
    Gdiplus::FontFamily family(L"Microsoft YaHei UI");
    Gdiplus::Font font(&family, m.sx * sizeFactor, Gdiplus::FontStyleRegular,
                       Gdiplus::UnitPixel);
    Gdiplus::SolidBrush brush(ink);
    Gdiplus::StringFormat fmt;
    fmt.SetAlignment(Gdiplus::StringAlignmentCenter);
    fmt.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    fmt.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);
    Gdiplus::RectF box = m.rect(0.0f, 0.0f, 1.0f, 1.0f);
    g.DrawString(text, -1, &font, box, &fmt, &brush);
}

}  // namespace

namespace glyph {

void Draw(Gdiplus::Graphics& g, tb::Id id, const Gdiplus::RectF& box,
          REAL penWidth, const Gdiplus::Color& ink) {
    Map m{ box.X, box.Y, box.Width, box.Height };

    Gdiplus::Pen pen(ink, penWidth);
    pen.SetStartCap(Gdiplus::LineCapRound);
    pen.SetEndCap(Gdiplus::LineCapRound);
    pen.SetLineJoin(Gdiplus::LineJoinRound);

    switch (id) {
    case tb::Id::Rect:
        g.DrawRectangle(&pen, m.rect(0.12f, 0.16f, 0.88f, 0.84f));
        break;

    case tb::Id::Ellipse:
        g.DrawEllipse(&pen, m.rect(0.12f, 0.16f, 0.88f, 0.84f));
        break;

    case tb::Id::Arrow: {
        // The reference icon uses an open corner head, not a filled triangle.
        Gdiplus::PointF a = m(0.16f, 0.84f), b = m(0.84f, 0.16f);
        g.DrawLine(&pen, a, b);
        REAL dx = b.X - a.X, dy = b.Y - a.Y;
        REAL len = std::sqrt(dx * dx + dy * dy);
        dx /= len; dy /= len;
        const REAL hl = len * 0.28f, ca = 0.82f, sa = 0.57f;
        REAL rx = dx * ca - dy * sa, ry = dy * ca + dx * sa;
        REAL lx = dx * ca + dy * sa, ly = dy * ca - dx * sa;
        g.DrawLine(&pen, b, Gdiplus::PointF(b.X - rx * hl, b.Y - ry * hl));
        g.DrawLine(&pen, b, Gdiplus::PointF(b.X - lx * hl, b.Y - ly * hl));
        break;
    }

    case tb::Id::Pen: {
        // Pencil: a parallelogram body with a triangular tip at the lower left.
        Gdiplus::PointF a = m(0.34f, 0.66f), b = m(0.72f, 0.28f);
        REAL dx = b.X - a.X, dy = b.Y - a.Y;
        REAL len = std::sqrt(dx * dx + dy * dy);
        dx /= len; dy /= len;
        REAL nx = -dy, ny = dx;
        REAL hw = len * 0.16f;
        Gdiplus::PointF body[4] = {
            Gdiplus::PointF(a.X + nx * hw, a.Y + ny * hw),
            Gdiplus::PointF(b.X + nx * hw, b.Y + ny * hw),
            Gdiplus::PointF(b.X - nx * hw, b.Y - ny * hw),
            Gdiplus::PointF(a.X - nx * hw, a.Y - ny * hw),
        };
        g.DrawPolygon(&pen, body, 4);
        Gdiplus::PointF tip(a.X - dx * len * 0.28f, a.Y - dy * len * 0.28f);
        Gdiplus::PointF point[3] = { body[0], body[3], tip };
        g.DrawPolygon(&pen, point, 3);
        break;
    }

    case tb::Id::Mosaic: {
        // 2x2 checkerboard, matching the reference icon.
        Gdiplus::SolidBrush grey(Gdiplus::Color(0xFF9AA0A6));
        g.FillRectangle(&grey, m.rect(0.12f, 0.16f, 0.50f, 0.50f));
        g.FillRectangle(&grey, m.rect(0.50f, 0.50f, 0.88f, 0.84f));
        g.DrawRectangle(&pen, m.rect(0.12f, 0.16f, 0.88f, 0.84f));
        break;
    }

    case tb::Id::Text:
        DrawTextGlyph(g, L"A", m, ink, 0.82f);
        break;

    case tb::Id::Badge:
        g.DrawEllipse(&pen, m.rect(0.12f, 0.16f, 0.88f, 0.84f));
        DrawTextGlyph(g, L"1", m, ink, 0.60f);
        break;

    case tb::Id::Undo: {
        // Nearly a full ring, gap at the upper-left, head at the arc's end.
        Gdiplus::RectF e = m.rect(0.16f, 0.20f, 0.84f, 0.80f);
        g.DrawArc(&pen, e, 150.0f, -270.0f);
        REAL rx = e.Width / 2.0f, ry = e.Height / 2.0f;
        const REAL a = 240.0f * 3.14159265f / 180.0f;
        Gdiplus::PointF p(e.X + rx + rx * std::cos(a), e.Y + ry + ry * std::sin(a));
        // The reference head is a square hook, not angled barbs: down the left
        // side, then back inwards across the middle of the ring.
        REAL k = rx * 0.80f;
        Gdiplus::PointF hook[3] = { p, Gdiplus::PointF(p.X, p.Y + k),
                                    Gdiplus::PointF(p.X + k, p.Y + k) };
        g.DrawLines(&pen, hook, 3);
        break;
    }

    case tb::Id::LongShot: {
        // A page bracket over a pair of scissors.
        g.DrawLine(&pen, m(0.20f, 0.08f), m(0.80f, 0.08f));
        g.DrawLine(&pen, m(0.20f, 0.08f), m(0.20f, 0.42f));
        g.DrawLine(&pen, m(0.80f, 0.08f), m(0.80f, 0.42f));
        g.DrawEllipse(&pen, m.rect(0.23f, 0.70f, 0.41f, 0.88f));
        g.DrawEllipse(&pen, m.rect(0.59f, 0.70f, 0.77f, 0.88f));
        g.DrawLine(&pen, m(0.36f, 0.72f), m(0.72f, 0.44f));
        g.DrawLine(&pen, m(0.64f, 0.72f), m(0.28f, 0.44f));
        break;
    }

    case tb::Id::Ocr: {
        // Scan brackets around a 文 — text recognised out of the selection.
        const REAL c = 0.26f;
        g.DrawLine(&pen, m(0.10f, 0.10f + c), m(0.10f, 0.10f));
        g.DrawLine(&pen, m(0.10f, 0.10f), m(0.10f + c, 0.10f));
        g.DrawLine(&pen, m(0.90f - c, 0.10f), m(0.90f, 0.10f));
        g.DrawLine(&pen, m(0.90f, 0.10f), m(0.90f, 0.10f + c));
        g.DrawLine(&pen, m(0.90f, 0.90f - c), m(0.90f, 0.90f));
        g.DrawLine(&pen, m(0.90f, 0.90f), m(0.90f - c, 0.90f));
        g.DrawLine(&pen, m(0.10f + c, 0.90f), m(0.10f, 0.90f));
        g.DrawLine(&pen, m(0.10f, 0.90f), m(0.10f, 0.90f - c));
        DrawTextGlyph(g, L"文", m, ink, 0.52f);
        break;
    }

    case tb::Id::Pin: {
        // Thumbtack at 45 deg: needle, flat head across it, stub above the head.
        Gdiplus::PointF foot = m(0.26f, 0.76f), head = m(0.58f, 0.44f);
        g.DrawLine(&pen, foot, head);
        REAL dx = head.X - foot.X, dy = head.Y - foot.Y;
        REAL len = std::sqrt(dx * dx + dy * dy);
        dx /= len; dy /= len;
        REAL nx = -dy, ny = dx;
        REAL hw = m.sx * 0.30f;
        g.DrawLine(&pen, Gdiplus::PointF(head.X + nx * hw, head.Y + ny * hw),
                        Gdiplus::PointF(head.X - nx * hw, head.Y - ny * hw));
        g.DrawLine(&pen, head, Gdiplus::PointF(head.X + dx * len * 0.30f,
                                               head.Y + dy * len * 0.30f));
        break;
    }

    case tb::Id::Record: {
        g.DrawEllipse(&pen, m.rect(0.14f, 0.18f, 0.86f, 0.82f));
        Gdiplus::SolidBrush dot(ink);
        g.FillEllipse(&dot, m.rect(0.36f, 0.40f, 0.64f, 0.60f));
        break;
    }

    case tb::Id::Save: {
        g.DrawLine(&pen, m(0.50f, 0.12f), m(0.50f, 0.62f));
        Barbs(g, pen, m(0.50f, 0.62f), 0.0f, 1.0f, m.sx * 0.26f);
        Gdiplus::PointF tray[4] = { m(0.20f, 0.70f), m(0.20f, 0.88f),
                                    m(0.80f, 0.88f), m(0.80f, 0.70f) };
        g.DrawLines(&pen, tray, 4);
        break;
    }

    case tb::Id::Cancel:
        g.DrawLine(&pen, m(0.22f, 0.26f), m(0.78f, 0.74f));
        g.DrawLine(&pen, m(0.78f, 0.26f), m(0.22f, 0.74f));
        break;

    case tb::Id::Done: {
        Gdiplus::PointF tick[3] = { m(0.20f, 0.52f), m(0.42f, 0.74f), m(0.80f, 0.26f) };
        g.DrawLines(&pen, tick, 3);
        break;
    }
    }
}

}  // namespace glyph
