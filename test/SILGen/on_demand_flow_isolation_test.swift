// The upstream flow isolation tests, run on demand. Their diagnostics are in
// the initializers and deinits of classes and actors, local actors included,
// which the coordinator emits since Phase 6.2.

// RUN: %target-swift-frontend -strict-concurrency=complete -swift-version 5 \
// RUN:   -parse-as-library -emit-sil -verify \
// RUN:   %S/../Concurrency/flow_isolation_class.swift -o /dev/null \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %target-swift-frontend -strict-concurrency=complete -swift-version 5 \
// RUN:   -parse-as-library -emit-sil -verify \
// RUN:   %S/../Concurrency/flow_isolation_basic.swift -o /dev/null \
// RUN:   -Xllvm -sil-on-demand-emission
// RUN: %target-swift-frontend -strict-concurrency=complete -swift-version 5 \
// RUN:   -parse-as-library -emit-sil -verify \
// RUN:   %S/../Concurrency/flow_isolation_actor.swift -o /dev/null \
// RUN:   -Xllvm -sil-on-demand-emission
