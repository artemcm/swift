// One Clang module, built once under -version-independent-apinotes, serving
// clients at two Swift versions in an explicit module build.
//
// Implicit-module tests cannot cover this, because every client builds its own
// copy of the module. The part it exercises is the Swift lookup table stored in
// the module. Its keys are Swift names, and API notes change Swift names, so the
// table has to carry the names every version's client will look up.
//
// The expectations are the default mode's, and the last runs check them against
// the default mode itself.

// REQUIRES: objc_interop

// RUN: %empty-directory(%t)

// RUN: %target-swift-emit-pcm -module-name VersionMatrix -o %t/VersionMatrix-4.pcm %S/Inputs/version-matrix/module.modulemap -swift-version 4 -Xfrontend -version-independent-apinotes
// RUN: %target-swift-emit-pcm -module-name VersionMatrix -o %t/VersionMatrix-5.pcm %S/Inputs/version-matrix/module.modulemap -swift-version 5 -Xfrontend -version-independent-apinotes

// Each module, at each client version.
// RUN: %target-swift-frontend -typecheck -verify -verify-ignore-unrelated -verify-additional-prefix v4- %s -swift-version 4 -version-independent-apinotes -module-cache-path %t/mcp -Xcc -fmodule-map-file=%S/Inputs/version-matrix/module.modulemap -Xcc -fmodule-file=VersionMatrix=%t/VersionMatrix-4.pcm
// RUN: %target-swift-frontend -typecheck -verify -verify-ignore-unrelated -verify-additional-prefix v5- %s -swift-version 5 -version-independent-apinotes -module-cache-path %t/mcp -Xcc -fmodule-map-file=%S/Inputs/version-matrix/module.modulemap -Xcc -fmodule-file=VersionMatrix=%t/VersionMatrix-4.pcm
// RUN: %target-swift-frontend -typecheck -verify -verify-ignore-unrelated -verify-additional-prefix v4- %s -swift-version 4 -version-independent-apinotes -module-cache-path %t/mcp -Xcc -fmodule-map-file=%S/Inputs/version-matrix/module.modulemap -Xcc -fmodule-file=VersionMatrix=%t/VersionMatrix-5.pcm
// RUN: %target-swift-frontend -typecheck -verify -verify-ignore-unrelated -verify-additional-prefix v5- %s -swift-version 5 -version-independent-apinotes -module-cache-path %t/mcp -Xcc -fmodule-map-file=%S/Inputs/version-matrix/module.modulemap -Xcc -fmodule-file=VersionMatrix=%t/VersionMatrix-5.pcm

// The runs above prove nothing if a client quietly built a module of its own.
// RUN: not ls %t/mcp/*/VersionMatrix-*.pcm

// The oracle: the default mode, one implicitly built module per client version.
// RUN: %target-swift-frontend -typecheck -verify -verify-ignore-unrelated -verify-additional-prefix v4- %s -swift-version 4 -I %S/Inputs/version-matrix -module-cache-path %t/mcp-legacy
// RUN: %target-swift-frontend -typecheck -verify -verify-ignore-unrelated -verify-additional-prefix v5- %s -swift-version 5 -I %S/Inputs/version-matrix -module-cache-path %t/mcp-legacy

import VersionMatrix

func client() {
  // Unversioned names hold at every version.
  nameHeader_fromNotes()
  __privU()
  privHeaderUndoneU()

#if swift(>=5)
  nameV4()
  nameUV_unversioned()
  privV4()
  __privHeaderUndoneV4()

  // The 4.0 slice's names survive only as compatibility aliases.
  nameV4_fromNotes() // expected-v5-error {{'nameV4_fromNotes()' has been renamed to 'nameV4()'}}
  nameUV_v4() // expected-v5-error {{'nameUV_v4()' has been renamed to 'nameUV_unversioned()'}}

  // The 4.0 slice's visibility does not leak up.
  __privV4() // expected-v5-error {{cannot find '__privV4' in scope}}
  privHeaderUndoneV4() // expected-v5-error {{cannot find 'privHeaderUndoneV4' in scope}}
#else
  nameV4_fromNotes()
  nameUV_v4()
  __privV4()
  privHeaderUndoneV4()

  nameUV_unversioned() // expected-v4-error {{'nameUV_unversioned()' has been renamed to 'nameUV_v4()'}}

  // The unversioned visibility does not apply below the 4.0 slice.
  privV4() // expected-v4-error {{cannot find 'privV4' in scope}}
  __privHeaderUndoneV4() // expected-v4-error {{cannot find '__privHeaderUndoneV4' in scope}}
#endif
}
