// Test that the on-demand SILGen path matches the legacy path for
// @c (non-Underscored) functions. These have hasOnlyCEntryPoint() ==
// true: the body's SILDeclRef is the foreign entry directly, with
// no separate Swift entry. Tests that the seed loop pushes the right
// SILDeclRef.
//
// Legacy emitFunction uses SILDeclRef(decl, fd->hasOnlyCEntryPoint()),
// while the current on-demand seed uses SILDeclRef(fd) (foreign=false),
// which would emit a Swift entry that should not exist.

// RUN: %target-swift-emit-sil -parse-as-library %s > %t.normal.sil
// RUN: %target-swift-emit-sil -parse-as-library -Xllvm -sil-on-demand-emission %s > %t.ondemand.sil
// RUN: diff %t.normal.sil %t.ondemand.sil

// RUN: %target-swift-emit-sil -parse-as-library %s | %FileCheck %s

// The single foreign entry for the @c function (no Swift entry at all).
// CHECK-LABEL: sil hidden [asmname "grapefruit"] @$s16on_demand_c_test6orangeyS2iFTo
// CHECK-NOT: sil hidden @$s16on_demand_c_test6orangeyS2iF :
@c(grapefruit)
func orange(_ x: Int) -> Int {
  return x
}

// A peer Swift function using the @c function as a C function pointer.
// CHECK-LABEL: sil hidden @$s16on_demand_c_test12useFromSwiftyS2iF
func useFromSwift(_ x: Int) -> Int {
  return orange(x)
}
