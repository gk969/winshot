#pragma once

#include "Annotation.h"

namespace annot {

// Z-ordered bottom to top. The list owns the annotations; callers borrow raw
// pointers for one message handler at a time.
class AnnotationList {
public:
    size_t Count() const { return m_items.size(); }
    Annotation* At(size_t i) const {
        return i < m_items.size() ? m_items[i].get() : nullptr;
    }
    int IndexOf(const Annotation* a) const;

    void Add(std::unique_ptr<Annotation> a);
    void InsertAt(size_t i, std::unique_ptr<Annotation> a);
    std::unique_ptr<Annotation> RemoveAt(size_t i);
    std::unique_ptr<Annotation> ReplaceAt(size_t i, std::unique_ptr<Annotation> a);
    void Clear();

    // Topmost annotation under pt, or nullptr.
    Annotation* TopAt(Gdiplus::PointF pt) const;

    // `skip` leaves one shape out, for the overlay's cached canvas while that
    // shape is being dragged: the drag redraws it in the chrome pass instead.
    void DrawAll(Gdiplus::Graphics& g, const Annotation* skip = nullptr) const;

private:
    std::vector<std::unique_ptr<Annotation>> m_items;
};

// The half-side of one selection marker for this shape. `base` is the overlay's
// DPI-scaled default; a shape that has a stroke grows its markers with it, and
// the two kinds whose handles sit on a box the user can already see take half.
Gdiplus::REAL HandleSize(const Annotation& a, Gdiplus::REAL base);

// Selection chrome, per 矩形-点击已画矩形.png and
// 椭圆-点击已画椭圆可调整大小位置.png: a thin red box where the shape does not
// draw its own, and a white-cored red square on every handle.
void DrawSelection(Gdiplus::Graphics& g, const Annotation& a, Gdiplus::REAL base);

}  // namespace annot
