#pragma once

// The window whose bounds the pre-selection frame follows while the cursor
// hovers the live desktop, before any region has been picked.
namespace winpick {

// The topmost eligible window under a physical virtual-screen point, as that
// window's visible bounds in the same coordinates. Empty when there is none,
// which is what leaves a click meaning "the whole screen".
CRect TopWindowUnder(POINT screenPt);

}  // namespace winpick
