// Legacy emitOrDelayFunction delays an implicit declaration that can't be used
// outside the module, here a struct's implicit initializer in a whole-module
// compile, until something references it. The only reference here is from a
// default-argument generator, which ArgumentGeneratorsRequest canonicalizes
// outside the coordinator's worklist, so the body scan never sees the
// reference. The coordinator finds the forced initializer in
// pendingForcedFunctions instead (queueForcedFunctions), and the never
// referenced memberwise initializer stays unemitted, as in legacy.

// RUN: %empty-directory(%t)
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M %s \
// RUN:   -o %t/legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M %s \
// RUN:   -o %t/ondemand.sil -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: diff %t/legacy.sil %t/ondemand.sil
// RUN: %FileCheck %s --implicit-check-not='@$s1M1PV1xACSi_tcfC' \
// RUN:   < %t/ondemand.sil

// CHECK-LABEL: sil hidden @$s1M1PVACycfC :
// CHECK-LABEL: sil hidden @$s1M1fySiAA1PVFfA_ :
struct P { var x = 0 }
func f(_ p: P = P()) -> Int { return p.x }
