//===--- MemoryReader.h - Abstract access to remote memory ------*- C++ -*-===//
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
//  This file declares an abstract interface for working with the memory
//  of a remote process.
//
//===----------------------------------------------------------------------===//

#ifndef SWIFT_REMOTE_MEMORYREADER_H
#define SWIFT_REMOTE_MEMORYREADER_H

#include "swift/Remote/RemoteAddress.h"
#include "swift/SwiftRemoteMirror/MemoryReaderInterface.h"
#include <optional>

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <memory>
#include <string>
#include <tuple>

namespace swift {
namespace remote {

/// An abstract interface for reading memory.
///
/// This abstraction presents memory as if it were a read-only
/// representation of the address space of a remote process.
class MemoryReader {
  uint8_t cachedPointerSize = 0;
  uint8_t cachedSizeSize = 0;
  uint64_t cachedPtrAuthMask = 0;
  uint8_t cachedObjCReservedLowBits = 0xff;
  uint64_t cachedLeastValidPointerValue = 0;
  uint8_t cachedObjCInteropIsEnabled = 0xff;

protected:
  virtual bool queryDataLayout(DataLayoutQueryType type, void *inBuffer,
                               void *outBuffer) = 0;

public:
  std::optional<uint8_t> getPointerSize() {
    if (cachedPointerSize == 0) {
      if (!queryDataLayout(DLQ_GetPointerSize, nullptr, &cachedPointerSize))
        return std::nullopt;
    }
    return cachedPointerSize;
  }

  std::optional<uint8_t> getSizeSize() {
    if (cachedSizeSize == 0) {
      if (!queryDataLayout(DLQ_GetSizeSize, nullptr, &cachedSizeSize))
        return std::nullopt;
    }
    return cachedSizeSize;
  }

  std::optional<uint64_t> getPtrAuthMask() {
    if (cachedPtrAuthMask == 0) {
      auto ptrSize = getPointerSize();
      if (!ptrSize)
        return std::nullopt;

      if (ptrSize.value() == sizeof(uint64_t)) {
        if (!queryDataLayout(DLQ_GetPtrAuthMask, nullptr, &cachedPtrAuthMask))
          return std::nullopt;
      } else if (ptrSize.value() == sizeof(uint32_t)) {
        uint32_t mask;
        if (!queryDataLayout(DLQ_GetPtrAuthMask, nullptr, &mask))
          return std::nullopt;
        cachedPtrAuthMask = mask;
      }
    }
    return cachedPtrAuthMask;
  }

  std::optional<uint8_t> getObjCReservedLowBits() {
    if (cachedObjCReservedLowBits == 0xff) {
      if (!queryDataLayout(DLQ_GetObjCReservedLowBits, nullptr,
                           &cachedObjCReservedLowBits))
        return std::nullopt;
    }
    return cachedObjCReservedLowBits;
  }

  std::optional<uint64_t> getLeastValidPointerValue() {
    if (cachedLeastValidPointerValue == 0) {
      if (!queryDataLayout(DLQ_GetLeastValidPointerValue, nullptr,
                           &cachedLeastValidPointerValue))
        return std::nullopt;
    }
    return cachedLeastValidPointerValue;
  }

  std::optional<bool> getObjCInteropIsEnabled() {
    if (cachedObjCInteropIsEnabled == 0xff) {
      if (!queryDataLayout(DLQ_GetObjCInteropIsEnabled, nullptr,
                           &cachedObjCInteropIsEnabled))
        return std::nullopt;
    }
    return cachedObjCInteropIsEnabled;
  }

  /// A convenient name for the return type from readBytes.
  using ReadBytesResult =
      std::unique_ptr<const void, std::function<void(const void *)>>;

  template <typename T>
  using ReadObjResult =
      std::unique_ptr<const T, std::function<void(const void *)>>;

  /// Look up the given public symbol name in the remote process.
  virtual RemoteAddress getSymbolAddress(const std::string &name) = 0;

  /// Attempts to read a C string from the given address in the remote
  /// process.
  ///
  /// Returns false if the operation failed.
  virtual bool readString(RemoteAddress address, std::string &dest) = 0;

  /// Attempts to read a remote address from the given address in the remote
  /// process.
  ///
  /// Returns false if the operator failed.
  template <typename IntegerType>
  bool readRemoteAddress(RemoteAddress address, RemoteAddress &out) {
    constexpr std::size_t integerSize = sizeof(IntegerType);
    static_assert((integerSize == 4 || integerSize == 8) &&
                  "Only 32 or 64 bit architectures are supported!");
    return readRemoteAddressImpl(address, out, integerSize);
  }

  /// Attempts to read an integer from the given address in the remote
  /// process.
  ///
  /// Returns false if the operation failed.
  template <typename IntegerType>
  bool readInteger(RemoteAddress address, IntegerType *dest) {
    static_assert(!std::is_same<RemoteAddress, IntegerType>(),
                  "RemoteAddress cannot be read in directly, use "
                  "readRemoteAddress instead.");

    return readBytes(address, reinterpret_cast<uint8_t*>(dest),
                     sizeof(IntegerType));
  }

  /// Attempts to read an integer of the specified size from the given
  /// address in the remote process.  Following `storeEnumElement`
  /// in EnumImpl.h, this reads arbitrary-size integers by ignoring
  /// high-order bits that are outside the range of `IntegerType`.
  ///
  /// Returns false if the operation failed.
  template <typename IntegerType>
  bool readInteger(RemoteAddress address, size_t bytes, IntegerType *dest) {
    *dest = 0;
    size_t readSize = std::min(bytes, sizeof(IntegerType));
    // FIXME: Assumes host and target have the same endianness.
    // TODO: Query DLQ for endianness of target, compare to endianness of host.
#if defined(__BIG_ENDIAN__)
    // Read low-order bits of source ...
    if (!readBytes(address + (bytes - readSize), (uint8_t *)dest, readSize)) {
      return false;
    }
    // ... align result to low-order bits of *dest
    *dest >>= 8 * (sizeof(IntegerType) - readSize);
#else
    // Read from low-order bytes of integer
    if (!readBytes(address, (uint8_t *)dest, readSize)) {
      return false;
    }
#endif
    return true;
  }

  template <typename T>
  ReadObjResult<T> readObj(RemoteAddress address) {
    auto bytes = readBytes(address, sizeof(T));
    auto deleter = bytes.get_deleter();
    auto ptr = bytes.get();
    bytes.release();
    return ReadObjResult<T>(reinterpret_cast<const T *>(ptr), deleter);
  }

  /// Attempts to read 'size' bytes from the given address in the remote process.
  ///
  /// Returns a pointer to the requested data and a function that must be called to
  /// free that data when done. The pointer will be NULL if the operation failed.
  ///
  /// NOTE: subclasses MUST override at least one of the readBytes functions. The default
  /// implementation calls through to the other one.
  virtual ReadBytesResult
  readBytes(RemoteAddress address, uint64_t size) {
    auto *Buf = malloc(size);
    if (!Buf)
      return ReadBytesResult{};
    ReadBytesResult Result(Buf, [](const void *ptr) {
      free(const_cast<void *>(ptr));
    });
    bool success = readBytes(address, reinterpret_cast<uint8_t *>(Buf), size);
    if (!success) {
      Result.reset();
    }
    return Result;
  }

  /// Attempts to read 'size' bytes from the given address in the
  /// remote process.
  ///
  /// Returns false if the operation failed.
  ///
  /// NOTE: subclasses MUST override at least one of the readBytes functions. The default
  /// implementation calls through to the other one.
  virtual bool readBytes(RemoteAddress address, uint8_t *dest, uint64_t size) {
    auto Ptr = readBytes(address, size);
    if (!Ptr)
      return false;
    
    memcpy(dest, Ptr.get(), size);
    return true;
  }
  
  /// Attempts to resolve a pointer value read from the given remote address.
  virtual RemoteAbsolutePointer resolvePointer(RemoteAddress address,
                                               uint64_t readValue) {
    // Default implementation returns the read value as is.
    return RemoteAbsolutePointer(
        RemoteAddress(readValue, address.getAddressSpace()));
  }

  /// Performs the inverse operation of \ref resolvePointer.
  /// A use-case for this is to turn file addresses into in-process addresses.
  virtual std::optional<RemoteAddress>
  resolveRemoteAddress(RemoteAddress address) const {
    return std::nullopt;
  }

  virtual std::optional<RemoteAbsolutePointer>
  resolvePointerAsSymbol(RemoteAddress address) {
    return std::nullopt;
  }

  /// Lookup a symbol for the given remote address.
  virtual RemoteAbsolutePointer getSymbol(RemoteAddress address) {
    if (auto symbol = resolvePointerAsSymbol(address))
      return *symbol;
    return RemoteAbsolutePointer(address);
  }

  /// Lookup a dynamic symbol name (ie dynamic loader binding) for the given
  /// remote address. Note: An address can be referenced by both dynamic and
  /// regular symbols, this function must return a dynamic symbol only.
  virtual RemoteAbsolutePointer getDynamicSymbol(RemoteAddress address) {
    return nullptr;
  }

  /// Attempt to read and resolve a pointer value at the given remote address.
  std::optional<RemoteAbsolutePointer> readPointer(RemoteAddress address,
                                                   unsigned pointerSize) {
    // First, try to lookup the pointer as a dynamic symbol (binding), as
    // reading memory may potentially be expensive.
    if (auto dynamicSymbol = getDynamicSymbol(address))
      return dynamicSymbol;

    auto result = readBytes(address, pointerSize);
    if (!result)
      return std::nullopt;

    uint64_t pointerData;
    if (pointerSize == 4) {
      uint32_t theData;
      memcpy(&theData, result.get(), 4);
      pointerData = theData;
    } else if (pointerSize == 8) {
      memcpy(&pointerData, result.get(), 8);
    } else {
      return std::nullopt;
    }
    
    return resolvePointer(address, pointerData);
  }

  // Parse extra inhabitants stored in a pointer.
  // Sets *extraInhabitant to -1 if the pointer at this address
  // is actually a valid pointer.
  // Otherwise, it sets *extraInhabitant to the inhabitant
  // index (counting from 0).
  bool readHeapObjectExtraInhabitantIndex(RemoteAddress address,
                                          int *extraInhabitantIndex) {
    auto PointerSize = getPointerSize();
    auto LeastValidPointerValue = getLeastValidPointerValue();
    auto ObjCReservedLowBits = getObjCReservedLowBits();

    if (!PointerSize || !LeastValidPointerValue || !ObjCReservedLowBits)
      return false;

    uint64_t RawPointerValue;
    if (!readInteger(address, PointerSize.value(), &RawPointerValue)) {
      return false;
    }
    if (RawPointerValue >= LeastValidPointerValue.value()) {
      *extraInhabitantIndex = -1; // Valid value, not an XI
    } else {
      *extraInhabitantIndex = (RawPointerValue >> ObjCReservedLowBits.value());
    }
    return true;
  }

  bool readFunctionPointerExtraInhabitantIndex(RemoteAddress address,
                                               int *extraInhabitantIndex) {
    auto PointerSize = getPointerSize();
    auto LeastValidPointerValue = getLeastValidPointerValue();
    if (!PointerSize || !LeastValidPointerValue)
      return false;

    uint64_t RawPointerValue;
    if (!readInteger(address, PointerSize.value(), &RawPointerValue)) {
      return false;
    }
    if (RawPointerValue >= LeastValidPointerValue.value()) {
      *extraInhabitantIndex = -1; // Valid value, not an XI
    } else {
      *extraInhabitantIndex = RawPointerValue;
    }
    return true;
  }

  virtual ~MemoryReader() = default;

protected:
  /// Implementation detail of remoteRemoteAddress. This exists because
  /// templated functions cannot be virtual.
  ///
  /// Attempts to read a remote address of a given size from the given address
  /// in the remote process.
  ///
  /// Returns false if the operator failed.
  virtual bool readRemoteAddressImpl(RemoteAddress address, RemoteAddress &out,
                                     std::size_t integerSize) {
    assert((integerSize == 4 || integerSize == 8) &&
           "Only 32 or 64 bit architectures are supported!");
    if (integerSize == 4) {
      uint32_t buf;
      if (!readBytes(address, reinterpret_cast<uint8_t *>(&buf), integerSize))
        return false;
      out = RemoteAddress(buf, address.getAddressSpace());
      return true;
    }
    if (integerSize == 8) {
      uint64_t buf;
      if (!readBytes(address, reinterpret_cast<uint8_t *>(&buf), integerSize))
        return false;
      out = RemoteAddress(buf, address.getAddressSpace());
      return true;
    }
    return false;
  }
};

} // end namespace remote
} // end namespace swift

#endif // SWIFT_REFLECTION_READER_H

