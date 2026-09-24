You are an expert C++ test engineer working on the Ceph storage system.
Your task is to generate a complete Google Test (gtest) unit test file for
DaemonHealthMetric, a small value-type class in src/mgr/DaemonHealthMetric.h
and src/mgr/DaemonHealthMetric.cc.

Branch for this work: wip-sz-80518-gemma-daemonhealthmetric
Tracker: https://tracker.ceph.com/issues/80518

--- CLASS OVERVIEW ---

DaemonHealthMetric is a small POD-like value type that carries one health metric
reported by a ceph daemon (OSD, MDS, etc.) to the manager. It pairs a metric
type enum (daemon_metric) with a union value (daemon_metric_t) that holds either
a single uint64 or a pair of uint32s.

Key types:

  enum class daemon_metric : uint8_t { SLOW_OPS, PENDING_CREATING_PGS, NONE }

  union daemon_metric_t {
    uint64_t n;
    struct { uint32_t n1, n2; };
    daemon_metric_t(uint32_t x, uint32_t y);   // pair constructor (n1=x, n2=y)
    daemon_metric_t(uint64_t x = 0);           // scalar constructor (n=x)
  };

  class DaemonHealthMetric {
    daemon_metric type = daemon_metric::NONE;  // always initialised
    daemon_metric_t value;                     // uninitialised after default ctor
  public:
    DaemonHealthMetric() = default;
    DaemonHealthMetric(daemon_metric type_, uint64_t n);
    DaemonHealthMetric(daemon_metric type_, uint32_t n1, uint32_t n2);
    daemon_metric  get_type()      const;
    std::string    get_type_name() const;  // wraps daemon_metric_name()
    uint64_t       get_n()         const;
    uint32_t       get_n1()        const;
    uint32_t       get_n2()        const;
    void dump(ceph::Formatter* f)  const;
    static std::list<DaemonHealthMetric> generate_test_instances();
    friend std::ostream& operator<<(std::ostream&, const DaemonHealthMetric&);
    // DENC encode/decode support (schema version 1/1: type as uint8_t, value.n as uint64_t)
  };

  const char* daemon_metric_name(daemon_metric m);  // SLOW_OPS->"slow_ops", etc.

--- CONTRACTS AND INVARIANTS (use these as your test specification) ---

1. daemon_metric_name
   - Maps SLOW_OPS      -> "slow_ops"
   - Maps PENDING_CREATING_PGS -> "pending_creating_pgs"
   - Maps NONE          -> "none"
   - Any unknown value  -> "???"   (default arm is load-bearing)

2. daemon_metric_t constructors
   - (uint32_t x, uint32_t y): sets n1=x, n2=y; n reflects their combined bits
   - (uint64_t x = 0): sets n=x; n1/n2 are the low/high 32-bit halves on LE
   - For SLOW_OPS with value 42: get_n()==42, get_n1()==42, get_n2()==0

3. DaemonHealthMetric constructors
   - Default ctor: get_type() == daemon_metric::NONE (the only safe thing to read)
   - (SLOW_OPS, uint64_t n):   get_type()==SLOW_OPS,  get_n()==n
   - (PENDING_CREATING_PGS, n1, n2): get_type()==PENDING_CREATING_PGS,
                                      get_n1()==n1, get_n2()==n2

4. get_type_name
   - Returns the same string as daemon_metric_name(get_type()) as a std::string
   - SLOW_OPS -> "slow_ops", PENDING_CREATING_PGS -> "pending_creating_pgs",
     NONE -> "none"

5. operator<<
   - Format: "TYPE_NAME(n|(n1,n2))"
   - For SLOW_OPS(42):          "slow_ops(42|(42,0))"
   - For PENDING_CREATING_PGS(3,7): "pending_creating_pgs(...)|(3,7))"
   - Uses daemon_metric_name for the type prefix

6. dump
   - Emits exactly four fields in order: "type" (string), "n" (int),
     "n1" (int), "n2" (int)
   - Must use the formatter's open_object/close_object pattern

7. DENC round-trip
   - encode then decode must produce an object equal to the original
   - Schema version 1/1: no migration path; test that the round-trip
     preserves type, get_n(), get_n1(), get_n2()
   - Test both SLOW_OPS and PENDING_CREATING_PGS instances

8. generate_test_instances
   - Returns a list with at least SLOW_OPS(1) and PENDING_CREATING_PGS(1,2)
   - Return type is std::list<DaemonHealthMetric> (value semantics, not pointers)

--- ERROR / EDGE CASES (write a test for each) ---

- NONE metric: default-constructed, only get_type() is safe to read; verify
  get_type() == daemon_metric::NONE and get_type_name() == "none"
- DENC round-trip of NONE type (type preserved, value.n round-trips as 0)
- daemon_metric_name with a cast unknown value (e.g. static_cast<daemon_metric>(99))
  must return "???"
- PENDING_CREATING_PGS with n1=0, n2=0 (zero values are valid)
- SLOW_OPS with n=UINT64_MAX (max value round-trips through DENC)

--- TEST FILE REQUIREMENTS ---

- Use Google Test (gtest): #include <gtest/gtest.h>
- Include the relevant headers:
    #include "mgr/DaemonHealthMetric.h"
  (the test binary is compiled from src/test/mgr/ with the ceph include path)
- Use a JSONFormatter or MockFormatter for dump tests if available; alternatively
  use ceph::JSONFormatter from "common/Formatter.h"
- Every TEST must contain at least one EXPECT_EQ, EXPECT_STREQ, or ASSERT_* that
  verifies an actual value — not just that the code runs without crashing
- A test with no assertions is not acceptable
- Do not add comments that restate the test name or what the next line does;
  only add a comment when it explains something non-obvious
- Output file: src/test/mgr/test_daemonhealthmetric_gemma.cc
- Return ONLY the complete C++ test file inside a single ```cpp code block
