#include "stdafx.h"
#include "Dpi.h"
#include <shellscalingapi.h>

#pragma comment(lib, "gdi32.lib")

namespace Dpi {

UINT ForWindow(HWND hwnd) {
    if (!hwnd) return 96;
    UINT dpi = GetDpiForWindow(hwnd);
    return dpi ? dpi : 96;
}

UINT ForMonitorOfPoint(POINT pt) {
    HMONITOR mon = MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST);
    UINT dx = 96, dy = 96;
    if (SUCCEEDED(GetDpiForMonitor(mon, MDT_EFFECTIVE_DPI, &dx, &dy)))
        return dx ? dx : 96;
    return 96;
}

int S(HWND hwnd, int logicalPx) {
    return MulDiv(logicalPx, ForWindow(hwnd), 96);
}

int FontHeightForPoint(HWND hwnd, int pointSize) {
    return -MulDiv(pointSize, ForWindow(hwnd), 72);
}

RECT VirtualScreen() {
    RECT r;
    r.left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    r.top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    r.right = r.left + GetSystemMetrics(SM_CXVIRTUALSCREEN);
    r.bottom = r.top + GetSystemMetrics(SM_CYVIRTUALSCREEN);
    return r;
}

}  // namespace Dpi
