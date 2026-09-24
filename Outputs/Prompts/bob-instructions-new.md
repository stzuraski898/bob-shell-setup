# Latent Bug Unit Test Prompts (Top 5 Issue Objects)

---

### 1. DaemonState

You are tasked with writing adversarial unit tests for Ceph Manager class `DaemonState` to expose latent bugs and contract divergences documented in its Intent Assessment file.

**References & Locations:**
- Target Source: `src/mgr/DaemonState.cc` / `src/mgr/DaemonState.h`
- Intent Assessment File: `/home/szuraski/BobOutput/Object History/DaemonState-intent.md`
  (Fallback if sandboxed to `/home/szuraski/ceph`: use relative path `../BobOutput/Object History/DaemonState-intent.md`)
- Raw History Corpus (reference): `/home/szuraski/BobOutput/Object History/v3/DaemonState/`
- Final HTML Output Directory: `/home/szuraski/BobOutput/HTML/`

**Step-by-Step Instructions:**

Step 1: Check whether a local branch matching `wip-sz-*daemonstate*` exists (`git branch --list 'wip-sz-*daemonstate*'`). If so, check it out. If not, create a new branch named `wip-sz-daemonstate-latent-bug-tests` from `ceph-origin/main`.

Step 2: Read the Intent Assessment file.
- Path: `/home/szuraski/BobOutput/Object History/DaemonState-intent.md` (if blocked by sandbox, try `../BobOutput/Object History/DaemonState-intent.md` via terminal read).
- Identify all functions flagged `DIVERGED` or `UNGROUNDED`. Extract the documented invariants, error conditions, and critiques describing how current code deviates from historical intent.
- Do not stop after reading — proceed immediately to Step 3.

Step 3: Perform Git Archaeology. For each `DIVERGED` or `UNGROUNDED` defect identified in Step 2, run:
```
git log -S "<relevant_symbol>" --oneline -- src/mgr/DaemonState.cc
git blame src/mgr/DaemonState.cc | grep "<relevant_line>"
```
Record the 12-character short SHA for both the **Establishing Commit** (first introduced the contract/invariant) and the **Breaking Commit** (introduced the defect/regression). Build GitHub hyperlinks in the form `https://github.com/ceph/ceph/commit/<sha>` — these will be embedded in the final HTML report.

Step 4: Write adversarial unit tests in `src/test/mgr/test_daemonstate.cc` following existing GoogleTest patterns (see `test_clusterstate.cc`).
- Name tests: `TEST_F(DaemonStateTest, LatentBug_<FunctionName>_<Issue>)`.
- Assert the **historically intended, correct behavior** — not the buggy current behavior. Tests must **fail** at `HEAD`; that failure is the desired outcome. Do NOT weaken or alter assertions to make tests pass against buggy code.
- Every assertion expected to fail at `HEAD` must use GTest `<<` streaming to print the Current (Buggy) State and Expected (Correct) State:
  ```cpp
  ASSERT_FALSE(exists)
    << "Current: empty device STILL EXISTS (leaked)"
    << "\nExpected: empty device should be pruned and NOT exist";
  ASSERT_EQ(device->wear_level, -1.0f)
    << "Current wear_level: " << device->wear_level << "f (corrupt string parsed as valid 0.0f)"
    << "\nExpected: -1.0f (unknown/parse failure sentinel)";
  ```
- Avoid bare `ASSERT_TRUE` / `ASSERT_EQ` with no message — every failing assertion must be self-explanatory from test output alone.
- Every test must use `EXPECT_EQ`, `EXPECT_NE`, `EXPECT_FALSE`, `EXPECT_TRUE`, `ASSERT_DEATH`, or `EXPECT_THROW` against specific return values and state fields. No trivial smoke tests (`EXPECT_NO_THROW`, empty constructor-destructor runs).

Step 5: Update `src/test/CMakeLists.txt` to include the test target if adding a new test executable.

Step 6: Build the test binary:
```
./do_cmake.sh -DWITH_RADOSGW_LANCEDB=OFF
ninja -C build unittest_mgr_daemonstate
```

Step 7: Run the tests and capture output:
```
./build/bin/unittest_mgr_daemonstate --gtest_filter="*LatentBug*"
```
Record all test failures, crashes, assertion failures, or sanitiser reports. Perform an adversarial gap analysis: (1) method coverage for all diverged functions, (2) error paths and missing boundary checks, (3) boundary/edge cases and invalid inputs, (4) concurrency and state transitions. If any unexercised defect remains, add tests, rebuild, and re-run.

Step 8: Squash and commit the test suite:
```
git add src/test/mgr/test_daemonstate.cc src/test/CMakeLists.txt
git commit -m "test/mgr: add adversarial unit tests exposing latent bugs in DaemonState

Add unit tests asserting historical design contracts for DaemonState
based on intent assessment findings.

Assisted-by: IBM Bob"
```
Check `git log --oneline`. If a test commit already exists on this branch, use `git commit --amend` or `git reset --soft HEAD~1 && git commit` to fold new tests in. Do not use `git rebase -i`.

Step 9: Produce a Structured Summary Report and save it to `/home/szuraski/BobOutput/HTML/DaemonState_latent_bugs_report.html`. Include:
- **Summary Dashboard**: a table mapping each `LatentBug_*` test to its intent file finding, pass/fail status, and source location in `src/mgr/DaemonState.cc`.
- **Per-Finding Detail Sections**: precise defect LOC, GTest failure output (Current vs. Expected from `<<` messages), and clickable GitHub hyperlinks to both the Establishing Commit and Breaking Commit from Step 3.

---

### 2. PyModuleRegistry

You are tasked with writing adversarial unit tests for Ceph Manager class `PyModuleRegistry` to expose latent bugs and contract divergences documented in its Intent Assessment file.

**References & Locations:**
- Target Source: `src/mgr/PyModuleRegistry.cc` / `src/mgr/PyModuleRegistry.h`
- Intent Assessment File: `/home/szuraski/BobOutput/Object History/PyModuleRegistry-intent.md`
  (Fallback if sandboxed to `/home/szuraski/ceph`: use relative path `../BobOutput/Object History/PyModuleRegistry-intent.md`)
- Raw History Corpus (reference): `/home/szuraski/BobOutput/Object History/v3/PyModuleRegistry/`
- Final HTML Output Directory: `/home/szuraski/BobOutput/HTML/`

**Step-by-Step Instructions:**

Step 1: Check whether a local branch matching `wip-sz-*pymoduleregistry*` exists (`git branch --list 'wip-sz-*pymoduleregistry*'`). If so, check it out. If not, create a new branch named `wip-sz-pymoduleregistry-latent-bug-tests` from `ceph-origin/main`.

Step 2: Read the Intent Assessment file.
- Path: `/home/szuraski/BobOutput/Object History/PyModuleRegistry-intent.md` (if blocked by sandbox, try `../BobOutput/Object History/PyModuleRegistry-intent.md` via terminal read).
- Identify all functions flagged `DIVERGED` or `UNGROUNDED`. Extract the documented invariants, error conditions, and critiques describing how current code deviates from historical intent.
- Do not stop after reading — proceed immediately to Step 3.

Step 3: Perform Git Archaeology. For each `DIVERGED` or `UNGROUNDED` defect identified in Step 2, run:
```
git log -S "<relevant_symbol>" --oneline -- src/mgr/PyModuleRegistry.cc
git blame src/mgr/PyModuleRegistry.cc | grep "<relevant_line>"
```
Record the 12-character short SHA for both the **Establishing Commit** and the **Breaking Commit**. Build GitHub hyperlinks: `https://github.com/ceph/ceph/commit/<sha>` — these will be embedded in the final HTML report.

Step 4: Write adversarial unit tests in `src/test/mgr/test_pymoduleregistry.cc` following existing GoogleTest patterns (see `test_clusterstate.cc`, `test_daemonstate.cc`).
- Name tests: `TEST_F(PyModuleRegistryTest, LatentBug_<FunctionName>_<Issue>)`.
- Assert the **historically intended, correct behavior** — not the buggy current behavior. Tests must **fail** at `HEAD`; that failure is the desired outcome. Do NOT weaken or alter assertions to make tests pass against buggy code.
- Every assertion expected to fail at `HEAD` must use GTest `<<` streaming to print the Current (Buggy) State and Expected (Correct) State:
  ```cpp
  ASSERT_EQ(result, -EINVAL)
    << "Current: returned " << result << " (missing validation)"
    << "\nExpected: -EINVAL when module name is empty";
  ```
- Avoid bare `ASSERT_TRUE` / `ASSERT_EQ` with no message — every failing assertion must be self-explanatory from test output alone.
- Every test must use `EXPECT_EQ`, `EXPECT_NE`, `EXPECT_FALSE`, `EXPECT_TRUE`, `ASSERT_DEATH`, or `EXPECT_THROW` against specific return values and state fields. No trivial smoke tests.

Step 5: Update `src/test/CMakeLists.txt` to include the test target if adding a new test executable.

Step 6: Build the test binary:
```
./do_cmake.sh -DWITH_RADOSGW_LANCEDB=OFF
ninja -C build unittest_mgr_pymoduleregistry
```

Step 7: Run the tests and capture output:
```
./build/bin/unittest_mgr_pymoduleregistry --gtest_filter="*LatentBug*"
```
Record all test failures, crashes, assertion failures, or sanitiser reports. Perform an adversarial gap analysis: (1) method coverage for all diverged functions, (2) error paths and missing boundary checks, (3) boundary/edge cases and invalid inputs, (4) concurrency and state transitions. If any unexercised defect remains, add tests, rebuild, and re-run.

Step 8: Squash and commit the test suite:
```
git add src/test/mgr/test_pymoduleregistry.cc src/test/CMakeLists.txt
git commit -m "test/mgr: add adversarial unit tests exposing latent bugs in PyModuleRegistry

Add unit tests asserting historical design contracts for PyModuleRegistry
based on intent assessment findings.

Assisted-by: IBM Bob"
```
Check `git log --oneline`. If a test commit already exists on this branch, use `git commit --amend` or `git reset --soft HEAD~1 && git commit` to fold new tests in. Do not use `git rebase -i`.

Step 9: Produce a Structured Summary Report and save it to `/home/szuraski/BobOutput/HTML/PyModuleRegistry_latent_bugs_report.html`. Include:
- **Summary Dashboard**: a table mapping each `LatentBug_*` test to its intent file finding, pass/fail status, and source location in `src/mgr/PyModuleRegistry.cc`.
- **Per-Finding Detail Sections**: precise defect LOC, GTest failure output (Current vs. Expected from `<<` messages), and clickable GitHub hyperlinks to both the Establishing Commit and Breaking Commit from Step 3.

---

### 3. MgrCap

You are tasked with writing adversarial unit tests for Ceph Manager class `MgrCap` to expose latent bugs and contract divergences documented in its Intent Assessment file.

**References & Locations:**
- Target Source: `src/mgr/MgrCap.cc` / `src/mgr/MgrCap.h`
- Intent Assessment File: `/home/szuraski/BobOutput/Object History/MgrCap-intent.md`
  (Fallback if sandboxed to `/home/szuraski/ceph`: use relative path `../BobOutput/Object History/MgrCap-intent.md`)
- Raw History Corpus (reference): `/home/szuraski/BobOutput/Object History/v3/MgrCap/`
- Final HTML Output Directory: `/home/szuraski/BobOutput/HTML/`

**Step-by-Step Instructions:**

Step 1: Check whether a local branch matching `wip-sz-*mgrcap*` exists (`git branch --list 'wip-sz-*mgrcap*'`). If so, check it out. If not, create a new branch named `wip-sz-mgrcap-latent-bug-tests` from `ceph-origin/main`.

Step 2: Read the Intent Assessment file.
- Path: `/home/szuraski/BobOutput/Object History/MgrCap-intent.md` (if blocked by sandbox, try `../BobOutput/Object History/MgrCap-intent.md` via terminal read).
- Identify all functions flagged `DIVERGED` or `UNGROUNDED`. Extract the documented invariants, error conditions, and capability parsing contracts describing how current code deviates from historical intent.
- Do not stop after reading — proceed immediately to Step 3.

Step 3: Perform Git Archaeology. For each `DIVERGED` or `UNGROUNDED` defect identified in Step 2, run:
```
git log -S "<relevant_symbol>" --oneline -- src/mgr/MgrCap.cc
git blame src/mgr/MgrCap.cc | grep "<relevant_line>"
```
Record the 12-character short SHA for both the **Establishing Commit** and the **Breaking Commit**. Build GitHub hyperlinks: `https://github.com/ceph/ceph/commit/<sha>` — these will be embedded in the final HTML report.

Step 4: Write adversarial unit tests in `src/test/mgr/test_mgrcap.cc` following existing GoogleTest patterns (see `test_clusterstate.cc`, `test_daemonstate.cc`).
- Name tests: `TEST_F(MgrCapTest, LatentBug_<FunctionName>_<Issue>)`.
- Assert the **historically intended, correct behavior** — not the buggy current behavior. Tests must **fail** at `HEAD`; that failure is the desired outcome. Do NOT weaken or alter assertions to make tests pass against buggy code.
- Tests targeting the capability string parser must inject malformed tokens, truncated inputs, negative numbers, and invalid grant types that the intent file identifies as unchecked.
- Every assertion expected to fail at `HEAD` must use GTest `<<` streaming to print the Current (Buggy) State and Expected (Correct) State:
  ```cpp
  ASSERT_FALSE(cap.is_valid())
    << "Current: malformed cap string incorrectly parsed as valid"
    << "\nExpected: parse must fail and is_valid() must return false";
  ```
- Avoid bare `ASSERT_TRUE` / `ASSERT_EQ` with no message — every failing assertion must be self-explanatory from test output alone.
- Every test must use `EXPECT_EQ`, `EXPECT_NE`, `EXPECT_FALSE`, `EXPECT_TRUE`, `ASSERT_DEATH`, or `EXPECT_THROW` against specific return values and state fields. No trivial smoke tests.

Step 5: Update `src/test/CMakeLists.txt` to include the test target if adding a new test executable.

Step 6: Build the test binary:
```
./do_cmake.sh -DWITH_RADOSGW_LANCEDB=OFF
ninja -C build unittest_mgr_mgrcap
```

Step 7: Run the tests and capture output:
```
./build/bin/unittest_mgr_mgrcap --gtest_filter="*LatentBug*"
```
Record all test failures, crashes, assertion failures, or sanitiser reports. Perform an adversarial gap analysis: (1) method coverage for all diverged functions, (2) error paths and missing boundary checks, (3) boundary/edge cases and invalid capability strings, (4) capability state transitions. If any unexercised defect remains, add tests, rebuild, and re-run.

Step 8: Squash and commit the test suite:
```
git add src/test/mgr/test_mgrcap.cc src/test/CMakeLists.txt
git commit -m "test/mgr: add adversarial unit tests exposing latent bugs in MgrCap

Add unit tests asserting historical design contracts for MgrCap
based on intent assessment findings.

Assisted-by: IBM Bob"
```
Check `git log --oneline`. If a test commit already exists on this branch, use `git commit --amend` or `git reset --soft HEAD~1 && git commit` to fold new tests in. Do not use `git rebase -i`.

Step 9: Produce a Structured Summary Report and save it to `/home/szuraski/BobOutput/HTML/MgrCap_latent_bugs_report.html`. Include:
- **Summary Dashboard**: a table mapping each `LatentBug_*` test to its intent file finding, pass/fail status, and source location in `src/mgr/MgrCap.cc`.
- **Per-Finding Detail Sections**: precise defect LOC, GTest failure output (Current vs. Expected from `<<` messages), and clickable GitHub hyperlinks to both the Establishing Commit and Breaking Commit from Step 3.

---

### 4. MgrOpRequest

You are tasked with writing adversarial unit tests for Ceph Manager class `MgrOpRequest` to expose latent bugs and contract divergences documented in its Intent Assessment file.

**References & Locations:**
- Target Source: `src/mgr/MgrOpRequest.cc` / `src/mgr/MgrOpRequest.h`
- Intent Assessment File: `/home/szuraski/BobOutput/Object History/MgrOpRequest-intent.md`
  (Fallback if sandboxed to `/home/szuraski/ceph`: use relative path `../BobOutput/Object History/MgrOpRequest-intent.md`)
- Raw History Corpus (reference): `/home/szuraski/BobOutput/Object History/v3/MgrOpRequest/`
- Final HTML Output Directory: `/home/szuraski/BobOutput/HTML/`

**Step-by-Step Instructions:**

Step 1: Check whether a local branch matching `wip-sz-*mgropRequest*` exists (`git branch --list 'wip-sz-*mgropRequest*'`). If so, check it out. If not, create a new branch named `wip-sz-mgropRequest-latent-bug-tests` from `ceph-origin/main`.

Step 2: Read the Intent Assessment file.
- Path: `/home/szuraski/BobOutput/Object History/MgrOpRequest-intent.md` (if blocked by sandbox, try `../BobOutput/Object History/MgrOpRequest-intent.md` via terminal read).
- Identify all functions flagged `DIVERGED` or `UNGROUNDED`. Extract the documented invariants, error conditions, string formatting contracts, and lifecycle/flag state descriptions.
- Do not stop after reading — proceed immediately to Step 3.

Step 3: Perform Git Archaeology. For each `DIVERGED` or `UNGROUNDED` defect identified in Step 2, run:
```
git log -S "<relevant_symbol>" --oneline -- src/mgr/MgrOpRequest.cc
git blame src/mgr/MgrOpRequest.cc | grep "<relevant_line>"
```
Record the 12-character short SHA for both the **Establishing Commit** and the **Breaking Commit**. Build GitHub hyperlinks: `https://github.com/ceph/ceph/commit/<sha>` — these will be embedded in the final HTML report.

Step 4: Write adversarial unit tests in `src/test/mgr/test_mgropRequest.cc` following existing GoogleTest patterns (see `test_clusterstate.cc`, `test_daemonstate.cc`).
- Name tests: `TEST_F(MgrOpRequestTest, LatentBug_<FunctionName>_<Issue>)`.
- Assert the **historically intended, correct behavior** — not the buggy current behavior. Tests must **fail** at `HEAD`; that failure is the desired outcome. Do NOT weaken or alter assertions to make tests pass against buggy code.
- Tests targeting string formatting, serialization symmetry, or memory tracking must inject boundary values, null payloads, and truncated inputs identified as unchecked in the intent file.
- Every assertion expected to fail at `HEAD` must use GTest `<<` streaming to print the Current (Buggy) State and Expected (Correct) State:
  ```cpp
  ASSERT_EQ(req->get_flag(FLAG_PROFILE), true)
    << "Current: FLAG_PROFILE not set after profile mark"
    << "\nExpected: flag must be set when mark_profile() is called";
  ```
- Avoid bare `ASSERT_TRUE` / `ASSERT_EQ` with no message — every failing assertion must be self-explanatory from test output alone.
- Every test must use `EXPECT_EQ`, `EXPECT_NE`, `EXPECT_FALSE`, `EXPECT_TRUE`, `ASSERT_DEATH`, or `EXPECT_THROW`. No trivial smoke tests.

Step 5: Update `src/test/CMakeLists.txt` to include the test target if adding a new test executable.

Step 6: Build the test binary:
```
./do_cmake.sh -DWITH_RADOSGW_LANCEDB=OFF
ninja -C build unittest_mgr_mgropRequest
```

Step 7: Run the tests and capture output:
```
./build/bin/unittest_mgr_mgropRequest --gtest_filter="*LatentBug*"
```
Record all test failures, crashes, assertion failures, or sanitiser reports. Perform an adversarial gap analysis: (1) method coverage for all diverged functions, (2) error paths and missing boundary checks, (3) boundary/edge cases and invalid inputs, (4) lifecycle and flag state transitions. If any unexercised defect remains, add tests, rebuild, and re-run.

Step 8: Squash and commit the test suite:
```
git add src/test/mgr/test_mgropRequest.cc src/test/CMakeLists.txt
git commit -m "test/mgr: add adversarial unit tests exposing latent bugs in MgrOpRequest

Add unit tests asserting historical design contracts for MgrOpRequest
based on intent assessment findings.

Assisted-by: IBM Bob"
```
Check `git log --oneline`. If a test commit already exists on this branch, use `git commit --amend` or `git reset --soft HEAD~1 && git commit` to fold new tests in. Do not use `git rebase -i`.

Step 9: Produce a Structured Summary Report and save it to `/home/szuraski/BobOutput/HTML/MgrOpRequest_latent_bugs_report.html`. Include:
- **Summary Dashboard**: a table mapping each `LatentBug_*` test to its intent file finding, pass/fail status, and source location in `src/mgr/MgrOpRequest.cc`.
- **Per-Finding Detail Sections**: precise defect LOC, GTest failure output (Current vs. Expected from `<<` messages), and clickable GitHub hyperlinks to both the Establishing Commit and Breaking Commit from Step 3.

---

### 5. DaemonServer

You are tasked with writing adversarial unit tests for Ceph Manager class `DaemonServer` to expose latent bugs and contract divergences documented in its Intent Assessment file.

**References & Locations:**
- Target Source: `src/mgr/DaemonServer.cc` / `src/mgr/DaemonServer.h`
- Intent Assessment File: `/home/szuraski/BobOutput/Object History/DaemonServer-intent.md`
  (Fallback if sandboxed to `/home/szuraski/ceph`: use relative path `../BobOutput/Object History/DaemonServer-intent.md`)
- Raw History Corpus (reference): `/home/szuraski/BobOutput/Object History/v3/DaemonServer/`
- Final HTML Output Directory: `/home/szuraski/BobOutput/HTML/`

**Step-by-Step Instructions:**

Step 1: Check whether a local branch matching `wip-sz-*daemonserver*` exists (`git branch --list 'wip-sz-*daemonserver*'`). If so, check it out. If not, create a new branch named `wip-sz-daemonserver-latent-bug-tests` from `ceph-origin/main`.

Step 2: Read the Intent Assessment file.
- Path: `/home/szuraski/BobOutput/Object History/DaemonServer-intent.md` (if blocked by sandbox, try `../BobOutput/Object History/DaemonServer-intent.md` via terminal read).
- Identify all functions flagged `DIVERGED` or `UNGROUNDED`. Extract the documented invariants, error conditions, connection lifecycle contracts, and destructor cleanup requirements.
- Do not stop after reading — proceed immediately to Step 3.

Step 3: Perform Git Archaeology. For each `DIVERGED` or `UNGROUNDED` defect identified in Step 2, run:
```
git log -S "<relevant_symbol>" --oneline -- src/mgr/DaemonServer.cc
git blame src/mgr/DaemonServer.cc | grep "<relevant_line>"
```
Record the 12-character short SHA for both the **Establishing Commit** and the **Breaking Commit**. Build GitHub hyperlinks: `https://github.com/ceph/ceph/commit/<sha>` — these will be embedded in the final HTML report.

Step 4: Write adversarial unit tests in `src/test/mgr/test_daemonserver.cc` following existing GoogleTest patterns (see `test_clusterstate.cc`, `test_daemonstate.cc`).
- Name tests: `TEST_F(DaemonServerTest, LatentBug_<FunctionName>_<Issue>)`.
- Assert the **historically intended, correct behavior** — not the buggy current behavior. Tests must **fail** at `HEAD`; that failure is the desired outcome. Do NOT weaken or alter assertions to make tests pass against buggy code.
- Tests targeting connection lifecycle, concurrent connection resets, or destructor cleanup must exercise concurrent threads or teardown edge cases identified in the intent review.
- Every assertion expected to fail at `HEAD` must use GTest `<<` streaming to print the Current (Buggy) State and Expected (Correct) State:
  ```cpp
  ASSERT_EQ(server.active_connections(), 0)
    << "Current: " << server.active_connections() << " connections not cleaned up"
    << "\nExpected: 0 active connections after reset";
  ```
- Avoid bare `ASSERT_TRUE` / `ASSERT_EQ` with no message — every failing assertion must be self-explanatory from test output alone.
- Every test must use `EXPECT_EQ`, `EXPECT_NE`, `EXPECT_FALSE`, `EXPECT_TRUE`, `ASSERT_DEATH`, or `EXPECT_THROW`. No trivial smoke tests.

Step 5: Update `src/test/CMakeLists.txt` to include the test target if adding a new test executable.

Step 6: Build the test binary:
```
./do_cmake.sh -DWITH_RADOSGW_LANCEDB=OFF
ninja -C build unittest_mgr_daemonserver
```

Step 7: Run the tests and capture output:
```
./build/bin/unittest_mgr_daemonserver --gtest_filter="*LatentBug*"
```
Record all test failures, crashes, assertion failures, or sanitiser reports. Perform an adversarial gap analysis: (1) method coverage for all diverged functions, (2) error paths and missing boundary checks, (3) boundary/edge cases and invalid inputs, (4) concurrency, connection resets, and state transitions. If any unexercised defect remains, add tests, rebuild, and re-run.

Step 8: Squash and commit the test suite:
```
git add src/test/mgr/test_daemonserver.cc src/test/CMakeLists.txt
git commit -m "test/mgr: add adversarial unit tests exposing latent bugs in DaemonServer

Add unit tests asserting historical design contracts for DaemonServer
based on intent assessment findings.

Assisted-by: IBM Bob"
```
Check `git log --oneline`. If a test commit already exists on this branch, use `git commit --amend` or `git reset --soft HEAD~1 && git commit` to fold new tests in. Do not use `git rebase -i`.

Step 9: Produce a Structured Summary Report and save it to `/home/szuraski/BobOutput/HTML/DaemonServer_latent_bugs_report.html`. Include:
- **Summary Dashboard**: a table mapping each `LatentBug_*` test to its intent file finding, pass/fail status, and source location in `src/mgr/DaemonServer.cc`.
- **Per-Finding Detail Sections**: precise defect LOC, GTest failure output (Current vs. Expected from `<<` messages), and clickable GitHub hyperlinks to both the Establishing Commit and Breaking Commit from Step 3.
