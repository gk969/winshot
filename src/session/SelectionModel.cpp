#include "stdafx.h"
#include "SelectionModel.h"

namespace {

inline bool Near(POINT p, POINT q, int radius) {
    return abs(p.x - q.x) <= radius && abs(p.y - q.y) <= radius;
}

inline void Normalize(RECT& r) {
    if (r.right < r.left) std::swap(r.left, r.right);
    if (r.bottom < r.top) std::swap(r.top, r.bottom);
}

}  // namespace

void SelectionModel::Reset(RECT bounds) {
    m_bounds = bounds;
    m_rect = bounds;
    m_default = true;
}

void SelectionModel::Set(RECT r) {
    Normalize(r);
    Clamp(r);
    m_rect = r;
    m_default = r.left == m_bounds.left && r.top == m_bounds.top &&
                r.right == m_bounds.right && r.bottom == m_bounds.bottom;
}

SelHandle SelectionModel::HitTest(POINT pt, int radius) const {
    const RECT& r = m_rect;
    POINT corners[4] = {
        { r.left, r.top },  { r.right, r.top },
        { r.right, r.bottom }, { r.left, r.bottom },
    };
    const SelHandle cornerHandles[4] = {
        SelHandle::TopLeft, SelHandle::TopRight,
        SelHandle::BottomRight, SelHandle::BottomLeft,
    };
    for (int i = 0; i < 4; ++i)
        if (Near(pt, corners[i], radius)) return cornerHandles[i];

    // The frame draws eight grips, four corners and four edge midpoints, and
    // those are the only places a press resizes. Claiming the whole edge line
    // would leave the rest of the frame with nothing to say about it.
    const POINT mids[4] = {
        { (r.left + r.right) / 2, r.top },   { r.right, (r.top + r.bottom) / 2 },
        { (r.left + r.right) / 2, r.bottom }, { r.left, (r.top + r.bottom) / 2 },
    };
    const SelHandle midHandles[4] = {
        SelHandle::Top, SelHandle::Right, SelHandle::Bottom, SelHandle::Left,
    };
    for (int i = 0; i < 4; ++i)
        if (Near(pt, mids[i], radius)) return midHandles[i];

    return SelHandle::None;
}

bool SelectionModel::Contains(POINT pt) const {
    return pt.x >= m_rect.left && pt.x < m_rect.right &&
           pt.y >= m_rect.top && pt.y < m_rect.bottom;
}
bool SelectionModel::NearFrame(POINT pt, int band) const {
    const RECT& r = m_rect;
    if (pt.x < r.left - band || pt.x > r.right + band) return false;
    if (pt.y < r.top - band || pt.y > r.bottom + band) return false;
    return abs(pt.x - r.left) <= band || abs(pt.x - r.right) <= band ||
           abs(pt.y - r.top) <= band || abs(pt.y - r.bottom) <= band;
}

void SelectionModel::BeginCreate(POINT anchor) {
    m_default = false;
    m_anchor = anchor;
    m_rect = { anchor.x, anchor.y, anchor.x, anchor.y };
}

void SelectionModel::UpdateCreate(POINT pt) {
    RECT r = { m_anchor.x, m_anchor.y, pt.x, pt.y };
    Normalize(r);
    Clamp(r);
    m_rect = r;
}

void SelectionModel::MoveTo(RECT r) {
    int w = r.right - r.left;
    int h = r.bottom - r.top;
    if (w <= 0 || h <= 0) return;
    int l = std::clamp(r.left, m_bounds.left, m_bounds.right - w);
    int t = std::clamp(r.top, m_bounds.top, m_bounds.bottom - h);
    m_rect = { l, t, l + w, t + h };
    m_default = false;
}

void SelectionModel::MoveBy(int dx, int dy) {
    if (m_default) return;
    RECT r = m_rect;
    r.left += dx; r.top += dy; r.right += dx; r.bottom += dy;
    MoveTo(r);
}

void SelectionModel::Resize(SelHandle handle, POINT pt) {
    if (m_default) return;
    RECT r = m_rect;
    switch (handle) {
    case SelHandle::TopLeft:     r.left = pt.x; r.top = pt.y; break;
    case SelHandle::Top:         r.top = pt.y; break;
    case SelHandle::TopRight:    r.right = pt.x; r.top = pt.y; break;
    case SelHandle::Right:       r.right = pt.x; break;
    case SelHandle::BottomRight: r.right = pt.x; r.bottom = pt.y; break;
    case SelHandle::Bottom:      r.bottom = pt.y; break;
    case SelHandle::BottomLeft:  r.left = pt.x; r.bottom = pt.y; break;
    case SelHandle::Left:        r.left = pt.x; break;
    default: return;
    }
    Normalize(r);
    Clamp(r);
    m_rect = r;
}

void SelectionModel::Nudge(int dx, int dy, bool resizeEdges) {
    if (m_default) return;
    RECT r = m_rect;
    if (resizeEdges) {
        r.right += dx;
        r.bottom += dy;
    } else {
        r.left += dx;
        r.top += dy;
        r.right += dx;
        r.bottom += dy;
    }
    Normalize(r);
    Clamp(r);
    m_rect = r;
}

void SelectionModel::Clamp(RECT& r) const {
    if (r.left < m_bounds.left) r.left = m_bounds.left;
    if (r.top < m_bounds.top) r.top = m_bounds.top;
    if (r.right > m_bounds.right) r.right = m_bounds.right;
    if (r.bottom > m_bounds.bottom) r.bottom = m_bounds.bottom;
}
