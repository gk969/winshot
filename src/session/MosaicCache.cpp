#include "stdafx.h"
#include "MosaicCache.h"
#include "CaptureSession.h"
#include "DesktopCapture.h"
#include "SelectionModel.h"
#include "AnnotationList.h"
#include "Shapes.h"

#include <algorithm>

namespace {

// Block-average in place. Reads happen before the block is written, so no
// second buffer is needed.
void Pixelate(Gdiplus::Bitmap& bmp, int block) {
    if (block < 2) return;

    const int w = (int)bmp.GetWidth(), h = (int)bmp.GetHeight();
    Gdiplus::Rect full(0, 0, bmp.GetWidth(), bmp.GetHeight());
    Gdiplus::BitmapData d{};
    // The C++ enum has no ReadWrite member — the access flags are a bitmask.
    const auto rw = static_cast<Gdiplus::ImageLockMode>(Gdiplus::ImageLockModeRead |
                                                        Gdiplus::ImageLockModeWrite);
    if (bmp.LockBits(&full, rw, PixelFormat32bppARGB, &d) != Gdiplus::Ok)
        return;

    auto pixel = [&](int x, int y) -> uint32_t& {
        return reinterpret_cast<uint32_t*>(
            static_cast<BYTE*>(d.Scan0) + (size_t)y * d.Stride)[x];
    };

    for (int by = 0; by < h; by += block) {
        const int y1 = std::min(by + block, h);
        for (int bx = 0; bx < w; bx += block) {
            const int x1 = std::min(bx + block, w);
            // Corners and centre rather than every pixel: 4-8x cheaper and, at
            // these sizes, indistinguishable.
            const int pts[5][2] = {
                { bx, by }, { x1 - 1, by }, { bx, y1 - 1 }, { x1 - 1, y1 - 1 },
                { (bx + x1) / 2, (by + y1) / 2 },
            };
            unsigned r = 0, g = 0, b = 0;
            for (const auto& p : pts) {
                const uint32_t c = pixel(p[0], p[1]);
                r += (c >> 16) & 0xFF;
                g += (c >> 8) & 0xFF;
                b += c & 0xFF;
            }
            const uint32_t avg = 0xFF000000u | ((r / 5) << 16) | ((g / 5) << 8) |
                                 (b / 5);
            for (int y = by; y < y1; ++y)
                for (int x = bx; x < x1; ++x)
                    pixel(x, y) = avg;
        }
    }
    bmp.UnlockBits(&d);
}

}  // namespace

const Gdiplus::Bitmap* MosaicCache::Pixels(int block, Gdiplus::PointF* at) {
    const RECT sel = m_session->Sel().Rect();
    const POINT off = m_session->CapOff();
    const int w = sel.right - sel.left, h = sel.bottom - sel.top;
    if (w <= 0 || h <= 0) return nullptr;

    const bool fresh = m_bmp && m_block == block && m_sel.left == sel.left &&
                       m_sel.top == sel.top && m_sel.right == sel.right &&
                       m_sel.bottom == sel.bottom && m_off.x == off.x &&
                       m_off.y == off.y;
    if (!fresh) {
        m_bmp.reset();
        auto bmp = std::make_unique<Gdiplus::Bitmap>(w, h, PixelFormat32bppARGB);
        {
            Gdiplus::Graphics g(bmp.get());
            g.SetInterpolationMode(Gdiplus::InterpolationModeNearestNeighbor);
            g.SetClip(Gdiplus::RectF(0.0f, 0.0f, (Gdiplus::REAL)w,
                                     (Gdiplus::REAL)h));
            g.TranslateTransform((Gdiplus::REAL)-sel.left,
                                 (Gdiplus::REAL)-sel.top);

            const DesktopCapture& cap = m_session->Capture();
            g.DrawImage(cap.Image(), off.x, off.y, cap.Width(), cap.Height());
            // 马赛克-鼠标拖动变模糊.png pixelates the red curve it is dragged
            // over, so the ink already on the canvas belongs in the sample.
            // Other mosaic strokes stay out: a band must not pixelate its
            // neighbour into a second layer of mush.
            for (size_t i = 0; i < m_session->Annos().Count(); ++i) {
                annot::Annotation* a = m_session->Annos().At(i);
                if (a && a->GetKind() != annot::Kind::Mosaic) a->Draw(g);
            }
        }
        Pixelate(*bmp, block);

        m_bmp = std::move(bmp);
        m_block = block;
        m_sel = sel;
        m_off = off;
        m_at = Gdiplus::PointF((Gdiplus::REAL)sel.left, (Gdiplus::REAL)sel.top);
    }

    *at = m_at;
    return m_bmp.get();
}
