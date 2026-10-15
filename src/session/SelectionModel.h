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

    void Set(RECT r);

    SelHandle HitTest(POINT pt, int radius) const;
    bool Contains(POINT pt) const;

    void BeginCreate(POINT anchor);
    void UpdateCreate(POINT pt);
    // Repositions without changing size, stopping at the bounds.
    void MoveTo(RECT r);
    void MoveBy(int dx, int dy);
    void Resize(SelHandle handle, POINT pt);
    void Nudge(int dx, int dy, bool resizeEdges);

private:
    void Clamp(RECT& r) const;

    RECT m_rect = {};
    RECT m_bounds = {};
    POINT m_anchor = {};
    bool m_default = true;
};
