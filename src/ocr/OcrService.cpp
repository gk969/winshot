#include "stdafx.h"
#include "OcrService.h"

#include "../AppMessages.h"

#include <thread>

// afx.h's MFC exception macro collides with CurrencyIdentifiers::TRY() in the
// globalization projection. Nothing here uses TRY/CATCH.
#undef TRY

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.Streams.h>

#pragma comment(lib, "windowsapp.lib")

namespace {

namespace globalization = winrt::Windows::Globalization;
namespace imaging = winrt::Windows::Graphics::Imaging;
namespace ocrapi = winrt::Windows::Media::Ocr;
namespace streams = winrt::Windows::Storage::Streams;

// Recognition of small screen text drops off a cliff; rendering the same pixels
// twice as large is what makes Chinese UI text come back legible.
constexpr int kSmallHeight = 400;
constexpr double kUpscale = 2.0;

Gdiplus::Bitmap* Prepared(Gdiplus::Bitmap& src, std::unique_ptr<Gdiplus::Bitmap>& holder) {
    if (src.GetHeight() >= kSmallHeight) return &src;

    const int w = (int)(src.GetWidth() * kUpscale + 0.5);
    const int h = (int)(src.GetHeight() * kUpscale + 0.5);
    auto big = std::make_unique<Gdiplus::Bitmap>(w, h, PixelFormat32bppARGB);
    Gdiplus::Graphics g(big.get());
    g.SetInterpolationMode(Gdiplus::InterpolationModeBicubic);
    g.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);
    g.DrawImage(&src, Gdiplus::Rect(0, 0, w, h));
    holder = std::move(big);
    return holder.get();
}

imaging::SoftwareBitmap ToSoftware(Gdiplus::Bitmap& bmp) {
    Gdiplus::Rect rc(0, 0, (int)bmp.GetWidth(), (int)bmp.GetHeight());
    Gdiplus::BitmapData data{};
    if (bmp.LockBits(&rc, Gdiplus::ImageLockModeRead, PixelFormat32bppARGB, &data) != Gdiplus::Ok)
        return imaging::SoftwareBitmap{ nullptr };

    // WriteBytes copies into the writer, so the LockBits buffer is released
    // before anything below can throw.
    streams::DataWriter writer;
    writer.WriteBytes(winrt::array_view<uint8_t const>(
        (uint8_t const*)data.Scan0,
        (uint8_t const*)data.Scan0 + (size_t)data.Stride * (size_t)data.Height));
    bmp.UnlockBits(&data);

    // Bgra8 matches LockBits' Format32bppARGB byte order, so there is no
    // conversion and no PNG round trip.
    return imaging::SoftwareBitmap::CreateCopyFromBuffer(
        writer.DetachBuffer(), imaging::BitmapPixelFormat::Bgra8,
        (int32_t)bmp.GetWidth(), (int32_t)bmp.GetHeight());
}

ocrapi::OcrEngine Engine() {
    for (auto tag : { L"zh-CN", L"en-US" })
        if (auto e = ocrapi::OcrEngine::TryCreateFromLanguage(globalization::Language(tag)))
            return e;
    return ocrapi::OcrEngine::TryCreateFromUserProfileLanguages();
}

}  // namespace

namespace ocr {

std::wstring Run(Gdiplus::Bitmap& bmp) {
    try {
        // MFC does not initialise an apartment for threads it did not create,
        // and every call below needs one.
        winrt::init_apartment(winrt::apartment_type::multi_threaded);

        std::wstring out;
        {
            std::unique_ptr<Gdiplus::Bitmap> holder;
            imaging::SoftwareBitmap sb = ToSoftware(*Prepared(bmp, holder));
            if (sb) {
                ocrapi::OcrEngine engine = Engine();
                if (engine) {
                    winrt::hstring text = engine.RecognizeAsync(sb).get().Text();
                    out.assign(text.data(), text.size());
                }
            }
        }  // the WinRT objects have to go before the apartment closes
        winrt::uninit_apartment();
        return out;
    } catch (...) {
        return std::wstring();
    }
}

bool StartAsync(std::unique_ptr<Gdiplus::Bitmap> bmp, HWND notify) {
    if (!bmp || !::IsWindow(notify)) return false;
    try {
        std::thread worker([bmp = std::move(bmp), notify] {
            std::wstring* text = new std::wstring(Run(*bmp));
            if (!::PostMessageW(notify, WM_APP_OCR_DONE, (WPARAM)text, 0)) delete text;
        });
        worker.detach();
        return true;
    } catch (...) {
        return false;
    }
}

}  // namespace ocr
