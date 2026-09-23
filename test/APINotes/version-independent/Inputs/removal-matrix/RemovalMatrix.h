// Removals: an API notes entry taking an attribute away that the header wrote.
//
// Each declaration carries the attribute in the header and has a sidecar entry
// that undoes it, in one of the slice arrangements selection has to tell
// apart.

void removeU(void) __attribute__((swift_private));
void removeV4(void) __attribute__((swift_private));
void removeV5(void) __attribute__((swift_private));

// The unversioned slice adds what the 4.0 slice removes, so which one wins
// decides the attribute, not just whether it came from the header.
void addUremoveV4(void);

// The reverse: the unversioned slice removes the header's attribute, and the
// 4.0 slice puts it back.
void removeUaddV4(void) __attribute__((swift_private));

// Untouched control: the header's attribute must survive.
void removeUntouched(void) __attribute__((swift_private));

// The header says nothing, so the removal has nothing to undo.
void removeNoHeader(void);
