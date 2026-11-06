// The upstream definite initialization test, run on demand. Phase 6.2 emits
// its classes, and Phase 6.3 its protocol extensions. What it still misses
// is in top-level code (global variables and entry points), which the gap
// check allows. Once those land, the check fails with "no gaps left": then
// run this test under plain -verify.

// RUN: not %target-swift-emit-sil -enable-copy-propagation=requested-passes-only \
// RUN:   -primary-file %S/../SILOptimizer/definite_init_diagnostics.swift \
// RUN:   -o /dev/null -verify -Xllvm -sil-on-demand-emission 2> %t.err
// RUN: %{python} %S/Inputs/verify_gap_check.py \
// RUN:   %S/../SILOptimizer/definite_init_diagnostics.swift %t.err \
// RUN:   --allow top-level
