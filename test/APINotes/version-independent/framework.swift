// Differential parity over APINotesFrameworkTest, the realistic sidecar the rest
// of test/APINotes tests against: several SwiftVersions blocks deliberately out
// of order, and the only checked-in input with Type:, ResultType: and
// Nullability: keys. See lit.local.cfg for the harness.
//
// Type:, ResultType: and Nullability: rewrite a declaration's type rather than
// attach an attribute, and the version-independent collapse does not cover
// them yet. The declarations they touch still diverge, and the name can too,
// because omit-needless-words reads parameter types. That divergence is checked
// in, so anything else diverging fails this test, and so does closing the gap.

// REQUIRES: objc_interop

// REDEFINE: %{vi-module} = APINotesFrameworkTest
// REDEFINE: %{vi-map} = %S/../Inputs/custom-frameworks/APINotesFrameworkTest.framework/Modules/module.modulemap
// REDEFINE: %{vi-build-flags} = -F %S/../Inputs/custom-frameworks
// REDEFINE: %{vi-expected} = %S/Inputs/known-divergence/framework.txt

// RUN: %empty-directory(%t)
// RUN: %{vi-parity}

// A non-empty interface is the control, so the comparison cannot pass on two
// modules that both failed to build.
// RUN: %FileCheck %s --check-prefix=NONEMPTY --input-file %t/capture-4-at-5.txt
// NONEMPTY: class TypeChanges
