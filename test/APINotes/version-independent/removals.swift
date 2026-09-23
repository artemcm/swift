// Differential parity for API notes removals: entries that take away an
// attribute the header wrote, rather than adding one.
//
// Getting a removal wrong is not a missing annotation. The declaration comes
// out Swift-private where the default mode makes it visible, so the name a
// client writes changes.

// REQUIRES: objc_interop

// DEFINE: %{module} = RemovalMatrix
// DEFINE: %{v} =
// DEFINE: %{emit} = %target-swift-emit-pcm %mcp_opt -module-name %{module} %t/module.modulemap
// DEFINE: %{print} = %target-swift-ide-test -print-module -module-to-print=%{module} -source-filename %s -function-definitions=false -swift-version %{v}
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

// Parity holds for any output, including one where no removal was honored at
// all, so pin down what the default mode produces.
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

//--- module.modulemap
module RemovalMatrix {
  header "RemovalMatrix.h"
  export *
}

//--- RemovalMatrix.h
// Removals: an API notes entry taking an attribute away that the header wrote.
//
// Each declaration carries the attribute in the header and has a sidecar entry
// that undoes it, in one of the slice arrangements selection has to tell
// apart.

void removeU(void) __attribute__((swift_private));
void removeV4(void) __attribute__((swift_private));
void removeV5(void) __attribute__((swift_private));

// The unversioned slice adds what the 4.0 slice removes, so which one wins
// decides the attribute, not just whether it came from the header.
void addUremoveV4(void);

// The reverse: the unversioned slice removes the header's attribute, and the
// 4.0 slice puts it back.
void removeUaddV4(void) __attribute__((swift_private));

// Untouched control: the header's attribute must survive.
void removeUntouched(void) __attribute__((swift_private));

// The header says nothing, so the removal has nothing to undo.
void removeNoHeader(void);

//--- RemovalMatrix.apinotes
Name: RemovalMatrix

Functions:
  - Name: removeU
    SwiftPrivate: false
  - Name: addUremoveV4
    SwiftPrivate: true
  - Name: removeUaddV4
    SwiftPrivate: false
  - Name: removeNoHeader
    SwiftPrivate: false

SwiftVersions:
  - Version: 4
    Functions:
      - Name: removeV4
        SwiftPrivate: false
      - Name: addUremoveV4
        SwiftPrivate: false
      - Name: removeUaddV4
        SwiftPrivate: true
  - Version: 5
    Functions:
      - Name: removeV5
        SwiftPrivate: false
