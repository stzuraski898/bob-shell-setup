# Intent Assessment: Mgr

**Source files:** `src/mgr/Mgr.cc`, `src/mgr/Mgr.h`
**Corpus HEAD:** `8681fa6ebac230f86eb445bf57095c63e7f1abcc` (2026-09-11T21:40:59Z)
**Assessment date:** 2026-09-11
**Commits analysed:** 105
**Functions assessed:** 19

> This artefact was produced by an AI assessment agent reading the raw git
> corpus in `/home/szuraski/BobOutput/Object History/v4/Mgr/`.
> It describes the *intended* behaviour of each function as reconstructed from
> commit history — not necessarily what the current code does.
> Test-writing agents should use this as the ground truth for what to test,
> and treat divergences as likely bugs.

---

### Class overview

`Mgr` represents the active Ceph Manager daemon instance. It coordinates cluster state monitoring, daemon metadata caching, cluster map ingestion (`OSDMap`, `FSMap`, `MonMap`, `ServiceMap`), key-value configuration synchronization with monitors, and active Python module execution via `PyModuleRegistry` and `DaemonServer`.

Primary invariants and ownership rules:
- Internal state transitions and map processing are guarded by `Mgr::lock` (a `ceph::mutex`).
- Initialization is asynchronous via `finisher` to avoid blocking startup paths, transitioning from uninitialized -> initializing -> initialized.
- Once active, the daemon tracks metadata changes for OSDs, MDSs, and Mons, indexing them into `DaemonStateIndex` and resolving physical container hostnames via CRUSH hierarchy where appropriate.
- Historically, `Mgr` underwent major architectural evolutions: moving from monolithic python management to `PyModuleRegistry`/`ActivePyModules` (`9718896c8b84`), introducing asynchronous background initialization and beacon handshakes (`e0e87da6529d`, `cbd1726fde08`), switching config-key polling to incremental KV push subscriptions for Pacific+ clusters (`edf1ea2f5092`), removing legacy CephFS C++ client embedding (`f20df2eb8545`), and restoring explicit shutdown cleanup for `DaemonServer` (`fd4d4ce58b86`, `75b6149b294e`).

---

## `Mgr::Mgr(MonClient *monc_, const MgrMap& mgrmap, PyModuleRegistry *py_module_registry_, Messenger *clientm_, Objecter *objecter_, LogChannelRef clog_, LogChannelRef audit_clog_)`

**Introduced:** `ac30e6cee2b2` — mgr: create ceph-mgr service
**Last modified:** `75b6149b294e` — common/TrackedOp: make OpHistory::on_shutdown() idempotent
**Change count:** 14 commits touched this function
**Divergence:** OK

### Intent

Constructs the active manager daemon instance and initializes subcomponents including cluster state tracking, daemon server, finisher queue, logging channels, and Python module registry bindings. Sets the objecter pointer in `ClusterState`.

### Invariants and contracts

- Must initialize `digest_received` to `false` and reset `initialization_start_time` to zero clock time. (Established: `f25763208ff6`, `bf25a08cc58c`)
- Must bind `cluster_state` with the provided `objecter` instance upon construction. (Introduced: `ac30e6cee2b2`)
- Must pass `clog` and `audit_clog` references down to `server`. (Introduced: `9718896c8b84`)

### Error conditions

- None. Construction is non-failing assuming valid pointer arguments.

### Evolution summary

Originally instantiated its own client messenger, `MonClient`, and `Objecter` in `ac30e6cee2b2`. Refactored in `7845f8d757ad` and `6c10417f7ed3` to accept external references from `MgrStandby`. Integrated `PyModuleRegistry` in `9718896c8b84`. Removed legacy embedded CephFS `Client` in `f20df2eb8545`. Added monotonic clock tracker `initialization_start_time` in `bf25a08cc58c`.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — The constructor at [`src/mgr/Mgr.cc:59-79`](ceph-agent-26/src/mgr/Mgr.cc:59) initializes all member fields, sets `digest_received(false)`, `initialized(false)`, `initializing(false)`, `initialization_start_time(ceph::coarse_mono_clock::zero())`, and invokes `cluster_state.set_objecter(objecter)` on line 78 matching all historical contracts.

---

## `Mgr::~Mgr()`

**Introduced:** `ac30e6cee2b2` — mgr: create ceph-mgr service
**Last modified:** `75b6149b294e` — common/TrackedOp: make OpHistory::on_shutdown() idempotent
**Change count:** 6 commits touched this function
**Divergence:** OK

### Intent

Destroys the `Mgr` instance and releases managed resources.

### Invariants and contracts

- Resource teardown must rely on `shutdown()` or member destructors in correct reverse initialization order. (Established: `75b6149b294e`)

### Error conditions

- None. Destructor is `noexcept`.

### Evolution summary

Originally deleted allocated `objecter`, `monc`, and `client_messenger` in `ac30e6cee2b2`. As ownership shifted to `MgrStandby`, raw pointer deletion was removed in `7845f8d757ad`. In `fd4d4ce58b86`, `server.shutdown()` was temporarily called here to resolve OpHistory thread use-after-free races, then moved into `Mgr::shutdown()` in `75b6149b294e`.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — [`src/mgr/Mgr.cc:82-84`](ceph-agent-26/src/mgr/Mgr.cc:82) defines an empty destructor, delegating member destruction in reverse member declaration order.

---

## `void Mgr::shutdown()`

**Introduced:** `ac30e6cee2b2` — mgr: create ceph-mgr service
**Last modified:** `75b6149b294e` — common/TrackedOp: make OpHistory::on_shutdown() idempotent
**Change count:** 9 commits touched this function
**Divergence:** OK

### Intent

Performs an orderly shutdown of the active manager instance by unregistering admin socket commands, flushing and stopping the background finisher, and terminating the daemon server.

### Invariants and contracts

- If `initialized` is true, must unregister admin socket commands registered by this instance before tearing down internal services. (Established: `75b6149b294e`)
- Must wait for the finisher queue to empty before stopping the finisher thread. (Established: `ce6b1909dd55`, `75b6149b294e`)
- Must shut down `server` (`DaemonServer`) to stop incoming RPCs and background `OpTracker` threads. (Established: `fd4d4ce58b86`, `75b6149b294e`)

### Error conditions

- None.

### Evolution summary

Originally queued active module shutdown on the finisher in `ac30e6cee2b2` and `523b7cafc4c8`. Removed entirely in `dd9f9e268b55` because signal handlers immediately exited via `_exit(0)`. Re-introduced in `75b6149b294e` as part of clean unit test teardown and explicit `DaemonServer` lifecycle management.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — [`src/mgr/Mgr.cc:86-97`](ceph-agent-26/src/mgr/Mgr.cc:86) unregisters admin socket commands when `initialized` is true (lines 88-91), drains and stops `finisher` (lines 93-94), and invokes `server.shutdown()` (line 96).

---

## `static std::string crush_hostname_for_osd(ClusterState& cluster_state, int osd_id)`

**Introduced:** `dcd9c5bac5e2` — mgr: override OSD hostname with CRUSH physical host in all metadata paths
**Last modified:** `dcd9c5bac5e2` — mgr: override OSD hostname with CRUSH physical host in all metadata paths
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent

Extracts the physical host bucket name from the CRUSH hierarchy for a given OSD ID by querying `ClusterState`'s `OSDMap`.

### Invariants and contracts

- Must inspect `osdmap.crush` full location for bucket key `"host"`. (Established: `dcd9c5bac5e2`)
- Must return an empty string if the CRUSH map is unavailable, if the OSD is not in CRUSH, or if no `"host"` bucket exists. (Established: `dcd9c5bac5e2`)
- Must access `OSDMap` via `cluster_state.with_osdmap()` to ensure thread safety without taking lower-level daemon locks. (Established: `dcd9c5bac5e2`)

### Error conditions

- Returns `""` (empty string) when location is not found or CRUSH map is null.

### Evolution summary

Introduced in `dcd9c5bac5e2` to resolve container/pod vs physical hostname discrepancy in containerized deployments (tracker #73080).

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Implementation at [`src/mgr/Mgr.cc:99-112`](ceph-agent-26/src/mgr/Mgr.cc:99) safely accesses `with_osdmap`, checks `osdmap.crush`, searches location map for `"host"`, and returns the hostname or empty string.

---

## `void MetadataUpdate::finish(int r)`

**Introduced:** `ac30e6cee2b2` — mgr: create ceph-mgr service
**Last modified:** `ec5988807024` — mgr: preserve reported hostname when CRUSH host is unavailable
**Change count:** 17 commits touched this function
**Divergence:** OK

### Intent

Asynchronous callback invoked when a mon command for daemon metadata completes. Parses the JSON metadata response, injects defaults, overrides OSD hostnames with physical CRUSH hosts when available, and updates or inserts the `DaemonState` in `DaemonStateIndex`.

### Invariants and contracts

- Must call `daemon_state.clear_updating(key)` unconditionally on completion. (Introduced: `ac30e6cee2b2`)
- If `r == 0`, must validate that response is valid JSON and that the root JSON value is an object (`json_spirit::obj_type`); otherwise log and return without updating. (Established: `92b2fe9e653f`)
- Must skip metadata entries missing the `"hostname"` field. (Established: `3c333f359964`)
- Must apply default key-value pairs from `defaults` if missing in returned metadata. (Established: `8ce30bc4cd23`)
- Must resolve CRUSH host *before* taking `state->lock` to preserve lock ordering (`Objecter::rwlock` must not be acquired under `state->lock`). (Established: `dcd9c5bac5e2`)
- Must populate `m["hostname"]` with CRUSH physical host if available; otherwise fall back to reported metadata hostname. (Established: `ec5988807024`)
- Must update metadata via `daemon_state.update_metadata(state, m)` when daemon exists, ensuring device index re-registration. (Established: `8a2f4429b129`)
- Must abort via `ceph_abort()` if `key.type` is not one of `"mds"`, `"osd"`, `"mgr"`, or `"mon"`. (Established: `61fca96c2910`, `5aac7eba36be`)

### Error conditions

- `r != 0`: Logs debug error message and clears updating state. (Introduced: `ac30e6cee2b2`)
- Invalid JSON or non-object JSON: Logs error and returns. (Established: `ac30e6cee2b2`, `92b2fe9e653f`)
- Missing `"hostname"` in JSON: Logs skip notice and returns. (Established: `3c333f359964`)

### Evolution summary

Started with basic MDS/OSD metadata parsing in `ac30e6cee2b2`. Added defaults injection in `8ce30bc4cd23`. Added device state index synchronization via `daemon_state.update_metadata` in `8a2f4429b129`. Added sanity checks for non-object JSON in `92b2fe9e653f`. Handled mon metadata in `430ba5e231d6`. Added CRUSH physical host resolution in `dcd9c5bac5e2` and fixed fallback for non-CRUSH daemons in `ec5988807024`.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — [`src/mgr/Mgr.cc:114-225`](ceph-agent-26/src/mgr/Mgr.cc:114) clears updating state at line 116, validates JSON object format at lines 121-131, drops incomplete entries lacking `"hostname"` at line 137, resolves CRUSH hostname outside `state->lock` at lines 154-161, updates metadata with proper locking at lines 164-183, handles new daemon creation and registration at lines 185-217, and aborts on invalid daemon types at line 219.

---

## `MetadataUpdate::MetadataUpdate(DaemonStateIndex &daemon_state_, ClusterState &cluster_state_, const DaemonKey &key_)`

**Introduced:** `ac30e6cee2b2` — mgr: create ceph-mgr service
**Last modified:** `dcd9c5bac5e2` — mgr: override OSD hostname with CRUSH physical host in all metadata paths
**Change count:** 3 commits touched this function
**Divergence:** OK

### Intent

Constructs a `MetadataUpdate` completion context and immediately registers the daemon key as updating in `DaemonStateIndex`.

### Invariants and contracts

- Must invoke `daemon_state.notify_updating(key)` in constructor to prevent duplicate concurrent metadata fetches. (Established: `3eaf1516ebbf`)

### Error conditions

- None.

### Evolution summary

Originally a trivial constructor in `ac30e6cee2b2`. In `3eaf1516ebbf`, `daemon_state.notify_updating(key)` was moved into the constructor to prevent duplicate requests across call sites. In `dcd9c5bac5e2`, `ClusterState&` was added to enable CRUSH lookup on completion.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Inline constructor at [`src/mgr/Mgr.h:128-133`](ceph-agent-26/src/mgr/Mgr.h:128) stores references and calls `daemon_state.notify_updating(key)` on line 132.

---

## `void MetadataUpdate::set_default(const std::string &k, const std::string &v)`

**Introduced:** `8ce30bc4cd23` — mgr: fix metadata handling from old MDS daemons
**Last modified:** `8ce30bc4cd23` — mgr: fix metadata handling from old MDS daemons
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent

Stores a default key-value pair to inject into the daemon metadata if the monitor response does not contain the key.

### Invariants and contracts

- Defaults are applied only when the key is absent in the parsed JSON response. (Established: `8ce30bc4cd23`)

### Error conditions

- None.

### Evolution summary

Introduced in `8ce30bc4cd23` to supply synthetic `"addr"` metadata for legacy MDS daemons.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Inline method at [`src/mgr/Mgr.h:135-138`](ceph-agent-26/src/mgr/Mgr.h:135) sets `defaults[k] = v`.

---

## `void Mgr::background_init(Context *completion)`

**Introduced:** `ac30e6cee2b2` — mgr: create ceph-mgr service
**Last modified:** `cbd1726fde08` — mgr: ensure that all modules have started before advertising active mgr
**Change count:** 7 commits touched this function
**Divergence:** OK

### Intent

Asynchronously initiates manager daemon initialization on the finisher thread and signals the caller via `completion` only after `init()` completes and all active python modules have started.

### Invariants and contracts

- Must hold `lock` and assert `!initializing` and `!initialized`. (Introduced: `7845f8d757ad`, `ab23c5069647`)
- Must set `initializing = true` and record `initialization_start_time` before queueing onto finisher. (Established: `7845f8d757ad`, `bf25a08cc58c`)
- Must start the finisher thread before queueing tasks. (Established: `7845f8d757ad`)
- Must wait for `py_module_registry->check_all_modules_started()` before marking `initialized = true`, `initializing = false`, and invoking `completion->complete(0)`. (Established: `cbd1726fde08`)

### Error conditions

- None.

### Evolution summary

Originally ran synchronous initialization in `ac30e6cee2b2`. Moved to background finisher in `7845f8d757ad`. Added completion callback in `e0e87da6529d`. In `cbd1726fde08`, module startup check `check_all_modules_started()` was added before setting `initialized = true` to avoid advertising active status prematurely. In `bf25a08cc58c`, `initialization_start_time` tracking was added.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — [`src/mgr/Mgr.cc:227-249`](ceph-agent-26/src/mgr/Mgr.cc:227) acquires `lock`, asserts initialization flags (lines 230-231), sets `initialization_start_time` (line 233), starts `finisher` (line 235), runs `init()`, and chains `py_module_registry->check_all_modules_started()` to set `initialized = true` and fire `completion->complete(0)` (lines 239-247).

---

## `std::map<std::string, std::string> Mgr::load_store()`

**Introduced:** `ac30e6cee2b2` — mgr: create ceph-mgr service
**Last modified:** `edf1ea2f5092` — mgr: use new kv subscription for mgr/, device/, config/
**Change count:** 9 commits touched this function
**Divergence:** OK

### Intent

Synchronously loads legacy `config-key` entries with prefixes matching `mgr/` or `device/` from the monitor cluster during startup (used when monitors are pre-Pacific).

### Invariants and contracts

- Caller must hold `lock` before calling; `lock` is dropped across synchronous mon command waits and reacquired. (Established: `c93dc8849145`)
- Must execute `"config-key ls"` and assert return status `r == 0`. (Established: `ac30e6cee2b2`, `ab23c5069647`)
- Must filter keys matching `PyModule::mgr_store_prefix` or `"device/"` prefix. (Established: `45d4dfed1ded`, `3bafb5e57168`)
- Must tolerate racing key deletions during `"config-key get"` by checking `get_cmd.r == 0` before storing result. (Established: `615a6562bc6a`)

### Error conditions

- Assertion failure if `config-key ls` fails (`cmd.r != 0`). (Established: `ab23c5069647`)
- Non-zero return from individual `config-key get` is tolerated and skipped. (Established: `615a6562bc6a`)

### Evolution summary

Renamed from `load_config()` to `load_store()` in `37484af0b860`. Device metadata support added in `45d4dfed1ded`. Toleration for racing deletes added in `615a6562bc6a`. Prefix rename `config_prefix` -> `mgr_store_prefix` in `3bafb5e57168`. With Pacific KV subscriptions (`edf1ea2f5092`), this function is only invoked as a fallback for pre-Pacific monitors.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — [`src/mgr/Mgr.cc:251-290`](ceph-agent-26/src/mgr/Mgr.cc:251) enforces `ceph_mutex_is_locked_by_me(lock)` (line 253), issues `config-key ls`, drops/re-locks around wait, filters on store and device prefixes (lines 270-276), tolerates racing changes (line 283), and returns the populated map.

---

## `static void handle_mgr_signal(int signum)`

**Introduced:** `c81e542b3281` — mgr: enable multiple python modules
**Last modified:** `dfd01d765304` — blacklist -> blocklist
**Change count:** 5 commits touched this function
**Divergence:** OK

### Intent

One-shot async signal handler for `SIGINT` and `SIGTERM`. Logs the received signal and immediately exits the process via `_exit(0)`.

### Invariants and contracts

- Must terminate immediately via `_exit(0)` without invoking Python module shutdown hooks, relying on monitor blocklisting to evict clients. (Established: `3363a1001c7b`)

### Error conditions

- None.

### Evolution summary

Originally invoked `signal_mgr->handle_signal(signum)` to run graceful shutdown in `c81e542b3281` and `3d360b97ed7d`. Due to deadlocks in Python module teardown (tracker #42744, #42981), changed in `3363a1001c7b` to exit immediately via `_exit(0)`. Updated terminology to blocklist in `dfd01d765304`.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — [`src/mgr/Mgr.cc:292-301`](ceph-agent-26/src/mgr/Mgr.cc:292) logs the signal and immediately calls `_exit(0)`.

---

## `void Mgr::init()`

**Introduced:** `ac30e6cee2b2` — mgr: create ceph-mgr service
**Last modified:** `f20df2eb8545` — mgr: excise CephFS client from mgr C++ base
**Change count:** 31 commits touched this function
**Divergence:** OK

### Intent

Performs core initialization of the active manager instance: registers signal handlers, checks monitor feature capabilities, subscribes to cluster maps, synchronizes initial OSDMap, FSMap, MgrDigest, and KV stores, initializes daemon metadata and device state, starts active Python modules, and registers admin socket commands.

### Invariants and contracts

- Must hold `lock` and assert `initializing && !initialized`. (Introduced: `7845f8d757ad`, `ab23c5069647`)
- Must register one-shot signal handlers for `SIGINT` and `SIGTERM`. (Established: `c81e542b3281`)
- If monitors do not support Pacific KV subscriptions (`FEATURE_PACIFIC`), must sleep for `3 * mgr_tick_period` to ensure module options are propagated in beacons. (Established: `b356fd0a8c65`)
- Must subscribe to `log-info`, `mgrdigest`, `fsmap`, `servicemap`, and (if Pacific+) `kv:config/`, `kv:mgr/`, `kv:device/`. (Established: `9ea37c223f92`, `97cfc3cb694e`, `edf1ea2f5092`)
- Must wait for `OSDMap` epoch corresponding to `last_failure_osd_epoch` to ensure blocklists against prior active manager instances have taken effect. (Established: `f2986a4400bb`)
- If server initialization fails (e.g. bind failure), must exit with code 1. (Established: `2dca5b436a21`)
- Must load initial daemon metadata via `load_all_metadata()` before waiting on maps. (Introduced: `ac30e6cee2b2`)
- Must wait on condition variables until `cluster_state.have_fsmap()` is true and `digest_received` is true. (Established: `ac30e6cee2b2`, `f25763208ff6`)
- Must start active Python modules via `py_module_registry->active_start()`. (Established: `9718896c8b84`)
- Must register the `"mgr_status"` admin socket hook. (Established: `3e056ca5c6d2`)
- Under `WITH_LIBCEPHSQLITE`, must initialize `cephsqlite` VFS and register client with `py_module_registry`. (Established: `52446d00f647`, `e72194b42ce1`)

### Error conditions

- `server.init()` failure: logs error and calls `exit(1)`. (Established: `b4a4a7a89b21`, `2dca5b436a21`)
- `sqlite3_open_v2` failure: logs error and aborts via `ceph_abort()`. (Established: `52446d00f647`)
- `cephsqlite_setcct` failure: logs error and aborts via `ceph_abort()`. (Established: `52446d00f647`)

### Evolution summary

Originally initialized messenger, monc, and objecter directly in `ac30e6cee2b2`. Shifted to external services in `7845f8d757ad`. Added OSDMap wait for prior instance blocklist in `f2986a4400bb`. Added pre-Pacific beacon delay in `b356fd0a8c65`. Added Pacific KV subscription support in `edf1ea2f5092`. Added SQLite VFS initialization in `52446d00f647` and `e72194b42ce1`. Removed embedded CephFS client in `f20df2eb8545`.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — [`src/mgr/Mgr.cc:303-465`](ceph-agent-26/src/mgr/Mgr.cc:303) faithfully implements all startup phases: signal handler registration (lines 310-313), Pacific mon feature check and sleep workaround (lines 316-330), map subscriptions (lines 333-341), blocklist OSDMap sync (lines 353-362), `server.init()` error check (lines 365-372), `load_all_metadata()` (line 378), condition variable waits for FSMap and MgrDigest (lines 388-392), device state population (lines 399-420), `py_module_registry->active_start()` (lines 424-428), `admin_socket->register_command("mgr_status")` (lines 432-436), and conditional SQLite initialization (lines 438-462).

---

## `void Mgr::load_all_metadata()`

**Introduced:** `ac30e6cee2b2` — mgr: create ceph-mgr service
**Last modified:** `dcd9c5bac5e2` — mgr: override OSD hostname with CRUSH physical host in all metadata paths
**Change count:** 14 commits touched this function
**Divergence:** DIVERGED

### Intent

Synchronously queries the monitors for all existing MDS, OSD, and Mon metadata at startup, populates `DaemonStateIndex` with corresponding `DaemonState` entries, and maps OSD hostnames to physical CRUSH host buckets where applicable.

### Invariants and contracts

- Caller must hold `lock`; `lock` is dropped across mon command wait and reacquired. (Established: `ac30e6cee2b2`, `c93dc8849145`)
- Must assert that all three monitor commands (`mds metadata`, `osd metadata`, `mon metadata`) return success (`r == 0`). (Introduced: `ac30e6cee2b2`, `ab23c5069647`)
- Must skip incomplete metadata entries missing `"hostname"`. (Established: `ac30e6cee2b2`)
- For OSDs, must resolve CRUSH physical host bucket via `crush_hostname_for_osd(cluster_state, osd_id)` and use it as `hostname` when non-empty. (Established: `dcd9c5bac5e2`)
- Must populate metadata map via `DaemonState::set_metadata(m)` and insert into `daemon_state`. (Established: `67b5d3e343c5`)

### Error conditions

- Assertion failure if any metadata command fails (`r != 0`). (Introduced: `ac30e6cee2b2`, `ab23c5069647`)
- Skipping entries lacking `"hostname"`. (Introduced: `ac30e6cee2b2`)

### Evolution summary

Introduced in `ac30e6cee2b2` for MDS, OSD, and Mon metadata loading. Added devid extraction via `set_metadata` in `67b5d3e343c5`. Mon metadata parsing updated in `80cee1d98816`. In `dcd9c5bac5e2`, CRUSH physical hostname resolution was added for OSDs.

### Deferred / known incomplete

None.

### Implementation critique

DIVERGED — In [`src/mgr/Mgr.cc:495-508`](ceph-agent-26/src/mgr/Mgr.cc:495) (MDS loop), metadata is assigned directly via `dm->metadata.emplace(key, val.get_str())` instead of calling `dm->set_metadata(m)` like the Mon loop (line 529) and OSD loop (line 560). Commit `67b5d3e343c5` established that `set_metadata()` must be called to populate parsed fields (such as device IDs). Furthermore, at lines 478-482, `lock` is unlocked and re-locked while waiting for monitor commands, which correctly matches the concurrency contract.

---

## `void Mgr::handle_osd_map()`

**Introduced:** `ac30e6cee2b2` — mgr: create ceph-mgr service
**Last modified:** `3db2b5767056` — mgr: remove health msgs from the metrics if osd destroyed
**Change count:** 19 commits touched this function
**Divergence:** OK

### Intent

Processes newly received `OSDMap` updates: identifies joined or restarted OSDs to trigger asynchronous metadata fetches, clears daemon health metrics for OSDs that are (down and out) or destroyed, culls removed OSDs from `DaemonStateIndex`, and notifies `ClusterState`.

### Invariants and contracts

- Caller must hold `lock`. (Introduced: `ac30e6cee2b2`, `c93dc8849145`)
- Must not trigger metadata fetch if `daemon_state.is_updating(k)` is already true. (Introduced: `ac30e6cee2b2`)
- Must clear `daemon_health_metrics` under `daemon->lock` if an OSD is both down and out, or if it is destroyed. (Established: `282558cf4027`, `3db2b5767056`)
- Must trigger `MetadataUpdate` if OSD is new (`!daemon`) or if `osd_map.get_up_from(osd_id) == osd_map.get_epoch()` (newly joined/restarted). (Established: `ac30e6cee2b2`, `73078cf73c3a`)
- Must notify cluster state via `cluster_state.notify_osdmap(osd_map)`. (Introduced: `fa147e3a591a`)
- Must cull missing OSDs from daemon state via `daemon_state.cull("osd", names_exist)`. (Established: `a22b256bad1f`)

### Error conditions

- None.

### Evolution summary

Originally fetched metadata unconditionally for non-existing daemons in `ac30e6cee2b2`. Added OSD join detection in `73078cf73c3a`. In `3072b113242e`, down/out OSDs were culled, which broke metrics; reverted in `282558cf4027` to instead clear `daemon_health_metrics`. In `3db2b5767056`, health metrics clearing was extended to destroyed OSDs.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — [`src/mgr/Mgr.cc:566-633`](ceph-agent-26/src/mgr/Mgr.cc:566) checks lock assertion at line 568, tracks existing OSD names in `names_exist`, skips updating daemons (line 589), clears metrics under `daemon->lock` if out+down or destroyed (lines 596-605), detects joined OSDs at current epoch (line 610), triggers `MetadataUpdate` mon command (lines 618-626), notifies `cluster_state` (line 628), and culls non-existent OSDs (line 632).

---

## `void Mgr::handle_log(ceph::ref_t<MLog> m)`

**Introduced:** `9ea37c223f92` — mgr: pass through cluster log to plugins
**Last modified:** `a50a91d24349` — mgr/{Mgr,MgrStandby}: use ref_t<M>
**Change count:** 3 commits touched this function
**Divergence:** OK

### Intent

Receives incoming cluster log messages (`MLog`) and forwards each log entry to all registered Python modules via `py_module_registry->notify_all(e)`.

### Invariants and contracts

- Must iterate over all log entries in `m->entries` and dispatch each to `py_module_registry`. (Introduced: `9ea37c223f92`, `9718896c8b84`)

### Error conditions

- None.

### Evolution summary

Introduced in `9ea37c223f92`. Updated to route via `py_module_registry` in `9718896c8b84` and migrated to `ceph::ref_t` in `a50a91d24349`.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — [`src/mgr/Mgr.cc:635-640`](ceph-agent-26/src/mgr/Mgr.cc:635) loops over `m->entries` and calls `py_module_registry->notify_all(e)`.

---

## `void Mgr::handle_service_map(ceph::ref_t<MServiceMap> m)`

**Introduced:** `97cfc3cb694e` — mgr: allow/track service registrations
**Last modified:** `3dbc1f0578d9` — mgr: tell monc when we get new servicemap, fsmap
**Change count:** 3 commits touched this function
**Divergence:** OK

### Intent

Processes incoming `ServiceMap` updates from the monitor, updates subscription ack status with `MonClient`, updates `ClusterState`, and notifies `DaemonServer`.

### Invariants and contracts

- Must acknowledge map receipt to `MonClient` via `monc->sub_got("servicemap", m->service_map.epoch)`. (Established: `3dbc1f0578d9`)
- Must update `cluster_state` with `m->service_map`. (Introduced: `97cfc3cb694e`)
- Must notify `server.got_service_map()`. (Introduced: `97cfc3cb694e`)

### Error conditions

- None.

### Evolution summary

Introduced in `97cfc3cb694e`. Added `sub_got` ack call in `3dbc1f0578d9` to prevent re-requesting old maps upon subscription renewal.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — [`src/mgr/Mgr.cc:642-648`](ceph-agent-26/src/mgr/Mgr.cc:642) logs epoch, notifies `monc->sub_got()`, updates `cluster_state`, and invokes `server.got_service_map()`.

---

## `void Mgr::handle_mon_map()`

**Introduced:** `430ba5e231d6` — mgr: request mon metadata when receiving a report msg from an unknown monitor
**Last modified:** `dcd9c5bac5e2` — mgr: override OSD hostname with CRUSH physical host in all metadata paths
**Change count:** 7 commits touched this function
**Divergence:** OK

### Intent

Processes `MonMap` updates by requesting metadata for all monitors in the latest map (if not already updating) and culling removed monitors from `DaemonStateIndex`.

### Invariants and contracts

- Caller must hold `lock`. (Introduced: `430ba5e231d6`, `c93dc8849145`)
- Must issue `"mon metadata"` mon commands outside the `with_monmap()` callback to avoid recursive locking on `MonClient` lock. (Established: `c037f4cb5d74`)
- Must use daemon key type `"mon"`. (Established: `8fc290bfba4d`)
- Must cull stale monitors from `DaemonStateIndex` via `daemon_state.cull("mon", names_exist)`. (Established: `430ba5e231d6`)

### Error conditions

- None.

### Evolution summary

Introduced in `430ba5e231d6` to handle mon reports from unindexed monitors. In `c037f4cb5d74`, updated to proactively refresh metadata for all monitors on MonMap change, moving the command dispatch outside `with_monmap()`. Fixed daemon type typo (`"osd"` -> `"mon"`) in `8fc290bfba4d`. Formatted command with `constexpr std::string_view` in `bbb1574eabf0`.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — [`src/mgr/Mgr.cc:650-671`](ceph-agent-26/src/mgr/Mgr.cc:650) asserts lock, extracts monitor names inside `with_monmap()`, dispatches `MetadataUpdate` commands outside `with_monmap()`, and calls `daemon_state.cull("mon", names_exist)` at line 670.

---

## `Dispatcher::dispatch_result_t Mgr::ms_dispatch2(const ceph::ref_t<Message>& m)`

**Introduced:** `ac30e6cee2b2` — mgr: create ceph-mgr service
**Last modified:** `56cb05775a93` — mgr: indicate map message is acked instead of unhandled
**Change count:** 16 commits touched this function
**Divergence:** OK

### Intent

Primary message dispatcher for the manager. Routes incoming messages based on message type (`MSG_MGR_DIGEST`, `CEPH_MSG_MON_MAP`, `CEPH_MSG_FS_MAP`, `CEPH_MSG_OSD_MAP`, `MSG_SERVICE_MAP`, `MSG_LOG`, `MSG_KV_DATA`), updates internal states, notifies Python modules, and returns dispatch status (`HANDLED`, `ACKNOWLEDGED`, or `UNHANDLED`).

### Invariants and contracts

- Must acquire `lock` before message routing. (Introduced: `ac30e6cee2b2`, `948635a8b213`)
- For `CEPH_MSG_MON_MAP`, `CEPH_MSG_FS_MAP`, and `CEPH_MSG_OSD_MAP`, must invoke internal map handler *before* notifying Python module subscribers. (Established: `190f37978f72`)
- For `CEPH_MSG_OSD_MAP`, must continuously renew subscription via `objecter->maybe_request_map()`. (Introduced: `ac30e6cee2b2`)
- For `MSG_KV_DATA`, if `initialized` is true, must forward updates to `py_module_registry->update_kv_data()`; otherwise must track changes in `pre_init_store`. (Established: `edf1ea2f5092`)
- Must return `Dispatcher::ACKNOWLEDGED()` for passthrough/shared map messages (`MON_MAP`, `FS_MAP`, `OSD_MAP`, `SERVICE_MAP`), `Dispatcher::HANDLED()` for exclusively handled messages (`MGR_DIGEST`, `LOG`, `KV_DATA`), and `Dispatcher::UNHANDLED()` for unknown messages. (Established: `56cb05775a93`)

### Error conditions

- Unknown message type returns `Dispatcher::UNHANDLED()`. (Established: `56cb05775a93`)

### Evolution summary

Evolved from boolean `ms_dispatch` to `ms_dispatch2` returning `dispatch_result_t` in `56cb05775a93`. Ensured map handling occurs prior to module notification in `190f37978f72`. Added `MSG_KV_DATA` handling for Pacific KV sync in `edf1ea2f5092`. Added `mds_metadata` and `osd_metadata` notifications in `403340bcf8c2`.

### Deferred / known incomplete

- Line 703: Comment notes `//no users: py_module_registry->notify_all("service_map", "");`.

### Implementation critique

SATISFIES — [`src/mgr/Mgr.cc:673-748`](ceph-agent-26/src/mgr/Mgr.cc:673) acquires `lock` at line 676, properly dispatches each message type, enforces handler execution before notification, tracks pre-initialization KV data correctly (lines 720-741), and returns proper `Dispatcher` result codes matching `56cb05775a93`.

---

## `void Mgr::handle_fs_map(ceph::ref_t<MFSMap> m)`

**Introduced:** `ac30e6cee2b2` — mgr: create ceph-mgr service
**Last modified:** `dcd9c5bac5e2` — mgr: override OSD hostname with CRUSH physical host in all metadata paths
**Change count:** 14 commits touched this function
**Divergence:** OK

### Intent

Processes incoming `FSMap` updates: acknowledges map receipt to `MonClient`, awakens threads waiting on `fs_map_cond`, updates `ClusterState`, checks MDS daemons for address changes or missing metadata to trigger `MetadataUpdate`, and culls defunct MDS daemons.

### Invariants and contracts

- Caller must hold `lock`. (Introduced: `ac30e6cee2b2`, `c93dc8849145`)
- Must acknowledge map receipt via `monc->sub_got("fsmap", m->epoch)`. (Established: `3dbc1f0578d9`)
- Must signal `fs_map_cond.notify_all()`. (Introduced: `ac30e6cee2b2`, `1113eb123b14`)
- Must update `cluster_state` via `cluster_state.set_fsmap(new_fsmap)`. (Introduced: `ac30e6cee2b2`)
- For each MDS in `mds_info`, must skip if `!new_fsmap.gid_exists(gid)`. (Established: `6f10373b7a23`)
- Must compare existing metadata `"addr"` with map `info.addrs`; if missing or mismatched, trigger `MetadataUpdate` with default `"addr"` fallback. (Established: `8ce30bc4cd23`, `a6fab0825f27`, `ea1481d08d56`)
- Must cull missing MDS daemons via `daemon_state.cull("mds", names_exist)`. (Established: `a22b256bad1f`)

### Error conditions

- None.

### Evolution summary

Introduced in `ac30e6cee2b2`. Added condition variable wake in `1113eb123b14`. Added non-existent MDS filtering in `6f10373b7a23`. Added default `"addr"` injection for legacy MDS daemons in `8ce30bc4cd23`. Added `sub_got` ack in `3dbc1f0578d9`.

### Deferred / known incomplete

- Line 762: `// TODO: callers (e.g. from python land) are potentially going to see the new fsmap before we've bothered populating all the resulting daemon_state. Maybe we should block python land while we're making this kind of update?`

### Implementation critique

SATISFIES — [`src/mgr/Mgr.cc:751-821`](ceph-agent-26/src/mgr/Mgr.cc:751) asserts lock at line 753, sends `sub_got` ack (line 758), notifies `fs_map_cond` (line 760), updates `cluster_state` (line 767), checks GID existence (line 774), verifies address changes under `metadata->lock` (lines 788-802), queues `MetadataUpdate` with fallback default (lines 806-819), and culls missing MDS entries (line 820).

---

## `bool Mgr::got_mgr_map(const MgrMap& m)`

**Introduced:** `ac30e6cee2b2` — mgr: create ceph-mgr service
**Last modified:** `403340bcf8c2` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 7 commits touched this function
**Divergence:** OK

### Intent

Handles updates to the `MgrMap`. Notifies Python module subscribers, inspects enabled module set for changes (triggering a respawn if module list changed), updates `ClusterState`, and notifies `DaemonServer`.

### Invariants and contracts

- Must acquire `lock`. (Introduced: `16fcee1f71fc`, `948635a8b213`)
- Must notify Python modules via `py_module_registry->notify_all("mgr_map", "")`. (Established: `403340bcf8c2`)
- If `m.modules != old_modules`, must log respawn message and return `true` to signal `MgrStandby` to respawn the daemon. (Established: `16fcee1f71fc`)
- If module list is unchanged, must update `cluster_state.set_mgr_map(m)`, invoke `server.got_mgr_map()`, and return `false`. (Established: `16fcee1f71fc`, `cf68ce511f31`)

### Error conditions

- Returns `true` when module list changes to request process respawn. (Established: `16fcee1f71fc`)

### Evolution summary

Originally returned `void` in `ac30e6cee2b2`. In `16fcee1f71fc`, changed to return `bool` indicating whether module list changed requiring a daemon respawn. Added `server.got_mgr_map()` in `cf68ce511f31`. Added cache invalidation notification `notify_all("mgr_map", "")` in `403340bcf8c2`.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — [`src/mgr/Mgr.cc:823-843`](ceph-agent-26/src/mgr/Mgr.cc:823) acquires `lock`, compares old and new module sets (lines 828-833), fires `py_module_registry->notify_all("mgr_map", "")` (line 832), returns `true` on module set mismatch (line 836), and updates `cluster_state` and `server` before returning `false` (lines 839-842).

---

## `bool Mgr::exceeded_initialization_expiration()`

**Introduced:** `bf25a08cc58c` — mgr, common, qa, doc: issue health error after max expiration is exceeded
**Last modified:** `bf25a08cc58c` — mgr, common, qa, doc: issue health error after max expiration is exceeded
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent

Checks whether manager module initialization has exceeded the configured maximum timeout (`mgr_module_load_expiration`). If exceeded, forcefully resets initialization state and marks the manager as initialized so it sends an active beacon to avoid blocking cluster operations.

### Invariants and contracts

- If `initialization_start_time` is zero (initialization not started), must return `false` immediately. (Established: `bf25a08cc58c`)
- If elapsed time exceeds `g_conf().get_val<milliseconds>("mgr_module_load_expiration")`, must acquire `lock`, reset `initialization_start_time` to zero, set `initializing = false`, set `initialized = true`, and return `true`. (Established: `bf25a08cc58c`)
- Must return `false` if elapsed time has not exceeded expiration threshold. (Established: `bf25a08cc58c`)

### Error conditions

- None.

### Evolution summary

Introduced in `bf25a08cc58c` to prevent indefinite beacon stalls during slow module startup.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — [`src/mgr/Mgr.cc:845-870`](ceph-agent-26/src/mgr/Mgr.cc:845) checks `is_zero(initialization_start_time)` at line 849, calculates elapsed duration (line 854), compares against `mgr_module_load_expiration` (line 860), and under `lock` resets start time and flips `initializing = false`, `initialized = true` before returning the boolean result.

---

## `void Mgr::handle_mgr_digest(ceph::ref_t<MMgrDigest> m)`

**Introduced:** `ac30e6cee2b2` — mgr: create ceph-mgr service
**Last modified:** `403340bcf8c2` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 11 commits touched this function
**Divergence:** OK

### Intent

Processes incoming monitor digest messages (`MMgrDigest`): updates `ClusterState` with monitor status and health JSON, notifies registered Python modules, prompts PG summary/stats refreshes, and signals startup waiters on `digest_cond`.

### Invariants and contracts

- Must load digest into `ClusterState` via `cluster_state.load_digest(m.get())`. (Introduced: `ac30e6cee2b2`)
- Must notify Python modules of `"mon_status"`, `"health"`, `"pg_summary"`, `"pg_stats"`, and `"pg_dump"`. (Established: `9718896c8b84`, `403340bcf8c2`)
- If `digest_received` is false, must set `digest_received = true` and awaken waiters via `digest_cond.notify_all()`. (Established: `f25763208ff6`, `c93dc8849145`)

### Error conditions

- None.

### Evolution summary

Introduced in `ac30e6cee2b2`. Startup condition signaling added in `f25763208ff6`. Health notifications added in `3068c4290166`. Python module notifications for `pg_stats` and `pg_dump` added in `403340bcf8c2`.

### Deferred / known incomplete

- Line 879: `// Hack: use this as a tick/opportunity to prompt python-land that the pgmap might have changed since last time we were here.`

### Implementation critique

SATISFIES — [`src/mgr/Mgr.cc:871-891`](ceph-agent-26/src/mgr/Mgr.cc:871) updates `cluster_state`, sends all notifications (`mon_status`, `health`, `pg_summary`, `pg_stats`, `pg_dump`), resets message ref, and updates `digest_received` / signals `digest_cond` at lines 887-890.

---

## `std::map<std::string, std::string> Mgr::get_services() const`

**Introduced:** `a0183a63fa79` — mgr: enable python modules to advertise their service URI
**Last modified:** `948635a8b213` — mgr: Mutex::Locker -> std::lock_guard
**Change count:** 3 commits touched this function
**Divergence:** OK

### Intent

Returns the current map of service URIs advertised by active Python modules.

### Invariants and contracts

- Must acquire `lock` before querying `py_module_registry->get_services()`. (Introduced: `a0183a63fa79`, `948635a8b213`)

### Error conditions

- None.

### Evolution summary

Introduced in `a0183a63fa79`. Routed through `py_module_registry` in `9718896c8b84`.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — [`src/mgr/Mgr.cc:893-898`](ceph-agent-26/src/mgr/Mgr.cc:893) locks `lock` with `std::lock_guard` and returns `py_module_registry->get_services()`.

---

## `int Mgr::call(std::string_view admin_command, const cmdmap_t& cmdmap, const bufferlist& inbl, Formatter *f, std::ostream& errss, ceph::buffer::list& out)`

**Introduced:** `3e056ca5c6d2` — mgr: add 'mgr_status' tell command
**Last modified:** `68221661b00f` — mgr, qa: add `pending_modules` to asock command
**Change count:** 3 commits touched this function
**Divergence:** OK

### Intent

Admin socket hook callback executing manager-level administration commands (specifically `"mgr_status"`).

### Invariants and contracts

- If `admin_command == "mgr_status"`, must format an object section containing `mgrmap_epoch`, `initialized` boolean, and `pending_modules` string array, returning 0. (Established: `3e056ca5c6d2`, `68221661b00f`)
- If command is unrecognized, must return `-ENOSYS`. (Established: `3e056ca5c6d2`)
- Must catch `bad_cmd_get` exceptions, output error description to `errss`, and return `-EINVAL`. (Established: `3e056ca5c6d2`)

### Error conditions

- Unrecognized admin command: returns `-ENOSYS`. (Established: `3e056ca5c6d2`)
- Malformed command arguments (`bad_cmd_get`): returns `-EINVAL`. (Established: `3e056ca5c6d2`)

### Evolution summary

Introduced in `3e056ca5c6d2` supporting `"mgr_status"`. Updated signature for bufferlist in `07ad8df2dd74`. Added `pending_modules` list output in `68221661b00f`.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — [`src/mgr/Mgr.cc:900-933`](ceph-agent-26/src/mgr/Mgr.cc:900) handles `"mgr_status"` by dumping `mgrmap_epoch`, `initialized`, and `pending_modules` (lines 910-924), returns `-ENOSYS` on unknown commands (line 926), and catches `bad_cmd_get` returning `-EINVAL` (lines 928-931).

---

## `bool Mgr::is_initialized() const`

**Introduced:** `7845f8d757ad` — mgr: flesh out standby/HA
**Last modified:** `7845f8d757ad` — mgr: flesh out standby/HA
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent

Returns whether the active manager daemon has completed startup initialization.

### Invariants and contracts

- Must return the value of `initialized`. (Introduced: `7845f8d757ad`)

### Error conditions

- None.

### Evolution summary

Inline accessor in `Mgr.h` introduced in `7845f8d757ad`.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Defined inline at [`src/mgr/Mgr.h:80`](ceph-agent-26/src/mgr/Mgr.h:80) as `bool is_initialized() const { return initialized; }`.

---

## `entity_addrvec_t Mgr::get_server_addrs() const`

**Introduced:** `7f787704cdcd` — mgr: use entity_addrvec_t for MgrMap
**Last modified:** `7f787704cdcd` — mgr: use entity_addrvec_t for MgrMap
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent

Returns the network address vector of the manager's `DaemonServer`.

### Invariants and contracts

- Must return `server.get_myaddrs()`. (Introduced: `7f787704cdcd`)

### Error conditions

- None.

### Evolution summary

Introduced in `7f787704cdcd` replacing single address `get_server_addr()`.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Defined inline at [`src/mgr/Mgr.h:82-84`](ceph-agent-26/src/mgr/Mgr.h:82) returning `server.get_myaddrs()`.
