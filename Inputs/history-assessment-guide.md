# History Assessment Guide

A prompting strategy for producing per-class intent artefacts that test-writing agents
can reference to understand what each function *should* be doing — not just what it
currently does.

---

## Architecture

Assessment is split into two stages:

```
Stage 1 — Shell script (runs once on sockeni07, no AI involved)
  collect-object-history-v3.sh
    → writes raw git data to /home/szuraski/BobOutput/Object History/v3/<ClassName>/

  Per-class output:
    commits.txt        one-liner per non-merge commit touching .cc ∪ .h (newest first)
    blame.txt          git blame -w -M -C on .cc and .h
    functions.txt      ctags function list: name | file:line
    diffs/
      <sha>.diff       git show scoped to .cc and .h for every commit in commits.txt

Stage 2 — AI assessment agent (reads raw corpus, writes intent artefact)
  reads:  /home/szuraski/BobOutput/Object History/v3/<ClassName>/
  writes: /home/szuraski/BobOutput/Object History/<ClassName>-intent.md
```

**AI agents never run git commands.** All git interaction happened in Stage 1.
Re-run the collection script after a significant rebase to refresh the corpus.

---

## Purpose

Unit-test agents work exclusively from the current source code. This creates a
critical blind spot: a function whose implementation was wrong, temporarily broken,
or refactored mid-development will produce tests that enshrine the wrong behaviour.
Git history contains the authoritative record of *intended* behaviour — commit
messages, the sequence of deliberate changes, and the pattern of bug fixes all encode
design intent that is invisible at `HEAD`.

This guide tells a **history assessment agent** how to reason over that raw corpus,
extract per-function intent, and write a structured artefact that test-writing agents
can consume without ambiguity.

The key insight is that the assessment agent does not need pre-computed SHA lists or
evidence tags. It can reason directly: "these diff hunks are in the function's line
range, therefore this commit changed this function." That is more reliable than any
collection-time heuristic, and it enables richer judgments — "this commit only
changed a comment" vs "this commit rewrote the core dispatch logic".

---

## Output location

Intent artefacts live in a single shared directory on the host, alongside the older
curator artefacts. All test-writing agents read from the same location.

```
/home/szuraski/BobOutput/Object History/
  <ClassName>-intent.md      ← one file per class assessed
```

Example:

```
/home/szuraski/BobOutput/Object History/
  DaemonServer-intent.md
  MgrClient-intent.md
  ClusterState-intent.md
```

**Never stage or commit anything inside `Object History/`.** These files are reference
artefacts for AI agents — they live on the host filesystem, not in the repository.
If a class is re-assessed (e.g. after a rebase), overwrite the existing file in place;
the corpus HEAD SHA in the file header makes the revision visible.

---

## What the assessment agent must do

### Step 0 — read the corpus header and orient

Open `commits.txt` and note:
- The HEAD SHA and collection timestamp (line beginning `# collected_at:`)
- The total number of commits (count non-comment lines)
- Whether the class has a `.cc` file, a `.h` file, or both

Open `functions.txt` and build a mental map of:
- Every function and its start line in its source file
- Which file contains each function (some classes are header-only)

Do not begin writing the artefact until you have read the full corpus.

### Step 1 — for each function, identify its relevant commits

For each function listed in `functions.txt`:

1. Note its start line (e.g. `handle_command | src/mgr/DaemonServer.cc:447`).
2. Scan the diff files in `diffs/` for hunk headers (`@@ -N,M +N,M @@`) that
   overlap with that line range. A diff hunk overlaps the function if:
   - The `+` side of the hunk header places at least one changed line within the
     function's body (from its start line to the next function's start line minus 1).
3. For each matching diff: read the commit message from `commits.txt` and the full
   diff content. Note what changed and why.
4. Check `blame.txt` to see who last touched each line of the function — the blame
   SHAs are cross-references back to commits in `diffs/`.

You are doing what a programmer does when reviewing history: scanning hunks, reading
messages, building a picture of evolution. You do not need to be perfectly precise
about line ranges — if a commit's diff is clearly in or near the function and the
commit message is relevant, include it.

### Step 2 — assess intent for each function

For each function, produce an intent summary by answering these questions from the
evidence:

1. **What is the function supposed to do?**
   Answer from: the function name and signature, the introduction commit message,
   and any commit messages using intent language (see Intent Keywords below).

2. **What invariants must hold?**
   Answer from: commit messages containing `prevent`, `reject`, `validate`, `must`,
   `should`, `assert`; and from reverted commits (a revert tells you what was
   *wrong*, which is often the clearest statement of what *right* looks like).

3. **What error conditions are deliberate?**
   Answer from: commits fixing bugs or adding guard clauses — these represent
   explicit decisions about what the function should do when inputs are bad or
   state is unexpected.

4. **Has the function diverged from its stated intent?**
   A DIVERGENCE flag is warranted when: a commit message says the function should
   do X, but the current source clearly does Y and no subsequent commit explains
   the change. This is the most valuable signal for test-writing agents — a test
   that validates the stated intent will expose the divergence.

5. **What has been deferred or is known to be incomplete?**
   Answer from: TODO/FIXME/HACK comments in diffs, or commit messages containing
   `workaround`, `temporary`, `hack`, `TODO`.

### Step 3 — critically evaluate the current implementation

After establishing intent from the history, **read the current source for the
function** and evaluate how well it satisfies the contracts you have just
documented. This is the adversarial step — approach the code as a reviewer
looking for problems, not as the author defending it.

For each function, answer:

1. **Does the current implementation satisfy every invariant you documented?**
   Go through each invariant bullet and check it against the current code line by
   line. If the code does not enforce the invariant, that is a DIVERGED finding.

2. **Does it handle every error condition you documented?**
   Trace each error path through the current code. Check whether the return value
   or state change matches what the history says it should be. A missing guard
   clause or a wrong error code is a DIVERGED finding.

3. **Are there observable behaviours in the current code that have no grounding
   in any commit message?**
   Undocumented behaviour is not necessarily wrong, but it warrants scrutiny. If
   a code path does something significant and no commit explains why, note it as
   **ungrounded behaviour** in the per-function section. Test-writing agents
   should treat ungrounded behaviour as a candidate bug — not a contract.

4. **Does the current code contain defensive checks that the history suggests
   should be unnecessary?**
   A guard clause that was added to paper over a race condition, or a special-case
   that was never removed after the root cause was fixed, is worth flagging. These
   are places where the implementation has grown away from its intended design.

5. **Is the function doing more or less than it was designed to do?**
   Feature creep (doing more than the contract requires) and silent truncation
   (doing less) are both DIVERGED findings if they contradict a commit-established
   contract.

Be blunt. The purpose of this step is to find real problems, not to produce a
balanced assessment. A function that fully satisfies its contracts should be noted
as such — but do not soften findings to be polite about the code.

### Step 4 — identify the introduction commit for each function

The introduction commit is typically the earliest diff where the function first
appears in a `+` (added) hunk. It often contains the most complete statement of
design intent. If the introduction commit message is a large refactor with no
function-specific context, look for the first bug-fix commit instead — that is
often where the contract was first made explicit.

### Intent keywords to scan for in commit messages

These fragments in a commit subject or body are high-signal for design intent:

| Keyword pattern | Interpretation |
|---|---|
| `fix`, `fixes`, `fixed`, `bug`, `regression` | The function had a defect; the fix defines correct behaviour |
| `revert` | A previous change was wrong; the reverted diff defines what *not* to do |
| `refactor`, `cleanup`, `simplify` | Structural change; behaviour should be identical before and after |
| `add`, `implement`, `introduce` | Initial design intent — often the richest context |
| `handle`, `support`, `allow`, `prevent`, `reject`, `validate` | Explicit behavioural contract |
| `TODO`, `FIXME`, `HACK`, `workaround` | Known incomplete or deferred intent |
| `must not`, `should not`, `assert`, `invariant` | Hard constraints on the function |

---

## Output format — `<ClassName>-intent.md`

### File header

```markdown
# Intent Assessment: <ClassName>

**Source files:** `<src_cc>`, `<src_h>`
**Corpus HEAD:** `<sha>` (<date>)
**Assessment date:** <YYYY-MM-DD>
**Commits analysed:** <N>
**Functions assessed:** <N>

> This artefact was produced by an AI assessment agent reading the raw git
> corpus in `/home/szuraski/BobOutput/Object History/v3/<ClassName>/`.
> It describes the *intended* behaviour of each function as reconstructed from
> commit history — not necessarily what the current code does.
> Test-writing agents should use this as the ground truth for what to test,
> and treat divergences as likely bugs.
```

### Class overview

Before the per-function sections, write a two-to-four sentence summary of the
class as a whole:

- What is the class's role in the system?
- What are its primary invariants or ownership rules?
- Has it undergone significant structural changes (large refactors, renames,
  major rewrites)? If so, note the approximate commit where that happened.

### Per-function section

One section per function. Use this exact structure:

```markdown
## `<ClassName>::<method_name>(<params>)`

**Introduced:** `<sha>` — <commit subject>
**Last modified:** `<sha>` — <commit subject>
**Change count:** <N> commits touched this function
**Divergence:** OK | DIVERGED

### Intent

<One to three sentences stating what the function is designed to do.
 This must be grounded in commit messages, not inferred from the current code.
 If the current code is the only evidence, state that explicitly.>

### Invariants and contracts

- <Each invariant on a separate bullet. Cite the commit SHA that established it.>
- Example: "Must not return success if the request map is empty. (Established: abc1234)"
- Example: "Caller is responsible for holding the lock before calling. (Introduced: def5678)"

### Error conditions

- <Each deliberate error path, grounded in a commit.>
- Example: "Returns -EINVAL when the command format is unknown. (Added: 9ab2345 'mgr: reject malformed commands')"

### Evolution summary

<Two to five sentences describing how the function has changed over time.
 Focus on semantic changes — rewrites, behaviour changes, additions of new cases.
 Skip purely cosmetic commits (whitespace, renames of unrelated variables).>

### Deferred / known incomplete

<List any TODO/FIXME/HACK items found in diffs, or "None." if clean.>

### Implementation critique

<A critical evaluation of how well the current implementation satisfies the
 contracts established above. Be direct and specific. Examples of what belongs here:

 SATISFIES — "The current implementation correctly enforces all documented
 invariants. The guard at line N matches the contract established in abc1234."

 DIVERGED — "The current code omits the empty-map check that was added in abc1234
 and documented as required. Line N returns 0 unconditionally; the contract
 requires -EINVAL."

 UNGROUNDED — "Lines N–M perform a lock downgrade that no commit message explains.
 This may be correct but has no historical justification — treat as a candidate bug."

 OVERCAUTIOUS — "The null-pointer check at line N was introduced in def5678 to
 work around a now-fixed caller bug. The workaround was never removed and now
 masks potential contract violations from callers."

 Do not write "the implementation looks reasonable" or hedge with "appears to".
 Either it satisfies the contract or it does not. If you cannot tell from the
 current source, say so explicitly and state what would need to be verified.>

### Test-writing notes

<Optional. Include only when there is something a test-writing agent would not
 discover from the code alone. Examples:
 - "The revert of <sha> means this case was once handled differently — worth
   testing the boundary explicitly."
 - "The HACK at line N was introduced in <sha> with message 'workaround for X'
   — tests should verify the workaround still holds."
 - "This function was split off from <other_function> in <sha> — tests should
   cover the split behaviour separately.">
```

### Divergence flag rules

Set `DIVERGED` when **all** of the following hold:

1. A commit message explicitly states what the function should do (using intent
   language from the keyword table above).
2. The current source code demonstrably does not match that stated intent.
3. No subsequent commit explains the change (i.e. the divergence was not itself
   a deliberate fix).

If in doubt, leave the flag as `OK` and note the uncertainty in the Evolution
summary. A false DIVERGED is more harmful than a missed one — it will send the
test-writing agent chasing phantom bugs.

---

## Self-check before writing the artefact

Answer each question. If any answer is "no", do another pass before writing.

- [ ] Have I read every commit in `commits.txt`, not just the signal ones?
- [ ] For every function in `functions.txt`, have I scanned at least the first
      three and the last three diff files chronologically for relevant hunks?
- [ ] Have I used `blame.txt` to cross-reference who last touched each function,
      and does that SHA appear in my per-function analysis?
- [ ] For every DIVERGED flag I am about to set, can I name the specific commit
      SHA that stated the intent and the specific line in the current source that
      contradicts it?
- [ ] Is every invariant I am documenting grounded in a commit, not inferred from
      a reading of the current code?
- [ ] For every function, have I read the current source and produced an
      Implementation critique — not just assessed the history?
- [ ] For every SATISFIES verdict, can I point to the specific line(s) of current
      code that enforce each invariant?
- [ ] Have I flagged every code path in the current source that has no grounding
      in any commit message as UNGROUNDED?

---

## Prompt template — assessment task

Copy this template and fill in the bracketed fields:

```
Read the raw git corpus for <ClassName> at:
/home/szuraski/BobOutput/Object History/v3/<ClassName>/

The corpus contains:
- commits.txt: all non-merge commits touching <SRC_CC> and <SRC_H>, newest first
- blame.txt:   git blame output for both source files
- functions.txt: ctags function list (name | file:line)
- diffs/<sha>.diff: full git show output scoped to the two source files, one file
  per commit

Your task has two phases. Phase 1 establishes what each function was designed to
do from the git history. Phase 2 critically evaluates whether the current
implementation actually does that.

Step 1: Read commits.txt in full. Note the total commit count, the HEAD SHA, and
the date range of the history.

Step 2: Read functions.txt. Build a list of every function and its start line.
Do not stop after reading — proceed immediately to Step 3.

Step 3: For each function, scan the diff files in diffs/ for hunks that overlap
its line range. For each matching diff, read the commit subject from commits.txt
and the full diff content. Note what changed and why. Use blame.txt to identify
which commits last touched which lines.

Step 4: For each function, read its current implementation in <SRC_CC> or <SRC_H>.
Evaluate the current code critically against the contracts you established in
Step 3. Do not be charitable — if the code does not enforce a contract, say so.
Specifically:
- Does every invariant from the history have a corresponding enforcement in the
  current code? If not, that is a DIVERGED finding.
- Does every error condition documented in the history have a corresponding guard
  in the current code? If not, that is a DIVERGED finding.
- Are there code paths in the current implementation that no commit explains?
  If so, flag them as UNGROUNDED.
- Are there defensive checks that history suggests are stale? Flag as OVERCAUTIOUS.

Step 5: Write the intent artefact to:
/home/szuraski/BobOutput/Object History/<ClassName>-intent.md

Follow the format in the History Assessment Guide exactly. Every function in
functions.txt must have a section. Every invariant and error condition must cite
the commit SHA that established it. Every function must have an Implementation
critique subsection — do not leave it empty or write that the implementation
"looks correct". Cite specific line numbers from the current source. Set DIVERGED
when you can name the specific commit that stated the intent and the specific line
in the current source that contradicts it.

Step 6: After writing the first draft, perform a self-check:
- Have you read every commit, not just the obvious signal ones?
- For every function, have you read the current source and produced a critique?
- For every DIVERGED flag, can you cite the SHA and the contradicting line?
- For every SATISFIES verdict, can you cite the specific lines that enforce each
  invariant?
- Have you flagged all ungrounded code paths?

If the self-check reveals gaps, update the artefact before declaring done.

Do not stop after reading the corpus — proceed immediately through all steps.
```

---

## How the test-writing agent consumes the intent artefact

The test-writing agent receives the `<ClassName>-intent.md` file alongside its
normal prompt. It uses it as follows:

1. **For each function under test**, read the corresponding section in the intent
   artefact before reading the current source. This establishes the expected
   contract before the agent sees the implementation.

2. **Invariants and contracts** become `EXPECT` assertions. If the artefact says
   "must not return success when the request map is empty", the test must assert
   that the return value is not success when given an empty map.

3. **Divergences** are the highest-priority test targets. A DIVERGED function
   should be tested against the *stated intent*, not the current implementation —
   that is the point. The test should fail on the current code if the divergence
   is real. The test-writing agent must note this explicitly in the test comment:
   `// Intent: <what artefact says>. Current code diverges — test validates intent.`

4. **Error conditions** become dedicated error-path tests, one per bullet in the
   artefact section.

5. **Deferred / known incomplete** items are flagged in a `DISABLED_` test or a
   `// TODO` comment so they are visible but not blocking CI.

---

## Integration with the unit-test prompt guide

The intent artefact replaces the "read the current source first" step in the
unit-test prompt guide. The recommended sequence for a test-writing agent is:

1. Read `<ClassName>-intent.md` (intent artefact) — this establishes the contract.
2. Read the current source (`<SRC_CC>`, `<SRC_H>`) — this shows the implementation.
3. Note any DIVERGED flags — these are tests the agent *must* write regardless of
   whether they currently pass.
4. Follow the rest of the unit-test prompt guide (four-dimension gap analysis,
   EXPECT assertions, build + run loop).

See `Inputs/unit-test-prompt-guide.md` for the full implementation prompt template
and the gap-analysis loop structure.

---

## Caveats

- **Diff scanning is approximate.** The agent is reasoning about line ranges from
  ctags start lines, without computed end lines. It may miss commits that changed
  the very end of a function or include commits that changed a function immediately
  below. This is acceptable — a missed commit means slightly less context; an
  incorrect DIVERGED flag is the more serious error to avoid.

- **Renames are invisible to ctags line numbers.** If a file was renamed mid-history,
  diffs before the rename use the old filename. The agent should note when it sees
  a diff where the filename in the hunk header differs from the current filename.

- **Merge commits are excluded.** `commits.txt` contains only non-merge commits.
  The introduction of a feature into mainline (via merge) is not captured. This is
  intentional — the non-merge commits contain the design intent; the merge is
  infrastructure.

- **The assessment is one agent's reading of the history.** It is not a mechanical
  ground truth. A test-writing agent should treat it as high-quality evidence, not
  as infallible specification. When the artefact and the current code conflict and
  the DIVERGED flag is not set, the test-writing agent should use judgment.
