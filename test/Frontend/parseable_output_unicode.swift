// RUN: %target-swift-frontend -primary-file %s %S/Inputs/file🚀.swift -o %t.out -module-name parseable_output_unicode -emit-module -emit-module-path %t.swiftmodule -frontend-parseable-output 2>&1 | %FileCheck %s

// CHECK: {{[1-9][0-9]*}}
// CHECK-NEXT: {
// CHECK-NEXT:   "kind": "began",
// CHECK-NEXT:   "name": "compile",
