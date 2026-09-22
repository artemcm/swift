// Scale coverage for the API notes selection cache, which two of its properties
// need and which no other test in this directory provides.
//
// The input is deliberately large and deliberately boring: a plain unversioned
// sidecar of 64 SwiftName keys, with no versioned slices at all. What matters is
// the number of *annotated* declarations, not the shape of the annotations.
//
// Two things here are load-bearing, so do not tidy them away:
//
//   * The 64 declarations. `getAPINotesSelection` hands out a reference into a
//     `llvm::DenseMap`, which invalidates outstanding references when it grows;
//     from its initial 64 buckets that happens at 48 entries. An input below
//     that threshold never grows the map and never exercises the indirection
//     that keeps the reference valid.
//   * The 6 repeated runs. The failures this guards are heap-layout dependent,
//     so a single run can pass against broken code. One RUN line would report
//     that as flakiness rather than as breakage.

// REQUIRES: objc_interop

// RUN: %empty-directory(%t)

// RUN: %target-swift-ide-test -print-module -module-to-print=SelectionCacheScale -source-filename %s -I %S/Inputs/selection-cache-scale -swift-version 4 -module-cache-path %t/mcp-legacy > %t/legacy.txt

// The control: legacy mode has to have produced the renames, or the comparisons
// below would pass on two equally empty files.
// RUN: %FileCheck %s --check-prefix=RENAMED --input-file %t/legacy.txt
// RENAMED: func renamedScaled01()
// RENAMED: func renamedScaled64()

// RUN: %target-swift-ide-test -print-module -module-to-print=SelectionCacheScale -source-filename %s -I %S/Inputs/selection-cache-scale -swift-version 4 -module-cache-path %t/mcp-1 -version-independent-apinotes > %t/capture-1.txt
// RUN: %diff %t/legacy.txt %t/capture-1.txt

// RUN: %target-swift-ide-test -print-module -module-to-print=SelectionCacheScale -source-filename %s -I %S/Inputs/selection-cache-scale -swift-version 4 -module-cache-path %t/mcp-2 -version-independent-apinotes > %t/capture-2.txt
// RUN: %diff %t/legacy.txt %t/capture-2.txt

// RUN: %target-swift-ide-test -print-module -module-to-print=SelectionCacheScale -source-filename %s -I %S/Inputs/selection-cache-scale -swift-version 4 -module-cache-path %t/mcp-3 -version-independent-apinotes > %t/capture-3.txt
// RUN: %diff %t/legacy.txt %t/capture-3.txt

// RUN: %target-swift-ide-test -print-module -module-to-print=SelectionCacheScale -source-filename %s -I %S/Inputs/selection-cache-scale -swift-version 4 -module-cache-path %t/mcp-4 -version-independent-apinotes > %t/capture-4.txt
// RUN: %diff %t/legacy.txt %t/capture-4.txt

// RUN: %target-swift-ide-test -print-module -module-to-print=SelectionCacheScale -source-filename %s -I %S/Inputs/selection-cache-scale -swift-version 4 -module-cache-path %t/mcp-5 -version-independent-apinotes > %t/capture-5.txt
// RUN: %diff %t/legacy.txt %t/capture-5.txt

// RUN: %target-swift-ide-test -print-module -module-to-print=SelectionCacheScale -source-filename %s -I %S/Inputs/selection-cache-scale -swift-version 4 -module-cache-path %t/mcp-6 -version-independent-apinotes > %t/capture-6.txt
// RUN: %diff %t/legacy.txt %t/capture-6.txt
