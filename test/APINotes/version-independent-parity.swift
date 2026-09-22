// Differential parity harness for version-independent API notes.
//
// One API notes surface is imported twice at each language version: once the
// legacy way, where Clang applies the slice it selected, and once in
// version-independent mode, where the Clang module carries every slice and the
// importer selects. The two printed interfaces have to be identical.
//
// The diff is the assertion. That is the point: adding a declaration to
// Inputs/version-matrix extends the coverage without anyone having to predict
// or hand-write the expected output, and any divergence the importer grows
// shows up here rather than in somebody's project.
//
// Cells that do not reach parity yet live in a separate module; see
// version-independent-parity-gaps.swift.

// REQUIRES: objc_interop

// RUN: %empty-directory(%t)

// Swift 4
// RUN: %target-swift-ide-test -print-module -module-to-print=VersionMatrix -source-filename %s -I %S/Inputs/version-matrix -swift-version 4 -module-cache-path %t/mcp-legacy-4 > %t/legacy-4.txt
// RUN: %target-swift-ide-test -print-module -module-to-print=VersionMatrix -source-filename %s -I %S/Inputs/version-matrix -swift-version 4 -module-cache-path %t/mcp-capture-4 -version-independent-apinotes > %t/capture-4.txt
// RUN: %diff -u %t/legacy-4.txt %t/capture-4.txt

// Swift 5
// RUN: %target-swift-ide-test -print-module -module-to-print=VersionMatrix -source-filename %s -I %S/Inputs/version-matrix -swift-version 5 -module-cache-path %t/mcp-legacy-5 > %t/legacy-5.txt
// RUN: %target-swift-ide-test -print-module -module-to-print=VersionMatrix -source-filename %s -I %S/Inputs/version-matrix -swift-version 5 -module-cache-path %t/mcp-capture-5 -version-independent-apinotes > %t/capture-5.txt
// RUN: %diff -u %t/legacy-5.txt %t/capture-5.txt

// Swift 6
// RUN: %target-swift-ide-test -print-module -module-to-print=VersionMatrix -source-filename %s -I %S/Inputs/version-matrix -swift-version 6 -module-cache-path %t/mcp-legacy-6 > %t/legacy-6.txt
// RUN: %target-swift-ide-test -print-module -module-to-print=VersionMatrix -source-filename %s -I %S/Inputs/version-matrix -swift-version 6 -module-cache-path %t/mcp-capture-6 -version-independent-apinotes > %t/capture-6.txt
// RUN: %diff -u %t/legacy-6.txt %t/capture-6.txt

// A non-empty interface is the control. Without it the diff would also pass on
// two modules that both failed to build. These are spot checks on the Swift 4
// output, one per annotation family.
// RUN: %FileCheck %s < %t/capture-4.txt

// The 5.0 slice covers Swift 4 as well, and is the lowest that does, so it wins.
// CHECK-DAG: func nameU_v5()
// CHECK-DAG: func nameV4_fromNotes()
// A sidecar rename outranks one written in the header.
// CHECK-DAG: func nameHeader_fromNotes()
// CHECK-DAG: func __privU()
// 'SwiftPrivate: false' undoes the header's swift_private.
// CHECK-DAG: func privHeaderUndoneU()
// CHECK-DAG: func privHeaderUndoneV4()
// CHECK-DAG: func availNonswiftU()
// CHECK-DAG: struct EnumFlagV4 : OptionSet
// A tag whose only 4.0 slice sets no key keeps the unannotated shape.
// CHECK-DAG: struct EnumClosedKeyless
// CHECK-DAG: init(designatedU value: CInt)
// CHECK-DAG: class MatrixNonGenericV4 : MatrixRoot
