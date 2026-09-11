# Object History: ClusterState

**File:** `src/mgr/ClusterState.cc` / `src/mgr/ClusterState.h`
**Component:** `ceph-mgr` — cluster-scope state (PGMap, FSMap, MgrMap, ServiceMap, health/mon-status JSON)
**Curator branch:** `agent/4` at worktree `/home/szuraski/ceph-agent-4`
**Curation date:** 2025-09-09
**Git horizon:** Earliest visible commit: `ac30e6cee2b` (2016-06-30, John Spray "mgr: create ceph-mgr service").
**Total non-merge commits touching file (all refs):** 176 visible; 5 non-merge on `main` branch HEAD, plus rich deep history on all refs.

---

## Commit Catalogue

| SHA (short) | Date | Author | Subject | Fix-signal |
|---|---|---|---|---|
| `0bac6af3c18` | 2026-05-19 | Nitzan Mordechai | mgr/ClusterState: remove debug 30 memory spike | **YES** — Fixes tracker#64082 |
| `c8c1019d196` | 2025-10-02 | Edwin Rodriguez | Add missing blank line after comment block | no |
| `f1bac41828d` | 2025-10-01 | Edwin Rodriguez | Update indent settings cc | **YES** — Fixes tracker#72587 |
| `3ab70dd3e11` | 2024-10-16 | Max Kellermann | common/Formatter: move {JSON,Table,XML}Formatter to separate files | no |
| `70b41ea1ee8` | 2025-06-06 | Kamoltat Sirivadhna | src/mgr/ClusterState.cc: micro improve ingest_pgstats | no (optimization) |
| `a21b250f029` | 2025-02-27 | Adam King (merge) | (merge — introduced file to this repo's history as "new file" baseline) | no |
| `9e906733fe0` | 2018-07-29 | Sage Weil | mgr/ClusterState: discard pg updates for pgs >= pg_num | **YES** — filter |
| `ae688fc4d72` | 2017-07-11 | Sage Weil | mgr/ClusterState: do not mangle PGMap outside of Incremental | **YES** — Fixes tracker#20208 |
| `6afca3beb2a` | 2017-05-23 | Sage Weil | mgr/ClusterState: make pg stat filtering less fragile | **YES** — robustness |
| `aad1afcb96d` | 2017-05-30 | Kefu Chai | mgr: reset pending_inc after applying it | **YES** — correctness fix |
| `06154ebbd07` | 2017-08-10 | Sage Weil | mgr/ClusterState: record osd_stat for out osds too | **YES** — behavioral fix |
| `681d37c0555` | 2017-05-19 | Sage Weil | mgr/ClusterState: apply latest osdmap to pgmap | **YES** — correctness |
| `c2258991393` | 2017-06-07 | Sage Weil | mgr/ClusterState: dump pgmap and inc at dout 30 | no (later reversed) |
| `97cfc3cb694` | 2017-06-26 | Sage Weil | mgr: allow/track service registrations | no (feature) |
| `6c10417f7ed` | 2017-06-27 | Sage Weil | mgr: include MgrMap in ClusterState | no (feature) |
| `fa147e3a591` | 2016-07-31 | John Spray | mgr: handle PGStats with a PGMap | no (founding) |
| `ac30e6cee2b` | 2016-06-30 | John Spray | mgr: create ceph-mgr service | no (founding) |

---

## Method: `ClusterState::ClusterState` (constructor)

**Intent:** Initialize the `ClusterState` object with a `MonClient`, `Objecter`, and initial `MgrMap`; null-initialize the admin-socket hook pointer.

**First introduced:** `ac30e6cee2b` (2016-06-30, John Spray) — original ceph-mgr creation. MgrMap parameter added in `6c10417f7ed` (2017-06-27, Sage Weil) to carry the manager map at construction time.

**Commit history (affecting this method):**

| SHA | Date | Subject |
|---|---|---|
| `ac30e6cee2b` | 2016-06-30 | mgr: create ceph-mgr service (founded) |
| `6c10417f7ed` | 2017-06-27 | mgr: include MgrMap in ClusterState (added mgrmap param) |
| `948635a8b21` | 2018-10-16 | mgr: Mutex::Locker -> std::lock_guard |

**Notable diffs:** None (no fix-signal commits directly to constructor body).

**Known defects:** None.

**divergence_flag:** `false` — constructor body is trivial; no functional divergence from apparent intent.

---

## Method: `ClusterState::set_objecter`

**Intent:** Thread-safely replace the `Objecter` pointer (used during mgr standby→active transition when a new Objecter is wired up).

**First introduced:** `ac30e6cee2b` (2016-06-30, John Spray).

**Commit history (affecting this method):**

| SHA | Date | Subject |
|---|---|---|
| `ac30e6cee2b` | 2016-06-30 | mgr: create ceph-mgr service (founded) |
| `948635a8b21` | 2018-10-16 | mgr: Mutex::Locker -> std::lock_guard |

**Notable diffs:** None.

**Known defects:** None.

**divergence_flag:** `false`

---

## Method: `ClusterState::set_fsmap`

**Intent:** Thread-safely update the cached `FSMap` when the monitor sends a new one.

**First introduced:** `ac30e6cee2b` (2016-06-30, John Spray).

**Commit history (affecting this method):**

| SHA | Date | Subject |
|---|---|---|
| `ac30e6cee2b` | 2016-06-30 | mgr: create ceph-mgr service (founded) |
| `948635a8b21` | 2018-10-16 | mgr: Mutex::Locker -> std::lock_guard |

**Notable diffs:** None.

**Known defects:** None.

**divergence_flag:** `false`

---

## Method: `ClusterState::set_mgr_map`

**Intent:** Thread-safely replace the cached `MgrMap` when a new map is received from the monitor.

**First introduced:** `6c10417f7ed` (2017-06-27, Sage Weil) — when MgrMap support was added to ClusterState.

**Commit history (affecting this method):**

| SHA | Date | Subject |
|---|---|---|
| `6c10417f7ed` | 2017-06-27 | mgr: include MgrMap in ClusterState (founded) |
| `948635a8b21` | 2018-10-16 | mgr: Mutex::Locker -> std::lock_guard |

**Notable diffs:** None.

**Known defects:** None.

**divergence_flag:** `false`

---

## Method: `ClusterState::set_service_map`

**Intent:** Thread-safely replace the cached `ServiceMap` when the monitor delivers a new one.

**First introduced:** `97cfc3cb694` (2017-06-26, Sage Weil) — when service registrations were added to ClusterState.

**Commit history (affecting this method):**

| SHA | Date | Subject |
|---|---|---|
| `97cfc3cb694` | 2017-06-26 | mgr: allow/track service registrations (founded) |
| `948635a8b21` | 2018-10-16 | mgr: Mutex::Locker -> std::lock_guard |

**Notable diffs:** None.

**Known defects:** None.

**divergence_flag:** `false`

---

## Method: `ClusterState::load_digest`

**Intent:** Atomically ingest the health JSON and mon-status JSON blobs received in an `MMgrDigest` message from the monitor.

**First introduced:** `ac30e6cee2b` (2016-06-30, John Spray) — originally also consumed a `pg_summary_json` field. That field was removed in `fa147e3a591` (2016-07-31) when PGStats handling was moved to a dedicated path.

**Commit history (affecting this method):**

| SHA | Date | Subject |
|---|---|---|
| `ac30e6cee2b` | 2016-06-30 | mgr: create ceph-mgr service (founded) |
| `fa147e3a591` | 2016-07-31 | mgr: handle PGStats with a PGMap (removed pg_summary_json from digest path) |
| `948635a8b21` | 2018-10-16 | mgr: Mutex::Locker -> std::lock_guard |

**Notable diffs:** None (no fix-keyword commits specifically targeting this method body).

**Known defects:** None.

**divergence_flag:** `false`

---

## Method: `ClusterState::ingest_pgstats`

**Intent:** Receive per-OSD PG stat reports (`MPGStats`), filter out stale or out-of-range stats (wrong pool, pg beyond pg_num, older version pair), and accumulate valid updates into `pending_inc` for deferred application to `pg_map`.

**First introduced:** `fa147e3a591` (2016-07-31, John Spray) — introduced full PGStats handling inside the mgr (replacing the old pg_summary_json approach).

**Commit history (affecting this method):**

| SHA | Date | Subject | Fix-signal |
|---|---|---|---|
| `fa147e3a591` | 2016-07-31 | mgr: handle PGStats with a PGMap (founded) | — |
| `d6d1db62ede` | 2017-05-23 | mgr: apply PGMap incremental at same interval as reports | no |
| `6afca3beb2a` | 2017-05-23 | mgr/ClusterState: make pg stat filtering less fragile | **YES** |
| `983fe8ec889` | 2017-05-20 | mon,mgr: std::move(osd_stat) when possible | no |
| `06154ebbd07` | 2017-08-10 | mgr/ClusterState: record osd_stat for out osds too | **YES** |
| `ae688fc4d72` | 2017-07-11 | mgr/ClusterState: do not mangle PGMap outside of Incremental | **YES** |
| `9e906733fe0` | 2018-07-29 | mgr/ClusterState: discard pg updates for pgs >= pg_num | **YES** |
| `948635a8b21` | 2018-10-16 | mgr: Mutex::Locker -> std::lock_guard | no |
| `70b41ea1ee8` | 2025-06-06 | src/mgr/ClusterState.cc: micro improve ingest_pgstats | no (optimization) |

**Notable diffs:**

### `6afca3beb2a` — make pg stat filtering less fragile (2017-05-23)

```diff
-    if (pg_map.pg_stat.count(pgid) == 0) {
-      // "but DNE in pg_map; pool was probably deleted."
+    if (existing_pools.count(pgid.pool()) == 0) {
+      // "but pool not in existing_pools"
```

Changed the "unknown PG" filter to check whether the *pool* exists in `existing_pools` (a separately-maintained map) rather than whether the PG already has an entry in `pg_map.pg_stat`. This decoupled the filter from PGMap state drift caused by unrelated bugs.

### `ae688fc4d72` — do not mangle PGMap outside of Incremental (2017-07-11, Fixes tracker#20208)

```diff
-    if (pg_map.pg_stat[pgid].get_version_pair() > pg_stats.get_version_pair()) {
+    const auto q = pg_map.pg_stat.find(pgid);
+    if (q != pg_map.pg_stat.end() &&
+        q->second.get_version_pair() > pg_stats.get_version_pair()) {
```

Stopped using `operator[]` on `pg_map.pg_stat` (which would silently default-insert a new entry for unknown PGs, mutating `pg_map` outside an `Incremental`), switching to `find()`.

### `9e906733fe0` — discard pg updates for pgs >= pg_num (2018-07-29)

```diff
+    if (pgid.ps() >= r->second) {
+      dout(15) << ... << " but > pg_num " << r->second << dendl;
+      continue;
+    }
// and in notify_osdmap:
-    existing_pools.insert(p.first);
+    existing_pools[p.first] = p.second.get_pg_num();
```

Added a second filter layer: after confirming the pool exists, discard stats for a PG whose placement-seed exceeds the current `pg_num`. Changed `existing_pools` from `set<int64_t>` to `map<int64_t, unsigned>` to record `pg_num` per pool.

### `70b41ea1ee8` — micro improve ingest_pgstats (2025-06-06)

```diff
+  const auto existing_pools_end_it = existing_pools.end();
+  const auto pg_map_pg_stat_end_it = pg_map.pg_stat.end();
-    pending_inc.pg_stat_updates[pgid] = pg_stats;
+    pending_inc.pg_stat_updates.insert_or_assign(pgid, pg_stats);
```

Cached end() iterators outside the hot loop; replaced `operator[]` assignment with `insert_or_assign` to avoid default-construction overhead for new PG entries.

**Known defects:** None (no TODO/FIXME/HACK in this method body).

**divergence_flag:** `false` — each change traces to a concrete bug or performance goal.

---

## Method: `ClusterState::update_delta_stats`

**Intent:** Flush `pending_inc` into `pg_map` by calling `apply_incremental`, then reset `pending_inc` to empty. Dumps the incremental at `dout(30)` only when non-empty (after 2026 fix).

**First introduced:** `d6d1db62ede` (2017-05-23, Sage Weil "mgr: apply PGMap incremental at same interval as reports").

**Commit history (affecting this method):**

| SHA | Date | Subject | Fix-signal |
|---|---|---|---|
| `d6d1db62ede` | 2017-05-23 | mgr: apply PGMap incremental at same interval as reports (founded) | no |
| `aad1afcb96d` | 2017-05-30 | mgr: reset pending_inc after applying it | **YES** |
| `c2258991393` | 2017-06-07 | mgr/ClusterState: dump pgmap and inc at dout 30 | no |
| `3ab70dd3e11` | 2024-10-16 | common/Formatter: move JSONFormatter to separate file | no |
| `0bac6af3c18` | 2026-05-19 | mgr/ClusterState: remove debug 30 memory spike | **YES** |

**Notable diffs:**

### `aad1afcb96d` — reset pending_inc after applying it (2017-05-30)

```diff
+  pending_inc = PGMap::Incremental();
```

Without this reset, `apply_incremental` could be called again on an already-applied `pending_inc`, causing data corruption because `apply_incremental` is not idempotent.

### `0bac6af3c18` — remove debug 30 memory spike (2026-05-19, Fixes tracker#64082)

```diff
-  dout(30) << " pg_map before:\n";
-  JSONFormatter jf(true);
-  jf.dump_object("pg_map", pg_map);
-  jf.flush(*_dout);
-  *_dout << dendl;
-  dout(30) << " incremental:\n";
+  if (!pending_inc.empty()) {
+    dout(30) << " incremental:\n";
     JSONFormatter jf(true);
     jf.dump_object("pending_inc", pending_inc);
...
+  }
```

The full `pg_map` dump (potentially multi-MB on a large cluster) at `dout(30)` was flooding the log queue on every tick. The fix retains the `pending_inc` dump (far smaller) but only when the incremental is non-empty, preventing log queue memory spikes.

**Known defects:** None.

**divergence_flag:** `false`

---

## Method: `ClusterState::notify_osdmap`

**Intent:** When a new OSDMap arrives, synchronize `pg_map` with the new OSD layout via `PGMapUpdater::check_osd_map` and `check_down_pgs`, rebuild the `existing_pools` filter map from current pool list, flush and reset `pending_inc`.

**First introduced:** `681d37c0555` (2017-05-19, Sage Weil).

**Commit history (affecting this method):**

| SHA | Date | Subject | Fix-signal |
|---|---|---|---|
| `681d37c0555` | 2017-05-19 | mgr/ClusterState: apply latest osdmap to pgmap (founded) | **YES** |
| `6afca3beb2a` | 2017-05-23 | mgr/ClusterState: make pg stat filtering less fragile | **YES** |
| `aad1afcb96d` | 2017-05-30 | mgr: reset pending_inc after applying it | **YES** |
| `c2258991393` | 2017-06-07 | mgr/ClusterState: dump pgmap and inc at dout 30 | no |
| `9e906733fe0` | 2018-07-29 | mgr/ClusterState: discard pg updates for pgs >= pg_num | **YES** |
| `948635a8b21` | 2018-10-16 | mgr: Mutex::Locker -> std::lock_guard | no |
| `3ab70dd3e11` | 2024-10-16 | common/Formatter: move JSONFormatter to separate file | no |
| `0bac6af3c18` | 2026-05-19 | mgr/ClusterState: remove debug 30 memory spike | **YES** |

**Notable diffs:**

### `681d37c0555` — apply latest osdmap to pgmap (2017-05-19)
Introduced the method. Ensures that when the OSDMap changes (pools deleted, OSDs going down), `pg_map` is cleaned up in concert — zeroing stats for gone OSDs and clearing deleted pools' PG entries.

### `6afca3beb2a` — make pg stat filtering less fragile (2017-05-23)
```diff
+  existing_pools.clear();
+  for (auto& p : osd_map.get_pools()) {
+    existing_pools.insert(p.first);
+  }
```
`notify_osdmap` became the authoritative writer for `existing_pools`, keeping it in sync with each new OSDMap.

### `9e906733fe0` — discard pg updates for pgs >= pg_num (2018-07-29)
```diff
-    existing_pools.insert(p.first);
+    existing_pools[p.first] = p.second.get_pg_num();
```
Changed `existing_pools` from `set<int64_t>` to `map<int64_t, unsigned>` to also record `pg_num`, enabling the `ps >= pg_num` filter in `ingest_pgstats`.

### `0bac6af3c18` — remove debug 30 memory spike (2026-05-19, Fixes tracker#64082)
Same as in `update_delta_stats`: removed the full `pg_map` JSON dump; retained the guarded `pending_inc` dump.

**Known defects:**

```
// TODO: Complete the separation of PG state handling so
// that a cut-down set of functionality remains in PGMonitor
// while the full-blown PGMap lives only here.
```

**Location:** `src/mgr/ClusterState.cc` line 190 (tail of `notify_osdmap` body).
**Blame:** `a21b250f029` (baseline merge, Adam King, 2025-02-27) — present at earliest visible history.
**Age:** Since ≥ 2017 (visible in `aad1afcb96d` diff context by Kefu Chai).
**Meaning:** The original design aspiration to fully migrate PG tracking out of `PGMonitor` into the standalone mgr-side `PGMap` was never completed. `PGMonitor` in the mon still holds a cut-down view; the TODO records the unfinished boundary work.

**divergence_flag:** `true` — the persistent TODO at the end of this method signals that the PGMonitor/mgr PGMap separation refactor described as the original intent was never fully completed.

---

## Method: `ClusterState::final_init`

**Intent:** Register the `dump_osd_network` admin-socket command by wiring up a `ClusterSocketHook` to the process-global `AdminSocket`; must be called after `g_ceph_context` is initialized.

**First introduced:** Added with the heartbeat network ping-time statistics feature. Present in baseline (`a21b250f029`). Exact original SHA predates this repo's horizon.

**Commit history (affecting this method):**

| SHA | Date | Subject | Fix-signal |
|---|---|---|---|
| `1a7cdedb560` | 2019-09-05 | common/admin_socket: drop explicit prefix arg to register_command | no |
| `f1bac41828d` | 2025-10-01 | Update indent settings cc (Fixes tracker#72587) | **YES** (cosmetic) |

**Notable diffs:**

### `1a7cdedb560` — drop explicit prefix arg (2019-09-05, Sage Weil)
The `register_command` API was simplified; `final_init` lost a now-unnecessary prefix string argument.

**Known defects:** None.

**divergence_flag:** `false`

---

## Method: `ClusterState::asok_command`

**Intent:** Handle admin-socket commands dispatched to `ClusterState`; currently implements only `dump_osd_network`, which formats per-OSD heartbeat ping-time statistics (1min/5min/15min averages, min, max, last) filtered by a configurable threshold value, sorted descending by worst ping time, skipping stale entries.

**First introduced:** Added alongside the heartbeat network ping-time feature. Present in baseline (`a21b250f029`).

**Commit history (affecting this method):**

| SHA | Date | Subject | Fix-signal |
|---|---|---|---|
| `af2f825ec3c` | 2019-09-06 | test: Allow fractional milliseconds to make test possible | no |
| `f1bac41828d` | 2025-10-01 | Update indent settings cc (Fixes tracker#72587) | **YES** (cosmetic) |

**Notable diffs:**

### `f1bac41828d` — Update indent settings cc (2025-10-01, Fixes tracker#72587)
Changed the file-level modeline from `indent-tabs-mode:t` / `smarttab` to `indent-tabs-mode:nil` / `expandtab`. The body of `asok_command` was reflowed accordingly. No functional change.

**Known defects:** None.

**divergence_flag:** `false`

---

## Method: `ClusterState::have_fsmap` (inline, header only)

**Intent:** Thread-safely return `true` if a valid FSMap has been received (epoch > 0).

**Commit history:** Defined entirely inline in the header. No `.cc`-file commits target this method.

**Notable diffs:** None.

**Known defects:** None.

**divergence_flag:** `false`

---

## Method: `ClusterState::with_servicemap` (inline template, header only)

**Intent:** Provide a lock-guarded read-only callback accessor for the `ServiceMap`; callers pass a callable that receives `const servicemap&`.

**First introduced:** `97cfc3cb694` (2017-06-26, Sage Weil) — when service registrations were added.

**Commit history:** N/A — defined entirely inline in the header; no `.cc`-file commits target this method.

**Notable diffs:** None.

**Known defects:** None.

**divergence_flag:** `false`

---

## Method: `ClusterState::with_fsmap` (inline template, header only)

**Intent:** Provide a lock-guarded read-only callback accessor for the `FSMap`.

**First introduced:** `ac30e6cee2b` (2016-06-30, John Spray).

**Commit history:** N/A — defined entirely inline in the header; no `.cc`-file commits target this method.

**Notable diffs:** None.

**Known defects:** None.

**divergence_flag:** `false`

---

## Method: `ClusterState::with_mgrmap` (inline template, header only)

**Intent:** Provide a lock-guarded read-only callback accessor for the `MgrMap`.

**First introduced:** `6c10417f7ed` (2017-06-27, Sage Weil).

**Commit history:** N/A — defined entirely inline in the header; no `.cc`-file commits target this method.

**Notable diffs:** None.

**Known defects:** None.

**divergence_flag:** `false`

---

## Method: `ClusterState::with_pgmap` (inline template, header only)

**Intent:** Provide a lock-guarded read-only callback accessor for the `PGMap`.

**First introduced:** `fa147e3a591` (2016-07-31, John Spray).

**Commit history:** N/A — defined entirely inline in the header; no `.cc`-file commits target this method.

**Notable diffs:** None.

**Known defects:** None.

**divergence_flag:** `false`

---

## Method: `ClusterState::with_mutable_pgmap` (inline template, header only)

**Intent:** Provide a lock-guarded mutable callback accessor for the `PGMap` for callers that need to modify it in-place.

**Commit history:** N/A — defined entirely inline in the header; no `.cc`-file commits target this method.

**Notable diffs:** None.

**Known defects:** None.

**divergence_flag:** `false`

---

## Method: `ClusterState::with_monmap` (inline template, header only)

**Intent:** Provide a lock-guarded callback accessor that delegates to `MonClient::with_monmap`, asserting `monc != nullptr` first.

**Commit history:** N/A — defined entirely inline in the header; no `.cc`-file commits target this method.

**Notable diffs:** None.

**Known defects:** None.

**divergence_flag:** `false`

---

## Method: `ClusterState::with_osdmap` (inline template, header only)

**Intent:** Provide a lock-free callback accessor delegating to `Objecter::with_osdmap`, asserting `objecter != nullptr`; the OSDMap lock is managed by Objecter itself.

**Commit history:** N/A — defined entirely inline in the header; no `.cc`-file commits target this method.

**Notable diffs:** None.

**Known defects:** None.

**divergence_flag:** `false`

---

## Method: `ClusterState::with_osdmap_and_pgmap` (inline template, header only)

**Intent:** Provide a combined accessor that invokes `cb(osdmap, pg_map, …args)` under both the Objecter OSDMap lock and the ClusterState lock, ensuring a consistent snapshot of both maps.

**Commit history:** N/A — defined entirely inline in the header; no `.cc`-file commits target this method.

**Notable diffs:** None.

**Known defects:** None.

**divergence_flag:** `false`

---

## Method: `ClusterState::with_health` (inline template, header only)

**Intent:** Provide a lock-guarded read-only callback accessor for the health JSON blob.

**Commit history:** N/A — defined entirely inline in the header; no `.cc`-file commits target this method.

**Notable diffs:** None.

**Known defects:** None.

**divergence_flag:** `false`

---

## Method: `ClusterState::with_mon_status` (inline template, header only)

**Intent:** Provide a lock-guarded read-only callback accessor for the mon-status JSON blob.

**Commit history:** N/A — defined entirely inline in the header; no `.cc`-file commits target this method.

**Notable diffs:** None.

**Known defects:** None.

**divergence_flag:** `false`

---

## Known Defects (consolidated)

| Type | Location | Text | Blame SHA | Age |
|---|---|---|---|---|
| TODO | `ClusterState.cc:190` (tail of `notify_osdmap`) | "Complete the separation of PG state handling so that a cut-down set of functionality remains in PGMonitor while the full-blown PGMap lives only here." | `a21b250f029` (baseline; present since ≥ 2017) | ≥ 8 years |

---

## Fix-Signal Summary

| Method | Total commits | Fix-signal commits | Tracker refs |
|---|---|---|---|
| `ClusterState()` (constructor) | 3 | 0 | — |
| `set_objecter` | 2 | 0 | — |
| `set_fsmap` | 2 | 0 | — |
| `set_mgr_map` | 2 | 0 | — |
| `set_service_map` | 2 | 0 | — |
| `load_digest` | 3 | 0 | — |
| `ingest_pgstats` | 9 | 4 | tracker#20208 (indirect) |
| `update_delta_stats` | 5 | 2 | tracker#64082 |
| `notify_osdmap` | 8 | 5 | tracker#64082, tracker#20208 |
| `final_init` | 2 | 1 | tracker#72587 (cosmetic) |
| `asok_command` | 2 | 1 | tracker#72587 (cosmetic) |
| `have_fsmap` (inline) | 0 | 0 | — |
| `with_servicemap` (inline) | 0 | 0 | — |
| `with_fsmap` (inline) | 0 | 0 | — |
| `with_mgrmap` (inline) | 0 | 0 | — |
| `with_pgmap` (inline) | 0 | 0 | — |
| `with_mutable_pgmap` (inline) | 0 | 0 | — |
| `with_monmap` (inline) | 0 | 0 | — |
| `with_osdmap` (inline) | 0 | 0 | — |
| `with_osdmap_and_pgmap` (inline) | 0 | 0 | — |
| `with_health` (inline) | 0 | 0 | — |
| `with_mon_status` (inline) | 0 | 0 | — |
