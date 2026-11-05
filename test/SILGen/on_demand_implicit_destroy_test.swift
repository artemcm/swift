// ImplicitDestroyChecker on demand: the function-only pipeline mirrors it
// right after MoveOnlyChecker, as addMandatoryDiagnosticOptPipeline does (D4).
// Each RUN line checks the same expectations.

// RUN: %target-swift-frontend -emit-sil -verify %s -o /dev/null \
// RUN:   -enable-experimental-feature NondeinitableTypes
// RUN: %target-swift-frontend -emit-sil -verify %s -o /dev/null \
// RUN:   -enable-experimental-feature NondeinitableTypes \
// RUN:   -Xllvm -sil-on-demand-emission

// REQUIRES: swift_feature_NondeinitableTypes

// No stored `var`: its synthesized setter is a member that the on-demand path
// doesn't emit yet, and the setter has a diagnostic of its own.
struct ND: ~Copyable, ~Deinitable {
  let x: Int
  consuming func finish() { discard self }
}

func make() -> ND { ND(x: 0) }
func mayThrow() throws {}
func transfer(_ nd: consuming ND) -> ND { nd }

func neverConsumed() {
  let nd = make() // expected-error {{'nd' is not consumed on all paths}}
  _ = nd.x
} // expected-note {{path exits here without a consume}}

func consumedOnOneBranch(_ b: Bool) {
  let nd = make() // expected-error {{'nd' is not consumed on all paths}}
  if b { nd.finish() } // expected-note {{path exits here without a consume}}
}

func varOverwrite() {
  var nd = make() // expected-error {{'nd' is not consumed on all paths}}
  nd = make() // expected-note {{path exits here without a consume}}
  nd.finish()
}

func inoutOverwrite(_ nd: inout ND) { // expected-error {{'nd' is not consumed on all paths}}
  nd = make() // expected-note {{path exits here without a consume}}
}

func throwingPath() throws {
  let nd = make() // expected-error {{'nd' is not consumed on all paths}}
  try mayThrow() // expected-note {{path exits here without a consume}}
  nd.finish()
}

func genericParameter<T: ~Copyable & ~Deinitable>(_ t: consuming T) {} // expected-error {{'t' is not consumed on all paths}}
// expected-note@-1 {{path exits here without a consume}}

func capturedByLocalFunction() {
  let nd = make() // expected-error {{'nd' is not consumed on all paths}}
  func local() { _ = nd.x }
  local()
} // expected-note {{path exits here without a consume}}

// Accepted.

func finishes() { make().finish() }

func consumedOnEveryBranch(_ b: Bool) {
  let nd = make()
  if b { nd.finish() } else { transfer(nd).finish() }
}

func reinitialized() {
  var nd = make()
  nd.finish()
  nd = make()
  nd.finish()
}

func trapsOnOneBranch(_ b: Bool) {
  let nd = make()
  if b { fatalError() }
  nd.finish()
}

func loop(_ n: Int) {
  for _ in 0..<n {
    let nd = make()
    nd.finish()
  }
}
