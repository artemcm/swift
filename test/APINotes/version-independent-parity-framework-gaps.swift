// Differential parity over the real API notes test framework, rather than over a
// purpose-built surface.
//
// version-independent-parity.swift covers a matrix written for the harness, and
// it passes. This one covers APINotesFrameworkTest, the sidecar the rest of this
// directory already tests against: 329 lines, 4 SwiftVersions blocks ordered
// 3.0, 5, 4, 4.2 on purpose to catch ordering bugs, and the only checked-in
// input with Type:, ResultType:, Nullability:, Protocols:, and Enumerators:
// keys. It is the closest thing the suite has to a realistic sidecar.
//
// It fails at every Swift version, most heavily at Swift 4. Five distinct
// classes, in rough order of severity:
//
//  1. A live name differs, not just a compatibility alias. At Swift 4 legacy
//     imports the class as `RenamedGeneric` with `OldRenamedGeneric` as the
//     alias, and version-independent mode imports it the other way around. Same
//     inversion for VeryImportantCStruct, VeryImportantCAlias,
//     NormallyUnchangedWrapper, and NormallyChangedWrapper. A client written
//     against one spelling does not compile against the other.
//
//  2. `Type:` and `ResultType:` are dropped, and the drop changes the Swift
//     name. Legacy imports `method(with a: A?) -> A`; version-independent mode
//     imports `method(withA a: Any) -> Any`. The name moves because
//     omit-needless-words reads the parameter type to decide whether "A" is
//     redundant, so a missing type carrier is not a cosmetic loss. This is the
//     "ResultType: has no carrier" gap, which also corrupts names.
//
//  3. `Nullability:` is dropped. Legacy imports
//     `acceptDoublePointer(_ ptr: UnsafeMutablePointer<CDouble>?)`;
//     version-independent mode makes the parameter non-optional.
//
//  4. Compatibility aliases are missing, across functions, initializers,
//     methods, class and instance properties, enum constants, and globals. This
//     is the alias-direction gap, and it reaches more declaration kinds here
//     than the narrow matrix does.
//
//  5. A protocol requirement's result type is dropped, so `requirement()`
//     appears only in version-independent output.
//
// Keep this file as the realistic backstop. The narrow per-class tests over
// Inputs/version-matrix are the ratchet; this one says whether the ratchet has
// reached real input yet. As classes close, the divergence shrinks, and when it
// reaches zero this starts XPASSing: drop the XFAIL at that point rather than
// deleting the file, because it stays valuable as a regression guard.

// REQUIRES: objc_interop
// XFAIL: *

// RUN: %empty-directory(%t)

// Swift 4
// RUN: %target-swift-ide-test -F %S/Inputs/custom-frameworks -print-module -module-to-print=APINotesFrameworkTest -source-filename %s -function-definitions=false -swift-version 4 -module-cache-path %t/mcp-legacy-4 > %t/legacy-4.txt
// RUN: %target-swift-ide-test -F %S/Inputs/custom-frameworks -print-module -module-to-print=APINotesFrameworkTest -source-filename %s -function-definitions=false -swift-version 4 -module-cache-path %t/mcp-capture-4 -version-independent-apinotes > %t/capture-4.txt

// Swift 4.2
// RUN: %target-swift-ide-test -F %S/Inputs/custom-frameworks -print-module -module-to-print=APINotesFrameworkTest -source-filename %s -function-definitions=false -swift-version 4.2 -module-cache-path %t/mcp-legacy-42 > %t/legacy-42.txt
// RUN: %target-swift-ide-test -F %S/Inputs/custom-frameworks -print-module -module-to-print=APINotesFrameworkTest -source-filename %s -function-definitions=false -swift-version 4.2 -module-cache-path %t/mcp-capture-42 -version-independent-apinotes > %t/capture-42.txt

// Swift 5
// RUN: %target-swift-ide-test -F %S/Inputs/custom-frameworks -print-module -module-to-print=APINotesFrameworkTest -source-filename %s -function-definitions=false -swift-version 5 -module-cache-path %t/mcp-legacy-5 > %t/legacy-5.txt
// RUN: %target-swift-ide-test -F %S/Inputs/custom-frameworks -print-module -module-to-print=APINotesFrameworkTest -source-filename %s -function-definitions=false -swift-version 5 -module-cache-path %t/mcp-capture-5 -version-independent-apinotes > %t/capture-5.txt

// Swift 6
// RUN: %target-swift-ide-test -F %S/Inputs/custom-frameworks -print-module -module-to-print=APINotesFrameworkTest -source-filename %s -function-definitions=false -swift-version 6 -module-cache-path %t/mcp-legacy-6 > %t/legacy-6.txt
// RUN: %target-swift-ide-test -F %S/Inputs/custom-frameworks -print-module -module-to-print=APINotesFrameworkTest -source-filename %s -function-definitions=false -swift-version 6 -module-cache-path %t/mcp-capture-6 -version-independent-apinotes > %t/capture-6.txt

// A non-empty interface is the control, so the comparison cannot pass on two
// modules that both failed to build.
// RUN: %FileCheck %s --check-prefix=NONEMPTY --input-file %t/capture-5.txt
// NONEMPTY: class TypeChanges

// RUN: %diff -u %t/legacy-4.txt %t/capture-4.txt
// RUN: %diff -u %t/legacy-42.txt %t/capture-42.txt
// RUN: %diff -u %t/legacy-5.txt %t/capture-5.txt
// RUN: %diff -u %t/legacy-6.txt %t/capture-6.txt
