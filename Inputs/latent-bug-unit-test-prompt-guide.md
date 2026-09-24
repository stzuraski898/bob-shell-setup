# Bug-Hunting Unit Test Prompt Guide (v2.0)

A prompt engineering guide for instructing AI agents (such as IBM Bob) to write **adversarial unit tests** based on historical intent analysis and latent bug findings in Ceph Manager (`ceph-mgr`).

Unlike conventional unit test prompts that aim for passing tests or code coverage verification, this guide targets **bug exposure**: instructing agents to ingest pre-computed **Intent Assessment files**, identify functions flagged with divergences or ungrounded behaviors, and write targeted test cases designed to **fail against existing bugs or prove discrepancies between historical design contracts and actual code behavior**.

---

## 1. Intent Assessment File Locations & Architecture

Agents must not rely on humans manually transcribing individual bugs into the prompt. Instead, prompts must direct agents to read the structured intent artefacts generated during historical assessment.

### Standard Intent File Paths

All intent files live on the host filesystem in standard locations:

```
/home/szuraski/BobOutput/Object History/
  <ClassName>-intent.md      ← Primary per-class intent markdown file
```

- **Per-Class Intent Markdown**: `/home/szuraski/BobOutput/Object History/<ClassName>-intent.md` (e.g., `DaemonServer-intent.md`, `DaemonState-intent.md`, `Gil-intent.md`, `ThreadMonitor-intent.md`, `MgrOpRequest-intent.md`, `MgrClient-intent.md`).
- **Aggregated HTML Assessment Explorer**: `Outputs/ceph-mgr-intents-assessment.html` (or `dataset.json` / `parsed_intents.json` in repository setups).
- **Raw Git Corpus (if deeper diff context is needed)**: `/home/szuraski/BobOutput/Object History/v3/<ClassName>/` (contains `commits.txt`, `blame.txt`, `functions.txt`, and `diffs/<sha>.diff`).

### How Agents Must Ingest Intent Files

Each `<ClassName>-intent.md` contains per-function assessments structured with standardized status tags:

| Status Flag | Meaning in Intent File | Agent Action |
|---|---|---|
| `DIVERGED` | The current implementation directly violates an invariant, contract, or error condition established in git history. | **Primary target.** Write tests that assert the historically intended contract; the test is expected to fail on `HEAD`. |
| `UNGROUNDED` | Code exhibits observable behavior, unvalidated stream extractions, or assumptions with no commit grounding or missing error checks. | **Secondary target.** Write tests supplying invalid tokens, truncated inputs, or edge boundaries to expose undefined behavior or silent failures. |
| `OVERCAUTIOUS` | Defensive checks or redundant guards masking underlying issues. | Audit for stale workarounds or dead code paths. |
| `CLEAN` / `OK` | Implementation satisfies documented historical intent. | Standard regression coverage only (low priority for bug hunting). |

Agents should be instructed to parse `<ClassName>-intent.md`, locate every function tagged with `DIVERGED` or `UNGROUNDED` in its `Implementation critique` / `Divergence` section, and extract the documented invariants and error conditions.

---

## 2. Core Philosophy: Adversarial Test Generation

### The Blind Spot of Standard Test Generation
Standard unit test generators read code at `HEAD` and write assertions that mirror what the code currently does. When the code contains a latent bug, omission, race condition, or diverged contract, standard tests simply codify and legitimize the buggy behavior.

### Ground Truth via Intent Artefacts
The intent files reconstruct historical design intent from git history, commit messages, PR reviews, and architectural invariants.

Adversarial tests derive their assertions from **intended invariants**, not current code lines:
- If `<ClassName>-intent.md` establishes that a method must reject null pointers or malformed inputs with `-EINVAL`, but `HEAD` silently crashes or ignores errors, the test **must assert `-EINVAL`** (and will fail on the buggy code).
- If `<ClassName>-intent.md` notes that a state copy must be acquired under a lock, or stream extraction must verify `good()` before returning success, the test **must craft inputs that trigger the unchecked stream condition or test concurrent integrity**.

---

## 3. Structural Prompting Rules for Bug-Exposing Tests

To ensure the AI agent autonomously discovers and targets latent bugs from the intent files without human hand-holding or weakening assertions, apply the following prompt rules:

### Rule 1: Point to the Intent File Path in Step 1
Explicitly instruct the agent where to find the intent file for the target class:

> `Read /home/szuraski/BobOutput/Object History/<ClassName>-intent.md (or ../BobOutput/Object\ History/<ClassName>-intent.md if the workspace is sandboxed to the ceph tree). Scan all functions in the class, identify every function marked DIVERGED or UNGROUNDED, and list the specific contract violations to target.`

> **Path Fallback Rule:** If the agent's workspace is set to `/home/szuraski/ceph`, the intent file at an absolute path outside the workspace may be blocked by sandbox restrictions. Always provide **both** the absolute path and a relative path (e.g. `../BobOutput/Object History/<ClassName>-intent.md`) in the prompt, and instruct the agent to try the relative path if the absolute one fails.

### Rule 2: Explicitly Forbid "Assertion Softening"
Bob will intuitively try to make all tests pass by changing assertions to match buggy behavior. **You must forbid this explicitly.**

> **Mandatory Prompt Instruction:**
> "Do NOT alter or weaken test assertions to accommodate bugs or diverged behavior in the source code. The tests MUST assert the intended behavior documented in `<ClassName>-intent.md`. If a test fails, aborts, or throws because of a latent defect in `src/mgr/`, that failure is the desired outcome. Document all failing tests in your final summary."

### Rule 3: Demand State-Checking Assertions and Boundary Payloads
Forbid trivial smoke tests (`EXPECT_NO_THROW`, simple constructor-destructor runs):
- Every test must use `EXPECT_EQ`, `EXPECT_NE`, `EXPECT_FALSE`, `EXPECT_TRUE`, `ASSERT_DEATH`, or `EXPECT_THROW` against specific return values and state fields.
- Tests targeting stream parsers (flagged in intent files as missing extraction checks) must inject invalid tokens, incomplete records, negative numbers, and truncated streams.
- Tests targeting locks and thread lifecycles must exercise concurrent threads or test teardown edge cases identified in the intent review.

### Rule 4: Provide Exact Build and Test Execution Commands
Provide concrete Ninja build targets and binary execution commands to eliminate discovery thrashing:
```bash
./do_cmake.sh -DWITH_RADOSGW_LANCEDB=OFF   # add flag if lancedb dependency fails
ninja -C build unittest_mgr_<name>
./build/bin/unittest_mgr_<name> --gtest_filter="*LatentBug*"
```

### Rule 5: Isolate Failing/Bug-Exposing Tests
To maintain CI cleanliness when committing reproducers:
- Name the bug-exposing tests clearly: `TEST_F(<ClassName>Test, LatentBug_<Method>_<Issue>)`.
- If required by the repository workflow, annotate known failing tests with `DISABLED_` or place them in a dedicated test suite with tracker issue links.

### Rule 6: Mandate Descriptive Assertions with Current vs. Expected Values

Silent assertion failures make triage harder. Every assertion that is **expected to fail at HEAD** must stream a human-readable message showing the current (buggy) value and the expected (correct) value.

> **Mandatory Prompt Instruction:**
> For every assertion that is expected to fail at HEAD, use GTest's `<<` stream operator to print the exact **Current (Buggy) State** and **Expected (Correct) State** under the contract. For example:
> ```cpp
> ASSERT_FALSE(exists)
>   << "Current: empty device STILL EXISTS (leaked)"
>   << "\nExpected: empty device should be pruned and NOT exist";
>
> ASSERT_EQ(device->wear_level, -1.0f)
>   << "Current wear_level: " << device->wear_level << "f (corrupt string parsed as valid 0.0f)"
>   << "\nExpected: -1.0f (unknown/parse failure sentinel)";
> ```
> Avoid bare `ASSERT_TRUE` / `ASSERT_FALSE` / `ASSERT_EQ` with no message — every failing assertion must be immediately self-explanatory from the test output alone.

### Rule 7: Enforce Automatic Git Archaeology

Do not leave git history exploration as an implicit follow-up. Make it a mandatory, numbered step so the agent compiles commit provenance **before** writing the summary report.

> **Mandatory Prompt Instruction:**
> Before writing the final summary, use git tools to locate:
> 1. The **Establishing Commit** — the commit that first introduced the design contract, invariant, or related helper (use `git log -S "<symbol>" --oneline` or `git log -p -- <file>`).
> 2. The **Breaking Commit** — the commit that introduced the defect, omission, or regression (`git log -S "<broken_symbol>"`, `git blame <file>`).
>
> Record the 12-character short SHA for each and build a GitHub hyperlink:
> ```
> https://github.com/ceph/ceph/commit/<sha>
> ```
> Include these links in the final HTML summary report alongside each finding.

---

## 4. Generic Reusable Prompt Template

Below is the generic prompt template. You only need to supply `<ClassName>`, `<TargetSource>`, `<TargetHeader>`, `<trackerID>`, and `<test_binary_name>` — the agent reads the intent file to discover the bugs autonomously:

```markdown
You are tasked with writing adversarial unit tests for Ceph Manager class `<ClassName>` to expose latent bugs and contract divergences documented in its Intent Assessment file.

### References & Locations:
- Target Source: `src/mgr/<TargetSource>.cc` / `src/mgr/<TargetHeader>.h`
- Intent Assessment File: `/home/szuraski/BobOutput/Object History/<ClassName>-intent.md`
  (Fallback if sandboxed to `/home/szuraski/ceph`: use relative path `../BobOutput/Object History/<ClassName>-intent.md`)
- Raw History Corpus (reference): `/home/szuraski/BobOutput/Object History/v3/<ClassName>/`
- Final HTML Output Directory: `/home/szuraski/BobOutput/HTML/`

### Step-by-Step Instructions:

Step 1: Check whether a local branch matching `wip-sz-<trackerID>*` exists (`git branch --list 'wip-sz-<trackerID>*'`). If so, check it out. If not, create a new branch named `wip-sz-<trackerID>-<classname>-latent-bug-tests` from `ceph-origin/main`.

Step 2: Read the Intent Assessment file.
- Path: `/home/szuraski/BobOutput/Object History/<ClassName>-intent.md`
  (If blocked by sandbox, try `../BobOutput/Object History/<ClassName>-intent.md` via terminal read.)
- Identify all functions flagged with `DIVERGED` or `UNGROUNDED`.
- Extract the documented invariants, error conditions, and critiques describing how current code deviates from historical intent.
- Do not stop after reading — proceed immediately to Step 3.

Step 3: Perform Git Archaeology.
For each `DIVERGED` or `UNGROUNDED` defect identified in Step 2, run git diagnostics to locate:
1. The **Establishing Commit** — the commit that first introduced the design contract, invariant, or related helper:
   ```
   git log -S "<relevant_symbol>" --oneline -- src/mgr/<TargetSource>.cc
   git log -p -- src/mgr/<TargetSource>.cc | grep -A5 "<relevant_symbol>"
   ```
2. The **Breaking Commit** — the commit that introduced the bug, omission, or regression:
   ```
   git log -S "<broken_symbol>" --oneline -- src/mgr/<TargetSource>.cc
   git blame src/mgr/<TargetSource>.cc | grep "<relevant_line>"
   ```
Record the 12-character short SHA for each commit. Build GitHub hyperlinks in the form:
`https://github.com/ceph/ceph/commit/<sha>`
These links will be embedded in the final HTML report.

Step 4: Write adversarial unit tests in `src/test/mgr/test_<test_binary_name>.cc` following existing GoogleTest patterns.
- For each `DIVERGED` or `UNGROUNDED` finding, create dedicated tests named `TEST_F(<ClassName>Test, LatentBug_<FunctionName>_<IssueDescription>)`.
- **Assert Correct Contracts, Not Buggy Realities**: Write all assertions against the **historically intended, correct behavior** (the design specification). When run against buggy `HEAD`, the tests must **fail** (non-zero exit code), acting as a regression shield. Do NOT write assertions that verify the bug is present (i.e., do not assert the buggy outcome so the test passes at `HEAD`).
- **Descriptive Failure Messages**: For every assertion expected to fail at `HEAD`, append a `<<` streaming message that clearly states the Current (Buggy) State and Expected (Correct) State:
  ```cpp
  ASSERT_FALSE(exists)
    << "Current: empty device STILL EXISTS (leaked)"
    << "\nExpected: empty device should be pruned and NOT exist";

  ASSERT_EQ(device->wear_level, -1.0f)
    << "Current wear_level: " << device->wear_level << "f (corrupt string parsed as valid 0.0f)"
    << "\nExpected: -1.0f (unknown/parse failure sentinel)";
  ```
- Avoid bare `ASSERT_TRUE` / `ASSERT_EQ` with no message — every assertion must be self-explanatory from test output alone.

Step 5: Update `src/test/CMakeLists.txt` to include the test file/target if adding a new test executable.

Step 6: Build the test binary:
  ```
  ./do_cmake.sh -DWITH_RADOSGW_LANCEDB=OFF   # add -DWITH_RADOSGW_LANCEDB=OFF if lancedb fails
  ninja -C build unittest_mgr_<test_binary_name>
  ```

Step 7: Run the tests and capture output:
  ```
  ./build/bin/unittest_mgr_<test_binary_name> --gtest_filter="*LatentBug*"
  ```
  Record all test failures, crashes, assertion failures, or sanitiser reports.

Step 8: Squash and commit the test suite:
  ```
  test/mgr: add adversarial unit tests exposing latent bugs in <ClassName>

  Add unit tests asserting historical design contracts for <ClassName>
  based on intent assessment findings.

  Fixes: https://tracker.ceph.com/issues/<trackerID>
  Assisted-by: IBM Bob
  ```
  Note: Check `git log --oneline`. If a test commit already exists on this branch, use `git commit --amend` or soft-reset (`git reset --soft HEAD~1 && git commit`) to fold new tests in. Do not use `git rebase -i`.

Step 9: Produce a Structured Summary Report and save it to `/home/szuraski/BobOutput/HTML/<ClassName>_latent_bugs_report.html`.
Structure the HTML report as follows:
- **Summary Dashboard**: a table mapping each `LatentBug_*` test to its intent file finding, pass/fail status, and source location in `src/mgr/`.
- **Per-Finding Detail Sections**: for each finding, include:
  - The precise lines of code (LOC) in `src/mgr/<TargetSource>.cc` that contain the defect.
  - The GTest failure output (Current State vs. Expected State from the `<<` messages).
  - Clickable GitHub hyperlinks to both the **Establishing Commit** and **Breaking Commit** discovered in Step 3.
```

---

## 5. Summary Checklist for Launching Agents

- [ ] `<ClassName>-intent.md` exists in `/home/szuraski/BobOutput/Object History/`.
- [ ] Prompt provides **both** the absolute path and relative fallback path (`../BobOutput/Object History/<ClassName>-intent.md`) for sandboxed workspace environments.
- [ ] Prompt directs the agent to read the intent file and filter for `DIVERGED` and `UNGROUNDED` sections.
- [ ] Prompt explicitly forbids weakening assertions to pass against buggy `HEAD` code (**Rule 2**).
- [ ] Prompt mandates **asserting the correct contract** (not the buggy reality) so that tests fail at `HEAD` (**Rule 4 / Step 4**).
- [ ] Every assertion uses GTest `<<` streaming to print **Current (Buggy) State** vs **Expected (Correct) State** (**Rule 6**).
- [ ] Git archaeology step is included: agent must find the **Establishing Commit** and **Breaking Commit** for each defect and produce GitHub hyperlinks (**Rule 7 / Step 3**).
- [ ] Exact build and test runner commands (`ninja -C build unittest_mgr_<test_binary_name>`) are specified, including the `-DWITH_RADOSGW_LANCEDB=OFF` fallback flag.
- [ ] Branch naming (`wip-sz-<trackerID>-*`) and commit squashing instructions are included.
- [ ] Final HTML report save location (`/home/szuraski/BobOutput/HTML/<ClassName>_latent_bugs_report.html`) is specified, with Summary Dashboard and per-finding detail sections.

---

## 6. Key Lessons Learned (from v1.0 to v2.0)

| Issue | Root Cause | Fix Applied |
|---|---|---|
| Agent wrote tests that **passed at HEAD** by asserting the bug was present | Prompt ambiguity: "exposing the bug" was interpreted as verifying its presence, not asserting correct behavior | Rule 6 and Step 4 now mandate **asserting the contract** so tests fail at HEAD |
| Git archaeology required a **second prompt turn** | No explicit instruction to run `git log -S` / `git blame` before writing the report | Rule 7 and Step 3 are now mandatory, producing commit SHAs and GitHub links in the first run |
| Agent failed to read the intent file due to **sandbox path restrictions** | Prompt only specified the absolute path, which was blocked when workspace ≠ `/home/szuraski` | Rule 1 and Step 2 now require both absolute and relative fallback paths |
| Assertion failures were **silent** — no indication of what went wrong | No instruction to add `<<` messages to assertions | Rule 6 mandates descriptive `<<` streaming on every assertion expected to fail at HEAD |
| `do_cmake.sh` failed due to missing **lancedb** dependency | Build flag omitted from original template | Step 6 now includes `-DWITH_RADOSGW_LANCEDB=OFF` as a documented fallback |
