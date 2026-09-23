// Differential parity for a module whose declarations reach into another
// captured module: categories on its classes, signatures naming its types, and
// globals imported as members of its types. See lit.local.cfg for the harness.
//
// The Swift lookup table of a captured module is built from its own
// declarations collapsed at each version. The names of the other module's
// declarations, which some of its keys sit under, come from that module's
// notes, which this module's build reads already captured.

// REQUIRES: objc_interop

// REDEFINE: %{vi-dep-module} = ChainBase
// REDEFINE: %{vi-dep-map} = %S/Inputs/chain/ChainBase.modulemap
// REDEFINE: %{vi-module} = ChainExt
// REDEFINE: %{vi-map} = %S/Inputs/chain/ChainExt.modulemap

// RUN: %empty-directory(%t)
// RUN: %{vi-chain-parity}

// RUN: %FileCheck %s --check-prefix=V4 < %t/capture-5-at-4.txt
// RUN: %FileCheck %s --check-prefix=V5 < %t/capture-4-at-5.txt

// V4-DAG: extension ChainClassSwift {
// V4-DAG: func extMethodU_ext()
// V4-DAG: func extMethodV4_ext4()
// V4-DAG: func chainUsesClass(_ c: ChainClassSwift)

// V5-DAG: func extMethodV4()
// V5-DAG: func chainUsesIndex(_ i: ChainIndexV4)
