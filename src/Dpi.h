#pragma once

// All geometry in this app is physical pixels. Only font point sizes and
// text metrics go through the scaling helpers below.
namespace Dpi {

UINT ForWindow(HWND hwnd);
UINT ForMonitorOfPoint(POINT pt);

// Scale a logical (96dpi) size to physical pixels for the given window.
int S(HWND hwnd, int logicalPx);

// Font height (negative lfHeight) for a point size at the window's DPI.
int FontHeightForPoint(HWND hwnd, int pointSize);

RECT VirtualScreen();

}  // namespace Dpi
