#pragma once

#include <cstdint>
#include <vector>

namespace ls {

// One live grab of the long-shot hole. The overlay's window region leaves the
// hole empty, so what is on screen there is the target window itself — which is
// the only way a scrolled page can reach us.
struct Frame {
    int width = 0, height = 0;
    std::vector<uint32_t> px;    // BGRA, row packed
    std::vector<uint64_t> sigs;  // one per row, for FindShift
};

// BitBlt a screen rect and hash its rows. The cursor is hidden for the copy:
// it sits inside the hole while the user scrolls, and would be stitched in.
bool GrabFrame(RECT screenRect, Frame& out);

}  // namespace ls
