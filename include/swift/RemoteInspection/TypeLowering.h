//===--- TypeLowering.h - Swift Type Lowering for Reflection ----*- C++ -*-===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//
// Implements logic for computing in-memory layouts from TypeRefs loaded from
// reflection metadata.
//
//===----------------------------------------------------------------------===//

#ifndef SWIFT_REFLECTION_TYPELOWERING_H
#define SWIFT_REFLECTION_TYPELOWERING_H

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/Support/Casting.h"
#include "swift/Remote/MetadataReader.h"
#include "swift/Remote/TypeInfoProvider.h"
#include "swift/RemoteInspection/BitMask.h"
#include "swift/RemoteInspection/DescriptorFinder.h"

#include <memory>

namespace swift {
namespace reflection {

using llvm::cast;
using llvm::dyn_cast;
using remote::RemoteRef;

class TypeConverter;
class TypeRef;
class TypeRefBuilder;
class BuiltinTypeDescriptor;

// Defined in TypeLowering.cpp, not public -- they're friends below
class LowerType;
class EnumTypeInfoBuilder;
class RecordTypeInfoBuilder;
class ExistentialTypeInfoBuilder;

enum class EnumKind : unsigned {
  // An enum with no payload cases. The record will have no fields, but
  // will have the correct size.
  NoPayloadEnum,

  // An enum with a single payload case and zero or more no-payload
  // cases.  The no-payload cases may be encoded with an extra tag
  // byte or as invalid payload values ("extra inhabitants").
  SinglePayloadEnum,

  // An enum with multiple payload cases and zero or more non-payload
  // cases.  The selector that indicates what case is currently active
  // may be encoded in unused "spare bits" common to all payloads and/or
  // may use a separate tag byte.
  MultiPayloadEnum,
};

enum class RecordKind : unsigned {
  Invalid,

  // A Swift tuple type.
  Tuple,

  // A Swift struct type.
  Struct,

  // A Swift-native function is always a function pointer followed by a
  // retainable, nullable context pointer.
  ThickFunction,

  // An existential is a three-word buffer followed by value metadata and
  // witness tables.
  OpaqueExistential,

  // A class existential is a retainable pointer followed by witness
  // tables.
  ClassExistential,

  // An existential metatype.
  ExistentialMetatype,

  // An error existential is a special kind of heap object, so is a retainable
  // pointer, with no witness tables.
  ErrorExistential,

  // A class instance layout, consisting of the stored properties of
  // one class, excluding superclasses.
  ClassInstance,

  // A closure context instance layout, consisting of the captured values.
  // For now, captured values do not retain their names.
  ClosureContext,
};

enum class ReferenceCounting : unsigned {
  Native,
  Unknown
};

enum class ReferenceKind : unsigned {
  Strong,
#define REF_STORAGE(Name, ...) Name,
#include "swift/AST/ReferenceStorage.def"
};

enum class TypeInfoKind : unsigned {
  Builtin,
  Record,
  Reference,
  Invalid,
  Enum,
  Array,
};

class TypeInfo {
  TypeInfoKind Kind;
  unsigned Size, Alignment, Stride, NumExtraInhabitants;
  bool BitwiseTakable;

public:
  TypeInfo(TypeInfoKind Kind,
           unsigned Size, unsigned Alignment,
           unsigned Stride, unsigned NumExtraInhabitants,
           bool BitwiseTakable)
    : Kind(Kind), Size(Size), Alignment(Alignment), Stride(Stride),
      NumExtraInhabitants(NumExtraInhabitants),
      BitwiseTakable(BitwiseTakable) {
    assert(Alignment > 0);
  }

  TypeInfo(): Kind(TypeInfoKind::Invalid), Size(0), Alignment(0), Stride(0),
              NumExtraInhabitants(0), BitwiseTakable(true) {
  }

  TypeInfoKind getKind() const { return Kind; }

  unsigned getSize() const { return Size; }
  unsigned getAlignment() const { return Alignment; }
  unsigned getStride() const { return Stride; }
  unsigned getNumExtraInhabitants() const { return NumExtraInhabitants; }
  bool isBitwiseTakable() const { return BitwiseTakable; }

  void dump() const;
  void dump(std::ostream &stream, unsigned Indent = 0) const;

  // Using the provided reader, inspect our value.
  // Return false if we can't inspect value.
  // Set *inhabitant to <0 if the value is valid (not an XI)
  // Else set *inhabitant to the XI value (counting from 0)
  virtual bool readExtraInhabitantIndex(remote::MemoryReader &reader,
                                        remote::RemoteAddress address,
                                        int *index) const {
    return false;
  }

  // Calculate and return the spare bit mask for this type
  virtual BitMask getSpareBits(TypeConverter &TC, bool &hasAddrOnly) const {
    return BitMask::zeroMask(getSize());
  }

  virtual ~TypeInfo() { }
};

struct FieldInfo {
  std::string Name;
  unsigned Offset;
  int Value;
  const TypeRef *TR;
  const TypeInfo &TI;
};

/// Builtins and (opaque) imported value types
class BuiltinTypeInfo : public TypeInfo {
  std::string Name;

public:
  explicit BuiltinTypeInfo(TypeRefBuilder &builder,
                           BuiltinTypeDescriptorBase &descriptor);

  explicit BuiltinTypeInfo(unsigned Size, unsigned Alignment, unsigned Stride,
                           unsigned NumExtraInhabitants, bool BitwiseTakable);
  /// Construct an empty builtin type info.
  BuiltinTypeInfo()
      : TypeInfo(TypeInfoKind::Builtin,
                 /*Size=*/0,
                 /*Alignment=*/1,
                 /*Stride=*/1,
                 /*ExtraInhabitants=*/0,
                 /*BitwiseTakable=*/true),
        Name("") {}

  const std::string &getMangledTypeName() const {
    return Name;
  }

  bool readExtraInhabitantIndex(remote::MemoryReader &reader,
                                remote::RemoteAddress address,
                                int *extraInhabitantIndex) const override;

  BitMask getSpareBits(TypeConverter &TC, bool &hasAddrOnly) const override;

  static bool classof(const TypeInfo *TI) {
    return TI->getKind() == TypeInfoKind::Builtin;
  }
};

/// Class instances, structs, tuples
class RecordTypeInfo : public TypeInfo {
  RecordKind SubKind;
  std::vector<FieldInfo> Fields;

public:
  RecordTypeInfo(unsigned Size, unsigned Alignment,
                 unsigned Stride, unsigned NumExtraInhabitants,
                 bool BitwiseTakable,
                 RecordKind SubKind, const std::vector<FieldInfo> &Fields)
    : TypeInfo(TypeInfoKind::Record, Size, Alignment, Stride,
               NumExtraInhabitants, BitwiseTakable),
      SubKind(SubKind), Fields(Fields) {}

  RecordKind getRecordKind() const { return SubKind; }
  unsigned getNumFields() const { return Fields.size(); }
  const std::vector<FieldInfo> &getFields() const { return Fields; }

  bool readExtraInhabitantIndex(remote::MemoryReader &reader,
                                remote::RemoteAddress address,
                                int *index) const override;

  BitMask getSpareBits(TypeConverter &TC, bool &hasAddrOnly) const override;

  static bool classof(const TypeInfo *TI) {
    return TI->getKind() == TypeInfoKind::Record;
  }
};

/// Enums
class EnumTypeInfo : public TypeInfo {
  EnumKind SubKind;
  std::vector<FieldInfo> Cases;

protected:
  EnumTypeInfo(unsigned Size, unsigned Alignment,
               unsigned Stride, unsigned NumExtraInhabitants,
               bool BitwiseTakable,
               EnumKind SubKind, const std::vector<FieldInfo> &Cases)
    : TypeInfo(TypeInfoKind::Enum, Size, Alignment, Stride,
               NumExtraInhabitants, BitwiseTakable),
      SubKind(SubKind), Cases(Cases) {}

public:
  EnumKind getEnumKind() const { return SubKind; }
  const std::vector<FieldInfo> &getCases() const { return Cases; }
  unsigned getNumCases() const { return Cases.size(); }
  unsigned getNumPayloadCases() const {
    auto Cases = getCases();
    return std::count_if(Cases.begin(), Cases.end(),
                         [](const FieldInfo &Case){return Case.TR != 0;});
  }
  unsigned getNumNonEmptyPayloadCases() const {
    auto Cases = getCases();
    return std::count_if(Cases.begin(), Cases.end(),
                         [](const FieldInfo &Case){
                           // For our purposes here, assume any case
                           // with invalid (missing) typeinfo is non-empty
                           return Case.TR != 0
                             && (Case.TI.getKind() == TypeInfoKind::Invalid
                                 || Case.TI.getSize() > 0);
                         });
  }
  // Size of the payload area.
  unsigned getPayloadSize() const {
    return EnumTypeInfo::getPayloadSizeForCases(Cases);
  }

  static unsigned getPayloadSizeForCases(const std::vector<FieldInfo> &Cases) {
    unsigned size = 0;
    for (auto Case : Cases) {
      if (Case.TR != 0 && Case.TI.getSize() > size) {
        size = Case.TI.getSize();
      }
    }
    return size;
  }

  // Returns true if this enum is `Optional`
  // (This was factored out of a piece of code that was just
  // checking the EnumKind.  This is vastly better than that,
  // but could probably be improved further.)
  bool isOptional() const {
    return
      SubKind == EnumKind::SinglePayloadEnum
      && Cases.size() == 2
      && Cases[0].Name == "some"
      && Cases[1].Name == "none";
  }

  virtual bool projectEnumValue(remote::MemoryReader &reader,
                                remote::RemoteAddress address,
                                int *CaseIndex) const = 0;

  static bool classof(const TypeInfo *TI) {
    return TI->getKind() == TypeInfoKind::Enum;
  }
};

/// References to classes, closure contexts and anything else with an
/// 'isa' pointer
class ReferenceTypeInfo : public TypeInfo {
  ReferenceKind SubKind;
  ReferenceCounting Refcounting;

public:
  ReferenceTypeInfo(unsigned Size, unsigned Alignment,
                    unsigned Stride, unsigned NumExtraInhabitants,
                    bool BitwiseTakable, ReferenceKind SubKind,
                    ReferenceCounting Refcounting)
    : TypeInfo(TypeInfoKind::Reference, Size, Alignment, Stride,
               NumExtraInhabitants, BitwiseTakable),
      SubKind(SubKind), Refcounting(Refcounting) {}

  ReferenceKind getReferenceKind() const {
    return SubKind;
  }

  ReferenceCounting getReferenceCounting() const {
    return Refcounting;
  }

  bool readExtraInhabitantIndex(remote::MemoryReader &reader,
                                remote::RemoteAddress address,
                                int *extraInhabitantIndex) const override {
    if (getNumExtraInhabitants() == 0) {
      *extraInhabitantIndex = -1;
      return true;
    }
    return reader.readHeapObjectExtraInhabitantIndex(address, extraInhabitantIndex);
  }

  BitMask getSpareBits(TypeConverter &TC, bool &hasAddrOnly) const override;

  static bool classof(const TypeInfo *TI) {
    return TI->getKind() == TypeInfoKind::Reference;
  }
};

/// Array based layouts like Builtin.FixedArray<N, T>
class ArrayTypeInfo : public TypeInfo {
  const TypeInfo *ElementTI;

public:
  explicit ArrayTypeInfo(intptr_t size, const TypeInfo *elementTI);

  bool readExtraInhabitantIndex(remote::MemoryReader &reader,
                                remote::RemoteAddress address,
                                int *extraInhabitantIndex) const override;

  BitMask getSpareBits(TypeConverter &TC, bool &hasAddrOnly) const override;
  const TypeInfo *getElementTypeInfo() const { return ElementTI; }
  static bool classof(const TypeInfo *TI) {
    return TI->getKind() == TypeInfoKind::Array;
  }
};

/// This class owns the memory for all TypeInfo instances that it vends.
class TypeConverter {
  TypeRefBuilder &Builder;
  std::vector<std::unique_ptr<const TypeInfo>> Pool;
  using KeyT = std::pair<const TypeRef *, remote::TypeInfoProvider::IdType>;
  llvm::DenseMap<KeyT, const TypeInfo *> Cache;
  llvm::DenseSet<const TypeRef *> RecursionCheck;
  llvm::DenseMap<std::pair<unsigned, unsigned>,
                 const ReferenceTypeInfo *> ReferenceCache;

  const TypeRef *RawPointerTR = nullptr;
  const TypeRef *NativeObjectTR = nullptr;
  const TypeRef *UnknownObjectTR = nullptr;
  const TypeRef *ThinFunctionTR = nullptr;
  const TypeRef *AnyMetatypeTR = nullptr;

  const TypeInfo *ThinFunctionTI = nullptr;
  const TypeInfo *ThickFunctionTI = nullptr;
  const TypeInfo *AnyMetatypeTI = nullptr;
  const TypeInfo *DefaultActorStorageTI = nullptr;
  const TypeInfo *EmptyTI = nullptr;

  /// Used for lightweight error handling. We don't have access to
  /// llvm::Expected<> here, so TypeConverter just stores a pointer to the last
  /// encountered error instead that is stored in the cache.
  using TCError = std::pair<const char *, const TypeRef *>;
  TCError LastError = {nullptr, nullptr};
  std::unique_ptr<llvm::DenseMap<KeyT, TCError>> ErrorCache;

public:
  explicit TypeConverter(TypeRefBuilder &Builder) : Builder(Builder) {}

  /// Called by LLDB.
  void enableErrorCache() {
    ErrorCache = std::make_unique<llvm::DenseMap<KeyT, TCError>>();
  }
  void setError(const char *msg, const TypeRef *TR) { LastError = {msg, TR}; }

  /// Retreive the error and reset it.
  std::string takeLastError();

  TypeRefBuilder &getBuilder() { return Builder; }

  /// Tests if the type is concrete enough that its size is known.
  /// For example, a bound generic class is fixed size even if some
  /// of the generic argument types contain generic parameters.
  bool hasFixedSize(const TypeRef *TR);

  /// Returns layout information for a value of the given type.
  /// For a class, this returns the lowering of the reference value.
  ///
  /// The type must either be concrete, or at least fixed-size, as
  /// determined by the isFixedSize() predicate.
  const TypeInfo *getTypeInfo(const TypeRef *TR,
                              remote::TypeInfoProvider *externalInfo);

  /// Returns layout information for an instance of the given
  /// class.
  ///
  /// Not cached.
  const RecordTypeInfo *
  getClassInstanceTypeInfo(const TypeRef *TR, unsigned start,
                           remote::TypeInfoProvider *ExternalTypeInfo);

  unsigned targetPointerSize() {
    auto *rawPointerTI = getTypeInfo(getRawPointerTypeRef(), nullptr);
    return rawPointerTI->getSize();
  }

private:
  friend class swift::reflection::LowerType;
  friend class swift::reflection::EnumTypeInfoBuilder;
  friend class swift::reflection::RecordTypeInfoBuilder;
  friend class swift::reflection::ExistentialTypeInfoBuilder;

  const ReferenceTypeInfo *
  getReferenceTypeInfo(ReferenceKind Kind,
                       ReferenceCounting Refcounting);

  /// TypeRefs for special types for which we need to know the layout
  /// intrinsically in order to layout anything else.
  ///
  /// IRGen emits BuiltinTypeDescriptors for these when compiling the
  /// standard library.
  const TypeRef *getRawPointerTypeRef();
  const TypeRef *getNativeObjectTypeRef();
  const TypeRef *getUnknownObjectTypeRef();
  const TypeRef *getThinFunctionTypeRef();
  const TypeRef *getAnyMetatypeTypeRef();

  const TypeInfo *getThinFunctionTypeInfo();
  const TypeInfo *getThickFunctionTypeInfo();
  const TypeInfo *getAnyMetatypeTypeInfo();
  const TypeInfo *getDefaultActorStorageTypeInfo();
  const TypeInfo *getRawUnsafeContinuationTypeInfo();
  const TypeInfo *getEmptyTypeInfo();

  template <typename TypeInfoTy, typename... Args>
  const TypeInfoTy *makeTypeInfo(Args &&... args) {
    auto TI = new TypeInfoTy(::std::forward<Args>(args)...);
    Pool.push_back(std::unique_ptr<const TypeInfo>(TI));
    return TI;
  }
};

/// Utility class for performing universal layout for types such as
/// tuples, structs, thick functions, etc.
class RecordTypeInfoBuilder {
  TypeConverter &TC;
  unsigned Size, Alignment, NumExtraInhabitants;
  bool BitwiseTakable;
  RecordKind Kind;
  std::vector<FieldInfo> Fields;
  bool Empty;
  bool Invalid;

public:
  RecordTypeInfoBuilder(TypeConverter &TC, RecordKind Kind)
    : TC(TC), Size(0), Alignment(1), NumExtraInhabitants(0),
      BitwiseTakable(true), Kind(Kind), Empty(true), Invalid(false) {}

  bool isInvalid() const { return Invalid; }
  void markInvalid(const char *msg, const TypeRef *TR = nullptr) {
    Invalid = true;
    TC.setError(msg, TR);
  }

  unsigned addField(unsigned fieldSize, unsigned fieldAlignment,
                    unsigned numExtraInhabitants,
                    bool bitwiseTakable);

  // Add a field of a record type, such as a struct.
  void addField(const std::string &Name, const TypeRef *TR,
                remote::TypeInfoProvider *ExternalTypeInfo);

  const RecordTypeInfo *build();

  unsigned getNumFields() const {
    return Fields.size();
  }

  unsigned getFieldOffset(unsigned Index) const {
    return Fields[Index].Offset;
  }
};

}
}

#endif
