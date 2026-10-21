// RUN: %target-swift-frontend -emit-sil %s -o /dev/null -verify -Xllvm -sil-capture-scc-scheduling=module
// RUN: %target-swift-frontend -emit-sil %s -o /dev/null -verify -Xllvm -sil-capture-scc-scheduling=scc
// RUN: not %target-swift-frontend -emit-sil %s -o /dev/null -Xllvm -sil-capture-scc-scheduling=scc -module-name T3 -Xllvm -sil-print-capture-scc-sets 2>&1 | %FileCheck %s

// T3: diagnostics from the passes of the capture SCC block
// (CaptureSCCSchedule.h) are emitted once per function in both schedules.
// capturePromoted's escaping closure captures a box that capture promotion
// promotes, creating a clone in the same SCC; the clone must not repeat its
// original's diagnostics.

func escape(_ f: @escaping () -> Int) {}

// The clone (Tf2i_n) joins the set after capture promotion creates it, ahead of
// its original in function-list order, and stays in it for the rest of the
// block.
// CHECK: Capture SCC set for capture-promotion: $s2T315capturePromotedyyF $s2T315capturePromotedyyFSiycfU_{{$}}
// CHECK-NEXT: Capture SCC set for access-enforcement-selection: $s2T315capturePromotedyyF $s2T315capturePromotedyyFSiycfU_Tf2i_n $s2T315capturePromotedyyFSiycfU_{{$}}
// CHECK-NEXT: Capture SCC set for mandatory-allocbox-to-stack: $s2T315capturePromotedyyF $s2T315capturePromotedyyFSiycfU_Tf2i_n $s2T315capturePromotedyyFSiycfU_{{$}}
// CHECK-NEXT: Capture SCC set for diagnose-static-exclusivity: $s2T315capturePromotedyyF $s2T315capturePromotedyyFSiycfU_Tf2i_n $s2T315capturePromotedyyFSiycfU_{{$}}
public func capturePromoted() {
  var x = 1
  x += 1
  escape { x }
}

// DiagnoseInvalidEscapingCaptures (inside the block), on a closure that also
// captures a promotable box.
public func inoutCapturedByEscaping(_ v: inout Int) { // expected-note {{parameter 'v' is declared 'inout'}}
  var y = 1
  y += 1
  escape { // expected-error {{escaping closure captures 'inout' parameter 'v'}}
    v + y // expected-note {{captured here}}
  }
}

func takesInoutAndClosure<T>(_ p: inout T, _ c: () -> ()) {}

// DiagnoseStaticExclusivity, through a closure's access summary.
public func overlapping() {
  var local = 5
  takesInoutAndClosure(&local) { // expected-error {{overlapping accesses to 'local', but modification requires exclusive access; consider copying to a local variable}}
    local = 8 // expected-note {{conflicting access is here}}
  }
}
