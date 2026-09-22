// Enough declarations carrying API notes to grow the importer's per-declaration
// selection cache past its initial bucket count. Nothing here is versioned: a
// plain unversioned sidecar is all it takes.
//
// The count is the point. llvm::DenseMap starts at 64 buckets and grows when it
// reaches 48 entries, and 48 is where the crash measurably begins, so 64
// declarations clears the threshold with margin. Do not shrink this list.

void scaled01(void);
void scaled02(void);
void scaled03(void);
void scaled04(void);
void scaled05(void);
void scaled06(void);
void scaled07(void);
void scaled08(void);
void scaled09(void);
void scaled10(void);
void scaled11(void);
void scaled12(void);
void scaled13(void);
void scaled14(void);
void scaled15(void);
void scaled16(void);
void scaled17(void);
void scaled18(void);
void scaled19(void);
void scaled20(void);
void scaled21(void);
void scaled22(void);
void scaled23(void);
void scaled24(void);
void scaled25(void);
void scaled26(void);
void scaled27(void);
void scaled28(void);
void scaled29(void);
void scaled30(void);
void scaled31(void);
void scaled32(void);
void scaled33(void);
void scaled34(void);
void scaled35(void);
void scaled36(void);
void scaled37(void);
void scaled38(void);
void scaled39(void);
void scaled40(void);
void scaled41(void);
void scaled42(void);
void scaled43(void);
void scaled44(void);
void scaled45(void);
void scaled46(void);
void scaled47(void);
void scaled48(void);
void scaled49(void);
void scaled50(void);
void scaled51(void);
void scaled52(void);
void scaled53(void);
void scaled54(void);
void scaled55(void);
void scaled56(void);
void scaled57(void);
void scaled58(void);
void scaled59(void);
void scaled60(void);
void scaled61(void);
void scaled62(void);
void scaled63(void);
void scaled64(void);
