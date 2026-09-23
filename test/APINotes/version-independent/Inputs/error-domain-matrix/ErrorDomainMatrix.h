// NSErrorDomain across the slice arrangements that matter. The client imports
// Foundation, so that the _BridgedStoredNSError wrapper actually forms and
// shows up in the printed interface. The module itself only forward-declares
// NSString: importing Foundation here would tie it to the SDK modules of the
// Swift version it was built at.
//
// The domain is the one API notes key whose loss is not cosmetic: it decides
// whether the enum imports as an error wrapper plus a nested Code, or as a bare
// enum, and the two have different Swift names. A client written against one
// does not compile against the other.

@class NSString;

extern NSString *const ErrNotesDomain;
extern NSString *const ErrHeaderDomain;

// Domain supplied only by the unversioned slice.
enum ErrUCode { ErrUCodeFirst = 1 };

// Domain supplied only by the 4.0 slice, so a 5.0 client must not see a wrapper.
enum ErrV4Code { ErrV4CodeFirst = 1 };

// Domain supplied only by the 5.0 slice, so a 6.0 client must not see a wrapper.
enum ErrV5Code { ErrV5CodeFirst = 1 };

// Header writes a domain and the notes replace it.
enum ErrHeaderCode {
  ErrHeaderCodeFirst = 1
} __attribute__((ns_error_domain(ErrHeaderDomain)));

// Control: no notes entry at all. Keeps the comparison honest about which
// declarations the notes are responsible for.
enum ErrUntouchedCode { ErrUntouchedCodeFirst = 1 };
