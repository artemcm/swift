// Differential parity for C++ declarations: namespaces, nested namespaces,
// records and their methods.

// REQUIRES: objc_interop

// DEFINE: %{module} = CxxMatrix
// DEFINE: %{v} =
// DEFINE: %{emit} = %target-swift-emit-pcm %mcp_opt -module-name %{module} %t/module.modulemap -cxx-interoperability-mode=default
// DEFINE: %{print} = %target-swift-ide-test -print-module -module-to-print=%{module} -source-filename %s -function-definitions=false -swift-version %{v} -cxx-interoperability-mode=default
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

// RUN: %FileCheck %s --check-prefix=V4 < %t/capture-6-at-4.txt
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

//--- module.modulemap
module CxxMatrix {
  header "CxxMatrix.h"
  requires cplusplus
  export *
}

//--- CxxMatrix.h
// C++ declarations under version-independent API notes: namespaces, records
// and their methods. The Swift lookup table collects captured declarations by
// walking into namespaces and records, so each of these has to be found there.
//
// Naming is <kind><arrangement>, as in version-matrix: U for the unversioned
// slice, V4 for the 4.0 slice.

namespace MatrixNS {
void nsFuncU();
void nsFuncV4();
void nsPrivV4();

struct NSRecord {
  int value;
  void methodU() const;
  void methodV4() const;
  void methodPrivV4() const;
};

enum class NSScopedEnumV4 { first, second };

namespace Inner {
void innerFuncU();
void innerFuncV4();
} // namespace Inner
} // namespace MatrixNS

struct TopRecordV4 {
  int field;
};

//--- CxxMatrix.apinotes
Name: CxxMatrix

Namespaces:
  - Name: MatrixNS
    Functions:
      - Name: nsFuncU
        SwiftName: 'nsFuncU_unversioned()'
    Tags:
      - Name: NSRecord
        Methods:
          - Name: methodU
            SwiftName: 'methodU_unversioned()'
    Namespaces:
      - Name: Inner
        Functions:
          - Name: innerFuncU
            SwiftName: 'innerFuncU_unversioned()'

SwiftVersions:
  - Version: 4
    Namespaces:
      - Name: MatrixNS
        Functions:
          - Name: nsFuncV4
            SwiftName: 'nsFuncV4_v4()'
          - Name: nsPrivV4
            SwiftPrivate: true
        Tags:
          - Name: NSRecord
            Methods:
              - Name: methodV4
                SwiftName: 'methodV4_v4()'
              - Name: methodPrivV4
                SwiftPrivate: true
          - Name: NSScopedEnumV4
            SwiftName: NSScopedEnumV4_v4
        Namespaces:
          - Name: Inner
            Functions:
              - Name: innerFuncV4
                SwiftName: 'innerFuncV4_v4()'
    Tags:
      - Name: TopRecordV4
        SwiftName: TopRecordV4_v4
