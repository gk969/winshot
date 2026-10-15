#pragma once

#include <cstdint>
#include <vector>

// Auto-stitching for 长截图. Deliberately free of MFC and GDI+: the whole
// feature turns on this one comparison, so it is kept small enough to test on
// its own.
namespace ls {

// One row of BGRA pixels reduced to a hash. Every 4th pixel keeps a 4K row to a
// few hundred reads; quantising each channel to 6 bits absorbs the subpixel
// jitter a scroll leaves behind.
uint64_t RowSignature(const uint32_t* px, int width);

// Signatures for a whole block of rows, top to bottom.
std::vector<uint64_t> RowSignatures(const uint32_t* px, int width, int height,
                                    int stridePx);

struct Shift {
    int rows = 0;    // new content rows below what is already accumulated
    int matches = 0; // tail rows that agreed at that shift
    bool jump = false;  // nothing lined up: the content changed wholesale
};

// `tail` is the last B rows of the accumulated image, oldest first; `frame` is
// the current frame, top to bottom. The frame's row p shows the same content as
// tail row j when p == frameRows - B - rows + j, which is what gets searched.
//
// The smallest matching shift wins: a document with a repeating pattern matches
// at rows and rows+period, and understitching is recoverable while
// over-stitching duplicates content.
Shift FindShift(const std::vector<uint64_t>& tail, const std::vector<uint64_t>& frame,
                int maxStep);

// Rows of overlap that have to agree for a shift to be accepted.
int Tolerance(int tailRows);

}  // namespace ls
