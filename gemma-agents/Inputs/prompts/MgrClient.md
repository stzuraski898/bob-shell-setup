You are an expert C++ test engineer working on the Ceph storage system.
Your task is to generate a complete Google Test (gtest) unit test file for
MgrClient, the client-side half of the ceph-mgr protocol in
src/mgr/MgrClient.h and src/mgr/MgrClient.cc.

Branch for this work: wip-sz-77535-gemma-mgrclient
Tracker: https://tracker.ceph.com/issues/77535

--- CLASS OVERVIEW ---

MgrClient manages a daemon's connection to the active ceph-mgr.  It drives
reconnection, stats reporting, service-daemon registration, and command
dispatch.  It is heavily lock-guarded (ceph_mutex lock) and uses a
Messenger for network I/O.

Key public interface (focus your tests on these):

  bool is_initialized() const;
    - Returns true iff init() has been called and shutdown() has not

  int service_daemon_register(const std::string& service,
                              const std::string& name,
                              const std::map<std::string,std::string>& metadata);
    - Registers this daemon as a named service instance
    - Returns 0 on success, -EEXIST if already registered
    - After registration, service_name_ and daemon_name_ are set

  int service_daemon_update_status(std::map<std::string,std::string>&& status);
    - Updates the daemon's status map
    - Returns -ENOENT if not yet registered, 0 on success

  int service_daemon_update_task_status(
        std::string task_name,
        std::map<std::string,std::string>&& status);
    - Updates the task-level status for the named task
    - Returns -ENOENT if not yet registered, 0 on success

  void update_daemon_health(std::vector<DaemonHealthMetric>&& metrics);
    - Replaces the health-metric vector with the provided one
    - Idempotent — can be called before registration

  void update_daemon_metadata(const std::string& key, const std::string& val);
    - Upserts a single metadata key/value pair

  static std::string format_counter_path(
        const std::string& service_name,
        const std::string& daemon_name,
        const std::string& path,
        PerfCounterInstance* c,
        bool average);
    - Returns a formatted counter path string
    - Format: "service_name.daemon_name/path" (or similar — check the source)

--- CONTRACTS AND INVARIANTS (use these as your test specification) ---

1. is_initialized
   - False before init() is called
   - True after init() is called
   - False after shutdown() is called
   - NOTE: init() requires a live Messenger; for unit tests you can test the
     flag state directly on a minimally-constructed MgrClient if possible,
     or use a DISABLED_ test noting the Messenger dependency

2. service_daemon_register
   - Returns -EEXIST on a second call with the same service/name
   - After success: service_name_ accessible via the class state
   - Idempotent failure: a failed second registration does not corrupt state

3. service_daemon_update_status
   - Returns -ENOENT before register is called
   - Returns 0 after registration; status map is updated

4. service_daemon_update_task_status
   - Returns -ENOENT before register is called
   - Returns 0 after registration; task map is updated for the named task

5. update_daemon_health
   - Replaces the health metric vector wholesale (not an append)
   - Calling with an empty vector clears the metrics

6. format_counter_path (static — easily unit-tested without a live Messenger)
   - Produces a string containing service_name, daemon_name, and path
   - The separator between components matches what the source uses

--- TESTABILITY NOTE ---

MgrClient requires a Messenger, CephContext, and MonClient to construct fully
and call init()/shutdown().  Focus unit tests on:

  a) Methods that do not require an active connection:
     is_initialized() (before init), format_counter_path, update_daemon_health,
     update_daemon_metadata, service_daemon_update_status (returns -ENOENT)

  b) State-only paths reachable without a live messenger:
     service_daemon_register (can call without network if carefully isolated)

  c) For methods that genuinely require a network path, write the test as
     DISABLED_<TestName> with a comment explaining the dependency, so the
     test structure is visible and can be enabled in an integration context

--- ERROR / EDGE CASES (write a test for each) ---

- service_daemon_update_status before register -> -ENOENT
- service_daemon_update_task_status before register -> -ENOENT
- service_daemon_register called twice with same service/name -> -EEXIST
- update_daemon_health with empty vector -> health metrics are cleared
- update_daemon_health called twice -> second call replaces first
- format_counter_path with empty path component -> result is still well-formed
- format_counter_path with typical values ("rgw", "zone1", "req") -> verify
  the returned string contains all three components

--- TEST FILE REQUIREMENTS ---

- Use Google Test (gtest): #include <gtest/gtest.h>
- Include the relevant headers:
    #include "mgr/MgrClient.h"
    #include "mgr/DaemonHealthMetric.h"
  (the test binary is compiled from src/test/mgr/ with the ceph include path)
- Where MgrClient cannot be constructed without infrastructure, use DISABLED_
  tests with a clear comment rather than omitting the test entirely
- Every enabled TEST must contain at least one EXPECT_EQ, EXPECT_NE, or
  ASSERT_* that verifies an actual value
- A test with no assertions is not acceptable
- Do not add comments that restate the test name or what the next line does;
  only add a comment when it explains something non-obvious
- Output file: src/test/mgr/test_mgrclient_gemma.cc
- Return ONLY the complete C++ test file inside a single ```cpp code block
