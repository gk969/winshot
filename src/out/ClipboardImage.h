#pragma once

namespace out {

// Puts the image on the clipboard as CF_DIB. Every consumer takes it (Paint,
// Office, Explorer) and, unlike CF_BITMAP, there is no GDI object whose
// lifetime we then have to track.
bool SetClipboard(Gdiplus::Bitmap& bmp);

}  // namespace out
