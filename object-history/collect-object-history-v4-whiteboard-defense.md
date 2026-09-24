# Whiteboard Defense: `collect-object-history-v4.sh`

## 1. Purpose & Motivation

`collect-object-history-v4.sh` is a **rename-aware corpus collector** for the Ceph `src/mgr/` subsystem. Its job is to produce a rich, per-class historical snapshot — commits, diffs, blame, and function lists — for 27 C++ manager classes, so that an AI or human reviewer can understand how each class evolved over the entire project lifetime.

The key problem it solves over its predecessor (`v3`) is **rename contamination**: when a class's source file was renamed during the project's history (e.g., `MgrPyModule.cc` → `ActivePyModule.cc`), calling `git show <old-sha> -- <current-path>` produces a spurious "new file mode" diff. v4 resolves the historically-correct path for every commit before generating diffs, eliminating this noise.

---

## 2. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  Main loop                                                          │
│   for each class in CLASS_FILES (sorted, parallel &)               │
│       └─ collect_class CLASS SRC_CC SRC_H                          │
└────────────────────────────┬────────────────────────────────────────┘
                             │
          ┌──────────────────▼────────────────────┐
          │  collect_class (background subshell)   │
          │                                        │
          │  resolve_rename_chain(SRC_CC)          │
          │  resolve_rename_chain(SRC_H)           │
          │       └─ chain_cc.tmp / chain_h.tmp    │
          │                                        │
          │  build_sha_to_path_map(chain_cc)       │
          │  build_sha_to_path_map(chain_h)        │
          │       └─ map_cc.tmp / map_h.tmp        │
          │                                        │
          │  ┌─ commits.txt  (SHA + one-liner)     │
          │  ├─ blame.txt    (git blame -w -M -C)  │
          │  ├─ functions.txt (ctags)              │
          │  ├─ rename_chain.txt (human-readable)  │
          │  ├─ diffs/<sha>.diff (per commit)      │
          │  └─ commit_function_map.txt            │
          └────────────────────────────────────────┘

  After all workers: INDEX.txt (summary table)
```

---

## 3. Configuration

| Variable | Default | Purpose |
|---|---|---|
| `CEPH_ROOT` | `git rev-parse --show-toplevel` | Absolute path to the repo root; falls back to `.` |
| `OUTPUT_DIR` | `$1` or `/home/szuraski/BobOutput/Object History/v4` | Root of all output |
| `CLASS_FILES` | Associative array | Maps class name → `src_cc:src_h` pairs for 27 Ceph mgr classes |

The associative array `CLASS_FILES` is the single place to add or remove classes. The colon-separated value encodes the `.cc` and `.h` paths relative to `CEPH_ROOT`.

---

## 4. Key Functions

### 4.1 `resolve_rename_chain <current_path>`

**Input:** A relative path to a source file (e.g., `src/mgr/ActivePyModule.cc`).

**Output (stdout):** One line per path segment, newest first:
```
<path> <sha_newest_in_segment> <sha_oldest_in_segment>
```

**Mechanism:**

1. Runs `git log --follow --name-status --format='COMMIT:%H' -- <path>` to produce a stream that follows renames backward through history.
2. Pipes into `awk`:
   - `COMMIT:<sha>` lines update `seg_new` (first time) and `seg_old` (always) for the current segment.
   - `R` (rename) lines close the current segment (emit a line) and open a new segment at the old path (`$2`), resetting `seg_new = seg_old` so the new segment starts from the rename commit.
   - `END` flushes the last open segment.

**Example output for `ActivePyModule.cc`:**
```
src/mgr/ActivePyModule.cc  <sha_today>  <sha_of_rename>
src/mgr/MgrPyModule.cc     <sha_of_rename>  <sha_first_commit>
```

---

### 4.2 `build_sha_to_path_map <chain_file>`

**Input:** A file containing segment lines produced by `resolve_rename_chain`.

**Output (stdout):** One line per commit that touched a file in any segment:
```
<sha> <path>
```

**Mechanism:**

For each segment `(path, seg_new, seg_old)`:
1. Runs `git log --no-merges --format="%H" "${seg_old}~1..${seg_new}" -- "${path}"` to enumerate all commits strictly within the segment range.
2. Runs a separate `git log -1 "${seg_old}"` to include the oldest boundary commit (excluded by the `~1` trick above).

This produces a complete, non-overlapping SHA→path mapping across the entire rename history.

---

### 4.3 `collect_class <CLASS> <SRC_CC> <SRC_H>`

The per-class worker. Runs as a background subshell (`&`). Produces all output files under `${OUTPUT_DIR}/${CLASS}/`.

**Step-by-step flow:**

| Step | Output File | Method |
|---|---|---|
| 1 | `rename_chain.txt` | `resolve_rename_chain` for `.cc` and `.h` separately |
| 2 | `map_cc.tmp` / `map_h.tmp` | `build_sha_to_path_map` from chain files |
| 3 | `commits.txt` | Union of SHAs from both maps → `git log --no-walk --stdin` for one-liner metadata |
| 4 | `blame.txt` | `git blame -w -M -C` on current `.cc` (and `.h` if distinct) |
| 5 | `functions.txt` | `ctags --language-force=C++ --c++-kinds=f+p` on current `.cc` and `.h` |
| 6 | `diffs/<sha>.diff` | `git show <sha> -- <hist_cc> [<hist_h>]` using historically-correct paths from map |
| 7 | `commit_function_map.txt` | Parse `@@` hunk-context lines from each `.diff` and match against `functions.txt` names |

Temp files (`chain_cc.tmp`, `chain_h.tmp`, `map_cc.tmp`, `map_h.tmp`, `func_names.tmp`) are deleted at the end.

---

## 5. Output File Reference

```
${OUTPUT_DIR}/
├── INDEX.txt                          ← Summary table (class, #commits, #functions, #diffs)
└── <ClassName>/
    ├── commits.txt                    ← SHA date author | subject (rename-aware, newest first)
    ├── blame.txt                      ← git blame -w -M -C on .cc and .h
    ├── functions.txt                  ← ctags: "qualified_name | file:line"
    ├── rename_chain.txt               ← path segments: "path sha_new sha_old"
    ├── commit_function_map.txt        ← "SHA | func1 func2 ..."
    └── diffs/
        └── <40-char-sha>.diff         ← scoped diff (historically-correct paths)
```

### `commit_function_map.txt` detail

- For each commit, its pre-generated `.diff` is re-read.
- Every `@@ -a,b +c,d @@ <context>` line in a unified diff contains the nearest enclosing function name appended by git.
- The script strips the `@@ ... @@` prefix, strips the argument list, and matches the result against `functions.txt` names — both the full `Class::method` form and the bare `method` name.
- This means even pre-rename commits correctly map to current function identities since the match is on content, not on line numbers.

---

## 6. Parallelism & Locking

```bash
for CLASS in ...; do
  collect_class "${CLASS}" "${SRC_CC}" "${SRC_H}" &
done
for job in $(jobs -p); do
  wait "${job}" || ...
done
```

All 27 class workers are spawned simultaneously as background subshells. A simple `flock`-guarded `log()` function serialises stderr output so log lines don't interleave. Each worker writes to its own `${OUTPUT_DIR}/${CLASS}/` directory, so there is no shared state contention between workers.

---

## 7. Edge Cases & Design Decisions

| Scenario | Handling |
|---|---|
| `.cc` == `.h` (single-file class) | `chain_h` and `map_h` are `cp`'d from the `.cc` equivalents; blame and diffs are only run once |
| SHA not found in path map (shouldn't happen) | Falls back silently to the current `SRC_CC`/`SRC_H` path |
| `ctags` not installed | `CTAGS_BIN` is empty; `functions.txt` emits a comment line rather than crashing |
| Commit is a merge | `--no-merges` excludes merges from the SHA list; diffs would be noisy across merged branches |
| Diff already written | `[[ -f "${diff_file}" ]] && continue` makes the diff step **idempotent**; safe to rerun |
| Worker process fails | Non-zero exit is caught with `wait "${job}" || ...`; `FAILED` counter increments; script continues and reports at the end |
| Repo not a git worktree | `git rev-parse --show-toplevel` fails; `CEPH_ROOT` becomes `.`; subsequent `git` calls may still fail but do not crash the script due to `|| true` guards |

---

## 8. Dependencies

| Tool | Required? | Notes |
|---|---|---|
| `git` | **Yes** | Must be ≥ 2.9 for `--stdin` support on `git log` |
| `ctags` | Optional | Universal-ctags preferred; exuberant-ctags accepted; absence degrades `functions.txt` only |
| `awk` | **Yes** | POSIX awk (gawk/mawk/nawk all work) |
| `flock` | Optional | Used for serialised logging; falls back to non-locked `echo` if absent |
| `bash` | **Yes** | Requires bash ≥ 4.0 for associative arrays (`declare -A`) |

---

## 9. Known Limitations

1. **`build_sha_to_path_map` boundary off-by-one**: The `${seg_old}~1..${seg_new}` range excludes `seg_old`, then a second `git log -1 "${seg_old}"` includes it. If `seg_old` is the initial commit of the repository, `${seg_old}~1` does not exist and the range expression silently returns nothing — the fallback `-1` call still catches it.

2. **`commits.txt` sort order**: After unioning SHAs from the two maps and passing them to `git log --no-walk --stdin`, output order is determined by git's walk and may not be strictly chronological. Consumers should not rely on line order for anything time-sensitive.

3. **`commit_function_map.txt` matching fidelity**: The `@@` hunk context is only as good as git's nearest-enclosing-function heuristic for C++. Templated functions, lambdas, and free functions defined before any class scope may not produce useful context strings.

4. **No incremental mode**: The script rebuilds all artifacts from scratch on each run (except existing `.diff` files, which are skipped). For large repos this can be slow.

5. **Hardcoded output path default**: The fallback `OUTPUT_DIR` contains a space (`Object History/v4`). While quoted consistently in the script, tools that receive the path without quoting downstream may fail.

---

## 10. Typical Invocation & Deployment

```bash
# Local (from inside a ceph worktree):
bash collect-object-history-v4.sh /tmp/my-output

# Remote (deploy-and-run on sockeni07):
scp collect-object-history-v4.sh szuraski@sockeni07:~/tmp/
ssh szuraski@sockeni07 'cd /home/szuraski/ceph && \
  bash ~/tmp/collect-object-history-v4.sh 2>&1 | tee ~/tmp/collect-v4.log'
```

Expected runtime: several minutes for a full Ceph history with 27 parallel workers. Completion is confirmed by `INDEX.txt` in the output directory and a `Collection complete (v4)` log line on stderr.
