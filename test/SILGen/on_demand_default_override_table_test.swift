// Phase 6.2: under CoroutineAccessors, an open class of a resilient module
// gets a default override table, with a shim from each yield_once_2 accessor
// to its yield_once original. On demand, the seeder emits the table after the
// vtable, as legacy does, and canonicalizes the shim.

// REQUIRES: swift_feature_CoroutineAccessors
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M %s \
// RUN:   -enable-library-evolution \
// RUN:   -enable-experimental-feature CoroutineAccessors -o %t.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M %s \
// RUN:   -enable-library-evolution \
// RUN:   -enable-experimental-feature CoroutineAccessors -o %t.ondemand.sil \
// RUN:   -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: diff %t.legacy.sil %t.ondemand.sil
// RUN: %FileCheck %s < %t.ondemand.sil

// CHECK-LABEL: sil_default_override_table C {
// CHECK:   #C.x!yielding_mutate: #C.x!modify: {{.*}} : @$s1M1CC1xSaySiGvxTwd

open class C {
  open var x: [Int] = []
  public init() {}
}
