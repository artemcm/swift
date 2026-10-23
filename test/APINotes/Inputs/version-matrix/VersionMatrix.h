// A wide API notes surface for comparing version-independent API notes against
// the default mode. Nothing here is interesting on its own: the point is enough
// distinct (annotation kind x slice arrangement) cells that any divergence
// between the two modes shows up as a difference in the imported interface.
//
// Naming is <kind><arrangement>, where the arrangement is one of:
//   U        annotated only by the unversioned slice
//   V4       annotated only by the 4.0 slice
//   UV       annotated by both
//   Header   carries the attribute in the header as well as in the notes
//   Keyless  named by a 4.0 slice that sets no key

#pragma clang assume_nonnull begin

// --- SwiftName -------------------------------------------------------------

void nameU(void);
void nameV4(void);
void nameUV(void);
void nameHeader(void) __attribute__((swift_name("nameHeader_fromHeader()")));
void nameHeaderV4(void) __attribute__((swift_name("nameHeaderV4_fromHeader()")));
void nameKeylessV4(void);

// --- SwiftPrivate ----------------------------------------------------------

void privU(void);
void privV4(void);
void privHeaderUndoneU(void) __attribute__((swift_private));
void privHeaderUndoneV4(void) __attribute__((swift_private));

// --- Availability ----------------------------------------------------------

void availNonswiftU(void);
void availNonswiftV4(void);
void availNoneU(void);

// --- Enum shape ------------------------------------------------------------

enum EnumOpenU { EnumOpenUFirst = 1 };
enum EnumFlagV4 { EnumFlagV4First = 1, EnumFlagV4Second = 2 };
enum EnumClosedKeyless { EnumClosedKeylessFirst = 1 };

// --- Objective-C container annotations -------------------------------------

#ifdef __OBJC__

__attribute__((objc_root_class))
@interface MatrixRoot
- (instancetype)init;
@end

@interface MatrixClass : MatrixRoot
@property (nonatomic, readonly) id accessorsU;
@property (nonatomic, readonly) id accessorsV4;
- (instancetype)initWithDesignatedU:(int)value;
- (void)methodPrivateV4;
@end

@interface MatrixMembersU : MatrixRoot
- (void)aMethod;
@end

@interface MatrixNonGenericV4<Element> : MatrixRoot
@end

#endif // __OBJC__

#pragma clang assume_nonnull end
