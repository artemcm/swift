// Test that on-demand emission inlines @_transparent functions from
// non-primary files (rdar://15366167).
//
// In legacy non-single-frontend mode, @_transparent functions from
// non-primary files have no SIL body, so mandatory inlining cannot
// process them. The on-demand path SILGen's the body on demand.

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// On-demand: @_transparent body is SILGen'd from non-primary file and inlined.
// RUN: %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -primary-file %t/Caller.swift %t/Helper.swift \
// RUN:   -module-name test \
// RUN:   -Xllvm -sil-on-demand-emission \
// RUN:   -o - | %FileCheck --check-prefix=ONDEMAND %s

// Legacy: @_transparent from non-primary file is not inlined.
// RUN: %target-swift-frontend -emit-sil -parse-as-library \
// RUN:   -primary-file %t/Caller.swift %t/Helper.swift \
// RUN:   -module-name test \
// RUN:   -o - | %FileCheck --check-prefix=LEGACY %s

// On-demand path: transparentHelper is inlined into caller (no apply).
// ONDEMAND-LABEL: sil hidden @$s4test6calleryS2iF
// ONDEMAND-NOT: apply
// ONDEMAND: return

// On-demand path: transparentHelper body was stripped after inlining.
// It retains external linkage; the definition is emitted when Helper.swift
// is the primary.
// ONDEMAND: sil hidden_external [transparent] @$s4test17transparentHelperyS2iF

// Legacy path: caller still has an apply (transparentHelper body unavailable).
// LEGACY-LABEL: sil hidden @$s4test6calleryS2iF
// LEGACY: function_ref @$s4test17transparentHelperyS2iF
// LEGACY: apply

// Legacy path: transparentHelper is an external declaration with no body.
// LEGACY: sil hidden_external [transparent] @$s4test17transparentHelperyS2iF

//--- Helper.swift
@_transparent func transparentHelper(_ x: Int) -> Int { return x }

//--- Caller.swift
func caller(_ x: Int) -> Int { return transparentHelper(x) }
