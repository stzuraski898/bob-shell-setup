# History Assessment Prompts — ceph-mgr (5 objects)

Generated from `Inputs/history-assessment-guide.md`.
Each prompt below is ready to paste into a Bob agent session.
Fill in any `<placeholder>` values that depend on live system state.

---

## 1. `DaemonKey`

**Source files:** `src/mgr/DaemonKey.h`, `src/mgr/DaemonKey.cc` (~37 lines)
**Test status:** in-progress — [#80175](https://tracker.ceph.com/issues/80175)

```
Read the raw git corpus for DaemonKey at:
/home/szuraski/BobOutput/Object History/v3/DaemonKey/

The corpus contains:
- commits.txt: all non-merge commits touching src/mgr/DaemonKey.cc and src/mgr/DaemonKey.h, newest first
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

Step 4: For each function, read its current implementation in src/mgr/DaemonKey.cc or src/mgr/DaemonKey.h.
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
/home/szuraski/BobOutput/Object History/DaemonKey-intent.md

Follow the format in the History Assessment Guide exactly
(Inputs/history-assessment-guide.md). Every function in
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

## 2. `MgrCap`

**Source files:** `src/mgr/MgrCap.h`, `src/mgr/MgrCap.cc` (~583 lines)
**Test status:** covered — `src/test/mgr/test_mgrcap.cc`

```
Read the raw git corpus for MgrCap at:
/home/szuraski/BobOutput/Object History/v3/MgrCap/

The corpus contains:
- commits.txt: all non-merge commits touching src/mgr/MgrCap.cc and src/mgr/MgrCap.h, newest first
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

Step 4: For each function, read its current implementation in src/mgr/MgrCap.cc or src/mgr/MgrCap.h.
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
/home/szuraski/BobOutput/Object History/MgrCap-intent.md

Follow the format in the History Assessment Guide exactly
(Inputs/history-assessment-guide.md). Every function in
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

## 3. `ClusterState`

**Source files:** `src/mgr/ClusterState.h`, `src/mgr/ClusterState.cc` (~387 lines)
**Test status:** covered — `src/test/mgr/test_clusterstate.cc`

```
Read the raw git corpus for ClusterState at:
/home/szuraski/BobOutput/Object History/v3/ClusterState/

The corpus contains:
- commits.txt: all non-merge commits touching src/mgr/ClusterState.cc and src/mgr/ClusterState.h, newest first
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

Step 4: For each function, read its current implementation in src/mgr/ClusterState.cc or src/mgr/ClusterState.h.
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
/home/szuraski/BobOutput/Object History/ClusterState-intent.md

Follow the format in the History Assessment Guide exactly
(Inputs/history-assessment-guide.md). Every function in
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

## 4. `PyModule`

**Source files:** `src/mgr/PyModule.h`, `src/mgr/PyModule.cc` (~812 lines)
**Test status:** none

```
Read the raw git corpus for PyModule at:
/home/szuraski/BobOutput/Object History/v3/PyModule/

The corpus contains:
- commits.txt: all non-merge commits touching src/mgr/PyModule.cc and src/mgr/PyModule.h, newest first
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

Step 4: For each function, read its current implementation in src/mgr/PyModule.cc or src/mgr/PyModule.h.
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
/home/szuraski/BobOutput/Object History/PyModule-intent.md

Follow the format in the History Assessment Guide exactly
(Inputs/history-assessment-guide.md). Every function in
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

## 5. `ThreadMonitor`

**Source files:** `src/mgr/ThreadMonitor.h`, `src/mgr/ThreadMonitor.cc` (~250 lines)
**Test status:** none

```
Read the raw git corpus for ThreadMonitor at:
/home/szuraski/BobOutput/Object History/v3/ThreadMonitor/

The corpus contains:
- commits.txt: all non-merge commits touching src/mgr/ThreadMonitor.cc and src/mgr/ThreadMonitor.h, newest first
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

Step 4: For each function, read its current implementation in src/mgr/ThreadMonitor.cc or src/mgr/ThreadMonitor.h.
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
/home/szuraski/BobOutput/Object History/ThreadMonitor-intent.md

Follow the format in the History Assessment Guide exactly
(Inputs/history-assessment-guide.md). Every function in
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

## Notes

- All prompts use the **v3 assessment flow** from `Inputs/history-assessment-guide.md`.
  They are **not** the older v2 curator prompts.
- The corpus for each class must exist at
  `/home/szuraski/BobOutput/Object History/v3/<ClassName>/` before running the
  agent. Use `collect-object-history-v3.sh` to generate it.
- Output artefacts land at
  `/home/szuraski/BobOutput/Object History/<ClassName>-intent.md` (note the
  `-intent` suffix, distinct from the older `<ClassName>.md` curator artefacts).
- Do **not** stage or commit anything under `Object History/`.
