// Differential parity for NSErrorDomain. The error wrapper needs the Foundation
// overlay, so the client imports Foundation, and the fixture is a module of its
// own: importing Foundation into a shared one would change every other cell's
// output. The module itself only forward-declares NSString, because a module
// that imports an SDK module can't be read at another Swift version: its
// dependencies and the client's are built per version, and would be two
// copies.
//
// The domain decides the imported shape, not just an attribute. With it the
// enum becomes an error wrapper struct plus a nested Code; without it the enum
// keeps its C name. The classification also feeds the enum's Swift name, which
// is a key in the module's Swift lookup table, so this covers that table as
// well as the importer.

// REQUIRES: objc_interop

// DEFINE: %{module} = ErrorDomainMatrix
// DEFINE: %{v} =
// DEFINE: %{emit} = %target-swift-emit-pcm %mcp_opt -module-name %{module} %t/module.modulemap
// DEFINE: %{print} = %target-swift-ide-test -print-module -module-to-print=%{module} -source-filename %s -function-definitions=false -swift-version %{v} -import-module Foundation
// DEFINE: %{oracle} = \
// DEFINE:   %{emit} -swift-version %{v} -o %t/default-%{v}.pcm && \
// DEFINE:   %{print} -Xcc -fmodule-file=%{module}=%t/default-%{v}.pcm \
// DEFINE:     > %t/default-%{v}.txt 2> %t/default-%{v}.err && \
// DEFINE:   not grep error: %t/default-%{v}.err
// DEFINE: %{check} = \
// DEFINE:   %{print} -version-independent-apinotes -Xcc -fmodule-file=%{module}=%t/capture-4.pcm \
// DEFINE:     > %t/capture-4-at-%{v}.txt 2> %t/capture-4-at-%{v}.err && \
// DEFINE:   not grep error: %t/capture-4-at-%{v}.err && \
// DEFINE:   %diff %t/default-%{v}.txt %t/capture-4-at-%{v}.txt && \
// DEFINE:   %{print} -version-independent-apinotes -Xcc -fmodule-file=%{module}=%t/capture-6.pcm \
// DEFINE:     > %t/capture-6-at-%{v}.txt 2> %t/capture-6-at-%{v}.err && \
// DEFINE:   not grep error: %t/capture-6-at-%{v}.err && \
// DEFINE:   %diff %t/default-%{v}.txt %t/capture-6-at-%{v}.txt

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// Captured modules, built at the lowest and the highest Swift version.
// RUN: %{emit} -swift-version 4 -o %t/capture-4.pcm -Xfrontend -version-independent-apinotes
// RUN: %{emit} -swift-version 6 -o %t/capture-6.pcm -Xfrontend -version-independent-apinotes

// At each version, the default-mode module built at that version is the
// oracle, and both captured modules have to print exactly as it does.
// Clients get a module only through -fmodule-file, with no module map, so
// none of them can build one of their own instead.
// REDEFINE: %{v} = 4
// RUN: %{oracle}
// RUN: %{check}
// REDEFINE: %{v} = 4.2
// RUN: %{oracle}
// RUN: %{check}
// REDEFINE: %{v} = 5
// RUN: %{oracle}
// RUN: %{check}
// REDEFINE: %{v} = 6
// RUN: %{oracle}
// RUN: %{check}

// The fixture has to tell the versions apart, or a module that applied its
// notes while it was built would pass as well.
// RUN: %{print} -Xcc -fmodule-file=%{module}=%t/default-4.pcm > %t/default-4-at-6.txt
// RUN: not %diff -q %t/default-6.txt %t/default-4-at-6.txt

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

//--- module.modulemap
module ErrorDomainMatrix {
  header "ErrorDomainMatrix.h"
  export *
}

//--- ErrorDomainMatrix.h
// NSErrorDomain across the slice arrangements that matter. The client imports
// Foundation, so that the _BridgedStoredNSError wrapper actually forms and
// shows up in the printed interface. The module itself only forward-declares
// NSString: importing Foundation here would tie it to the SDK modules of the
// Swift version it was built at.
//
// The domain is the one API notes key whose loss is not cosmetic: it decides
// whether the enum imports as an error wrapper plus a nested Code, or as a bare
// enum, and the two have different Swift names. A client written against one
// does not compile against the other.

@class NSString;

extern NSString *const ErrNotesDomain;
extern NSString *const ErrHeaderDomain;

// Domain supplied only by the unversioned slice.
enum ErrUCode { ErrUCodeFirst = 1 };

// Domain supplied only by the 4.0 slice, so a 5.0 client must not see a wrapper.
enum ErrV4Code { ErrV4CodeFirst = 1 };

// Domain supplied only by the 5.0 slice, so a 6.0 client must not see a wrapper.
enum ErrV5Code { ErrV5CodeFirst = 1 };

// Header writes a domain and the notes replace it.
enum ErrHeaderCode {
  ErrHeaderCodeFirst = 1
} __attribute__((ns_error_domain(ErrHeaderDomain)));

// Control: no notes entry at all. Keeps the comparison honest about which
// declarations the notes are responsible for.
enum ErrUntouchedCode { ErrUntouchedCodeFirst = 1 };

//--- ErrorDomainMatrix.apinotes
Name: ErrorDomainMatrix

Tags:
  - Name: ErrUCode
    NSErrorDomain: ErrNotesDomain
  - Name: ErrHeaderCode
    NSErrorDomain: ErrNotesDomain

SwiftVersions:
  - Version: 4
    Tags:
      - Name: ErrV4Code
        NSErrorDomain: ErrNotesDomain
  - Version: 5
    Tags:
      - Name: ErrV5Code
        NSErrorDomain: ErrNotesDomain
