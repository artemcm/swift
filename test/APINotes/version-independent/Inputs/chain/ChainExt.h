// The second module of the chain. Its declarations reach into ChainBase in
// each way the Swift lookup table records: categories on ChainBase's classes,
// signatures naming ChainBase's types, and globals imported as members of
// ChainBase's types.

@import ChainBase;

@interface ChainClass (ChainExt)
- (void)extMethodU;
- (void)extMethodV4;
@end

@interface ChainClassV4 (ChainExt)
- (void)extOnV4Class;
@end

void chainUsesClass(ChainClass *_Nonnull c);
void chainUsesV4Class(ChainClassV4 *_Nonnull c);
void chainUsesIndex(ChainIndexV4 i);
void chainUsesEnum(enum ChainEnumV4 e);

// Imported as members of ChainBase's types.
ChainClass *_Nonnull ChainClassMake(void);
ChainClassV4 *_Nonnull ChainClassV4Make(void);
ChainClassV4 *_Nonnull ChainClassV4MakeV4(void);
