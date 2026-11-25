// The upstream definite initialization test, run on demand, under plain
// -verify, as legacy runs it. Phase 6.2 emits its classes, Phase 6.3 its
// protocol extensions, and Phase 6.6 its globals and top-level code: no
// diagnostic is missing or extra on demand. Until Phase 6.6 a gap check
// (Inputs/verify_gap_check.py) allowed the top-level ones.

// RUN: %target-swift-emit-sil -enable-copy-propagation=requested-passes-only \
// RUN:   -primary-file %S/../SILOptimizer/definite_init_diagnostics.swift \
// RUN:   -o /dev/null -verify -Xllvm -sil-on-demand-emission
