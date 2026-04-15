// Verify that OnDemandMandatoryInlining correctly inlines a
// @_transparent function which itself references a non-transparent
// cross-module function. The inlined body's reference to the non-
// transparent callee must be present in the client's SILModule as an
// external declaration. This exercises the replacement of the
// MandatorySILLinker module pass with on-demand deserialization
// (`loadFunction` + explicit `linkFunction(LinkNormal)`).

// RUN: %empty-directory(%t)

// Build the library module.
// RUN: %target-swift-frontend -emit-module -parse-as-library \
// RUN:   -module-name NonTransparentCalleeLib \
// RUN:   -o %t/NonTransparentCalleeLib.swiftmodule \
// RUN:   -emit-module-path %t/NonTransparentCalleeLib.swiftmodule \
// RUN:   %S/Inputs/on_demand_transparent_nontransparent_callee_lib.swift

// Compile the client with both paths and diff.
// RUN: %target-swift-emit-sil -parse-as-library -I %t %s > %t/normal.sil
// RUN: %target-swift-emit-sil -parse-as-library -I %t \
// RUN:   -Xllvm -sil-on-demand-emission %s > %t/ondemand.sil
// RUN: diff %t/normal.sil %t/ondemand.sil

// Additional FileCheck verification: the transparent function is
// inlined (no `apply` to it in `useOuter`'s body) and its non-
// transparent callee is pulled in as an external declaration.
// RUN: %FileCheck %s < %t/ondemand.sil

import NonTransparentCalleeLib

// CHECK-LABEL: sil hidden @{{.*}}useOuter
// CHECK-NOT: transparentOuter
// CHECK: function_ref @$s23NonTransparentCalleeLib03nonB5InneryS2iF
// CHECK-NEXT: apply
// CHECK: return
// CHECK: end sil function {{.*}}useOuter
func useOuter(_ x: Int) -> Int {
  return transparentOuter(x)
}

// The non-transparent callee is present as a declaration with no body.
// CHECK: sil @$s23NonTransparentCalleeLib03nonB5InneryS2iF{{[^{]*$}}
