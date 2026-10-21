// RUN: %target-swift-frontend -emit-sil %s -module-name E -sil-verify-all -Xllvm -sil-capture-scc-scheduling=module -o %t.module.sil
// RUN: %target-swift-frontend -emit-sil %s -module-name E -sil-verify-all -Xllvm -sil-capture-scc-scheduling=scc -o %t.scc.sil
// RUN: diff %t.module.sil %t.scc.sil
// RUN: %FileCheck %s --check-prefix=SIL < %t.scc.sil
// RUN: %target-swift-frontend -emit-sil %s -module-name E -Xllvm -sil-capture-scc-scheduling=scc -Xllvm -sil-print-capture-scc-sets -o /dev/null 2>&1 | %FileCheck %s --check-prefix=SETS

// Capture SCC transforms (CaptureSCCSchedule.h) emit the same SIL in both
// schedules, and pass -sil-verify-all in both. The inputs cover each pass of the
// capture SCC block: boxes captured by closures and local functions,
// @inout_aliasable captures, capture promotion, and a box-to-stack
// specialization that deletes its original closure.

func callTwice(_ f: () -> Int) -> Int { f() + f() }
func modify(_ body: () -> ()) { body() }

// MandatoryAllocBoxToStack specializes the closure to take the promoted box's
// address and deletes the original. The original is in the pass's SCC set and
// gone from the next pass's set.
// SETS: Capture SCC set for mandatory-allocbox-to-stack: $s1E20mutatingClosureValueSiyF $s1E20mutatingClosureValueSiyFyycfU_{{$}}
// SETS-NEXT: Capture SCC set for diagnose-static-exclusivity: $s1E20mutatingClosureValueSiyF $s1E20mutatingClosureValueSiyFyycfU_Tf0s_n{{$}}
// SIL-NOT: sil private @$s1E20mutatingClosureValueSiyFyycfU_ :
// SIL: sil private @$s1E20mutatingClosureValueSiyFyycfU_Tf0s_n : $@convention(thin) (@inout_aliasable Int) -> () {
public func mutatingClosureValue() -> Int {
  var total = 0
  let bump = { total += 1 }
  bump()
  bump()
  return total
}

// CapturePromotion: the closure only reads the box.
public func capturePromoted() -> Int {
  var x = 1
  x += 1
  let c = { x + 1 }
  return c()
}

// Local functions that share a box, and a non-escaping closure.
public func localFunctions() -> Int {
  var total = 0
  func add(_ n: Int) { total += n }
  func addTwice(_ n: Int) { add(n); add(n) }
  addTwice(3)
  return callTwice { total }
}

// AccessEnforcementSelection and DiagnoseStaticExclusivity: an inout parameter
// captured by a non-escaping closure, inside nested closures.
public func inoutCaptured(_ x: inout Int) {
  modify {
    x += 1
    modify { x += 2 }
  }
}

// Mutually recursive local functions capturing a box.
public func recursiveLocals(_ n: Int) -> Int {
  var count = 0
  func even(_ k: Int) { count += 1; if k > 0 { odd(k - 1) } }
  func odd(_ k: Int) { count += 1; if k > 0 { even(k - 1) } }
  even(n)
  return count
}
