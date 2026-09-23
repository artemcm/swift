// A module with two API notes readers: its own sidecar, SidecarCore.apinotes,
// and the one of the module it is exported as, Sidecar.apinotes. Each reader's
// slices form their own slice groups, and selection runs once per group, so a
// declaration both sidecars annotate can take its name from one reader and its
// visibility from the other, at different versions.
//
// Naming is <kind>_<arrangement>, where the arrangement says which sidecar sets
// the key at which slice: Core or Exported, U (unversioned) or V4.

void name_CoreU(void);
void name_ExportedU(void);
void name_ExportedV4(void);

// Different keys from different readers.
void namePriv_CoreUName_ExportedUPriv(void);
void namePriv_CoreV4Name_ExportedUPriv(void);
void namePriv_CoreUName_ExportedV4Priv(void);

// Both readers have a slice for the same declaration, at different versions,
// so each group selects on its own.
void name_CoreU_ExportedV4Priv(void);

// Both readers set the same key. The default mode applies them in group order.
void name_CoreU_ExportedU(void);
void name_CoreV4_ExportedU(void);
void name_CoreU_ExportedV4(void);
