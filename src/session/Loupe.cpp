#include "stdafx.h"
#include "Loupe.h"

#include "../DesktopCapture.h"
#include "../Dpi.h"
#include "../out/ClipboardText.h"
#include "CaptureSession.h"

#include <algorithm>

namespace {

const wchar_t kFace[] = L"Microsoft YaHei UI";

}  // namespace

RECT loupe::CardRect(HWND hwnd, CPoint at, const CRect& bounds) {
    const int w = Dpi::S(hwnd, kBoxW);
    // The readout starts on the frame's bottom row, so the two boxes share it.
    const int h = Dpi::S(hwnd, kBoxH) + Dpi::S(hwnd, kInfoH) - 1;
    int x = at.x - w / 2;
    int y = at.y - Dpi::S(hwnd, kBoxH) / 2;
    if (x < bounds.left) x = bounds.left;
    if (x + w > bounds.right) x = bounds.right - w;
    if (y < bounds.top) y = bounds.top;
    if (y + h > bounds.bottom) y = bounds.bottom - h;
    return RECT{ x, y, x + w, y + h };
}

COLORREF loupe::Sampled(const DesktopCapture& cap, CPoint at, POINT off) {
    Gdiplus::Bitmap* img = cap.Image();
    if (!img) return RGB(255, 255, 255);
    const int x = std::clamp<int>(at.x - off.x, 0, (int)img->GetWidth() - 1);
    const int y = std::clamp<int>(at.y - off.y, 0, (int)img->GetHeight() - 1);
    Gdiplus::Color c;
    if (img->GetPixel(x, y, &c) != Gdiplus::Ok) return RGB(255, 255, 255);
    return RGB(c.GetRed(), c.GetGreen(), c.GetBlue());
}

void loupe::Draw(CaptureSession& session, CPoint at, Gdiplus::Graphics& g, const CRect& bounds) {
    const HWND hwnd = session.Overlay().GetSafeHwnd();
    const int boxW = Dpi::S(hwnd, kBoxW), boxH = Dpi::S(hwnd, kBoxH);
    const int infoH = Dpi::S(hwnd, kInfoH);
    const int pad = Dpi::S(hwnd, 1);
    const RECT card = CardRect(hwnd, at, bounds);

    Gdiplus::SolidBrush frame(kFrame);
    g.FillRectangle(&frame, (Gdiplus::REAL)card.left, (Gdiplus::REAL)card.top,
                    (Gdiplus::REAL)boxW, (Gdiplus::REAL)boxH);

    const int fieldX = card.left + pad, fieldY = card.top + pad;
    const int fieldW = boxW - pad * 2, fieldH = boxH - pad * 2;

    Gdiplus::Bitmap* img = session.Capture().Image();
    if (!img) return;
    // The cursor is in overlay-client space; the still starts at `off` within it.
    const POINT off = session.CapOff();
    const int ax = at.x - off.x, ay = at.y - off.y;
    int srcW = fieldW / kScale, srcH = fieldH / kScale;
    srcW = std::min(srcW, (int)img->GetWidth());
    srcH = std::min(srcH, (int)img->GetHeight());
    // Centred on the cursor, then pushed back inside the still so the field is
    // never partly empty; the crosshair below follows the same offset, which is
    // what keeps it on the sampled pixel at the screen edges.
    const int sx = std::clamp<int>(ax - srcW / 2, 0, (int)img->GetWidth() - srcW);
    const int sy = std::clamp<int>(ay - srcH / 2, 0, (int)img->GetHeight() - srcH);

    const Gdiplus::GraphicsState gs = g.Save();
    g.SetClip(Gdiplus::RectF((Gdiplus::REAL)fieldX, (Gdiplus::REAL)fieldY,
                             (Gdiplus::REAL)fieldW, (Gdiplus::REAL)fieldH));
    g.SetInterpolationMode(Gdiplus::InterpolationModeNearestNeighbor);
    g.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);
    g.DrawImage(img, Gdiplus::Rect(fieldX, fieldY, fieldW, fieldH),
                sx, sy, srcW, srcH, Gdiplus::UnitPixel);

    g.SetPixelOffsetMode(Gdiplus::PixelOffsetModeNone);
    g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    // The sampled pixel occupies a kScale-wide block; the crosshair goes on its
    // centre, which is also where the cursor is.
    const int cx = std::clamp<int>(fieldX + (ax - sx) * kScale + kScale / 2,
                                   fieldX, fieldX + fieldW - 1);
    const int cy = std::clamp<int>(fieldY + (ay - sy) * kScale + kScale / 2,
                                   fieldY, fieldY + fieldH - 1);
    Gdiplus::Pen cross(kCross, (Gdiplus::REAL)Dpi::S(hwnd, 4));
    g.DrawLine(&cross, (Gdiplus::REAL)fieldX, (Gdiplus::REAL)cy,
               (Gdiplus::REAL)(fieldX + fieldW), (Gdiplus::REAL)cy);
    g.DrawLine(&cross, (Gdiplus::REAL)cx, (Gdiplus::REAL)fieldY,
               (Gdiplus::REAL)cx, (Gdiplus::REAL)(fieldY + fieldH));
    g.Restore(gs);

    const int iy = card.top + boxH - pad;
    Gdiplus::SolidBrush back(kInfoBack);
    g.FillRectangle(&back, (Gdiplus::REAL)card.left, (Gdiplus::REAL)iy,
                    (Gdiplus::REAL)boxW, (Gdiplus::REAL)infoH);

    const COLORREF c = Sampled(session.Capture(), at, off);
    CString lines[4];
    lines[0].Format(L"%d x %d", session.Sel().Width(), session.Sel().Height());
    lines[1].Format(L"RGB:(%d,%d,%d)", GetRValue(c), GetGValue(c), GetBValue(c));
    lines[2] = L"按c复制色号";
    lines[3] = L"鼠标右键自由截图";

    Gdiplus::FontFamily family(kFace);
    Gdiplus::Font font(&family, (Gdiplus::REAL)Dpi::S(hwnd, kInfoFont),
                       Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
    g.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
    Gdiplus::StringFormat fmt;
    fmt.SetAlignment(Gdiplus::StringAlignmentNear);
    fmt.SetLineAlignment(Gdiplus::StringAlignmentNear);
    const int textPad = Dpi::S(hwnd, kInfoPad), lineH = Dpi::S(hwnd, kInfoLine);
    Gdiplus::SolidBrush ink(kInfoText);
    for (int i = 0; i < 4; ++i)
        g.DrawString(lines[i], -1, &font,
                     Gdiplus::RectF((Gdiplus::REAL)(card.left + textPad),
                                    (Gdiplus::REAL)(iy + pad + i * lineH),
                                    (Gdiplus::REAL)(boxW - textPad * 2),
                                    (Gdiplus::REAL)lineH),
                     &fmt, &ink);
}

bool loupe::CopyColor(const DesktopCapture& cap, CPoint at, POINT off) {
    const COLORREF c = Sampled(cap, at, off);
    CString s;
    s.Format(L"RGB:(%d,%d,%d)", GetRValue(c), GetGValue(c), GetBValue(c));
    return out::SetText(s.GetString());
}
