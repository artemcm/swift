// On demand, the function-only diagnostic pipeline links each function where
// the legacy pipeline runs MandatorySILLinker over the module
// (OnDemandSILLinker). Before it, the shared functions a body references, such
// as @_alwaysEmitIntoClient ones, stayed hidden_external declarations, and an
// object file referenced symbols that no library defines.

// RUN: %target-swift-frontend -emit-sil -parse-as-library -module-name M %s \
// RUN:   -Xllvm -sil-on-demand-emission | %FileCheck %s
// RUN: %target-swift-frontend -emit-ir -parse-as-library -module-name M %s \
// RUN:   -Xllvm -sil-on-demand-emission | %FileCheck --check-prefix=IR %s

// CHECK: sil shared {{.*}}@$ss27_finalizeUninitializedArrayySayxGABnlF : {{.*}} {
// CHECK: sil shared {{.*}}@$sSlsE3mapySayqd__Gqd__7ElementQzqd_0_YKXEqd_0_YKs5ErrorRd_0_r0_lF : {{.*}} {

// IR-DAG: define linkonce_odr hidden {{.*}}@"$ss27_finalizeUninitializedArrayySayxGABnlF"(
// IR-DAG: define linkonce_odr hidden {{.*}}@"$sSlsE3mapySayqd__Gqd__7ElementQzqd_0_YKXEqd_0_YKs5ErrorRd_0_r0_lF"(

func g() -> [Int] { return [1, 2, 3].map { $0 &* 2 } }
