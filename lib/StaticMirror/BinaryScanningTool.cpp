//===------------ BinaryScanningTool.cpp - Swift Compiler ----------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#include "swift/StaticMirror/BinaryScanningTool.h"
#include "swift/Basic/Unreachable.h"
#include "swift/Demangling/Demangler.h"
#include "swift/Reflection/ReflectionContext.h"
#include "swift/Reflection/TypeLowering.h"
#include "swift/Remote/CMemoryReader.h"
#include "swift/StaticMirror/ObjectFileContext.h"

#include "llvm/ADT/StringSet.h"
#include "llvm/Object/Archive.h"
#include "llvm/Object/MachOUniversal.h"

#include <sstream>

using namespace llvm::object;

namespace swift {
namespace static_mirror {

BinaryScanningTool::BinaryScanningTool(
    const std::vector<std::string> &binaryPaths, const std::string Arch) {
  for (const std::string &BinaryFilename : binaryPaths) {
    auto BinaryOwner = unwrap(createBinary(BinaryFilename));
    Binary *BinaryFile = BinaryOwner.getBinary();

    // The object file we are doing lookups in -- either the binary itself, or
    // a particular slice of a universal binary.
    std::unique_ptr<ObjectFile> ObjectOwner;
    const ObjectFile *O = dyn_cast<ObjectFile>(BinaryFile);
    if (!O) {
      auto Universal = cast<MachOUniversalBinary>(BinaryFile);
      ObjectOwner = unwrap(Universal->getMachOObjectForArch(Arch));
      O = ObjectOwner.get();
    }

    // Retain the objects that own section memory
    BinaryOwners.push_back(std::move(BinaryOwner));
    ObjectOwners.push_back(std::move(ObjectOwner));
    ObjectFiles.push_back(O);
  }
}

std::vector<std::string>
BinaryScanningTool::collectConformances(const std::vector<std::string> &protocolNames) {
  std::vector<std::string> conformances;
  auto context = makeReflectionContextForObjectFiles(ObjectFiles);
  using Runtime = External<RuntimeTarget<sizeof(uintptr_t)>>;
  using NativeReflectionContext = swift::reflection::ReflectionContext<Runtime>;
  auto reflectionContext = (NativeReflectionContext *)context.Owner.get();
  auto Error = reflectionContext->iterateConformances([&](auto Type, auto Proto) {
    llvm::dbgs() << "Type: " << Type << "\n";
    llvm::dbgs() << "Proto: " << Proto << "\n";
  });

  return conformances;
}

} // end namespace static_mirror
} // end namespace swift
