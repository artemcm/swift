// Differential parity for a module with two API notes readers, its own sidecar
// and the one of the module it is exported as.
//
// Each reader's slices form their own slice groups, and the rest of this
// directory has one reader per module, so this is the only coverage of
// selection running once per group and of groups applying in order.

// REQUIRES: objc_interop

// DEFINE: %{module} = SidecarCore
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

// Both sidecars have to be read at all, or the parity above is over one. Where
// both set the same key, the exported module's sidecar applies second and wins.
// RUN: %FileCheck %s --check-prefix=V4 < %t/capture-6-at-4.txt
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

//--- module.modulemap
module SidecarCore {
  header "SidecarCore.h"
  export_as Sidecar
  export *
}

//--- SidecarCore.h
// A module with two API notes readers: its own sidecar, SidecarCore.apinotes,
// and the one of the module it is exported as, Sidecar.apinotes. Each reader's
// slices form their own slice groups, and selection runs once per group, so a
// declaration both sidecars annotate can take its name from one reader and its
// visibility from the other, at different versions.
//
// Naming is <kind>_<arrangement>, where the arrangement says which sidecar sets
// the key at which slice: Core or Exported, U (unversioned) or V4.

void name_CoreU(void);
void name_ExportedU(void);
void name_ExportedV4(void);

// Different keys from different readers.
void namePriv_CoreUName_ExportedUPriv(void);
void namePriv_CoreV4Name_ExportedUPriv(void);
void namePriv_CoreUName_ExportedV4Priv(void);

// Both readers have a slice for the same declaration, at different versions,
// so each group selects on its own.
void name_CoreU_ExportedV4Priv(void);

// Both readers set the same key. The default mode applies them in group order.
void name_CoreU_ExportedU(void);
void name_CoreV4_ExportedU(void);
void name_CoreU_ExportedV4(void);

//--- SidecarCore.apinotes
Name: SidecarCore

Functions:
  - Name: name_CoreU
    SwiftName: 'name_CoreU_core()'
  - Name: namePriv_CoreUName_ExportedUPriv
    SwiftName: 'namePriv_CoreUName_ExportedUPriv_core()'
  - Name: namePriv_CoreUName_ExportedV4Priv
    SwiftName: 'namePriv_CoreUName_ExportedV4Priv_core()'
  - Name: name_CoreU_ExportedV4Priv
    SwiftName: 'name_CoreU_ExportedV4Priv_core()'
  - Name: name_CoreU_ExportedU
    SwiftName: 'name_CoreU_ExportedU_core()'
  - Name: name_CoreU_ExportedV4
    SwiftName: 'name_CoreU_ExportedV4_core()'

SwiftVersions:
  - Version: 4
    Functions:
      - Name: namePriv_CoreV4Name_ExportedUPriv
        SwiftName: 'namePriv_CoreV4Name_ExportedUPriv_core4()'
      - Name: name_CoreV4_ExportedU
        SwiftName: 'name_CoreV4_ExportedU_core4()'

//--- Sidecar.apinotes
Name: Sidecar

Functions:
  - Name: name_ExportedU
    SwiftName: 'name_ExportedU_exported()'
  - Name: namePriv_CoreUName_ExportedUPriv
    SwiftPrivate: true
  - Name: namePriv_CoreV4Name_ExportedUPriv
    SwiftPrivate: true
  - Name: name_CoreU_ExportedU
    SwiftName: 'name_CoreU_ExportedU_exported()'
  - Name: name_CoreV4_ExportedU
    SwiftName: 'name_CoreV4_ExportedU_exported()'

SwiftVersions:
  - Version: 4
    Functions:
      - Name: name_ExportedV4
        SwiftName: 'name_ExportedV4_exported4()'
      - Name: namePriv_CoreUName_ExportedV4Priv
        SwiftPrivate: true
      - Name: name_CoreU_ExportedV4Priv
        SwiftPrivate: true
      - Name: name_CoreU_ExportedV4
        SwiftName: 'name_CoreU_ExportedV4_exported4()'
