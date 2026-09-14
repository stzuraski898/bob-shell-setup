# Intent Artefact — `DaemonKey`

**Object:** `src/mgr/DaemonKey.cc` / `src/mgr/DaemonKey.h`
**HEAD SHA:** `8681fa6ebac230f86eb445bf57095c63e7f1abcc`
**Corpus collected:** 2026-09-11T21:40:59Z
**Assessed:** all 3 non-merge commits, 3 diff files, blame for both source files

---

## 1. Commit History Summary

| SHA (short) | Date | Author | Subject |
|---|---|---|---|
| `5aac7eba` | 2019-09-29 | Kefu Chai | mgr: use a struct for DaemonKey |
| `85d82faa` | 2025-10-01 | Edwin Rodriguez | Update indent settings h |
| `aec62d9e` | 2025-08-14 | Max Kellermann | mgr/DaemonKey: include cleanup |

**Total commits:** 3  
**Date range:** 2019-09-29 → 2025-10-01  
**Note on `commit_function_map.txt`:** All three SHAs map to `(no functions)`. This is expected: `5aac7eba` was a new-file creation (the `@@` hunk header carries no surrounding-function context), and the other two commits only touched include lines and editor modelines — both outside any function body.

---

## 2. Rename Chain

Both `src/mgr/DaemonKey.cc` and `src/mgr/DaemonKey.h` have existed at their current paths since they were created by `5aac7eba` (2019-09-29). No renames have occurred.

---

## 3. Design Intent (established by `5aac7eba`, tracker #42079)

`DaemonKey` was introduced to replace ad-hoc `std::pair<std::string,std::string>` usage throughout the manager. The commit message lists three explicit goals:

1. **Readability:** field names `type` and `name` replace `first`/`second`.
2. **ADL control:** a named struct allows a single `operator<<` to be found everywhere, eliminating the ambiguity with the generic pair streaming operator that produced the erroneous `"osd,1"` form. The canonical printed form is `"type.name"` (dot-separated, e.g. `"osd.1"`).
3. **Consolidation:** `parse`, `operator<<`, and `to_string` are co-located in one translation unit with a stable dot-separator invariant.

**Wire format invariant (established `5aac7eba`):** The canonical string representation of a `DaemonKey` is `type + '.' + name`. This invariant is shared by `parse`, `operator<<`, and `ceph::to_string` and must never diverge between them.

---

## 4. Function Analyses

> **functions.txt lists 8 entries** (4 in `.cc`, 4 in `.h`) for 4 logical functions. Each logical function is treated as one unit below.

---

### 4.1 `parse` (static member)

**Locations:** `src/mgr/DaemonKey.cc:5` · `src/mgr/DaemonKey.h:15`  
**Relevant commits:** `5aac7eba` (created)  
**Blame:** all lines attributed to `5aac7eba`

#### Intent

Parse a dot-separated string of the form `"type.name"` into a `DaemonKey`. Returns a `std::pair<DaemonKey, bool>` where the `bool` signals whether parsing succeeded (a dot was found). On failure, returns `{{}, false}` — a zero-value `DaemonKey` and `false`.

The choice of `s.find('.')` (finds **first** dot) is intentional: `name` may itself contain dots (e.g. `"client.admin"` where `type="client"`, `name="admin"`).

#### Invariants (all established by `5aac7eba`)

- I-1: A dot `'.'` must be present for parse to succeed.
- I-2: On missing dot, return value is `{DaemonKey{}, false}` — not an exception.
- I-3: `type` receives `s.substr(0, p)` — everything before the first dot.
- I-4: `name` receives `s.substr(p + 1)` — everything after the first dot (may contain further dots).

#### Implementation Critique

**Current implementation (reconstructed from `5aac7eba` diff, confirmed by blame):**

```cpp
// DaemonKey.cc:5-13
std::pair<DaemonKey, bool> DaemonKey::parse(const std::string& s)
{
  auto p = s.find('.');
  if (p == s.npos) {
    return {{}, false};
  } else {
    return {DaemonKey{s.substr(0, p), s.substr(p + 1)}, true};
  }
}
```

**Rating: CONFORMANT** — all four invariants are correctly enforced.

**UNGROUNDED — empty-field keys (`.cc:11`):** When input is `"."`, `p == 0`, and the function returns `{DaemonKey{"", ""}, true}`. When input is `".foo"`, `type` is `""`. When input is `"foo."`, `name` is `""`. No commit has ever established whether empty `type` or empty `name` is a valid `DaemonKey`. The struct definition in `5aac7eba` carries the comment `// service type, like "osd", "mon"` and `// service id / name, like "1", "a"` — both examples are non-empty — but no guard exists and no commit explicitly accepts or rejects empty fields. The caller is silently handed `true` with an empty-field key. This is UNGROUNDED: the code path exists, but its intent was never stated in the commit history.

---

### 4.2 `operator<`

**Locations:** `src/mgr/DaemonKey.cc:15` · `src/mgr/DaemonKey.h:18`  
**Relevant commits:** `5aac7eba` (created)  
**Blame:** all lines attributed to `5aac7eba`

#### Intent

Provide a strict weak ordering for `DaemonKey` so it can be used as a key in ordered containers (`std::map`, `std::set`). Ordering is lexicographic: `type` compared first via `std::string::compare`, then `name` by `<` if `type` values are equal.

#### Invariants (all established by `5aac7eba`)

- I-5: `type` is the primary sort key.
- I-6: `name` is the secondary sort key (tiebreaker).
- I-7: The comparison satisfies strict weak ordering (irreflexive, asymmetric, transitive).

#### Implementation Critique

**Current implementation (reconstructed from `5aac7eba` diff, confirmed by blame):**

```cpp
// DaemonKey.cc:15-24
bool operator<(const DaemonKey& lhs, const DaemonKey& rhs)
{
  if (int cmp = lhs.type.compare(rhs.type); cmp < 0) {
    return true;
  } else if (cmp > 0) {
    return false;
  } else {
    return lhs.name < rhs.name;
  }
}
```

**Rating: CONFORMANT** — I-5, I-6, I-7 all enforced.

**Note — redundant branch (`.cc:19`):** The `else if (cmp > 0) { return false; }` branch is never needed for correctness — after `cmp < 0` is ruled out, returning `lhs.name < rhs.name` in the `else` would handle both `cmp > 0` (yields `false` because `lhs.name < rhs.name` is irrelevant when types differ) — wait: this is not the case; `lhs.name < rhs.name` would be evaluated even when `cmp > 0`, producing an incorrect result. The `else if (cmp > 0)` branch is therefore **necessary for correctness**, not merely a clarity choice. The three-branch structure is correct and required; no issue.

---

### 4.3 `operator<<`

**Locations:** `src/mgr/DaemonKey.cc:26` · `src/mgr/DaemonKey.h:19`  
**Relevant commits:** `5aac7eba` (created); `aec62d9e` (include cleanup — moved `<ostream>` to `.cc`, replaced with `<iosfwd>` in `.h`)  
**Blame:** function body attributed to `5aac7eba`; `.h:6` (`#include <iosfwd>`) attributed to `aec62d9e`

#### Intent

Stream a `DaemonKey` to an `std::ostream` in the canonical `"type.name"` format. This is the **primary motivation** for the struct: eliminate the `"osd,1"` form produced by pair's generic `operator<<` (tracker #42079). Must produce output identical to `ceph::to_string`.

The include-cleanup commit (`aec62d9e`) moved `#include <ostream>` from `.h` to `.cc`, placing `#include <iosfwd>` in `.h` instead. This is correct: `.h` only declares `operator<<` (needs `std::ostream` as an incomplete type for the declaration), while `.cc` defines it (needs the full `std::ostream` definition).

#### Invariants (all established by `5aac7eba`)

- I-8: Output format is exactly `type << '.' << name` — dot-separated, no spaces.
- I-9: Output must be consistent with `ceph::to_string` output.
- I-10: Free function (non-member) — required for ADL to resolve correctly everywhere (commit message explicitly calls this out).

#### Implementation Critique

**Current implementation (reconstructed from diffs, confirmed by blame):**

```cpp
// DaemonKey.cc:26-29
std::ostream& operator<<(std::ostream& os, const DaemonKey& key)
{
  return os << key.type << '.' << key.name;
}
```

**Rating: CONFORMANT** — I-8, I-9, I-10 all satisfied. Format matches `to_string` exactly.

**Include split (`.h:6`, `.cc:3`):** The `<iosfwd>` / `<ostream>` split introduced by `aec62d9e` is correct and idiomatic. No issue.

---

### 4.4 `ceph::to_string`

**Locations:** `src/mgr/DaemonKey.cc:32` · `src/mgr/DaemonKey.h:22`  
**Relevant commits:** `5aac7eba` (created)  
**Blame:** all lines attributed to `5aac7eba`

#### Intent

Return a `std::string` representation of a `DaemonKey` in the canonical `"type.name"` format. Lives in `namespace ceph` — the commit places it there deliberately to control ADL: Ceph-internal code calling `ceph::to_string(key)` gets this function without ambiguity.

#### Invariants (all established by `5aac7eba`)

- I-11: Return value is exactly `type + '.' + name`.
- I-12: Output must be consistent with `operator<<` output (I-9).
- I-13: Must be in `namespace ceph` for ADL correctness (explicit design decision in `5aac7eba`).
- I-14: `parse(to_string(k)).first == k` and `parse(to_string(k)).second == true` for any `k` with non-empty `type` and `name` (round-trip property implied by shared dot invariant).

#### Implementation Critique

**Current implementation (reconstructed from `5aac7eba` diff, confirmed by blame):**

```cpp
// DaemonKey.cc:31-36
namespace ceph {
std::string to_string(const DaemonKey& key)
{
  return key.type + '.' + key.name;
}
}
```

**Rating: CONFORMANT** — I-11, I-12, I-13, I-14 all satisfied.

**UNGROUNDED — round-trip for empty-field keys (`.cc:34`):** For `DaemonKey{"", ""}`, `to_string` returns `"."`. Then `parse(".")` returns `{DaemonKey{"",""}, true}` — the round-trip holds mechanically. However, as noted under `parse`, whether such keys are intentionally valid is never established by any commit. The `to_string` behaviour for empty-field keys is therefore also UNGROUNDED by the same gap.

---

## 5. Cross-Function Consistency Check

| Property | `parse` | `operator<<` | `to_string` |
|---|---|---|---|
| Separator character | `'.'` (find) | `'.'` (emit) | `'.'` (concat) |
| Field order | type before name | type before name | type before name |
| Consistent | ✓ | ✓ | ✓ |

All three functions agree on the wire format. No divergence.

---

## 6. DIVERGED Findings

**None.** No commit introduced a behavioural change that contradicts an earlier invariant. The two post-2019 commits (`aec62d9e`, `85d82faa`) are purely cosmetic (include hygiene, editor modeline) and do not affect any function body.

---

## 7. UNGROUNDED Findings

| ID | Location | Description |
|---|---|---|
| U-1 | `DaemonKey.cc:11` (`parse`) | Input strings with an empty `type` (`".foo"`, `"."`) or empty `name` (`"foo."`, `"."`) return `{key, true}` with one or both fields empty. No commit has ever established whether empty `type` or empty `name` is a valid key. The code path is reachable and silently succeeds. |
| U-2 | `DaemonKey.cc:34` (`to_string`) | `to_string` for a key with empty fields (e.g. `DaemonKey{"",""}`) returns `"."`. The round-trip holds mechanically, but whether such keys should ever exist is unaddressed. Consequential of U-1. |

---

## 8. OVERCAUTIOUS Findings

**None.** There are no defensive checks in the codebase that are demonstrably rendered redundant by established invariants.

---

## 9. Self-Check

| Check | Result |
|---|---|
| Every commit in `commits.txt` read? | ✓ All 3 commits read and analysed |
| Every diff in `diffs/` read? | ✓ All 3 diff files read |
| Every function in `functions.txt` has a section? | ✓ All 8 entries (4 logical functions) covered |
| Every invariant cites the SHA that established it? | ✓ All invariants cite `5aac7eba` or `aec62d9e` |
| Every DIVERGED flag names the specific commit and contradicting line? | ✓ No DIVERGED flags raised (none warranted) |
| All ungrounded code paths flagged? | ✓ U-1 and U-2 flagged with line numbers |
| `blame.txt` consulted for last-touch attribution? | ✓ Used to confirm all function bodies are `5aac7eba`; header include line 6 is `aec62d9e` |
| `commit_function_map.txt` discrepancy explained? | ✓ All entries are `(no functions)` due to new-file creation context and non-function-body hunks |
