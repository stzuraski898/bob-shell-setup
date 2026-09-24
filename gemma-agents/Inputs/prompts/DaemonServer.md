You are an expert C++ test engineer working on the Ceph storage system.
Your task is to generate a complete Google Test (gtest) unit test file for
DaemonServer, the network-facing server component of ceph-mgr in
src/mgr/DaemonServer.h and src/mgr/DaemonServer.cc.

Branch for this work: wip-sz-80176-gemma-daemonserver
Tracker: https://tracker.ceph.com/issues/80176

--- CLASS OVERVIEW ---

DaemonServer is a large class (~3900 lines).  It owns the messenger that
daemons connect to, processes perf/health/service-map reports, and dispatches
mgr commands.  Most of its logic requires a live CephContext, Messenger,
OSDMap, and cluster state.

Because of these dependencies, this unit test file must focus on the subset
of methods and helpers that are testable in isolation:

  1. Static / free helpers with no network dependency
  2. Pure-logic helpers whose inputs can be constructed in a test fixture
  3. DISABLED_ stubs for methods that genuinely need a live cluster

--- TESTABLE SURFACES (write tests for these) ---

1. key_from_service (static)
   - Located at DaemonServer.cc ~line 545
   - Signature (inferred): converts a service type + id into a DaemonKey
   - Contract: DaemonKey::type == service_type, DaemonKey::name == id
   - Test with ("osd", "1"), ("mds", "a"), ("mon", "alpha")
   - Verify the returned key matches the expected type and name

2. _generate_command_map
   - Builds a map from command prefix -> MgrCommand pointer
   - Given a vector of MgrCommand objects, each entry must appear in the map
   - Duplicate prefixes: last writer wins (or first — verify the actual
     behaviour from the source)

3. _get_mgrcommand
   - Returns a pointer to the MgrCommand for a known prefix
   - Returns nullptr for an unknown prefix

4. _allowed_command
   - Enforces capability-based command authorisation
   - Given a DaemonServer, a capability string, and a command prefix,
     verify the allow/deny logic (if the method can be called without
     a live MgrSession — if not, write as DISABLED_)

5. dump_pg_ready
   - Writes a boolean "pg_ready" field to the provided Formatter
   - Test with pg_ready_ = true and pg_ready_ = false
   - Verify the formatter output contains the expected value

6. Inner type: CommandContext
   - If CommandContext is constructible in isolation, verify that
     reply() / send_early_reply() set the expected state fields

--- DISABLED_ STUBS (write these as documentation) ---

For each of the following, write a DISABLED_ test with a comment explaining
which infrastructure component blocks it from running in unit tests:

  - DISABLED_Init: requires Messenger, CephContext, MonClient
  - DISABLED_HandleReport: requires a live OSDMap and DaemonStateIndex
  - DISABLED_SendReport: requires active connections to the cluster
  - DISABLED_HandleCommand: requires MgrSession, AuthorizationManager

--- CONTRACTS AND INVARIANTS ---

1. key_from_service
   - type and name fields of the returned DaemonKey must exactly match inputs
   - Consistent with DaemonKey::parse(type + "." + name)

2. _generate_command_map
   - Every MgrCommand in the input vector appears as a value in the output map
   - Keys are the cmd_prefix strings from each MgrCommand

3. _get_mgrcommand
   - Returns non-null for any prefix that was inserted by _generate_command_map
   - Returns null for any prefix that was not inserted

4. dump_pg_ready
   - Writes "pg_ready": true  when pg_ready_ is set
   - Writes "pg_ready": false when pg_ready_ is not set

--- ERROR / EDGE CASES ---

- _generate_command_map with an empty input vector -> result map is empty
- _get_mgrcommand with an empty string prefix -> nullptr
- _get_mgrcommand with a prefix that was never registered -> nullptr
- dump_pg_ready: verify both true and false states

--- TEST FILE REQUIREMENTS ---

- Use Google Test (gtest): #include <gtest/gtest.h>
- Include the relevant headers:
    #include "mgr/DaemonServer.h"
    #include "mgr/DaemonKey.h"
    #include "common/Formatter.h"
  (the test binary is compiled from src/test/mgr/ with the ceph include path)
- For formatter tests use ceph::JSONFormatter
- Where DaemonServer cannot be constructed without infrastructure, target the
  static/helper methods directly or use a test fixture that constructs only
  what is needed; use DISABLED_ for the rest
- Every enabled TEST must contain at least one EXPECT_EQ, EXPECT_NE,
  EXPECT_TRUE/FALSE, or ASSERT_* that verifies an actual value
- A test with no assertions is not acceptable
- Do not add comments that restate the test name or what the next line does;
  only add a comment when it explains something non-obvious
- Output file: src/test/mgr/test_daemonserver_gemma.cc
- Return ONLY the complete C++ test file inside a single ```cpp code block
