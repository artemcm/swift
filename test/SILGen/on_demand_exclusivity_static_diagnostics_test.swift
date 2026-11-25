// The upstream exclusivity diagnostics test, run on demand. Sixteen of its
// diagnostics are in members of structs and of one class; the on-demand
// coordinator emits those members since Phase 6.1. The verifier checks every
// expected diagnostic, including those of the top-level functions.

// RUN: %target-swift-frontend -enforce-exclusivity=checked -swift-version 4 \
// RUN:   -emit-sil -primary-file %S/../SILOptimizer/exclusivity_static_diagnostics.swift \
// RUN:   -o /dev/null -verify -Xllvm -sil-on-demand-emission
