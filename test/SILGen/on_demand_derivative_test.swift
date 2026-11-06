// Test that the on-demand SILGen path registers the
// SILDifferentiabilityWitness for a `@derivative(of:)` declaration
// via the new SILDifferentiabilityWitnessRequest.
//
// The lit harness may rebuild _Differentiation.swiftmodule from its
// interface in a sub-compilation that inherits -sil-on-demand-emission;
// that lowering stays on the legacy path
// (on_demand_module_interface_test.swift).

// RUN: %target-swift-emit-sil -parse-as-library -Xllvm -sil-on-demand-emission %s | %FileCheck %s

// REQUIRES: differentiable_programming

import _Differentiation

// Differentiability witness, registered by SILDifferentiabilityWitnessRequest
// processing vjpOriginal's @derivative attribute. The vjp: slot is
// populated; jvp: slot is left to a later pass (Differentiation) that
// the function-only pipeline does not run, so we use {{.*}} to allow
// any contents in the witness body.
// CHECK-LABEL: sil_differentiability_witness {{.*}} [reverse] [parameters 0] [results 0] @$s25on_demand_derivative_test8originalyS2fF
// CHECK: vjp:

// The original function.
// CHECK-LABEL: sil @$s25on_demand_derivative_test8originalyS2fF :
public func original(_ x: Float) -> Float {
  return x
}

// The derivative declaration.
// CHECK-LABEL: sil @$s25on_demand_derivative_test11vjpOriginalySf5value_S2fc8pullbacktSfF :
@derivative(of: original)
public func vjpOriginal(_ x: Float)
    -> (value: Float, pullback: (Float) -> Float) {
  return (x, { v in v })
}

// VJP derivative thunk: canonicalized by CanonicalSynthesizedFunctionRequest.
// CHECK-LABEL: sil [thunk] [heuristic_always_inline] @$s25on_demand_derivative_test8originalyS2fFTJrSpSr :
