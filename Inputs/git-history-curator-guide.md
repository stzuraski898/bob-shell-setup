# Git History Curator Guide

A prompting strategy for producing per-class history artefacts that test-writing agents
can reference to understand what each function *should* be doing — not just what it
currently does.

---

## Architecture

History collection is split into two stages:

```
Stage 1 — Shell script (runs once on sockeni07, no AI involved)
  collect-object-history-v2.sh  (or v1: collect-object-history.sh)
    → writes raw git data to /home/szuraski/BobOutput/Object History/raw/<ClassName>/

  File inventory (v2 layout; v1 is identical except where noted):

      00-HEADER.txt     class metadata, HEAD SHA, run timestamp
      01-commits.txt    all non-merge commits touching the source file
      01b-commits-all.txt  [v2 only] all commits including merges
                           (merge commits can record when a feature entered mainline)
      02-messages.txt   full commit message for every SHA in 01
      03-signal-commits.txt  signal-annotated subset of 01
                             signal = commit whose hunk-level diff touches this file
                             AND whose subject/body matches an intent keyword
                             (hunk-level test removes cross-subsystem false positives)
                             NOTE: this is an ANNOTATION, not a filter — all commits
                             remain in 01; signal status is surfaced in 10-commits-detail
      04-signal-diffs.txt    full diffs for signal commits
      05-blame.txt      git blame -w -M -C on current source
                        [v1: blame -w -M only]
      06-todos.txt      all TODO/FIXME/HACK lines
      07-classes.txt    every class/struct in the header (forward declarations excluded)
      08-methods.txt    [v1 only] method declarations at class scope
                        (brace-depth tracked; data members and body lines excluded)
      08-functions.txt  [v2 only] ctags-derived function inventory — replaces 08-methods
                        pipe-delimited fields per line:
                          function_id | qualified_name | signature |
                          decl_file:line | def_file:line | kind
                        handles overloads, inline methods, constructors, operators
                        (see "08-functions.txt format" section below)
      09-function-commits.txt  function → SHA index with evidence tags
                               format: ### ClassName::method_name
                                       <sha>  [L][G][S][B]  (space-separated tags)
                               [L] = git log -L line-range (most precise — tracks body)
                               [G] = git log -G \bname\b (regex grep — catches rewrites)
                               [S] = git log -S QualifiedName (pickaxe — exact string)
                               [B] = git blame current lines (who introduced them)
                               multiple tags on one SHA = multiple passes confirmed it
                               no metadata here — all detail is in 10
      10-commits-detail.txt    one block per unique SHA appearing in 09 (deduplicated)
                               fields: date / author / subject / signal: yes|no
                               body / scoped diff (target .cc and .h only)
                               signal: yes = this commit matched an intent keyword
                               deduplicated: a SHA shared by N functions appears once

Stage 2 — AI curator agent (reads raw files, writes formatted artefact)
  reads:  /home/szuraski/BobOutput/Object History/raw/<ClassName>/
  writes: /home/szuraski/BobOutput/Object History/<ClassName>.md
```

**AI agents never run git commands.** All git interaction happens in Stage 1.
Signal commits in `03-signal-commits.txt` are pre-verified at the hunk level: the
script confirms each commit's diff actually changed a hunk in the target file before
annotating it as a signal, eliminating cross-subsystem false positives from broad
keyword matches. Signal is an *annotation only* — non-signal commits that changed a
function are still recorded in `09-function-commits.txt`.
Re-run the script after a significant rebase to refresh the raw data.

---

## Purpose

Unit-test agents work exclusively from the current source code. This is a blind spot:
a function whose implementation was wrong, temporarily broken, or refactored mid-way
through development will produce tests that enshrine the wrong behaviour. Git history
contains the authoritative record of *intended* behaviour — commit messages, review
notes baked into commits, and the sequence of deliberate changes all encode design
intent that is invisible at `HEAD`.

This guide tells a **curator agent** how to extract that history per-function, where to
store it, and how to format it so test-writing agents can consume it without ambiguity.

---

## Output location

History artefacts live in a single shared directory on the host — not in the
repository. All agents read from the same location, so a history file written once
is available to every subsequent test-writing agent without re-running the curator.

```
/home/szuraski/BobOutput/Object History/
  <ClassName>.md          ← one file per class under analysis
```

Example:

```
/home/szuraski/BobOutput/Object History/
  DaemonServer.md
  ActivePyModules.md
  MgrClient.md
```

**Never stage or commit anything inside `Object History/`.** These files are reference
artefacts for AI agents — they live on the host filesystem, not in the repository.
If a class is re-analysed (e.g. after a significant rebase), overwrite the existing
file in place; the HEAD SHA in the header makes the revision visible.

---

## What the curator agent must collect

### Step 0 — enumerate all classes in the target file before collecting anything

Before touching a single `git log` command, the curator agent **must** run:

```bash
grep -n "^class \|^struct " <header_file>
```

List every class and struct defined in the header. If the header contains more than one
class, **each class gets its own `## Class:` section and its own complete set of
`## Method:` blocks** in the output artefact. Do not assume the target class is the only
one. Headers like `DaemonState.h` define `DaemonState`, `DeviceState`, and
`DaemonStateIndex` — all three must be covered.

If a discovered class was not named in the prompt, include it anyway and note it in the
artefact header as: `Note: <ClassName> discovered in same header — included.`

### Per-method collection

For every **public method** of every class, collect the fields below.
Also include **private methods that a public method delegates to non-trivially** — defined
as: a private method called from ≥1 public method whose logic is not a one-liner (i.e.
it contains a branch, a loop, a lock acquisition, or a return value that changes the
public method's behaviour). Simple getter forwarding (`return member_;`) does not qualify.

| Field | Source | Description |
|---|---|---|
| `function` | Current source | Fully-qualified method signature |
| `first_introduced` | `git log --follow --diff-filter=A` | Commit SHA + message when the function was first added |
| `last_modified` | `git log -1 -- <file>` on the relevant hunk | Commit SHA + message of the most recent change to this function |
| `change_count` | `git log --follow -- <file> \| grep -c '^commit'` | Number of commits that touched the file (use as a proxy for churn) |
| `commit_log` | `git log --follow --format="%H %s" -- <file>` filtered to commits that actually diff the function, de-duplicated by `%H` after cherry-pick detection (see Caveats) | Ordered list (newest-first) of all commits that changed this specific function |
| `design_signals` | Parsed from commit messages | Any message fragment containing intent keywords (see below) |
| `divergence_flag` | Curator-set | `DIVERGED` if the current implementation contradicts the stated intent; `OK` otherwise |

### Intent keywords to scan for in commit messages

These fragments in a commit subject or body indicate design intent:

- `fix`, `fixes`, `fixed`, `bug`, `regression` → the function had a defect; the fix defines correct behaviour
- `revert` → a previous change was wrong; the reverted commit defines what *not* to do
- `refactor`, `cleanup`, `simplify` → structural change; behaviour should be identical before and after
- `add`, `implement`, `introduce` → initial design intent
- `handle`, `support`, `allow`, `prevent`, `reject`, `validate` → explicit behavioural contract
- `TODO`, `FIXME`, `HACK`, `workaround` in the diff body → known incomplete or deferred intent

---

## Stage 1 reference — git commands used by the collection script

> **Note for curator agents (Stage 2):** this section documents the git commands that the
> collection script ran when it populated the raw data. **Curator agents do not run any
> of these commands.** They are provided here so human operators can understand what each
> raw file contains and reproduce individual steps if needed. Stage 2 agents read
> pre-collected files only.

### 1. Identify all commits that touched the file

```bash
# Non-merge commits (populates 01-commits.txt)
git log --follow --no-merges --oneline -- <file>

# All commits including merges (populates 01b-commits-all.txt, v2 only)
git log --follow --oneline -- <file>
```

### 2. For each function — four independent evidence passes (v2)

The v2 script runs all four passes and unions the results. Evidence tags in
`09-function-commits.txt` record which pass(es) found each SHA.

**Pass L — line-range (most precise; tracks body across renames):**
```bash
# start/end come from ctags (08-functions.txt decl_file:line / def_file:line)
git log --follow --no-merges --format="%H" \
  -L <start>,<end>:<file>
```
Produces [L] tags. Requires exact line numbers; does not collapse overloads.

**Pass G — regex grep (catches rewrites and moves to different lines):**
```bash
git log --follow --no-merges --format="%H" \
  -G '\b<function_name>\b' -- <file>
```
Produces [G] tags. More commits than L; lower precision.

**Pass S — pickaxe (exact string; catches additions and deletions of the symbol):**
```bash
git log --follow --no-merges --format="%H" \
  -S '<ClassName>::<function_name>' -- <file>
```
Produces [S] tags. Finds commits where the symbol count changed (introduced/removed).

**Pass B — blame (who introduced the current lines):**
```bash
git blame -w -M -C -- <file> | grep '<function_name>'
# then extract the SHAs from blame output column 1
```
Produces [B] tags. Reflects current authorship only; misses deleted lines.

**Evidence tag confidence ranking (highest to lowest):**
1. `[L]` — line-range tracked the body; highest precision, lowest false-positive rate
2. `[S]` — pickaxe on qualified name; exact but only fires on symbol-count changes
3. `[G]` — regex grep; broader, may include unrelated mentions
4. `[B]` — blame; current-state only, misses any commit that deleted the line

A SHA carrying multiple tags (e.g. `[L][S]`) was confirmed by independent passes —
treat it as higher-confidence than a SHA carrying only `[G]` or `[B]`.

### 3. Signal annotation — hunk-level test

The v2 script uses `git diff-tree` to verify a commit actually changed a hunk in the
target file before annotating it as a signal. This replaces the `grep "^[+-]"` approach
which produced false positives from `--- a/file` and `+++ b/file` header lines.

```bash
# Hunk-level test: does this commit change the target file?
git diff-tree --no-commit-id -r --name-only <sha> | grep -qF "<file>"
# If exit 0: commit genuinely changes the file — mark as signal candidate
# Then check subject/body for intent keywords before writing to 03-signal-commits.txt
```

### 4. Function inventory via ctags (v2)

```bash
ctags --fields=+ne --output-format=json -- <file.cc> <file.h>
# fields: name, scope, signature, pattern, line (decl), end (end of body)
# kind: f=function, m=member, p=prototype
# Output written to 08-functions.txt (pipe-delimited, one function per line)
```

Falls back to awk-based declaration parsing if ctags is unavailable (v1 behaviour,
produces `08-methods.txt`).

### 5. Extract the introduction commit

```bash
git log --follow --diff-filter=A --format="%H %ad %s" --date=short -- <file>
```

### 6. Retrieve full message of any commit of interest

```bash
git show --no-patch --format="%H%n%s%n%b" <sha>
```

### 7. Annotate with blame for current implementation

```bash
# v2: -C also tracks code copied from other files
git blame -w -M -C -- <file> | grep -A5 -B5 "<function_name>"
```

---

## Output format — `<ClassName>.md`

Each file must be strictly structured so test-writing agents can parse it with a simple
section scan. Do not add prose between sections. Do not summarise unless the format
calls for it.

### File-level header and class structure

```markdown
# Git History: <ClassName>
Source: <relative/path/to/source.cc> (and header if separate)
Generated: <ISO-8601 date>
Branch: <current branch name>
HEAD: <current HEAD SHA>
Note: history is file-level; indirect changes (struct fields, macros) may be absent.
[Note: <ExtraClass> discovered in same header — included.]  ← add if extra classes found

---

## Class: <ClassName>

<!-- One sentence describing the class's overall responsibility, sourced from commit
     messages or header comments. Do not invent description. -->

### Methods in this class

<!-- List every method name on a single line each. This acts as a quick index so
     test agents can scan for a method without reading all ## Method: blocks. -->
- `method_one(arg_type)`
- `method_two()`

---

## Method: <ClassName>::<method_signature>

### Intent summary
<One or two sentences synthesised from commit messages that describe what this method
is *supposed* to do. If commit messages are unclear, write "No clear intent signal —
infer from implementation." Do not invent intent that is not supported by commit text.>

### Change history (newest first)

| SHA (short) | Date | Subject | Signal |
|---|---|---|---|
| `abc1234` | 2024-03-12 | fix: prevent double-free on eviction | fix |
| `def5678` | 2023-11-04 | refactor: extract helper for clarity | refactor |
| `ghi9012` | 2023-08-19 | implement DaemonServer::update_metadata | introduce |

### Notable diffs

<!-- Only include diffs for commits with a fix, revert, or explicit contract signal.
     Omit pure refactors and style commits unless they changed observable behaviour.
     Use ~~~ fences (not ```) for diff blocks here to avoid nesting conflicts. -->

**`abc1234` — fix: prevent double-free on eviction**
~~~diff
- if (entry) delete entry;
+ if (entry) { delete entry; entry = nullptr; }
~~~
*Why it matters for tests:* calling the method twice must not crash; the post-condition
is that the pointer is null after deletion.

### Divergence flag

`OK` / `DIVERGED: <one-sentence description of the divergence>`

<!-- Set to DIVERGED if the current source does something the commit history explicitly
     prohibited or reversed. If DIVERGED, describe what the history says should happen. -->

### Known defects / deferred intent

<!-- List any TODO/FIXME/HACK in the current implementation, with the line reference. -->

- Line 142: `// TODO: handle the case where metadata map is empty`

---
```

Repeat the `## Method:` block for every method in the class.
When a file defines more than one class, repeat the full `## Class:` block
(including its `### Methods in this class` index) for each class, then list
all `## Method:` blocks for that class before starting the next `## Class:` block.

**Qualifying `## Method:` prefix:** always use the fully-qualified form
`<ClassName>::<method_name>` so a test agent scanning for "DaemonState::" finds
only that class's methods even in a multi-class artefact.

---

## `08-functions.txt` format (v2 only)

Each non-comment line is pipe-delimited with exactly six fields:

```
function_id | qualified_name | signature | decl_file:line | def_file:line | kind
```

| Field | Description |
|---|---|
| `function_id` | Unique integer assigned by the script (stable within one run) |
| `qualified_name` | Fully-qualified name: `ClassName::method_name` |
| `signature` | Full parameter list as ctags extracted it, e.g. `(int id, bool force)` |
| `decl_file:line` | File and line of the declaration (usually the `.h`); `-` if not found |
| `def_file:line` | File and line of the definition (usually the `.cc`); `-` if header-only |
| `kind` | `f` = free function, `m` = member function, `p` = prototype/declaration |

Lines beginning with `#` are comments (class headers, section separators, etc.).

Example:
```
42 | DaemonState::get_daemon | (const DaemonKey &key) | DaemonState.h:87 | DaemonState.cc:203 | m
43 | DaemonState::get_daemon | (const std::string &type, int id) | DaemonState.h:88 | DaemonState.cc:218 | m
```
Note: two lines with the same `qualified_name` and different `signature` are overloads.
Each overload gets its own `## Method:` block (use the full signature to disambiguate).

When `def_file:line` is `-`, the function is defined inline in the header.
The `decl_file:line` line number is used for both `git log -L` passes in that case.

---

## Self-check before writing the output file

Before saving `<ClassName>.md`, the curator agent must answer these questions. For
every "no", **fix the artefact immediately and re-check** — do not proceed with a
failing check.

1. Does the artefact cover **every class** defined in the header (not just the one named
   in the prompt)?
   → Use `07-classes.txt` (which already excludes forward declarations) as the ground
   truth. Every line in that file that is not a comment must have a matching `## Class:`
   section in the artefact. Do not re-run `grep` independently — `07-classes.txt` is
   already correct; use it.

2. For each class, does every method in the function inventory have a `## Method:` block?
   → Determine which inventory file is present:
     - v2 run: use `08-functions.txt` (pipe-delimited; one function per line).
       Each line's `qualified_name` field is the method name to check.
       Filter to entries where `kind` is `f`, `m`, or `p` (skip data members/enums).
     - v1 run: use `08-methods.txt` (one declaration per line under `### ClassName`).
       Every non-comment, non-`###` line with a `(` is a method declaration.
   Cross-reference the inventory file line-by-line.
   A self-assessment without reading the inventory file is not acceptable.
   Both files already exclude data members and forward declarations.
   → If any method is missing: add the block before saving.

3. For each method, is the "Change history" table sourced from `09-function-commits.txt`
   for that method's `### ClassName::method_name` section — not inferred from
   whole-file commit lists?
   → Look up each method by its `### <ClassName>::<method_name>` entry in
   `09-function-commits.txt`. Every SHA listed there must appear in the
   "Change history" table for that method's `## Method:` block.
   → When reading a row in the change history table, note the evidence tag(s) from 09:
     a SHA with `[L]` or `[L][S]` has higher confidence than one with `[G]` or `[B]`
     only — reflect this in the "Signal" column if meaningful (e.g. "fix [L]").
   → If `# none found` appears for a method, note "No tracked commits — history
   inferred from file-level log" in that method's intent summary.

4. Is the intent summary for each method sourced from commit text — not inferred from
   the current implementation alone?
   → Source: commits that appear in both `09-function-commits.txt` (for this method)
   AND `03-signal-commits.txt` are the highest-confidence signals. If none exist,
   fall back to all commits in `09-function-commits.txt` for this method, then
   `02-messages.txt`. If still no signal: write "No clear intent signal — infer
   from implementation."

5. For every `fix` or `revert` commit in a method's `09-function-commits.txt` entries
   that also appears in `03-signal-commits.txt`, is there a "Notable diffs" entry?
   → Scope each diff block in `04-signal-diffs.txt` to its `=== <sha>: ... ===`
   section; extract only hunks whose file path matches the target `.cc` or `.h`.
   → If any such commit is missing a Notable diffs entry: add it before saving.

6. Are any `TODO`/`FIXME`/`HACK` lines from `06-todos.txt` listed under
   "Known defects / deferred intent" for the relevant method?
   → Every non-comment line in `06-todos.txt` must appear under the method it belongs to.
   If the method cannot be determined, list it under the class header.
   → If any are missing: add them before saving.

7. Does the file header include the exact HEAD SHA from `00-HEADER.txt`?
   → If no: copy the `head_sha:` value from `00-HEADER.txt` into the artefact header.

8. Are cherry-picked commits de-duplicated? (Same `%s %b` fingerprint appearing twice
   with different SHAs should appear only once, annotated with both SHAs.)
   → If no: merge the duplicates.

9. Is the `divergence_flag` set for every method (either `OK` or `DIVERGED: …`)?
   → If no: compare the intent summary against the current source and set the flag.

10. Does the HEAD SHA in `00-HEADER.txt` match the actual worktree HEAD?
   → Run `git rev-parse HEAD` and compare to `head_sha:` in `00-HEADER.txt`.
    If they differ, the raw data is stale. **Stop, report the mismatch, and do not write
    the artefact** — re-run `collect-object-history.sh` first to refresh the raw data.

---

## Running the collection script (Stage 1)

Before launching any curator agent, run the collection script once on `sockeni07`
from inside any ceph worktree. Use v2 for new runs; v1 is retained for reference.

**v2 (recommended):**
```bash
scp collect-object-history-v2.sh szuraski@sockeni07:/tmp/
ssh szuraski@sockeni07 "cd /home/szuraski/ceph && bash /tmp/collect-object-history-v2.sh"
```

**v1 (fallback if ctags is unavailable on sockeni07):**
```bash
scp collect-object-history.sh szuraski@sockeni07:/tmp/
ssh szuraski@sockeni07 "cd /home/szuraski/ceph && bash /tmp/collect-object-history.sh"
```

Confirm ctags availability before choosing: `ssh szuraski@sockeni07 "ctags --version"`.

Both scripts populate `/home/szuraski/BobOutput/Object History/raw/` with one
subdirectory per class. The scripts are idempotent — re-running overwrites stale data.
Run after any significant rebase to refresh raw data before re-curating.

---

## Prompt template — curator task (Stage 2)

Use this template when launching a curator agent via `bob run` or `launch-bob-agents.sh`.
Replace all `<placeholders>`. **The raw data must already exist from Stage 1 before
launching an agent.**

**The curator task is read-only. Do not run any git commands, make code changes,
create branches, or commit anything. All source data comes from the pre-collected
files in the raw directory.**

```
Step 1: confirm the raw history data exists for <ClassName>:
  ls /home/szuraski/BobOutput/Object History/raw/<ClassName>/
If the directory is missing or empty, stop and report — do not proceed.

Step 2: check artefact staleness before reading anything else:
  a. Read 00-HEADER.txt and note the head_sha value.
  b. Run: git rev-parse HEAD
  c. If the two SHAs differ, stop immediately and report:
       "Raw data is stale: collected at <head_sha>, worktree is at <current>.
        Re-run collect-object-history.sh before curating <ClassName>."
     Do not proceed with curation on stale data.

Step 3: read the following files in order and load their contents into working memory:
  a. 07-classes.txt  — list every class/struct declared in the header.
     Each class found must get its own ## Class: section in the output artefact.
     Do not assume <ClassName> is the only class in the file.
     Note: forward declarations are already excluded.
  b. Function inventory — check which file is present and read accordingly:
     IF 08-functions.txt exists (v2 run):
       Pipe-delimited format: function_id | qualified_name | signature |
                              decl_file:line | def_file:line | kind
       Each line where kind is f, m, or p is a real method.
       The qualified_name field gives you the <ClassName>::<method_name> form directly.
       This is your complete method inventory — do not supplement with grep.
     ELSE IF 08-methods.txt exists (v1 run):
       One declaration per line under each ### ClassName section.
       Every non-comment, non-### line with a ( is a real method declaration.
     Either file already excludes data members and forward declarations.
  c. 09-function-commits.txt — THE PRIMARY SOURCE FOR CHANGE HISTORY.
     Format: ### ClassName::method_name followed by one SHA per line.
     Evidence tags on each SHA (v2):
       [L] = git log -L line-range tracked this function body precisely (highest trust)
       [G] = git log -G regex found function name (approximate; may include nearby code)
       [S] = git log -S pickaxe on qualified name (exact, fires on symbol count change)
       [B] = git blame on current lines (current authorship; misses deleted history)
     Multiple tags on one SHA = multiple independent passes confirmed it (higher confidence).
     For each method, collect its SHA list from this file. These are the only commits
     you need to look up — do not infer history from any other source.
     Non-signal commits ARE included here; signal status is in 10-commits-detail.txt.
  d. 10-commits-detail.txt — THE PRIMARY SOURCE FOR COMMIT CONTENT.
     Format: === <sha> === blocks, each containing:
       date / author / subject / signal: yes|no / body / diff
     The diff is already scoped to the target .cc and .h — no filtering needed.
     signal: yes means the commit message matched intent keywords AND the hunk-level
     diff test confirmed it touched the target file (no false positives from header lines).
     For each SHA in a method's 09 list, look up its block here to get the full
     context. A SHA shared by multiple functions appears only once — that is correct.
  e. 06-todos.txt — all TODO/FIXME/HACK in current source.
  f. 00-HEADER.txt — HEAD SHA (already read in Step 2, confirm it is loaded).

Do not stop after reading — proceed immediately to Step 4.

Step 4: write the history artefact to:
  /home/szuraski/BobOutput/Object History/<ClassName>.md
Format the file exactly as specified in the Git History Curator Guide
(Inputs/git-history-curator-guide.md). Every class from 07-classes.txt must have a
## Class: section with a ### Methods in this class index. Every method from
08-methods.txt must have a ## Method: block using the fully-qualified
<ClassName>::<method_name> prefix. The "Change history" table for each method must
be populated from the SHAs in 09-function-commits.txt for that method, with each
SHA's metadata looked up in 10-commits-detail.txt. Any SHA whose block has
signal: yes must have a Notable diffs entry (the diff is already in that block —
copy the relevant hunk). Every item from 06-todos.txt must appear under Known
defects for the relevant method. Do not stage or commit this file.

Step 5: perform all ten self-check items from the guide. For check 2, cross-reference
the ## Method: blocks in the artefact against 08-methods.txt line-by-line — every
method listed there must have a corresponding block. Correct any failures before
proceeding.

Step 6: print a one-line summary per method in this format:
  <ClassName>::<MethodName>: <intent sentence> [<N> commits, <N> fix signals]
This gives the test-writing agent a quick index without reading the full file.
```

---

## How the test-writing agent consumes the history artefact

The test-writing agent must read `Object History/<ClassName>.md` **before** opening the
source file. The reading order is:

1. Open `<ClassName>.md` and read the intent summary for each method.
2. For any method with a `fix` or `revert` signal, read the "Notable diffs" section
   and note the correct post-condition before writing any assertion for that method.
3. For any method with a "Known defects" entry, do **not** write a test that passes
   against the defective behaviour — write the test for the *intended* behaviour and
   mark it with a `// TODO: currently fails — see <SHA>` comment so the defect is
   visible.
4. Only after steps 1–3, open the source file and confirm the current implementation
   matches the intended behaviour. If it does not, note the divergence in the
   gap-analysis output and alert the user before writing tests.

Add this instruction to every test-writing prompt that has a corresponding curator
artefact:

> Before reading the source, open
> /home/szuraski/BobOutput/Object History/<ClassName>.md
> and do the following:
> 1. Check the `HEAD:` line in the artefact header. Run `git rev-parse HEAD` in your
>    worktree and confirm the SHAs match. If they differ, stop and alert the user —
>    the artefact is stale and its divergence flags cannot be trusted.
> 2. For each method, record the intent summary, fix signals, and divergence flag.
>    Use this as the ground truth for what each method is supposed to do.
> 3. Where the divergence flag is DIVERGED, note the discrepancy in the gap-analysis
>    output and alert the user before writing any assertion for that method — do not
>    write a test that encodes the wrong (current) behaviour.
> 4. For any method with a "Known defects" entry, write the test for the *intended*
>    behaviour and mark it `// TODO: currently fails — see <SHA>`.

---

## Integration with the unit-test prompt guide

The curator task is a **prerequisite step** that always runs before the main
test-writing task described in `unit-test-prompt-guide.md`, for every class under
analysis without exception. Run it as a separate `bob run` invocation so its output
exists on disk before the test-writing agent starts. The step numbering in the
combined prompt must be adjusted to avoid confusing the agent:

```
Step 0 (curator, separate run): collect git history → write Object History/<ClassName>.md
Step 1: check out / create the wip-sz-* branch          ← same as template Step 1
Step 2: read Object History/<ClassName>.md; write tests ← replaces template Step 2 open
Step 3–N: build, run, gap analysis, commit              ← same as template Steps 3–N
```

Always include the explicit instruction in every test-writing prompt:

> Step 0 is already complete. Before reading the source, open
> /home/szuraski/BobOutput/Object History/<ClassName>.md
> and confirm it passes all ten self-check items from the curator guide, including
> the HEAD SHA staleness check (check 10). If the file does not exist or the SHA does
> not match the worktree HEAD, stop and report — do not proceed without a fresh artefact.

---

## Caveats and known limitations

- **Rename detection.** `git log --follow` tracks renames but is imperfect for files
  moved across directories alongside large edits. If `--follow` produces an unexpectedly
  short history, also run `git log -- <old/path/if/known>` and merge the results. For
  files renamed more than once, run `git log --name-only --follow -- <file>` to get the
  full rename chain, then replay the log for each historical path and merge results,
  de-duplicating by SHA.

- **Granularity.** `git log -- <file>` tracks file-level history, not function-level.
  The diff-grep approach above is a proxy; it will miss commits that changed a function
  indirectly (e.g. changing a struct field used inside the function). Note this
  limitation in the artefact header with:
  `Note: history is file-level; indirect changes (struct fields, macros) may be absent.`

- **Merge commits.** Merge commits carry no per-function diff but do record when a
  feature entered mainline (e.g. a squash-merge of an agent branch). In v2, they are
  preserved in `01b-commits-all.txt` for reference. Curator agents should **not** include
  merge commits in the "Change history" table for individual methods — they appear in
  `09-function-commits.txt` only when a non-merge pass (L/G/S/B) found them, which
  should not happen. If you see a merge SHA in a method's 09 list, skip it and note
  `merge commit — skipped from per-method table` in the intent summary.

- **Cherry-picked commits.** In the ceph multi-agent worktree setup, commits are
  frequently cherry-picked between agent branches. A cherry-pick produces a new SHA
  with identical `%s %b`. De-duplicate by running:
  ```bash
  git log --follow --format="%H %s" -- <file> | sort -k2 -u
  ```
  When two SHAs share a subject, record both SHAs in the history entry and note
  `cherry-pick detected`.

- **High-churn files (> 200 commits).** The v2 script imposes **no cap** on history —
  every commit found by any of the four evidence passes is retained in
  `09-function-commits.txt` and `10-commits-detail.txt`. Signal status (from
  `03-signal-commits.txt`) is an annotation inside `10-commits-detail.txt`, not a filter.
  Curator agents must process all commits in a method's 09 list without truncating.
  If `02-messages.txt` is very large, read it section-by-section rather than loading the
  whole file at once, but do not skip any entry.
  Note: the v1 script used to cap grep-fallback output with `head -30` / `head -50`; this
  is corrected in v2. If working from v1 data, the "Change history" table may be
  incomplete for high-churn methods — note this in the artefact header as:
  `Warning: collected with v1 script — change history may be truncated for high-churn methods.`

- **Squashed history.** If the repository uses squash-merge (no individual commits
  per fix), the commit log will be sparse. In that case, the "Notable diffs" section
  will be thin — note "Squashed history: individual fix commits not available" and
  rely on the commit message body for intent signals.

- **`-L :<function>:<file>` syntax.** Git's `-L` log flag requires the function name
  to match a regex against `@@ ... @@` context markers. For C++ overloads, append the
  argument signature: `-L ":DaemonServer::update\b:<file>"`. If the regex matches
  nothing, fall back to Approach C from the git commands section.
