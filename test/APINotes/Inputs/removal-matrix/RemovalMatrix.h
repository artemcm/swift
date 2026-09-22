// Removals: an API notes entry taking an attribute away that the header wrote.
//
// Each declaration carries the attribute in the header and has a sidecar entry
// that undoes it, in one of the slice arrangements the selector has to tell
// apart.

void removeU(void) __attribute__((swift_private));
void removeV4(void) __attribute__((swift_private));

// Untouched control: the header's attribute must survive.
void removeUntouched(void) __attribute__((swift_private));

// The header says nothing, so the removal has nothing to undo.
void removeNoHeader(void);
