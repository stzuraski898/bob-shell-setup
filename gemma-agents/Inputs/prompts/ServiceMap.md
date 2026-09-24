You are an expert C++ test engineer working on the Ceph storage system.
Your task is to generate a complete Google Test (gtest) unit test file for
ServiceMap, a set of encode/decode/dump value types in src/mgr/ServiceMap.h
and src/mgr/ServiceMap.cc.

Branch for this work: wip-sz-80174-gemma-servicemap
Tracker: https://tracker.ceph.com/issues/80174

--- CLASS OVERVIEW ---

ServiceMap models the live map of all running non-core Ceph services (RGW,
RBD mirror, MDS, etc.).  It has three nested levels:

  struct ServiceMap {
    epoch_t epoch = 0;
    utime_t modified;
    std::map<std::string, Service> services;  // keyed by service name

    struct Service {
      std::map<std::string, Daemon> daemons;  // keyed by daemon id

      std::string get_summary() const;
      bool has_running_tasks() const;
      std::string get_task_summary(std::string_view task_name) const;
      void count_metadata(const std::string& field, std::map<std::string,int>*) const;
      void encode(bufferlist&, uint64_t) const;
      void decode(bufferlist::const_iterator&);
      void dump(Formatter*) const;
      static void generate_test_instances(std::list<Service*>&);
    };

    struct Daemon {
      std::map<std::string, std::string> metadata;
      std::map<std::string, std::string> task_status;
      utime_t last_seen;

      void encode(bufferlist&, uint64_t) const;
      void decode(bufferlist::const_iterator&);
      void dump(Formatter*) const;
      static void generate_test_instances(std::list<Daemon*>&);
    };

    static bool is_normal_ceph_entity(std::string_view type);
    DaemonKey get_daemon(const std::string& type, const std::string& id);
    void rm_daemon(const std::string& type, const std::string& id);
    void encode(bufferlist&, uint64_t) const;
    void decode(bufferlist::const_iterator&);
    void dump(Formatter*) const;
    static void generate_test_instances(std::list<ServiceMap*>&);
  };

--- CONTRACTS AND INVARIANTS (use these as your test specification) ---

1. Daemon::encode / Daemon::decode round-trip
   - All fields (metadata, task_status, last_seen) must round-trip exactly
   - Encoding schema version: test with the current supported feature set
   - An empty Daemon (no metadata, no task_status) must also round-trip

2. Service::encode / Service::decode round-trip
   - The daemons map must round-trip exactly (keys and values)
   - An empty Service (no daemons) must round-trip

3. ServiceMap::encode / ServiceMap::decode round-trip
   - epoch, modified, and services map must all round-trip
   - An empty ServiceMap (epoch=0, no services) must round-trip

4. ServiceMap::is_normal_ceph_entity
   - Returns true for: "mds", "osd", "mon", "mgr", "client"
   - Returns false for: "rgw", "rbd-mirror", "nfs", ""
   - This is a static method with a fixed allowlist

5. Service::get_summary
   - Returns a string summarising the number of running daemons
   - For a Service with 0 daemons: summary must not be empty
   - For a Service with 1 daemon: summary reflects "1 daemon" or similar text
   - For multiple daemons: count appears in the summary

6. Service::has_running_tasks
   - Returns true if any Daemon in the service has a non-empty task_status map
   - Returns false if all daemons have empty task_status maps
   - Returns false for an empty service (no daemons)

7. Service::get_task_summary
   - Returns a summary string for the named task across all daemons
   - Returns an empty string or descriptive text if no daemon has that task
   - Does not throw for an unknown task name

8. Service::count_metadata
   - Counts occurrences of each distinct value for the given metadata field
   - Populates the provided map: value -> count
   - Daemons missing the field do not contribute to any count

9. ServiceMap::get_daemon
   - Returns a DaemonKey for the named type and id
   - The key's type and name fields match the arguments

10. ServiceMap::rm_daemon
    - Removes the named daemon from the services map
    - After removal, the daemon is no longer reachable
    - Removing a non-existent daemon must not crash

--- ERROR / EDGE CASES (write a test for each) ---

- Daemon::encode/decode with non-ASCII metadata values (unicode in std::string)
- Service with multiple daemons where only some have task_status set
- ServiceMap with multiple services, each with multiple daemons
- is_normal_ceph_entity with empty string -> false
- is_normal_ceph_entity with mixed-case (e.g. "OSD") -> false (case sensitive)
- count_metadata on a field that no daemon has -> output map is empty
- rm_daemon on a service that becomes empty after removal (service entry removed
  or left empty — verify the expected post-state)

--- TEST FILE REQUIREMENTS ---

- Use Google Test (gtest): #include <gtest/gtest.h>
- Include the relevant headers:
    #include "mgr/ServiceMap.h"
    #include "include/encoding.h"
    #include "common/Formatter.h"
  (the test binary is compiled from src/test/mgr/ with the ceph include path)
- For encode/decode tests use ceph::buffer::list and
  ceph::encode() / ceph::decode() helpers
- For dump tests use ceph::JSONFormatter
- Every TEST must contain at least one EXPECT_EQ, EXPECT_TRUE/FALSE, or
  ASSERT_* that verifies an actual value
- A test with no assertions is not acceptable
- Do not add comments that restate the test name or what the next line does;
  only add a comment when it explains something non-obvious
- Output file: src/test/mgr/test_servicemap_gemma.cc
- Return ONLY the complete C++ test file inside a single ```cpp code block
