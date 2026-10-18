#pragma once

enum class SelHandle {
    None,
    TopLeft, Top, TopRight, Right, BottomRight, Bottom, BottomLeft, Left
};

// The capture region, in overlay-client pixels — which are the same pixels as
// the frozen still, so annotations and the export share this space.
class SelectionModel {
public:
    void Reset(RECT bounds);

    const RECT& Bounds() const { return m_bounds; }
    const RECT& Rect() const { return m_rect; }
    int Width() const { return m_rect.right - m_rect.left; }
    int Height() const { return m_rect.bottom - m_rect.top; }
    bool IsEmpty() const { return Width() <= 0 || Height() <= 0; }

    // True until the user touches the selection; while true a left drag starts
    // a new region instead of moving the full-screen default.
    bool IsDefault() const { return m_default; }
    // A press that never dragged still picked the region: it stays the whole
    // screen, but the next press moves it and the loupe card goes away.
    void MarkPicked() { m_default = false; }

    void Set(RECT r);

    // The box the drawn annotations cover, or null for none. The region may
    // never be moved or resized so that something falls outside it, which also
    // means it can never end up smaller than what is drawn on it. Callers set it
    // before each change; it is not remembered across them.
    void SetKeepIn(const RECT* keepIn) {
        m_keepIn = keepIn ? *keepIn : RECT{};
        m_hasKeepIn = keepIn != nullptr;
    }

    SelHandle HitTest(POINT pt, int radius) const;
    bool Contains(POINT pt) const;
    // Within `band` pixels of the frame line, on either side of it. The corners
    // and edge midpoints answer through HitTest first; what is left along the
    // frame is where a press moves the whole region.
    bool NearFrame(POINT pt, int band) const;

    void BeginCreate(POINT anchor);
    void UpdateCreate(POINT pt);
    // Repositions without changing size, stopping at the bounds.
    void MoveTo(RECT r);
    void MoveBy(int dx, int dy);
    void Resize(SelHandle handle, POINT pt);
    void Nudge(int dx, int dy, bool resizeEdges);

private:
    void Clamp(RECT& r) const;
    // Grows `r` back over the drawings, for the resizes that move one edge.
    void KeepIn(RECT& r) const;
    // Slides `r` back over the drawings, keeping its size, for the moves.
    void KeepInside(RECT& r) const;
    bool HasKeepIn() const { return m_hasKeepIn && !IsRectEmpty(&m_keepIn); }

    RECT m_rect = {};
    RECT m_bounds = {};
    POINT m_anchor = {};
    RECT m_keepIn = {};
    bool m_hasKeepIn = false;
    bool m_default = true;
};
