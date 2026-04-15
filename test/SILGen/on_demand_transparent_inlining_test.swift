// Test that OnDemandMandatoryInlining correctly inlines @_transparent
// functions from a separately-compiled module.

// RUN: %empty-directory(%t)

// Build the library module containing a @_transparent function.
// RUN: %target-swift-frontend -emit-module -parse-as-library \
// RUN:   -module-name TransparentLib -o %t/TransparentLib.swiftmodule \
// RUN:   -emit-module-path %t/TransparentLib.swiftmodule \
// RUN:   %S/Inputs/on_demand_transparent_lib.swift

// Compile the client with both paths and diff.
// RUN: %target-swift-emit-sil -parse-as-library -I %t %s > %t/normal.sil
// RUN: %target-swift-emit-sil -parse-as-library -I %t -Xllvm -sil-on-demand-emission %s > %t/ondemand.sil
// RUN: diff %t/normal.sil %t/ondemand.sil

import TransparentLib

// CHECK-LABEL: sil hidden @$s34on_demand_transparent_inlining_test9useDoubleySiSiF
// The @_transparent function body should be inlined.
func useDouble(_ x: Int) -> Int {
  return transparentDouble(x)
}
