#include "stdafx.h"

namespace {
struct GdiplusInit {
    ULONG_PTR token = 0;
    GdiplusInit() {
        Gdiplus::GdiplusStartupInput in;
        Gdiplus::GdiplusStartup(&token, &in, nullptr);
    }
    ~GdiplusInit() {
        if (token) Gdiplus::GdiplusShutdown(token);
    }
};
GdiplusInit g_gdiplus;
}
