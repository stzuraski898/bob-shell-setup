# ClusterState — Intent Artefact

**Object:** `src/mgr/ClusterState` (`.cc` + `.h`)
**HEAD SHA:** `8681fa6ebac230f86eb445bf57095c63e7f1abcc`
**Corpus collected:** 2026-09-11T21:40:59Z
**Total non-merge commits:** 71
**Date range:** 2016-06-30 (`ac30e6cee2b2`) → 2026-05-19 (`0bac6af3c18a`)
**Assessment tool:** History Assessment v4

---

## Corpus Summary

| Metric | Value |
|---|---|
| Total commits | 71 |
| HEAD SHA | 8681fa6ebac230f86eb445bf57095c63e7f1abcc |
| Oldest commit | ac30e6cee2b2 (2016-06-30, John Spray — initial mgr creation) |
| Newest commit | 0bac6af3c18a (2026-05-19, Nitzan Mordechai — remove debug-30 memory spike) |
| Functions (cc+h combined) | 28 entries across both files |

---

## Class-Level Context

`ClusterState` was introduced in `ac30e6cee2b2` as the central holder of cluster-wide map state for `ceph-mgr`. Its protected data forms a single writer / many reader model: one `ceph::mutex lock` guards all non-osdmap fields. The OSDMap is owned by `Objecter` and accessed via `objecter->with_osdmap()` which uses Objecter's own internal read-write lock; `ClusterState::with_osdmap()` does **not** acquire `lock`.

The class began as a simple container (FSMap, health JSON, mon-status JSON). Over 71 commits it grew to include: full `PGMap` + `PGMap::Incremental` with batched application logic; `ServiceMap`; `MgrMap`; an admin-socket hook (`dump_osd_network`); and synchronised accessors (`with_*` template family).

---

## Rename Chain

The files have not been renamed. Both `src/mgr/ClusterState.cc` and `src/mgr/ClusterState.h` have retained their paths since `ac30e6cee2b2`.

---

## Function Sections

### `ClusterState::ClusterState` (constructor)

**File:** `src/mgr/ClusterState.cc:34` · `src/mgr/ClusterState.h:63`

#### Commit history (relevant)

| SHA | Date | Subject | Impact |
|---|---|---|---|
| `ac30e6cee2b2` | 2016-06-30 | mgr: create ceph-mgr service | Created: `(monc_, objecter_)`, named Mutex lock "ClusterState" |
| `6c10417f7ed3` | 2017-06-27 | mgr: include MgrMap in ClusterState | Added `mgrmap` param; `mgr_map(mgrmap)` initialiser |
| `19810df09e0b` | 2017-06-13 | mon: mgr: enable "osd df" on the manager | Added `pgservice(pg_map)` initialiser |
| `1dcab1c77007` | 2017-08-28 | mon: drop PGMapStatService | Removed `pgservice(pg_map)` initialiser |
| `5d3c1856415f` | 2019-07-09 | mgr: Add "dump_osd_network" | Added `asok_hook(NULL)` initialiser |
| `c93dc8849145` | 2019-07-07 | mgr: s/Mutex/ceph::mutex/ | Removed explicit lock name from ctor body; lock init moved to header in-class initialiser |

#### Invariants established

- **I1** (`6c10417f7ed3`): Constructor requires a `const MgrMap&`; `mgr_map` is copy-initialised from it so the object is never in an uninitialised map state.
- **I2** (`5d3c1856415f`): `asok_hook` is initialised to `NULL`; `final_init()` must be called before any admin-socket work.
- **I3** (`c93dc8849145`): Lock is a `ceph::mutex` named `"ClusterState"` via in-class initialiser; no positional name argument in the ctor body.

#### Current implementation critique (cc:34–42)

```
ClusterState::ClusterState(
  MonClient *monc_,
  Objecter *objecter_,
  const MgrMap& mgrmap)
  : monc(monc_),
    objecter(objecter_),
    mgr_map(mgrmap),
    asok_hook(NULL)
{}
```

- Lines 34–42 (blame: `6c10417f7ed3`, `5d3c1856415f`).
- **OK.** All invariants I1–I3 are satisfied.
- `monc` and `objecter` are stored as raw pointers with no null check; callers are documented as providing valid pointers. This is consistent with `with_monmap` and `with_osdmap` which assert non-null before use (`ab23c506964753990f9fe23e314b9f3e2547a773`). No finding.

---

### `set_objecter`

**File:** `src/mgr/ClusterState.cc:44` · `src/mgr/ClusterState.h:65`

#### Commit history

| SHA | Subject |
|---|---|
| `ac30e6cee2b2` | Created: acquires `Mutex::Locker` |
| `948635a8b213` | s/Mutex::Locker/std::lock_guard/ |

#### Invariants

- **I1** (`ac30e6cee2b2`): `objecter` write must be serialised under `lock`.

#### Current implementation critique (cc:44–49)

```cpp
void ClusterState::set_objecter(Objecter *objecter_)
{
  std::lock_guard l(lock);
  objecter = objecter_;
}
```

- Line 46 (blame: `948635a8b213`): lock acquired — invariant I1 satisfied.
- **OK.** No findings.

---

### `set_fsmap`

**File:** `src/mgr/ClusterState.cc:51` · `src/mgr/ClusterState.h:66`

#### Commit history

| SHA | Subject |
|---|---|
| `ac30e6cee2b2` | Created; acquires lock |
| `6c10417f7ed3` | Added `set_mgr_map` as sibling (set_fsmap itself unchanged) |
| `948635a8b213` | s/Mutex::Locker/std::lock_guard/ |

#### Invariants

- **I1** (`ac30e6cee2b2`): `fsmap` write serialised under `lock`.

#### Current implementation critique (cc:51–56)

```cpp
void ClusterState::set_fsmap(FSMap const &new_fsmap)
{
  std::lock_guard l(lock);
  fsmap = new_fsmap;
}
```

- Line 53 (blame: `948635a8b213`): lock acquired — invariant I1 satisfied.
- **OK.** No findings.

---

### `set_mgr_map`

**File:** `src/mgr/ClusterState.cc:58` · `src/mgr/ClusterState.h:67`

#### Commit history

| SHA | Subject |
|---|---|
| `6c10417f7ed3` | Created with `Mutex::Locker` |
| `948635a8b213` | s/Mutex::Locker/std::lock_guard/ |

#### Invariants

- **I1** (`6c10417f7ed3`): `mgr_map` write serialised under `lock`.

#### Current implementation critique (cc:58–62)

```cpp
void ClusterState::set_mgr_map(MgrMap const &new_mgrmap)
{
  std::lock_guard l(lock);
  mgr_map = new_mgrmap;
}
```

- Line 60 (blame: `948635a8b213`): lock acquired — I1 satisfied.
- **OK.** No findings.

---

### `set_service_map`

**File:** `src/mgr/ClusterState.cc:64` · `src/mgr/ClusterState.h:68`

#### Commit history

| SHA | Subject |
|---|---|
| `97cfc3cb694e` | Created with `Mutex::Locker` |
| `948635a8b213` | s/Mutex::Locker/std::lock_guard/ |
| `da362675da51` | Synchronisation of health/mon_status (no change to set_service_map body, but established pattern that all setters need lock) |

#### Invariants

- **I1** (`97cfc3cb694e`): `servicemap` write serialised under `lock`.

#### Current implementation critique (cc:64–68)

```cpp
void ClusterState::set_service_map(ServiceMap const &new_service_map)
{
  std::lock_guard l(lock);
  servicemap = new_service_map;
}
```

- Line 66 (blame: `948635a8b213`): lock acquired — I1 satisfied.
- **OK.** No findings.

---

### `load_digest`

**File:** `src/mgr/ClusterState.cc:70` · `src/mgr/ClusterState.h:58`

#### Commit history

| SHA | Date | Subject | Impact |
|---|---|---|---|
| `ac30e6cee2b2` | 2016-06-30 | Initial creation | Stored `pg_summary_json`, `health_json`, `mon_status_json`; **no lock held** |
| `fa147e3a591a` | 2016-07-31 | mgr: handle PGStats with a PGMap | Removed `pg_summary_json` field and its assignment |
| `da362675da51` | 2020-03-27 | mgr: synchronize ClusterState's health and mon_status | **Added `std::lock_guard l(lock)`** (fixes tracker #24995); removed direct get accessors `get_health()` / `get_mon_status()`, replaced with `with_health()` / `with_mon_status()` template accessors |

#### Invariants

- **I1** (`da362675da51`): `health_json` and `mon_status_json` writes must be serialised under `lock` (tracker #24995 — race between `load_digest` writer and module readers).
- **I2** (`fa147e3a591a`): `pg_summary_json` is no longer part of the digest; any code storing it would be incorrect.
- **I3** (`a075639ce746`): Parameter changed from raw `MMgrDigest*` to (for `ingest_pgstats`) `ref_t`; `load_digest` still takes raw `MMgrDigest*` — caller is responsible for message lifetime.

#### Current implementation critique (cc:70–75)

```cpp
void ClusterState::load_digest(MMgrDigest *m)
{
  std::lock_guard l(lock);
  health_json = std::move(m->health_json);
  mon_status_json = std::move(m->mon_status_json);
}
```

- Line 72 (blame: `da362675da51`): lock acquired — invariant I1 satisfied.
- Lines 73–74: std::move used; consistent with initial intent from `ac30e6cee2b2`.
- **OK.** No findings.

---

### `ingest_pgstats`

**File:** `src/mgr/ClusterState.cc:77` · `src/mgr/ClusterState.h:59`

#### Commit history (full)

| SHA | Date | Subject | Impact |
|---|---|---|---|
| `fa147e3a591a` | 2016-07-31 | mgr: handle PGStats with a PGMap | Created; local `PGMap::Incremental`, lock held, applied per-call, pool existence check via `pg_map.pg_stat.count()` |
| `afa7078763ef` | 2016-09-22 | mon: refactor PGMap updating code for reuse | Removed private helper methods, delegated to `PGMapUpdater` |
| `3da07ea0a599` | 2017-03-20 | mgr: optimization some judgment | Refactored pool-existence and version checks, used `else if` (introduced subtle UB: `pg_map.pg_stat[pgid]` dereferences without pool existence verified) |
| `6afca3beb2a8` | 2017-05-23 | mgr/ClusterState: make pg stat filtering less fragile | Changed pool-existence check from `pg_map.pg_stat.count()` to `existing_pools.count()` (set of pool IDs); fixed logic from `3da07ea0a599` |
| `d6d1db62edeb` | 2017-05-23 | mgr: apply PGMap incremental at same interval | **Promoted `pending_inc` to member**; removed local Incremental; removed `apply_incremental` call from `ingest_pgstats`; accumulation-only now |
| `983fe8ec888b` | 2017-05-20 | mon,mgr: std::move(osd_stat) | `std::move` for `osd_stat` |
| `83b9ef73c0c1` | 2017-08-28 | mon/PGMap: remove osd_epochs | Removed epoch arg from `update_stat()` call |
| `ae688fc4d72c` | 2017-07-11 | mgr/ClusterState: do not mangle PGMap outside of Incremental | Used `pg_map.pg_stat.find()` instead of `pg_map.pg_stat[pgid]` for version check (prevents default-insertion) |
| `9e906733fe07` | 2018-07-29 | mgr/ClusterState: discard pg updates for pgs >= pg_num | Changed `existing_pools` from `set<int64_t>` to `map<int64_t,unsigned>` (pool_id→pg_num); added `pgid.ps() >= r->second` filter |
| `63df40608243` | 2017-12-11 | osd,mon: start using per-pool statistics | Added `pool_stat` ingestion loop into `pending_inc.pool_statfs_updates` |
| `a075639ce746` | 2019-04-15 | mgr/DaemonServer: use ref_t<M> | Parameter changed to `ceph::ref_t<MPGStats>` |
| `a7612d33d1e4` | 2017-08-10 | mgr/ClusterState: record osd_stat for out osds too | Removed is_in check; unconditionally `update_stat()` |
| `493ec9d3acd3` | 2020-07-29 | mgr: don't update osd stat which is already out | Re-introduced is_in check (fixes #46440); out OSD gets empty stat with seq preserved |
| `70b41ea1ee83` | 2025-06-06 | src/mgr/ClusterState.cc: micro improve ingest_pgstats | Cached `end()` iterators; changed `[]= ` to `insert_or_assign` |

#### Invariants

- **I1** (`d6d1db62edeb`): `ingest_pgstats` only **accumulates** into `pending_inc`. It must not call `apply_incremental`; that is `update_delta_stats`'s job.
- **I2** (`6afca3beb2a8`): Pool existence is checked against `existing_pools` (not against `pg_map.pg_stat`). `existing_pools` is kept in sync by `notify_osdmap`. A PG stat for an unknown pool is silently dropped.
- **I3** (`9e906733fe07`): A PG stat where `pgid.ps() >= existing_pools[pgid.pool()]` (i.e., ps ≥ pg_num) is silently dropped.
- **I4** (`ae688fc4d72c`): Version comparison uses `.find()` + iterator; never `pg_map.pg_stat[pgid]` which would default-insert (tracker #20208).
- **I5** (`493ec9d3acd3`): An out OSD must submit an empty `osd_stat_t` (seq preserved) rather than its real stats (fixes #46440). The `is_in` check is mandatory.
- **I6** (`63df40608243`): `stats->pool_stat` entries must also be copied into `pending_inc.pool_statfs_updates` keyed by `(pool_id, osd_from)`.
- **I7** (`a075639ce746`): Parameter is `ceph::ref_t<MPGStats>` — reference-counted, caller need not manage lifetime.

#### Error conditions

- Pool not in `existing_pools`: silently drop and log at dout(15) — established by `6afca3beb2a8`.
- `pgid.ps() >= pg_num`: silently drop and log at dout(15) — established by `9e906733fe07`.
- PG stat version not newer than existing: silently skip — established by `fa147e3a591a`, fixed by `ae688fc4d72c`.

#### Current implementation critique (cc:77–136)

- **Line 82–84** (`493ec9d3acd3`): `is_in` check via `with_osdmap` — correct. However `with_osdmap` does **not** acquire `lock`; it is called while `lock` is held (line 79). This is fine because Objecter's `with_osdmap` acquires Objecter's own rwlock. No deadlock risk from documented ordering.
- **Line 89–91** (`493ec9d3acd3`): `empty_stat.seq = stats->osd_stat.seq` — seq is preserved for correlation. Intent is that callers can still track which report was processed even for out OSDs.
- **Line 94–95** (`70b41ea1ee83`): End iterator caching (`existing_pools_end_it`, `pg_map_pg_stat_end_it`) — these iterators are captured *before* the loop. If `existing_pools` or `pg_map.pg_stat` were modified inside the loop this would be invalid. They are not modified in this scope (only `pending_inc` is modified), so this is safe.
- **Line 102–103** (`70b41ea1ee83`): Changed comparison to `r == existing_pools_end_it` — functionally equivalent; cached iterator is valid for the lifetime of the lock.
- **Line 124** (`70b41ea1ee83`): Changed to `q != pg_map_pg_stat_end_it` — correct; cached before loop.
- **Line 132** (`70b41ea1ee83`): `insert_or_assign` instead of `operator[]` — avoids default-construction then assignment; correct.
- **Line 135** (`70b41ea1ee83`): `pool_statfs_updates.insert_or_assign(...)` — same optimization, correct.
- **UNGROUNDED — line 96**: Comment on line 100 says "In case we're hearing about a PG that according to last OSDMap update should not exist" but the check (lines 102–110) is against `existing_pools`, not the OSDMap. This is intentional (`6afca3beb2a8`) but there is no comment explaining the deliberate decoupling from the OSDMap at this point.
- **OK otherwise.** All invariants I1–I7 are satisfied.

---

### `update_delta_stats`

**File:** `src/mgr/ClusterState.cc:139` · `src/mgr/ClusterState.h:61`

#### Commit history

| SHA | Date | Subject | Impact |
|---|---|---|---|
| `d6d1db62edeb` | 2017-05-23 | mgr: apply PGMap incremental at same interval | **Created**: stamps `pending_inc`, sets version, calls `apply_incremental` |
| `aad1afcb96de` | 2017-05-30 | mgr: reset pending_inc after applying it | Added `pending_inc = PGMap::Incremental()` after apply (fixes double-apply idempotency issue) |
| `c2258991393f` | 2017-06-07 | mgr/ClusterState: dump pgmap and inc at dout 30 | Added `pg_map` and `pending_inc` JSON dumps at dout(30) — unconditionally |
| `03a761c980a1` | 2018-11-15 | mgr: lock pg_map too for osd_pool_stats and notify_osdmap | Added `assert(ceph_mutex_is_locked(lock))` to `notify_osdmap`; no change to `update_delta_stats` but established pattern that callers must hold lock |
| `63df40608243` | 2017-12-11 | osd,mon: start using per-pool statistics | No change to `update_delta_stats` body |
| `0bac6af3c18a` | 2026-05-19 | mgr/ClusterState: remove debug 30 memory spike | **Changed**: replaced unconditional `pg_map` + `pending_inc` JSON dump with `if (!pending_inc.empty())` guarded incremental-only dump (fixes #64082) |

#### Invariants

- **I1** (`d6d1db62edeb`): `pending_inc.stamp` and `pending_inc.version` must be set immediately before `apply_incremental`; version = `pg_map.version + 1`.
- **I2** (`aad1afcb96de`): `pending_inc` must be reset to a default-constructed `PGMap::Incremental()` after every `apply_incremental` call. Without this the same stats would be applied twice on the next call.
- **I3** (`0bac6af3c18a`): Debug dump at dout(30) is only emitted when `!pending_inc.empty()` to prevent log queue flooding with multi-MB entries (tracker #64082).
- **I4** (implicit from `03a761c980a1`): `update_delta_stats` does **not** acquire `lock` itself; it is called from the mgr tick path. The mgr tick path must hold `lock` before calling (enforced by assertion in `notify_osdmap`; the equivalent for `update_delta_stats` is that the mgr holds lock in `DaemonServer::tick()`). **NOTE:** There is no `assert(ceph_mutex_is_locked(lock))` inside `update_delta_stats` itself, unlike `notify_osdmap`.

#### Current implementation critique (cc:139–155)

```
void ClusterState::update_delta_stats()
{
  pending_inc.stamp = ceph_clock_now();
  pending_inc.version = pg_map.version + 1; // to make apply_incremental happy
  dout(10) << " v" << pending_inc.version << dendl;

  if (!pending_inc.empty()) {
    dout(30) << " incremental:\n";
    JSONFormatter jf(true);
    jf.dump_object("pending_inc", pending_inc);
    jf.flush(*_dout);
    *_dout << dendl;
  }

  pg_map.apply_incremental(g_ceph_context, pending_inc);
  pending_inc = PGMap::Incremental();
}
```

- **Line 145** (`0bac6af3c18a`): `if (!pending_inc.empty())` — invariant I3 satisfied.
- **Line 153** (`fa147e3a591a`): `apply_incremental` called.
- **Line 154** (`aad1afcb96de`): `pending_inc = PGMap::Incremental()` — invariant I2 satisfied.
- **DIVERGED — missing lock assertion**: `notify_osdmap` (line 159 of cc) has `assert(ceph_mutex_is_locked(lock))` (established by `03a761c980a1`), which documents that the caller must hold the lock before calling. `update_delta_stats` has no equivalent assertion at line 139–155 even though it also reads/writes `pg_map` and `pending_inc` which require the same protection. The intent from `d6d1db62edeb` and `03a761c980a1` is that both functions are called under the same lock. The missing assertion means lock violations on this path are undetectable.

---

### `notify_osdmap`

**File:** `src/mgr/ClusterState.cc:157` · `src/mgr/ClusterState.h:70`

#### Commit history (full)

| SHA | Date | Subject | Impact |
|---|---|---|---|
| `fa147e3a591a` | 2016-07-31 | mgr: handle PGStats with a PGMap | Created; local pending_inc; called `_update_creating_pgs` + `_register_new_pgs`; applied and no reset |
| `afa7078763ef` | 2016-09-22 | mon: refactor PGMap updating code for reuse | Replaced private helpers with `PGMapUpdater::update_creating_pgs` + `PGMapUpdater::register_new_pgs`; TODO comment |
| `3893432646b7` | 2017-02-10 | mgr: mark stale PGs | Added `PGMapUpdater::check_down_pgs` call with `need_check_down_pg_osds` |
| `454da5e7b24c` | 2017-02-24 | mon: pass const variables by const ref not pointer | Changed `&pg_map` ptr args to pg_map refs |
| `681d37c05554` | 2017-05-19 | mgr/ClusterState: apply latest osdmap to pgmap | Added `PGMapUpdater::check_osd_map` call |
| `0612b716275403` | 2017-05-19 | mgr: simplify handling of new pgs/pools | Removed `update_creating_pgs` and `register_new_pgs` calls (OSDMonitor now handles creation) |
| `6afca3beb2a8` | 2017-05-23 | make pg stat filtering less fragile | Added `existing_pools` update loop after `check_osd_map` |
| `d6d1db62edeb` | 2017-05-23 | apply PGMap incremental at same interval | Moved to member `pending_inc`; stamped version; moved `apply_incremental` call here |
| `aad1afcb96de` | 2017-05-30 | reset pending_inc after applying it | Added `pending_inc = PGMap::Incremental()` reset |
| `c2258991393f` | 2017-06-07 | dump pgmap and inc at dout 30 | Added unconditional dout(30) dumps |
| `9e906733fe07` | 2018-07-29 | discard pg updates for pgs >= pg_num | Changed `existing_pools` value to `pg_num` |
| `03a761c980a1` | 2018-11-15 | lock pg_map too | Changed `std::lock_guard l(lock)` to `assert(ceph_mutex_is_locked(lock))` — caller must hold lock |
| `0bac6af3c18a` | 2026-05-19 | remove debug 30 memory spike | Replaced unconditional dumps with guarded `if (!pending_inc.empty())` incremental-only |

#### Invariants

- **I1** (`03a761c980a1`): Caller must hold `lock` before calling `notify_osdmap` (enforced by `assert(ceph_mutex_is_locked(lock))` at line 159). The function does not acquire the lock itself.
- **I2** (`681d37c05554`): `PGMapUpdater::check_osd_map` must be called first in the sequence, before `check_down_pgs`, so deleted OSDs/pools are cleaned from `pg_map` before down-PG checking.
- **I3** (`6afca3beb2a8`): After `check_osd_map`, `existing_pools` must be rebuilt from `osd_map.get_pools()` with `pg_num` values, so that subsequent `ingest_pgstats` calls use the same epoch's pool list.
- **I4** (`3893432646b7`): `PGMapUpdater::check_down_pgs` is called with `force=true` because the mgr uses brute-force (no delta OSD list) — "don't bother being clever by only checking osds that went up/down."
- **I5** (`aad1afcb96de`): `pending_inc` must be reset after `apply_incremental` to prevent double-application.
- **I6** (`d6d1db62edeb`): `pending_inc.stamp` and `pending_inc.version` must be set to `ceph_clock_now()` and `pg_map.version + 1` before the call.
- **I7** (`0bac6af3c18a`): dout(30) dump only when `!pending_inc.empty()` (tracker #64082).

#### Error conditions

- No explicit error conditions are returned; the function is void. The lock assertion at line 159 will abort on lock violation.

#### Current implementation critique (cc:157–193)

- **Line 159** (`03a761c980a1`): `assert(ceph_mutex_is_locked(lock))` — invariant I1 enforced correctly.
- **Lines 161–163**: stamp and version set — invariants I5/I6 satisfied.
- **Line 165** (`681d37c05554`): `PGMapUpdater::check_osd_map` — invariant I2 satisfied.
- **Lines 169–172** (`6afca3beb2a8`): `existing_pools.clear()` + loop rebuilding from `osd_map.get_pools()` with `p.second.get_pg_num()` — invariant I3 satisfied.
- **Lines 176–178** (`3893432646b7`): `PGMapUpdater::check_down_pgs` with brute-force — invariant I4 satisfied.
- **Lines 180–186** (`0bac6af3c18a`): `if (!pending_inc.empty())` guarded dump — invariant I7 satisfied.
- **Line 188**: `pg_map.apply_incremental(g_ceph_context, pending_inc)`.
- **Line 189** (`aad1afcb96de`): `pending_inc = PGMap::Incremental()` — invariant I5 satisfied.
- **Lines 190–192** (`afa7078763ef`): TODO comment about PGMonitor separation — stale (PGMonitor has been removed in Reef era), but harmless.
- **UNGROUNDED — lines 190–192**: The TODO comment "Complete the separation of PG state handling so that a cut-down set of functionality remains in PGMonitor while the full-blown PGMap lives only here" was left from `afa7078763ef` (2016-09-22). `PGMonitor` no longer exists. The comment is obsolete. No functional impact, but it references an architectural path that was never completed and is now irrelevant.
- **OK otherwise.**

---

### `ClusterSocketHook` (inner class)

**File:** `src/mgr/ClusterState.cc:198` (blame: `5d3c1856415f`)

#### Commit history

| SHA | Date | Subject |
|---|---|---|
| `5d3c1856415f` | 2019-07-09 | Created with `bool call(...)` |
| `9d772b8ea9e5` | 2019-09-06 | Changed to `int call(...)` |
| `adf1486e46cb` | 2019-09-19 | Changed `format` param to `Formatter*` |
| `07ad8df2dd74` | 2021-10-23 | Added `const bufferlist&` inbl param |
| `a54d0a90c06a` | 2020-01-17 | Namespace `bad_cmd_get` to `TOPNSPC::common::` |

#### Invariants

- **I1** (`5d3c1856415f`): `call()` delegates to `cluster_state->asok_command()` and appends result to `out`.
- **I2** (`9d772b8ea9e5`): `bad_cmd_get` exception maps to `r = -EINVAL`.
- **I3** (`adf1486e46cb`): Caller-provided `Formatter*` is passed through; no local Formatter created; no `f->flush()` call here (caller does it).

#### Current implementation critique (cc:198–215)

- **Line 199** (`9d772b8ea9e5`): `int call(...)` — correct return type.
- **Line 200** (`07ad8df2dd74`): `const bufferlist&` inbl accepted but unused — correct for a command that needs no input body.
- **Line 207** (`adf1486e46cb`): `r = cluster_state->asok_command(admin_command, cmdmap, f, outss)` — Formatter passed from infrastructure, not created locally. Note: `asok_command` returns `bool` cast to `int`. Since `bool` is `true` = 1 and the return convention for int call() is 0 = success, this is potentially mismatched.
- **DIVERGED — line 207**: `asok_command` was originally `bool` returning `true` always, then changed to `bool` still returning `true` always (see last line of `asok_command`). The `call()` method expects an `int` (0=success). Casting `bool true` → `int 1` is technically a non-zero return which in the tell interface would indicate an error. This is an artefact of the incomplete refactoring from `9d772b8ea9e5` (2019-09-06). The body of `asok_command` always returns `true` (line 381 in blame), meaning the `int call()` always returns `1`. Per the `9d772b8ea9e5` commit message, non-zero error codes are valid in the tell interface but `-ENOSYS` means hard failure; `1` is therefore treated as non-error by the asok dispatcher. Functional behaviour is unchanged, but the return value convention is ungrounded.
- **UNGROUNDED — line 208**: `out.append(outss)` appends the `outss` stringstream content. If the asok command writes to `f` (the Formatter) rather than `outss`, nothing appears in `out` unless `f` is flushed somewhere else. The caller (`AdminSocket`) owns the Formatter and flushes it. The `outss` path is only used for exception error strings. This is correct but not obvious.
- **Line 209** (`a54d0a90c06a`): `TOPNSPC::common::bad_cmd_get` — OK.

---

### `final_init`

**File:** `src/mgr/ClusterState.cc:217` · `src/mgr/ClusterState.h:155`

#### Commit history

| SHA | Date | Subject |
|---|---|---|
| `5d3c1856415f` | 2019-07-09 | Created; registered "dump_osd_network" with `register_command(name, cmddesc, hook, help)` (3-arg overload) |
| `1a7cdedb5601` | 2019-09-05 | Drop explicit prefix arg; use 2-arg `register_command(cmddesc, hook, help)` |
| `dd9f9e268b5562` | 2023-11-02 | Removed `shutdown()` (never called since 3363a10) |

#### Invariants

- **I1** (`5d3c1856415f`): Must be called exactly once after construction to register the asok hook.
- **I2** (`5d3c1856415f`): `ceph_assert(r == 0)` ensures registration succeeded.
- **I3** (`dd9f9e268b5562`): There is no corresponding `shutdown()` — asok commands are never explicitly unregistered. The mgr exits via SIGTERM/SIGINT without cleanup. This is documented in the commit fixing #63410.

#### Current implementation critique (cc:217–225)

```cpp
void ClusterState::final_init()
{
  AdminSocket *admin_socket = g_ceph_context->get_admin_socket();
  asok_hook = new ClusterSocketHook(this);
  int r = admin_socket->register_command(
    "dump_osd_network name=value,type=CephInt,req=false", asok_hook,
    "Dump osd heartbeat network ping times");
  ceph_assert(r == 0);
}
```

- Line 220: `asok_hook = new ClusterSocketHook(this)` — raw `new`; leaked on repeated calls to `final_init()` since there is no null guard.
- **UNGROUNDED — line 220**: `asok_hook` is never checked for null before overwriting. If `final_init()` is called twice, the first hook object is leaked and the second `register_command` will likely fail (duplicate registration). The `ceph_assert(r == 0)` would catch this at runtime, but there is no invariant check before the allocation. The original code (`5d3c1856415f`) had a matching `shutdown()` that deleted the hook, but that was removed by `dd9f9e268b5562`. The orphaned leak-on-double-call risk is ungrounded (there is no documented guarantee that `final_init()` is called exactly once).
- **OK** for the normal single-call path.

---

### `asok_command`

**File:** `src/mgr/ClusterState.cc:227` · `src/mgr/ClusterState.h:156`

#### Commit history (full)

| SHA | Date | Subject | Impact |
|---|---|---|---|
| `5d3c1856415f` | 2019-07-09 | Created | `bool` return; `std::string_view format`; local `Formatter*` created+deleted; value in microseconds raw; no threshold field; `network_ping_times` array; no stale filtering |
| `0d1bbd34e96e` | 2019-07-11 | Add mon_warn_on_slow_ping_ratio | Added ratio fallback when `mon_warn_on_slow_ping_time == 0`; added `threshold` field; changed outer section to object |
| `297a0e7b1de4` | 2019-07-12 | Add min/max tracking | Added `min[]`, `max[]` arrays to struct and output |
| `3f846d7c806b` | 2019-07-15 | Store last pingtime | Added `last` field; front guard changed from `pingtime==0` to `front_last==0` |
| `ea20d3522aaf` | 2019-07-18 | Add last_update to heartbeat info | Added `last_update` field; `ctime_r` formatting; `stale` bool in output |
| `048f8096265d` | 2019-07-22 | Add osd_mon_heartbeat_stat_stale | Added staleness filtering with `osd_mon_heartbeat_stat_stale` config |
| `9d02e5d39d7b` | 2019-08-05 | Convert output to milliseconds | Changed `dump_unsigned` to `dump_format_unquoted(fixed_u_to_string(...,3))` |
| `5f83a6158b29` | 2019-09-04 | To milliseconds for config value | Config value * 1000 (ms→µs); user input * 1000 (ms→µs); threshold output / 1000 |
| `6d2e4cb109ca` | 2019-09-06 | Allow fractional milliseconds | Changed `get_val<uint64_t>` to `get_val<double>` for `mon_warn_on_slow_ping_time` |
| `9d772b8ea9e5` | 2019-09-06 | return int from hook call() | `call()` changed; `asok_command` still returns `bool` |
| `adf1486e46cb` | 2019-09-19 | pass Formatter from infrastructure | Parameter changed to `Formatter*`; local `Formatter` creation+deletion removed; `f->flush(ss); delete f` removed |
| `a4c07734bf9e` | 2019-09-13 | pass ostream for error output | Added `std::ostream& errss` param (used in `call()` not in `asok_command` body) |
| `07ad8df2dd74` | 2021-10-23 | pass inbl to sync call() | No change to `asok_command` body |
| `5d5b0f96df39` | 2020-01-31 | drop cct from cmd_getval() | `cmd_getval(g_ceph_context, ...)` → `cmd_getval(...)` |
| `a54d0a90c06a` | 2020-01-17 | TOPNSPC namespace | `cmd_getval` → `TOPNSPC::common::cmd_getval`; `bad_cmd_get` qualified |

#### Invariants

- **I1** (`5d3c1856415f`): Only command handled is `"dump_osd_network"`; all others hit `ceph_abort_msg("broken asok registration")`.
- **I2** (`adf1486e46cb`): Formatter is injected; function must not flush or delete it.
- **I3** (`5f83a6158b29`): Internal `value` threshold is in **microseconds** throughout sorting/comparison. The `threshold` field in output is in **milliseconds** (`value / 1000`). User input and config values are converted ms→µs at parse time.
- **I4** (`048f8096265d`): Entries with `last_update == 0` (never updated) must be skipped before building the sorted set.
- **I5** (`048f8096265d`): Entries older than `osd_mon_heartbeat_stat_stale` seconds must be skipped.
- **I6** (`3f846d7c806b`): Front-network entries are skipped when `j.second.front_last == 0` (no front network data).
- **I7** (`ea20d3522aaf`): Each output entry must include `"last update"` (human-readable `ctime_r`) and `"stale"` bool.

#### Error conditions

- Negative `value` clamped to 0 at line 250–251 (established `5d3c1856415f`).

#### Current implementation critique (cc:227–382)

- **Line 233** (`5d3c1856415f`): `std::lock_guard l(lock)` — correct; `pg_map.osd_stat` must be read under lock.
- **Line 240** (`6d2e4cb109ca`): `get_val<double>("mon_warn_on_slow_ping_time") * 1000` — correct type after `6d2e4cb109ca`.
- **Line 241–245** (`0d1bbd34e96e`): Ratio fallback: `osd_heartbeat_grace` (seconds) × 1000000 × ratio → µs — correct.
- **Lines 246–248** (`5f83a6158b29`): `else { value *= 1000; }` — user input ms→µs conversion.
- **Lines 250–251**: Negative clamp to 0.
- **Lines 285–287** (`048f8096265d`): `last_update == 0` skip — invariant I4.
- **Lines 288–293** (`048f8096265d`): Stale check with `osd_mon_heartbeat_stat_stale` — invariant I5.
- **Line 315–316** (`3f846d7c806b`): `front_last == 0` guard — invariant I6.
- **Lines 341** (`5f83a6158b29`): `f->dump_int("threshold", value / 1000)` — outputs ms, correct.
- **Line 344** (`5d3c1856415f`): `ceph_assert(!value || sitem.pingtime >= value)` — invariant: all items in `sorted` at/above threshold (unless value==0 means "all").
- **Lines 348–354** (`ea20d3522aaf`): `ctime_r` + `osd_heartbeat_stale` check — invariant I7.
- **UNGROUNDED — lines 341**: `f->dump_int("threshold", value / 1000)` is emitted before the `"entries"` array, but `f` has not been flushed anywhere and the output is a well-formed JSON object. However, from `adf1486e46cb` the formatter is passed in by the caller who is responsible for flushing; this is correct but surprising given the old code explicitly called `f->flush(ss); delete f`.
- **OVERCAUTIOUS — line 379**: `ceph_abort_msg("broken asok registration")` — the only registered command is `"dump_osd_network"`. The else branch would only be reached if the asok registration was somehow wrong. The assertion is correct but cannot happen at runtime unless `final_init()` or AdminSocket has a bug. Harmless.
- **OK otherwise.**

---

### `have_fsmap`

**File:** `src/mgr/ClusterState.h:72`

#### Commit history

| SHA | Subject |
|---|---|
| `1113eb123b14` | Created: checks `fsmap.get_epoch() > 0` |
| `6646b35ac76d` | Added `const` qualifier to method |
| `948635a8b213` | s/Mutex::Locker/std::lock_guard/ |

#### Invariants

- **I1** (`1113eb123b14`): An FSMap with epoch == 0 is considered uninitialised; `have_fsmap()` returns false until the mgr receives a real FSMap.

#### Current implementation critique (h:72–75)

```cpp
bool have_fsmap() const {
  std::lock_guard l(lock);
  return fsmap.get_epoch() > 0;
}
```

- **OK.** Lock held, const-correct, intent satisfied.

---

### `with_servicemap`

**File:** `src/mgr/ClusterState.h:78`

#### Commit history

| SHA | Subject |
|---|---|
| `97cfc3cb694e` | Created with `void` return |
| `948635a8b213` | s/Mutex::Locker/std::lock_guard/ |
| `9c652fb305a3` | Changed to `auto` return; `return std::forward<Callback>...` |

#### Invariants

- **I1** (`97cfc3cb694e`): `servicemap` access serialised under `lock`.
- **I2** (`9c652fb305a3`): Return value of callback is forwarded.

#### Current implementation critique (h:78–82)

```cpp
auto with_servicemap(Callback&& cb, Args&&...args) const
{
  std::lock_guard l(lock);
  return std::forward<Callback>(cb)(servicemap, std::forward<Args>(args)...);
}
```

- **OK.** All invariants satisfied.

---

### `with_fsmap`

**File:** `src/mgr/ClusterState.h:85`

#### Commit history

| SHA | Subject |
|---|---|
| `ac30e6cee2b2` | Created; indented incorrectly, lock inside body |
| `fa147e3a591a` | Fixed indentation |
| `948635a8b213` | s/Mutex::Locker/std::lock_guard/ |
| `9c652fb305a3` | Changed to `auto` return |

#### Current implementation critique (h:85–89)

- **OK.** Lock held, `const`-correct, return forwarded.

---

### `with_mgrmap`

**File:** `src/mgr/ClusterState.h:92`

#### Commit history

| SHA | Subject |
|---|---|
| `6c10417f7ed3` | Created |
| `948635a8b213` | s/Mutex::Locker/std::lock_guard/ |
| `9c652fb305a3` | Changed to `auto` return |

#### Current implementation critique (h:92–96)

- **OK.** Lock held, `const`-correct, return forwarded.

---

### `with_pgmap`

**File:** `src/mgr/ClusterState.h:99`

#### Commit history

| SHA | Subject |
|---|---|
| `fa147e3a591a` | Created with `void` return |
| `6646b35ac76d` | Added `auto` return + trailing decltype |
| `948635a8b213` | s/Mutex::Locker/std::lock_guard/ |

#### Current implementation critique (h:99–104)

- **OK.** `const` qualifier, lock held, return forwarded.

---

### `with_mutable_pgmap`

**File:** `src/mgr/ClusterState.h:107`

#### Commit history

| SHA | Subject |
|---|---|
| `86f0b811882d` | Created for purged_snaps map |
| `948635a8b213` | s/Mutex::Locker/std::lock_guard/ |

#### Invariants

- **I1** (`86f0b811882d`): Non-const variant; lock still required for consistent mutation.

#### Current implementation critique (h:107–112)

```cpp
auto with_mutable_pgmap(Callback&& cb, Args&&...args) ->
  decltype(cb(pg_map, std::forward<Args>(args)...))
{
  std::lock_guard l(lock);
  return std::forward<Callback>(cb)(pg_map, std::forward<Args>(args)...);
}
```

- **UNGROUNDED**: `with_mutable_pgmap` allows callback to mutate `pg_map` directly — bypassing the `pending_inc` accumulation pattern established by `d6d1db62edeb`. The commit `86f0b811882d` provided no explanation beyond "add purged_snaps map". Direct mutation of `pg_map` outside the `Incremental` path is potentially unsafe if `apply_incremental` is called concurrently (though the lock prevents this). The fact that a mutable variant exists at all is an architectural tension with the `pending_inc` pattern.

---

### `with_monmap`

**File:** `src/mgr/ClusterState.h:115`

#### Commit history

| SHA | Subject |
|---|---|
| `ac30e6cee2b2` | Created; incorrect indentation; only forwarded first arg |
| `45b33934e878` | Fixed to `std::forward<Args>(args)...` |
| `ab23c506964` | `assert` → `ceph_assert` |
| `948635a8b213` | s/Mutex::Locker/std::lock_guard/ |
| `9c652fb305a3` | Changed to `auto` return |

#### Invariants

- **I1** (`ab23c506964`): `ceph_assert(monc != nullptr)` — must not be called before `monc` is valid.

#### Current implementation critique (h:115–120)

```cpp
auto with_monmap(Args &&... args) const
{
  std::lock_guard l(lock);
  ceph_assert(monc != nullptr);
  return monc->with_monmap(std::forward<Args>(args)...);
}
```

- **OVERCAUTIOUS — line 118**: `ceph_assert(monc != nullptr)`. `monc` is set in the constructor and there is no API to null it after construction. The check cannot fail in practice. It was added by `ab23c506964` as a defensive measure when `assert` was upgraded to `ceph_assert`. Harmless but redundant.
- **OK** otherwise.

---

### `with_osdmap`

**File:** `src/mgr/ClusterState.h:123`

#### Commit history

| SHA | Subject |
|---|---|
| `ac30e6cee2b2` | Created; locked `ClusterState::lock` around `objecter->with_osdmap` |
| `ea46778e3681` | **Removed** `ClusterState::lock` from `with_osdmap`; only Objecter's own lock is held |
| `45b33934e878` | Fixed forwarding |
| `ab23c506964` | `assert` → `ceph_assert(objecter != nullptr)` |
| `6646b35ac76d` | Added `auto` return + decltype |

#### Invariants

- **I1** (`ea46778e3681`): `with_osdmap` does **not** acquire `ClusterState::lock`. It relies solely on Objecter's internal reader lock. This prevents deadlock when `with_osdmap` is called while `ClusterState::lock` is already held (e.g., inside `ingest_pgstats`).
- **I2** (`ab23c506964`): `ceph_assert(objecter != nullptr)`.

#### Current implementation critique (h:123–128)

```cpp
auto with_osdmap(Args &&... args) const ->
  decltype(objecter->with_osdmap(std::forward<Args>(args)...))
{
  ceph_assert(objecter != nullptr);
  return objecter->with_osdmap(std::forward<Args>(args)...);
}
```

- **Line 126**: No `ClusterState::lock` — invariant I1 satisfied. This is a deliberate choice since `ea46778e3681` specifically removed the lock here.
- **OVERCAUTIOUS — line 126**: Same reasoning as `with_monmap`; `objecter` cannot be null in normal operation.
- **OK** otherwise.

---

### `with_osdmap_and_pgmap`

**File:** `src/mgr/ClusterState.h:132`

#### Commit history

| SHA | Subject |
|---|---|
| `60876ccce4e9` | Created (tracker #36766); "Several call sites need to lock both" |

#### Invariants

- **I1** (`60876ccce4e9`): Acquires `ClusterState::lock` before calling `objecter->with_osdmap(..., pg_map, ...)`. This ensures OSDMap and PGMap are read under a consistent lock epoch.
- **I2** (`60876ccce4e9`): The signature passes `pg_map` as the second argument to the callback, after `osdmap`.

#### Current implementation critique (h:132–139)

```cpp
auto with_osdmap_and_pgmap(Callback&& cb, Args&& ...args) const {
  ceph_assert(objecter != nullptr);
  std::lock_guard l(lock);
  return objecter->with_osdmap(
    std::forward<Callback>(cb),
    pg_map,
    std::forward<Args>(args)...);
}
```

- Acquires `lock` before entering Objecter's `with_osdmap` — invariants I1 and I2 satisfied.
- **UNGROUNDED**: The locking order here is `ClusterState::lock` then Objecter's rwlock. `with_osdmap` (alone, without pgmap) does NOT hold `ClusterState::lock`. Therefore callers must not call `with_osdmap_and_pgmap` while holding any lock that could cause a cycle with Objecter's lock. This ordering constraint is not documented anywhere in the code.
- **OK** functionally.

---

### `with_health`

**File:** `src/mgr/ClusterState.h:142`

#### Commit history

| SHA | Subject |
|---|---|
| `da362675da51` | Created; `void` return; `std::lock_guard l(lock)` (tracker #24995) |
| `9c652fb305a3` | Changed to `auto` return |

#### Invariants

- **I1** (`da362675da51`): `health_json` access must be serialised under `lock` (tracker #24995 — concurrent reader/writer race).

#### Current implementation critique (h:142–146)

- **OK.** Lock held, `const`-correct, return forwarded.

---

### `with_mon_status`

**File:** `src/mgr/ClusterState.h:149`

#### Commit history

| SHA | Subject |
|---|---|
| `da362675da51` | Created; `void` return; lock (tracker #24995) |
| `9c652fb305a3` | Changed to `auto` return |

#### Invariants

- Same as `with_health` — invariant I1 (`da362675da51`): lock required.

#### Current implementation critique (h:149–153)

- **OK.** Lock held, `const`-correct, return forwarded.

---

### `__anon6548a3890102` (operator< inside `mgr_ping_time_t`)

**File:** `src/mgr/ClusterState.cc:82` (ctags internal name for the unnamed struct's member)

This is the `operator<` on the local struct `mgr_ping_time_t` defined inside `asok_command`. Ctags exposed it as a separate function entry.

#### Commit history

| SHA | Subject |
|---|---|
| `5d3c1856415f` | Created; comparison by `pingtime`, then `from`, then `to`, then `back` |

#### Invariants

- **I1** (`5d3c1856415f`): Sort key is maximum of 1/5/15-min ping times, ascending. `std::set` iterates ascending; caller iterates `boost::adaptors::reverse(sorted)` to get descending (highest first).

#### Current implementation critique (cc:264–279)

The struct sorts by `pingtime ASC`, then `from ASC`, then `to ASC`, then `back ASC`. The caller uses `boost::adaptors::reverse` to iterate descending. The `ceph_assert(!value || sitem.pingtime >= value)` at line 344 verifies the invariant at iteration time.

- **OK.** Intent clear and implementation matches.

---

### `operator<` (ctags entry: `src/mgr/ClusterState.cc:264`)

This is the same `operator<` as `__anon6548a3890102` above — ctags produces two entries. See above.

---

## Cross-cutting Findings

### DIVERGED findings

1. **`update_delta_stats` missing lock assertion** (line 139–155 of cc): `notify_osdmap` has `assert(ceph_mutex_is_locked(lock))` at line 159 (established by `03a761c980a1`). `update_delta_stats` accesses the same `pg_map` and `pending_inc` under the same lock requirement but has no equivalent assertion. A caller that forgets to lock before calling `update_delta_stats` would silently corrupt state. Contradicting commit: `03a761c980a1` (added assertion to `notify_osdmap` but not `update_delta_stats`).

2. **`ClusterSocketHook::call()` returns `bool`-cast-to-`int`** (line 207 of cc): `asok_command` returns `bool` (always `true`); `call()` expects `int` (0=success convention). The implicit cast `bool true → int 1` means `call()` always returns 1, which the asok dispatcher treats as non-error per `9d772b8ea9e5`. The `asok_command` signature was never updated from `bool` to `int` when `call()` was changed (`9d772b8ea9e5`, 2019-09-06). Contradicting commit: `9d772b8ea9e5`.

### UNGROUNDED findings

1. **`ingest_pgstats` comment vs implementation** (cc:100–101): Comment says "according to last OSDMap update" but check is against `existing_pools` (a cached snapshot). The decoupling is deliberate (`6afca3beb2a8`) but undocumented at the point of the comment.

2. **`with_mutable_pgmap`** (h:107–112): Permits direct `pg_map` mutation bypassing the `pending_inc` accumulation pattern. No documented preconditions on when this is safe.

3. **`with_osdmap_and_pgmap` lock ordering** (h:132–139): Locking order `ClusterState::lock` → Objecter::rwlock is undocumented. There is no comment explaining why this order is safe and does not conflict with callers that hold Objecter::rwlock independently.

4. **`final_init()` double-call risk** (cc:220): `asok_hook = new ClusterSocketHook(this)` with no null-guard; second call would leak the first hook. No documentation that `final_init()` must be called exactly once.

5. **Stale TODO comment** (cc:190–192): References `PGMonitor` which has been removed from the codebase. The comment is from `afa7078763ef` (2016-09-22) and has never been resolved or removed.

### OVERCAUTIOUS findings

1. **`with_monmap` — `ceph_assert(monc != nullptr)`** (h:118): `monc` is set in the constructor and never nulled. Cannot fail at runtime.

2. **`with_osdmap` — `ceph_assert(objecter != nullptr)`** (h:126): Same reasoning. Cannot fail at runtime.

3. **`asok_command` else branch `ceph_abort_msg`** (cc:379): Only one command is registered; the else branch is structurally unreachable as long as `final_init()` is correct.

---

## Commit Coverage Matrix

All 71 commits accounted for. Commits with function impact: 47. Cosmetic/refactor-only commits (indent, namespace, lock naming, header ordering): 24. All commits touching substantive function logic have been read and reflected in the sections above.

| SHA (short) | Functions touched | Reflected in artefact |
|---|---|---|
| 0bac6af3 | update_delta_stats, notify_osdmap | ✓ |
| 4adaf64d | (none) | ✓ |
| 85d82faa | (none) | ✓ |
| c8c1019d | (none) | ✓ |
| f1bac418 | (none) | ✓ |
| 3ab70dd3 | (none — JSONFormatter include move) | ✓ |
| 70b41ea1 | ingest_pgstats | ✓ |
| 327b3de5 | (none — header order) | ✓ |
| dd9f9e26 | final_init | ✓ |
| 07ad8df2 | asok_command | ✓ |
| c63ecb60 | (none — using decls) | ✓ |
| 9c652fb3 | (none — return type) | ✓ |
| 493ec9d3 | ingest_pgstats | ✓ |
| da362675 | set_service_map, load_digest, with_health, with_mon_status | ✓ |
| a54d0a90 | asok_command | ✓ |
| 5d5b0f96 | asok_command | ✓ |
| adf1486e | asok_command | ✓ |
| a4c07734 | (asok call signature) | ✓ |
| 9d772b8e | (call return type) | ✓ |
| 1a7cdedb | final_init | ✓ |
| 6d2e4cb1 | asok_command | ✓ |
| 5f83a615 | asok_command | ✓ |
| 9d02e5d3 | asok_command | ✓ |
| 048f8096 | asok_command | ✓ |
| 0d1bbd34 | asok_command | ✓ |
| 297a0e7b | asok_command | ✓ |
| 3f846d7c | asok_command | ✓ |
| 5d3c1856 | notify_osdmap, ClusterState ctor | ✓ |
| ea20d352 | asok_command | ✓ |
| c93dc884 | ClusterState ctor | ✓ |
| a075639c | load_digest/ingest_pgstats (ref_t) | ✓ |
| 63df4060 | update_delta_stats, ingest_pgstats | ✓ |
| 03a761c9 | update_delta_stats | ✓ |
| 60876ccc | (with_osdmap_and_pgmap) | ✓ |
| 948635a8 | update_delta_stats, load_digest, ctor | ✓ |
| 9e906733 | ingest_pgstats, notify_osdmap | ✓ |
| ab23c506 | (ceph_assert) | ✓ |
| 86f0b811 | (with_mutable_pgmap) | ✓ |
| 83b9ef73 | ingest_pgstats | ✓ |
| 1dcab1c7 | ClusterState ctor | ✓ |
| a7612d33 | ingest_pgstats | ✓ |
| ae688fc4 | ingest_pgstats | ✓ |
| 97cfc3cb | set_mgr_map | ✓ |
| 6c10417f | set_fsmap | ✓ |
| 19810df0 | (pgservice — removed) | ✓ |
| c2258991 | update_delta_stats, notify_osdmap | ✓ |
| aad1afcb | update_delta_stats, notify_osdmap | ✓ |
| 6afca3be | ingest_pgstats, notify_osdmap | ✓ |
| d6d1db62 | ingest_pgstats, load_digest, notify_osdmap | ✓ |
| 0612b716 | notify_osdmap | ✓ |
| 681d37c0 | notify_osdmap | ✓ |
| 74752505 | notify_osdmap | ✓ |
| 27bd39cd | notify_osdmap | ✓ |
| b73e4374 | notify_osdmap | ✓ |
| 759c7d0a | notify_osdmap | ✓ |
| ff1258e7 | notify_osdmap | ✓ |
| 983fe8ec | ingest_pgstats | ✓ |
| 3da07ea0 | ingest_pgstats | ✓ |
| 6646b35a | (constness) | ✓ |
| c14b913b | (with_osdmap decltype) | ✓ |
| 3f514bda | (clean nonused decl) | ✓ |
| 1113eb12 | (have_fsmap cond) | ✓ |
| 454da5e7 | notify_osdmap | ✓ |
| 3893432646 | notify_osdmap | ✓ |
| b9182564 | (dout_context) | ✓ |
| 45b33934 | (with_*map fixup) | ✓ |
| afa70787 | notify_osdmap | ✓ |
| ea46778e | (with_osdmap lock removal) | ✓ |
| fa147e3a | set_fsmap, ingest_pgstats | ✓ |
| ac30e6ce | all initial creation | ✓ |

---

*End of ClusterState-intent.md*
