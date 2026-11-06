// On demand, DiagnosedSILFunctionRequest runs the function-only pipeline over
// a closure component in one scoped run, SILPassManager::executeScoped. Each
// span of function passes runs over the component's functions in an order,
// and legacy's runFunctionPasses runs a span over the module callees first.
// Passes read other functions' bodies and depend on that order:
//
// - FlowIsolation analyzes the defer body that an initializer calls, and needs
//   NoReturnFolding to have run on it, so that the path of a defer that ends
//   in fatalError doesn't carry nonisolation out (Defer.swift).
// - SendNonSendable and the move-only checker read the body of a closure that
//   a function passes to a call, before the span rewrites it
//   (PassedSending.swift and PassedConsume.swift).
//
// Legacy's order comes from BottomUpFunctionOrder: Tarjan's strongly connected
// components algorithm over the targets of full applies, which CalleeCache
// resolves to a function_ref. A component runs after the components it calls,
// and the functions of a component in the order that they pop off the stack.
// The walk starts from each function in turn, in the order of the module's
// function list, which is the order that SILGen created the functions in.
// That order decides between functions that no call connects. A closure that a
// function only passes, or that a let binding holds, is not its callee, and
// runs after it.
//
// The order checks pin that rule on both paths: siblings, a closure applied in
// place or held by a let, a cycle of three, a cycle through the root, closures
// that nest, and local functions that are declared in a different order than
// they are used. Each also pins the order in which the closure group passes
// are given a component's members, which legacy's ClosureGroupSchedule lists
// bottom-up.

// REQUIRES: concurrency
// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// RUN: %target-swift-frontend -strict-concurrency=complete -swift-version 5 \
// RUN:   -parse-as-library -emit-sil -verify %t/Defer.swift -o /dev/null
// RUN: %target-swift-frontend -strict-concurrency=complete -swift-version 5 \
// RUN:   -parse-as-library -emit-sil -verify %t/Defer.swift -o /dev/null \
// RUN:   -Xllvm -sil-on-demand-emission

// RUN: %target-swift-frontend -strict-concurrency=complete -swift-version 5 \
// RUN:   -parse-as-library -emit-sil -verify %t/PassedSending.swift \
// RUN:   -o /dev/null
// RUN: %target-swift-frontend -strict-concurrency=complete -swift-version 5 \
// RUN:   -parse-as-library -emit-sil -verify %t/PassedSending.swift \
// RUN:   -o /dev/null -Xllvm -sil-on-demand-emission

// RUN: %target-swift-frontend -emit-sil -sil-verify-all -verify \
// RUN:   %t/PassedConsume.swift -o /dev/null
// RUN: %target-swift-frontend -emit-sil -sil-verify-all -verify \
// RUN:   %t/PassedConsume.swift -o /dev/null -Xllvm -sil-on-demand-emission

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Siblings.swift -o /dev/null -Xllvm -sil-print-pass-name \
// RUN:   -Xllvm -sil-print-closure-groups > %t/siblings.legacy 2>&1
// RUN: %FileCheck --check-prefix=SIBLINGS %s < %t/siblings.legacy \
// RUN:   && %FileCheck --check-prefix=GROUPSIBLINGS %s < %t/siblings.legacy
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Siblings.swift -o /dev/null -Xllvm -sil-print-pass-name \
// RUN:   -Xllvm -sil-print-closure-groups -Xllvm -sil-on-demand-emission \
// RUN:   > %t/siblings.ondemand 2>&1
// RUN: %FileCheck --check-prefix=SIBLINGS %s < %t/siblings.ondemand \
// RUN:   && %FileCheck --check-prefix=GROUPSIBLINGS %s < %t/siblings.ondemand

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Shapes.swift -o /dev/null -Xllvm -sil-print-pass-name \
// RUN:   -Xllvm -sil-print-closure-groups > %t/shapes.legacy 2>&1
// RUN: %FileCheck --check-prefix=SHAPES %s < %t/shapes.legacy \
// RUN:   && %FileCheck --check-prefix=GROUPSHAPES %s < %t/shapes.legacy
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Shapes.swift -o /dev/null -Xllvm -sil-print-pass-name \
// RUN:   -Xllvm -sil-print-closure-groups -Xllvm -sil-on-demand-emission \
// RUN:   > %t/shapes.ondemand 2>&1
// RUN: %FileCheck --check-prefix=SHAPES %s < %t/shapes.ondemand \
// RUN:   && %FileCheck --check-prefix=GROUPSHAPES %s < %t/shapes.ondemand

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Cycle.swift -o /dev/null -Xllvm -sil-print-pass-name \
// RUN:   -Xllvm -sil-print-closure-groups > %t/cycle.legacy 2>&1
// RUN: %FileCheck --check-prefix=CYCLE %s < %t/cycle.legacy \
// RUN:   && %FileCheck --check-prefix=GROUPCYCLE %s < %t/cycle.legacy
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Cycle.swift -o /dev/null -Xllvm -sil-print-pass-name \
// RUN:   -Xllvm -sil-print-closure-groups -Xllvm -sil-on-demand-emission \
// RUN:   > %t/cycle.ondemand 2>&1
// RUN: %FileCheck --check-prefix=CYCLE %s < %t/cycle.ondemand \
// RUN:   && %FileCheck --check-prefix=GROUPCYCLE %s < %t/cycle.ondemand

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/RootCycle.swift -o /dev/null -Xllvm -sil-print-pass-name \
// RUN:   -Xllvm -sil-print-closure-groups > %t/rootcycle.legacy 2>&1
// RUN: %FileCheck --check-prefix=ROOTCYCLE %s < %t/rootcycle.legacy \
// RUN:   && %FileCheck --check-prefix=GROUPROOTCYCLE %s < %t/rootcycle.legacy
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/RootCycle.swift -o /dev/null -Xllvm -sil-print-pass-name \
// RUN:   -Xllvm -sil-print-closure-groups -Xllvm -sil-on-demand-emission \
// RUN:   > %t/rootcycle.ondemand 2>&1
// RUN: %FileCheck --check-prefix=ROOTCYCLE %s < %t/rootcycle.ondemand \
// RUN:   && %FileCheck --check-prefix=GROUPROOTCYCLE %s < %t/rootcycle.ondemand

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Roots.swift -o /dev/null -Xllvm -sil-print-pass-name \
// RUN:   -Xllvm -sil-print-closure-groups > %t/roots.legacy 2>&1
// RUN: %FileCheck --check-prefix=ROOTS %s < %t/roots.legacy \
// RUN:   && %FileCheck --check-prefix=GROUPROOTS %s < %t/roots.legacy
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Roots.swift -o /dev/null -Xllvm -sil-print-pass-name \
// RUN:   -Xllvm -sil-print-closure-groups -Xllvm -sil-on-demand-emission \
// RUN:   > %t/roots.ondemand 2>&1
// RUN: %FileCheck --check-prefix=ROOTS %s < %t/roots.ondemand \
// RUN:   && %FileCheck --check-prefix=GROUPROOTS %s < %t/roots.ondemand

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Declared.swift -o /dev/null -Xllvm -sil-print-pass-name \
// RUN:   -Xllvm -sil-print-closure-groups > %t/declared.legacy 2>&1
// RUN: %FileCheck --check-prefix=DECLARED %s < %t/declared.legacy \
// RUN:   && %FileCheck --check-prefix=GROUPDECLARED %s < %t/declared.legacy
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Declared.swift -o /dev/null -Xllvm -sil-print-pass-name \
// RUN:   -Xllvm -sil-print-closure-groups -Xllvm -sil-on-demand-emission \
// RUN:   > %t/declared.ondemand 2>&1
// RUN: %FileCheck --check-prefix=DECLARED %s < %t/declared.ondemand \
// RUN:   && %FileCheck --check-prefix=GROUPDECLARED %s < %t/declared.ondemand

// RUN: %target-swift-frontend -strict-concurrency=complete -swift-version 5 \
// RUN:   -parse-as-library -emit-sil -module-name M %t/PassedSending.swift \
// RUN:   -o /dev/null -Xllvm -sil-print-pass-name 2>&1 \
// RUN:   | %FileCheck --check-prefix=SENDING %s
// RUN: %target-swift-frontend -strict-concurrency=complete -swift-version 5 \
// RUN:   -parse-as-library -emit-sil -module-name M %t/PassedSending.swift \
// RUN:   -o /dev/null -Xllvm -sil-print-pass-name \
// RUN:   -Xllvm -sil-on-demand-emission 2>&1 \
// RUN:   | %FileCheck --check-prefix=SENDING %s

//--- Defer.swift

func randomBool() -> Bool { return false }

actor Bob {
  var x: Int
  nonisolated func speak() {}

  init(spice doesNotFlow: Int) {
    if true {
      defer {
        if randomBool() {
          speak()
          fatalError("oops")
        }
      }
      self.x = 0
    }
    self.x = 20
  }
}

//--- PassedSending.swift

// The two closures are passed to a call, so legacy runs SendNonSendable on
// their parent first. It finds each capture's use inside the closure, where
// the diagnostic belongs. That use is an ignored_use, which a later pass of
// the same span erases from a closure that has already been through the span.

class NonSendableKlass {}

func closureTests() async {
  func sendingClosure(_ x: sending () -> ()) {}

  func testLetOneNSVariableError() async {
    let x = NonSendableKlass()
    sendingClosure { _ = x } // expected-warning {{closure passed as an argument to a 'sending' parameter captures 'x' which is accessed later by code in the current isolation context}}
    sendingClosure { _ = x } // expected-note {{access can happen concurrently}}
  }
}

// SENDING: SendNonSendable (send-non-sendable), Function: $s1M12closureTestsyyYaF14sendingClosureL_{{.*}}
// SENDING: SendNonSendable (send-non-sendable), Function: $s1M12closureTestsyyYaF25testLetOneNSVariableErrorL_yyYaF{{$}}
// SENDING: SendNonSendable (send-non-sendable), Function: $s1M12closureTestsyyYaF25testLetOneNSVariableErrorL_yyYaFyyXEfU_{{$}}
// SENDING: SendNonSendable (send-non-sendable), Function: $s1M12closureTestsyyYaF25testLetOneNSVariableErrorL_yyYaFyyXEfU0_{{$}}

//--- PassedConsume.swift

// The closure is passed to useNonEscaping. The move-only checker marks a
// function that it diagnosed, and skips a value that a partial_apply passes
// to a marked closure. Checked first, the closure would hide the parent's
// error on x.

public class Klass {}

public struct NonTrivialStruct {
  var k = Klass()
}

func consume(_: consuming NonTrivialStruct) {}

func testLoadableConsumingNonEscapingClosure2(_ x: consuming NonTrivialStruct) {
    // expected-error @-1 {{'x' used after consume}}
    // expected-error @-2 {{}}
    consume(x) // expected-note {{consumed here}}
    func useNonEscaping(_ f: () -> ()) {}
    useNonEscaping { // expected-note {{used here}}
        consume(x) // expected-note {{consumed here}}
    }
}

//--- Siblings.swift

// Legacy runs a function's callees in instruction order.

func parent() -> Int {
  func first() -> Int { return 1 }
  func second() -> Int { return 2 }
  return first() + second()
}

// GROUPSIBLINGS: Closure group for access-enforcement-selection: $s1M6parentSiyF5firstL_SiyF $s1M6parentSiyF6secondL_SiyF $s1M6parentSiyF{{$}}

// SIBLINGS: NoReturnFolding (noreturn-folding), Function: $s1M6parentSiyF5firstL_SiyF{{$}}
// SIBLINGS: NoReturnFolding (noreturn-folding), Function: $s1M6parentSiyF6secondL_SiyF{{$}}
// SIBLINGS: NoReturnFolding (noreturn-folding), Function: $s1M6parentSiyF{{$}}

//--- Shapes.swift

// immediate is a callee of shapes, so it runs first. bound is held by a let
// binding, which getCalleeOrigin doesn't look through, so it runs after
// shapes. even and odd call each other, so they are one component, which runs
// in the order that its functions pop off Tarjan's stack: odd, then even.

func shapes() -> Int {
  let immediate = { () -> Int in 1 }()
  let bound = { () -> Int in 2 }
  func even(_ n: Int) -> Bool { return n == 0 ? true : odd(n - 1) }
  func odd(_ n: Int) -> Bool { return n == 0 ? false : even(n - 1) }
  return immediate + bound() + (even(4) ? 1 : 0)
}

// GROUPSHAPES: Closure group for access-enforcement-selection: $s1M6shapesSiyFSiyXEfU_ $s1M6shapesSiyF3oddL_ySbSiF $s1M6shapesSiyF4evenL_ySbSiF $s1M6shapesSiyF $s1M6shapesSiyFSiycfU0_{{$}}

// SHAPES: NoReturnFolding (noreturn-folding), Function: $s1M6shapesSiyFSiyXEfU_{{$}}
// SHAPES: NoReturnFolding (noreturn-folding), Function: $s1M6shapesSiyF3oddL_ySbSiF{{$}}
// SHAPES: NoReturnFolding (noreturn-folding), Function: $s1M6shapesSiyF4evenL_ySbSiF{{$}}
// SHAPES: NoReturnFolding (noreturn-folding), Function: $s1M6shapesSiyF{{$}}
// SHAPES: NoReturnFolding (noreturn-folding), Function: $s1M6shapesSiyFSiycfU0_{{$}}

//--- Cycle.swift

// a calls b and c, which both call a. Legacy lists the members of the cycle as
// it pops them off its DFS stack, after the callees of the first function that
// it visited: c, b, a.

func scc() -> Int {
  func a(_ n: Int) -> Int { return n == 0 ? 0 : b(n - 1) + c(n - 1) }
  func b(_ n: Int) -> Int { return a(n) }
  func c(_ n: Int) -> Int { return a(n) }
  return a(3)
}

// GROUPCYCLE: Closure group for access-enforcement-selection: $s1M3sccSiyF1cL_yS2iF $s1M3sccSiyF1bL_yS2iF $s1M3sccSiyF1aL_yS2iF $s1M3sccSiyF{{$}}

// CYCLE: NoReturnFolding (noreturn-folding), Function: $s1M3sccSiyF1cL_yS2iF{{$}}
// CYCLE: NoReturnFolding (noreturn-folding), Function: $s1M3sccSiyF1bL_yS2iF{{$}}
// CYCLE: NoReturnFolding (noreturn-folding), Function: $s1M3sccSiyF1aL_yS2iF{{$}}
// CYCLE: NoReturnFolding (noreturn-folding), Function: $s1M3sccSiyF{{$}}

//--- RootCycle.swift

// helper calls the root, so the root and helper form a cycle, and other, which
// the root calls after helper, is a component of its own that finishes first.

func walk(_ n: Int) -> Int {
  func helper() -> Int { return walk(0) }
  func other() -> Int { return 1 }
  return n == 0 ? 0 : helper() + other()
}

// GROUPROOTCYCLE: Closure group for access-enforcement-selection: $s1M4walkyS2iF5otherL_SiyF $s1M4walkyS2iF6helperL_SiyF $s1M4walkyS2iF{{$}}

// ROOTCYCLE: NoReturnFolding (noreturn-folding), Function: $s1M4walkyS2iF5otherL_SiyF{{$}}
// ROOTCYCLE: NoReturnFolding (noreturn-folding), Function: $s1M4walkyS2iF6helperL_SiyF{{$}}
// ROOTCYCLE: NoReturnFolding (noreturn-folding), Function: $s1M4walkyS2iF{{$}}

//--- Roots.swift

// Nothing calls these closures: roots passes two of them to use, and the first
// passes the third. Legacy runs functions that no call connects in the order
// that SILGen created them, a nested closure before the next sibling.

func use(_ f: () -> ()) {}

func roots() {
  use { use { } }
  use { }
}

// GROUPROOTS: Closure group for access-enforcement-selection: $s1M5rootsyyF $s1M5rootsyyFyyXEfU_ $s1M5rootsyyFyyXEfU_yyXEfU_ $s1M5rootsyyFyyXEfU0_{{$}}

// ROOTS: NoReturnFolding (noreturn-folding), Function: $s1M5rootsyyF{{$}}
// ROOTS: NoReturnFolding (noreturn-folding), Function: $s1M5rootsyyFyyXEfU_{{$}}
// ROOTS: NoReturnFolding (noreturn-folding), Function: $s1M5rootsyyFyyXEfU_yyXEfU_{{$}}
// ROOTS: NoReturnFolding (noreturn-folding), Function: $s1M5rootsyyFyyXEfU0_{{$}}

//--- Declared.swift

// SILGen creates a local function where it is declared, and a closure where
// the expression is, so legacy runs x before y although the calls are in the
// other order, and p before the closure that passes it, although the closure
// is the first to refer to p. No call connects any of them.

func use(_ f: () -> ()) {}

func order() {
  func x() {}
  func y() {}
  use(y)
  use(x)
}

func later() {
  func p() {}
  use { use(p) }
  func q() {}
  use(q)
  use { }
}

// GROUPDECLARED: Closure group for access-enforcement-selection: $s1M5orderyyF $s1M5orderyyF1xL_yyF $s1M5orderyyF1yL_yyF{{$}}
// GROUPDECLARED: Closure group for access-enforcement-selection: $s1M5lateryyF $s1M5lateryyF1pL_yyF $s1M5lateryyFyyXEfU_ $s1M5lateryyF1qL_yyF $s1M5lateryyFyyXEfU0_{{$}}

// DECLARED: NoReturnFolding (noreturn-folding), Function: $s1M5orderyyF{{$}}
// DECLARED: NoReturnFolding (noreturn-folding), Function: $s1M5orderyyF1xL_yyF{{$}}
// DECLARED: NoReturnFolding (noreturn-folding), Function: $s1M5orderyyF1yL_yyF{{$}}
// DECLARED: NoReturnFolding (noreturn-folding), Function: $s1M5lateryyF{{$}}
// DECLARED: NoReturnFolding (noreturn-folding), Function: $s1M5lateryyF1pL_yyF{{$}}
// DECLARED: NoReturnFolding (noreturn-folding), Function: $s1M5lateryyFyyXEfU_{{$}}
// DECLARED: NoReturnFolding (noreturn-folding), Function: $s1M5lateryyF1qL_yyF{{$}}
// DECLARED: NoReturnFolding (noreturn-folding), Function: $s1M5lateryyFyyXEfU0_{{$}}
