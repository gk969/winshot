#include "stdafx.h"
#include "ClipboardText.h"

namespace out {

bool SetText(const wchar_t* text) {
    if (!text) return false;
    const size_t chars = wcslen(text) + 1;

    if (!::OpenClipboard(nullptr)) return false;
    bool ok = false;
    if (::EmptyClipboard()) {
        HGLOBAL h = ::GlobalAlloc(GMEM_MOVEABLE, chars * sizeof(wchar_t));
        if (h) {
            if (wchar_t* p = (wchar_t*)::GlobalLock(h)) {
                ::CopyMemory(p, text, chars * sizeof(wchar_t));
                ::GlobalUnlock(h);
                // On success the clipboard owns the handle; never free it then.
                ok = ::SetClipboardData(CF_UNICODETEXT, h) != nullptr;
            }
            if (!ok) ::GlobalFree(h);
        }
    }
    ::CloseClipboard();
    return ok;
}

}  // namespace out
