# Whiteboard Defense: `collect-object-history-v4.sh`
### Rename-Aware Ceph MGR Corpus Collector

---

## 1. High-Level Architecture & Mental Model

### What It Does (One Sentence)

For each of 27 hard-coded Ceph MGR C++ classes, the script resolves the full
rename history of the class's source files, collects every non-merge commit
that ever touched those files (under any prior path), extracts scoped diffs
that use the historically-correct path, runs ctags on the current source, and
writes the whole corpus to a per-class directory tree for downstream
consumption by an AI or human analyst.

### Pipeline Flow

```
  CLASS_FILES dict (27 classes, .cc:.h pairs)
        │
        ▼ (parallel workers, one subshell per class)
  ┌─────────────────────────────────────────────────────────────┐
  │  collect_class()                                            │
  │                                                             │
  │  1. resolve_rename_chain(SRC_CC)  ──►  chain_cc.tmp        │
  │     resolve_rename_chain(SRC_H)   ──►  chain_h.tmp         │
  │     (git log --follow --name-status | awk)                  │
  │     writes: rename_chain.txt                                │
  │                                                             │
  │  2. build_sha_to_path_map(chain_cc) ──► map_cc.tmp         │
  │     build_sha_to_path_map(chain_h)  ──► map_h.tmp          │
  │     (git log per segment, two-pass to include seg_old)     │
  │                                                             │
  │  3. union(map_cc SHAs, map_h SHAs) | git log --no-walk     │
  │     writes: commits.txt                                     │
  │                                                             │
  │  4. git blame -w -M -C (current .cc and .h)                │
  │     writes: blame.txt                                       │
  │                                                             │
  │  5. ctags --language-force=C++ --c++-kinds=f+p             │
  │     writes: functions.txt                                   │
  │                                                             │
  │  6. For each SHA in commits.txt:                           │
  │       lookup hist_cc, hist_h from map_cc/map_h             │
  │       git show sha -- hist_cc [hist_h]                     │
  │     writes: diffs/<sha>.diff                               │
  │                                                             │
  │  7. For each SHA: parse @@ hunk context from .diff,        │
  │     match against functions.txt names                       │
  │     writes: commit_function_map.txt                         │
  │                                                             │
  │  (clean up *.tmp)                                           │
  └─────────────────────────────────────────────────────────────┘
        │
        ▼ (main waits for all workers with `wait`)
  INDEX.txt  (class × commits × functions × diffs summary table)
```

### Output Directory Shape

```
<output_dir>/
  INDEX.txt
  <ClassName>/
    rename_chain.txt          ← path segments, newest first
    commits.txt               ← all non-merge SHAs, formatted
    blame.txt                 ← git blame -w -M -C
    functions.txt             ← ctags output (name | file:line)
    commit_function_map.txt   ← SHA → touched functions
    diffs/
      <sha>.diff              ← one file per commit, scoped path
```

---

## 2. Architectural Decisions & Trade-offs

| Decision | Alternative Not Taken | Why This Choice |
|---|---|---|
| **`git log --follow --name-status`** to discover renames | Single `git log -- current_path` (v3 approach) | `--follow` traverses rename boundaries; without it, commits from before a rename are silently omitted. `--name-status` surfaces the `R`-status lines that carry the old path, which is what the awk parser exploits. |
| **Offline raw corpus** (files on disk) | On-the-fly git execution by the AI at query time | Pre-materialization is deterministic and repeatable at a fixed HEAD SHA. The AI can read a static snapshot without needing git access, repository access, or an SSH session on `sockeni07`. It also makes corpus size predictable and reviewable before feeding to a model. |
| **Per-class parallel subshells** (`collect_class ... &`) | Serial per-class execution | 27 classes each requiring O(N_commits) `git show` calls is I/O-bound. Parallelism cuts wall time roughly by the number of classes. `wait` at the end collects exit codes and counts failures. |
| **Two-pass `build_sha_to_path_map`** (range query + `seg_old` explicit query) | Single `git log seg_old..seg_new -- path` | The range `seg_old..seg_new` in git is exclusive of `seg_old` itself. Without the explicit second query for `seg_old`, the oldest commit in every rename segment is silently dropped. This was almost certainly a v3 bug. |
| **`git show sha -- hist_path`** with historically-correct path | `git show sha -- current_path` | `git show sha -- current_path` on a commit that predates a rename produces a "new file mode" spurious diff because git doesn't know that file yet at that path. Using `hist_path` scopes the diff to exactly what changed in the actual working tree at that SHA. |
| **ctags on current source** (not historical) | Running ctags on every historical checkout | Current function names are what the downstream consumer (AI) needs to reason about. Historical function names may no longer exist. The hunk-context matching in step 7 bridges old commits to current function identities anyway. |
| **`git log --no-walk --stdin`** to format commits | Multiple `git log -1 sha` calls | `--no-walk --stdin` is a single process that accepts all SHAs on stdin and formats them in one pass, avoiding fork overhead proportional to commit count. |
| **`flock` on a shared lock file for logging** | Raw `echo >&2` | Multiple background subshells writing to stderr can interleave. `flock` serializes log lines. Falls back gracefully when `flock` is absent. |
| **`set -euo pipefail`** | No error handling | Prevents silent failures from propagating. `|| true` is used deliberately where a command may produce no output (e.g., empty ctags result for header-only files) without wanting to abort the whole worker. |
| **Idempotent diff skip (`[[ -f diff_file ]] && continue`)** | Always regenerate | Re-running the script on an already-populated output directory skips existing diffs. Useful for resuming an interrupted run without re-fetching all diffs from a large history. |

---

## 3. Data Structures, Algorithms & Invariants

### 3.1 `CLASS_FILES` Associative Array

- Type: bash `declare -A` (hash map)
- Key: class name string (e.g. `ActivePyModule`)
- Value: colon-delimited `.cc:.h` pair (`src/mgr/ActivePyModule.cc:src/mgr/ActivePyModule.h`)
- Invariant: both sides of the colon are relative paths from `CEPH_ROOT`. The `.h` and `.cc` sides may be identical (header-only or implementation-only class); the script handles this with `[[ "${SRC_H}" != "${SRC_CC}" ]]` guards throughout.

### 3.2 Rename Chain Segments

The `resolve_rename_chain` function produces a list of **segments**:

```
<path>  <sha_newest_in_segment>  <sha_oldest_in_segment>
```

- **A segment** is a contiguous range of commits during which the file lived at `<path>`.
- Segments are ordered newest-first. The first segment always uses the current path; the last ends at the file creation commit.
- The awk state machine tracks `cur_path`, `seg_new` (newest SHA seen so far in the current segment), and `seg_old` (oldest SHA seen so far). On a rename (`R` status line): flush the current segment, reset `cur_path` to the old name (`$2` in the tab-delimited output), and carry `seg_old` forward as the next segment's `seg_new` so ranges abut without gap.

**Invariant**: every commit that `git log --follow` would visit is covered by exactly one segment, and the segment's path is the path the file had at that commit.

### 3.3 SHA-to-Path Map

`build_sha_to_path_map` expands each segment into individual `<sha> <path>` lines:

```
git log --no-merges --format="%H" "${seg_old}~1..${seg_new}" -- "${path}"
git log --no-merges --format="%H" -1 "${seg_old}" -- "${path}"
```

The two-pass design is necessary because the git range notation `A..B` means "commits reachable from B but not from A", which excludes `A` itself. The second query explicitly recovers `seg_old`.

**Invariant**: Every SHA in `map_cc` and `map_h` maps to exactly one path; lookups during diff extraction use `awk '$1==sha{print $2; exit}'` which takes the first match and exits (no duplicates expected given the invariant, but the `exit` guards against hypothetical edge cases).

### 3.4 Commit-Function Mapping Algorithm

For each diff file the script parses git's `@@` hunk headers:

```
@@ -123,10 +125,12 @@ DaemonServer::handle_report(msg)
```

The embedded text after the second `@@` is git's **function context annotation**, set by the diff driver's `funcname` pattern (C++ support is built in). The script strips the `@@ ... @@` prefix, strips the argument list (`\(.*`), and trims whitespace to get a bare `ClassName::method` or `method` token.

It then checks two forms against the `known` lookup set built from `functions.txt`:
1. Full form: `ClassName::method`
2. Bare name: `method` (after stripping everything up to and including `::`)

This dual-form check handles two cases: ctags emits the bare name (`handle_report`) while git emits the qualified form (`DaemonServer::handle_report`), or vice versa.

**Invariant**: this mapping is purely lexical — it matches names by string equality, not by line numbers. This makes it valid across the full history, including commits that predate a file rename.

---

## 4. Threat Model & Adversarial Handling

### 4.1 Attacker-Controlled Repository History

**Scenario**: a malicious actor crafts a commit message or file path containing shell metacharacters, awk field separators, or path traversal sequences (e.g., `../../etc/passwd`, `; rm -rf`).

**Mitigations**:
- All git output consumed by awk uses field variables (`$1`, `$2`, `$3`) — awk does not invoke a shell, so metacharacters in content cannot escape to the shell.
- SHA validation `[[ "${sha}" =~ ^[0-9a-f]{40}$ ]]` before any `git show` call: if a line in `commits.txt` or the map is not a valid 40-hex SHA, it is silently skipped. This blocks command injection through a crafted SHA-shaped string.
- `diff_file="${DIFFS_DIR}/${sha}.diff"` uses the validated SHA as the filename. Because SHAs are constrained to `[0-9a-f]{40}`, path traversal via the filename is impossible.
- `set -euo pipefail` means unexpected git failures abort the worker rather than silently continuing in a potentially inconsistent state.

**Residual risk**: `OUTPUT_DIR` is taken from `$1` (first CLI arg). A malicious caller could pass `--output-dir=/etc` and, with sufficient permissions, write files to sensitive locations. The script does not sanitize this argument. In practice the script is invoked manually by a trusted engineer on a known host.

### 4.2 Malicious File Content via ctags

**Scenario**: source files contain crafted strings that confuse ctags output parsing.

**Mitigation**: ctags output is consumed by awk's field-split, not by `eval` or `source`. The `grep -v "^!"` strips ctags header lines. Output is only written to `functions.txt`; it is never executed. Risk is limited to corrupted `functions.txt` entries, which degrade the commit-function map but cannot execute code.

### 4.3 Extremely Large Histories

**Scenario**: a class with thousands of commits causes the `map_cc.tmp` file to grow very large, or thousands of `git show` subprocesses exhaust file descriptors.

**Impact**: slow collection, possible OOM. No mitigation is implemented; the script has no commit-count cap. Workers are isolated subshells, so one very large class cannot directly crash other workers.

### 4.4 Repository Not Found / Not a Git Repo

**Mitigation**: `CEPH_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"`. If not inside a git repo, `CEPH_ROOT` defaults to `.`. Subsequent `git log` commands will then fail, and `set -euo pipefail` will abort the worker (not the main process, since workers run in background subshells). The `FAILED` counter captures this. The user sees `WARNING: worker PID X exited non-zero`.

---

## 5. Failure Modes, Edge Cases & Blast Radius

### 5.1 File Does Not Exist at HEAD

If `SRC_CC` does not exist in the working tree (e.g., the class was deleted or the path was wrong):

- `resolve_rename_chain` runs `git log --follow ... -- path` and produces no output if the path has never existed. `chain_cc.tmp` is empty.
- `build_sha_to_path_map` reads from an empty file and produces no output. `map_cc.tmp` is empty.
- `commits.txt` gets a header but no SHAs.
- `blame.txt` gets `# (file not found or empty)`.
- `functions.txt` skips the file (`[[ -f "${src_file}" ]] || continue`).
- No diffs are written.
- `commit_function_map.txt` is written with headers only.
- **Blast radius**: single class, silently empty. The class row in `INDEX.txt` shows `0 0 0`.

### 5.2 Rename Chain Produces Overlapping or Duplicate SHAs

If `git log --follow` somehow visits the same SHA twice (e.g., a complex merge history), `build_sha_to_path_map` may emit duplicate `sha path` lines. The `sort -u` in the commits.txt generation deduplicates SHAs before feeding them to `git log --no-walk`. For diffs, `awk '$1==sha{print $2; exit}'` takes the first match; duplicate entries for the same SHA with different paths would cause one to be ignored. **Blast radius**: at most one diff uses a slightly wrong historical path, producing a "new file mode" diff — the v3 bug it was designed to avoid, now isolated to only that SHA.

### 5.3 `ctags` Not Available

The script checks for `universal-ctags` then `ctags` at startup. If neither is found, `CTAGS_BIN` is empty, `functions.txt` is written with `# ctags not available`, and `commit_function_map.txt` will match no function names (all commits emit `(no functions)`). **Blast radius**: functions.txt and commit_function_map.txt are empty; all other outputs are unaffected.

### 5.4 `seg_old~1` Fails for Root Commits

`git log --format="%H" "${seg_old}~1..${seg_new}" -- "${path}"` — if `seg_old` is the very first commit in the repository, `seg_old~1` does not exist. Git silently treats a non-existent parent as the empty tree and still returns results for the range. The explicit second query `git log -1 ${seg_old}` then correctly captures `seg_old` itself. **Impact**: none; the two-pass design handles this.

### 5.5 Parallel Worker Collision on Shared Lock File

`LOG_LOCK` is keyed on `$$` (the PID of the main shell), so all workers share one lock file. Workers are subshells of the same script and inherit `LOG_LOCK`. `flock` on the shared file serializes log writes. **Risk**: if a worker exits abnormally without releasing `flock`, subsequent workers block on log writes. In practice `flock` uses advisory locks that are released automatically when the file descriptor is closed on process exit. **Blast radius**: log output may be delayed but collection continues.

### 5.6 OUTPUT_DIR Contains Spaces

`OUTPUT_DIR="${1:-/home/szuraski/BobOutput/Object History/v4}"` — the default value contains spaces. The script uses `"${OUT}"`, `"${DIFFS_DIR}"` etc. consistently with double-quoting, so spaces in the path are handled correctly for `mkdir`, `git show`, and `find`. The `IFS=':' read` that splits `.cc:.h` pairs is independent of `OUTPUT_DIR`. **Risk**: low, correctly handled.

### 5.7 Worker Failure Accounting

Background workers run in subshells (`collect_class ... &`). `set -euo pipefail` in the parent does **not** propagate to background jobs — a subshell failure does not abort the parent. The `wait "${job}" || FAILED=$(( FAILED + 1 ))` loop manually counts non-zero exits. The final exit code of the script is `0` even if some workers fail (the script logs the count but does not `exit 1`). A CI system piping the output would not see a failure signal.

---

## 6. Observability & Triage Playbook

### 6.1 Log Structure

All log output is written to **stderr** via `log()`. Format:

```
[collect-v4] --- ClassName ---
[collect-v4]   ClassName: N commits, M functions, K diffs -> /path/to/out/
[collect-v4] HEAD: <sha> (<date>)
[collect-v4] Output dir: <path>
[collect-v4] Launching 27 workers in parallel...
[collect-v4] Collection complete (v4). All workers succeeded.
[collect-v4] Index: /path/to/INDEX.txt
```

The recommended invocation captures this with `2>&1 | tee ~/tmp/collect-v4.log` (shown in the script header comment).

### 6.2 INDEX.txt

After all workers finish, `INDEX.txt` provides a per-class summary table:

```
Class                               Commits Functions    Diffs
-----                               ------- ---------    -----
ActivePyModule                           42        18       42
...
```

**Triage**: a class showing `0 0 0` indicates the file path is wrong or the file has never existed in git. A class showing commits > diffs suggests idempotent skip was triggered on a partial prior run, or some `git show` calls silently failed (piped to `|| true`).

### 6.3 Diagnosing a Bad Rename Chain

Inspect `<ClassName>/rename_chain.txt` directly:

```bash
cat Outputs/.../ActivePyModule/rename_chain.txt
```

Expected: newest segment uses `src/mgr/ActivePyModule.cc`, older segments use `src/mgr/MgrPyModule.cc` (or similar prior names). If only one segment appears for a class known to have been renamed, the `git log --follow` traversal failed to follow — check whether the rename was below git's rename-detection similarity threshold or whether `--follow` was not available in the installed git version.

### 6.4 Diagnosing a "New File Mode" Diff

If `diffs/<sha>.diff` begins with `new file mode 100644` for a commit you know modified an existing file, the historically-correct path was not resolved. Check:

1. `<ClassName>/map_cc.tmp` was deleted — rerun and check `resolve_rename_chain` for that class.
2. The SHA appears in `map_cc.tmp` but maps to the wrong path.
3. The fallback `[[ -z "${hist_cc}" ]] && hist_cc="${SRC_CC}"` was triggered — meaning the SHA appeared in `commits.txt` but not in `map_cc.tmp`, which is a bug in segment boundary handling.

### 6.5 Diagnosing Empty `commit_function_map.txt`

All entries show `(no functions)`:
- Check `functions.txt` is non-empty (`grep -v "^#" functions.txt | head`).
- Check that a sample diff file has `@@ ... @@ ClassName::method` in its hunk headers (`grep "^@@" diffs/<any>.diff | head`).
- If `@@` lines exist but function context is absent (e.g., `@@ -1,5 +1,5 @@` with nothing after the second `@@`), the git diff driver did not emit function context — this occurs when the file's language is not recognized. All files here end in `.cc`/`.h`, so this should not happen with a standard git C++ diff driver.

### 6.6 Re-Running After Partial Failure

The idempotent diff skip (`[[ -f "${diff_file}" ]] && continue`) means re-running the script will not regenerate existing diffs. It **will** regenerate `commits.txt`, `blame.txt`, `functions.txt`, `rename_chain.txt`, and `commit_function_map.txt` from scratch. Temp files (`chain_cc.tmp` etc.) are always cleaned up on success; on worker crash they may be left in `<ClassName>/`. Safe to delete manually before re-running.

---

*Document produced against `collect-object-history-v4.sh` at revision captured in the repository. All mechanisms described are grounded in the actual script code, not inferred behavior.*
