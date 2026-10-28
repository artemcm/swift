// RUN: %target-swift-frontend -emit-sil %s -o /dev/null -verify
// RUN: not %target-swift-frontend -emit-sil %s -o /dev/null -module-name D -Xllvm -sil-print-closure-groups 2>&1 | %FileCheck %s --check-prefix=GROUPS
// RUN: not %target-swift-frontend -emit-sil %s -o /dev/null -module-name D 2>&1 | %FileCheck %s --check-prefix=ORDER
// RUN: not %target-swift-frontend -emit-sil %s -o /dev/null -module-name D -Xllvm -sil-print-pass-name -Xllvm -sil-print-pass-time 2>&1 | %FileCheck %s --check-prefix=NAMES
// RUN: %target-swift-frontend -emit-sil %s -o /dev/null -Xllvm -sil-disable-pass=diagnose-static-exclusivity

// CapturePromotion, AccessEnforcementSelection, MandatoryAllocBoxToStack, and
// DiagnoseStaticExclusivity run as one closure group block: one group at a
// time, callees first, each group through all four passes.

func takesInoutAndClosure<T>(_ p: inout T, _ c: () -> ()) {}
func modify(_ body: () -> ()) { body() }
func takesSendable(_: @escaping @Sendable () -> Void) {}

// A conflict found through the closure's access summary.
// GROUPS: Closure group for diagnose-static-exclusivity: $s1D11overlappingyyF $s1D11overlappingyyFyyXEfU_{{$}}
// ORDER: closure_group_scheduling_diagnostics.swift:[[@LINE+3]]:{{[0-9]+}}: error: overlapping accesses to 'local'
public func overlapping() {
  var local = 5
  takesInoutAndClosure(&local) { // expected-error {{overlapping accesses to 'local', but modification requires exclusive access; consider copying to a local variable}}
    local = 8 // expected-note {{conflicting access is here}}
  }
}

// The same conflict through nested closures, all in one group.
// GROUPS: Closure group for diagnose-static-exclusivity: $s1D6nestedyyF $s1D6nestedyyFyyXEfU_ $s1D6nestedyyFyyXEfU_yyXEfU_ $s1D6nestedyyFyyXEfU_yyXEfU_yyXEfU_{{$}}
public func nested() {
  var local = 5
  modify {
    takesInoutAndClosure(&local) { // expected-error {{overlapping accesses to 'local', but modification requires exclusive access; consider copying to a local variable}}
      modify {
        local = 8 // expected-note {{conflicting access is here}}
      }
    }
  }
}

// A function without closures is a group by itself.
// GROUPS: Closure group for diagnose-static-exclusivity: $s1D5aloneSiyF{{$}}
public func alone() -> Int { 1 }

// The function calls overlapping(), so overlapping()'s group runs first,
// through all four passes. Its DiagnoseStaticExclusivity error comes before
// this function's CapturePromotion warning.
// GROUPS:     Closure group for capture-promotion: $s1D27mutatesAfterSendableCaptureyyF $s1D27mutatesAfterSendableCaptureyyFyyYbcfU_{{$}}
// GROUPS-NOT: Closure group for
// GROUPS:     Closure group for access-enforcement-selection: $s1D27mutatesAfterSendableCaptureyyF $s1D27mutatesAfterSendableCaptureyyFyyYbcfU_{{$}}
// GROUPS-NOT: Closure group for
// GROUPS:     Closure group for mandatory-allocbox-to-stack: $s1D27mutatesAfterSendableCaptureyyF $s1D27mutatesAfterSendableCaptureyyFyyYbcfU_{{$}}
// GROUPS-NOT: Closure group for
// GROUPS:     Closure group for diagnose-static-exclusivity: $s1D27mutatesAfterSendableCaptureyyF $s1D27mutatesAfterSendableCaptureyyFyyYbcfU_{{$}}
// ORDER: closure_group_scheduling_diagnostics.swift:[[@LINE+7]]:{{[0-9]+}}: warning: 'i' mutated after capture by sendable closure
public func mutatesAfterSendableCapture() {
  overlapping()
  var i = 17 // expected-note {{variable defined here}}
  takesSendable { // expected-note {{variable captured by sendable closure}}
    print(i) // expected-warning {{reference to captured var 'i' in concurrently-executing code}} expected-note {{capturing use}}
  }
  i += 1 // expected-warning {{'i' mutated after capture by sendable closure}}
}

// Pass-name and pass-time output name the group's first member.
// NAMES: Start closure group block at stage: Mandatory Diagnostic Passes + Enabling Optimization Passes ({{[0-9]+}} groups)
// NAMES: Run closure group pass {{.*}}: DiagnoseStaticExclusivity (diagnose-static-exclusivity), Function: $s1D11overlappingyyF
// NAMES: ms: diagnose-static-exclusivity #{{[0-9]+}} @$s1D11overlappingyyF
