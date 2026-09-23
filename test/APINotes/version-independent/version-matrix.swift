// Differential parity for version-independent API notes over the widest
// fixture: names, visibility, availability, enum shape, SwiftWrapper and
// Objective-C container annotations, on functions, globals, enumerators,
// typedefs, tags, classes, categories and protocols, across unversioned,
// versioned and keyless slices. See lit.local.cfg for the harness.
//
// The parity is the assertion, so adding a declaration to Inputs/version-matrix
// extends the coverage without anyone predicting the expected output.

// REQUIRES: objc_interop

// REDEFINE: %{vi-module} = VersionMatrix
// REDEFINE: %{vi-map} = %S/Inputs/version-matrix/module.modulemap

// RUN: %empty-directory(%t)
// RUN: %{vi-parity}

// Parity holds for any output, so spot-check what the default mode produces,
// one check per annotation family, on captured modules built at another
// version than the one they are read at.
// RUN: %FileCheck %s --check-prefix=V4 < %t/capture-6-at-4.txt
// RUN: %FileCheck %s --check-prefix=V42 < %t/capture-4-at-4.2.txt
// RUN: %FileCheck %s --check-prefix=V6 < %t/capture-4-at-6.txt

// The 5.0 slice covers Swift 4 as well, and is the lowest that does, so it wins.
// V4-DAG: func nameU_v5()
// V4-DAG: func nameV4_fromNotes()
// A sidecar rename outranks one written in the header.
// V4-DAG: func nameHeader_fromNotes()
// So does a versioned one, at its version.
// V4-DAG: func nameHeaderV4_fromNotes()
// A 4.0 slice that sets no key still wins at 4.0, suppressing the unversioned
// rename.
// V4-DAG: func nameKeylessV4()
// The 4.2 slice is the lowest at or above 4.0.
// V4-DAG: func nameV42_v42()
// V4-DAG: func __privU()
// 'SwiftPrivate: false' undoes the header's swift_private.
// V4-DAG: func privHeaderUndoneU()
// V4-DAG: func privHeaderUndoneV4()
// V4-DAG: func availNonswiftU()
// V4-DAG: struct EnumFlagV4 : OptionSet
// A tag whose only 4.0 slice sets no key keeps the unannotated shape.
// V4-DAG: struct EnumClosedKeyless
// V4-DAG: init(designatedU value: CInt)
// V4-DAG: class MatrixNonGenericV4 : MatrixRoot
// V4-DAG: var globalNameV4_v4: CInt
// V4-DAG: var __globalPrivV4: CInt
// V4-DAG: var enumeratorUV_v4: EnumeratorNames
// V4-DAG: struct WrapperEnumV4 : Hashable
// V4-DAG: typealias WrapperNoneV4 = CInt
// A type has one canonical name, so an older version's rename of one is an
// alias.
// V4-DAG: typealias TypedefNameV4_v4 = TypedefNameV4
// V4-DAG: typealias MatrixProtocolV4_v4 = MatrixProtocolV4
// V4-DAG: func categoryMethodV4_v4()
// V4-DAG: func categoryAccessorsV4() -> Any
// V4-DAG: func protocolMethodV4_v4()

// V42-DAG: func nameV42_v42()
// V42-DAG: func nameU_v5()
// V42-DAG: func nameV4()

// Above every slice but the 6.0 one.
// V6-DAG: func nameU_unversioned()
// V6-DAG: func nameV6_v6()
// V6-DAG: func nameV42()
// V6-DAG: var globalNameU_unversioned: CInt
// V6-DAG: var enumeratorUV_unversioned: EnumeratorNames
// V6-DAG: struct WrapperStructU : Hashable
// V6-DAG: struct WrapperNoneV4 : Hashable
// V6-DAG: func categoryMethodU_unversioned()
// V6-DAG: var categoryAccessorsV4: Any { get }
// V6-DAG: protocol MatrixProtocolU_unversioned
// V6-DAG: func protocolMethodU_unversioned()
