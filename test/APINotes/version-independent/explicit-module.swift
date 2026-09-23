// One Clang module, built under -version-independent-apinotes, serving clients
// at every Swift version in an explicit module build.
//
// The part this exercises beyond the printed-interface parity tests is name
// lookup from source. That goes through the Swift lookup table stored in the
// module, whose keys are Swift names, and API notes change Swift names, so the
// table has to carry the names every version's client will look up.
//
// Each client reads the module built at every version. The expectations are
// the default mode's, and the last runs check them against the default mode
// itself, with one module per client version.

// REQUIRES: objc_interop

// DEFINE: %{v} =
// DEFINE: %{built} =
// DEFINE: %{prefix} =
// DEFINE: %{emit} = %target-swift-emit-pcm %mcp_opt -module-name VersionMatrix %S/Inputs/version-matrix/module.modulemap -swift-version %{v}
// DEFINE: %{client} = %target-swift-frontend -typecheck -verify -verify-ignore-unrelated -verify-additional-prefix %{prefix}- %s -swift-version %{v} -Xcc -fmodule-file=VersionMatrix=%t/%{built}.pcm
// DEFINE: %{check} = %{client} -version-independent-apinotes
// DEFINE: %{oracle} = %{emit} -o %t/default-%{v}.pcm && %{client}

// RUN: %empty-directory(%t)

// REDEFINE: %{v} = 4
// RUN: %{emit} -o %t/capture-4.pcm -Xfrontend -version-independent-apinotes
// REDEFINE: %{v} = 4.2
// RUN: %{emit} -o %t/capture-4.2.pcm -Xfrontend -version-independent-apinotes
// REDEFINE: %{v} = 5
// RUN: %{emit} -o %t/capture-5.pcm -Xfrontend -version-independent-apinotes
// REDEFINE: %{v} = 6
// RUN: %{emit} -o %t/capture-6.pcm -Xfrontend -version-independent-apinotes

// Each module, at each client version.
// REDEFINE: %{v} = 4
// REDEFINE: %{prefix} = v4
// REDEFINE: %{built} = capture-4
// RUN: %{check}
// REDEFINE: %{built} = capture-4.2
// RUN: %{check}
// REDEFINE: %{built} = capture-5
// RUN: %{check}
// REDEFINE: %{built} = capture-6
// RUN: %{check}

// REDEFINE: %{v} = 4.2
// REDEFINE: %{prefix} = v42
// REDEFINE: %{built} = capture-4
// RUN: %{check}
// REDEFINE: %{built} = capture-4.2
// RUN: %{check}
// REDEFINE: %{built} = capture-5
// RUN: %{check}
// REDEFINE: %{built} = capture-6
// RUN: %{check}

// REDEFINE: %{v} = 5
// REDEFINE: %{prefix} = v5
// REDEFINE: %{built} = capture-4
// RUN: %{check}
// REDEFINE: %{built} = capture-4.2
// RUN: %{check}
// REDEFINE: %{built} = capture-5
// RUN: %{check}
// REDEFINE: %{built} = capture-6
// RUN: %{check}

// REDEFINE: %{v} = 6
// REDEFINE: %{prefix} = v6
// REDEFINE: %{built} = capture-4
// RUN: %{check}
// REDEFINE: %{built} = capture-4.2
// RUN: %{check}
// REDEFINE: %{built} = capture-5
// RUN: %{check}
// REDEFINE: %{built} = capture-6
// RUN: %{check}

// The oracle: the default mode, one module per client version.
// REDEFINE: %{v} = 4
// REDEFINE: %{prefix} = v4
// REDEFINE: %{built} = default-4
// RUN: %{oracle}
// REDEFINE: %{v} = 4.2
// REDEFINE: %{prefix} = v42
// REDEFINE: %{built} = default-4.2
// RUN: %{oracle}
// REDEFINE: %{v} = 5
// REDEFINE: %{prefix} = v5
// REDEFINE: %{built} = default-5
// RUN: %{oracle}
// REDEFINE: %{v} = 6
// REDEFINE: %{prefix} = v6
// REDEFINE: %{built} = default-6
// RUN: %{oracle}

import VersionMatrix

func client() {
  // Unversioned names hold at every version.
  nameHeader_fromNotes()
  __privU()
  privHeaderUndoneU()

#if swift(>=6)
  nameU_unversioned()
  nameV42()
  nameV6_v6()
  nameU_v5() // expected-v6-error {{'nameU_v5()' has been renamed to 'nameU_unversioned()'}}
  nameV42_v42() // expected-v6-error {{'nameV42_v42()' has been renamed to 'nameV42()'}}
#elseif swift(>=5)
  nameU_v5()
  nameV42()
  nameV6_v6()
  // The unversioned name is not offered below the version that selects it.
  nameU_unversioned() // expected-v5-error {{cannot find 'nameU_unversioned' in scope}}
#elseif swift(>=4.2)
  nameU_v5()
  nameV42_v42()
  nameV6_v6()
  nameV42() // expected-v42-error {{'nameV42()' has been renamed to 'nameV42_v42()'}}
#else
  nameU_v5()
  nameV42_v42()
  nameV6_v6()
#endif

#if swift(>=4.2)
  nameV4()
  nameUV_unversioned()
  privV4()
  __privHeaderUndoneV4()
  _ = TopLevelTypes.self

  // The 4.0 slice's names survive only as compatibility aliases.
  nameV4_fromNotes() // expected-v42-error {{'nameV4_fromNotes()' has been renamed to 'nameV4()'}} expected-v5-error {{'nameV4_fromNotes()' has been renamed to 'nameV4()'}} expected-v6-error {{'nameV4_fromNotes()' has been renamed to 'nameV4()'}}

  // The 4.0 slice's visibility does not leak up.
  __privV4() // expected-v42-error {{cannot find '__privV4' in scope}} expected-v5-error {{cannot find '__privV4' in scope}} expected-v6-error {{cannot find '__privV4' in scope}}
#else
  nameV4_fromNotes()
  nameUV_v4()
  __privV4()
  privHeaderUndoneV4()

  nameUV_unversioned() // expected-v4-error {{'nameUV_unversioned()' has been renamed to 'nameUV_v4()'}}

  // The unversioned visibility does not apply below the 4.0 slice.
  privV4() // expected-v4-error {{cannot find 'privV4' in scope}}
#endif
}

struct TopLevelTypes {
  // Types have one canonical name, the newest version's, and older versions'
  // names are aliases of it.
  var wrapper: WrapperStructU
  var typedef: TypedefNameV4
  var protocolExistential: any MatrixProtocolU_unversioned
}
