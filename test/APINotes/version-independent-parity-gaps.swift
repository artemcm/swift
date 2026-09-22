// The cells where version-independent API notes import does not yet match the
// legacy path. Companion to version-independent-parity.swift, which must stay
// green; this one is expected to fail until the gaps close.
//
// When a fix lands, this test starts XPASSing. That is the signal to move the
// declarations it covers into Inputs/version-matrix and shrink this file. When
// it is empty, delete it.
//
// Known divergence, at -swift-version 4:
//
//   * A key-less versioned slice. The *live* name agrees between the two paths
//     (the slice marker makes the selection correct), but the compatibility
//     alias does not: legacy offers `@available(swift, introduced: 4.2,
//     renamed:)` where version-independent mode offers an `obsoleted: 3` alias
//     pointing the other way.
//
//   * A header-written `swift_name` plus a versioned rename. Legacy synthesizes
//     an alias for the header spelling; version-independent mode does not.
//
// Both come from the same root cause. `checkVersionedSwiftName` steers on
// `IsReplacedByActive`, and `ProcessVersionedAPINotes` forces that flag false
// for every slice in version-independent mode, so the `ResetToActive` and
// `UseAsFallback` arms never run. Fixing it means either recording the
// superseded-by-active relationship in the payload, or reconstructing it on the
// client from the selected slice.

// REQUIRES: objc_interop
// XFAIL: *

// RUN: %empty-directory(%t)

// RUN: %target-swift-ide-test -print-module -module-to-print=VersionMatrixGaps -source-filename %s -I %S/Inputs/version-matrix-gaps -swift-version 4 -module-cache-path %t/mcp-legacy-4 > %t/legacy-4.txt
// RUN: %target-swift-ide-test -print-module -module-to-print=VersionMatrixGaps -source-filename %s -I %S/Inputs/version-matrix-gaps -swift-version 4 -module-cache-path %t/mcp-capture-4 -version-independent-apinotes > %t/capture-4.txt
// RUN: %diff -u %t/legacy-4.txt %t/capture-4.txt
