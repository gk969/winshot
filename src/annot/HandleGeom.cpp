#include "stdafx.h"
#include "HandleGeom.h"

#include <algorithm>
#include <cmath>

namespace annot {

Gdiplus::PointF BoxHandleAt(const Gdiplus::RectF& b, int i) {
    const Gdiplus::REAL mx = b.X + b.Width / 2.0f;
    const Gdiplus::REAL my = b.Y + b.Height / 2.0f;
    const Gdiplus::REAL r = b.X + b.Width, bo = b.Y + b.Height;
    switch (i) {
    case 0:  return Gdiplus::PointF(b.X, b.Y);
    case 1:  return Gdiplus::PointF(mx, b.Y);
    case 2:  return Gdiplus::PointF(r, b.Y);
    case 3:  return Gdiplus::PointF(r, my);
    case 4:  return Gdiplus::PointF(r, bo);
    case 5:  return Gdiplus::PointF(mx, bo);
    case 6:  return Gdiplus::PointF(b.X, bo);
    default: return Gdiplus::PointF(b.X, my);
    }
}

void BoxResize(Gdiplus::RectF& box, int i, Gdiplus::PointF pt) {
    Gdiplus::REAL l = box.X, t = box.Y;
    Gdiplus::REAL r = box.X + box.Width, bo = box.Y + box.Height;

    switch (i) {
    case 0: l = pt.X; t = pt.Y; break;
    case 1: t = pt.Y; break;
    case 2: r = pt.X; t = pt.Y; break;
    case 3: r = pt.X; break;
    case 4: r = pt.X; bo = pt.Y; break;
    case 5: bo = pt.Y; break;
    case 6: l = pt.X; bo = pt.Y; break;
    default: l = pt.X; break;
    }

    box = Gdiplus::RectF(std::min(l, r), std::min(t, bo),
                         std::fabs(r - l), std::fabs(bo - t));
}

}  // namespace annot
