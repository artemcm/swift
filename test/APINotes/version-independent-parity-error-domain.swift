// Differential parity for NSErrorDomain, which needs Foundation and so needs a
// module of its own: importing Foundation into a shared API notes fixture would
// rewrite every other cell's expected output.
//
// Worth its own file because the domain decides the imported *shape*, not just an
// attribute. With it the enum becomes an error wrapper struct plus a nested Code;
// without it the enum keeps its C name and imports as a plain type. Losing the
// domain therefore renames the declaration, and the classification is computed
// during name import and then cached, so a miss there is not recoverable later.
//
// The regression this guards: classifyEnum read NSErrorDomainAttr straight off
// the declaration. Under version-independent API notes the annotation sits in a
// versioned wrapper at that point, so a domain that only a sidecar supplied went
// missing and the declaration disappeared from the interface entirely.

// REQUIRES: objc_interop

// RUN: %empty-directory(%t)

// Swift 4: the unversioned and the 4.0 slice both apply.
// RUN: %target-swift-ide-test -print-module -module-to-print=ErrorDomainMatrix -source-filename %s -I %S/Inputs/error-domain-matrix -swift-version 4 -module-cache-path %t/mcp-legacy-4 > %t/legacy-4.txt
// RUN: %target-swift-ide-test -print-module -module-to-print=ErrorDomainMatrix -source-filename %s -I %S/Inputs/error-domain-matrix -swift-version 4 -module-cache-path %t/mcp-capture-4 -version-independent-apinotes > %t/capture-4.txt
// RUN: %diff -u %t/legacy-4.txt %t/capture-4.txt

// Swift 5: the 4.0 slice must not apply, so ErrV4Code keeps its C name.
// RUN: %target-swift-ide-test -print-module -module-to-print=ErrorDomainMatrix -source-filename %s -I %S/Inputs/error-domain-matrix -swift-version 5 -module-cache-path %t/mcp-legacy-5 > %t/legacy-5.txt
// RUN: %target-swift-ide-test -print-module -module-to-print=ErrorDomainMatrix -source-filename %s -I %S/Inputs/error-domain-matrix -swift-version 5 -module-cache-path %t/mcp-capture-5 -version-independent-apinotes > %t/capture-5.txt
// RUN: %diff -u %t/legacy-5.txt %t/capture-5.txt

// Swift 6
// RUN: %target-swift-ide-test -print-module -module-to-print=ErrorDomainMatrix -source-filename %s -I %S/Inputs/error-domain-matrix -swift-version 6 -module-cache-path %t/mcp-legacy-6 > %t/legacy-6.txt
// RUN: %target-swift-ide-test -print-module -module-to-print=ErrorDomainMatrix -source-filename %s -I %S/Inputs/error-domain-matrix -swift-version 6 -module-cache-path %t/mcp-capture-6 -version-independent-apinotes > %t/capture-6.txt
// RUN: %diff -u %t/legacy-6.txt %t/capture-6.txt

// The controls. A diff alone would also pass on two modules that both failed to
// build.
// RUN: %FileCheck %s --check-prefix=V4 < %t/capture-4.txt
// RUN: %FileCheck %s --check-prefix=V5 < %t/capture-5.txt

// A sidecar-only domain has to produce the wrapper, and the enum's name loses
// the 'Code' suffix to it.
// V4-DAG: struct ErrU : _BridgedStoredNSError
// V4-DAG: struct ErrV4 : _BridgedStoredNSError
// A sidecar domain replaces one written in the header.
// V4-DAG: struct ErrHeader : _BridgedStoredNSError
// No notes entry, so no wrapper.
// V4-NOT: struct ErrUntouched :

// At 5.0 the 4.0 slice is out of range, so this one keeps its C name and shape.
// V5-DAG: struct ErrV4Code
// V5-DAG: struct ErrU : _BridgedStoredNSError
