// The dependency scanner must stop putting the API notes Swift version on the
// Clang command line in version-independent mode, and must keep putting it
// there in legacy mode.
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
// CAPTURE-NOT: "-fapinotes-swift-version=
// CAPTURE: "-fswift-version-independent-apinotes"
// CAPTURE-NOT: "-fapinotes-swift-version=

import APINotesTest
