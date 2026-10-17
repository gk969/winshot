#pragma once

// A frozen still of the whole virtual desktop. Taken before the overlay window
// exists, so the overlay can never appear in its own background.
class DesktopCapture {
public:
    bool Grab();

    // 编辑 hands the session a stitched image to keep working on. Unlike the
    // still it is anchored inside the screen rather than at its corner, so the
    // overlay and the compositor need to know where it starts.
    void Adopt(std::unique_ptr<Gdiplus::Bitmap> image, POINT origin);

    // The still Adopt replaced. 编辑 keeps it as the ground outside the frame,
    // so it is handed over rather than dropped with the document.
    std::unique_ptr<Gdiplus::Bitmap> Detach() {
        m_width = m_height = 0;
        return std::move(m_image);
    }

    // Moving an adopted image without replacing it: the 编辑 view scrolls the
    // stitched document by moving where it starts.
    void SetOrigin(POINT origin) { m_origin = origin; }

    // Non-const because Gdiplus::Graphics::DrawImage takes Image*, not
    // const Image*; the image itself is never mutated after Grab().
    Gdiplus::Bitmap* Image() const { return m_image.get(); }
    int Width() const { return m_width; }
    int Height() const { return m_height; }

    // Top-left of the still in physical virtual-screen coordinates.
    POINT Origin() const { return m_origin; }

private:
    std::unique_ptr<Gdiplus::Bitmap> m_image;
    int m_width = 0;
    int m_height = 0;
    POINT m_origin = {};
};
