#pragma once

namespace annot {

// The block-averaged still a 马赛克 stroke fills its band with. Owned by the
// capture session; the shapes borrow the pointer, which outlives them.
class MosaicSource {
public:
    virtual ~MosaicSource() = default;

    // Pixels covering the selection, already averaged into `block`-sized
    // squares, and where they sit in overlay-client coords. Null when there is
    // nothing to sample yet.
    virtual const Gdiplus::Bitmap* Pixels(int block, Gdiplus::PointF* at) = 0;
};

}  // namespace annot
