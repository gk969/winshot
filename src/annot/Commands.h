#pragma once

#include "AnnotationList.h"

namespace annot {

// Undo is a stack of inverse edits over the list, not list snapshots — a
// mosaic stroke list would make every snapshot enormous.
struct Edit {
    enum class Op { Add, Remove, Replace };
    Op op = Op::Add;
    size_t index = 0;
    // Remove and Replace carry the annotation the list held before the edit.
    std::unique_ptr<Annotation> item;
};

using UndoStack = std::vector<Edit>;

// Reverses e. Returns the index the restored annotation ends up at, or -1 when
// the undo took it out of the list.
int ApplyUndo(AnnotationList& list, Edit&& e);

}  // namespace annot
