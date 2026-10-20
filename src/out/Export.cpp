#include "stdafx.h"
#include "Export.h"

#include <commdlg.h>

namespace out {

namespace {

constexpr int kJpegQuality = 90;

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

// Everything after the last separator. The extension has to be read off the
// name alone: a folder called "v1.2" says nothing about the file in it.
const wchar_t* Leaf(const wchar_t* path) {
    const wchar_t* leaf = path;
    for (const wchar_t* p = path; *p; ++p)
        if (*p == L'\\' || *p == L'/') leaf = p + 1;
    return leaf;
}

bool HasExtension(const wchar_t* path) {
    return wcschr(Leaf(path), L'.') != nullptr;
}

bool IsJpegPath(const wchar_t* path) {
    const wchar_t* dot = wcsrchr(Leaf(path), L'.');
    if (!dot) return false;
    return _wcsicmp(dot, L".jpg") == 0 || _wcsicmp(dot, L".jpeg") == 0;
}

CString DefaultName() {
    SYSTEMTIME st;
    ::GetLocalTime(&st);
    CString name;
    // Deliberately extensionless: the format dropdown decides it, and a name
    // that already carried one would override the dropdown every time.
    name.Format(L"截图%04d%02d%02d%02d%02d%02d", st.wYear, st.wMonth, st.wDay,
                st.wHour, st.wMinute, st.wSecond);
    return name;
}

}  // namespace

bool Save(Gdiplus::Bitmap& bmp, const wchar_t* path) {
    CLSID clsid;
    if (IsJpegPath(path)) {
        if (!EncoderClsid(L"image/jpeg", &clsid)) return false;
        // The parameter is ignored unless its type is exactly LONG, and without
        // it the encoder falls back to its own default of 75, which rings
        // visibly around the solid frames and text a screenshot is full of.
        Gdiplus::EncoderParameters ep{};
        LONG quality = kJpegQuality;
        ep.Count = 1;
        ep.Parameter[0].Guid = Gdiplus::EncoderQuality;
        ep.Parameter[0].Type = Gdiplus::EncoderParameterValueTypeLong;
        ep.Parameter[0].NumberOfValues = 1;
        ep.Parameter[0].Value = &quality;
        return bmp.Save(path, &clsid, &ep) == Gdiplus::Ok;
    }
    if (!EncoderClsid(L"image/png", &clsid)) return false;
    return bmp.Save(path, &clsid, nullptr) == Gdiplus::Ok;
}

bool SaveWithDialog(Gdiplus::Bitmap& bmp, HWND owner) {
    wchar_t file[520];
    lstrcpynW(file, DefaultName(), (int)std::size(file));

    OPENFILENAMEW ofn{};
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = owner;
    ofn.lpstrFilter = L"PNG (*.png)\0*.png\0JPEG (*.jpg)\0*.jpg\0";
    ofn.lpstrFile = file;
    ofn.nMaxFile = (DWORD)std::size(file);
    // lpstrDefExt is a single value that does not follow the filter: with
    // L"png" here Windows appends .png even when the caller picked JPEG, which
    // would make the format dropdown do nothing. The extension comes from
    // nFilterIndex below instead.
    ofn.lpstrDefExt = nullptr;
    ofn.Flags = OFN_PATHMUSTEXIST | OFN_OVERWRITEPROMPT | OFN_HIDEREADONLY;

    // The caller owns the overlay's topmost state; it has to be demoted for the
    // dialog to be seen, and the overlay knows how to allow that.
    if (!::GetSaveFileNameW(&ofn)) return false;

    // nFilterIndex is 1-based and entry 1 is PNG. A name typed with an extension
    // of its own wins over the dropdown: that is what a Save As box does
    // everywhere else, and it keeps the name and the bytes in agreement.
    if (!HasExtension(file)) {
        const wchar_t* ext = (ofn.nFilterIndex == 2) ? L".jpg" : L".png";
        // GetSaveFileName guarantees the returned string fits in nMaxFile but
        // leaves no room to grow it.
        if (wcslen(file) + wcslen(ext) < std::size(file)) lstrcatW(file, ext);
    }
    return Save(bmp, file);
}

}  // namespace out
