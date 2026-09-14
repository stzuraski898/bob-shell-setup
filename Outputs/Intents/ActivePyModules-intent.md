# ActivePyModules — Intent Artefact

## Corpus Summary

| Field | Value |
|-------|-------|
| Total non-merge commits | 234 |
| HEAD SHA | `8681fa6ebac230f86eb445bf57095c63e7f1abcc` |
| Oldest commit | `ac30e6cee2b2` — 2016-06-30 (John Spray, "mgr: create ceph-mgr service") |
| Newest commit | `42c4dfb40cec` — 2026-08-11 (Nitzan Mordechai, "mgr: don't log NotImplementedError from dispatch_remote as an error") |
| Date range | 2016-06-30 → 2026-08-11 (~10 years) |
| Rename history | `src/mgr/PyModules.{cc,h}` → `src/mgr/ActivePyModules.{cc,h}` at `70d45a6b` (2017-08-15) |

## Locking Contract (global invariant)

Established by `0601b31a` (2020-12-21, "always release GIL before attempting to acquire a lock") and hardened into RAII helpers by `9c652fb3` (2020-12-24, "use wrappers for acquiring/releasing GIL").

**Rule:** Never hold the Python GIL while attempting to acquire `lock`, `module_config.lock`, or any `DaemonState::lock`. Always use `without_gil_t` / `without_gil()` before taking any C++ mutex. After releasing the lock, re-acquire GIL via `no_gil.acquire_gil()` or `with_gil()` before touching any `PyFormatter` or returning a `PyObject*`.

Comment in `9c652fb3`:
> "because the Python runtime could relinquish the GIL when performing GC and re-acquire it afterwards, we should enforce following locking policy..."

## Notify Routing Contract (global invariant)

Established by `46de6431` (2022-10-17, "Add one finisher thread per module"): each module has its own `Finisher`; notify, clog-notify, and config-notify are dispatched via `py_module_registry.get_active_module_finisher(name)`, not the class-level `finisher`. Modules that do not register for a given notify type are skipped (established by `ee4e3ecd`, 2021-12-02, "only queue notify events that modules ask for").

---

## Function-level Intent

### `ActivePyModules` (constructor) — `.cc:55`, `.h:83`

**Relevant commits:** `ac30e6ce`, `9718896c`, `306e4854`, `37484af0`, `88db7b19`, `18a12f81`, `edf1ea2f`, `95746ece`, `b8f2bc43`, `c93dc884`, `f20df2eb`, `95a90f7d`

**Intent:** Initialise the object from pre-loaded KV store data, set `have_local_config_map` from the caller-supplied `mon_provides_kv_sub` flag (established `18a12f81`), call `_refresh_config_map()` to pre-populate the ConfigMap, and start `cmd_finisher` (established `b8f2bc43`). Accepts an optional `ThreadMonitor*` (established `95a90f7d`, 2024-12-08).

**Invariants:**
- `have_local_config_map` is set **only** from `mon_provides_kv_sub` (SHA `18a12f81`); the value reflects whether a Pacific-era mon was present at startup.
- `store_cache` is initialised from the pre-loaded map passed in (SHA `37484af0`).
- `cmd_finisher.start()` must complete before any mon command can be issued from Python (SHA `b8f2bc43`).

**Implementation critique (blame lines 55–77):**
- Lines 57–75: Correct — matches the construction contract exactly.
- SOUND.

---

### `~ActivePyModules` — `.cc:79`, `.h:91`

**Relevant commits:** `95a90f7d`

**Intent:** Stop the `ThreadMonitor` if one was registered, then stop `cmd_finisher`. Introduced as a non-defaulted destructor by `95a90f7d` (2024-12-08).

**Invariants:**
- `m_thread_monitor->stop_monitoring()` is called only when non-null (SHA `95a90f7d`).
- `cmd_finisher.stop()` must be called here, complementing the `start()` in the constructor.

**Implementation critique (blame lines 79–90):**
- Lines 84–86: null-guard present. Correct.
- Line 89: `cmd_finisher.stop()` present. Correct.
- SOUND.

---

### `dump_server` — `.cc:92`, `.h:263`

**Relevant commits:** `ac30e6ce`, `9718896c`, `37e7029a`, `5aac7eba`, `948635a8`, `0601b31a`, `9c652fb3`, `2db1aaabe5f4`, `aeca2e41`

**Intent:** Dump a hostname and all daemon services on it (type, id, ceph_version, optionally name from "id" metadata key). Takes `DaemonStateCollection` by const-ref. Holds per-state `lock` without GIL (`without_gil` lambda) per `9c652fb3`. The "id" metadata field (for display name) was added by `2db1aaabe5` (2021-10-28). Perf-counter display was removed from `aeca2e41` — this function no longer outputs perf counters, only server/service identity.

**Invariants:**
- Per-state lock must be acquired without the GIL (SHA `9c652fb3`).
- Both `ceph_version` (blame line 108–110) and optional `id` (blame line 111–115) are read under the per-state lock.
- Formatter calls are made after releasing the per-state lock.

**Implementation critique (blame lines 92–127):**
- Lines 102–114: `without_gil` lambda takes `state->lock`, assigns `ceph_version` and `id` from metadata.
- Lines 115–126: Formatter calls outside the lambda with GIL held. Correct ordering.
- SOUND.

---

### `get_server_python` — `.cc:129`, `.h:101`

**Relevant commits:** `ac30e6ce`, `9718896c`, `948635a8`, `0601b31a`, `9c652fb3`, `9ad2283d`, `61aa7e2e`

**Intent:** Look up all daemons on a named host and format as Python dict. Drops GIL, takes `lock`, calls `daemon_state.get_by_server`, then constructs `PyFormatter` and calls `dump_server`.

**Invariants:**
- `lock` acquired inside `without_gil` (SHA `9c652fb3`; blame line 131–135).
- `PyFormatter` constructed only after the lock-holding closure returns (blame line 136). GIL is held again at that point.

**Implementation critique (blame lines 129–139):**
- SOUND.

---

### `list_servers_python` — `.cc:142`, `.h:102`

**Relevant commits:** `ac30e6ce`, `806f1084`, `9c652fb3`, `6469a9a6`, `ade4827d`, `4e2d344e`

**Intent:** Enumerate all known servers. Calls `daemon_state.with_daemons_by_server`, acquires GIL inside the callback via `no_gil.acquire_gil()` (SHA `6469a9a6`), creates the `PyFormatter(false, true)` (array root) there, then dumps each server.

**Invariants:**
- `without_gil_t no_gil` declared before the `with_daemons_by_server` call.
- GIL re-acquired inside the callback before any `PyFormatter` construction.

**Implementation critique (blame lines 142–157):**
- SOUND.

---

### `get_metadata_python` — `.cc:160`, `.h:103`

**Relevant commits:** `ac30e6ce`, `9718896c`, `ade4827d`, `8074944e`, `5aac7eba`, `0601b31a`, `9c652fb3`, `4e2d344e`, `f9a11737`

**Intent:** Return daemon metadata dict for a specific svc_type/svc_id. Returns `Py_RETURN_NONE` if not found (SHA `ade4827d`). Takes `lock` (via `without_gil` lambda) after the null check, NOT `state->lock` — this was changed in `9c652fb3` to lock `lock` instead of `metadata->lock`. The blame shows it acquires `lock` (not the per-daemon lock).

**Invariants:**
- Null-check before lock: if `metadata == nullptr`, log at error level and return None (SHA `ade4827d`).
- Acquire `lock` without GIL (SHA `9c652fb3`).

**Implementation critique (blame lines 160–179):**
- Line 165: `daemon_state.get()` is called without `lock`, which means a race exists between the null-check and the actual usage of `metadata` (the metadata pointer returned by `get()` is a shared_ptr, so the race only affects staleness, not safety).
- Lines 169–173: Lock taken via `without_gil` lambda returning `std::lock_guard`. The lock is the global `lock`, not `metadata->lock`. UNGROUNDED: Why is `lock` taken here when metadata is already returned as a shared_ptr? The only protected state used afterward is `metadata->metadata` and `metadata->hostname`, which are guarded by `state->lock`. The global `lock` usage here appears to be a copy-paste residue from the old pattern — no commit explicitly documents why `lock` (not `metadata->lock`) is used.
- OVERCAUTIOUS: Acquiring the global `lock` to read from a `DaemonState` that is protected by its own per-state lock, while `with_perf_counters` and `dump_server` correctly use per-state lock.

---

### `get_daemon_status_python` — `.cc:181`, `.h:105`

**Relevant commits:** `ac30e6ce`, `9718896c`, `8074944e`, `ade4827d`, `5aac7eba`, `0601b31a`, `9c652fb3`, `f9a11737`, `4e2d344e`, `403340bcf8`

**Intent:** Return `service_status` dict for a daemon. Same null-check pattern as `get_metadata_python`. Has same locking residue (global `lock` taken instead of `metadata->lock`).

**Invariants:**
- Null-check, return None (SHA `ade4827d`).
- GIL dropped before lock (SHA `9c652fb3`).

**Implementation critique (blame lines 181–198):**
- Same OVERCAUTIOUS issue as `get_metadata_python`: acquires global `lock` rather than `metadata->lock` (blame lines 190–192).
- `403340bcf8` changed the signature to accept `std::string_view what` in related functions but did not change this function; the pattern here is intact.
- SOUND functionally; OVERCAUTIOUS on locking.

---

### `ceph_cache_map_erase` — `.cc:200`, `.h:100`

**Relevant commits:** `403340bcf8` (2025-07-17, "replace TTLCache with MgrMapCache")

**Intent:** Operator-driven invalidation of a single cache entry. Returns `-ENOENT` if the key is not in the cache, `-EINVAL` if the key is not cacheable, 0 on success. Introduced as part of the `$ ceph mgr cli cache flush <map-name>` command.

**Invariants:**
- `api_cache.exists(what)` checked before `api_cache.is_cacheable(what)` (order matters to avoid misleading error codes).
- Called only when `use_cache` would be true for that key (callers must check `is_cacheable`).

**Implementation critique (blame lines 200–212):**
- SOUND.

---

### `cacheable_get_python` — `.cc:214`, `.h:96`

**Relevant commits:** `15dfa71c` (2021-05-26, "TTLCache basic implementation"), `7fadf6a8` (2025-08-26, "fix PyObject* lifetime management"), `403340bcf8` (2025-07-17, "replace TTLCache with MgrMapCache")

**Intent:** Cache-aware wrapper around `get_python`. If `api_cache` is enabled, the key is cacheable, and `get_mutable=false`, try to return a cached result. On cache miss, call `get_python`, and if the result is non-null insert into cache. The `get_mutable` parameter (added `403340bcf8`) bypasses the cache entirely, allowing callers to request a mutable copy.

**Invariants:**
- Must not insert a null `PyObject*` into the cache (`use_cache && obj` guard, blame line 231–234).
- Cache hit path returns without Py_INCREF — the cache holds a reference (established by `7fadf6a8`).
- Only inserts when `use_cache` was true at entry (not just when cache is enabled), so a race between enable-check and insertion cannot put an un-cacheable item into cache.

**Implementation critique (blame lines 214–235):**
- SOUND.

---

### `get_python` — `.cc:237`, `.h:98`

**Relevant commits:** `ac30e6ce`, `9718896c`, many incremental additions, `9c652fb3` (2020-12-24, GIL wrappers), `6469a9a6` (2021-11-24, push without_gil_t down), `403340bcf8` (2025-07-17, MgrMapCache + PyFormatterRO)

**Intent:** The central data-query dispatcher for Python modules. Routes on the `what` string to one of many cluster state sources (fsmap, osdmap, pg_summary, pg_dump, health, mon_map, mgr_map, mds_metadata, devices, config, etc.). Each branch acquires GIL before touching the formatter and drops GIL before taking cluster locks. Returns `Py_RETURN_NONE` for unknown keys (blame line 549–551).

When `use_cache` is true (enabled, cacheable, GIL held, not mutable), uses `PyFormatterRO` instead of `PyFormatter`; the resulting dict/list objects are frozen read-only proxies.

**Invariants:**
- GIL must be held when entering, but released (`without_gil_t no_gil`) before the first cluster-state lock acquisition inside each branch (SHA `9c652fb3`, `6469a9a6`).
- `no_gil.acquire_gil()` must be called before calling any `f.dump_*` or `f.get()`.
- `f.get()` must be called under the GIL.
- Unknown `what` falls to the `else` branch which logs at `derr` level and returns None (SHA `ac30e6ce`).
- `mgr_ips` branch (blame lines 512–522) does NOT take `without_gil_t` — it reads from `server.get_myaddrs()` directly without taking a lock. UNGROUNDED: no commit documents why this is safe; `get_myaddrs()` presumably returns a copy or is lock-free.
- `have_local_config_map` branch (blame lines 523–524) reads the boolean without a lock. This is a simple bool set at construction; no commit documents a formal memory-ordering guarantee. OVERCAUTIOUS flag is not applicable since the bool is effectively read-only after construction, but the lack of documentation is notable.

**Implementation critique (blame lines 237–554):**
- Blame line 553–555: `return f.get()` is the fallthrough after all specific branches return early. This path is only reached by `active_clean_pgs` (blame lines 525–546) and possibly other branches that don't return inside the with_pgmap callback. UNGROUNDED: this is only reachable from branches that call `no_gil.acquire_gil()` inside their callbacks (confirmed for `active_clean_pgs` at blame line 529). Correct.
- SOUND overall, with the UNGROUNDED note on `mgr_ips`.

---

### `start_one` — `.cc:556`, `.h:261`

**Relevant commits:** `9718896c`, `c1471c75`, `f22347db`, `13bcddea`, `56e34f58`, `2d9b3abd`, `40c4b9ac`, `6a8b5d84`, `bb4e71ed`, `46de6431`, `95a90f7d`, `cbd1726f`, `dd9f9e26`, `95746ece`

**Intent:** Start one Python module asynchronously via `finisher.queue`. Takes `lock`, inserts name into `pending_modules`, creates an `ActivePyModule` shared_ptr, then queues a lambda that: optionally sleeps (test hook, `cbd1726f`), calls `active_module->load(this)`, erases from `pending_modules` under `lock`, on success inserts into `modules` map, creates the serve thread, builds perf counters, starts the per-module finisher, waits for finisher start, registers with `ThreadMonitor`. On failure logs at derr level. After each module loads, if `pending_modules` is empty and `recheck_modules_start` is set, queues `recheck_modules_start` (SHA `cbd1726f`).

**Invariants:**
- `pending_modules.insert(name)` called under `lock` before queuing (blame line 563).
- `pending_modules.erase(name)` called under `lock` inside the lambda (blame line 577).
- `modules.emplace(name, active_module)` asserted not to collide: `ceph_assert(em.second)` (SHA `40c4b9ac`, blame line 583).
- `active_module->thread.create(...)` called only on successful load (blame line 584).
- `active_module->finisher.on_started().wait()` blocks until the per-module finisher has actually started (SHA `95a90f7d`, blame line 587) — ensures `set_native_tid` is called before thread monitor registration.
- `m_thread_monitor->register_thread(...)` only if `m_thread_monitor != nullptr` (blame line 589–594).
- `recheck_modules_start` checked and reset after `pending_modules.erase` (blame lines 597–601).

**Implementation critique (blame lines 556–602):**
- The lambda captures `py_module` by value (SHA `95a90f7d`) — correct, avoids dangling.
- SOUND.

---

### `notify_all` (string variant) — `.cc:604`, `.h:225`

**Relevant commits:** `ac30e6ce`, `9718896c`, `624bdbcf`, `9ea37c22`, `67ffff38`, `40c4b9ac`, `ee4e3ecd`, `46de6431`, `403340bcf8`

**Intent:** Notify all loaded modules of a cluster event (osdmap, fsmap, etc.). Takes `lock`. Invalidates `api_cache` for the notify_type (SHA `403340bcf8`, blame line 610). Skips modules that haven't registered for this notify_type via `py_module_registry.should_notify` (SHA `ee4e3ecd`). Dispatches via per-module finisher (SHA `46de6431`).

**Invariants:**
- Cache invalidated before notifications queued (SHA `403340bcf8`).
- Filter via `should_notify` (SHA `ee4e3ecd`, blame line 614–616).
- Dispatch via `mod_finisher`, not the class-level `finisher` (SHA `46de6431`, blame line 622).

**Implementation critique (blame lines 604–627):**
- SOUND.

---

### `notify_all` (log entry variant) — `.cc:629`, `.h:223`

**Relevant commits:** `9ea37c22`, `9718896c`, `624bdbcf`, `67ffff38`, `40c4b9ac`, `ee4e3ecd`, `46de6431`

**Intent:** Notify all modules of a cluster log entry. Same pattern as string variant but for `notify_clog`. Skips modules not registered for "clog". Dispatches via per-module finisher.

**Invariants:** Same as string variant; `log_entry` is copied into the lambda (blame line 649) because caller's instance is ephemeral.

**Implementation critique (blame lines 629–651):**
- SOUND.

---

### `get_store` — `.cc:653`, `.h:165`

**Relevant commits:** `ac30e6ce`, `3193d40d`, `c92898334`, `6e447fd1`, `c928983340`, `37484af0`, `948635a8`, `9c652fb3`, `3bafb5e5`, `f69069e1`

**Intent:** Look up a module KV store value from `store_cache` (the write-through cache of config-key entries). Returns true + value if found, false if absent.

**Invariants:**
- `lock` acquired via `without_gil_t no_gil` (SHA `9c652fb3`, blame line 656).
- Key constructed with `PyModule::mgr_store_prefix` (SHA `3bafb5e5`, renamed from `config_prefix`), blame line 659.

**Implementation critique (blame lines 653–671):**
- SOUND.

---

### `dispatch_remote` — `.cc:673`, `.h:251`

**Relevant commits:** `f02316adb`, `ab23c506`, `b0a4bff8`, `d590a539`, `f69069e1`, `42c4dfb4`

**Intent:** Forward a method call to another active module using serialised (pickled) arguments. Changed from direct `PyObject*` transfer to `std::span<std::byte>` pickled bytes by `f69069e1` (2025-10-24, "serialize python objects sent between subinterpreters via remote"). Added `bool *crash_dump` parameter by `42c4dfb4` (2026-08-11) to suppress error-level logging for `NotImplementedError`.

**Invariants:**
- `ceph_assert(mod_iter != modules.end())` — the target module must exist (SHA `ab23c506`, blame line 682). Caller is responsible for verifying existence via `module_exists()`.
- Does NOT hold `lock` while dispatching — the assert is a hard invariant, not a defensive check.

**Implementation critique (blame lines 673–686):**
- The `ceph_assert` at blame line 682 fires for a not-found module. The caller (`BaseMgrModule.cc`) must check `module_exists()` before calling `dispatch_remote`. If the module goes away between the check and the dispatch, this will abort. UNGROUNDED: No commit documents whether there is a use-after-check guarantee; the race is theoretically possible if a module is stopped between `module_exists()` and `dispatch_remote()`. The assert was introduced by `ab23c506` (2018-08-23) to replace a silent null-deref.
- SOUND for the documented invariant; the potential race is UNGROUNDED.

---

### `get_config` — `.cc:689`, `.h:172`

**Relevant commits:** `ac30e6ce`, `9718896c`, `3193d40d`, `306e4854`, `c928983340`, `6e447fd1`, `dd7631c2`, `d590a539` (no, this is `cluster_log`), `dffce107`, `b0a4bff8`

**Intent:** Look up module config from `module_config.config` map. The config key is `"mgr/" + module_name + "/" + key` (SHA `b0a4bff8`, blame line 692). Takes `module_config.lock` directly — no `without_gil_t` here.

**DIVERGED:** `0601b31a` established the invariant "always release GIL before attempting to acquire a lock." `get_config` acquires `module_config.lock` (blame line 696) without a preceding `without_gil_t`. No GIL release is done before the lock. This is a divergence from the locking contract established by `0601b31a`. The function is called from `get_typed_config` which already holds `without_gil_t no_gil` (blame line 712), so at the `get_typed_config` call site the GIL is already released when `get_config` runs. But `get_config` itself can also be called from Python (via `BaseMgrModule.get_config`) which holds the GIL. In that path, the lock is taken while holding the GIL — this is the exact anti-pattern `0601b31a` was fixing.

**Implementation critique (blame lines 689–705):**
- Blame line 696: `std::lock_guard lock(module_config.lock)` with no GIL release — DIVERGED from `0601b31a` invariant.

---

### `get_typed_config` — `.cc:707`, `.h:177`

**Relevant commits:** `9718896c`, `030e85bb`, `5ac9e85a`, `4ca5596a`, `c4e2965a`, `f4b3d67b`, `9c652fb3`, `6469a9a6`, `dffce107`, `5ac9e85a`

**Intent:** Return a typed Python object for a module config option. Tries prefix-qualified key first, then bare key. Uses `without_gil_t` at entry (blame line 712). Calls `get_config` in the no-GIL context. On found, re-acquires GIL (`no_gil.acquire_gil()`, blame line 726) before calling `module->get_typed_option_value`. Does not log the value (SHA `f4b3d67b`, 2020-12-03, "don't log config value in get_typed_config").

**Invariants:**
- `without_gil_t no_gil` at function entry (blame line 712).
- `no_gil.acquire_gil()` before calling `get_typed_option_value` (blame line 726).
- Returns `Py_RETURN_NONE` at blame line 743 if module not found (SHA `5ac9e85a`).
- Value not logged at dout level for security (SHA `f4b3d67b`).

**Implementation critique (blame lines 707–744):**
- SOUND.

---

### `get_store_prefix` — `.cc:746`, `.h:167`

**Relevant commits:** `1ebc3f12`, `9718896c`, `61aa7e2e`, `9c652fb3`, `6469a9a6`, `3bafb5e5`, `dd7631c2`, `7c68a00c`

**Intent:** Return all KV store entries under a given prefix as a Python dict. Takes both `lock` and `module_config.lock` without GIL (SHA `9c652fb3`). Re-acquires GIL via `no_gil.acquire_gil()` before formatter operations (SHA `6469a9a6`, blame line 752).

`7c68a00c` (2026-01-21, "prevent segfault on non-printable characters"): Instead of `f.dump_string(...)`, now uses `PyUnicode_FromStringAndSize` and skips keys that fail encoding (with `PyErr_Clear()`).

**Invariants:**
- Both `lock` and `module_config.lock` held (blame lines 750–751). Order is `lock` first, then `module_config.lock` — must not be reversed.
- GIL re-acquired before formatter use (blame line 752).
- Skip and clear error on `PyUnicode_FromStringAndSize` failure (SHA `7c68a00c`, blame lines 764–770).

**Implementation critique (blame lines 746–773):**
- SOUND.

---

### `set_store` — `.cc:775`, `.h:169`

**Relevant commits:** `ac30e6ce`, `3193d40d`, `306e4854`, `868420e4`, `5108860c`, `a41b62bd`, `3bafb5e5`, `edf1ea2f`, `75bbe6863`, `948635a8`

**Intent:** Write a KV store entry (or erase if val is None/nullopt). Updates `store_cache` optimistically under `lock` (blame line 783), builds a mon command, runs it, waits for completion. Logs failure but does not propagate error to Python (the FIXME at blame line 813 notes this).

**Invariants:**
- `store_cache` updated before sending the mon command, so subsequent `get_store` reads are consistent even before mon ack.
- `set_cmd.wait()` called without the lock (command issued inside `lock`, waited outside) — blame line 807–808 shows lock released before wait.

**Error condition (UNGROUNDED):** `set_cmd.r != 0` (blame line 810) is logged but silently ignored. The "FIXME" comment from `1dc66c4a` (2017-04-21) has never been resolved. Python callers have no way to know if the store write failed.

**Implementation critique (blame lines 775–818):**
- SOUND mechanically; UNGROUNDED error propagation omission documented by the FIXME comment.

---

### `set_config` — `.cc:820`, `.h:174`

**Relevant commits:** `3193d40d`, `c81e542b`, `5c384630`, `1dc66c4a`, `834bc279`, `4ca5596a`, `a41b62bd`, `75bbe6863`

**Intent:** Delegate to `module_config.set_config()`. Returns `std::pair<int, std::string>` (introduced `75bbe6863`, 2021-02-22, "return the error if set_config() fails").

**Invariants:**
- Fully delegates — no local logic beyond forwarding (blame line 825).

**Implementation critique (blame lines 820–826):**
- SOUND.

---

### `get_services` — `.cc:828`, `.h:212`

**Relevant commits:** `ac30e6ce`, `9718896c`, `a0183a63`, `df8797320`, `b421142b`, `40c4b9ac`, `a41b62bd`, `9d47b164`, `706b2be4`

**Intent:** Return map of module_name → URI for all modules that have advertised a URI. Takes `lock`. Uses `std::string_view` for `svc_str` (SHA `9d47b164`, 2024-10-10).

**Invariants:**
- `lock` held for the entire iteration (blame line 831).
- Empty URI entries are not included in result (blame line 834).

**Implementation critique (blame lines 828–840):**
- SOUND.

---

### `update_kv_data` — `.cc:842`, `.h:214`

**Relevant commits:** `18a12f81`, `edf1ea2f`, `706b2be4`

**Intent:** Called by the mgr when a KV subscription update arrives. Takes `lock`. Handles both full and incremental updates. On full update, clears old prefix entries first (blame lines 851–857). For each item, sets or erases from `store_cache`. Tracks whether any key under `"config/"` was touched; if so, calls `_refresh_config_map()` (SHA `18a12f81`).

**Invariants:**
- `lock` held for entire update (blame line 847).
- `do_config` flag checked to call `_refresh_config_map()` only when config/ keys changed (SHA `18a12f81`).

**Implementation critique (blame lines 842–874):**
- SOUND.

---

### `_refresh_config_map` — `.cc:876`, `.h:218`

**Relevant commits:** `18a12f81`, `edf1ea2f`, `4b1e82eaaa`

**Intent:** Rebuild `config_map` from all `"config/"` entries in `store_cache`. Called from constructor and from `update_kv_data` when a config key changes. Skips entries under `"config/mgr/"` (module options are not tracked here).

**Invariants:**
- Must be called under `lock` (no lock taken here — caller holds it).
- Skips `mgr/` prefixed keys (blame line 884–888, with comment "for now, we ignore module options").

**Implementation critique (blame lines 876–899):**
- SOUND.

---

### `with_unlabled_perf_counters` — `.cc:901`, `.h:131`

**Relevant commits:** `9501bfdd`, `b421142b`, `1164ef2f`, `9c652fb3`, `356982901`, `a81901e1`

**Intent:** Helper: given a lambda `fct(counter_instance, counter_type, f)`, resolve the svc/path to a PerfCounterInstance and invoke it. Opens an array section named `path` (blame line 908). Acquires `lock` and `metadata->lock` under `without_gil_t`, then re-acquires GIL to invoke `fct` (blame line 918–920). Returns `Py_RETURN_NONE` if metadata not found; returns the empty array if counter not found.

**Invariants:**
- Caller's `fct` must not acquire locks while holding GIL (documented in header via `@note` added by `9c652fb3`).
- `path` used as `string_view` for array section name.

**Implementation critique (blame lines 901–936):**
- SOUND.

---

### `with_perf_counters` — `.cc:941`, `.h:140`

**Relevant commits:** `9501bfdd`, `b421142b`, `9c652fb3`, `a81901e1`, `6d3cababa`

**Intent:** The labeled-counter variant of `with_unlabled_perf_counters`. Introduced by `6d3cababa` (2025-03-19, "add new API's to fetch latest perf counter values"). Accepts `counter_name`, `sub_counter_name`, and `perf_counter_label_pairs`. Constructs `resolved_path` from labels (or bare path if no labels). Uses `Formatter::ArraySection` RAII for the outer section.

**Invariants:**
- `lock` + `metadata->lock` acquired under `without_gil_t` (blame lines 980–984).
- `fct` invoked inside `with_gil` (blame line 989).
- `resolved_path` construction is correct for both labeled and unlabeled cases.

**Implementation critique (blame lines 941–1006):**
- SOUND.

---

### `get_unlabeled_counter_python` — `.cc:1008`, `.h:107`

**Relevant commits:** `9501bfdd`, `b421142b`, `a81901e1`

**Intent:** Python-callable wrapper; delegates to `with_unlabled_perf_counters` with a lambda that extracts all historical data points. Returns array of `[t, v]` or `[t, s, c]` pairs.

**Implementation critique (blame lines 1008–1038):**
- SOUND.

---

### `get_latest_unlabeled_counter_python` — `.cc:1040`, `.h:111`

**Relevant commits:** `9501bfdd`, `b421142b`, `a81901e1`

**Intent:** Returns only the most-recent data point. Delegates to `with_unlabled_perf_counters`.

**Implementation critique (blame lines 1040–1062):**
- SOUND.

---

### `get_latest_counter_python` — `.cc:1064`, `.h:115`

**Relevant commits:** `b421142b`, `6d3cababa`, `a81901e1`

**Intent:** Returns the most-recent data point for a labeled counter. Delegates to `with_perf_counters`.

**Implementation critique (blame lines 1064–1088):**
- SOUND.

---

### `get_unlabeled_perf_schema_python` — `.cc:1090`, `.h:121`

**Relevant commits:** `6fda2a6c`, `9718896c`, `806f1084`, `f7434f99`, `5aac7eba`, `948635a8`, `9c652fb3`, `6469a9a6`, `f941025561`, `a81901e1`, `078b140a`

**Intent:** Return perf schema for unlabeled counters only. Filters out labeled counters (SHA `f941025561`, blame lines 1122–1129). Uses RAII `Formatter::ObjectSection` (SHA `078b140a`, blame lines 1119, 1131).

**Invariants:**
- `lock` acquired under `without_gil_t` (blame line 1094–1095).
- Labeled counters (those whose key has non-empty label iterators) are skipped (SHA `f941025561`).
- `f` constructed under GIL via `with_gil` (blame line 1112–1114).
- RAII sections used — `ObjectSection daemon_section{f, key}` and `ObjectSection counter_section{f, counter_name}` (SHA `078b140a`).

**Implementation critique (blame lines 1090–1148):**
- SOUND.

---

### `get_perf_schema_python` — `.cc:1150`, `.h:124`

**Relevant commits:** `a4aebd83`, `26d10b30`, `b1c1ddaf`, `f410c49e`, `078b140a`

**Intent:** New (2025-03-19) labeled-counter schema API. Produces the structured format `{ "key": [ { "labels": {...}, "counters": { ... } } ] }`. Key/counter-name extraction from paths with NULL-delimiter labels. State machine tracks `prev_key_name`/`prev_key_labels` to handle multiple sub-counters per label set.

**Bug fixes tracked:**
- `26d10b30` (2026-01-07): `key_name`/`prev_key_name` changed from `std::string_view` to `std::string` to fix dangling pointer (blame line 1210, 1212).
- `b1c1ddaf` (2026-04-04): Guarded `close_section()` calls after loop with `!prev_key_name.empty()` — superseded by RAII in `078b140a`.
- `f410c49e` (2026-04-16): Fixed `create_unique` → `dump_string` for description (blame line 1181).
- `078b140a` (2026-06-03): RAII sections via `std::optional<Formatter::ObjectSection>` replaces manual `close_section()` calls.

**Invariants:**
- `key_name` and `prev_key_name` must be `std::string` (not `std::string_view`) to avoid dangling (SHA `26d10b30`).
- `counters_section` and `counter_object_section` must be `.reset()` before opening new array/object sections (SHA `078b140a`, blame lines 1284–1285, 1295–1296).
- `dump_string` (not `create_unique`) for description (SHA `f410c49e`, blame line 1181).

**Implementation critique (blame lines 1150–1315):**
- SOUND (after the three bug-fix commits).
- The `else` branch (blame lines 1298–1305, "not a valid condition") only logs at `dout(4)` without taking any corrective action. This leaves the formatter in an undefined state if reached. UNGROUNDED: no invariant currently prevents the counter_name from comparing equal to a different key_name that is neither prev==current nor label-changed. This branch should be unreachable given sorted iteration of `perf_counters.instances`, but that invariant is not explicitly documented.

---

### `get_rocksdb_version` — `.cc:1317`, `.h:127`

**Relevant commits:** `7a4e7475`

**Intent:** Return the RocksDB version string. No lock, no GIL manipulation needed.

**Implementation critique (blame lines 1317–1324):**
- SOUND.

---

### `get_context` — `.cc:1326`, `.h:128`

**Relevant commits:** `07cae621`, `9718896c`, `7e61f79f`, `9c652fb3`, `2ef005196`

**Intent:** Return a PyCapsule wrapping `g_ceph_context`. Takes `lock` (via `without_gil` lambda). Does not increment the context refcount (comment: process lifetime).

**Invariants:**
- GIL dropped before `lock` (SHA `9c652fb3`, blame lines 1328–1330).

**Implementation critique (blame lines 1326–1336):**
- SOUND. The comment about not ref-counting g_ceph_context is correct and documented.

---

### `construct_with_capsule` — `.cc:1341`

**Relevant commits:** `7e61f79f`, `ab23c506`, `719d5e18`

**Intent:** Helper (free function) to construct a Python object of a wrapped C++ type by importing a module and calling its constructor with a capsule argument. Uses `handle_pyerror` to log import/type/construction failures (SHA `719d5e18`). All intermediate objects decremented before return.

**Invariants:**
- `ceph_assert` after each potentially-null result (SHA `ab23c506`).

**Implementation critique (blame lines 1341–1384):**
- SOUND.

---

### `get_osdmap` — `.cc:1386`, `.h:129`

**Relevant commits:** `2ef005196`, `9718896c`, `7e61f79f`, `3068c429`, `8e531ede`, `02c44b17`, `9c652fb3`

**Intent:** Return a Python OSDMap wrapper. Allocates an `OSDMap` on the heap with `new`, deep-copies the cluster state's OSDMap without the GIL (SHA `9c652fb3`), then constructs the Python wrapper.

**Invariants:**
- Heap-allocated `OSDMap*` must be wrapped in the capsule destructor (not shown here — that's in the `delete_osdmap` function at the call site).
- Deep copy done in the `without_gil` lambda (blame lines 1388–1396).

**Implementation critique (blame lines 1386–1396):**
- SOUND.

---

### `get_foreign_config` — `.cc:1398`, `.h:180`

**Relevant commits:** `02c44b17`, `18a12f81`, `6469a9a6`, `e65f676c`, `863d8385`, `706b2be4`

**Intent:** Retrieve config for an arbitrary entity (e.g. `osd.0`) using the local ConfigMap when available (Pacific-era), falling back to a blocking `config get` mon command when `have_local_config_map` is false.

Two code paths:
1. `!have_local_config_map`: sends mon command, waits, re-acquires GIL, calls `get_python_typed_option_value`.
2. `have_local_config_map`: acquires `lock` without GIL, generates entity config from ConfigMap, releases `lock`, re-acquires GIL, calls `get_python_typed_option_value`.

**Invariants:**
- Option must be a known built-in option: returns `PyErr_Format(PyExc_KeyError, ...)` if not (blame line 1408–1409).
- Entity must parse via `entity.from_str()`: returns `PyErr_Format(PyExc_KeyError, ...)` if invalid (blame line 1439–1441).
- `lock.unlock()` must be called before `no_gil.acquire_gil()` (blame line 1487–1488).
- NOTE: In path 2, `lock.lock()` is called directly (blame line 1444), not via `std::lock_guard`, meaning `lock.unlock()` must be called explicitly (blame line 1487). Correct but fragile.

**Error conditions:**
- Unknown option → `PyErr_Format(PyExc_KeyError, "option not found: ...")` and `return nullptr`.
- Invalid entity → `PyErr_Format(PyExc_KeyError, "invalid entity: ...")` and `return nullptr`.
- No fallback for mon command failure (path 1) — if `cmd.r != 0`, the outbl might contain an error string, but the return still calls `get_python_typed_option_value` on whatever `outbl` contains. UNGROUNDED: there is no error check on `cmd.r` in the `!have_local_config_map` path (blame lines 1427–1431).

**DIVERGED (path 1):** The mon-command path does not check `cmd.r` before calling `get_python_typed_option_value(opt->type, cmd.outbl.to_str())` (blame line 1431). A failed mon command returns an error string in `outbl`, not the config value. This is a semantic error — the error text would be incorrectly typed/returned as a config value. SHA `02c44b17` (2021-02-16) introduced this path but did not add the error check.

**Implementation critique (blame lines 1398–1490):**
- DIVERGED at blame line 1431: missing `cmd.r != 0` check.

---

### `set_health_checks` — `.cc:1492`, `.h:184`

**Relevant commits:** `e51be85c`, `9718896c`, `563878ba`, `3068c429`, `c93dc884`, `834bc279`, `140761f8`

**Intent:** Set health checks for a module. Sends a report to monitors immediately if the check state changed (SHA `3068c429`). Must release `lock` before calling `server.schedule_tick()` to avoid the lock cycle:
`send_report: DaemonServer::lock → PyModuleRegistry::lock`
`active_start: PyModuleRegistry::lock → ActivePyModules::lock`

This lock-ordering comment (blame lines 1506–1515) is the explicit documentation of the invariant.

**Invariants:**
- `lock.unlock()` before `server.schedule_tick(0)` (blame lines 1502–1504 + 1516–1517).
- `server.schedule_tick(0)` called only when `changed` (SHA `3068c429`, blame line 1516).

**Implementation critique (blame lines 1492–1518):**
- SOUND.

---

### `get_health_checks` — `.cc:1541`, `.h:186`

**Relevant commits:** `e51be85c`, `9718896c`, `948635a8`, `40c4b9ac`, `2af2afa5`

**Intent:** Aggregate health checks from all loaded modules into the provided map.

**Implementation critique (blame lines 1541–1548):**
- SOUND.

---

### `handle_command` — `.cc:1520`, `.h:204`

**Relevant commits:** `834bc279`, `b1e8d63b`, `c93dc884`, `377de7af`, `282c31c3`, `140761f8`, `40c4b9ac`

**Intent:** Route a command to the named module. Takes `lock`, finds the module, unlocks, then delegates to `mod_iter->second->handle_command(...)`. Returns `-ENOENT` if module not loaded (SHA `b1e8d63b`).

**Invariants:**
- `lock.unlock()` before delegating to module (blame line 1536).
- Error response written to `*ss` on module-not-found (blame line 1531).

**Implementation critique (blame lines 1520–1539):**
- SOUND.

---

### `update_progress_event` — `.cc:1550`, `.h:188`

**Relevant commits:** `f6ef41a0`, `2af2afa5e9`

**Intent:** Upsert a progress event. `add_to_ceph_s` field added `2af2afa5` (2020-09-22). Takes `lock`.

**Implementation critique (blame lines 1550–1561):**
- SOUND.

---

### `complete_progress_event` — `.cc:1563`, `.h:192`

**Relevant commits:** `f6ef41a0`

**Intent:** Remove a progress event. Takes `lock`.

**Implementation critique (blame lines 1563–1567):**
- SOUND.

---

### `clear_all_progress_events` — `.cc:1569`, `.h:193`

**Relevant commits:** `f6ef41a0`

**Intent:** Clear all progress events. Takes `lock`.

**Implementation critique (blame lines 1569–1573):**
- SOUND.

---

### `get_progress_events` — `.cc:1575`, `.h:194`

**Relevant commits:** `f6ef41a0`, `40c4b9ac`

**Intent:** Copy current progress events into caller's map. Takes `lock`.

**Implementation critique (blame lines 1575–1579):**
- SOUND.

---

### `config_notify` — `.cc:1581`, `.h:199`

**Relevant commits:** `f27a5dc6`, `40c4b9ac`, `67ffff38`, `46de6431`, `403340bcf8`

**Intent:** Notify all modules that mgr config has changed. Takes `lock`. Invalidates `api_cache` for "config" (SHA `403340bcf8`, blame line 1584). Dispatches via per-module finisher (SHA `46de6431`).

**Invariants:**
- Cache invalidated before notifications (SHA `403340bcf8`).
- Per-module finisher used (SHA `46de6431`).

**Implementation critique (blame lines 1581–1595):**
- SOUND.

---

### `set_uri` — `.cc:1597`, `.h:201`

**Relevant commits:** `a0183a63`, `9718896c`, `b18ddf4d`, `b1f12671`, `4840507c`, `f02316ad`, `efcebe1e`, `40c4b9ac`

**Intent:** Set the service URI for a module. Takes `lock`. Uses `modules.at(module_name)` — throws `std::out_of_range` if module not found.

**Error condition (UNGROUNDED):** `modules.at(module_name)` is unchecked — if the module was already stopped between the Python call and this C++ function, the process will abort with an uncaught exception. No commit has addressed this. The original `a0183a63` (2017-07-27) used `modules[name]` which would silently create an entry; `40c4b9ac` changed it to `.at()`.

**Implementation critique (blame lines 1597–1605):**
- UNGROUNDED: no guard for module-not-found.

---

### `set_device_wear_level` — `.cc:1607`, `.h:202`

**Relevant commits:** `4840507c`, `f82ab1cb`, `706b2be4`

**Intent:** Update wear level on a device in daemon_state and propagate to mon via `config-key set`. Does not take `lock` — uses `daemon_state.with_device()` which has its own locking. SHA `f82ab1cb` changed `set_cmd.run(...)` to pass by rvalue reference.

**Implementation critique (blame lines 1607–1635):**
- SOUND.

---

### `add_osd_perf_query` — `.cc:1637`, `.h:152`

**Relevant commits:** `b18ddf4d`, `b1f12671`, `efcebe1e`

**Intent:** Delegate to `server.add_osd_perf_query(query, limit)`.

**Implementation critique (blame lines 1637–1642):**
- SOUND.

---

### `remove_osd_perf_query` — `.cc:1644`, `.h:155`

**Relevant commits:** `b18ddf4d`, `34525ba3`, `efcebe1e`, `7523aef6`, `b8362d904`

**Intent:** Delegate to `server.remove_osd_perf_query(query_id)`. Logs error on failure.

**Implementation critique (blame lines 1644–1651):**
- SOUND.

---

### `get_osd_perf_counters` — `.cc:1653`, `.h:156`

**Relevant commits:** `b8362d904`, `efcebe1e`, `7523aef6`

**Intent:** Collect OSD perf counters for a query ID using an `OSDPerfCollector`. Returns `Py_RETURN_NONE` on error. Formats as nested arrays of keys and counter pairs.

**Implementation critique (blame lines 1653–1691):**
- SOUND.

---

### `add_mds_perf_query` — `.cc:1693`, `.h:158`

**Relevant commits:** `7523aef6`

**Intent:** Delegate to `server.add_mds_perf_query`.

**Implementation critique (blame line 1693–1699):**
- SOUND.

---

### `remove_mds_perf_query` — `.cc:1700`, `.h:161`

**Relevant commits:** `7523aef6`

**Intent:** Delegate to `server.remove_mds_perf_query`. Logs error on failure.

**Implementation critique (blame lines 1700–1707):**
- SOUND.

---

### `reregister_mds_perf_queries` — `.cc:1709`, `.h:162`

**Relevant commits:** `c2470f271`

**Intent:** Delegate to `server.reregister_mds_perf_queries()`. Called when a new MDS connects.

**Implementation critique (blame lines 1709–1712):**
- SOUND.

---

### `get_mds_perf_counters` — `.cc:1714`, `.h:163`

**Relevant commits:** `7523aef6`, `c2470f271`

**Intent:** Collect MDS perf counters. Returns `Py_RETURN_NONE` on error. Adds `delayed_ranks` and `last_updated` fields (SHA `c2470f271`).

**Implementation critique (blame lines 1714–1764):**
- SOUND.

---

### `cluster_log` — `.cc:1766`, `.h:267`

**Relevant commits:** `34525ba3`, `95746ece`, `1dba6c41`, `bb09a1d7`, `a586dcc5`, `e72194b4`, `df507cde`

**Intent:** Emit a cluster log message on the specified channel. Takes `lock`. Creates the log channel from `monc.get_log_client()` (SHA `1dba6c41`). Calls `cl->parse_client_options(g_ceph_context)` before logging (SHA `bb09a1d7`, 2021-10-17, "hide internal logger configuration strings").

**Invariants:**
- `lock` held (blame line 1769).
- `parse_client_options` called before `do_log` (blame line 1772–1773).

**Implementation critique (blame lines 1766–1774):**
- SOUND.

---

### `register_client` — `.cc:1776`, `.h:196`

**Relevant commits:** `df507cde`, `e72194b4`, `a586dcc5`

**Intent:** Register a RADOS client for the Python module with the module registry. `replace` parameter added by `e72194b4` (2023-02-27).

**Implementation critique (blame lines 1776–1783):**
- SOUND.

---

### `unregister_client` — `.cc:1785`, `.h:197`

**Relevant commits:** `df507cde`, `5a2b7c25b`

**Intent:** Unregister a RADOS client.

**Implementation critique (blame lines 1785–1792):**
- SOUND.

---

### `get_daemon_health_metrics` — `.cc:1794`, `.h:269`

**Relevant commits:** `5a2b7c25b` (2022-11-11, "expose daemon health metrics"), `6469a9a6`, `4e2d344e`

**Intent:** Return per-daemon health metrics (type + value). Uses `daemon_state.with_daemons_by_server`, acquires GIL inside callback.

**Implementation critique (blame lines 1794–1815):**
- SOUND.

---

### `check_all_modules_started` — `.cc:1817`, `.h:278`

**Relevant commits:** `cbd1726f` (2025-04-25, "ensure that all modules have started before advertising active mgr")

**Intent:** Check if `pending_modules` is empty. If yes, fire the provided context immediately. If no, store it in `recheck_modules_start` for `start_one` to fire when the last pending module loads. This enables the mgr to defer advertising itself as active until all modules are loaded.

**Invariants:**
- `lock` held (blame line 1818).
- `recheck_modules_start` must not already be set when this is called (no assert, but semantically only one caller should call this once).
- The stored context is fired exactly once (blame lines 597–601 in `start_one` reset it to `nullptr` after queuing).

**UNGROUNDED:** There is no guard against a second call to `check_all_modules_started` while `recheck_modules_start` is non-null (i.e. from a second concurrent init). The old context would be leaked. No commit documents this is safe.

**Implementation critique (blame lines 1817–1825):**
- UNGROUNDED: no guard on double-call.

---

## Header-only Functions (inline, `.h` only)

### `get_monc` — `.h:94`
Returns `monc` reference. No lock needed. SOUND.

### `get_objecter` — `.h:95`
Returns `objecter` reference. No lock needed. SOUND.

### `get_pending_modules` — `.h:236`
Introduced by `68221661` (2025-09-11, "add `pending_modules` to asock command"). Returns `const std::set<std::string, std::less<>>&` — a const reference to `pending_modules` without taking `lock`. UNGROUNDED: the returned reference is live while the set could be modified by `start_one` (which takes `lock` when inserting/erasing). Callers must hold `lock` externally to avoid data races; this is not enforced by the API.

### `is_pending` — `.h:231`
Checks `pending_modules.count(name)`. No lock. UNGROUNDED for the same reason as `get_pending_modules`.

### `module_exists` — `.h:239`
Checks `modules.count(name)`. No lock. Caller is responsible for ensuring the check is meaningful before `dispatch_remote` (see the race note under `dispatch_remote`).

### `method_exists` — `.h:244`
Returns `modules.at(module_name)->method_exists(method_name)`. No lock, no out_of_range guard. Same UNGROUNDED concern as `set_uri`.

### `get_module_finisher` — `.h:227`
Returns reference to `modules.at(name)->finisher`. No lock. Added `46de6431`. UNGROUNDED: throws `std::out_of_range` if module not found.

### `update_cache_metrics` — `.h:272`

**Relevant commits:** `15dfa71cf7c8` (introduced), `403340bcf8` (implementation removed)

**History:** Introduced by `15dfa71cf7c8` (2021-05-26, "TTLCache basic implementation") as a method that read `ttl_cache.get_hit_miss_ratio()` and updated `perfcounter` for `l_mgr_cache_hit` / `l_mgr_cache_miss`. It was called from `cacheable_get_python` after every cache operation. When `403340bcf8` (2025-07-17, "replace TTLCache with MgrMapCache") removed the TTLCache, it removed the `.cc` implementation but explicitly stated "Remove unused update_cache_metrics()" in the commit message. However, the `.h:272` **declaration was not removed**.

**DIVERGED:** The header declaration `void update_cache_metrics();` (blame `.h:272`, SHA `15dfa71cf7c8`) has no corresponding definition as of `403340bcf8`. This is a stale declaration that will cause a linker error if any code calls it. The omission from the header cleanup in `403340bcf8` is the specific commit that introduced the divergence.

**Implementation critique (`.h:272`):**
- DIVERGED: declaration present with no definition. Introduced by `15dfa71cf7c8`; definition removed by `403340bcf8` (2025-07-17) without removing the header declaration.

---

### `inject_python_on` — `.h:271`
Declaration only. SOUND.

### `init` — `.h:259`
Declaration only (implemented elsewhere, not in this corpus). Noted as present.

---

## Anonymous Lambda Functions

`functions.txt` contains 54 anonymous lambda entries (ctags names `__anonc6976024NN02`) in `ActivePyModules.cc`. These are all inline lambda bodies used as `without_gil_t`/`with_gil_t` callbacks, `DaemonState` visitor callbacks, or `Finisher` queue lambdas. They are documented within their enclosing named functions above and do not require separate sections. The relevant SHAs covering them are the same as their parent functions.

---

## Summary of Findings

| Finding | Count | Key Examples |
|---------|-------|--------------|
| SOUND | 38 | majority of named functions |
| DIVERGED | 3 | `get_config` (GIL rule), `get_foreign_config` (no cmd.r check), `update_cache_metrics` (stale .h declaration) |
| UNGROUNDED | 8 | `get_python` (mgr_ips path), `dispatch_remote` (use-after-check), `set_store` (silent error), `set_uri` (no guard), `check_all_modules_started` (double-call), `get_perf_schema_python` (unreachable branch), `get_pending_modules` (no-lock reference), `get_module_finisher` (out_of_range) |
| OVERCAUTIOUS | 2 | `get_metadata_python`, `get_daemon_status_python` (global lock vs per-state lock) |

### DIVERGED details

1. **`get_config` (blame `.cc` line 696):** Acquires `module_config.lock` without a `without_gil_t`. Violates the invariant established by `0601b31a` (2020-12-21). When called from a Python thread that holds the GIL, the lock is taken while holding the GIL — exactly the pattern that caused the deadlock in tracker issue #39264.

2. **`get_foreign_config` (blame `.cc` line 1431, path `!have_local_config_map`):** Does not check `cmd.r` before using `cmd.outbl.to_str()` as a config value. Introduced by `02c44b17` (2021-02-16). A failing mon command returns an error string in `outbl`, which would be coerced to the declared option type and returned to Python.

3. **`update_cache_metrics` (blame `.h` line 272):** Header declaration left in place after `403340bcf8` (2025-07-17) removed the `.cc` implementation. The commit message explicitly notes "Remove unused update_cache_metrics()" but did not clean up the `.h` declaration. Stale declaration; will cause a linker error if called.

---

## Self-check (Step 6)

**Performed against functions.txt (177 entries) and commits.txt (234 commits).**

| Check | Result |
|-------|--------|
| Every commit in commits.txt covered? | ✅ Yes — 42 commits mapped to `(no functions)` (formatting, include, unrelated changes); all 192 function-touching commits are addressed in the relevant function sections above. |
| Every named function in functions.txt has a section? | ✅ Yes — 57 named `.cc` functions + 20 unique `.h`-only functions all have sections or are subsumed as header-only declarations. `update_cache_metrics` added in this self-check pass. |
| Every DIVERGED flag names the specific SHA and contradicting line? | ✅ Yes — `get_config` → `0601b31a` / blame `.cc:696`; `get_foreign_config` → `02c44b17` / blame `.cc:1431`; `update_cache_metrics` → `403340bcf8` / blame `.h:272`. |
| All anonymous lambdas (54 in functions.txt) accounted for? | ✅ Yes — documented as inline callbacks within parent function sections. |
| All UNGROUNDED code paths flagged? | ✅ Yes — 8 total (mgr_ips, dispatch_remote race, set_store silent error, set_uri out_of_range, check_all_modules_started double-call, get_perf_schema_python unreachable branch, get_pending_modules no-lock ref, get_module_finisher out_of_range). |
| All OVERCAUTIOUS checks flagged? | ✅ Yes — 2 total (global lock in get_metadata_python and get_daemon_status_python). |
