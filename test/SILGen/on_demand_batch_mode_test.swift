// Batch mode: one frontend invocation lowers each primary file into its own
// SILModule, through one evaluator. A SILGen request cached while lowering
// one primary must not hand its result, a SILFunction in a destroyed module,
// to the next primary. Each primary's batch output must equal its
// single-primary output, on the legacy path and on demand.

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// Legacy path.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/A.swift -primary-file %t/B.swift %t/Shared.swift \
// RUN:   -o %t/A.batch.sil -o %t/B.batch.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -primary-file %t/A.swift %t/B.swift %t/Shared.swift -o %t/A.single.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   %t/A.swift -primary-file %t/B.swift %t/Shared.swift -o %t/B.single.sil
// RUN: diff %t/A.batch.sil %t/A.single.sil
// RUN: diff %t/B.batch.sil %t/B.single.sil
// RUN: %FileCheck --check-prefix=LEGACY %s < %t/B.batch.sil

// Raw SIL too: the stale interface used to print as a garbage function_ref.
// RUN: %target-swift-frontend -emit-silgen -parse-as-library -module-name M \
// RUN:   -primary-file %t/A.swift -primary-file %t/B.swift %t/Shared.swift \
// RUN:   -o %t/A.batch.silgen -o %t/B.batch.silgen
// RUN: %target-swift-frontend -emit-silgen -parse-as-library -module-name M \
// RUN:   %t/A.swift -primary-file %t/B.swift %t/Shared.swift \
// RUN:   -o %t/B.single.silgen
// RUN: diff %t/B.batch.silgen %t/B.single.silgen

// On demand.
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -Xllvm -sil-on-demand-emission \
// RUN:   -primary-file %t/A.swift -primary-file %t/B.swift %t/Shared.swift \
// RUN:   -o %t/A.ondemand.batch.sil -o %t/B.ondemand.batch.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -Xllvm -sil-on-demand-emission \
// RUN:   -primary-file %t/A.swift %t/B.swift %t/Shared.swift \
// RUN:   -o %t/A.ondemand.single.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M \
// RUN:   -Xllvm -sil-on-demand-emission \
// RUN:   %t/A.swift -primary-file %t/B.swift %t/Shared.swift \
// RUN:   -o %t/B.ondemand.single.sil
// RUN: diff %t/A.ondemand.batch.sil %t/A.ondemand.single.sil
// RUN: diff %t/B.ondemand.batch.sil %t/B.ondemand.single.sil
// RUN: %FileCheck --check-prefix=ONDEMAND --implicit-check-not='[unknown]' %s \
// RUN:   < %t/B.ondemand.batch.sil

// Object code with the verifier, on both paths.
// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -sil-verify-all \
// RUN:   -primary-file %t/A.swift -primary-file %t/B.swift %t/Shared.swift \
// RUN:   -o %t/A.o -o %t/B.o
// RUN: %target-swift-frontend -c -parse-as-library -module-name M \
// RUN:   -sil-verify-all -Xllvm -sil-on-demand-emission \
// RUN:   -primary-file %t/A.swift -primary-file %t/B.swift %t/Shared.swift \
// RUN:   -o %t/A.ondemand.o -o %t/B.ondemand.o

// The second primary calls the shared non-primary function by its name.
// LEGACY-LABEL: sil @$s1M4useBSiyF
// LEGACY: function_ref @$s1M6helperSiyF
// LEGACY: function_ref @$s1M17transparentHelperyS2iF
// LEGACY-LABEL: } // end sil function '$s1M4useBSiyF'

// On demand, the second primary also SILGens the non-primary
// @_transparent function again, inlines it, and strips its body. Its local
// vars get static and dynamic enforcement from the closure group passes.
// ONDEMAND-LABEL: sil @$s1M4useBSiyF
// ONDEMAND: function_ref @$s1M6helperSiyF
// ONDEMAND-NOT: function_ref @$s1M17transparentHelperyS2iF
// ONDEMAND-LABEL: } // end sil function '$s1M4useBSiyF'
// ONDEMAND: sil hidden_external [transparent] @$s1M17transparentHelperyS2iF
// ONDEMAND-LABEL: sil @$s1M6localByS2iF :
// ONDEMAND:         begin_access [modify] [static]
// ONDEMAND-LABEL: } // end sil function '$s1M6localByS2iF'
// ONDEMAND-LABEL: sil @$s1M8counterBySiycSiF :
// ONDEMAND:         begin_access [read] [dynamic]
// ONDEMAND-LABEL: } // end sil function '$s1M8counterBySiycSiF'

//--- Shared.swift
public func helper() -> Int { return 42 }
@_transparent public func transparentHelper(_ x: Int) -> Int { return x &+ 1 }
public func withDefault(_ x: Int = 7) -> Int { return x }
public func apply(_ f: () -> Int) -> Int { return f() }

//--- A.swift
public func useA() -> Int {
  return helper() &+ transparentHelper(1) &+ withDefault()
}
public func closureA(_ x: Int) -> Int { return apply { x &+ helper() } }
public func localA(_ x: Int) -> Int { var y = x; y &+= helper(); return y }
public func counterA(_ x: Int) -> () -> Int {
  var c = x
  let next = { c &+= 1; return c }
  _ = c
  return next
}

//--- B.swift
public func useB() -> Int {
  return helper() &+ transparentHelper(2) &+ withDefault()
}
public func closureB(_ x: Int) -> Int { return apply { x &+ helper() } }
public func localB(_ x: Int) -> Int { var y = x; y &+= helper(); return y }
public func counterB(_ x: Int) -> () -> Int {
  var c = x
  let next = { c &+= 1; return c }
  _ = c
  return next
}
