#pragma once

#include "MosaicSource.h"

class CaptureSession;

// What the 马赛克 brush samples: the frozen still under the selection plus the
// ink already on the canvas, averaged into squares. Rebuilt when the block size,
// the selection or the annotation list moves — never while a stroke is being
// dragged, which is what keeps a 60Hz redraw cheap.
class MosaicCache : public annot::MosaicSource {
public:
    explicit MosaicCache(CaptureSession* session) : m_session(session) {}

    const Gdiplus::Bitmap* Pixels(int block, Gdiplus::PointF* at) override;
    void Invalidate() { m_bmp.reset(); }

private:
    CaptureSession* m_session;
    std::unique_ptr<Gdiplus::Bitmap> m_bmp;
    int m_block = 0;
    RECT m_sel = {};
    POINT m_off = {};
    Gdiplus::PointF m_at{};
};
