// Differential parity for a module whose declarations reach into another
// captured module: categories on its classes, signatures naming its types, and
// globals imported as members of its types.
//
// The Swift lookup table of a captured module is built from its own
// declarations collapsed at each version. The names of the other module's
// declarations, which some of its keys sit under, come from that module's
// notes, which this module's build reads already captured.

// REQUIRES: objc_interop

// DEFINE: %{v} =
// DEFINE: %{emit-base} = %target-swift-emit-pcm %mcp_opt -module-name ChainBase %t/ChainBase.modulemap
// DEFINE: %{emit-ext} = %target-swift-emit-pcm %mcp_opt -module-name ChainExt %t/ChainExt.modulemap
// DEFINE: %{print} = %target-swift-ide-test -print-module -module-to-print=ChainExt -source-filename %s -function-definitions=false -swift-version %{v}
// DEFINE: %{oracle} = \
// DEFINE:   %{emit-base} -swift-version %{v} -o %t/base-default-%{v}.pcm && \
// DEFINE:   %{emit-ext} -swift-version %{v} -o %t/default-%{v}.pcm \
// DEFINE:     -Xcc -fmodule-file=ChainBase=%t/base-default-%{v}.pcm && \
// DEFINE:   %{print} -Xcc -fmodule-file=ChainBase=%t/base-default-%{v}.pcm \
// DEFINE:     -Xcc -fmodule-file=ChainExt=%t/default-%{v}.pcm \
// DEFINE:     > %t/default-%{v}.txt 2> %t/default-%{v}.err && \
// DEFINE:   not grep error: %t/default-%{v}.err
// DEFINE: %{check} = \
// DEFINE:   %{print} -version-independent-apinotes -Xcc -fmodule-file=ChainBase=%t/base-capture-6.pcm \
// DEFINE:     -Xcc -fmodule-file=ChainExt=%t/capture-4.pcm \
// DEFINE:     > %t/capture-4-at-%{v}.txt 2> %t/capture-4-at-%{v}.err && \
// DEFINE:   not grep error: %t/capture-4-at-%{v}.err && \
// DEFINE:   %diff %t/default-%{v}.txt %t/capture-4-at-%{v}.txt && \
// DEFINE:   %{print} -version-independent-apinotes -Xcc -fmodule-file=ChainBase=%t/base-capture-4.pcm \
// DEFINE:     -Xcc -fmodule-file=ChainExt=%t/capture-6.pcm \
// DEFINE:     > %t/capture-6-at-%{v}.txt 2> %t/capture-6-at-%{v}.err && \
// DEFINE:   not grep error: %t/capture-6-at-%{v}.err && \
// DEFINE:   %diff %t/default-%{v}.txt %t/capture-6-at-%{v}.txt

// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// Captured modules at the lowest and the highest Swift version. Each ChainExt
// is built against the ChainBase built at the other one, so the building
// versions of a chain must not matter either.
// RUN: %{emit-base} -swift-version 4 -o %t/base-capture-4.pcm -Xfrontend -version-independent-apinotes
// RUN: %{emit-base} -swift-version 6 -o %t/base-capture-6.pcm -Xfrontend -version-independent-apinotes
// RUN: %{emit-ext} -swift-version 4 -o %t/capture-4.pcm -Xfrontend -version-independent-apinotes \
// RUN:   -Xcc -fmodule-file=ChainBase=%t/base-capture-6.pcm
// RUN: %{emit-ext} -swift-version 6 -o %t/capture-6.pcm -Xfrontend -version-independent-apinotes \
// RUN:   -Xcc -fmodule-file=ChainBase=%t/base-capture-4.pcm

// At each version, the default-mode chain built at that version is the oracle,
// and both captured chains have to print exactly as it does. Clients get the
// modules only through -fmodule-file, with no module maps, so none of them can
// build one of their own instead.
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

// The fixture has to tell the versions apart, or a chain that applied its
// notes while it was built would pass as well.
// RUN: %{print} -Xcc -fmodule-file=ChainBase=%t/base-default-4.pcm \
// RUN:   -Xcc -fmodule-file=ChainExt=%t/default-4.pcm > %t/default-4-at-6.txt
// RUN: not %diff -q %t/default-6.txt %t/default-4-at-6.txt

// RUN: %FileCheck %s --check-prefix=V4 < %t/capture-6-at-4.txt
// RUN: %FileCheck %s --check-prefix=V5 < %t/capture-4-at-5.txt

// V4-DAG: extension ChainClassSwift {
// V4-DAG: func extMethodU_ext()
// V4-DAG: func extMethodV4_ext4()
// V4-DAG: func chainUsesClass(_ c: ChainClassSwift)

// V5-DAG: func extMethodV4()
// V5-DAG: func chainUsesIndex(_ i: ChainIndexV4)

//--- ChainBase.modulemap
module ChainBase {
  header "ChainBase.h"
  export *
}

//--- ChainBase.h
// The base of a two-module chain. ChainExt extends these declarations, and its
// Swift lookup table keys some of its own names under these declarations' Swift
// names, which this module's API notes decide.

__attribute__((objc_root_class))
@interface ChainRoot
@end

// Renamed by the unversioned slice.
@interface ChainClass : ChainRoot
- (void)baseMethod;
@end

// Renamed by the 4.0 slice only.
@interface ChainClassV4 : ChainRoot
@end

typedef int ChainIndexV4;

enum ChainEnumV4 { ChainEnumV4First = 1, ChainEnumV4Second = 2 };

//--- ChainBase.apinotes
Name: ChainBase

Classes:
  - Name: ChainClass
    SwiftName: ChainClassSwift

SwiftVersions:
  - Version: 4
    Classes:
      - Name: ChainClassV4
        SwiftName: ChainClassV4_v4
    Typedefs:
      - Name: ChainIndexV4
        SwiftName: ChainIndexV4_v4
    Tags:
      - Name: ChainEnumV4
        EnumKind: NSOptions

//--- ChainExt.modulemap
module ChainExt {
  header "ChainExt.h"
  export *
}

//--- ChainExt.h
// The second module of the chain. Its declarations reach into ChainBase in
// each way the Swift lookup table records: categories on ChainBase's classes,
// signatures naming ChainBase's types, and globals imported as members of
// ChainBase's types.

@import ChainBase;

@interface ChainClass (ChainExt)
- (void)extMethodU;
- (void)extMethodV4;
@end

@interface ChainClassV4 (ChainExt)
- (void)extOnV4Class;
@end

void chainUsesClass(ChainClass *_Nonnull c);
void chainUsesV4Class(ChainClassV4 *_Nonnull c);
void chainUsesIndex(ChainIndexV4 i);
void chainUsesEnum(enum ChainEnumV4 e);

// Imported as members of ChainBase's types.
ChainClass *_Nonnull ChainClassMake(void);
ChainClassV4 *_Nonnull ChainClassV4Make(void);
ChainClassV4 *_Nonnull ChainClassV4MakeV4(void);

//--- ChainExt.apinotes
Name: ChainExt

Classes:
  - Name: ChainClass
    Methods:
      - Selector: extMethodU
        MethodKind: Instance
        SwiftName: 'extMethodU_ext()'

Functions:
  - Name: ChainClassMake
    SwiftName: 'ChainClassSwift.make()'
  - Name: ChainClassV4Make
    SwiftName: 'ChainClassV4.make()'

SwiftVersions:
  - Version: 4
    Classes:
      - Name: ChainClass
        Methods:
          - Selector: extMethodV4
            MethodKind: Instance
            SwiftName: 'extMethodV4_ext4()'
    Functions:
      # Names ChainBase's type by the name only a 4.0 client has for it.
      - Name: ChainClassV4MakeV4
        SwiftName: 'ChainClassV4_v4.makeV4()'
