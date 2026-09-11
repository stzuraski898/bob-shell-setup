# Object History: DaemonStateIndex

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

## Class: DaemonStateIndex

**Defined in:** `src/mgr/DaemonState.h` (lines 134–292), `src/mgr/DaemonState.cc` (lines 223–387)
**Purpose:** Fuse the collection of per-daemon metadata from Ceph into a view queryable by
service type, ID, or server (FQDN). Manages the `all` map (keyed by `DaemonKey`), `by_server`
secondary index, and a `devices` map of `DeviceState` refs. Provides a read/write-locked
interface via shared_mutex.
**Concurrency:** Uses `ceph::shared_mutex lock` (read-write). Public methods acquire the lock
internally; underscore-prefixed variants (`_insert`, `_rm`, `_erase`) require the caller to
already hold a write lock.

---

## Method: DaemonStateIndex::DaemonStateIndex (constructor)

```cpp
DaemonStateIndex();
```

**Defined in:** `src/mgr/DaemonState.cc` line 223 (`= default`)
**Intent:** Default-initialise all members (maps, set, mutex). No parameters needed.
**divergence_flag:** false — `= default` in `.cc` matches the declared default constructor.

### Commit history

| SHA | Date | Author | Subject | Signal |
|-----|------|--------|---------|--------|
| `a21b250f029` | 2025-02-27 | Adam King | Initial add — constructor was `{}` inline in header | — |
| `d2d4c7d3f86` | 2025-08-14 | Max Kellermann | Un-inlined constructor and destructor to allow forward-declaration of MMgrReport types | structural |

**Commits touching this method:** 2  **Fix-signal commits:** 0

### Notable diffs

**`d2d4c7d3f86` — forward-declare types from MMgrReport.h (2025-08-14, Max Kellermann):**
```diff
-  DaemonStateIndex() {}
+  DaemonStateIndex();
+  ~DaemonStateIndex();
```
The constructor and destructor were moved out of line so that forward-declared types from
`MMgrReport.h` are fully visible at construction/destruction time (definitions in `.cc`).

### Known defects

None.

---

## Method: DaemonStateIndex::~DaemonStateIndex (destructor)

```cpp
~DaemonStateIndex();
```

**Defined in:** `src/mgr/DaemonState.cc` line 224 (`= default`)
**Intent:** Provide a defined destructor so forward-declared types are fully visible at
the destruction site (in `.cc`).
**divergence_flag:** false — `= default` matches declaration.

### Commit history

| SHA | Date | Author | Subject | Signal |
|-----|------|--------|---------|--------|
| `d2d4c7d3f86` | 2025-08-14 | Max Kellermann | Added out-of-line destructor for MMgrReport forward-declaration | structural |

**Commits touching this method:** 1  **Fix-signal commits:** 0

### Notable diffs

See constructor notable diff above — same commit introduced both.

### Known defects

None.

---

## Method: DaemonStateIndex::insert

```cpp
void insert(DaemonStatePtr dm);
```

**Defined in:** `src/mgr/DaemonState.cc` lines 226–230
**Intent:** Thread-safe (write-locked) wrapper around `_insert`. Acquires `lock` then
delegates to the internal helper.
**divergence_flag:** false — declaration matches implementation.

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

## Method: DaemonStateIndex::_insert

```cpp
void _insert(DaemonStatePtr dm);
```

**Defined in:** `src/mgr/DaemonState.cc` lines 232–252
**Intent:** Internal (lock-must-be-held) insert: if the key already exists, erases first;
then registers the daemon in both `by_server` and `all` maps, and updates the `devices`
map with attachment tuples (hostname, devname, path).
**divergence_flag:** false — underscore prefix correctly signals lock precondition;
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

## Method: DaemonStateIndex::exists

```cpp
bool exists(const DaemonKey &key) const;
```

**Defined in:** `src/mgr/DaemonState.cc` lines 314–319
**Intent:** Return `true` if a daemon with the given `DaemonKey` is present in the `all` map.
Acquires a shared (read) lock.
**divergence_flag:** false — declaration matches implementation.

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

## Method: DaemonStateIndex::get

```cpp
DaemonStatePtr get(const DaemonKey &key);
```

**Defined in:** `src/mgr/DaemonState.cc` lines 321–331
**Intent:** Return a shared pointer to the daemon state for `key`, or `nullptr` if not found.
Acquires a shared (read) lock.
**divergence_flag:** false — declaration matches implementation.

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

## Method: DaemonStateIndex::rm

```cpp
void rm(const DaemonKey &key);
```

**Defined in:** `src/mgr/DaemonState.cc` lines 333–337
**Intent:** Thread-safe (write-locked) wrapper around `_rm`. Acquires `lock` then delegates.
**divergence_flag:** false — declaration matches implementation.

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

## Method: DaemonStateIndex::_rm

```cpp
void _rm(const DaemonKey &key);
```

**Defined in:** `src/mgr/DaemonState.cc` lines 339–344
**Intent:** Internal (lock-must-be-held) remove: calls `_erase` only if the key exists.
The guard against absent keys prevents double-erase panics.
**divergence_flag:** false — underscore prefix signals lock precondition; declaration matches implementation.

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

## Method: DaemonStateIndex::get_by_server

```cpp
DaemonStateCollection get_by_server(const std::string &hostname) const;
```

**Defined in:** `src/mgr/DaemonState.cc` lines 302–312
**Intent:** Return a copy of the DaemonStateCollection for the given server hostname.
Returns an empty collection if the hostname is not found. Returns by value to avoid callers
needing to hold the index lock while iterating.
**divergence_flag:** false — declaration matches implementation; the header comment
explicitly documents the by-value return rationale.

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

## Method: DaemonStateIndex::get_by_service

```cpp
DaemonStateCollection get_by_service(const std::string &svc_name) const;
```

**Defined in:** `src/mgr/DaemonState.cc` lines 286–300
**Intent:** Iterate over `all` and collect every daemon whose `DaemonKey::type` matches
`svc_name`. Returns by value. Acquires shared (read) lock.
**divergence_flag:** false — declaration matches implementation.

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

## Method: DaemonStateIndex::get_all (inline)

```cpp
DaemonStateCollection get_all() const { return all; }
```

**Defined in:** `src/mgr/DaemonState.h` line 180
**Intent:** Return a copy of the full `all` map. Inline; acquires no lock — callers must
use the individual `DaemonState::lock` on each returned entry.
**divergence_flag:** false — entirely inline; no `.cc` counterpart.

### Commit history

| SHA | Date | Author | Subject | Signal |
|-----|------|--------|---------|--------|
| `a21b250f029` | 2025-02-27 | Adam King | Initial add | — |
| `85d82faac25` | 2025-10-01 | Edwin Rodriguez | Update indent settings h (mechanical) | fix (#72587) |

**Commits touching this method:** 2  **Fix-signal commits:** 1

### Notable diffs

**`85d82faac25` — Update indent settings h (2025-10-01, Edwin Rodriguez):**
Mechanical reformatting only. Fixes: https://tracker.ceph.com/issues/72587

### Known defects

None.

---

## Method: DaemonStateIndex::with_daemons_by_server (template, inline)

```cpp
template<typename Callback, typename...Args>
auto with_daemons_by_server(Callback&& cb, Args&&... args) const ->
  decltype(cb(by_server, std::forward<Args>(args)...));
```

**Defined in:** `src/mgr/DaemonState.h` lines 182–191
**Intent:** Invoke a callback with a snapshot copy of `by_server` *after* releasing the lock,
preventing Python GIL contention from blocking other threads waiting on the index lock.
**divergence_flag:** false — entirely inline; no `.cc` counterpart.

### Commit history

| SHA | Date | Author | Subject | Signal |
|-----|------|--------|---------|--------|
| `a21b250f029` | 2025-02-27 | Adam King | Initial add — callback was called while holding the shared lock | — |
| `b4304d521f6` | 2025-07-31 | Brad Hubbard | **Fix: copy `by_server` under the lock, release lock, then invoke callback** | **fix** (#72337) |
| `85d82faac25` | 2025-10-01 | Edwin Rodriguez | Update indent settings h (mechanical) | fix (#72587) |

**Commits touching this method:** 3  **Fix-signal commits:** 2

### Notable diffs

**`b4304d521f6` — Minimise time we hold the DaemonStateIndex lock (2025-07-31, Brad Hubbard):**
```diff
-    std::shared_lock l{lock};
-    
-    return std::forward<Callback>(cb)(by_server, std::forward<Args>(args)...);
+    const decltype(by_server) by_server_copy = [&] {
+      // Don't hold the lock any longer than necessary
+      std::shared_lock l{lock};
+      return by_server;
+    }();
+    return std::forward<Callback>(cb)(by_server_copy, std::forward<Args>(args)...);
```
**Root cause:** calling back into Python functions while holding `lock` could block this thread
waiting for the GIL, causing extended delays for all threads waiting to acquire the index lock.
**Fix:** capture a copy of `by_server` under the lock, release the lock via RAII, then invoke
the callback on the copy.
Fixes: https://tracker.ceph.com/issues/72337

**`85d82faac25` — Update indent settings h (2025-10-01, Edwin Rodriguez):**
Mechanical reformatting only. Fixes: https://tracker.ceph.com/issues/72587

### Known defects

None.

---

## Method: DaemonStateIndex::with_device (template, inline)

```cpp
template<typename Callback, typename...Args>
bool with_device(const std::string& dev, Callback&& cb, Args&&... args) const;
```

**Defined in:** `src/mgr/DaemonState.h` lines 193–203
**Intent:** Read-locked lookup of a device by id; invoke callback on the `DeviceState` if
found and return `true`, or return `false` if the device is unknown.
**divergence_flag:** false — entirely inline.

### Commit history

| SHA | Date | Author | Subject | Signal |
|-----|------|--------|---------|--------|
| `a21b250f029` | 2025-02-27 | Adam King | Initial add | — |
| `85d82faac25` | 2025-10-01 | Edwin Rodriguez | Update indent settings h (mechanical) | fix (#72587) |

**Commits touching this method:** 2  **Fix-signal commits:** 1

### Notable diffs

**`85d82faac25` — Update indent settings h (2025-10-01, Edwin Rodriguez):**
Mechanical reformatting only. Fixes: https://tracker.ceph.com/issues/72587

### Known defects

None.

---

## Method: DaemonStateIndex::with_device_write (template, inline)

```cpp
template<typename Callback, typename...Args>
bool with_device_write(const std::string& dev, Callback&& cb, Args&&... args);
```

**Defined in:** `src/mgr/DaemonState.h` lines 205–218
**Intent:** Write-locked lookup of a device; invoke callback; after callback completes,
erase the `DeviceState` from the map if it has become empty (no daemons, no metadata).
Returns `false` if device not found.
**divergence_flag:** false — entirely inline.

### Commit history

| SHA | Date | Author | Subject | Signal |
|-----|------|--------|---------|--------|
| `a21b250f029` | 2025-02-27 | Adam King | Initial add | — |
| `85d82faac25` | 2025-10-01 | Edwin Rodriguez | Update indent settings h (mechanical) | fix (#72587) |

**Commits touching this method:** 2  **Fix-signal commits:** 1

### Notable diffs

**`85d82faac25` — Update indent settings h (2025-10-01, Edwin Rodriguez):**
Mechanical reformatting only. Fixes: https://tracker.ceph.com/issues/72587

### Known defects

None.

---

## Method: DaemonStateIndex::with_device_create (template, inline)

```cpp
template<typename Callback, typename...Args>
void with_device_create(const std::string& dev, Callback&& cb, Args&&... args);
```

**Defined in:** `src/mgr/DaemonState.h` lines 220–226
**Intent:** Write-locked get-or-create of a `DeviceState`; invoke callback on the resulting
(possibly newly created) device. Used when the caller needs to ensure the device entry exists.
**divergence_flag:** false — entirely inline.

### Commit history

| SHA | Date | Author | Subject | Signal |
|-----|------|--------|---------|--------|
| `a21b250f029` | 2025-02-27 | Adam King | Initial add | — |
| `85d82faac25` | 2025-10-01 | Edwin Rodriguez | Update indent settings h (mechanical) | fix (#72587) |

**Commits touching this method:** 2  **Fix-signal commits:** 1

### Notable diffs

**`85d82faac25` — Update indent settings h (2025-10-01, Edwin Rodriguez):**
Mechanical reformatting only. Fixes: https://tracker.ceph.com/issues/72587

### Known defects

None.

---

## Method: DaemonStateIndex::with_devices (template, inline)

```cpp
template<typename Callback, typename...Args>
void with_devices(Callback&& cb, Args&&... args) const;
```

**Defined in:** `src/mgr/DaemonState.h` lines 228–234
**Intent:** Read-locked iteration over all known devices; invoke callback once per `DeviceState`.
**divergence_flag:** false — entirely inline.

### Commit history

| SHA | Date | Author | Subject | Signal |
|-----|------|--------|---------|--------|
| `a21b250f029` | 2025-02-27 | Adam King | Initial add | — |
| `85d82faac25` | 2025-10-01 | Edwin Rodriguez | Update indent settings h (mechanical) | fix (#72587) |

**Commits touching this method:** 2  **Fix-signal commits:** 1

### Notable diffs

**`85d82faac25` — Update indent settings h (2025-10-01, Edwin Rodriguez):**
Mechanical reformatting only. Fixes: https://tracker.ceph.com/issues/72587

### Known defects

None.

---

## Method: DaemonStateIndex::with_devices2 (template, inline)

```cpp
template<typename CallbackInitial, typename Callback, typename...Args>
void with_devices2(CallbackInitial&& cbi, Callback&& cb, Args&&... args) const;
```

**Defined in:** `src/mgr/DaemonState.h` lines 236–245
**Intent:** Read-locked iteration over all devices, but with a separate `cbi` callback invoked
first while the lock is held (allowing the caller to initialise output state before iteration
begins), followed by per-device `cb` invocations. Both callbacks run under the shared lock.
**divergence_flag:** false — entirely inline.

### Commit history

| SHA | Date | Author | Subject | Signal |
|-----|------|--------|---------|--------|
| `a21b250f029` | 2025-02-27 | Adam King | Initial add | — |
| `85d82faac25` | 2025-10-01 | Edwin Rodriguez | Update indent settings h (mechanical) | fix (#72587) |

**Commits touching this method:** 2  **Fix-signal commits:** 1

### Notable diffs

**`85d82faac25` — Update indent settings h (2025-10-01, Edwin Rodriguez):**
Mechanical reformatting only. Fixes: https://tracker.ceph.com/issues/72587

### Known defects

None.

---

## Method: DaemonStateIndex::list_devids_by_server (inline)

```cpp
void list_devids_by_server(const std::string& server, std::set<std::string> *ls);
```

**Defined in:** `src/mgr/DaemonState.h` lines 247–256
**Intent:** Populate `ls` with all device IDs attached to daemons running on the given server.
Acquires individual `DaemonState::lock` per entry (not the index lock directly — calls
`get_by_server` which takes the shared lock and returns a copy).
**divergence_flag:** false — entirely inline.

### Commit history

| SHA | Date | Author | Subject | Signal |
|-----|------|--------|---------|--------|
| `a21b250f029` | 2025-02-27 | Adam King | Initial add | — |
| `85d82faac25` | 2025-10-01 | Edwin Rodriguez | Update indent settings h (mechanical) | fix (#72587) |

**Commits touching this method:** 2  **Fix-signal commits:** 1

### Notable diffs

**`85d82faac25` — Update indent settings h (2025-10-01, Edwin Rodriguez):**
Mechanical reformatting only. Fixes: https://tracker.ceph.com/issues/72587

### Known defects

None.

---

## Method: DaemonStateIndex::notify_updating (inline)

```cpp
void notify_updating(const DaemonKey &k);
```

**Defined in:** `src/mgr/DaemonState.h` lines 258–261
**Intent:** Insert `k` into the `updating` set under a write lock, signalling that a daemon
update is in progress.
**divergence_flag:** false — entirely inline.

### Commit history

| SHA | Date | Author | Subject | Signal |
|-----|------|--------|---------|--------|
| `a21b250f029` | 2025-02-27 | Adam King | Initial add | — |
| `85d82faac25` | 2025-10-01 | Edwin Rodriguez | Update indent settings h (mechanical) | fix (#72587) |

**Commits touching this method:** 2  **Fix-signal commits:** 1

### Notable diffs

**`85d82faac25` — Update indent settings h (2025-10-01, Edwin Rodriguez):**
Mechanical reformatting only. Fixes: https://tracker.ceph.com/issues/72587

### Known defects

None.

---

## Method: DaemonStateIndex::clear_updating (inline)

```cpp
void clear_updating(const DaemonKey &k);
```

**Defined in:** `src/mgr/DaemonState.h` lines 262–265
**Intent:** Remove `k` from the `updating` set under a write lock, signalling that the update
has completed.
**divergence_flag:** false — entirely inline.

### Commit history

| SHA | Date | Author | Subject | Signal |
|-----|------|--------|---------|--------|
| `a21b250f029` | 2025-02-27 | Adam King | Initial add | — |
| `85d82faac25` | 2025-10-01 | Edwin Rodriguez | Update indent settings h (mechanical) | fix (#72587) |

**Commits touching this method:** 2  **Fix-signal commits:** 1

### Notable diffs

**`85d82faac25` — Update indent settings h (2025-10-01, Edwin Rodriguez):**
Mechanical reformatting only. Fixes: https://tracker.ceph.com/issues/72587

### Known defects

None.

---

## Method: DaemonStateIndex::is_updating (inline)

```cpp
bool is_updating(const DaemonKey &k);
```

**Defined in:** `src/mgr/DaemonState.h` lines 266–269
**Intent:** Return `true` if `k` is currently in the `updating` set (i.e. an in-flight update
is ongoing). Acquires a shared lock.
**divergence_flag:** false — entirely inline.

### Commit history

| SHA | Date | Author | Subject | Signal |
|-----|------|--------|---------|--------|
| `a21b250f029` | 2025-02-27 | Adam King | Initial add | — |
| `85d82faac25` | 2025-10-01 | Edwin Rodriguez | Update indent settings h (mechanical) | fix (#72587) |

**Commits touching this method:** 2  **Fix-signal commits:** 1

### Notable diffs

**`85d82faac25` — Update indent settings h (2025-10-01, Edwin Rodriguez):**
Mechanical reformatting only. Fixes: https://tracker.ceph.com/issues/72587

### Known defects

None.

---

## Method: DaemonStateIndex::update_metadata (inline)

```cpp
void update_metadata(DaemonStatePtr state,
                     const std::map<std::string,std::string>& meta);
```

**Defined in:** `src/mgr/DaemonState.h` lines 271–281
**Intent:** Atomically remove and re-insert a daemon's entry in the index so that
device metadata changes take effect. Holds the write lock for the entire operation
to prevent partial visibility; uses a nested lock guard on `state->lock` to safely
call `state->set_metadata`.
**divergence_flag:** false — entirely inline.

### Commit history

| SHA | Date | Author | Subject | Signal |
|-----|------|--------|---------|--------|
| `a21b250f029` | 2025-02-27 | Adam King | Initial add | — |
| `85d82faac25` | 2025-10-01 | Edwin Rodriguez | Update indent settings h (mechanical) | fix (#72587) |

**Commits touching this method:** 2  **Fix-signal commits:** 1

### Notable diffs

**`85d82faac25` — Update indent settings h (2025-10-01, Edwin Rodriguez):**
Mechanical reformatting only. Fixes: https://tracker.ceph.com/issues/72587

### Known defects

None.

---

## Method: DaemonStateIndex::cull

```cpp
void cull(const std::string& svc_name, const std::set<std::string>& names_exist);
```

**Defined in:** `src/mgr/DaemonState.cc` lines 346–368
**Intent:** Given the set of daemon names that currently exist for `svc_name` (from a cluster
map), erase any daemons in the index of that service type that are absent from the set.
Uses a write lock and batches victims before erasing to avoid iterator invalidation.
**divergence_flag:** false — declaration matches implementation.

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

## Method: DaemonStateIndex::cull_services

```cpp
void cull_services(const std::set<std::string>& types_exist);
```

**Defined in:** `src/mgr/DaemonState.cc` lines 370–387
**Intent:** For all daemons whose `service_daemon` flag is set, erase those whose service type
is absent from `types_exist`. Targets dynamically registered service daemons only (skips
built-in types). Uses a write lock and batches victims.
**divergence_flag:** false — declaration matches implementation.

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

### FIXME — `src/mgr/DaemonState.h` line 164

```cpp
// FIXME: shouldn't really be public, maybe construct DaemonState
// objects internally to avoid this.
PerfCounterTypes types;
```

**Blame:** First introduced in `a21b250f029` (2025-02-27, Adam King).
**Meaning:** The `PerfCounterTypes types` field is public only because `DaemonState` is
constructed by callers who need to pass `types` as a constructor argument. Making it private
would require `DaemonStateIndex` to become a factory for `DaemonState` objects. No tracker
reference is attached.

---

## Self-check (DaemonStateIndex)

| # | Check | Result |
|---|-------|--------|
| 1 | Every public method has a `## Method:` block | PASS — 22 methods covered: constructor, destructor, `insert`, `_insert`, `exists`, `get`, `rm`, `_rm`, `get_by_server`, `get_by_service`, `get_all`, `with_daemons_by_server`, `with_device`, `with_device_write`, `with_device_create`, `with_devices`, `with_devices2`, `list_devids_by_server`, `notify_updating`, `clear_updating`, `is_updating`, `update_metadata`, `cull`, `cull_services` |
| 2 | Every fix/revert commit has a Notable diffs entry | PASS — `b4304d521f6` (with_daemons_by_server), `f1bac41828d` (all .cc methods), `85d82faac25` (all .h methods) each documented |
| 3 | Every TODO/FIXME/HACK appears under Known defects | PASS — `// FIXME` line 164 documented |
| 4 | `divergence_flag` set for every method | PASS — all methods have `divergence_flag: false` |
| 5 | Commit counts are accurate and traceable | PASS — 12 total, 3 fix-signal, per-method counts verified |
| 6 | Author attribution present for all commits | PASS |
| 7 | No speculative claims about code not examined | PASS — all diffs inspected via `git show` |
