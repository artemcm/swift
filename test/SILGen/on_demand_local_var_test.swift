// Local variable accesses on demand. The function-only pipeline runs the
// closure group passes by default, so AccessEnforcementSelection chooses each
// access's enforcement and no begin_access [unknown] reaches canonical SIL
// (D2). Static and dynamic enforcement must match the legacy path.

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// RUN: %target-swift-emit-sil -parse-as-library -module-name M %t/Parity.swift \
// RUN:   -o %t/legacy.sil
// RUN: %target-swift-emit-sil -parse-as-library -module-name M %t/Parity.swift \
// RUN:   -Xllvm -sil-on-demand-emission -sil-verify-all -o %t/ondemand.sil
// RUN: diff %t/legacy.sil %t/ondemand.sil
// RUN: %FileCheck --implicit-check-not='[unknown]' %s < %t/ondemand.sil

// A box captured by a closure that is stored in a local `let` but never
// escapes: legacy MandatoryAllocBoxToStack specializes the closure, promotes
// the box, makes the accesses [static], and deletes the unspecialized closure.
// On demand, the function pass AllocBoxToStack specializes the closure too,
// but the accesses stay [dynamic] and the unspecialized closure stays. Known
// difference, recorded here so that a fix shows up.
// RUN: %target-swift-emit-sil -parse-as-library -module-name M \
// RUN:   %t/NonEscaping.swift | %FileCheck %s --check-prefix=NONESC-LEGACY
// RUN: %target-swift-emit-sil -parse-as-library -module-name M \
// RUN:   %t/NonEscaping.swift -Xllvm -sil-on-demand-emission -sil-verify-all \
// RUN:   | %FileCheck %s --check-prefix=NONESC-ONDEMAND

// Static enforcement: a local var that no closure captures.
// CHECK-LABEL: sil hidden @$s1M1fyS2iF :
// CHECK:         begin_access [modify] [static]
// CHECK:         begin_access [read] [static]
// CHECK-LABEL: } // end sil function '$s1M1fyS2iF'

// An inout parameter.
// CHECK-LABEL: sil hidden @$s1M4bumpyySizF :
// CHECK:         begin_access [modify] [static]
// CHECK-LABEL: } // end sil function '$s1M4bumpyySizF'

// A non-escaping closure literal captures the var's address, and its
// accesses are [static], like the parent's.
// CHECK-LABEL: sil hidden @$s1M7literalyS2iF :
// CHECK:         begin_access [read] [static]
// CHECK-LABEL: } // end sil function '$s1M7literalyS2iF'
// CHECK-LABEL: sil private [closure] @$s1M7literalyS2iFySiXEfU_ :
// CHECK:         begin_access [modify] [static]
// CHECK-LABEL: } // end sil function '$s1M7literalyS2iFySiXEfU_'

// Dynamic enforcement: an escaping closure captures the box, so the parent's
// and the closure's accesses are [dynamic].
// CHECK-LABEL: sil hidden @$s1M7counterySiycSiF :
// CHECK:         begin_access [read] [dynamic]
// CHECK-LABEL: } // end sil function '$s1M7counterySiycSiF'
// CHECK-LABEL: sil private [closure] @$s1M7counterySiycSiFSiycfU_ :
// CHECK:         begin_access [modify] [dynamic]
// CHECK:         begin_access [read] [dynamic]
// CHECK-LABEL: } // end sil function '$s1M7counterySiycSiFSiycfU_'

// NONESC-LEGACY-LABEL: sil hidden @$s1M7captureyS2iF :
// NONESC-LEGACY:         begin_access [read] [static]
// NONESC-LEGACY-LABEL: } // end sil function '$s1M7captureyS2iF'
// NONESC-LEGACY-LABEL: sil private [closure] @$s1M7captureyS2iFySicfU_Tf0ns_n :
// NONESC-LEGACY:         begin_access [modify] [static]
// NONESC-LEGACY-LABEL: } // end sil function '$s1M7captureyS2iFySicfU_Tf0ns_n'
// NONESC-LEGACY-NOT:   sil private [closure] @$s1M7captureyS2iFySicfU_ :

// NONESC-ONDEMAND-LABEL: sil hidden @$s1M7captureyS2iF :
// NONESC-ONDEMAND:         begin_access [read] [dynamic]
// NONESC-ONDEMAND-LABEL: } // end sil function '$s1M7captureyS2iF'
// NONESC-ONDEMAND-LABEL: sil private [closure] @$s1M7captureyS2iFySicfU_Tf0ns_n :
// NONESC-ONDEMAND:         begin_access [modify] [dynamic]
// NONESC-ONDEMAND-LABEL: } // end sil function '$s1M7captureyS2iFySicfU_Tf0ns_n'
// NONESC-ONDEMAND-LABEL: sil private [closure] @$s1M7captureyS2iFySicfU_ :

//--- Parity.swift
func f(_ x: Int) -> Int { var y = x; y += 1; return y }

func bump(_ x: inout Int) { x += 1 }

func apply(_ f: (Int) -> ()) { f(1) }

func literal(_ x: Int) -> Int {
  var total = x
  apply { total += $0 }
  return total
}

func counter(_ start: Int) -> () -> Int {
  var c = start
  let next = { c += 1; return c }
  _ = c
  return next
}

//--- NonEscaping.swift
func capture(_ x: Int) -> Int {
  var total = x
  let add = { (d: Int) in total += d }
  add(1)
  return total
}
