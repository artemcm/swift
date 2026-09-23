// C++ declarations under version-independent API notes: namespaces, records
// and their methods. The Swift lookup table collects captured declarations by
// walking into namespaces and records, so each of these has to be found there.
//
// Naming is <kind><arrangement>, as in version-matrix: U for the unversioned
// slice, V4 for the 4.0 slice.

namespace MatrixNS {
void nsFuncU();
void nsFuncV4();
void nsPrivV4();

struct NSRecord {
  int value;
  void methodU() const;
  void methodV4() const;
  void methodPrivV4() const;
};

enum class NSScopedEnumV4 { first, second };

namespace Inner {
void innerFuncU();
void innerFuncV4();
} // namespace Inner
} // namespace MatrixNS

struct TopRecordV4 {
  int field;
};
