// Differential parity for API notes removals: entries that take away an
// attribute the header wrote, rather than adding one. See lit.local.cfg for the
// harness.
//
// Getting a removal wrong is not a missing annotation. The declaration comes
// out Swift-private where the default mode makes it visible, so the name a
// client writes changes.

// REQUIRES: objc_interop

// REDEFINE: %{vi-module} = RemovalMatrix
// REDEFINE: %{vi-map} = %S/Inputs/removal-matrix/module.modulemap

// RUN: %empty-directory(%t)
// RUN: %{vi-parity}

// The parity above holds for any output, including one where no removal was
// honored at all, so pin down what the default mode produces.
// RUN: %FileCheck %s --check-prefix=V4 < %t/capture-6-at-4.txt
// RUN: %FileCheck %s --check-prefix=V5 < %t/capture-4-at-5.txt
// RUN: %FileCheck %s --check-prefix=V6 < %t/capture-4-at-6.txt

// An unversioned removal undoes the header's swift_private.
// V4-DAG: func removeU()
// So does a versioned one, at or below its version.
// V4-DAG: func removeV4()
// V4-DAG: func removeV5()
// The winning slice decides, whichever way it points.
// V4-DAG: func addUremoveV4()
// V4-DAG: func __removeUaddV4()
// No entry, so the header stands and the name keeps its mangling prefix.
// V4-DAG: func __removeUntouched()
// Nothing to remove, and removing nothing must not invent an attribute.
// V4-DAG: func removeNoHeader()

// At 5.0 the 4.0 slices are out of range.
// V5-DAG: func removeU()
// V5-DAG: func __removeV4()
// V5-DAG: func removeV5()
// V5-DAG: func __addUremoveV4()
// V5-DAG: func removeUaddV4()
// V5-DAG: func __removeUntouched()

// Above every slice, only the unversioned ones apply.
// V6-DAG: func removeU()
// V6-DAG: func __removeV5()
// V6-DAG: func __addUremoveV4()
// V6-DAG: func removeUaddV4()
