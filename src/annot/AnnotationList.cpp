#include "stdafx.h"
#include "AnnotationList.h"

namespace annot {

namespace {

const Gdiplus::Color kSel(0xFFFA373A);

}  // namespace

int AnnotationList::IndexOf(const Annotation* a) const {
    for (size_t i = 0; i < m_items.size(); ++i)
        if (m_items[i].get() == a) return (int)i;
    return -1;
}

void AnnotationList::Add(std::unique_ptr<Annotation> a) {
    m_items.push_back(std::move(a));
}

void AnnotationList::InsertAt(size_t i, std::unique_ptr<Annotation> a) {
    if (i >= m_items.size()) m_items.push_back(std::move(a));
    else m_items.insert(m_items.begin() + (long)i, std::move(a));
}

std::unique_ptr<Annotation> AnnotationList::RemoveAt(size_t i) {
    if (i >= m_items.size()) return nullptr;
    std::unique_ptr<Annotation> out = std::move(m_items[i]);
    m_items.erase(m_items.begin() + (long)i);
    return out;
}

std::unique_ptr<Annotation> AnnotationList::ReplaceAt(size_t i,
                                                      std::unique_ptr<Annotation> a) {
    if (i >= m_items.size()) return nullptr;
    std::unique_ptr<Annotation> old = std::move(m_items[i]);
    m_items[i] = std::move(a);
    return old;
}

void AnnotationList::Clear() {
    m_items.clear();
}

Annotation* AnnotationList::TopAt(Gdiplus::PointF pt) const {
    for (size_t i = m_items.size(); i-- > 0;)
        if (m_items[i]->HitTest(pt)) return m_items[i].get();
    return nullptr;
}

void AnnotationList::DrawAll(Gdiplus::Graphics& g, const Annotation* skip) const {
    for (const auto& a : m_items)
        if (a.get() != skip) a->Draw(g);
}

Gdiplus::REAL HandleSize(const Annotation& a, Gdiplus::REAL base) {
    switch (a.GetKind()) {
    case Kind::Rect:
    case Kind::Arrow: {
        // A 8px outline is not grabbable by a 5px dot, so these two track the
        // stroke. The 6 floor of headroom matters: DrawChrome clears the shape's
        // rect padded by the default radius plus 3, and a marker's outer edge is
        // its half-side plus half the border — past that the previous frame's
        // marker sits outside the cleared rect and smears.
        const Gdiplus::REAL byPen = a.PenWidth() * 0.5f + 2.0f;
        Gdiplus::REAL r = byPen > base * 0.6f ? byPen : base * 0.6f;
        if (r > 6.0f) r = 6.0f;
        return r;
    }
    case Kind::Ellipse:
    case Kind::Text:
        // Neither has a stroke to match, and eight markers around a box or an
        // outline the user can already see read better small.
        return base * 0.5f;
    default:
        return base;
    }
}

void DrawSelection(Gdiplus::Graphics& g, const Annotation& a, Gdiplus::REAL base) {
    if (a.NeedsBBoxGuide()) {
        Gdiplus::Pen box(kSel, 1.0f);
        g.DrawRectangle(&box, a.BBox());
    }

    const Gdiplus::REAL r = HandleSize(a, base);
    Gdiplus::SolidBrush core(0xFFFFFFFF);
    Gdiplus::Pen ring(kSel, 1.5f);
    for (int i = 0; i < a.HandleCount(); ++i) {
        const Gdiplus::PointF c = a.HandleAt(i);
        g.FillRectangle(&core, c.X - r, c.Y - r, r * 2.0f, r * 2.0f);
        g.DrawRectangle(&ring, c.X - r, c.Y - r, r * 2.0f, r * 2.0f);
    }
}

}  // namespace annot
