#pragma once

namespace out {

// Writes the bitmap out in whatever format the path's extension asks for:
// .jpg/.jpeg as JPEG, anything else as PNG.
bool Save(Gdiplus::Bitmap& bmp, const wchar_t* path);

// GetSaveFileName + Save, offering both formats. The caller must have demoted
// its topmost overlay already, or the dialog opens underneath it.
// Returns true when a file was actually written.
bool SaveWithDialog(Gdiplus::Bitmap& bmp, HWND owner);

}  // namespace out
