#pragma once

#include "AnnotationList.h"

class DesktopCapture;

namespace out {

// The exported image: the selection cropped out of the frozen still, with the
// annotations drawn on top and clipped to the same rectangle.
//
// `off` is where the capture starts relative to the space `sel` lives in — zero
// for the frozen still, the selection's corner once 编辑 hands back a stitched
// image that only covers part of that space.
std::unique_ptr<Gdiplus::Bitmap> RenderSelection(const DesktopCapture& cap, RECT sel,
                                                 const annot::AnnotationList& annos,
                                                 POINT off);

}  // namespace out
