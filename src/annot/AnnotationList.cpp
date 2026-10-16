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

void DrawSelection(Gdiplus::Graphics& g, const Annotation& a, Gdiplus::REAL r) {
    if (a.NeedsBBoxGuide()) {
        Gdiplus::Pen box(kSel, 1.0f);
        g.DrawRectangle(&box, a.BBox());
    }

    Gdiplus::SolidBrush core(0xFFFFFFFF);
    Gdiplus::Pen ring(kSel, 1.5f);
    for (int i = 0; i < a.HandleCount(); ++i) {
        const Gdiplus::PointF c = a.HandleAt(i);
        g.FillEllipse(&core, c.X - r, c.Y - r, r * 2.0f, r * 2.0f);
        g.DrawEllipse(&ring, c.X - r, c.Y - r, r * 2.0f, r * 2.0f);
    }
}

}  // namespace annot
