You are an expert C++ test engineer working on the Ceph storage system.
Your task is to generate a complete Google Test (gtest) unit test file for
DaemonKey, a small struct in src/mgr/DaemonKey.h and src/mgr/DaemonKey.cc.

Branch for this work: wip-sz-80175-gemma-daemonkey
Tracker: https://tracker.ceph.com/issues/80175

--- CLASS OVERVIEW ---

DaemonKey is a plain struct that replaced ad-hoc std::pair<string,string>
throughout the ceph-mgr codebase.  It identifies a daemon by type and name
(e.g. type="osd", name="1") and provides a stable string representation
"type.name" (dot-separated).

  struct DaemonKey {
    std::string type;   // service type, e.g. "osd", "mon", "client"
    std::string name;   // service id/name, e.g. "1", "a", "admin"

    static std::pair<DaemonKey, bool> parse(const std::string& s);
  };

  bool operator<(const DaemonKey& lhs, const DaemonKey& rhs);
  std::ostream& operator<<(std::ostream& os, const DaemonKey& key);

  namespace ceph {
    std::string to_string(const DaemonKey& key);
  }

--- CONTRACTS AND INVARIANTS (use these as your test specification) ---

1. parse
   - Splits on the FIRST dot: type = s.substr(0, pos), name = s.substr(pos+1)
   - Returns {key, true}  when a dot is found
   - Returns {{}, false}  when no dot is present (no exception)
   - I-1: dot must be present for success
   - I-2: failure returns {DaemonKey{}, false}, not an exception
   - I-3: type is everything before the first dot
   - I-4: name is everything after the first dot (may itself contain dots)

2. operator<
   - Strict weak ordering: type is the primary key, name is the tiebreaker
   - I-5: type is compared first
   - I-6: name breaks ties
   - I-7: satisfies irreflexivity, asymmetry, transitivity

3. operator<<
   - Canonical format: "type.name" (dot-separated, no spaces)
   - I-8: output is exactly type << '.' << name
   - I-9: must be consistent with ceph::to_string output

4. ceph::to_string
   - Returns type + '.' + name
   - I-11: exactly "type.name"
   - I-12: consistent with operator<< output
   - I-14: round-trip property — parse(to_string(k)) == {k, true} for any k
            with non-empty type and name

--- ERROR / EDGE CASES (write a test for each) ---

- parse("osd.1")         -> {{"osd","1"}, true}
- parse("client.admin")  -> {{"client","admin"}, true}  (name has no dot)
- parse("osd.1.extra")   -> {{"osd","1.extra"}, true}   (name contains a dot)
- parse("nodot")         -> {{}, false}                  (no dot at all)
- parse("")              -> {{}, false}                  (empty string)
- parse(".")             -> {{"",""}, true}              (both fields empty — valid per code)
- parse(".foo")          -> {{"","foo"}, true}           (empty type)
- parse("foo.")          -> {{"foo",""}, true}           (empty name)
- operator< ordering: {"mon","a"} < {"osd","1"} (type is primary key)
- operator< ordering: {"osd","0"} < {"osd","1"} (name is tiebreaker)
- operator< irreflexivity: !( {"osd","1"} < {"osd","1"} )
- to_string round-trip: parse(to_string(k)).first == k for "osd","1"
- operator<< vs to_string consistency: both produce the same string

--- ORDERING CORRECTNESS (container usage) ---

- Create a std::map<DaemonKey, int> and insert several keys;
  verify iteration order is lexicographic (type first, then name)
- Create a std::set<DaemonKey> and verify deduplication works

--- TEST FILE REQUIREMENTS ---

- Use Google Test (gtest): #include <gtest/gtest.h>
- Include the relevant headers:
    #include "mgr/DaemonKey.h"
  (the test binary is compiled from src/test/mgr/ with the ceph include path)
- Every TEST must contain at least one EXPECT_EQ, EXPECT_STREQ, or ASSERT_*
  that verifies an actual value — not just that the code compiles or runs
- A test with no assertions is not acceptable
- Do not add comments that restate the test name or what the next line does;
  only add a comment when it explains something non-obvious
- Output file: src/test/mgr/test_daemonkey_gemma.cc
- Return ONLY the complete C++ test file inside a single ```cpp code block
