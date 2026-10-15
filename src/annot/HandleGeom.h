#pragma once

namespace annot {

inline constexpr int kBoxHandles = 8;

Gdiplus::PointF BoxHandleAt(const Gdiplus::RectF& box, int i);

// Drags the given handle to pt. The box stays normalised, so a drag that
// crosses the opposite edge flips rather than inverting.
void BoxResize(Gdiplus::RectF& box, int i, Gdiplus::PointF pt);

}  // namespace annot
