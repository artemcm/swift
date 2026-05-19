// Audit probe: foreign-to-native thunks for Clang-imported functions.
//
// emitGlobalFunctionRef synchronously emits these thunks via
// emitForeignToNativeThunk -> getFunction -> setDeclRef. The thunk's
// SILDeclRef has hasDecl()=true but the decl's parent source file is
// null (ClangModuleUnit), so discoverCallees' primary-file filter
// skips them.

// RUN: %target-swift-emit-sil -parse-as-library %s > %t.normal.sil
// RUN: %target-swift-emit-sil -parse-as-library -Xllvm -sil-on-demand-emission %s > %t.ondemand.sil
// RUN: diff %t.normal.sil %t.ondemand.sil

// REQUIRES: objc_interop

import Foundation

func usesImported(_ s: NSString) -> Int {
  return s.length
}
