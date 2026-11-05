// The upstream infinite recursion test, run on demand: four of its
// diagnostics are in class members, which the coordinator emits since
// Phase 6.2, and its body-less @_silgen_name declaration used to abort the
// coordinator (D10).

// RUN: %target-swift-frontend -emit-sil \
// RUN:   %S/../SILOptimizer/infinite_recursion.swift -o /dev/null -verify \
// RUN:   -Xllvm -sil-on-demand-emission
