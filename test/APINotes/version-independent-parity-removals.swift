// Differential parity for API notes removals: entries that take away an
// attribute the header wrote, rather than adding one.
//
// A removal is recorded as a `SwiftVersionedRemovalAttr` naming the attribute
// kind to suppress, so honoring it means erasing what the header wrote and
// putting nothing in its place. Getting it wrong is not a missing annotation:
// the declaration comes out Swift-private where Clang would have made it
// visible, so the name a client writes changes.

// REQUIRES: objc_interop

// RUN: %empty-directory(%t)

// Swift 4: the unversioned and the 4.0 removal both apply.
// RUN: %target-swift-ide-test -print-module -module-to-print=RemovalMatrix -source-filename %s -I %S/Inputs/removal-matrix -swift-version 4 -module-cache-path %t/mcp-legacy-4 > %t/legacy-4.txt
// RUN: %target-swift-ide-test -print-module -module-to-print=RemovalMatrix -source-filename %s -I %S/Inputs/removal-matrix -swift-version 4 -module-cache-path %t/mcp-capture-4 -version-independent-apinotes > %t/capture-4.txt
// RUN: %diff -u %t/legacy-4.txt %t/capture-4.txt

// Swift 5: the 4.0 removal is out of range, so removeV4 stays private.
// RUN: %target-swift-ide-test -print-module -module-to-print=RemovalMatrix -source-filename %s -I %S/Inputs/removal-matrix -swift-version 5 -module-cache-path %t/mcp-legacy-5 > %t/legacy-5.txt
// RUN: %target-swift-ide-test -print-module -module-to-print=RemovalMatrix -source-filename %s -I %S/Inputs/removal-matrix -swift-version 5 -module-cache-path %t/mcp-capture-5 -version-independent-apinotes > %t/capture-5.txt
// RUN: %diff -u %t/legacy-5.txt %t/capture-5.txt

// The controls. A diff alone would also pass on two modules that both failed to
// build, and on one where no removal was honored at all.
// RUN: %FileCheck %s --check-prefix=V4 < %t/capture-4.txt
// RUN: %FileCheck %s --check-prefix=V5 < %t/capture-5.txt

// An unversioned removal undoes the header's swift_private.
// V4-DAG: func removeU()
// So does a 4.0 one, at 4.0.
// V4-DAG: func removeV4()
// No entry, so the header stands and the name keeps its mangling prefix.
// V4-DAG: func __removeUntouched()
// Nothing to remove, and removing nothing must not invent an attribute.
// V4-DAG: func removeNoHeader()

// At 5.0 the 4.0 removal is out of range.
// V5-DAG: func removeU()
// V5-DAG: func __removeV4()
// V5-DAG: func __removeUntouched()
