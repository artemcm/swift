// The dependency scanner's Clang command line carries the API notes Swift
// version in both modes, and the capture flag only in version-independent mode.
//
// Both belong on a version-independent command line. The flag makes a module
// build capture every slice unapplied, and the version is the one a consumer of
// such a module collapses the slices at.

// REQUIRES: objc_interop

// RUN: %empty-directory(%t)

// RUN: %target-swift-frontend -scan-dependencies %s -o %t/legacy.json \
// RUN:   -I %S/Inputs/custom-modules -swift-version 5 \
// RUN:   -module-cache-path %t/mcp-legacy
// RUN: %validate-json %t/legacy.json

// RUN: %target-swift-frontend -scan-dependencies %s -o %t/capture.json \
// RUN:   -I %S/Inputs/custom-modules -swift-version 5 \
// RUN:   -module-cache-path %t/mcp-capture \
// RUN:   -version-independent-apinotes
// RUN: %validate-json %t/capture.json

// RUN: %FileCheck %s --check-prefix=LEGACY --input-file %t/legacy.json

// LEGACY: "-fapinotes-swift-version=5"

// RUN: %FileCheck %s --check-prefix=CAPTURE --input-file %t/capture.json
// CAPTURE-DAG: "-fapinotes-swift-version=5"
// CAPTURE-DAG: "-fswift-version-independent-apinotes"

// Legacy mode must not opt into the scheme.
// RUN: %FileCheck %s --check-prefix=LEGACY-NOT --input-file %t/legacy.json
// LEGACY-NOT-NOT: "-fswift-version-independent-apinotes"

import APINotesTest
