#include "stdafx.h"
#include "ExportPng.h"

#include <commdlg.h>

namespace out {

namespace {

bool EncoderClsid(const wchar_t* mime, CLSID* clsid) {
    UINT count = 0, size = 0;
    Gdiplus::GetImageEncodersSize(&count, &size);
    if (size == 0) return false;

    std::vector<unsigned char> buf(size);
    Gdiplus::ImageCodecInfo* codecs =
        reinterpret_cast<Gdiplus::ImageCodecInfo*>(buf.data());
    if (Gdiplus::GetImageEncoders(count, size, codecs) != Gdiplus::Ok) return false;

    for (UINT i = 0; i < count; ++i) {
        if (wcscmp(codecs[i].MimeType, mime) == 0) {
            *clsid = codecs[i].Clsid;
            return true;
        }
    }
    return false;
}

CString DefaultName() {
    SYSTEMTIME st;
    ::GetLocalTime(&st);
    CString name;
    name.Format(L"截图%04d%02d%02d%02d%02d%02d.png", st.wYear, st.wMonth, st.wDay,
                st.wHour, st.wMinute, st.wSecond);
    return name;
}

}  // namespace

bool SavePng(Gdiplus::Bitmap& bmp, const wchar_t* path) {
    CLSID clsid;
    if (!EncoderClsid(L"image/png", &clsid)) return false;
    return bmp.Save(path, &clsid, nullptr) == Gdiplus::Ok;
}

bool SavePngWithDialog(Gdiplus::Bitmap& bmp, HWND owner) {
    wchar_t file[520];
    lstrcpynW(file, DefaultName(), (int)std::size(file));

    OPENFILENAMEW ofn{};
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = owner;
    ofn.lpstrFilter = L"PNG (*.png)\0*.png\0";
    ofn.lpstrFile = file;
    ofn.nMaxFile = (DWORD)std::size(file);
    ofn.lpstrDefExt = L"png";
    ofn.Flags = OFN_PATHMUSTEXIST | OFN_OVERWRITEPROMPT | OFN_HIDEREADONLY;

    // The caller owns the overlay's topmost state; it has to be demoted for the
    // dialog to be seen, and the overlay knows how to allow that.
    const BOOL ok = ::GetSaveFileNameW(&ofn);
    return ok && SavePng(bmp, file);
}

}  // namespace out
