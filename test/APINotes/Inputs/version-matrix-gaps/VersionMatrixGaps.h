// The cells where version-independent import does not yet match the legacy
// path. Kept apart from VersionMatrix.h so the parity harness can stay green
// while this one is expected to fail; see version-independent-parity-gaps.swift.

void gapKeyless(void);
void gapHeaderV4(void) __attribute__((swift_name("gapHeaderV4_fromHeader()")));
