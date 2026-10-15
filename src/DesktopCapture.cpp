#include "stdafx.h"
#include "DesktopCapture.h"
#include "Dpi.h"

bool DesktopCapture::Grab() {
    RECT vs = Dpi::VirtualScreen();
    int w = vs.right - vs.left;
    int h = vs.bottom - vs.top;
    if (w <= 0 || h <= 0) return false;

    HDC screen = ::GetDC(nullptr);
    if (!screen) return false;

    HDC mem = CreateCompatibleDC(screen);
    BITMAPINFO bi = {};
    bi.bmiHeader.biSize = sizeof(bi.bmiHeader);
    bi.bmiHeader.biWidth = w;
    bi.bmiHeader.biHeight = -h;  // top-down, matches Gdiplus LockBits rows
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;

    void* bits = nullptr;
    HBITMAP dib = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!mem || !dib || !bits) {
        if (dib) DeleteObject(dib);
        if (mem) DeleteDC(mem);
        ::ReleaseDC(nullptr, screen);
        return false;
    }

    HGDIOBJ oldBmp = SelectObject(mem, dib);

    // The cursor must not be burned into the still.
    ShowCursor(FALSE);
    BitBlt(mem, 0, 0, w, h, screen, vs.left, vs.top, SRCCOPY);
    ShowCursor(TRUE);

    SelectObject(mem, oldBmp);

    auto image = std::make_unique<Gdiplus::Bitmap>(w, h, PixelFormat32bppARGB);
    Gdiplus::BitmapData dst = {};
    Gdiplus::Rect lockRect(0, 0, w, h);
    if (image->LockBits(&lockRect, Gdiplus::ImageLockModeWrite,
                        PixelFormat32bppARGB, &dst) != Gdiplus::Ok) {
        DeleteObject(dib);
        DeleteDC(mem);
        ::ReleaseDC(nullptr, screen);
        return false;
    }

    // BitBlt leaves the alpha byte at zero, which GDI+ would render as fully
    // transparent.
    const uint32_t* srcBits = static_cast<const uint32_t*>(bits);
    for (int y = 0; y < h; ++y) {
        uint32_t* row = reinterpret_cast<uint32_t*>(
            static_cast<BYTE*>(dst.Scan0) + static_cast<size_t>(y) * dst.Stride);
        const uint32_t* srcRow = srcBits + static_cast<size_t>(y) * w;
        for (int x = 0; x < w; ++x) row[x] = srcRow[x] | 0xFF000000u;
    }
    image->UnlockBits(&dst);

    DeleteObject(dib);
    DeleteDC(mem);
    ::ReleaseDC(nullptr, screen);

    m_image = std::move(image);
    m_width = w;
    m_height = h;
    m_origin = { vs.left, vs.top };
    return true;
}

void DesktopCapture::Adopt(std::unique_ptr<Gdiplus::Bitmap> image, POINT origin) {
    if (!image) return;
    m_image = std::move(image);
    m_width = (int)m_image->GetWidth();
    m_height = (int)m_image->GetHeight();
    m_origin = origin;
}
