#pragma once

namespace ocr {

// Recognised text; empty when nothing was found or the engine is unavailable.
// Takes half a second to a few seconds, so it never runs on the UI thread —
// StartAsync does the threading.
std::wstring Run(Gdiplus::Bitmap& bmp);

// Hands the image over, recognises on its own thread, and posts
// WM_APP_OCR_DONE(wParam = new std::wstring) to `notify`. The bitmap is moved
// in, so the capture can close while the work is still running.
bool StartAsync(std::unique_ptr<Gdiplus::Bitmap> bmp, HWND notify);

}  // namespace ocr
