---
tracker: https://tracker.ceph.com/issues/80176
---
You are tasked with writing adversarial unit tests for Ceph Manager class `PyModuleRegistry` to expose latent bugs and contract divergences documented in its Intent Assessment file.

**References & Locations:**
- Target Source: `src/mgr/PyModuleRegistry.cc` / `src/mgr/PyModuleRegistry.h`
- Intent Assessment File: `/home/szuraski/BobOutput/Object History/PyModuleRegistry-intent.md`
  (Fallback if sandboxed to `/home/szuraski/ceph`: use relative path `../BobOutput/Object History/PyModuleRegistry-intent.md`)
- Raw History Corpus (reference): `/home/szuraski/BobOutput/Object History/v3/PyModuleRegistry/`
- Final HTML Output Directory: `/home/szuraski/BobOutput/HTML/`

Step 1: Check whether a local branch matching `wip-sz-*pymoduleregistry*` exists (`git branch --list 'wip-sz-*pymoduleregistry*'`). If so, check it out. If not, create a new branch named `wip-sz-pymoduleregistry-latent-bug-tests` from `ceph-origin/main`.

Step 2: Read the Intent Assessment file. Identify all functions flagged `DIVERGED` or `UNGROUNDED`. Extract the documented invariants, error conditions, and critiques describing how current code deviates from historical intent. Do not stop after reading — proceed immediately to Step 3.

Step 3: Perform Git Archaeology. For each `DIVERGED` or `UNGROUNDED` defect identified in Step 2, run:
```
git log -S "<relevant_symbol>" --oneline -- src/mgr/PyModuleRegistry.cc
git blame src/mgr/PyModuleRegistry.cc | grep "<relevant_line>"
```
Record the 12-character short SHA for both the **Establishing Commit** and the **Breaking Commit**. Build GitHub hyperlinks: `https://github.com/ceph/ceph/commit/<sha>` — these will be embedded in the final HTML report.

Step 4: Write adversarial unit tests in `src/test/mgr/test_pymoduleregistry.cc` following existing GoogleTest patterns (see `test_clusterstate.cc`, `test_daemonstate.cc`).
- Name tests: `TEST_F(PyModuleRegistryTest, LatentBug_<FunctionName>_<Issue>)`.
- Assert the **historically intended, correct behavior** — not the buggy current behavior. Tests must **fail** at `HEAD`; that failure is the desired outcome. Do NOT weaken or alter assertions to make tests pass against buggy code.
- Every assertion expected to fail at `HEAD` must use GTest `<<` streaming to print the Current (Buggy) State and Expected (Correct) State.
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
- **Per-Finding Detail Sections**: precise defect LOC, GTest failure output (Current vs. Expected), and clickable GitHub hyperlinks to both the Establishing Commit and Breaking Commit from Step 3.
