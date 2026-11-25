// A body can emit functions that nothing references: a local function that
// is never called, and its default argument generator. The body scan finds
// only the functions a function_ref names, so the coordinator sweeps the
// module for definitions from the files being emitted that haven't been
// canonicalized. Before the sweep, their raw bodies reached the verifier on
// demand ("access must have known enforcement outside raw stage").

// RUN: %empty-directory(%t)
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M %s \
// RUN:   -o %t/legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M %s \
// RUN:   -o %t/ondemand.sil -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: diff %t/legacy.sil %t/ondemand.sil
// RUN: %FileCheck %s < %t/ondemand.sil

func outer(_ x: Int) -> Int {
  // CHECK-LABEL: sil private [closure] @$s1M5outeryS2iF10unusedSwapL_yyxz_xztlF :
  // CHECK: begin_access [modify] [static]
  func unusedSwap<T>(_ a: inout T, _ b: inout T) { swap(&a, &b) }

  // The generator's raw body calls Int(_builtinIntegerLiteral:); once
  // canonical, the call is inlined.
  // CHECK-LABEL: sil private @$s1M5outeryS2iF17unusedWithDefaultL_yS2iFfA_ :
  // CHECK-NOT: function_ref
  // CHECK: } // end sil function '$s1M5outeryS2iF17unusedWithDefaultL_yS2iFfA_'
  func unusedWithDefault(_ y: Int = 3) -> Int { var z = y; z += 1; return z }
  return x
}

struct Holder {
  var value = 0
  mutating func method() {
    // CHECK-LABEL: sil private [closure] @$s1M6HolderV6methodyyF12unusedMemberL_yyACzF :
    // CHECK: begin_access [modify] [static]
    func unusedMember(_ h: inout Holder) { h.value += 1 }
  }
}
