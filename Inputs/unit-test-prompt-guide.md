# Writing Effective Bob Prompts for Unit Test Work

Notes from experience writing ceph-mgr unit test prompts for `launch-bob-agents.sh`.

---

## 1. Use numbered steps — not prose

Bob treats a vague instruction like "implement unit test coverage" as an invitation
to explore and summarise. A numbered sequence forces it to treat each step as a
concrete deliverable it must complete before moving on.

**Weak:**
> Create a branch and implement unit test coverage for DaemonServer.

**Strong:**
> Step 1: create a new git branch from the tip of ceph-origin/main.
> Step 2: cherry-pick X and Y.
> Step 3: write the tests.
> Step 4: update CMakeLists.txt.
> Step 5: build and run the tests to confirm they pass.

---

## 2. Explicitly forbid stopping after exploration

Bob's default behaviour is to read the relevant code, produce a summary of findings,
and consider the task complete. You must override this explicitly.

Add to every implementation prompt:

> Do not stop after reading — proceed immediately to the gap analysis and then
> to writing code.

For continuation tasks where the agent reads existing tests before writing new
ones, place the anti-escape instruction at the end of the read step, not as a
standalone sentence. Observed: without it, Bob reads the 4 900-line
test_activepymodules.cc, concludes the coverage looks good, and terminates.

---

## 3. Require ASSERTs on values, not just test completion

A test that constructs an object, calls a method, and returns without crashing is
**not** a meaningful test. Bob will write these by default if not told otherwise —
they pass trivially and catch nothing.

Require assertions that verify actual state:

> Every test must include ASSERT/EXPECT macros that verify the actual values of
> fields, return values, or observable side effects — not just that the code runs
> without crashing. A test with no assertions is not acceptable.

Examples of what to demand:
- `EXPECT_EQ(result, expected_value)` after calling a method
- `EXPECT_TRUE(obj.is_initialized())` after setup
- `EXPECT_EQ(map.size(), 3)` after inserting entries
- `EXPECT_STREQ(daemon.name.c_str(), "osd.0")` after parsing

Examples of what to reject (do not accept these alone):
- A test body that only constructs and destructs an object
- `SUCCEED()` with no other assertions
- Tests that only check the absence of a crash or exception

---

## 4. Point to existing tests as the pattern to follow

Bob writes better tests when it has a concrete reference. Always name the existing
test files explicitly.

> Write the tests in src/test/mgr/, following the patterns in the existing test
> files (e.g. test_clusterstate.cc, test_daemonstate.cc).

This steers Bob toward the correct fixture base class, include structure, and
CMakeLists.txt conventions already established in the project.

---

## 5. Give Bob the exact build and run commands

Without explicit commands, Bob will attempt to discover or configure the build
system from scratch. In the ceph-mgr worktrees this wasted 80+ turns as the agent
tried to run cmake directly, chased missing submodules, and never reached the
actual test work.

Always provide the full commands:

> Step N: if the build directory does not exist or is not configured, run
> `./do_cmake.sh` to configure it. Then build with:
> `ninja -C build unittest_mgr_<name>`. Run the test with:
> `./build/bin/unittest_mgr_<name>`.

This applies to any project with a non-trivial build setup — the more specific
the command, the fewer turns Bob wastes on discovery.

**The run must exit cleanly.** A test binary that crashes (exits with a signal,
`Exit code: unknown`, SIGABRT, SIGSEGV) is not a passing run — it is a test
failure that must be fixed before proceeding. Only a run that prints
`[  PASSED  ] N tests.` and exits with code 0 counts as passing. Make this
explicit in the prompt:

> The test run is only considered passing when the output contains
> `[  PASSED  ] N tests.` and the command exits with code 0. An `Exit code:
> unknown` or any signal-terminated exit is a crash — fix it before proceeding.

Also set `--max-turns` high enough for long tasks. The default (100) is too low
for tasks that include writing code, configuring a build, and running tests. Use
`bob run --max-turns 10000` for unit test work.

---

## 6. Specify branch setup requirements clearly

When cherry-picks are needed as prerequisites, list each PR URL separately and
specify the branch base. Bob will skip or mis-order these steps if they are buried
in prose.

> Step 1: create a new git branch from the tip of ceph-origin/main.
> Step 2: cherry-pick the scaffolding from <PR URL>.
> Step 3: cherry-pick the fix from <PR URL>.

### Branch naming convention

The defining characteristic of a branch is `wip-sz-<trackerID>` as the prefix,
e.g. `wip-sz-80176-daemonserver-unittests`. For new branches, use
`wip-sz-<trackerID>-words-with-hyphens`. If a branch for the tracker already
exists, use its name exactly as-is regardless of capitalisation or style.

**Check for an existing branch first.** A branch for the tracker may already
exist (e.g. from earlier work). The step should read:

> Step 1: check whether a local branch matching `wip-sz-<ID>*` already exists
> (`git branch --list 'wip-sz-<ID>*'`). If it does, check it out. If not,
> create a new branch named `wip-sz-<ID>-<short-description>` from the tip of
> `ceph-origin/main`.

Without this check, Bob creates a new branch with a different name and abandons
any prior work sitting on the existing one.

**Branch creation is mandatory even for review tasks.** If the task involves
writing or modifying any files (including a markdown review output), always
include a branch step. A genuinely read-only task that produces no files is the
only exception — and that is rare.

---

## 7. Commit strategy — squash, don't stack

Each tracker should produce the fewest logical commits needed to tell the story
of the work. "More tests" is not a logical commit — it is noise in the history.

### Rules

1. **Do all the work first, then commit once.** Complete the full gap-analysis
   loop before making any commit. Do not commit after the first passing run and
   again after gap-fill — that produces the stacking pattern we want to avoid.

2. **Squash into existing commits when a prior session left work.** If a test
   commit already exists on the branch (visible via `git log --oneline`), use
   `git commit --amend` or a soft-reset+recommit
   (`git reset --soft HEAD~1 && git commit`) to fold new tests in.
   **Do not instruct `git rebase -i`** — interactive rebase fails with
   `Exit code: 128` in these worktrees because of submodule symlink issues
   (`src/arrow`, `ceph-erasure-code-corpus`). Agents that hit this error tend to
   give up or thrash rather than fall back gracefully.

3. **Commit messages must describe coverage, not activity, and must be concise.**
   The subject line names the file/scope and the problem being solved. The body
   (if any) is a short paragraph — one or two sentences — stating what was broken
   or missing and how the tests address it. Do **not** produce multi-section
   breakdowns with headers, bullet lists, or per-dimension inventories in the
   commit message; that level of detail belongs in the gap-analysis notes, not in
   git history.

   Bad:
   > "add more tests for MgrClient"

   Also bad (over-verbose):
   > "test/mgr: unit tests for ServiceMap
   >
   > Method coverage (Dimension 1):
   > - Daemon: encode/decode …
   > - Service: encode/decode …
   > …
   > Error paths (Dimension 2):
   > …"

   Good:
   > "test/mgr: add unit tests for MgrClient"
   >
   > "test/mgr: add unit tests for ServiceMap covering encode/decode, state
   > transitions, and edge cases"

   Aim for a subject line that names the scope, plus an optional one-sentence body
   that summarises the broad areas covered (e.g. "encode/decode, error paths, state
   transitions") without listing every individual function or test case.

   The commit footer must always contain exactly these three lines (in this order,
   with no blank lines between them):

   ```
   Fixes: https://tracker.ceph.com/issues/<ID>
   Signed-off-by: Steven Zuraski <steven.zuraski@ibm.com>
   Assisted-by: IBM Bob
   ```

   Replace `<ID>` with the tracker number for the branch. These lines must appear
   as the last lines of every commit on a unit-test branch.

4. **Never commit analysis output.** Gap analysis notes, review documents, and
   scratch files go to `/home/szuraski/BobOutput/agent-<N>/<ID>-<desc>-run<N>/`
   on the remote host. Nothing in that directory belongs in git.

Add to every prompt:

> Once all four gap lists are genuinely empty and all tests pass, squash all test
> work into the fewest logical commits needed: check whether a previous test
> commit already exists on this branch (git log --oneline); if it does, use
> git commit --amend or a soft-reset+recommit (git reset --soft HEAD~1 &&
> git commit) to fold new tests into it rather than creating a separate "more
> tests" commit — note that git rebase -i may fail in this worktree due to
> submodule symlink issues, so prefer amend or soft-reset. Each commit must
> describe what behaviour is covered, not just that tests were added.

Observed behaviour without this instruction:
- Each reprompt session added a new commit on top: "expand coverage", "gap-fill",
  "more tests" — all of which should have been squashed into the original commit
- Agent 1 accumulated three separate REVIEW.md commits across three sessions

Observed failure mode with `git rebase -i`:
- Worktrees with submodule symlinks (`src/arrow`, `ceph-erasure-code-corpus`)
  cause interactive rebase to exit 128 immediately
- Some agents halt entirely; others loop retrying the same failing command
- The safe fallback is always `git commit --amend` for a single prior commit, or
  `git reset --soft HEAD~N && git commit` for squashing N commits

---

## 8. Include the tracker URL at the start of the prompt

The `launch-bob-agents.sh` script prepends the tracker URL to the prompt message.
Bob will fetch the tracker JSON to read the issue description, which gives it
context about the target class and acceptance criteria without you having to
repeat it all in the prompt.

---

## 9. Drive iteration — make the loop concrete and non-escapable

Bob's default behaviour after a passing test suite is to declare success. "Repeat
until confident" is not enough — Bob decides when it is confident, which is
immediately after the first pass. Observed: agent 3 added 31 tests, declared the
task done, and only added 19 more when reprompted. All 19 were found on the first
re-read. The loop must be structured so Bob cannot exit it by self-assessment.

### The four dimensions of coverage

Every iteration must explicitly audit all four:

1. **Method coverage** — every public method has at least one test that calls it
   and verifies a return value or observable side effect.
2. **Error paths** — every early return, guard clause, or error code path has a
   test that reaches it and asserts the error value/state.
3. **Boundary and edge cases** — null inputs, empty collections, zero/max values,
   pre-condition violations.
4. **State machine transitions** — if the class has internal state (flags, maps,
   counters), test the transitions: uninitialised→initialised, alive→dead,
   empty→populated→replaced.

### Required structure in the prompt

Replace "repeat until confident" with a concrete mandatory loop:

> After the first passing run, perform the following gap analysis before
> committing. For each of the four coverage dimensions — (1) method coverage,
> (2) error paths, (3) boundary/edge cases, (4) state transitions — list every
> item in `<Class>`'s implementation that is not yet exercised. If any list is
> non-empty, write tests for all items in it, rebuild, rerun, and repeat the gap
> analysis from scratch. Only proceed to commit when all four lists are empty.
> Do not shortcut this — a gap analysis that produces an empty list on the first
> pass is almost certainly wrong.

The final sentence matters: it pre-empts Bob producing a trivially empty list to
escape the loop.

For review tasks, mirror the same structure:

> After your first pass, produce a gap list covering the same four dimensions.
> If any list is non-empty, update REVIEW.md with findings and repeat. Do not
> conclude until the gap list is empty and you have re-read the implementation
> one final time looking specifically for anything the gap list could have missed.

`--max-turns` in `launch-bob-agents.sh` is set to `10000` to give agents enough
budget to run this loop many times without hitting an artificial ceiling.

---

## 10. Return to the agent branch when done

Each worktree has a stable `agent/<N>` branch that serves as its neutral home
state. The launch script checks this branch out automatically after `bob run`
exits, but the prompt should also instruct the agent to do it explicitly as the
final step — both as a safety net and to make the clean end-state visible in the
terminal:

> When all work is committed, run: `git checkout agent/<N>`

This makes it unambiguous which worktree is in use and leaves the worktree in a
predictable state for the next run.

---

## 11. Keep comments minimal

Test code that ships as part of the product must follow the same comment discipline
as production code. Gap-analysis runs leave behind comments that made sense during
authoring but have no value in the final commit.

**Prohibited comment patterns:**

- Gap-tracking tags: `// GAP-S-3:`, `// GAP-B-4:`, `// Gap-fill`, etc.
- Run markers: `// ---------------------------------------------------------------------------`, `// Gap-fill tests — Run 3`, `// Added in run 2`, etc.
- Restatements of the test name or what the next line obviously does:
  `// Test that encode round-trips correctly` immediately above `TEST(Foo, EncodeRoundTrip)`

**Acceptable comments:**

- Explanations of *why* a specific value or sequence was chosen when it is not obvious from the code
- Notes on non-obvious setup required by the implementation under test

Add to every implementation prompt:

> Do not add comments that track which gap or run a test came from. Do not add
> comments that restate what the test name or the next line of code already says.
> Only add a comment when it explains something that would not be obvious to a
> reader unfamiliar with the implementation.

---

## Template — implementation task

```
https://tracker.ceph.com/issues/<ID>
Start work on this tracker: <Title>. Step 1: check whether a local branch
matching wip-sz-<ID>* already exists (git branch --list 'wip-sz-<ID>*'). If it
does, check it out. If not, create a new branch named wip-sz-<ID>-<short-description>
from the tip of ceph-origin/main. Step 2: write the unit tests for <Class> in
src/test/mgr/, following the patterns in the existing test files
(test_clusterstate.cc, test_daemonstate.cc). Do not stop after reading the
implementation — proceed immediately to writing code. Every test must include
ASSERT/EXPECT
macros that verify actual values — not just that the code runs without crashing.
A test with no assertions is not acceptable. Step 3: update CMakeLists.txt to
build the new test. Step 4: if the build directory does not exist or is not
configured, run ./do_cmake.sh to configure it. Then build with:
ninja -C build unittest_mgr_<name>. Run the test with:
./build/bin/unittest_mgr_<name>. The run is only considered passing when the
output contains [  PASSED  ] N tests. and the command exits with code 0 — an
Exit code: unknown or signal-terminated exit is a crash that must be fixed
before proceeding. Step 5: perform a gap analysis across all four dimensions:
(1) method coverage — every public method called and its return value verified;
(2) error paths — every guard clause, early return, and error code reached and
asserted; (3) boundary/edge cases — null inputs, empty collections, zero/max
values, pre-condition violations; (4) state transitions — every internal state
change exercised. Write gap analysis notes to
/home/szuraski/BobOutput/agent-<N>/<ID>-<desc>-run<N>/ — do not commit these
notes. If any gaps are found, add tests, rebuild, rerun, and repeat the gap
analysis from scratch. Do not shortcut this — a gap analysis that produces an
empty list on the first pass is almost certainly wrong. Step 6: once all four
gap lists are genuinely empty and all tests pass, squash all test work into the
fewest logical commits needed: check whether a previous test commit already
exists on this branch (git log --oneline); if it does, use git commit --amend
or a soft-reset+recommit (git reset --soft HEAD~1 && git commit) to fold new
tests into it rather than creating a separate "more tests" commit — note that
git rebase -i may fail in this worktree due to submodule symlink issues, so
prefer amend or soft-reset. Each commit message must be concise: a subject line
naming the scope and a short body (one or two sentences) describing what was
missing and how the tests address it — no section headers, no bullet lists, no
per-dimension inventories. Every commit must end with this footer (no blank lines
between the three lines):

Fixes: https://tracker.ceph.com/issues/<ID>
Signed-off-by: Steven Zuraski <steven.zuraski@ibm.com>
Assisted-by: IBM Bob

When all work is committed, run: git checkout agent/<N>
```
