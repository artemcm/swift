//===--------------------- LegalConstExprVerifier.cpp ---------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//
// This file implements syntactic validation that a `@const` expression
// consists strictly of values and operations on those values as allowed
// by the `@const` feature specification at this time.
//
//===----------------------------------------------------------------------===//

#include "MiscDiagnostics.h"
#include "TypeChecker.h"
#include "swift/AST/ASTContext.h"
#include "swift/AST/ASTWalker.h"
#include "swift/AST/ParameterList.h"
#include "swift/AST/SemanticAttrs.h"
#include "swift/Basic/Assertions.h"
using namespace swift;

/// Return true iff the given \p type is a Stdlib integer type.
static bool isIntegerType(Type type) {
  return type->isInt() || type->isInt8() || type->isInt16() ||
         type->isInt32() || type->isInt64() || type->isUInt() ||
         type->isUInt8() || type->isUInt16() || type->isUInt32() ||
         type->isUInt64();
}

/// Return true iff the given \p type is a Float type.
static bool isFloatType(Type type) {
  return type->isFloat() || type->isDouble() || type->isFloat80();
}

/// Given an error expression \p errorExpr, diagnose the error based on the type
/// of the expression. For instance, if the expression's type is expressible by
/// a literal e.g. integer, boolean etc. report that it must be a literal.
/// Otherwise, if the expression is a nominal type, report that it must be
/// static member of the type.
static void diagnoseError(Expr *errorExpr, const ASTContext &astContext,
                          AbstractFunctionDecl *funcDecl) {
  DiagnosticEngine &diags = astContext.Diags;
  //Type exprType = errorExpr->getType();
  SourceLoc errorLoc = errorExpr->getLoc();

  diags.diagnose(errorLoc, diag::unsupported_const_operator);
  return;
}

static bool supportedBinaryOperator(BinaryExpr *binaryExpr) {
  const auto operatorDeclRefExpr = binaryExpr->getFn()->getMemberOperatorRef();
  if (!operatorDeclRefExpr)
    return false;

  // Non-stdlib operators are not allowed, for now
  auto operatorDecl = operatorDeclRefExpr->getDecl();
  if (!operatorDecl->getModuleContext()->isStdlibModule())
    return false;
  
  auto operatorName = operatorDecl->getBaseName();
  if (!operatorName.isOperator())
    return false;
  
  auto operatorIdentifier = operatorName.getIdentifier();
  if (!operatorIdentifier.isArithmeticOperator() &&
      !operatorIdentifier.isBitwiseOperator() &&
      !operatorIdentifier.isShiftOperator() &&
      !operatorIdentifier.isStandardComparisonOperator())
    return false;

  // Operators which are not integer or floating point type are not
  // allowed, for now.
  auto operatorType = binaryExpr->getType();
  if (!isIntegerType(operatorType) && !isFloatType(operatorType))
    return false;
  
  return true;
}

static Expr *checkSupportedInConst(Expr *expr) {
  SmallVector<Expr *, 4> expressionsToCheck;
  expressionsToCheck.push_back(expr);
  while (!expressionsToCheck.empty()) {
    Expr *expr = expressionsToCheck.pop_back_val();
    // Lookthrough identity_expr, tuple, array, and inject_into_optional expressions.
    if (IdentityExpr *identityExpr = dyn_cast<IdentityExpr>(expr)) {
      expressionsToCheck.push_back(identityExpr->getSubExpr());
      continue;
    }
    if (TupleExpr *tupleExpr = dyn_cast<TupleExpr>(expr)) {
      for (Expr *element : tupleExpr->getElements())
        expressionsToCheck.push_back(element);
      continue;
    }
    if (ArrayExpr *arrayExpr = dyn_cast<ArrayExpr>(expr)) {
      for (Expr *element : arrayExpr->getElements())
        expressionsToCheck.push_back(element);
      continue;
    }
    if (InjectIntoOptionalExpr *optionalExpr =
        dyn_cast<InjectIntoOptionalExpr>(expr)) {
      expressionsToCheck.push_back(optionalExpr->getSubExpr());
      continue;
    }
    
    // Ensure that binary expressions consist of literals, references
    // to other variables, and supported operators on integer and floating
    // point types only.
    if (BinaryExpr *binaryExpr = dyn_cast<BinaryExpr>(expr)) {
      if (!supportedBinaryOperator(binaryExpr))
        return binaryExpr;
      
      expressionsToCheck.push_back(binaryExpr->getLHS());
      expressionsToCheck.push_back(binaryExpr->getRHS());
      continue;
    }
    
    // Literal expressions are okay
    if (isa<LiteralExpr>(expr))
      continue;
    
    // Type expressions not supported in `@const` expressions
    if (isa<TypeExpr>(expr))
      return expr;
    
    // Closure expressions are not supported in `@const` expressions
    // TODO: `@const` closures
    if (isa<AbstractClosureExpr>(expr))
      return expr;
    
    // Default argument expressions of a function must be ensured to be a constant by the
    // definition of the function.
    if (isa<DefaultArgumentExpr>(expr))
      continue;
    
    auto checkVarDecl = [&](VarDecl *varDecl) -> bool {
      // `@const` variables are always okay, their initializer expressions
      // will be checked separately, individually.
      if (varDecl->isConstValue())
        return true;

      // Non-explicitly-`@const` variables must have an initial value
      // we can look through.
      if (!varDecl->hasInitialValue())
        return false;

      if (auto initExpr = varDecl->getParentInitializer()) {
        expressionsToCheck.push_back(initExpr);
        return true;
      }
      
      return false;
    };
    
    // If this is a member-ref, it has to be annotated constant evaluable,
    if (MemberRefExpr *memberRef = dyn_cast<MemberRefExpr>(expr)) {
      if (VarDecl *memberVarDecl = dyn_cast<VarDecl>(memberRef->getMember().getDecl())) {
        if (checkVarDecl(memberVarDecl))
          continue;
        return expr;
      }
      return expr;
    }
    
    if (DeclRefExpr *declRef = dyn_cast<DeclRefExpr>(expr)) {
      auto decl = declRef->getDecl();
      // `@const` paramters are always okay
      if (auto *paramDecl = dyn_cast<ParamDecl>(decl)) {
        if (!paramDecl->isConstVal())
          return expr;
        continue;
      }

      if (VarDecl *varDecl = dyn_cast<VarDecl>(declRef->getDecl())) {
        if (checkVarDecl(varDecl))
          continue;
        return expr;
      }
      return expr;
    }

    if (!isa<ApplyExpr>(expr))
      return expr;
    
    ApplyExpr *apply = cast<ApplyExpr>(expr);
    ValueDecl *calledValue = apply->getCalledValue();
    if (!calledValue)
      return expr;
    
    // If this is an enum case, check that it does not have associated values
    if (EnumElementDecl *enumCase = dyn_cast<EnumElementDecl>(calledValue)) {
      if (enumCase->hasAssociatedValues())
        return expr;
      continue;
    }

    // TODO: calls to `@const` functions
//  AbstractFunctionDecl *callee = dyn_cast<AbstractFunctionDecl>(calledValue);
//  if (!callee)
//    return expr;
//  if (callee->isConstFunction()) {
//    for (auto arg : *apply->getArgs())
//      expressionsToCheck.push_back(arg.getExpr());
//  }

    return expr;
  }
  return nullptr;
}

/// Given a call \c callExpr, if some or all of its arguments are required to be
/// constants, check the argument expressions.
static void verifyConstArguments(const CallExpr *callExpr,
                                 const ASTContext &ctx) {
  ValueDecl *calledDecl = callExpr->getCalledValue();
  if (!calledDecl || !isa<AbstractFunctionDecl>(calledDecl))
    return;
  AbstractFunctionDecl *callee = cast<AbstractFunctionDecl>(calledDecl);

  // Collect argument indices that are required to be constants.
  SmallVector<unsigned, 4> constantArgumentIndices;
  auto paramList = callee->getParameters();
  for (unsigned i = 0; i < paramList->size(); ++i) {
    ParamDecl *param = paramList->get(i);
    if (param->isConstVal())
      constantArgumentIndices.push_back(i);
  }
  if (constantArgumentIndices.empty())
    return;

  // Check that the arguments at the constantArgumentIndices are constants.
  SmallVector<Expr *, 4> arguments;
  for (auto arg : *callExpr->getArgs())
    arguments.push_back(arg.getExpr());

  for (unsigned constantIndex : constantArgumentIndices) {
    assert(constantIndex < arguments.size() &&
           "constantIndex exceeds the number of arguments to the function");
    Expr *argument = arguments[constantIndex];
    Expr *errorExpr = checkSupportedInConst(argument);
    if (errorExpr)
      diagnoseError(errorExpr, ctx, callee);
  }
}

void swift::diagnoseIllegalConstExpr(
    const Expr *expr, const DeclContext *declContext) {
  class ConstantReqCallWalker : public ASTWalker {
    DeclContext *DC;
    bool insideClosure;

  public:
    ConstantReqCallWalker(DeclContext *DC) : DC(DC), insideClosure(false) {}

    MacroWalking getMacroWalkingBehavior() const override {
      return MacroWalking::ArgumentsAndExpansion;
    }

    // Descend until we find a call expressions. Note that the input expression
    // could be an assign expression or another expression that contains the
    // call.
    PreWalkResult<Expr *> walkToExprPre(Expr *expr) override {
      // Handle closure expressions separately as we may need to
      // manually descend into the body.
      if (auto *closureExpr = dyn_cast<ClosureExpr>(expr)) {
        return walkToClosureExprPre(closureExpr);
      }

      if (!expr || isa<ErrorExpr>(expr) || !expr->getType())
        return Action::SkipNode(expr);

      if (auto *callExpr = dyn_cast<CallExpr>(expr)) {
        verifyConstArguments(callExpr, DC->getASTContext());
      }
      
      return Action::Continue(expr);
    }

    PreWalkResult<Expr *> walkToClosureExprPre(ClosureExpr *closure) {
      DC = closure;
      insideClosure = true;
      return Action::Continue(closure);
    }

    PostWalkResult<Expr *> walkToExprPost(Expr *expr) override {
      if (auto *closureExpr = dyn_cast<ClosureExpr>(expr)) {
        // Reset the DeclContext to the outer scope if we descended
        // into a closure expr and check whether or not we are still
        // within a closure context.
        DC = closureExpr->getParent();
        insideClosure = isa<ClosureExpr>(DC);
      }
      return Action::Continue(expr);
    }
  };

  // We manually check closure bodies from their outer contexts,
  // so bail early if we are being called directly on expressions
  // inside of a closure body.
  if (isa<ClosureExpr>(declContext)) {
    return;
  }

  ConstantReqCallWalker walker(const_cast<DeclContext *>(declContext));
  const_cast<Expr *>(expr)->walk(walker);
}
