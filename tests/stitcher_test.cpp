// Standalone checks for the stitching comparison — the one part of 长截图 whose
// correctness is not visible on screen. Build and run:
//
//   cl /EHsc /std:c++20 /W4 /source-charset:utf-8 /Fe:obj\stitcher_test.exe /Fo:obj\ ^
//      tests\stitcher_test.cpp src\longshot\Stitcher.cpp
//   obj\stitcher_test.exe
#include <cstdio>
#include <vector>

#include "../src/longshot/Stitcher.h"

namespace {

int g_failed = 0;

void Check(bool ok, const char* what) {
    std::printf("%s  %s\n", ok ? "ok  " : "FAIL", what);
    if (!ok) ++g_failed;
}

// A synthetic page. `period` == 0 makes every row unique; a non-zero period
// repeats the page every `period` rows, which is the case a shift search can
// answer wrongly.
void MakeDoc(std::vector<uint32_t>& doc, int w, int h, int period) {
    doc.assign((size_t)w * h, 0);
    for (int r = 0; r < h; ++r) {
        const int key = period ? r % period : r;
        const uint32_t seed = (uint32_t)key * 2654435761u;
        for (int x = 0; x < w; ++x)
            doc[(size_t)r * w + x] = (seed ^ ((uint32_t)(x / 8) * 40503u)) | 0xFF000000u;
    }
}

std::vector<uint32_t> Frame(const std::vector<uint32_t>& doc, int w, int top, int rows) {
    std::vector<uint32_t> out((size_t)w * rows);
    for (int r = 0; r < rows; ++r)
        for (int x = 0; x < w; ++x)
            out[(size_t)r * w + x] = doc[(size_t)(top + r) * w + x];
    return out;
}

std::vector<uint64_t> Sigs(const std::vector<uint32_t>& px, int w) {
    return ls::RowSignatures(px.data(), w, (int)px.size() / w, w);
}

}  // namespace

int main() {
    constexpr int kW = 200, kH = 300, kB = 100, kStep = 200;

    std::vector<uint32_t> doc;
    MakeDoc(doc, kW, 1200, 0);

    // The accumulated image always ends where the frame ends: tail = the last kB
    // rows of what has been stitched, frame = the hole at its new scroll offset.
    const auto tail = Frame(doc, kW, 200, kB);
    const auto tailSigs = Sigs(tail, kW);

    {
        auto f = Sigs(Frame(doc, kW, 0, kH), kW);
        auto m = ls::FindShift(tailSigs, f, kStep);
        Check(!m.jump && m.rows == 0, "no scroll reads as zero rows");
    }
    {
        auto f = Sigs(Frame(doc, kW, 37, kH), kW);
        auto m = ls::FindShift(tailSigs, f, kStep);
        Check(!m.jump && m.rows == 37, "a 37 row scroll reads as 37");
    }
    {
        auto f = Sigs(Frame(doc, kW, 200, kH), kW);
        auto m = ls::FindShift(tailSigs, f, kStep);
        Check(!m.jump && m.rows == 200, "a scroll of exactly maxStep reads as maxStep");
    }
    {
        auto f = Sigs(Frame(doc, kW, 250, kH), kW);
        auto m = ls::FindShift(tailSigs, f, kStep);
        Check(m.jump && m.rows == 0, "a scroll past the search band is a jump");
    }
    {
        // A caret or a hover highlight rewrites a band of rows inside the
        // overlap. Rows 163..263 of the frame are the ones compared at 37.
        auto raw = Frame(doc, kW, 37, kH);
        for (int r = 170; r < 180; ++r)
            for (int x = 0; x < kW; ++x) raw[(size_t)r * kW + x] = 0xFF202020u;
        auto m = ls::FindShift(tailSigs, Sigs(raw, kW), kStep);
        Check(!m.jump && m.rows == 37, "a disturbed caret band is still the same shift");
    }
    {
        // Most of the overlap disturbed is past what the tolerance allows.
        auto raw = Frame(doc, kW, 37, kH);
        for (int r = 200; r < 260; ++r)
            for (int x = 0; x < kW; ++x) raw[(size_t)r * kW + x] = 0xFF202020u;
        auto m = ls::FindShift(tailSigs, Sigs(raw, kW), kStep);
        Check(m.jump, "sixty disturbed rows are a jump, not a guess");
    }
    {
        // A page that repeats every 20 rows matches at 17, 37, 57…; taking the
        // first keeps the stitch short instead of duplicating content.
        MakeDoc(doc, kW, 1200, 20);
        const auto t2 = Sigs(Frame(doc, kW, 200, kB), kW);
        auto f = Sigs(Frame(doc, kW, 37, kH), kW);
        auto m = ls::FindShift(t2, f, kStep);
        Check(!m.jump && m.rows == 17, "a repeating page understitches rather than overlap");
    }
    {
        // Upward scrolling: the accumulated image now starts at doc row 300, so
        // its head is those rows, and scrolling up by 37 shows doc row 263 at the
        // top of the frame.
        MakeDoc(doc, kW, 1200, 0);
        const auto headSigs = Sigs(Frame(doc, kW, 300, kB), kW);
        {
            auto m = ls::FindUpShift(headSigs, Sigs(Frame(doc, kW, 300, kH), kW), kStep);
            Check(!m.jump && m.rows == 0, "scrolling up with nothing above reads as zero");
        }
        {
            auto m = ls::FindUpShift(headSigs, Sigs(Frame(doc, kW, 263, kH), kW), kStep);
            Check(!m.jump && m.rows == 37, "a 37 row scroll up reads as 37");
        }
        {
            auto m = ls::FindUpShift(headSigs, Sigs(Frame(doc, kW, 100, kH), kW), kStep);
            Check(!m.jump && m.rows == kStep, "a scroll up of exactly maxStep reads as maxStep");
        }
        {
            auto m = ls::FindUpShift(headSigs, Sigs(Frame(doc, kW, 50, kH), kW), kStep);
            Check(m.jump && m.rows == 0, "a scroll up past the search band is a jump");
        }
        {
            // The direction the other search would have taken: the head cannot
            // line up anywhere, so the controller has to be told not to prepend.
            auto m = ls::FindUpShift(headSigs, Sigs(Frame(doc, kW, 337, kH), kW), kStep);
            Check(m.jump, "a scroll down is a jump for the head");
        }
        {
            auto raw = Frame(doc, kW, 263, kH);
            for (int r = 40; r < 50; ++r)
                for (int x = 0; x < kW; ++x) raw[(size_t)r * kW + x] = 0xFF202020u;
            auto m = ls::FindUpShift(headSigs, Sigs(raw, kW), kStep);
            Check(!m.jump && m.rows == 37, "a disturbed band does not move a scroll up");
        }
    }
    {
        // A scroll back over ground already stitched. Neither end band lines up
        // there, so only a lookup in the whole document tells that apart from a
        // page turn — which is what stopped the session on the way back up.
        MakeDoc(doc, kW, 2000, 0);
        const auto whole = Sigs(doc, kW);
        // The accumulated image is doc rows 400..999, so the answer counts from
        // row 400, exactly as the controller's buffer does.
        const std::vector<uint64_t> acc(whole.begin() + 400, whole.begin() + 1000);
        {
            auto f = Sigs(Frame(doc, kW, 500, kH), kW);
            Check(ls::FindInside(acc, f) == 100, "a frame from the middle reads as its offset");
        }
        {
            auto f = Sigs(Frame(doc, kW, 400, kH), kW);
            Check(ls::FindInside(acc, f) == 0, "a frame at the top of the image reads as zero");
        }
        {
            auto f = Sigs(Frame(doc, kW, 700, kH), kW);
            Check(ls::FindInside(acc, f) == 300, "a frame at the bottom of the image is found");
        }
        {
            auto f = Sigs(Frame(doc, kW, 1000, kH), kW);
            Check(ls::FindInside(acc, f) < 0, "content below the image is not inside it");
        }
        {
            auto f = Sigs(Frame(doc, kW, 100, kH), kW);
            Check(ls::FindInside(acc, f) < 0, "content above the image is not inside it");
        }
        {
            auto raw = Frame(doc, kW, 500, kH);
            for (int r = 120; r < 130; ++r)
                for (int x = 0; x < kW; ++x) raw[(size_t)r * kW + x] = 0xFF202020u;
            Check(ls::FindInside(acc, Sigs(raw, kW)) == 100,
                  "a disturbed band still finds the frame inside");
        }
        {
            Check(ls::FindInside(acc, Sigs(Frame(doc, kW, 400, (int)acc.size()), kW)) == 0,
                  "a frame as tall as the image sits at zero");
            Check(ls::FindInside(acc, Sigs(Frame(doc, kW, 400, (int)acc.size() + kH), kW)) < 0,
                  "a frame taller than the image is nowhere inside it");
        }
        {
            // On a page that repeats every 20 rows a frame matches at several
            // offsets at once; any offset the frame really agrees with is a good
            // answer, since all that is being asked is "already stitched?".
            MakeDoc(doc, kW, 2000, 20);
            const auto rep = Sigs(doc, kW);
            const std::vector<uint64_t> acc2(rep.begin() + 400, rep.begin() + 1000);
            const auto f = Sigs(Frame(doc, kW, 437, kH), kW);
            const int o = ls::FindInside(acc2, f);
            bool agrees = o >= 0 && o + kH <= (int)acc2.size();
            for (int j = 0; agrees && j < kH; ++j)
                agrees = acc2[(size_t)(o + j)] == f[(size_t)j];
            Check(agrees, "a repeating page is found at an offset it really agrees with");
        }
    }
    {
        MakeDoc(doc, kW, 1200, 0);
        const auto one = Sigs(Frame(doc, kW, 5, 1), kW);
        const auto other = Sigs(Frame(doc, kW, 6, 1), kW);
        Check(one.size() == 1 && other.size() == 1 && one[0] != other[0],
              "different rows hash differently");

        auto raw = Frame(doc, kW, 5, 1);
        raw[8] ^= 0x40u;  // a sampled pixel (every 4th), one bit of one channel
        const auto changed = Sigs(raw, kW);
        Check(changed[0] != one[0], "one changed pixel changes the row hash");
    }
    {
        // Stride wider than the row: the frame comes out of a LockBits buffer.
        std::vector<uint32_t> padded((size_t)(kW + 13) * kH, 0xFF000000u);
        const auto dense = Frame(doc, kW, 100, kH);
        for (int r = 0; r < kH; ++r)
            for (int x = 0; x < kW; ++x)
                padded[(size_t)r * (kW + 13) + x] = dense[(size_t)r * kW + x];
        const auto a = ls::RowSignatures(padded.data(), kW, kH, kW + 13);
        const auto b = Sigs(dense, kW);
        Check(a == b, "a padded stride hashes the same as a packed one");
    }
    {
        Check(ls::Tolerance(100) == 25 && ls::Tolerance(8) == 4,
              "tolerance scales with the overlap band");
    }

    std::printf("%s (%d failures)\n", g_failed ? "FAIL" : "PASS", g_failed);
    return g_failed ? 1 : 0;
}
