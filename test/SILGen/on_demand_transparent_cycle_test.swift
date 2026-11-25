// Test cycle detection in OnDemandMandatoryInlining.
//
// Cycles in @_transparent inlining are detected via the request
// evaluator's activeRequests set rather than the legacy pass's
// CurrentInliningSet. CanonicalSILFunctionRequest::diagnoseCycle emits
// the primary diagnostic at the function declaration location;
// noteCycleStep emits `while inlining here` notes on the intermediate
// requests in activeRequests reverse order. This differs from the
// legacy module pass, which attaches diagnostics to call sites.
//
// DiagnoseInfiniteRecursion also legitimately reports the recursive
// cycles as infinite recursion; the warning markers below
// acknowledge that independent diagnostic.

// RUN: %target-swift-frontend -emit-sil %s -o /dev/null -verify \
// RUN:   -Xllvm -sil-on-demand-emission

// 2-function @_transparent cycle: waldo -> fred -> waldo.
@_transparent
func waldo(_ x: Double) -> Double { // expected-error {{inlining 'transparent' functions forms circular loop}}
  return fred(x) // expected-warning {{function call causes an infinite recursion}}
}

@_transparent
func fred(_ x: Double) -> Double { // expected-note {{while inlining here}}
  return waldo(x)
}

// 3-function @_transparent cycle: aaa -> bbb -> ccc -> aaa.
@_transparent
func aaa(_ x: Double) -> Double { // expected-error {{inlining 'transparent' functions forms circular loop}}
  return bbb(x) // expected-warning {{function call causes an infinite recursion}}
}

@_transparent
func bbb(_ x: Double) -> Double { // expected-note {{while inlining here}}
  return ccc(x)
}

@_transparent
func ccc(_ x: Double) -> Double { // expected-note {{while inlining here}}
  return aaa(x)
}
