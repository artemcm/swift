// RUN: not %target-swift-frontend -emit-sil %s -o /dev/null -module-name T6 -Xllvm -sil-capture-scc-scheduling=module -Xllvm -sil-print-pass-name 2>&1 | %FileCheck %s --check-prefix=NAMES-MODULE
// RUN: not %target-swift-frontend -emit-sil %s -o /dev/null -module-name T6 -Xllvm -sil-capture-scc-scheduling=scc -Xllvm -sil-print-pass-name 2>&1 | %FileCheck %s --check-prefix=NAMES-SCC
// RUN: %target-swift-frontend -emit-sil %s -o /dev/null -module-name T6 -Xllvm -sil-capture-scc-scheduling=scc -Xllvm -sil-disable-pass=diagnose-static-exclusivity
// RUN: not %target-swift-frontend -emit-sil %s -o /dev/null -module-name T6 -Xllvm -sil-capture-scc-scheduling=scc -Xllvm -sil-print-after=capture-promotion -Xllvm '-sil-print-function=$s2T61fyyFSiycfU_Tf2i_n' 2>&1 | %FileCheck %s --check-prefix=PRINT
// RUN: not %target-swift-frontend -emit-sil %s -o /dev/null -module-name T6 -Xllvm -sil-capture-scc-scheduling=scc -Xllvm -sil-verify-around-pass=capture-promotion -Xllvm -sil-print-pass-time 2>&1 | %FileCheck %s --check-prefix=TIME-SCC
// RUN: not %target-swift-frontend -emit-sil %s -o /dev/null -module-name T6 -Xllvm -sil-capture-scc-scheduling=module -Xllvm -sil-verify-around-pass=capture-promotion -Xllvm -sil-print-pass-time 2>&1 | %FileCheck %s --check-prefix=TIME-MODULE

// T6: tooling on capture SCC transforms (CaptureSCCSchedule.h).

// NAMES-MODULE: Run module pass #{{[0-9]+}}, {{.*}}: MarkNeverWrittenMutableClosureBoxesAsImmutable
// NAMES-MODULE: Run module pass {{.*}}: CapturePromotion (capture-promotion)
// NAMES-SCC: Start capture SCC block at stage: Mandatory Diagnostic Passes + Enabling Optimization Passes ({{[0-9]+}} SCCs)
// NAMES-SCC: Run capture SCC pass {{.*}}: CapturePromotion (capture-promotion), Function: $s2T61fyyF

// Capture SCC transforms honor -sil-print-pass-time like module passes; in scc
// mode each invocation names its SCC's first member.
// TIME-SCC: ms: capture-promotion #{{[0-9]+}} @$s2T61fyyF
// TIME-MODULE: ms: capture-promotion #{{[0-9]+}}{{$}}

// The clone, printed after capture promotion in its SCC.
// PRINT: sil private [ossa] @$s2T61fyyFSiycfU_Tf2i_n : $@convention(thin) (Int) -> Int {

func escape(_ f: @escaping () -> Int) {}
func takesInoutAndClosure<T>(_ p: inout T, _ c: () -> ()) {}

public func f() {
  var x = 1
  x += 1
  escape { x }
}

// An exclusivity error, which RUN line 3 disables with its pass.
public func overlapping() {
  var local = 5
  takesInoutAndClosure(&local) {
    local = 8
  }
}
