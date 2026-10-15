#include "stdafx.h"
#include "FrameGrab.h"
#include "Stitcher.h"

namespace ls {

bool GrabFrame(RECT rc, Frame& out) {
    const int w = rc.right - rc.left, h = rc.bottom - rc.top;
    if (w <= 0 || h <= 0) return false;

    HDC screen = ::GetDC(nullptr);
    if (!screen) return false;

    HDC mem = CreateCompatibleDC(screen);
    BITMAPINFO bi = {};
    bi.bmiHeader.biSize = sizeof(bi.bmiHeader);
    bi.bmiHeader.biWidth = w;
    bi.bmiHeader.biHeight = -h;  // top-down, so row 0 is the hole's top row
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
    ::ShowCursor(FALSE);
    BitBlt(mem, 0, 0, w, h, screen, rc.left, rc.top, SRCCOPY);
    ::ShowCursor(TRUE);
    SelectObject(mem, oldBmp);

    out.px.assign((size_t)w * h, 0u);
    const uint32_t* srcBits = static_cast<const uint32_t*>(bits);
    for (int y = 0; y < h; ++y) {
        const uint32_t* src = srcBits + (size_t)y * w;
        uint32_t* dst = out.px.data() + (size_t)y * w;
        for (int x = 0; x < w; ++x) dst[x] = src[x] | 0xFF000000u;
    }
    out.sigs = RowSignatures(out.px.data(), w, h, w);
    out.width = w;
    out.height = h;

    DeleteObject(dib);
    DeleteDC(mem);
    ::ReleaseDC(nullptr, screen);
    return true;
}

}  // namespace ls
