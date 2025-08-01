//===--- Registration.swift - register SIL classes ------------------------===//
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

import Basic
import SILBridging

public func registerSIL() {
  registerSILClasses()
  registerUtilities()
}

private func register<T: AnyObject>(_ cl: T.Type) {
  "\(cl)"._withBridgedStringRef { nameStr in
    let metatype = unsafeBitCast(cl, to: SwiftMetatype.self)
    registerBridgedClass(nameStr, metatype)
  }
}

private func registerSILClasses() {
  Function.register()
  register(BasicBlock.self)
  register(GlobalVariable.self)

  register(MultipleValueInstructionResult.self)

  register(Undef.self)
  register(PlaceholderValue.self)

  register(FunctionArgument.self)
  register(Argument.self)

  register(StoreInst.self)
  register(StoreWeakInst.self)
  register(StoreUnownedInst.self)
  register(StoreBorrowInst.self)
  register(AssignInst.self)
  register(AssignByWrapperInst.self)
  register(AssignOrInitInst.self)
  register(CopyAddrInst.self)
  register(ExplicitCopyAddrInst.self)
  register(EndAccessInst.self)
  register(BeginUnpairedAccessInst.self)
  register(EndUnpairedAccessInst.self)
  register(EndBorrowInst.self)
  register(CondFailInst.self)
  register(IncrementProfilerCounterInst.self)
  register(MarkFunctionEscapeInst.self)
  register(HopToExecutorInst.self)
  register(MarkUninitializedInst.self)
  register(FixLifetimeInst.self)
  register(DebugValueInst.self)
  register(DebugStepInst.self)
  register(SpecifyTestInst.self)
  register(UnconditionalCheckedCastAddrInst.self)
  register(BeginDeallocRefInst.self)
  register(EndInitLetRefInst.self)
  register(BindMemoryInst.self)
  register(RebindMemoryInst.self)
  register(EndApplyInst.self)
  register(AbortApplyInst.self)
  register(StrongRetainInst.self)
  register(StrongRetainUnownedInst.self)
  register(UnownedRetainInst.self)
  register(UnmanagedRetainValueInst.self)
  register(RetainValueInst.self)
  register(StrongReleaseInst.self)
  register(RetainValueAddrInst.self)
  register(ReleaseValueAddrInst.self)
  register(UnownedReleaseInst.self)
  register(UnmanagedReleaseValueInst.self)
  register(AutoreleaseValueInst.self)
  register(UnmanagedAutoreleaseValueInst.self)
  register(ReleaseValueInst.self)
  register(DestroyValueInst.self)
  register(DestroyAddrInst.self)
  register(EndLifetimeInst.self)
  register(ExtendLifetimeInst.self)
  register(StrongCopyUnownedValueInst.self)
  register(StrongCopyUnmanagedValueInst.self)
  register(StrongCopyWeakValueInst.self)
  register(InjectEnumAddrInst.self)
  register(DeallocStackInst.self)
  register(DeallocPackInst.self)
  register(DeallocPackMetadataInst.self)
  register(DeallocStackRefInst.self)
  register(DeallocRefInst.self)
  register(DeallocPartialRefInst.self)
  register(DeallocBoxInst.self)
  register(DeallocExistentialBoxInst.self)
  register(LoadInst.self)
  register(LoadWeakInst.self)
  register(LoadUnownedInst.self)
  register(LoadBorrowInst.self)
  register(BuiltinInst.self)
  register(UpcastInst.self)
  register(UncheckedRefCastInst.self)
  register(UncheckedRefCastAddrInst.self)
  register(UncheckedAddrCastInst.self)
  register(UncheckedTrivialBitCastInst.self)
  register(UncheckedBitwiseCastInst.self)
  register(UncheckedValueCastInst.self)
  register(RefToRawPointerInst.self)
  register(RefToUnmanagedInst.self)
  register(RefToUnownedInst.self)
  register(UnmanagedToRefInst.self)
  register(UnownedToRefInst.self)
  register(MarkUnresolvedNonCopyableValueInst.self)
  register(MarkUnresolvedReferenceBindingInst.self)
  register(MarkUnresolvedMoveAddrInst.self)
  register(CopyableToMoveOnlyWrapperValueInst.self)
  register(MoveOnlyWrapperToCopyableValueInst.self)
  register(MoveOnlyWrapperToCopyableBoxInst.self)
  register(CopyableToMoveOnlyWrapperAddrInst.self)
  register(MoveOnlyWrapperToCopyableAddrInst.self)
  register(ObjectInst.self)
  register(VectorInst.self)
  register(VectorBaseAddrInst.self)
  register(TuplePackExtractInst.self)
  register(TuplePackElementAddrInst.self)
  register(PackElementGetInst.self)
  register(PackElementSetInst.self)
  register(DifferentiableFunctionInst.self)
  register(LinearFunctionInst.self)
  register(DifferentiableFunctionExtractInst.self)
  register(LinearFunctionExtractInst.self)
  register(DifferentiabilityWitnessFunctionInst.self)
  register(ProjectBlockStorageInst.self)
  register(InitBlockStorageHeaderInst.self)
  register(RawPointerToRefInst.self)
  register(AddressToPointerInst.self)
  register(PointerToAddressInst.self)
  register(IndexAddrInst.self)
  register(IndexRawPointerInst.self)
  register(TailAddrInst.self)
  register(InitExistentialRefInst.self)
  register(OpenExistentialRefInst.self)
  register(InitExistentialValueInst.self)
  register(DeinitExistentialValueInst.self)
  register(OpenExistentialValueInst.self)
  register(InitExistentialAddrInst.self)
  register(DeinitExistentialAddrInst.self)
  register(OpenExistentialAddrInst.self)
  register(OpenExistentialBoxInst.self)
  register(OpenExistentialBoxValueInst.self)
  register(InitExistentialMetatypeInst.self)
  register(OpenExistentialMetatypeInst.self)
  register(MetatypeInst.self)
  register(ValueMetatypeInst.self)
  register(ExistentialMetatypeInst.self)
  register(TypeValueInst.self)
  register(OpenPackElementInst.self)
  register(PackLengthInst.self)
  register(DynamicPackIndexInst.self)
  register(PackPackIndexInst.self)
  register(ScalarPackIndexInst.self)
  register(ObjCProtocolInst.self)
  register(FunctionRefInst.self)
  register(DynamicFunctionRefInst.self)
  register(PreviousDynamicFunctionRefInst.self)
  register(GlobalAddrInst.self)
  register(GlobalValueInst.self)
  register(BaseAddrForOffsetInst.self)
  register(AllocGlobalInst.self)
  register(IntegerLiteralInst.self)
  register(FloatLiteralInst.self)
  register(StringLiteralInst.self)
  register(HasSymbolInst.self)
  register(TupleInst.self)
  register(TupleExtractInst.self)
  register(TupleElementAddrInst.self)
  register(TupleAddrConstructorInst.self)
  register(StructInst.self)
  register(StructExtractInst.self)
  register(StructElementAddrInst.self)
  register(EnumInst.self)
  register(UncheckedEnumDataInst.self)
  register(InitEnumDataAddrInst.self)
  register(UncheckedTakeEnumDataAddrInst.self)
  register(SelectEnumInst.self)
  register(RefElementAddrInst.self)
  register(RefTailAddrInst.self)
  register(KeyPathInst.self)
  register(UnconditionalCheckedCastInst.self)
  register(ConvertFunctionInst.self)
  register(ThinToThickFunctionInst.self)
  register(ThickToObjCMetatypeInst.self)
  register(ObjCToThickMetatypeInst.self)
  register(CopyBlockInst.self)
  register(CopyBlockWithoutEscapingInst.self)
  register(ConvertEscapeToNoEscapeInst.self)
  register(ObjCExistentialMetatypeToObjectInst.self)
  register(ObjCMetatypeToObjectInst.self)
  register(ValueToBridgeObjectInst.self)
  register(MarkDependenceInst.self)
  register(MarkDependenceAddrInst.self)
  register(RefToBridgeObjectInst.self)
  register(BridgeObjectToRefInst.self)
  register(BridgeObjectToWordInst.self)
  register(GetAsyncContinuationInst.self)
  register(GetAsyncContinuationAddrInst.self)
  register(ExtractExecutorInst.self)
  register(BeginAccessInst.self)
  register(BeginBorrowInst.self)
  register(BorrowedFromInst.self)
  register(ProjectBoxInst.self)
  register(ProjectExistentialBoxInst.self)
  register(CopyValueInst.self)
  register(ExplicitCopyValueInst.self)
  register(UnownedCopyValueInst.self)
  register(WeakCopyValueInst.self)
  register(UncheckedOwnershipConversionInst.self)
  register(MoveValueInst.self)
  register(DropDeinitInst.self)
  register(EndCOWMutationInst.self)
  register(EndCOWMutationAddrInst.self)
  register(ClassifyBridgeObjectInst.self)
  register(PartialApplyInst.self)
  register(ApplyInst.self)
  register(FunctionExtractIsolationInst.self)
  register(ClassMethodInst.self)
  register(SuperMethodInst.self)
  register(ObjCMethodInst.self)
  register(ObjCSuperMethodInst.self)
  register(WitnessMethodInst.self)
  register(IsUniqueInst.self)
  register(DestroyNotEscapedClosureInst.self)
  register(AllocStackInst.self)
  register(AllocPackInst.self)
  register(AllocPackMetadataInst.self)
  register(AllocRefInst.self)
  register(AllocRefDynamicInst.self)
  register(AllocBoxInst.self)
  register(AllocExistentialBoxInst.self)

  register(BeginCOWMutationInst.self)
  register(DestructureStructInst.self)
  register(DestructureTupleInst.self)
  register(BeginApplyInst.self)

  register(UnreachableInst.self)
  register(ReturnInst.self)
  register(ThrowInst.self)
  register(ThrowAddrInst.self)
  register(YieldInst.self)
  register(UnwindInst.self)
  register(TryApplyInst.self)
  register(BranchInst.self)
  register(CondBranchInst.self)
  register(SwitchValueInst.self)
  register(SwitchEnumInst.self)
  register(SwitchEnumAddrInst.self)
  register(SelectEnumAddrInst.self)
  register(DynamicMethodBranchInst.self)
  register(AwaitAsyncContinuationInst.self)
  register(CheckedCastBranchInst.self)
  register(CheckedCastAddrBranchInst.self)
  register(ThunkInst.self)
  register(MergeIsolationRegionInst.self)
  register(IgnoredUseInst.self)
}

private func registerUtilities() {
  registerVerifier()
  registerPhiUpdater()
}
