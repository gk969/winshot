#include "stdafx.h"
#include "ClipboardImage.h"

namespace out {
namespace {

// CF_DIB alone is not enough: .NET's Clipboard.GetImage() and a good many other
// consumers ask for CF_BITMAP by name and get nothing to render. Windows' own
// PrintScreen puts both up, so we do the same.
HBITMAP MakeBitmap(const Gdiplus::BitmapData& d, int w, int h) {
    BITMAPINFO bi{};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = w;
    bi.bmiHeader.biHeight = -h;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;

    // A DIB section — even one over a page-file mapping — comes back as a dead
    // handle in the reading process. GDI's own device bitmap survives the trip.
    HDC dc = ::GetDC(nullptr);
    HBITMAP hbmp = ::CreateCompatibleBitmap(dc, w, h);
    if (hbmp && ::SetDIBits(dc, hbmp, 0, h, d.Scan0, &bi, DIB_RGB_COLORS) == 0) {
        ::DeleteObject(hbmp);
        hbmp = nullptr;
    }
    ::ReleaseDC(nullptr, dc);
    return hbmp;
}

}  // namespace

bool SetClipboard(Gdiplus::Bitmap& bmp) {
    const int w = bmp.GetWidth(), h = bmp.GetHeight();
    if (w <= 0 || h <= 0) return false;

    const Gdiplus::Rect rect(0, 0, w, h);
    Gdiplus::BitmapData d{};
    if (bmp.LockBits(&rect, Gdiplus::ImageLockModeRead, PixelFormat32bppARGB, &d) !=
        Gdiplus::Ok)
        return false;

    BITMAPINFOHEADER hdr{};
    hdr.biSize = sizeof(hdr);
    hdr.biWidth = w;
    hdr.biHeight = -h;  // negative = top-down, which matches LockBits stride
    hdr.biPlanes = 1;
    hdr.biBitCount = 32;
    hdr.biCompression = BI_RGB;
    hdr.biSizeImage = (DWORD)((size_t)d.Stride * h);

    HGLOBAL mem = ::GlobalAlloc(GMEM_MOVEABLE, sizeof(hdr) + hdr.biSizeImage);
    if (!mem) {
        bmp.UnlockBits(&d);
        return false;
    }

    unsigned char* dst = (unsigned char*)::GlobalLock(mem);
    memcpy(dst, &hdr, sizeof(hdr));
    for (int y = 0; y < h; ++y)
        memcpy(dst + sizeof(hdr) + (size_t)y * d.Stride,
               (unsigned char*)d.Scan0 + (size_t)y * d.Stride, (size_t)d.Stride);
    ::GlobalUnlock(mem);

    HBITMAP hbmp = MakeBitmap(d, w, h);
    bmp.UnlockBits(&d);

    if (!::OpenClipboard(nullptr)) {
        ::GlobalFree(mem);
        if (hbmp) ::DeleteObject(hbmp);
        return false;
    }
    ::EmptyClipboard();
    // On success the clipboard owns each object; freeing it here would corrupt it.
    const bool dibOk = ::SetClipboardData(CF_DIB, mem) != nullptr;
    const bool bmpOk = hbmp && ::SetClipboardData(CF_BITMAP, hbmp) != nullptr;
    ::CloseClipboard();

    if (!dibOk) ::GlobalFree(mem);
    if (!bmpOk && hbmp) ::DeleteObject(hbmp);
    return dibOk || bmpOk;
}

}  // namespace out
