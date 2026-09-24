---
tracker: https://tracker.ceph.com/issues/80175
---
You are tasked with writing adversarial unit tests for Ceph Manager class `DaemonServer` to expose latent bugs and contract divergences documented in its Intent Assessment file.

**References & Locations:**
- Target Source: `src/mgr/DaemonServer.cc` / `src/mgr/DaemonServer.h`
- Intent Assessment File: `/home/szuraski/BobOutput/Object History/DaemonServer-intent.md`
  (Fallback if sandboxed to `/home/szuraski/ceph`: use relative path `../BobOutput/Object History/DaemonServer-intent.md`)
- Raw History Corpus (reference): `/home/szuraski/BobOutput/Object History/v3/DaemonServer/`
- Final HTML Output Directory: `/home/szuraski/BobOutput/HTML/`

Step 1: Check whether a local branch matching `wip-sz-*daemonserver*` exists (`git branch --list 'wip-sz-*daemonserver*'`). If so, check it out. If not, create a new branch named `wip-sz-daemonserver-latent-bug-tests` from `ceph-origin/main`.

Step 2: Read the Intent Assessment file. Identify all functions flagged `DIVERGED` or `UNGROUNDED`. Extract the documented invariants, error conditions, connection lifecycle contracts, and destructor cleanup requirements. Do not stop after reading — proceed immediately to Step 3.

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
- Every assertion expected to fail at `HEAD` must use GTest `<<` streaming to print the Current (Buggy) State and Expected (Correct) State.
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
- **Per-Finding Detail Sections**: precise defect LOC, GTest failure output (Current vs. Expected), and clickable GitHub hyperlinks to both the Establishing Commit and Breaking Commit from Step 3.
