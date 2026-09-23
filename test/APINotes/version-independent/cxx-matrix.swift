// Differential parity for C++ declarations: namespaces, nested namespaces,
// records and their methods. See lit.local.cfg for the harness.

// REQUIRES: objc_interop

// REDEFINE: %{vi-module} = CxxMatrix
// REDEFINE: %{vi-map} = %S/Inputs/cxx-matrix/module.modulemap
// REDEFINE: %{vi-flags} = -cxx-interoperability-mode=default

// RUN: %empty-directory(%t)
// RUN: %{vi-parity}

// RUN: %FileCheck %s --check-prefix=V4 < %t/capture-5-at-4.txt
// RUN: %FileCheck %s --check-prefix=V5 < %t/capture-4-at-5.txt

// V4-DAG: static func nsFuncU_unversioned()
// V4-DAG: static func nsFuncV4_v4()
// V4-DAG: static func __nsPrivV4()
// V4-DAG: func methodV4_v4()
// V4-DAG: func __methodPrivV4()
// V4-DAG: static func innerFuncV4_v4()

// V5-DAG: static func nsFuncV4()
// V5-DAG: static func nsPrivV4()
// V5-DAG: func methodV4()
// V5-DAG: static func innerFuncU_unversioned()
