#pragma once

#include "Toolbar.h"

// Toolbar icons are drawn as vectors rather than bitmaps so they stay crisp at
// every display scale — a 16px bitmap goes blurry at 133%.
namespace glyph {

void Draw(Gdiplus::Graphics& g, tb::Id id, const Gdiplus::RectF& box,
          Gdiplus::REAL penWidth, const Gdiplus::Color& ink);

}  // namespace glyph
