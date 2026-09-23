// Differential parity for a module with two API notes readers, its own sidecar
// and the one of the module it is exported as. See lit.local.cfg for the
// harness.
//
// Each reader's slices form their own slice groups, and the rest of this
// directory has one reader per module, so this is the only coverage of
// selection running once per group and of groups applying in order.

// REQUIRES: objc_interop

// REDEFINE: %{vi-module} = SidecarCore
// REDEFINE: %{vi-map} = %S/Inputs/two-sidecars/module.modulemap

// RUN: %empty-directory(%t)
// RUN: %{vi-parity}

// Both sidecars have to be read at all, or the parity above is over one. Where
// both set the same key, the exported module's sidecar applies second and wins.
// RUN: %FileCheck %s --check-prefix=V4 < %t/capture-5-at-4.txt
// RUN: %FileCheck %s --check-prefix=V5 < %t/capture-4-at-5.txt

// V4-DAG: func name_CoreU_core()
// V4-DAG: func name_ExportedU_exported()
// V4-DAG: func name_ExportedV4_exported4()
// V4-DAG: func name_CoreU_ExportedU_exported()
// V4-DAG: func name_CoreU_ExportedV4_exported4()
// V4-DAG: func __name_CoreU_ExportedV4Priv()

// V5-DAG: func name_ExportedV4()
// V5-DAG: func name_CoreU_ExportedV4_core()
// V5-DAG: func name_CoreU_ExportedV4Priv_core()
