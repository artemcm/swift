// D10: a function declared without a body, such as an @_silgen_name
// declaration of a C function, has nothing to emit. On demand, a body that
// called one made the coordinator queue it, and emitting it aborted.

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M %s \
// RUN:   -o %t.legacy.sil
// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M %s \
// RUN:   -o %t.ondemand.sil -sil-verify-all -Xllvm -sil-on-demand-emission
// RUN: diff %t.legacy.sil %t.ondemand.sil
// RUN: %FileCheck %s < %t.ondemand.sil

@_silgen_name("exit") func exit(_: Int32) -> Never

// CHECK-LABEL: sil hidden @$s1M4stopyyF :
// CHECK: function_ref @exit
func stop() { exit(0) }

// CHECK: {{^}}sil hidden_external @exit : $@convention(thin) (Int32) -> Never{{$}}
