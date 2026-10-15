#include "stdafx.h"
#include "Commands.h"

namespace annot {

int ApplyUndo(AnnotationList& list, Edit&& e) {
    switch (e.op) {
    case Edit::Op::Add:
        list.RemoveAt(e.index);
        return -1;
    case Edit::Op::Remove:
        list.InsertAt(e.index, std::move(e.item));
        return (int)e.index;
    case Edit::Op::Replace:
        list.ReplaceAt(e.index, std::move(e.item));
        return (int)e.index;
    }
    return -1;
}

}  // namespace annot
