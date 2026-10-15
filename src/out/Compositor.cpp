#include "stdafx.h"
#include "Compositor.h"
#include "AnnotationList.h"
#include "DesktopCapture.h"

namespace out {

std::unique_ptr<Gdiplus::Bitmap> RenderSelection(const DesktopCapture& cap, RECT sel,
                                                 const annot::AnnotationList& annos,
                                                 POINT off) {
    const int w = sel.right - sel.left, h = sel.bottom - sel.top;
    if (w <= 0 || h <= 0) return nullptr;

    auto bmp = std::make_unique<Gdiplus::Bitmap>(w, h, PixelFormat32bppARGB);

    // Row memcpy rather than DrawImage: both sides are 32bpp and the copy is
    // 1:1, so there is nothing for GDI+ to add — and the mosaic cache stays
    // sized to the crop instead of the whole desktop.
    const Gdiplus::Rect srcRect(sel.left - off.x, sel.top - off.y, w, h);
    const Gdiplus::Rect dstRect(0, 0, w, h);

    Gdiplus::BitmapData sd{}, dd{};
    if (cap.Image()->LockBits(&srcRect, Gdiplus::ImageLockModeRead,
                              PixelFormat32bppARGB, &sd) != Gdiplus::Ok)
        return nullptr;

    if (bmp->LockBits(&dstRect, Gdiplus::ImageLockModeWrite, PixelFormat32bppARGB,
                      &dd) != Gdiplus::Ok) {
        cap.Image()->UnlockBits(&sd);
        return nullptr;
    }

    const unsigned char* src = (const unsigned char*)sd.Scan0;
    unsigned char* dst = (unsigned char*)dd.Scan0;
    const size_t bytes = (size_t)w * 4;
    for (int y = 0; y < h; ++y)
        memcpy(dst + (size_t)y * dd.Stride, src + (size_t)y * sd.Stride, bytes);

    bmp->UnlockBits(&dd);
    cap.Image()->UnlockBits(&sd);

    Gdiplus::Graphics g(bmp.get());
    g.SetInterpolationMode(Gdiplus::InterpolationModeNearestNeighbor);
    g.SetClip(Gdiplus::RectF(0.0f, 0.0f, (Gdiplus::REAL)w, (Gdiplus::REAL)h));
    g.TranslateTransform((Gdiplus::REAL)-sel.left, (Gdiplus::REAL)-sel.top);
    annos.DrawAll(g);

    return bmp;
}

}  // namespace out
