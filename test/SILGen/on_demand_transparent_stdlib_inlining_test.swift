// Test that OnDemandMandatoryInlining correctly inlines @_transparent
// stdlib functions (e.g. integer arithmetic).

// RUN: %target-swift-emit-sil -parse-as-library %s > %t.normal.sil
// RUN: %target-swift-emit-sil -parse-as-library -Xllvm -sil-on-demand-emission %s > %t.ondemand.sil
// RUN: diff %t.normal.sil %t.ondemand.sil

func addOne(_ x: Int) -> Int {
  return x + 1
}

func negate(_ x: Bool) -> Bool {
  return !x
}
