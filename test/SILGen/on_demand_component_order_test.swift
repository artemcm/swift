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
// Legacy's callees are the targets of full applies, explored in instruction
// order. A closure that a function only passes, or that a let binding holds,
// is not its callee, and runs after it. The order checks pin that rule on both
// paths: siblings, a closure applied in place, a closure that a let holds,
// and recursion between local functions.

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
// RUN:   %t/Siblings.swift -o /dev/null -Xllvm -sil-print-pass-name 2>&1 \
// RUN:   | %FileCheck --check-prefix=SIBLINGS %s
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Siblings.swift -o /dev/null -Xllvm -sil-print-pass-name \
// RUN:   -Xllvm -sil-on-demand-emission 2>&1 \
// RUN:   | %FileCheck --check-prefix=SIBLINGS %s

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Shapes.swift -o /dev/null -Xllvm -sil-print-pass-name 2>&1 \
// RUN:   | %FileCheck --check-prefix=SHAPES %s
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Shapes.swift -o /dev/null -Xllvm -sil-print-pass-name \
// RUN:   -Xllvm -sil-on-demand-emission 2>&1 \
// RUN:   | %FileCheck --check-prefix=SHAPES %s

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Cycle.swift -o /dev/null -Xllvm -sil-print-pass-name 2>&1 \
// RUN:   | %FileCheck --check-prefix=CYCLE %s
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Cycle.swift -o /dev/null -Xllvm -sil-print-pass-name \
// RUN:   -Xllvm -sil-on-demand-emission 2>&1 \
// RUN:   | %FileCheck --check-prefix=CYCLE %s

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/RootCycle.swift -o /dev/null -Xllvm -sil-print-pass-name 2>&1 \
// RUN:   | %FileCheck --check-prefix=ROOTCYCLE %s
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/RootCycle.swift -o /dev/null -Xllvm -sil-print-pass-name \
// RUN:   -Xllvm -sil-on-demand-emission 2>&1 \
// RUN:   | %FileCheck --check-prefix=ROOTCYCLE %s

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Roots.swift -o /dev/null -Xllvm -sil-print-pass-name 2>&1 \
// RUN:   | %FileCheck --check-prefix=ROOTS %s
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/Roots.swift -o /dev/null -Xllvm -sil-print-pass-name \
// RUN:   -Xllvm -sil-on-demand-emission 2>&1 \
// RUN:   | %FileCheck --check-prefix=ROOTS %s

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

// SIBLINGS: NoReturnFolding (noreturn-folding), Function: $s1M6parentSiyF5firstL_SiyF{{$}}
// SIBLINGS: NoReturnFolding (noreturn-folding), Function: $s1M6parentSiyF6secondL_SiyF{{$}}
// SIBLINGS: NoReturnFolding (noreturn-folding), Function: $s1M6parentSiyF{{$}}

//--- Shapes.swift

// immediate is a callee of shapes, so it runs first. bound is held by a let
// binding, which getCalleeOrigin doesn't look through, so it runs after
// shapes. even and odd call each other, and legacy breaks the cycle where it
// closes.

func shapes() -> Int {
  let immediate = { () -> Int in 1 }()
  let bound = { () -> Int in 2 }
  func even(_ n: Int) -> Bool { return n == 0 ? true : odd(n - 1) }
  func odd(_ n: Int) -> Bool { return n == 0 ? false : even(n - 1) }
  return immediate + bound() + (even(4) ? 1 : 0)
}

// SHAPES: NoReturnFolding (noreturn-folding), Function: $s1M6shapesSiyFSiyXEfU_{{$}}
// SHAPES: NoReturnFolding (noreturn-folding), Function: $s1M6shapesSiyF3oddL_ySbSiF{{$}}
// SHAPES: NoReturnFolding (noreturn-folding), Function: $s1M6shapesSiyF4evenL_ySbSiF{{$}}
// SHAPES: NoReturnFolding (noreturn-folding), Function: $s1M6shapesSiyF{{$}}
// SHAPES: NoReturnFolding (noreturn-folding), Function: $s1M6shapesSiyFSiycfU0_{{$}}

//--- Cycle.swift

// a calls b and c, which both call a. Legacy lists the members of the cycle as
// it pops them off its DFS stack, after all the callees of the first function
// that it visited: c, b, a.

func scc() -> Int {
  func a(_ n: Int) -> Int { return n == 0 ? 0 : b(n - 1) + c(n - 1) }
  func b(_ n: Int) -> Int { return a(n) }
  func c(_ n: Int) -> Int { return a(n) }
  return a(3)
}

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

// ROOTCYCLE: NoReturnFolding (noreturn-folding), Function: $s1M4walkyS2iF5otherL_SiyF{{$}}
// ROOTCYCLE: NoReturnFolding (noreturn-folding), Function: $s1M4walkyS2iF6helperL_SiyF{{$}}
// ROOTCYCLE: NoReturnFolding (noreturn-folding), Function: $s1M4walkyS2iF{{$}}

//--- Roots.swift

// No closure calls another: roots passes them all. Legacy runs the ones that
// no function calls in the order SILGen created them, a nested closure before
// the next sibling.

func use(_ f: () -> ()) {}

func roots() {
  use { use { } }
  use { }
}

// ROOTS: NoReturnFolding (noreturn-folding), Function: $s1M5rootsyyF{{$}}
// ROOTS: NoReturnFolding (noreturn-folding), Function: $s1M5rootsyyFyyXEfU_{{$}}
// ROOTS: NoReturnFolding (noreturn-folding), Function: $s1M5rootsyyFyyXEfU_yyXEfU_{{$}}
// ROOTS: NoReturnFolding (noreturn-folding), Function: $s1M5rootsyyFyyXEfU0_{{$}}
