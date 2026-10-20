#include "stdafx.h"
#include "WindowPick.h"

namespace {

// The desktop's own layers. Hovering the wallpaper or the taskbar must not offer
// a pre-selection, because the click there already means the whole screen and a
// frame around the desktop would be a frame around nothing.
bool IsDesktopLayer(const wchar_t* cls) {
    return wcscmp(cls, L"Progman") == 0 || wcscmp(cls, L"WorkerW") == 0 ||
           wcscmp(cls, L"Shell_TrayWnd") == 0 ||
           wcscmp(cls, L"Shell_SecondaryTrayWnd") == 0 ||
           wcscmp(cls, L"ApplicationWindowLightDismiss") == 0;
}

// The bounds as the user sees them. GetWindowRect includes the several pixels of
// invisible resize border that DWM draws the shadow into, so a frame from it
// stands outside the window's own edge, and for a maximized window it runs off
// the negative side of the monitor; the extended frame bounds are the visible
// rectangle. The fallback is for the windows DWM has no such record of —
// borderless, layered, console — where there is no cleaner answer to have.
CRect VisibleBounds(HWND hwnd) {
    RECT r{};
    if (SUCCEEDED(::DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, &r,
                                          sizeof(r))) &&
        !::IsRectEmpty(&r))
        return CRect(r);
    if (::GetWindowRect(hwnd, &r) && !::IsRectEmpty(&r)) return CRect(r);
    return CRect();
}

}  // namespace

namespace winpick {

CRect TopWindowUnder(POINT screenPt) {
    const CPoint pt(screenPt);
    const DWORD ownPid = ::GetCurrentProcessId();

    // GetTopWindow then GetWindow(GW_HWNDNEXT) is the actual top-to-bottom z-order
    // and it includes owned windows. GW_HWNDPREV is the other way round — it
    // climbs, and from the topmost window it returns null at once, which is the
    // mistake that made this walk one window long. EnumWindows is not documented
    // to walk in z-order and skips owned windows, so it can report a dialog as
    // behind the window it belongs to — and "the topmost window here" is the
    // whole claim.
    //
    // Nothing is cached: the desktop under the overlay is live, and a cached list
    // would be wrong the moment anything opens, moves or closes. The chain is
    // longer than it looks — a few hundred entries, most of them invisible
    // tooltips and IME helpers belonging to explorer — but the point test below
    // rejects all of them without a second call, and the whole walk measured well
    // under a millisecond.
    for (HWND hwnd = ::GetTopWindow(::GetDesktopWindow()); hwnd;
         hwnd = ::GetWindow(hwnd, GW_HWNDNEXT)) {
        // Cheapest rejections first. The point test alone drops nearly every
        // window on a normal desktop, which keeps the DWM round trip at the end
        // and down to about one per mouse move.
        RECT rough{};
        if (!::GetWindowRect(hwnd, &rough) || !::PtInRect(&rough, pt)) continue;
        if (!::IsWindowVisible(hwnd)) continue;

        // Our own windows — the overlay, the tray sink, the tip card, the pins,
        // the OCR window — are not program windows by any reading, and the
        // overlay would otherwise win every hover on the screen.
        DWORD pid = 0;
        if (::GetWindowThreadProcessId(hwnd, &pid) == 0 || pid == ownPid) continue;

        if ((::GetWindowLong(hwnd, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) != 0) continue;

        wchar_t cls[64] = {};
        if (::GetClassName(hwnd, cls, ARRAYSIZE(cls)) && IsDesktopLayer(cls))
            continue;

        // Last, because it is the only call here that leaves the process. Start
        // Menu, Search, Task View and background UWP windows are all "visible"
        // and cloaked; without this one of them wins every hover of the desktop.
        DWORD cloaked = 0;
        if (SUCCEEDED(::DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked,
                                              sizeof(cloaked))) &&
            cloaked != 0)
            continue;

        const CRect bounds = VisibleBounds(hwnd);
        if (bounds.IsRectEmpty()) continue;
        return bounds;
    }
    return CRect();
}

}  // namespace winpick
