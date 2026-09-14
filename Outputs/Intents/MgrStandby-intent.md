# MgrStandby Intent Artefact

## Corpus Summary

| Field | Value |
|-------|-------|
| Total commits | 131 (non-merge commits touching `src/mgr/MgrStandby.cc` and/or `src/mgr/MgrStandby.h`) |
| HEAD SHA | `8681fa6ebac230f86eb445bf57095c63e7f1abcc` |
| Newest commit | `d8dde402` 2026-06-30 — "mgr: add heap admin socket command" |
| Oldest commit | `7a985df6` 2014-02-12 — "mds: Create MDSUtility…" (rename ancestor) |
| Active date range | 2016-07-15 (first direct `MgrStandby.cc` content) → 2026-06-30 |
| Collection date | 2026-09-11 |

---

## Functions Inventory (from functions.txt)

| Function | File:Line | Primary Commits |
|---|---|---|
| `MgrHook` (ctor) | cc:53 | `4a7976a5` |
| `MgrHook::call` | cc:54 | `4a7976a5`, `d8dde402` |
| `MgrStandby` (ctor) | cc:71 | `7845f8d7`, `2fd49a1a`, `cf68ce51`, `306eebe0`, `e27f6c6a`, many |
| `~MgrStandby` | cc:96 | `4a7976a5`, `75b6149b` |
| `get_tracked_keys` | cc:107 | `d3a10d35`, `2d4b4235`, `efc29fb3` |
| `handle_conf_change` | cc:124 | `d3a10d35`, `efc29fb3`, `d8dde402` |
| `asok_command` | cc:152 | `4a7976a5`, `d8dde402` |
| `handle_standby_mgr_signal` | cc:183 | `a3dad559` |
| `init` | cc:189 | `7845f8d7`, `10bf5123`, `430ba5e2`, `3193d40d`, `73af779d`, many |
| `send_beacon` | cc:298 | `5c384630`, `7845f8d7`, `712ad57d`, `1f3e9d48`, `bf25a08c`, many |
| `__anon3d649c410102` (tick lambda) | cc:239 | (contained in `tick`) |
| `__anon3d649c410202` (init config lambda) | cc:250 | `3193d40d`, `19000fad`, `95f80dda` |
| `__anon3d649c410302` (respawn lambda) | cc:391 | `2fd49a1a` |
| `__anon3d649c410402` (background_init callback) | cc:473 | `e0e87da6` |
| `tick` | cc:384 | `35fd964e`, `80ee71ab5`, `dd9f9e26` |
| `respawn` | cc:397 | `2fd49a1a`, `8e070294`, `ab23c506` |
| `_update_log_config` | cc:444 | `d3a10d35`, `bb09a1d7`, `a50a91d2` |
| `handle_mgr_map` | cc:450 | `7845f8d7`, `9718896c`, `c1471c75`, `35d2146c`, `b835b07b`, `f20df2eb`, many |
| `ms_dispatch2` | cc:507 | `7845f8d7`, `c93dc884`, `56cb0577`, `c9d0913f` |
| `ms_handle_refused` | cc:528 | `58dd3db0` |
| `main` | cc:534 | `7845f8d7`, `44354e00`, `3d360b97`, `a3dad559` |
| `state_str` | cc:548 | `7845f8d7`, `c1471c75`, `15dfa71c` |

---

## Per-Function Intent and Critique

---

### `MgrHook` / `MgrHook::call`

**Introduced:** `4a7976a5` 2025-03-24 — "mgr: add status command"

**Intent:** Proxy `AdminSocketHook` that bridges the admin socket dispatch into `MgrStandby::asok_command()`. Catches `bad_cmd_get` and maps it to `-EINVAL` so invalid parameter access does not propagate as an unhandled exception.

**Invariants established by commit history:**
- `4a7976a5`: `asok_hook` lifetime is managed by `MgrStandby`; `MgrHook` holds a raw back-pointer `mgr` — safe because the hook is unregistered before `MgrStandby` is destroyed.
- `d8dde402` 2026-06-30: the `call` signature was extended with `outbl` parameter to accommodate the heap command whose output goes to a bufferlist rather than a Formatter.

**Implementation critique (blame lines 53–69):**
- Line 62: delegates to `mgr->asok_command(admin_command, cmdmap, f, errss, outbl)` — correct per `d8dde402`.
- Line 63: `bad_cmd_get` catch is present — correct per `4a7976a5`.
- **UNGROUNDED:** `inbl` parameter of `call` is silently ignored. No commit in the corpus explains whether `status` or `heap` commands should ever honour `inbl`. Current behaviour is fine for both registered commands, but the omission is unexplained.

---

### `MgrStandby` (constructor)

**Introduced:** `7845f8d7` 2016-07-15  
**Key evolution commits:** `2fd49a1a` (argc/argv for respawn), `cf68ce51` (MgrClient, MGR entity name, random nonce via `getpid()`), `306eebe0` (ASIO `poolctx`), `c15e197c` (ms_public_type), `e27f6c6a` (random nonce via `Messenger::get_random_nonce()`), `a8a23747` (Objecter timeout configs), `6f35d2835` (fsid for MgrClient), `5c3846306` (`available_in_map` initialised to `false`), `f22347db` (Finisher).

**Invariants:**
- `5c3846306b6b`: `available_in_map` MUST be initialised `false` — the first time we declare availability we send command descriptions (blame line 92).
- `2fd49a1a`: `orig_argc`/`orig_argv` MUST be stored for `respawn()` (blame lines 89–91).
- `e27f6c6a` 2023-03-01: messenger uses `Messenger::get_random_nonce()`, not `getpid()`, to prevent nonce collision after rapid restart.
- `a8a23747`: `objecter` construction now takes `poolctx` for ASIO-backed timeouts.

**Implementation critique (blame lines 71–94):**
- Lines 73–92: initialiser list order matches declaration order in the header — correct; no reordering hazard.
- Line 80: `Messenger::get_random_nonce()` — correct per `e27f6c6a`.
- Line 92: `available_in_map(false)` — invariant satisfied.
- **UNGROUNDED (line 76–77):** `ms_public_type` fallback logic: if `ms_public_type` is empty, fall back to `ms_type`. This was introduced by `c15e197c` 2021-03-01 and is intentional, but no test in the corpus verifies the fallback path. Acceptable but worth noting.

---

### `~MgrStandby`

**Introduced:** `4a7976a5` 2025-03-24 (previously `= default`)  
**Modified by:** `75b6149b` 2026-05-21 — "common/TrackedOp: make OpHistory::on_shutdown() idempotent"

**Intent:** Guard destructor that (1) shuts down and releases `active_mgr` if still alive, then (2) unregisters and releases `asok_hook`. This protects against use-after-free if the object is destroyed while still active.

**Invariants established:**
- `75b6149b`: `active_mgr` must be explicitly shut down in the destructor as a failsafe, because the normal code path (respawn via `execv`) never returns, so the destructor is only reached in abnormal/test scenarios. The commit notes idempotent `on_shutdown()` design makes double-shutdown safe.
- `4a7976a5`: admin socket commands must be unregistered before the hook is reset, otherwise the admin socket could dispatch into a freed `MgrHook`.

**Implementation critique (blame lines 96–105):**
- Lines 97–100: `active_mgr->shutdown(); active_mgr.reset();` — correct per `75b6149b`.
- Lines 101–104: `unregister_commands` before `asok_hook.reset()` — correct per `4a7976a5`.
- **DIVERGED (potential — lines 96–100 vs. `dd9f9e26`):** `dd9f9e26` 2023-11-02 removed `MgrStandby::shutdown()` entirely because it was unreachable (`_exit(0)` was called on signals). The destructor path added by `75b6149b` re-introduces an orderly-shutdown sequence for `active_mgr` — but it does NOT call `timer.shutdown()`, `mgrc.shutdown()`, `monc.shutdown()`, `objecter.shutdown()`, or `client_messenger->shutdown()`. The original `shutdown()` (removed by `dd9f9e26`) called all of these in a specific order (timer → mgrc → poolctx.finish() → monc → active_mgr → objecter → client_messenger). Since the destructor path is for non-respawn exits, this is intentionally minimal, but the mismatch with the old shutdown contract is **UNGROUNDED** — no commit explains why only `active_mgr` needs explicit shutdown in the destructor but other subsystems do not.

---

### `get_tracked_keys`

**Introduced:** `d3a10d35` 2017-03-21 (as `get_tracked_conf_keys`, returning `const char**`)  
**Modified by:** `efc29fb3` 2021-04-16 (added `mgr_standby_modules`), `2d4b4235` 2025-02-25 (renamed to `get_tracked_keys`, returning `std::vector<std::string>`)

**Intent:** Declare the config keys for which `handle_conf_change` should be called. Required so the config observer framework knows which keys to watch.

**Invariants:**
- `d3a10d35`: all `clog_to_*` keys and `host`/`fsid` must be tracked so log channel config is updated live.
- `efc29fb3`: `mgr_standby_modules` must be tracked to trigger respawn when standby module enablement changes.
- `73af779d` 2021-04-16: `add_observer(this)` was missing before this commit — `handle_conf_change` was never called. The fix was to call `cct->_conf.add_observer(this)` in `init()`.

**Implementation critique (blame lines 107–122):**
- Lines 111–120: all 10 keys present — `clog_to_monitors`, `clog_to_syslog`, `clog_to_syslog_facility`, `clog_to_syslog_level`, `clog_to_graylog`, `clog_to_graylog_host`, `clog_to_graylog_port`, `mgr_standby_modules`, `host`, `fsid` — matches the history contract.
- **UNGROUNDED:** There is no corresponding `remove_observer` in the destructor or elsewhere. The `add_observer` in `init()` (blame line 195) is never undone. Since `MgrStandby` lives for the process lifetime this is technically safe, but differs from the pattern used by other observers in the codebase and is not explained by any commit.

---

### `handle_conf_change`

**Introduced:** `d3a10d35` 2017-03-21  
**Modified by:** `efc29fb3` 2021-04-16 (respawn on `mgr_standby_modules` change), `d8dde402` 2026-06-30 (no body change, signature identical)

**Intent:** React to live config changes. Two concerns: (1) if any `clog_*`/`host`/`fsid` key changes, update log channel config; (2) if `mgr_standby_modules` changes AND we are not currently the active mgr, respawn so the new setting takes effect.

**Invariants:**
- `efc29fb3`: the respawn guard `!active_mgr` is essential — if we are the active mgr, a change to `mgr_standby_modules` should not respawn us (we would lose active state). Only respawn when we are a pure standby.
- `efc29fb3`: respawn only if the desired state (config value) differs from the current state (`py_module_registry.have_standby_modules()`). Avoids spurious respawn if the value is set to the same value it already has.

**Implementation critique (blame lines 124–150):**
- Lines 128–138: `clog_*` / `host` / `fsid` guard — calls `_update_log_config()` — correct.
- Line 139: `changed.count("mgr_standby_modules") && !active_mgr` — guard is present — correct per `efc29fb3`.
- Line 140: mismatch check against `py_module_registry.have_standby_modules()` — correct per `efc29fb3`.
- **UNGROUNDED (line 139):** The `!active_mgr` guard is a raw pointer-nullness test. If `active_mgr` is in the process of being torn down (e.g., between `reset()` in `handle_mgr_map`'s deactivation branch and the subsequent `respawn()`), this check could briefly see `active_mgr == nullptr` even though a respawn is already in progress. There is no explicit lock check shown here — however `handle_conf_change` is called from the config observer thread and `active_mgr` is only manipulated under `lock`. The absence of `ceph_assert(ceph_mutex_is_locked_by_me(lock))` at the top of this function is inconsistent with `send_beacon` (blame line 300) which has this assertion.

---

### `asok_command`

**Introduced:** `4a7976a5` 2025-03-24 — "mgr: add status command"  
**Modified by:** `d8dde402` 2026-06-30 — "mgr: add heap admin socket command"

**Intent:** Single dispatch point for admin socket commands. Handles `status` (returns empty object, `0`) and `heap` (delegates to `ceph_heap_profiler_handle_command`). Falls through with `-ENOSYS` for unknown commands.

**Invariants:**
- `4a7976a5`: `status` must return `0` with an empty JSON object to satisfy the Rook operator's health check (fixes tracker #70571).
- `d8dde402`: `heap` must guard with `ceph_using_tcmalloc()` and return `-EOPNOTSUPP` if tcmalloc is not in use; output goes to `outbl`, not the Formatter.

**Implementation critique (blame lines 152–181):**
- Lines 157–160: `status` branch — correct.
- Lines 161–177: `heap` branch — tcmalloc guard present (line 162–165), `heapcmd` and `value` parameters parsed, output to `outbl` (line 176–178) — correct per `d8dde402`.
- Lines 178–180: `-ENOSYS` fallthrough — correct.
- **UNGROUNDED (line 159):** `status` returns an empty JSON object `{}`. The commit message says "TBD on adding useful information." There is no follow-up commit in the corpus that adds content. This is an acknowledged stub, not a logic error — but it means the Rook operator's health check cannot distinguish between a fully-functional mgr and one that just started.
- **UNGROUNDED:** `asok_command` has no lock protection. The `heap` path calls `ceph_heap_profiler_handle_command` which is not thread-safe with respect to `lock`. The `status` path is trivially safe. The `MgrHook::call` path acquires no lock. This was not addressed in any corpus commit and no prior code held the lock during asok dispatch.

---

### `handle_standby_mgr_signal`

**Introduced:** `a3dad559` 2026-06-14 — "mgr: handle SIGTERM/SIGINT in standby mgr to avoid CEPHADM_FAILED_DAEMON"

**Intent:** Static signal handler for SIGTERM and SIGINT in the standby mgr. Calls `_exit(0)` to produce exit code 0 (orderly-shutdown semantics) when the process is stopped, preventing systemd from marking the unit as failed (CEPHADM_FAILED_DAEMON).

**Context:** Before `a3dad559`, `MgrStandby` only registered SIGHUP. SIGTERM at OS default would produce exit code 143, causing systemd to report a failure. This mirrors the handler path that was historically in the active mgr and was removed by `3d360b97` 2019-10-14 when signal handling moved to `Mgr::init()`. The standby was left without SIGTERM handling until `a3dad559`.

**Invariants:**
- `a3dad559`: `_exit(0)` (not `exit(0)`) — correct; avoids running atexit handlers and Python finalizers that are known-broken (see `6146c85b` 2019-03-07).
- `b925be726` 2019-03-10 established the "exit 0 for orderly semantics" principle. `a3dad559` follows it.
- Registered with `register_async_signal_handler_oneshot` — fires only once, preventing re-entrant signal delivery.

**Implementation critique (blame lines 183–187):**
- Line 185: `derr` log of signal name before `_exit(0)` — matches pattern from `b925be726` / `6146c85b`.
- Line 186: `_exit(0)` — correct.
- **UNGROUNDED (line 183–187 vs. `3d360b97`):** `3d360b97` explicitly removed the static `signal_mgr` pointer + `handle_mgr_signal` / `handle_signal` trampoline from `MgrStandby`, arguing signal handling belongs in `Mgr::init()`. `a3dad559` reintroduces a static signal handler on `MgrStandby`, this time as a simple function (no pointer back to the object), which is architecturally cleaner. The two commits are not in conflict, but the history leaves a gap: `Mgr::init()` (which the active mgr calls) registers its own SIGTERM/SIGINT handlers. After `handle_mgr_map` promotes a standby to active, the standby's `handle_standby_mgr_signal` is still registered (as a oneshot) while `Mgr::init()` registers additional handlers. The interaction between these concurrent registrations is not documented in any commit.

---

### `init`

**Introduced:** `7845f8d7` 2016-07-15  
**Key evolution:** `10bf5123` (check monc.init() return), `44354e00` (SIGHUP moved to init), `3193d40d` (config callback before monc.init()), `430ba5e2` (set_passthrough_monmap after authenticate), `f22347db` (finisher.start()), `73af779d` (add_observer), `a3dad559` (SIGTERM/SIGINT oneshot), `4a7976a5` (asok hook registration), `d8dde402` (heap asok command), `306eebe0` (poolctx.start), `19000fad` (hide config values in log), `95f80dda` (simplify config prefix), `810369b0` (py_module_registry.init sooner), `15dfa71c` (mgr_perf_start)

**Intent:** Full initialization sequence:
1. Register signal handlers (SIGHUP, SIGTERM, SIGINT).
2. Register config observer.
3. Acquire `lock`.
4. Start finisher.
5. Start messenger, register dispatchers.
6. Register admin socket hook (`status`, `heap`).
7. Start ASIO pool.
8. Build monmap and handle failure.
9. Subscribe to `mgrmap`.
10. Set want-keys.
11. Set messenger on monc.
12. Register config callback (before `monc.init()`).
13. Register config-notify callback.
14. `monc.init()` — check return value.
15. `mgrc.init()` + register mgrc dispatcher.
16. `monc.authenticate()` — check return value.
17. `monc.set_passthrough_monmap()` after auth.
18. Set entity name on messenger from global id.
19. Set log client.
20. Update log config.
21. `objecter.init()` + `objecter.start()`.
22. `timer.init()`.
23. `py_module_registry.init()`.
24. `mgr_perf_start()`.
25. `tick()` to start beacon loop.

**Invariants:**
- `10bf5123`: `monc.init()` return MUST be checked — failure (e.g., missing keyring) must propagate as error; messenger must be shut down cleanly on failure.
- `3193d40d`: config callback MUST be registered BEFORE `monc.init()` so that the initial configuration message from the monitor is seen.
- `430ba5e2`: `monc.set_passthrough_monmap()` MUST be called AFTER `monc.authenticate()` completes, to avoid a deadlock where `ms_dispatch2` tries to acquire `lock` while `authenticate()` holds it (the lock is already held at the top of `init()`).
- `73af779d`: `add_observer(this)` MUST be called to make `handle_conf_change` fire. Without it, `handle_conf_change` is never invoked (bug fixed by this commit).
- `f22347db`: finisher MUST be started before the messenger (avoid race where a message arrives before the finisher is ready).
- `a3dad559`: SIGTERM/SIGINT registered as oneshot handlers in `init()` (before lock held).
- `4a7976a5`: asok hook registered after messenger started (so admin socket is ready).
- `d8dde402`: heap asok command registered in same block as status.

**Implementation critique (blame lines 189–296):**
- Line 193: `init_async_signal_handler()` — correct.
- Line 194: SIGHUP — correct.
- Lines 193–194: SIGTERM/SIGINT oneshot registration at lines 193–194 — correct per `a3dad559`.
- Line 197: `add_observer(this)` — correct per `73af779d`.
- Line 199: `std::lock_guard l(lock)` — correct. Lock held for rest of init.
- Lines 201–202: `finisher.start()` before messenger — correct per `f22347db`.
- Lines 203–207: messenger dispatchers + start — correct.
- Lines 207–222: asok hook creation and registration — correct per `4a7976a5`, `d8dde402`.
- Line 222: `poolctx.start(2)` — correct per `306eebe0`.
- Lines 225–229: `build_initial_monmap()` failure path — correct cleanup per `7845f8d7`.
- Line 233: `monc.sub_want("mgrmap", 0, 0)` — correct.
- Lines 239–251: config callback registered before `monc.init()` — correct per `3193d40d`.
- Lines 250–252: config-notify callback — correct per `f27a5dc6`.
- Lines 257–261: `monc.init()` return check — correct per `10bf5123`.
- Lines 262–263: `mgrc.init()` and dispatcher registration — correct per `cf68ce51`.
- Lines 265–272: `monc.authenticate()` check — correct.
- Line 277: `monc.set_passthrough_monmap()` — correct per `430ba5e2`.
- Lines 281–285: entity naming + log client + objecter init/start + timer init — correct.
- Line 288: `py_module_registry.init()` — correct per `810369b0`.
- Line 289: `mgr_perf_start()` — correct per `15dfa71c`.
- Line 292: `tick()` — correct (starts beacon loop per `35fd964e`).
- **DIVERGED (lines 193–194 vs. `3d360b97`):** `3d360b97` 2019-10-14 removed SIGINT/SIGTERM registration from `MgrStandby::main()`, leaving only SIGHUP. `a3dad559` re-adds them but now in `init()` instead of `main()`. This means `init()` registers the handlers while the lock is not yet held (lines 193–194 are before `std::lock_guard l(lock)` at line 197). This is intentional and safe since signal handlers must not hold locks, but is architecturally inconsistent with the historical pattern where the lock was acquired first in `init()`.
- **OVERCAUTIOUS (line 225–229):** `build_initial_monmap()` failure path calls `client_messenger->shutdown()` + `wait()` but does not call `finisher.stop()`, `timer` cleanup, or `asok_hook` unregistration — all of which were already set up. This could leave the admin socket registered with a pointer to a partially-initialized `MgrStandby`. This is a pre-existing condition established by `7845f8d7` that was never corrected.

---

### `send_beacon`

**Introduced:** `7845f8d7` 2016-07-15  
**Key evolution:** `5c3846306` (command descs + `available_in_map`), `1bf4a89890` (metadata), `b62520059` (addrs), `5f86c7282` (addrs stringify), `712ad57d` (ModuleInfo list with can_run), `6eb5c636` (can_run flag in ModuleInfo), `1f3e9d48` (module_options in ModuleInfo), `351a3b9d` (mgr_features), `df507cde` (RADOS client list for blocklist), `dfd01d76` (blacklist→blocklist rename), `78576c9e` (auto type for modules), `218f4cef` (pre-quincy compat: strip `positional=false`), `bf25a08c` (expiration-based availability)

**Intent:** Construct and send an `MMgrBeacon` to the monitor. The beacon declares whether this daemon is the active mgr (`available`), its server addresses, the list of loaded modules with their metadata, system info, and RADOS client addresses for blocklist purposes. When transitioning from not-available to available for the first time (`!available_in_map`), the beacon also carries the full command description set.

**Invariants:**
- `c93dc884`: `ceph_assert(ceph_mutex_is_locked_by_me(lock))` — `send_beacon` MUST be called under `lock`.
- `5c3846306b6b`: `available_in_map` tracks whether the monitor has already acknowledged our availability. Command descriptions MUST only be sent in the transition beacon (`!available_in_map`), not on every tick.
- `bf25a08c` 2025-07-29: `available` is now `active_mgr->is_initialized() || active_mgr->exceeded_initialization_expiration()`. The fallback `exceeded_initialization_expiration()` fires after `mgr_module_load_expiration` ms to unblock PG availability reporting even if modules are stuck.
- `1f3e9d48`: `module_options` must be included in each `ModuleInfo`.
- `218f4cef`: if `monc.monmap.min_mon_release < ceph_release_t::quincy`, strip `positional=false` from command strings before sending.
- `351a3b9d`: `CEPH_FEATURES_ALL` is passed as the features field of the beacon.

**Implementation critique (blame lines 298–382):**
- Line 300: `ceph_assert(ceph_mutex_is_locked_by_me(lock))` — invariant enforced.
- Line 303: `py_module_registry.get_modules()` — correct.
- Lines 307–315: loop builds `module_info` with `name`, `error_string`, `can_run`, `module_options` — correct per `712ad57d`, `6eb5c636`, `1f3e9d48`.
- Line 317: `get_clients()` — correct per `df507cde`.
- Lines 322–338: comment block describing the availability logic — correct per `bf25a08c`.
- Lines 336–339: `available` computation — `active_mgr != nullptr && (is_initialized() || exceeded_initialization_expiration())` — correct per `bf25a08c`.
- Line 341: `addrs = available ? active_mgr->get_server_addrs() : entity_addrvec_t()` — correct per `7f787704`.
- Lines 344–347: `addr` (legacy) and `addrs` (new) in metadata — correct per `b62520059`, `5f86c728`.
- Lines 349–357: beacon construction — correct.
- Lines 359–376: `if (available && !available_in_map)` — command descs and pre-quincy compat — correct per `5c3846306`, `218f4cef`.
- Line 378: `m->set_services(active_mgr->get_services())` — correct per `a0183a63`.
- Line 381: `monc.send_mon_message(std::move(m))` — correct.
- **UNGROUNDED (lines 359–376 vs. `available_in_map` state):** `available_in_map` is set to `true` in `handle_mgr_map` (blame line 490) when the *monitor* confirms our availability. Until that confirmation, each tick re-sends command descriptions. This is intentional (monitor may not have processed the first beacon), but the corpus contains no explicit comment explaining the retry semantics — it can appear as an accidental re-send.
- **UNGROUNDED (line 341):** If `available` is `true` because `exceeded_initialization_expiration()` returned true but `active_mgr->get_server_addrs()` returns an empty or unbound address (modules not yet bound), the beacon would advertise an unusable server address. No guard against this case exists; `bf25a08c` does not address it.

---

### `tick`

**Introduced:** `35fd964e` 2017-03-10 ("mgr: switch from send_beacon() to tick()")  
**Key evolution:** `80ee71ab5` (use `get_val<chrono::seconds>`), `489b30844` (FunctionContext→LambdaContext), `dd9f9e268` (removed `shutdown()` call; `tick` became the sole continuation)

**Intent:** Heartbeat driver. Calls `send_beacon()` then re-arms itself via `timer.add_event_after()` using `mgr_tick_period`. Provides the periodic keep-alive beacon to the monitor.

**Invariants:**
- `35fd964e`: `tick()` is called at the end of `init()` to start the loop; subsequent calls are driven by the timer callback.
- `80ee71ab5`: period MUST be read dynamically from `g_conf()` on every tick, not cached at startup, allowing live `mgr_tick_period` changes.
- `c93dc884` (lock assertion in `send_beacon`): `tick()` must be called under `lock`. The lambda at blame line 391–394 captures `this` and calls `tick()` directly — this lambda fires from the timer, which calls back under the `lock` (SafeTimer holds the lock when calling callbacks).

**Implementation critique (blame lines 384–395):**
- Line 387: `send_beacon()` — correct (lock is held by SafeTimer contract).
- Lines 389–394: `timer.add_event_after(g_conf().get_val<std::chrono::seconds>("mgr_tick_period").count(), new LambdaContext([this](int r){ tick(); }))` — correct.
- **UNGROUNDED (line 386 log at level 10):** `dout(10) << __func__ << dendl` — the commit `617c96014` 2017-07-12 ("Mgr: increase debug level for ticks 0 -> 10") deliberately moved this from level 0 to 10 to reduce log spam. This is intentional but the comment in the diff says "0 -> 10" while blame line 386 shows the current value is 10 — consistent.
- **UNGROUNDED (missing shutdown path):** After `dd9f9e268` removed `shutdown()`, there is no mechanism to stop the tick loop short of `execv()` (respawn) or `_exit()`. If `init()` fails partway through after `tick()` was already called (which cannot happen in current code since `tick()` is the last call in `init()`), the timer would fire on a partially-initialized object. This is structurally safe in the current code but fragile.

---

### `respawn`

**Introduced:** `2fd49a1a` 2017-06-07 ("mgr/MgrStandby: respawn when deactivated")  
**Key evolution:** `8e070294` (thread name warning comment), `ab23c506` (`assert` → `ceph_assert`)

**Intent:** Re-exec the current binary with the original argv, providing a clean-slate restart. Used when the active mgr is deactivated (becomes non-active per mgrmap), when the enabled module list changes (per `py_module_registry.handle_mgr_map()`), or when `mgr_standby_modules` config changes. The rationale (`2fd49a1a`) is that unwinding Python interpreter state is unreliable; a clean exec is more dependable.

**Invariants:**
- `2fd49a1a`: Tries `/proc/self/exe` first (survives binary replacement); falls back to `orig_argv[0]`. MUST call `unblock_all_signals(NULL)` before `execv` to ensure the new process starts with clean signal mask.
- `8e070294`: Any future copy-pasters MUST call `ceph_pthread_setname(pthread_self(), "ceph-mgr")` in `main()` so that `/proc/$pid/stat` contains `(ceph-mgr)` and not `(exe)`, enabling `killall` and log rotation.
- `ab23c506`: `assert(cwd)` → `ceph_assert(cwd)` — correct use of Ceph assert.
- On `execv` failure: log + `ceph_abort()`. There is no recovery path.

**Implementation critique (blame lines 397–442):**
- Lines 399–406: warning comment — present per `8e070294`.
- Lines 407–413: argv copy — correct.
- Lines 420–432: `/proc/self/exe` → fallback — correct per `2fd49a1a`.
- Line 436: `unblock_all_signals(NULL)` — invariant satisfied.
- Line 437: `execv(exe_path, new_argv)` — correct.
- Lines 439–441: failure log + `ceph_abort()` — correct.
- **UNGROUNDED (lines 430–432):** The success branch does `dout(1) << "respawning with exe " << exe_path` and then immediately overwrites `exe_path` with `PROCPREFIX "/proc/self/exe"`. The log line prints the *resolved* symlink target but then executes `/proc/self/exe` (the symlink). If `PROCPREFIX` is non-empty (FreeBSD compat), this could exec a different path than what was logged. Not a current bug on Linux but misleading.

---

### `_update_log_config`

**Introduced:** `d3a10d35` 2017-03-21  
**Modified by:** `bb09a1d7` 2021-10-17 ("common: hide internal logger configuration strings from clients") — simplified to `parse_client_options`; `a50a91d2` (ref_t refactor — no body change)

**Intent:** Re-read all log channel configuration from the current CephContext and apply to both `clog` and `audit_clog`. Called from `handle_conf_change` when any `clog_*` / `host` / `fsid` key changes, and once at the end of `init()` after authentication.

**Invariants:**
- `bb09a1d7`: the old 7-map manual construction is replaced by `parse_client_options(cct)` — a single call that reads all relevant keys internally. Both `clog` and `audit_clog` must always be updated together.

**Implementation critique (blame lines 444–448):**
- Lines 446–447: `clog->parse_client_options(cct)` and `audit_clog->parse_client_options(cct)` — correct per `bb09a1d7`.
- **OVERCAUTIOUS (eliminated):** The old failure check `if (parse_log_client_options(...) == 0)` that guarded against malformed config is gone in `bb09a1d7`. The new `parse_client_options` API presumably handles errors internally. The absence of error handling here is intentional and introduced by `bb09a1d7`.

---

### `handle_mgr_map`

**Introduced:** `7845f8d7` 2016-07-15  
**Key evolution:** `5c3846306` (`available_in_map` update), `e0e87da6` (background_init + immediate beacon callback), `16fcee1f` (respawn on module-list change via `got_mgr_map`), `9718896c` (PyModuleRegistry refactor: `handle_mgr_map` delegation), `c1471c75` (standby modules start), `810369b0` (registry init sooner), `35d2146c` (`mgr_standby_modules` guard), `b835b07b` (log reason for respawn), `f20df2eb` (remove `client` from Mgr constructor call), `c9d0913f` (dispatch_result_t), `a50a91d2` (ref_t parameter type)

**Intent:** Process an incoming `MMgrMap` update. Three branches:
1. **Active in map + `active_mgr` is null** → allocate and background-init a new `Mgr` instance. Register a callback to fire `send_beacon()` immediately when init completes.
2. **Active in map + `active_mgr` exists** → pass map to existing `Mgr` via `got_mgr_map()`; if it signals need-respawn, respawn.
3. **Not active in map + `active_mgr` exists** → we were demoted; respawn.
4. **Not active in map + `active_mgr` is null + another gid is active** → start standby modules if not already running and `mgr_standby_modules` is true.

Additionally: check `py_module_registry.handle_mgr_map()` for module-list changes first (may trigger respawn before state transitions).

**Invariants:**
- `9718896c`: `py_module_registry.handle_mgr_map(map)` MUST be called regardless of whether we are active. If it returns `true`, respawn immediately.
- `b835b07b`: log at level 1 before respawning.
- `e0e87da6`: background_init callback sends beacon immediately (not waiting for next tick) — MUST hold `lock` in callback (blame line 476).
- `5c3846306`: `available_in_map` MUST be updated to `true` on confirmation from monitor (blame lines 488–491).
- `35d2146c`: standby module start MUST be guarded by `mgr_standby_modules` config check.
- `c1471c75`: the `else if` / `else` restructuring is correct — only one of the three branches fires per map update.
- `f20df2eb`: `Mgr` constructor no longer takes `&client` — that parameter was removed when CephFS client was excised.

**Implementation critique (blame lines 450–505):**
- Line 452: `auto &map = mmap->get_map()` — correct (reference, not copy).
- Line 460: `py_module_registry.handle_mgr_map(map)` — correct per `9718896c`.
- Lines 461–464: respawn if need-respawn with level-1 log — correct per `b835b07b`.
- Line 466: `if (active_in_map)` — correct.
- Lines 467–479: new Mgr creation and background_init with callback — correct per `e0e87da6`.
- Line 471: `Mgr` constructor without `&client` — correct per `f20df2eb`.
- Lines 481–486: `got_mgr_map()` + respawn path — correct per `16fcee1f`.
- Lines 488–491: `available_in_map` update — correct per `5c3846306`.
- Lines 492–503: else-if / else branches (deactivation respawn, standby module start) — correct per `c1471c75`, `35d2146c`.
- **UNGROUNDED (lines 466–478):** When `active_in_map` is true and `active_mgr` is null, we create a new `Mgr` and call `background_init`. If `background_init` fails asynchronously (non-zero `r` in the callback), `send_beacon()` is still called. This means we may advertise as available even on init failure. The callback at blame lines 473–478 does not check `r`. No commit in the corpus explicitly addresses this — the failure mode is implicitly handled by `py_module_registry` health error mechanism (`bf25a08c`), but that only covers the expiration case, not a hard init failure.
- **DIVERGED (blame line 492 vs. `9718896c`):** `9718896c` introduced a two-phase `py_module_registry` init (`if (!is_initialized()) init(map); else handle_mgr_map(map)`). This two-phase pattern was removed by `810369b0` which moved `py_module_registry.init()` to `MgrStandby::init()`. The current code calls `py_module_registry.handle_mgr_map(map)` unconditionally — this is correct post-`810369b0`, but the intermediate commit `9718896c`'s FIXME comment (`// FIXME: error handling; assert(r == 0)`) in the init path was never resolved — it was silently dropped when the two-phase init was removed. The `py_module_registry.init()` in `MgrStandby::init()` also lacks error-return checking (blame line 288 shows it returns void in current code — but this was previously asserted non-zero by `9718896c`).

---

### `ms_dispatch2`

**Introduced:** As `ms_dispatch` in `7845f8d7` 2016-07-15; renamed to `ms_dispatch2` in a later refactor; return type changed to `dispatch_result_t` by `c9d0913f` 2025-02-18.  
**Key evolution:** `890f48256` (use `shared_ptr` local copy to prevent use-after-free), `cf68ce511` (allow MSG_MGR_MAP to pass through to mgrc), `c93dc884` (ceph::mutex unlock/lock), `91c6016d` (remove `ms_get_authorizer`), `56cb0577` (replace `handled=false` pass-through with `ACKNOWLEDGED()`), `c9d0913f` (`dispatch_result_t` return type)

**Intent:** Top-level message dispatch. Under `lock`:
1. If `MSG_MGR_MAP`: call `handle_mgr_map()`, set result to `ACKNOWLEDGED()`.
2. If `active_mgr` exists: copy the `shared_ptr` locally (use-after-free guard), drop `lock`, call `active_mgr->ms_dispatch2(m)`, re-acquire `lock`.
3. Return `r`.

**Invariants:**
- `890f48256`: `active_mgr` MUST be copied to a local `shared_ptr` before unlocking, to prevent use-after-free if `active_mgr` is reset in another thread while dispatch is running.
- `c93dc884`: MUST use `lock.unlock()`/`lock.lock()` (not `Unlock()`/`Lock()`).
- `56cb0577`: `MSG_MGR_MAP` MUST return `ACKNOWLEDGED()` (not `false`/unhandled) to suppress the "unhandled message" warning from the messenger layer. The old code that re-passed the map through as unhandled (to allow `mgrc` to see it) was removed — `mgrc` now gets map updates differently.
- `c9d0913f`: signature is `Dispatcher::dispatch_result_t`.

**Implementation critique (blame lines 507–525):**
- Line 509: `std::lock_guard l(lock)` — correct.
- Lines 514–516: MSG_MGR_MAP branch → `handle_mgr_map()` → `r = ACKNOWLEDGED()` — correct per `56cb0577`.
- Lines 518–522: `active_mgr` local copy + unlock + dispatch + relock — correct per `890f48256`, `c93dc884`.
- Line 524: `return r` — correct.
- **UNGROUNDED (lines 514–524):** If `m->get_type() == MSG_MGR_MAP` AND `active_mgr` is non-null, BOTH branches fire: first `handle_mgr_map()` sets `r = ACKNOWLEDGED()`, then `active_mgr->ms_dispatch2(m)` overwrites `r`. This means a MGR_MAP message that the active Mgr returns as "unhandled" would cause `r` to be `false`/unhandled even though it was processed by `handle_mgr_map()`. The old code at `cf68ce511` explicitly handled this by re-setting `handled = false` for MGR_MAP to let `mgrc` see it. `56cb0577` removed the re-set but did not add an early-return after the MGR_MAP branch, so the overwrite by `active_mgr->ms_dispatch2(m)` still occurs. This is a **DIVERGED** bug: `56cb0577` intended to make MGR_MAP always return `ACKNOWLEDGED()`, but the current code can return whatever `active_mgr->ms_dispatch2(m)` returns for a MSG_MGR_MAP message if `active_mgr` is non-null.

---

### `ms_handle_refused`

**Introduced:** `58dd3db0` 2016-09-20 ("mgr: update for Dispatcher::ms_handle_refused")

**Intent:** Satisfy the `Dispatcher` interface. Currently a no-op returning `false`.

**Implementation critique (blame lines 528–532):**
- Lines 530–531: "do nothing for now" comment — correct; returns `false`.
- **UNGROUNDED:** No follow-up commit in the corpus addresses what "for now" means. The 10-year-old placeholder has never been acted on. If a refused connection should trigger a re-connection attempt or a respawn, that logic is absent.

---

### `main`

**Introduced:** `7845f8d7` 2016-07-15  
**Key evolution:** `44354e00` (SIGHUP registration moved here initially, then moved to `init()` by `7060a6a7`), `3d360b97` (removed SIGINT/SIGTERM from main), `a3dad559` (add SIGTERM/SIGINT unregistration in main to pair with init registrations)

**Intent:** Post-`init()` wait loop. Calls `client_messenger->wait()` (blocking) until the messenger shuts down (which happens on `_exit()` or execv). Cleans up signal handlers and calls `shutdown_async_signal_handler()`.

**Invariants:**
- `7060a6a7`: SIGHUP registration moved to `init()` (earlier) so log-reopen works before the messenger wait.
- `3d360b97`: SIGINT/SIGTERM handlers removed from `main()` (moved into `Mgr::init()`); later `a3dad559` re-adds them in `init()` and unregisters them here.
- Signal handlers unregistered in `main()` must match those registered in `init()`.

**Implementation critique (blame lines 534–545):**
- Line 536: `client_messenger->wait()` — correct.
- Lines 539–541: unregister SIGHUP, SIGTERM, SIGINT — correct pairings with `init()` registrations per `a3dad559`.
- Line 542: `shutdown_async_signal_handler()` — correct.
- Line 544: `return 0` — correct.
- **UNGROUNDED (line 534):** `main()` receives `args` but never uses them. The parameter was present in the original `7845f8d7` but the body has never used it. The args were presumably intended for runtime re-configuration but were never implemented.
- **OVERCAUTIOUS:** `main()` does not call any subsystem shutdown (timer, objecter, monc, finisher, etc.) after `wait()` returns. The original `shutdown()` method (removed by `dd9f9e268`) would have done this. Since `_exit(0)` is now called on SIGTERM/SIGINT, the process never returns from `wait()` in normal operation — so the cleanup code would be unreachable. However, in exceptional cases (e.g., messenger shuts down without a signal), `main()` returns 0 with all subsystems still running and their threads unjoined. This is a **DIVERGED** condition relative to `dd9f9e268`'s intent (which was that `_exit()` is always used for shutdown), but `dd9f9e268` itself acknowledged this as intentional ("Users won't care, although our leak checking will.").

---

### `state_str`

**Introduced:** `7845f8d7` 2016-07-15 (returned `"standby"` or `"active"`)  
**Modified by:** `c1471c75` 2017-08-22 (added `"active (starting)"` state), `15dfa71c` 2021-05-26 (no body change — state_str mentioned as relevant for TTLCache)

**Intent:** Return a human-readable string for the current operational state: `"standby"` (no active_mgr), `"active"` (active_mgr exists and is fully initialized), `"active (starting)"` (active_mgr exists but not yet initialized).

**Invariants:**
- `c1471c75`: three-state logic is the established contract. The distinction between `"active"` and `"active (starting)"` matches the `available` logic in `send_beacon` (is_initialized or expiration override).
- `bf25a08c`: with the expiration override, a mgr can be `"active (starting)"` in `state_str` (not `is_initialized()`) but still report `available = true` in the beacon. This creates a subtle mismatch — `state_str` says "starting" but the beacon says "available".

**Implementation critique (blame lines 548–557):**
- Lines 550–556: three-state if/else — correct per `c1471c75`.
- **DIVERGED (lines 550–556 vs. `bf25a08c`):** `state_str()` at line 552 returns `"active"` only when `active_mgr->is_initialized()`, but `send_beacon` reports `available = true` when `is_initialized() || exceeded_initialization_expiration()`. Therefore, when the expiration fires, the mgr is advertising as available to the monitor but `state_str()` still returns `"active (starting)"`. This inconsistency means the admin socket `status` command, debug logs, and any caller of `state_str()` would show a state that contradicts the monitor-visible availability. `bf25a08c` updated `send_beacon` and added comments there, but did not update `state_str` to reflect the third availability condition. This is a **DIVERGED** finding: `bf25a08c` introduced the `exceeded_initialization_expiration()` path in `send_beacon` (blame line 338) but `state_str` at blame line 552 still only tests `is_initialized()`.

---

### Anonymous lambdas

**`__anon3d649c410102` (cc:239) — tick re-arm lambda**  
Same as `tick` analysis. See tick section. The lambda `[this](int r){ tick(); }` is the `timer.add_event_after` callback. No distinct invariants.

**`__anon3d649c410202` (cc:250) — config_callback lambda**  
Established by `3193d40d`, privacy-sanitized by `19000fad`, simplified by `95f80dda`. Intent: forward `mgr/` prefixed keys to `py_module_registry.handle_config(k, v)`. The value `v` is deliberately not logged (`19000fad`). Returns `true` if handled, `false` otherwise. Implementation is correct.

**`__anon3d649c410302` (cc:391) — respawn lambda (tick)**  
This is the `LambdaContext` passed to `timer.add_event_after` in `tick()`. Contains only `tick()`. No distinct invariants beyond `tick`.

**`__anon3d649c410402` (cc:473) — background_init callback**  
Established by `e0e87da6`. Intent: call `send_beacon()` immediately when `Mgr::background_init` completes, under `lock`. Blame line 476: `std::lock_guard l(lock)`. Blame line 477: `send_beacon()`. Correct. Does not check `r` (see `handle_mgr_map` UNGROUNDED above).

---

## Self-Check

| Check | Result |
|---|---|
| Every commit read? | All 131 commits in `commits.txt` accounted for. 118 have non-empty function mappings read or processed through blame attribution. 13 are formatting/whitespace-only (`4adaf64d`, `85d82faa`, `c8c1019d`, `f1bac418` and related) — confirmed to have no semantic changes via their diffs. |
| Critique for every function in functions.txt? | Yes. All 26 unique function names covered (cc and h entries for same function share section). |
| SHAs cited for every DIVERGED flag? | Yes. See DIVERGED items citing `56cb0577` (ms_dispatch2), `bf25a08c` / `c1471c75` (state_str), `810369b0` / `9718896c` (handle_mgr_map), `dd9f9e268` / `a3dad559` / `b925be726` (main). |
| All ungrounded code paths flagged? | Yes: `inbl` in `MgrHook::call`, `available_in_map` retry semantics in `send_beacon`, `background_init` failure in `handle_mgr_map`, `ms_handle_refused` placeholder, `main` `args` parameter, `state_str` vs. expiration-availability, missing `remove_observer`. |
| OVERCAUTIOUS items? | Yes: `build_initial_monmap()` failure path leaves asok registered; `main()` does not clean up subsystems on non-signal return; `_update_log_config` error check removal (`bb09a1d7`). |

---

## DIVERGED Summary

| Finding | SHA establishing intent | Contradicting line(s) | Description |
|---|---|---|---|
| `ms_dispatch2` MGR_MAP acknowledgement | `56cb0577` | blame cc:521 | `active_mgr->ms_dispatch2(m)` can overwrite `r = ACKNOWLEDGED()` set for MSG_MGR_MAP, causing an acknowledged message to return as unhandled if active_mgr returns false. |
| `state_str` vs. `send_beacon` availability | `bf25a08c` | blame cc:552 | `state_str` tests only `is_initialized()` but `send_beacon` uses `is_initialized() || exceeded_initialization_expiration()`. After expiration fires, beacon says "available" but `state_str` says "active (starting)". |
| `~MgrStandby` partial shutdown | `75b6149b` vs. `dd9f9e268` | blame cc:97–100 | Destructor shuts down `active_mgr` but not timer, finisher, monc, objecter, or client_messenger — which were shut down in the old `shutdown()` method removed by `dd9f9e268`. |
| `main()` post-wait cleanup | `dd9f9e268` | blame cc:534–545 | `dd9f9e268` assumed `_exit()` is always used; `main()` returns 0 without joining subsystem threads in exceptional cases. |
| `handle_mgr_map` init error handling | `9718896c` | blame cc:288 | `9718896c`'s `assert(r == 0)` for `py_module_registry.init()` was silently dropped when `810369b0` moved init earlier; current `py_module_registry.init()` in `MgrStandby::init()` ignores any failure. |
