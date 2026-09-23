// Differential parity for NSErrorDomain. See lit.local.cfg for the harness. The
// wrapper needs the Foundation overlay, so the client imports Foundation, and
// the fixture is a module of its own: importing Foundation into a shared one
// would change every other cell's output.
//
// The domain decides the imported shape, not just an attribute. With it the
// enum becomes an error wrapper struct plus a nested Code; without it the enum
// keeps its C name. The classification also feeds the enum's Swift name, which
// is a key in the module's Swift lookup table, so this covers that table as
// well as the importer.

// REQUIRES: objc_interop

// REDEFINE: %{vi-module} = ErrorDomainMatrix
// REDEFINE: %{vi-map} = %S/Inputs/error-domain-matrix/module.modulemap
// REDEFINE: %{vi-client-flags} = -import-module Foundation

// RUN: %empty-directory(%t)
// RUN: %{vi-parity}

// The parity above holds for any output, so pin down what the default mode
// produces.
// RUN: %FileCheck %s --check-prefix=V4 < %t/capture-6-at-4.txt
// RUN: %FileCheck %s --check-prefix=V5 < %t/capture-4-at-5.txt
// RUN: %FileCheck %s --check-prefix=V6 < %t/capture-4-at-6.txt

// A sidecar-only domain has to produce the wrapper, and the enum's name loses
// the 'Code' suffix to it.
// V4-DAG: struct ErrU : _BridgedStoredNSError
// V4-DAG: struct ErrV4 : _BridgedStoredNSError
// V4-DAG: struct ErrV5 : _BridgedStoredNSError
// A sidecar domain replaces one written in the header.
// V4-DAG: struct ErrHeader : _BridgedStoredNSError
// No notes entry, so no wrapper.
// V4-NOT: struct ErrUntouched :

// At 5.0 the 4.0 slice is out of range, so this one keeps its C name and shape.
// V5-DAG: struct ErrV4Code
// V5-DAG: struct ErrV5 : _BridgedStoredNSError
// V5-DAG: struct ErrU : _BridgedStoredNSError

// Above every slice, only the unversioned domain applies.
// V6-DAG: struct ErrV5Code
// V6-DAG: struct ErrU : _BridgedStoredNSError
