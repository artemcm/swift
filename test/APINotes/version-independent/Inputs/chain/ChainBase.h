// The base of a two-module chain. ChainExt extends these declarations, and its
// Swift lookup table keys some of its own names under these declarations' Swift
// names, which this module's API notes decide.

__attribute__((objc_root_class))
@interface ChainRoot
@end

// Renamed by the unversioned slice.
@interface ChainClass : ChainRoot
- (void)baseMethod;
@end

// Renamed by the 4.0 slice only.
@interface ChainClassV4 : ChainRoot
@end

typedef int ChainIndexV4;

enum ChainEnumV4 { ChainEnumV4First = 1, ChainEnumV4Second = 2 };
