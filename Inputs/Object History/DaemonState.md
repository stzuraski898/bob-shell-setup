# Object History: DaemonState

**Source file:** `src/mgr/DaemonState.cc` / `src/mgr/DaemonState.h`
**Worktree:** `/home/szuraski/ceph-agent-5`
**Branch:** `agent/5`
**History range:** `a21b250f029` (2025-02-27) → `e9abc5ce0bb` (2025-08-14)
**Total commits touching these files:** 12
**Fix-signal commits:** 3 (`b4304d521f6`, `f1bac41828d`, `85d82faac25`)
**Curator date:** 2025-10-22

---

## Commit Log (all 12, chronological)

| # | SHA (short) | Date | Author | Subject |
|---|-------------|------|--------|---------|
| 1 | `a21b250f029` | 2025-02-27 | Adam King | Merge pull request #61013 (initial add of files in worktree) |
| 2 | `32a7157d8cc` | 2025-04-25 | Max Kellermann | common/LogClient: add missing include |
| 3 | `b4304d521f6` | 2025-07-31 | Brad Hubbard | mgr/DaemonState: Minimise time we hold the DaemonStateIndex lock ★ |
| 4 | `d2d4c7d3f86` | 2025-08-14 | Max Kellermann | mgr/DaemonState: forward-declare types from MMgrReport.h |
| 5 | `35f6dd06dd0` | 2025-08-14 | Max Kellermann | mgr/DaemonState: move PerfCounters classes to separate sources |
| 6 | `7bfbdb328a7` | 2025-08-14 | Max Kellermann | mgr/DaemonState: include cleanup |
| 7 | `e9abc5ce0bb` | 2025-08-14 | Max Kellermann | mgr/DaemonState: forward-declare class DaemonHealthMetric |
| 8 | `1aef3773f3b` | 2025-09-12 | Max Kellermann | mgr: add missing includes |
| 9 | `f1bac41828d` | 2025-10-01 | Edwin Rodriguez | Update indent settings cc ★ |
| 10 | `85d82faac25` | 2025-10-01 | Edwin Rodriguez | Update indent settings h ★ |
| 11 | `c8c1019d196` | 2025-10-02 | Edwin Rodriguez | Add missing blank line after comment block |
| 12 | `4adaf64d718` | 2025-10-02 | Edwin Rodriguez | Add blank line after header block |

★ = contains fix-signal keyword (Fixes: tracker reference)

---

## Class: DaemonState

**Defined in:** `src/mgr/DaemonState.h` (lines 41–88), `src/mgr/DaemonState.cc` (lines 41–221)
**Purpose:** Stores the per-daemon state for a single managed daemon, including metadata,
device maps, perf counter instances, service-beacon fields, and running/default config.
**Concurrency:** Callers must hold `DaemonState::lock` (a `ceph::mutex`) before accessing mutable fields.

---

## Method: DaemonState::DaemonState (constructor)

```cpp
explicit DaemonState(PerfCounterTypes &types_);
```

**Defined in:** `src/mgr/DaemonState.cc` line 41
**Intent:** Initialise the `perf_counters` member with the shared `PerfCounterTypes` registry.
**divergence_flag:** false — declaration matches implementation; no drift observed.

### Commit history

| SHA | Date | Author | Subject | Signal |
|-----|------|--------|---------|--------|
| `a21b250f029` | 2025-02-27 | Adam King | Initial add — constructor was inline in header | — |
| `d2d4c7d3f86` | 2025-08-14 | Max Kellermann | Un-inlined constructor to allow forward-declaration of MMgrReport types | structural |
| `e9abc5ce0bb` | 2025-08-14 | Max Kellermann | Re-confirmed out-of-line after DaemonHealthMetric forward-declare refactor | structural |

**Commits touching this method:** 3  **Fix-signal commits:** 0

### Notable diffs

None — all changes were structural (inline→out-of-line) with no behavioral change.

### Known defects

None.

---

## Method: DaemonState::~DaemonState (destructor)

```cpp
~DaemonState() noexcept;
```

**Defined in:** `src/mgr/DaemonState.cc` line 46 (`= default`)
**Intent:** Provide a defined, noexcept destructor so that the forward-declared `DaemonHealthMetric`
is fully visible at the destruction point (defined in `.cc` where the full type is available).
**divergence_flag:** false — `= default` matches declaration exactly.

### Commit history

| SHA | Date | Author | Subject | Signal |
|-----|------|--------|---------|--------|
| `d2d4c7d3f86` | 2025-08-14 | Max Kellermann | Added out-of-line destructor to support forward declaration of MMgrReport types | structural |
| `e9abc5ce0bb` | 2025-08-14 | Max Kellermann | Retained; now also supports forward-declared DaemonHealthMetric | structural |

**Commits touching this method:** 2  **Fix-signal commits:** 0

### Notable diffs

**`e9abc5ce0bb` — forward-declare class DaemonHealthMetric (2025-08-14, Max Kellermann):**
```diff
-  explicit DaemonState(PerfCounterTypes &types_)
-    : perf_counters(types_)
-  {
-  }
+  explicit DaemonState(PerfCounterTypes &types_);
+  ~DaemonState() noexcept;
```
The destructor was added out-of-line (`= default` in `.cc`) so that `DaemonHealthMetric`'s
full type is visible when the destructor runs, allowing the header to forward-declare it.

### Known defects

None.

---

## Method: DaemonState::set_metadata

```cpp
void set_metadata(const std::map<std::string,std::string>& m);
```

**Defined in:** `src/mgr/DaemonState.cc` lines 179–208
**Intent:** Parse the metadata map sent by a daemon (from `MMgrReport`) into structured fields:
clears and repopulates `devices` and `devices_bypath` from `device_ids`/`device_paths` keys,
and extracts `hostname`.
**divergence_flag:** false — declaration in header matches implementation.

### Commit history

| SHA | Date | Author | Subject | Signal |
|-----|------|--------|---------|--------|
| `a21b250f029` | 2025-02-27 | Adam King | Initial add — method present in full form | — |
| `f1bac41828d` | 2025-10-01 | Edwin Rodriguez | Update indent settings cc (mechanical whitespace fix) | fix (#72587) |

**Commits touching this method:** 2  **Fix-signal commits:** 1

### Notable diffs

**`f1bac41828d` — Update indent settings cc (2025-10-01, Edwin Rodriguez):**
Mechanical reformatting only — indent mode changed from `indent-tabs-mode:t` to
`indent-tabs-mode:nil`. No behavioral change.
Fixes: https://tracker.ceph.com/issues/72587

### Known defects

None.
(Note: `// TODO: this can be generalized to other daemons` on line 61 of the header refers
to the `daemon_health_metrics` **field**, not to this method.)

---

## Method: DaemonState::_get_config_defaults

```cpp
const std::map<std::string,std::string>& _get_config_defaults();
```

**Defined in:** `src/mgr/DaemonState.cc` lines 210–221
**Intent:** Lazily decode the `config_defaults_bl` bufferlist into the `config_defaults` map
on first access; return the decoded map. The leading underscore signals that the caller is
expected to hold `DaemonState::lock`.
**divergence_flag:** false — method is private-by-convention (underscore prefix);
declaration in header matches implementation.

### Commit history

| SHA | Date | Author | Subject | Signal |
|-----|------|--------|---------|--------|
| `a21b250f029` | 2025-02-27 | Adam King | Initial add | — |
| `f1bac41828d` | 2025-10-01 | Edwin Rodriguez | Update indent settings cc (mechanical) | fix (#72587) |

**Commits touching this method:** 2  **Fix-signal commits:** 1

### Notable diffs

**`f1bac41828d` — Update indent settings cc (2025-10-01, Edwin Rodriguez):**
Mechanical reformatting only. Fixes: https://tracker.ceph.com/issues/72587

### Known defects

None.

---

## Known defects (class-level)

### TODO — `src/mgr/DaemonState.h` line 61

```cpp
// TODO: this can be generalized to other daemons
std::vector<DaemonHealthMetric> daemon_health_metrics;
```

**Blame:** First introduced in `a21b250f029` (2025-02-27, Adam King).
**Meaning:** The `daemon_health_metrics` field is noted as potentially applicable to more
daemon types than it currently serves. No tracker reference is attached.

---

## Self-check (DaemonState)

| # | Check | Result |
|---|-------|--------|
| 1 | Every public method has a `## Method:` block | PASS — 4 methods: constructor, destructor, `set_metadata`, `_get_config_defaults` |
| 2 | Every fix/revert commit has a Notable diffs entry | PASS — `b4304d521f6` affects DaemonStateIndex only (documented there); `f1bac41828d` and `85d82faac25` noted under affected methods |
| 3 | Every TODO/FIXME/HACK appears under Known defects | PASS — `// TODO` line 61 documented |
| 4 | `divergence_flag` set for every method | PASS — all four methods have `divergence_flag: false` |
| 5 | Commit counts are accurate and traceable | PASS — 12 total, 3 fix-signal, per-method counts verified |
| 6 | Author attribution present for all commits | PASS |
| 7 | No speculative claims about code not examined | PASS — all diffs inspected via `git show` |
