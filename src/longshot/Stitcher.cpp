#include "Stitcher.h"

namespace ls {

namespace {

// FNV-1a: cheap, and its avalanche means one changed pixel never hides behind
// an unchanged neighbour.
constexpr uint64_t kFnvOffset = 1469598103934665603ull;
constexpr uint64_t kFnvPrime = 1099511628211ull;

}  // namespace

uint64_t RowSignature(const uint32_t* px, int width) {
    uint64_t h = kFnvOffset;
    for (int x = 0; x < width; x += 4) {
        // Stored BGRA, so the three shifts pick out B, G and R; alpha is the
        // desktop's own and carries no information here.
        const uint32_t p = px[x];
        const uint32_t q = ((p >> 2) & 0x3Fu) | (((p >> 10) & 0x3Fu) << 6) |
                           (((p >> 18) & 0x3Fu) << 12);
        h ^= q;
        h *= kFnvPrime;
    }
    return h;
}

std::vector<uint64_t> RowSignatures(const uint32_t* px, int width, int height,
                                    int stridePx) {
    std::vector<uint64_t> out;
    out.reserve((size_t)height);
    for (int y = 0; y < height; ++y)
        out.push_back(RowSignature(px + (size_t)y * stridePx, width));
    return out;
}

int Tolerance(int tailRows) {
    // A blinking caret or a hovered row band costs about twenty rows of the
    // overlap band on its own, so the allowance has to be generous; past a
    // quarter of the band the page has turned rather than scrolled.
    const int t = tailRows / 4;
    return t < 4 ? 4 : t;
}

Shift FindShift(const std::vector<uint64_t>& tail, const std::vector<uint64_t>& frame,
                int maxStep) {
    Shift best{ 0, 0, true };
    const int B = (int)tail.size(), h = (int)frame.size();
    if (B <= 0 || h < B) return best;

    // Tail row j lines up with frame row h-B-d+j, which has to stay inside the
    // frame for every j.
    if (maxStep > h - B) maxStep = h - B;
    if (maxStep < 0) maxStep = 0;

    for (int d = 0; d <= maxStep; ++d) {
        const int base = h - B - d;
        int good = 0;
        for (int j = 0; j < B; ++j)
            if (tail[j] == frame[(size_t)(base + j)]) ++good;
        // Strictly greater, and d walks upward: the first shift that explains
        // the overlap is the one kept.
        if (good > best.matches) {
            best.matches = good;
            best.rows = d;
            best.jump = false;
        }
    }

    // A blinking caret or a hovered row costs a couple of rows at most; anything
    // worse means the content jumped (a PgDn past the search band, a page turn).
    if (best.matches < B - Tolerance(B)) {
        best.rows = 0;
        best.jump = true;
    }
    return best;
}

}  // namespace ls
