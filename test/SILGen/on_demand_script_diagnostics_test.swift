// Phase 6.6: a script's top-level code is lowered on demand, so its mandatory
// diagnostics are produced as on the legacy path: definite initialization of
// its globals (a global used in a top-level defer, by a function definition,
// or captured by a closure, before its initialization), a closure that
// escapes a script global, and the missing returns of top-level code. Each
// upstream test runs under plain -verify, with its own flags, on demand.

// RUN: %target-swift-frontend -emit-sil -o /dev/null -verify \
// RUN:   -primary-file %S/../SILOptimizer/definite_init_diagnostics_globals.swift \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %target-swift-frontend -emit-sil -o /dev/null -verify \
// RUN:   %S/../SILOptimizer/return.swift -Xllvm -sil-on-demand-emission
// RUN: %target-swift-frontend -emit-sil -module-name foo -o /dev/null -verify \
// RUN:   %S/closure_script_global_escape.swift -Xllvm -sil-on-demand-emission
