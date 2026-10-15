#pragma once

namespace out {

bool SavePng(Gdiplus::Bitmap& bmp, const wchar_t* path);

// GetSaveFileName + SavePng. The caller must have demoted its topmost overlay
// already, or the dialog opens underneath it.
// Returns true when a file was actually written.
bool SavePngWithDialog(Gdiplus::Bitmap& bmp, HWND owner);

}  // namespace out
