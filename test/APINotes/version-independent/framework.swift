// Differential parity over APINotesFrameworkTest, the realistic sidecar the rest
// of test/APINotes tests against: several SwiftVersions blocks deliberately out
// of order, and the only checked-in input with Type:, ResultType: and
// Nullability: keys.
//
// Type:, ResultType: and Nullability: rewrite a declaration's type rather than
// attach an attribute, and the version-independent collapse does not cover
// them yet. The declarations they touch still diverge, and the name can too,
// because omit-needless-words reads parameter types. That divergence is checked
// in, so anything else diverging fails this test, and so does closing the gap.

// REQUIRES: objc_interop

// DEFINE: %{module} = APINotesFrameworkTest
// DEFINE: %{v} =
// DEFINE: %{emit} = %target-swift-emit-pcm %mcp_opt -module-name %{module} %S/../Inputs/custom-frameworks/APINotesFrameworkTest.framework/Modules/module.modulemap -F %S/../Inputs/custom-frameworks
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
// DEFINE:   not %diff %t/default-%{v}.txt %t/capture-4-at-%{v}.txt | tail -n +3 > %t/capture-4-at-%{v}.diff && \
// DEFINE:   %diff %S/Inputs/APINotesFrameworkTest-divergence/at-%{v}.diff %t/capture-4-at-%{v}.diff && \
// DEFINE:   %{print} -version-independent-apinotes -Xcc -fmodule-file=%{module}=%t/capture-6.pcm \
// DEFINE:     > %t/capture-6-at-%{v}.txt 2> %t/capture-6-at-%{v}.err && \
// DEFINE:   not grep error: %t/capture-6-at-%{v}.err && \
// DEFINE:   %diff %t/capture-4-at-%{v}.txt %t/capture-6-at-%{v}.txt

// RUN: %empty-directory(%t)

// Captured modules, built at the lowest and the highest Swift version.
// RUN: %{emit} -swift-version 4 -o %t/capture-4.pcm -Xfrontend -version-independent-apinotes
// RUN: %{emit} -swift-version 6 -o %t/capture-6.pcm -Xfrontend -version-independent-apinotes

// At each version, the default-mode module built at that version is the
// oracle. The captured module built at 4 differs from it exactly as
// Inputs/APINotesFrameworkTest-divergence/at-<version>.diff records, and the
// one built at 6 prints exactly as the one built at 4. The diff's first two
// lines name the files compared, by absolute path, so they are dropped.
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

// A non-empty interface is the control, so the comparison cannot pass on two
// modules that both failed to build.
// RUN: %FileCheck %s --check-prefix=NONEMPTY --input-file %t/capture-4-at-5.txt
// NONEMPTY: class TypeChanges
