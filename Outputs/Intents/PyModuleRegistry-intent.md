# PyModuleRegistry — Intent Artefact

**Generated**: 2026-09-11  
**Source corpus**: `/home/szuraski/BobOutput/Object History/v4/PyModuleRegistry/`  
**Head SHA**: `8681fa6ebac230f86eb445bf57095c63e7f1abcc`  
**Corpus collected at**: 2026-09-11T21:40:59Z  
**Total non-merge commits**: 99  
**Date range**: 2017-08-14 (`9718896c`) → 2026-06-01 (`4c7621da`)  
**Files**: `src/mgr/PyModuleRegistry.cc`, `src/mgr/PyModuleRegistry.h`  
**Rename chain**: both files exist at their current paths from initial commit `9718896c` to HEAD with no renames.

---

## Corpus Summary

99 non-merge commits were read in full. The "no functions" entries in `commit_function_map.txt` were verified: they are formatting/whitespace changes (`4adaf64d`, `85d82fa`, `c8c1019d`, `f1bac418`, `706b2be4`), std-namespace cleanup (`706b2be4`), include-order fixes (`756a351`), client-registration data-structure changes (`78576c9`, `df507cde`, `b545fb9f`, `a586dcc`), finisher-thread additions (`46de643`), and notify-filter additions (`ee4e3ecd`) — none of these alter the analysed functions.

---

## Class Overview

`PyModuleRegistry` is the single owner of the Python interpreter lifecycle and of all loaded `PyModule` objects. It mediates between the mgr daemon and two runtime contexts:
- **Standby**: `StandbyPyModules` (one instance, optional)
- **Active**: `ActivePyModules` (one instance, optional)

The invariant established by `810369b0` (2018-02-05) is that `init()` is called first (interpreter up, all modules loaded), then exactly one of `standby_start()` or `active_start()` is called after the first `MgrMap` is received.

---

## Functions

---

### `init` — `src/mgr/PyModuleRegistry.cc:45`

**Purpose**: Initialize the CPython interpreter, register built-in modules (`ceph_logger`, `ceph_module`), configure `PYTHONPATH`, drop the GIL saving `pMainThreadState`, start the `ThreadMonitor`, then discover and load all Python module files from `mgr_module_path`.

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| `init()` takes no MgrMap argument; map is populated later via `handle_mgr_map` | `810369b0` (2018-02-05) |
| `std::lock_guard locker(lock)` is held for the entire function | `948635a8` (2018-10-16) |
| `PyConfig`/`Py_InitializeFromConfig` used instead of deprecated `Py_SetProgramName`+`Py_InitializeEx` | `4cf9b36c` (2024-02-03) |
| `PyConfig.parse_argv=0`, `configure_c_stdio=0`, `install_signal_handlers=0`, `pathconfig_warnings=0` are all set | `4cf9b36c` (2024-02-03) |
| `PyConfig.safe_path=0` set for Python ≥ 3.11 to allow site-packages access | `4cf9b36c` (2024-02-03) |
| `mgr_module_path` is appended to `pythonpath_env` (merging with existing `PYTHONPATH` env var) before interpreter init | `51a5774a` (2024-02-03) |
| `ceph_logger` only registered when `g_conf().get_val<bool>("daemonize")` is true | `410ce76f` (2018-02-08) |
| `PyEval_InitThreads()` called only for Python < 3.9 (deprecated/auto in 3.9+) | `28985555` (2020-11-16); removed entirely in `4cf9b36c` via new init path |
| `ceph_assert(pMainThreadState != nullptr)` after `PyEval_SaveThread()` | `ab23c506` (2018-08-23) |
| `thread_monitor->start_monitoring()` called after GIL drop | `95a90f7d` (2024-12-08) |
| All modules discovered from `mgr_module_path` via `probe_modules` (not from MgrMap.modules) | `6a8da7ca` (2017-11-16) |
| Module recorded in `modules` map even if `mod->load()` fails, so error can be reported | `7c80548d` (2018-03-15) |
| Disabled modules (in `mgr_disabled_modules` config) are filtered in `probe_modules` before loading | `067adbf9` (2020-04-30) |
| Error emitted to cluster log if no modules found | `67a47951` (2019-05-10) |
| Error emitted to cluster log listing names of failed-to-load modules | `9718896c` (2017-08-14, original) |
| `BOOST_SCOPE_EXIT_ALL` ensures `PyConfig_Clear` is called on all paths | `4cf9b36c` (2024-02-03) |

**Error conditions**

- `PyConfig_SetString` / `PyConfig_SetArgv` / `PyConfig_SetBytesString` failure: `ceph_assertf` aborts — no recovery path. Established `4cf9b36c`.
- `Py_InitializeFromConfig` failure: `ceph_assertf` aborts. Established `4cf9b36c`.
- `pMainThreadState == nullptr` after `PyEval_SaveThread()`: `ceph_assert` aborts. Established `ab23c506`.
- `mod->load()` failure: non-fatal, module still inserted into `modules` map, error logged. Established `7c80548d`.
- No modules found at all: cluster log error only, no abort. Established `67a47951`.

**Implementation critique** (blame lines 45–133)

- Lines 51–94: `PyConfig` initialization block is correct per `4cf9b36c` + `51a5774a`. The PYTHONPATH merging (lines 85–90) correctly prepends `mgr_module_path` ahead of the existing `PYTHONPATH`. **CORRECT**.
- Line 82: `PyImport_AppendInittab("ceph_logger", ...)` happens *inside* the `if (g_conf().get_val<bool>("daemonize"))` guard. `PyImport_AppendInittab("ceph_module", ...)` at line 84 is outside the guard — always registered. **CORRECT per `410ce76f`**.
- Line 99 (`ceph_assert(pMainThreadState != nullptr)`): present. **CORRECT per `ab23c506`**.
- Line 102 (`thread_monitor->start_monitoring()`): present. **CORRECT per `95a90f7d`**.
- Lines 107–132: `probe_modules` result iterated, each module loaded, failures tracked, both cluster log outputs present. **CORRECT**.
- **UNGROUNDED**: The `#undef WCHAR` at line 94 cleans up the macro defined at line 50. This is correct hygiene but the macro scope covers only the `PyConfig` initialization block, meaning `ceph_logger`/`ceph_module` registration at lines 80–84 occurs *between* the `PyConfig_SetBytesString` call at line 89 and `Py_InitializeFromConfig` at line 92. `PyImport_AppendInittab` must be called *before* `Py_Initialize`, which is satisfied here. No issue, but the ordering is easy to misread.
- **OVERCAUTIOUS**: No longer calling `PyEval_InitThreads()` at all — this was correct per `4cf9b36c` since `Py_InitializeFromConfig` on Python ≥ 3.9 initialises the GIL automatically. The old `#if PY_VERSION_HEX < 0x03090000` guard from `28985555` was properly superseded and is absent, consistent with minimum Python 3.9 requirement.

---

### `handle_mgr_map` — `src/mgr/PyModuleRegistry.cc:135`

**Purpose**: Process incoming `MgrMap` updates. On first invocation (epoch 0 → non-zero), set `enabled` and `always_on` flags on each loaded `PyModule`. On subsequent invocations, detect whether the active set has changed and notify `standby_modules` if running.

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| First-map path (epoch==0): sets `enabled` flag per `mgr_map.modules.count()` | `810369b0` (2018-02-05) |
| First-map path: sets `always_on` flag per `mgr_map.get_always_on_modules()` | `18f253aa` (2018-09-04) |
| First-map path returns `false` (no restart needed) | `810369b0` (2018-02-05) |
| Subsequent maps: `modules_changed` set true if `modules`, `always_on_modules`, OR `force_disabled_modules` differ | `9962772` (2024-07-19) added `force_disabled_modules`; `18f253aa` added `always_on_modules` |
| Subsequent maps: `standby_modules->handle_mgr_map()` called if standby is running | `c1471c75` (2017-08-22) |
| `std::lock_guard l(lock)` held for entire function | `948635a8` (2018-10-16) |

**Error conditions**

- No error conditions; function is purely informational and idempotent on repeated calls with same epoch.

**Implementation critique** (blame lines 135–165)

- Lines 139–153: first-map path. Both `enabled` (line 146) and `always_on` (lines 148–149) are set. Returns `false`. **CORRECT per `810369b0` + `18f253aa`**.
- Lines 154–164: subsequent-map path. `modules_changed` includes all three fields (lines 154–156). `standby_modules` forwarded at lines 159–162. **CORRECT per `9962772`**.
- **DIVERGED**: The header declaration (`PyModuleRegistry.h:130`) comments say `@return true if the mgrmap has changed such that the service needs restart`. The implementation returns `false` on the first-map receipt even though the caller (MgrStandby) uses the return value to decide whether to restart modules. This is intentional by design (`810369b0`'s comment: "First time we see MgrMap… this should always happen before someone calls standby_start or active_start"), but there is no assertion preventing the caller from receiving a `false` on first map and then calling `standby_start` before or during `handle_mgr_map` completing. The contract is maintained by caller convention, not enforcement here. This is documented in-code but could be tightened. **Flag as UNGROUNDED**: no assert or documentation confirming the caller ordering contract is upheld for the `epoch == 0` path.
- Lines 159–162: `standby_modules != nullptr` guard before forwarding. **CORRECT**; active modules are not forwarded because the active case is handled by MgrStandby respawning the entire active path.

---

### `standby_start` — `src/mgr/PyModuleRegistry.cc:169`

**Purpose**: Instantiate `StandbyPyModules`, then iterate all loaded modules and start those that are enabled, loadable, and implement a standby class (`pStandbyClass`).

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| `ceph_assert(active_modules == nullptr)` — cannot start standby if active is running | `ab23c506` (2018-08-23) |
| `ceph_assert(standby_modules == nullptr)` — cannot double-start | `ab23c506` (2018-08-23) |
| `ceph_assert(mgr_map.epoch > 0)` — MgrMap must have been received | `810369b0` (2018-02-05) |
| `StandbyPyModules` constructed with `(mgr_map, module_config, clog, mc, f)` | `f22347db` (2019-01-24) added `Finisher &f` |
| Modules skipped unless `is_enabled() && get_can_run()` | `7c80548d` (2018-03-15) |
| Always-on modules with a standby class that won't run are reported in cluster log as failed | `cf292dfa` (2018-07-16) |
| `start_one()` return value is not checked; failures are deferred to finisher | `f22347db` (2019-01-24) |

**Error conditions**

- `active_modules != nullptr` on entry: `ceph_assert` aborts. Established `ab23c506`.
- `standby_modules != nullptr` on entry: `ceph_assert` aborts. Established `ab23c506`.
- `mgr_map.epoch == 0` on entry: `ceph_assert` aborts. Established `810369b0`.
- Module fails to start: logged to cluster log if always-on; otherwise silently skipped.

**Implementation critique** (blame lines 169–208)

- Lines 172–177: all three precondition asserts present and correct. **CORRECT per `ab23c506` + `810369b0`**.
- Lines 183–184: `StandbyPyModules` constructed with correct arguments `(mgr_map, module_config, clog, mc, f)`. **CORRECT per `f22347db`**.
- Lines 186–207: module loop. The gate at line 188 `!(i.second->is_enabled() && i.second->get_can_run())` correctly skips non-runnable modules. The inner block at lines 190–192 inserts always-on modules with a standby class into `failed_modules` when they can't run. **CORRECT per `cf292dfa`**.
- **UNGROUNDED**: The cluster log error at lines 203–207 reports "Failed to execute ceph-mgr module(s) in standby mode". This error fires only for `always_on` modules that have a `pStandbyClass` but can't run (`!get_can_run()`). However, `force_disabled` modules are *not* checked here the way they are in `active_start`. An always-on module that is force-disabled would have `is_enabled()` set to `false` (since the force-disable path sets enabled to false in `handle_mgr_map`), so it would be skipped at line 188 without being listed as a failure. This is arguably correct but the asymmetry with `active_start`'s explicit `force_disabled_modules` check (added `9962772`) is undocumented and potentially confusing.

---

### `active_start` — `src/mgr/PyModuleRegistry.cc:210`

**Purpose**: Shut down any running standby modules, instantiate `ActivePyModules`, then iterate all loaded modules and start those that are enabled and loaded (not force-disabled).

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| `ceph_assert(active_modules == nullptr)` | `ab23c506` (2018-08-23) |
| `ceph_assert(mgr_map.epoch > 0)` | `810369b0` (2018-02-05) |
| If `standby_modules` is running, `shutdown()` + `reset()` is called before constructing active | `c1471c75` (2017-08-22) |
| `ActivePyModules` receives `thread_monitor.get()` as last argument | `95a90f7d` (2024-12-08) |
| `ActivePyModules` constructed without `Client&` (CephFS client removed) | `f20df2eb` (2025-01-30) |
| Module gate is `is_enabled() && is_loaded()` (not `get_can_run()`) so can_run=false modules still start | `cf5ef59b` (2018-04-23) |
| Force-disabled modules explicitly checked and skipped after the enabled+loaded gate | `9962772` (2024-07-19) |
| `start_one()` return value not checked; moved to finisher | `f22347db` (2019-01-24) |
| `bool mon_provides_kv_sub` parameter present, forwarded to `ActivePyModules` ctor | `edf1ea2f` (2021-02-16) |

**Error conditions**

- `active_modules != nullptr` on entry: `ceph_assert` aborts. Established `ab23c506`.
- `mgr_map.epoch == 0` on entry: `ceph_assert` aborts. Established `810369b0`.

**Implementation critique** (blame lines 210–261)

- Lines 218–226: lock acquired, precondition asserts present and correct. **CORRECT**.
- Lines 228–231: standby shutdown if present. **CORRECT per `c1471c75`**.
- Lines 233–241: `ActivePyModules` construction includes `thread_monitor.get()` as last parameter. **CORRECT per `95a90f7d`**.
- Lines 244–248: enabled+loaded gate uses `is_loaded()` not `get_can_run()`. **CORRECT per `cf5ef59b`**. The comment at lines 242–243 explains why.
- Lines 250–257: `force_disabled_modules` explicit check. **CORRECT per `9962772`**.
- Line 258: `start_one` called without checking return. **CORRECT per `f22347db`**.
- **UNGROUNDED**: `active_start` currently does not log a warning when a module is skipped because `!is_loaded()`. Lines 245–248 emit a dout(8) message only (from `9962772`) for the enabled-but-not-loaded path. For enabled modules that fail `is_loaded()`, there is no cluster log message; the failure will surface via `get_health_checks`. This is intentional by design (`7c80548d`'s comment: "Anything we're skipping because of !can_run will be flagged to the user separately via get_health_checks") — but the comment is misleading: the gate is `!is_loaded()` not `!get_can_run()`. The comment on line 242 still reads "!can_run" even though the code checks `is_loaded()`. **DIVERGED** comment at line 242–243: comment says "because of !can_run" but line 244 checks `i.second->is_loaded()`. This was changed in `cf5ef59b` (2018-04-23) which updated the gate from `get_can_run()` to `is_loaded()` but the adjacent comment was not updated.

---

### `get_site_packages` — `src/mgr/PyModuleRegistry.cc:263`

**Purpose**: Query the active Python interpreter for site-packages directories via `site.getsitepackages()`, falling back to `site.addsitepackages()` + `sys.path` inspection if the primary method is unavailable (virtualenvs).

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| Function moved from `PyModule` to `PyModuleRegistry` as a `static` member | `51a5774a` (2024-02-03) |
| Declared `static` because it has no instance state dependency | `51a5774a` (2024-02-03) |
| `ceph_assert(site_module)` — import of "site" must succeed | `ab23c506` (2018-08-23) |
| Primary path: `site.getsitepackages()` — produces colon-separated list | `9718896c` (2017-08-14, original) |
| Fallback path: `site.addsitepackages()` → `sys.path` inspection (for virtualenvs) | `9718896c` (2017-08-14, original) |
| `PyUnicode_AsUTF8` used (Python 3 only); `PyString_AsString` (Python 2) removed | `0a183082` (2020-04-20) |

**Error conditions**

- `PyImport_ImportModule("site")` returns null: `ceph_assert` aborts. Established `ab23c506`.
- `site.getsitepackages` not available and `site.addsitepackages` not available: `ceph_assert` aborts on the fallback. Established `ab23c506`.

**Implementation critique** (blame lines 263–327)

- Function is now only called from the pre-init configuration path but the blame shows it still exists as a live function definition in `.cc` at line 263. **NOTE**: after `51a5774a`, this function is declared `static` in the header and its primary use is gone (site packages now go into `pythonpath_env` via `PyConfig_SetBytesString` in `init()`). 
- **UNGROUNDED / OVERCAUTIOUS**: `get_site_packages()` is still compiled and linked but `51a5774a`'s purpose was to move site-package paths into `PyConfig.pythonpath_env` *before* `Py_InitializeFromConfig`. The current code in `init()` does NOT call `get_site_packages()` at all — the function exists but is dead code. The `PYTHONPATH` mechanism in `PyConfig` covers site packages via Python's normal `site` module processing. `get_site_packages()` is OVERCAUTIOUS dead code that should be removed but has not been.
- Ref: blame line 263 shows `51a5774aa605` as introducing the function to `.cc` — but the *intent* of that commit was to route paths through `PyConfig`, making the manual `get_site_packages()` call in `PyModule::load()` unnecessary. The function remains as an artifact.

---

### `probe_modules` — `src/mgr/PyModuleRegistry.cc:329`

**Purpose**: Scan `mgr_module_path` directory for subdirectories containing `module.py`, filtering out any names listed in `mgr_disabled_modules` config. Returns a `vector<string>` of module names.

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| Uses `std::filesystem::directory_iterator` (not POSIX `opendir`) | `40d06ce6` (2020-04-30) |
| Filters disabled module names via `mgr_disabled_modules` config + `ceph::split` | `067adbf9` (2020-04-30) |
| Returns `std::vector<std::string>` (changed from `std::set<std::string>`) | `7d2964bf` (2021-04-21) |
| Skips entries that are not directories | `40d06ce6` (2020-04-30) |
| Accepts a `path` parameter (extracted from caller to enable testing) | `67a47951` (2019-05-10) |
| Module presence detected by `module.py` existing in subdirectory | `9718896c` (2017-08-14, original) |

**Error conditions**

- No error handling for `fs::directory_iterator` construction failure (e.g., path does not exist). `std::filesystem` will throw `std::filesystem::filesystem_error`, which is not caught. This is an implicit abort. The caller in `init()` proceeds to log "No ceph-mgr modules found" if the result is empty, but a thrown exception would propagate uncaught.
- **UNGROUNDED**: no try/catch around `fs::directory_iterator`. If `mgr_module_path` does not exist or is unreadable, the process will crash with an uncaught filesystem exception rather than logging an error. The original POSIX implementation using `opendir` returned early silently if the directory couldn't be opened (`_list_modules` from `9718896c`).

**Implementation critique** (blame lines 329–350)

- Lines 331–334: disabled module filtering is correct. **CORRECT per `067adbf9`**.
- Lines 335–350: directory iteration with `is_directory` + `module.py` existence check. **CORRECT per `40d06ce6`**.
- Line 346: `modules.push_back(name)` — vector append, not set insert. **CORRECT per `7d2964bf`**.
- **DIVERGED** (vs. `9718896c` original intent): the original `_list_modules` function silently returned if `opendir` failed. Current code has no corresponding guard. This diverges from the original fault-tolerance contract. Commit `40d06ce6` introduced `std::filesystem` without adding error handling.

---

### `handle_command` — `src/mgr/PyModuleRegistry.cc:352`

**Purpose**: Dispatch a command to the named module via `ActivePyModules`. Returns `-EAGAIN` if active modules are not yet running.

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| Returns `-EAGAIN` when `active_modules == nullptr` | `834bc279` (2017-11-23) |
| Accepts `ModuleCommand&` + `MgrSession&` for authorization | `282c31c3` (2019-10-14) |
| `inbuf` parameter present | `140761f8` (2018-06-19) |
| No lock taken (delegates entirely to `ActivePyModules`) | `834bc279` (2017-11-23, original) |

**Error conditions**

- `active_modules == nullptr`: return `-EAGAIN`. Established `834bc279`.
- No other error path in the registry — all errors come from `ActivePyModules::handle_command`.

**Implementation critique** (blame lines 352–368)

- Line 360: `if (active_modules)` check is correct. **CORRECT**.
- Lines 361–362: delegates to `active_modules->handle_command(module_command, session, cmdmap, inbuf, ds, ss)` with full authorization parameters. **CORRECT per `282c31c3`**.
- Lines 364–368: `-EAGAIN` returned with an explanatory comment. **CORRECT per `834bc279`**.
- No lock: no mutex is held when calling into `active_modules`. This is safe because `active_modules` is a `unique_ptr` modified only under lock, but the check + dereference pattern is lock-free (it's a read of a `unique_ptr` without lock). **UNGROUNDED**: the `active_modules` pointer is accessed without `lock` here, whereas `get_py_commands`, `get_health_checks`, and other functions do take the lock. If `active_start` or a shutdown races with `handle_command`, there is a potential TOCTOU on the pointer. The original `834bc279` also had no lock, and no bug has been filed against it in the corpus, suggesting this is accepted practice in context, but it remains an inconsistency.

---

### `get_py_commands` — `src/mgr/PyModuleRegistry.cc:370`

**Purpose**: Return the list of `ModuleCommand` objects from all loaded modules (regardless of enabled/active state). Used to populate the mgr's command table early, before modules start.

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| Iterates `modules` map (all loaded modules, not just active) | `834bc279` (2017-11-23) |
| `std::lock_guard l(lock)` held | `948635a8` (2018-10-16) |
| Returns `vector<ModuleCommand>` by value | `834bc279` (2017-11-23) |
| Commands collected by calling `i.second->get_commands(&result)` on each `PyModule` | `834bc279` (2017-11-23) |

**Error conditions**

- None. Function is read-only and safe when `modules` is empty (returns empty vector).

**Implementation critique** (blame lines 370–380)

- Lock held at line 372, iteration at lines 375–377, return at line 379. **CORRECT**.
- **UNGROUNDED**: `modules` may contain modules that failed to load (`!is_loaded()`). `get_commands()` is called on all of them. If a module's load failure left `pClass == nullptr`, calling `get_commands()` on it would return an empty vector (PyModule::get_commands checks `pClass`). This is harmless but could return stale command definitions from a partially-loaded module. No invariant explicitly excludes failed modules from command extraction.

---

### `get_commands` — `src/mgr/PyModuleRegistry.cc:382`

**Purpose**: Convert all Python module commands to `MonCommand` format by calling `get_py_commands()` and wrapping each with `MonCommand::FLAG_MGR` (plus `FLAG_POLL` if `polling` is set).

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| Always sets `MonCommand::FLAG_MGR` | `78e884df` (2018-02-28) |
| Sets `MonCommand::FLAG_POLL` if `pyc.polling` is true | `78e884df` (2018-02-28) |
| `avail` field removed from `MonCommand` struct | `7734e9fa` (2018-09-27) |
| Calls `get_py_commands()` internally (single source of truth) | `834bc279` (2017-11-23) |

**Error conditions**

- None; pure transformation.

**Implementation critique** (blame lines 382–395)

- Lines 386–394: correct FLAG logic. **CORRECT per `78e884df`**.
- `get_py_commands()` called without explicit lock (it takes its own lock internally). **CORRECT**.
- **UNGROUNDED**: `get_commands()` itself has no lock guard. It calls `get_py_commands()` which acquires `lock`, so there is a brief window where `modules` could be modified between the call to `get_py_commands()` and return. Since `get_py_commands()` returns by value, this is safe, but technically there is no guarantee that two calls to `get_commands()` return consistent results.

---

### `get_health_checks` — `src/mgr/PyModuleRegistry.cc:397`

**Purpose**: When `active_modules` is running, aggregate health checks: (1) collect from `ActivePyModules`, (2) categorise modules as `dependency_modules` (enabled + `!can_run`) or `failed_modules` (enabled + `!loaded`, or `failed` + `can_run`, or pending past expiry), (3) report always-on modules not present in active modules as failed (unless obsolete or still pending), (4) emit `MGR_MODULE_DEPENDENCY` WARN and `MGR_MODULE_ERROR` ERR checks with per-module detail lines.

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| Only called when `active_modules` is non-null (standby does not report module issues) | `d9a47181` (2017-11-27) |
| `std::lock_guard l(lock)` held | `948635a8` (2018-10-16) |
| Two categories: `dependency_modules` (can_run=false) vs `failed_modules` | `d9a47181` (2017-11-27) |
| `failed_modules` gate: `(enabled && !loaded) || (failed && can_run)` — separates load-failure from runtime-failure | `cf5ef59b` (2018-04-23) |
| Count-with-detail format for both checks (detail lines list each module) | `4a7aca77` (2019-01-31) |
| `health_check_map_t::add()` called with explicit count parameter | `d0eb22f3` (2019-07-31) |
| Always-on modules not found in active are added to `failed_modules` (not `dependency_modules`) | `cf292dfa` (2018-07-16) |
| `obsolete_modules` set skipped in always-on check | `a59f4e5d` (2020-04-11) |
| Always-on modules still pending startup skipped in always-on check | `2d9b3abd` (2020-06-25) |
| Module stuck past expiry (still in `pending_modules`) added to `failed_modules` with message "Module failed to initialize." | `bf25a08c` (2025-07-29) |
| "Unknown error" message for not-found always-on replaced by "Not found or unloadable" | `a26e6067` (2018-08-20) |
| `MGR_MODULE_DEPENDENCY` severity: `HEALTH_WARN` | `d9a47181` (2017-11-27) |
| `MGR_MODULE_ERROR` severity: `HEALTH_ERR` | `d9a47181` (2017-11-27) |

**Error conditions**

- No error return; only side-effects on `*checks`.

**Implementation critique** (blame lines 397–489)

- Lines 399–402: lock acquired, early return if `!active_modules`. **CORRECT per `d9a47181`**.
- Lines 404–405: delegate to `active_modules->get_health_checks()`. **CORRECT**.
- Lines 419–435: module categorisation loop. The `is_pending` check at line 432 adds modules stuck past the `mgr_module_load_expiration` timeout to `failed_modules`. **CORRECT per `bf25a08c`**.
- Lines 438–451: always-on module check. Obsolete skip at line 439, pending skip at line 442, not-found check at line 445. **CORRECT per `2d9b3abd` + `a59f4e5d`**.
- Lines 453–488: MGR_MODULE_DEPENDENCY and MGR_MODULE_ERROR blocks with detail. **CORRECT per `4a7aca77` + `d0eb22f3`**.
- **UNGROUNDED**: Line 432 `active_modules->is_pending(module->get_name())` adds to `failed_modules` only when the module is *still pending* after expiry. But there is a subtlety: `is_pending()` returns true for *any* module still pending startup, not just those past the expiry threshold. The expiry logic lives in `ActivePyModules` (which decides to not retry and eventually clears out pending), but the `is_pending` check here fires as long as the module remains in `pending_modules`. This was intentional per `bf25a08c` (the `check_all_modules_started` / expiry mechanism ensures modules are eventually marked non-pending). No invariant violation, but the coupling between registry and `ActivePyModules::is_pending` semantics is implicit.
- **OVERCAUTIOUS**: Line 432 is an `else if` after the `(failed && can_run)` branch but the test only fires if neither the `dependency_modules` nor `failed_modules` paths above it matched *and* the module is pending. A module that is pending AND failed-with-can_run would have already been added to `failed_modules` by the prior branch and would not reach line 432. No double-count is possible. Correct.

---

### `handle_config` — `src/mgr/PyModuleRegistry.cc:491`

**Purpose**: Update the in-memory `module_config` key-value store from a config-key store notification. An empty value means deletion.

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| Takes `module_config.lock` (not `lock`) | `3193d40d` (2018-02-16) / `948635a8` (2018-10-16) |
| Non-empty `v`: inserts/updates `module_config.config[k]` | `3193d40d` (2018-02-16) |
| Empty `v`: erases `module_config.config[k]` | `3193d40d` (2018-02-16) |
| Config value is NOT logged to dout (sensitive data suppression) | `19000fad` (2020-12-03) |
| `dout(10)` logs key only (commented-out line explicitly shows suppression intent) | `19000fad` (2020-12-03) |

**Error conditions**

- None; pure map update.

**Implementation critique** (blame lines 491–504)

- Line 493: `std::lock_guard l(module_config.lock)`. Uses `module_config.lock`, distinct from `lock`. **CORRECT per `3193d40d`**.
- Lines 496–503: non-empty insert, empty erase. **CORRECT**.
- Line 499: `dout(10)` logs key but not value. The commented-out line at 497 makes intent explicit. **CORRECT per `19000fad`**.
- **UNGROUNDED**: `handle_config` only locks `module_config.lock`, not the outer `lock`. This means `handle_config` can race with `active_start` / `standby_start` which also read `module_config`. The `active_modules`/`standby_modules` constructors copy `module_config`, so a concurrent `handle_config` could write to `module_config` during construction. The `module_config.lock` should protect against this, but the outer `lock` is held by `active_start`/`standby_start`. Because `module_config.lock` is a different mutex, there's no deadlock, but the fine-grained locking model is implicit and not documented.

---

### `handle_config_notify` — `src/mgr/PyModuleRegistry.cc:506`

**Purpose**: Notify `ActivePyModules` that Ceph's config has changed, triggering `config_notify()` callbacks to all active module instances.

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| Takes outer `lock` | `f27a5dc6` (2018-11-17) |
| Silently no-ops if `active_modules == nullptr` | `f27a5dc6` (2018-11-17) |
| Only active modules receive notify; standby modules are not notified | `f27a5dc6` (2018-11-17) |
| `70e99e76` (2020-11-25) deleted `upgrade_config` which previously followed this function | `70e99e76` (2020-11-25) |

**Error conditions**

- None.

**Implementation critique** (blame lines 506–512)

- Lock acquired, null check, delegate. **CORRECT per `f27a5dc6`**.
- **CORRECT**. No issues.

---

### `check_all_modules_started` — `src/mgr/PyModuleRegistry.cc:514`

**Purpose**: Delegate to `ActivePyModules::check_all_modules_started(modules_start_complete)`. Sends the "active" beacon to the mon immediately if all modules are ready, or schedules it for later if `pending_modules` is still non-empty.

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| Simple delegation to `ActivePyModules` | `cbd1726f` (2025-04-25) |
| No null guard on `active_modules` | `cbd1726f` (2025-04-25) — the function is only called from `Mgr::background_init()` which runs after `active_start()` |
| No lock taken | `cbd1726f` (2025-04-25) |

**Error conditions**

- If called before `active_start()` (i.e., `active_modules == nullptr`): **undefined behavior / null dereference**. There is no assert or guard.

**Implementation critique** (blame lines 514–516)

- Line 515: `active_modules->check_all_modules_started(modules_start_complete)` with no null check.
- **DIVERGED**: All other delegation functions in the "cheeky call-throughs" block that require `active_modules` to be non-null use `ceph_assert(active_modules)` (e.g. `get_services()`, `is_module_active()`, `get_active_module_finisher()`). `check_all_modules_started` does not. While the call site (`Mgr::background_init`) guarantees this is called after `active_start`, the function contract is not self-enforced. This diverges from the established pattern in `ab23c506` (2018-08-23) which added `ceph_assert(active_modules)` to all callthroughs. Missing assert is a **DIVERGED** finding against the pattern established by `ab23c506`.

---

## Header-only Functions

The following functions are defined entirely in `src/mgr/PyModuleRegistry.h` and their implementation is captured in the blame output.

---

### `PyModuleRegistry` (constructor) — `src/mgr/PyModuleRegistry.h:119`

**Purpose**: Initialize `clog`, construct `thread_monitor` via `std::make_unique<ThreadMonitor>(g_ceph_context)`.

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| `thread_monitor` is constructed in member initializer list | `95a90f7d` (2024-12-08) |
| `explicit` keyword | `39ffec28` (2018-04-25) |
| `LogChannelRef clog_` is the sole constructor argument | `34525ba3` (2018-09-28) |

**Implementation critique** (blame h:119–122)

- Constructor correct. `thread_monitor` construction in initializer ensures monitoring is set up before `init()` is called. **CORRECT**.

---

### `~PyModuleRegistry` — `src/mgr/PyModuleRegistry.h:124`

**Purpose**: Stop `thread_monitor` on destruction.

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| Calls `thread_monitor->stop_monitoring()` | `95a90f7d` (2024-12-08) |

**Implementation critique** (blame h:124–126)

- **UNGROUNDED**: The destructor only stops the thread monitor. It does NOT call `active_modules->shutdown()` or `standby_modules->shutdown()`, and it does NOT call `Py_Finalize()`. The original `shutdown()` function (removed in `dd9f9e26`, 2023-11-02) handled Python finalisation. After `dd9f9e26`, the mgr just exits on SIGINT/SIGTERM, relying on process exit to clean up Python state. This is documented in `dd9f9e26`'s commit message. Not a bug, but the destructor is incomplete in a technical sense. **OVERCAUTIOUS** note: the explanatory comment about why `Py_EndInterpreter` is not called (present in the removed `shutdown()`) is now gone, making the rationale ungrounded in code.

---

### `handle_mgr_map` (declaration) — `src/mgr/PyModuleRegistry.h:130`

Covered under `handle_mgr_map` `.cc` entry above.

---

### `have_standby_modules` — `src/mgr/PyModuleRegistry.h:132`

**Purpose**: Returns `!!standby_modules` (truthy check on unique_ptr).

**Invariants**: Added `efc29fb3` (2021-04-16) for use by `MgrStandby::respawn_if_needed`. No lock taken — reads `standby_modules` which is a `unique_ptr` and could be null.

**Implementation critique** (blame h:132–134): **UNGROUNDED**: No lock. Other functions taking `lock` before reading `standby_modules` (e.g., `standby_start`). This is a concurrent read. Given the mgr's single-threaded dispatch model, this is likely safe in practice but inconsistent with the locking discipline. Added without a corresponding assert or lock in `efc29fb3`.

---

### `init` (declaration) — `src/mgr/PyModuleRegistry.h:136`

Covered under `init` `.cc` entry above. Signature changed from `int init(const MgrMap&)` to `void init()` in `03283b0c` (2018-03-02).

---

### `upgrade_config` — `src/mgr/PyModuleRegistry.h:138`

**Purpose**: Migrate Luminous→Mimic config-key store entries into the new-style config framework.

**Current status**: The declaration in the header still exists (blame h:138–140, from `37484af0`), but the implementation was **deleted** in `70e99e76` (2020-11-25) with the commit message "mgr: do not migrate conf from config-key store to new-style conf". The function body no longer exists in the `.cc` file.

**Implementation critique**: **DIVERGED** — the header declares `upgrade_config` at h:138–140 but the implementation was deleted in `70e99e76`. This is a linker error / ODR violation if any call site remains, or dead declaration if no call sites remain. The header declaration survives only because the blame data shows it was not removed from the `.h` file when the `.cc` implementation was deleted. This is a concrete divergence between the header contract and the implementation.

---

### `active_start` (declaration) — `src/mgr/PyModuleRegistry.h:142`

Covered under `active_start` `.cc` entry above.

---

### `standby_start` (declaration) — `src/mgr/PyModuleRegistry.h:149`

Covered under `standby_start` `.cc` entry above. Signature: `void standby_start(MonClient &mc, Finisher &f)` per `f22347db` (2019-01-24).

---

### `is_standby_running` — `src/mgr/PyModuleRegistry.h:151`

**Purpose**: Returns `standby_modules != nullptr`. No lock.

**Invariants**: Original `c1471c75` (2017-08-22). No lock — same concurrency caveat as `have_standby_modules`.

**Implementation critique**: **UNGROUNDED** (same as `have_standby_modules`): reads `standby_modules` without lock. Established as an established-but-unprotected pattern.

---

### `get_commands` (declaration) — `src/mgr/PyModuleRegistry.h:156`

Covered under `get_commands` `.cc` entry above.

---

### `get_py_commands` (declaration) — `src/mgr/PyModuleRegistry.h:157`

Covered under `get_py_commands` `.cc` entry above.

---

### `get_module` — `src/mgr/PyModuleRegistry.h:165`

**Purpose**: Look up a module by name; returns empty `PyModuleRef` if not found.

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| Returns empty ref (not nullptr or exception) if module not found | `5ac9e85a` (2019-01-25) |
| `std::lock_guard l(lock)` held | `948635a8` (2018-10-16) |

**Implementation critique** (blame h:165–173): Lock acquired, `find()` used (not `at()`). Returns `{}` on miss. **CORRECT**.

---

### `handle_command` (declaration) — `src/mgr/PyModuleRegistry.h:184`

Covered under `handle_command` `.cc` entry above.

---

### `get_health_checks` (declaration) — `src/mgr/PyModuleRegistry.h:196`

Covered under `get_health_checks` `.cc` entry above.

---

### `get_progress_events` — `src/mgr/PyModuleRegistry.h:198`

**Purpose**: Forward progress event query to `active_modules` if active.

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| Null-guarded (silently no-ops if `!active_modules`) | `ef336075` (2019-02-15) |
| No lock taken | `ef336075` (2019-02-15) |

**Implementation critique** (blame h:198–202): Null guard present. **CORRECT**. No lock — consistent with `notify_all` pattern.

---

### `notify_all` (string overload) — `src/mgr/PyModuleRegistry.h:207`

**Purpose**: Forward notify to `active_modules` if active. No-op if standby or not yet started.

**Invariants**: Original `9718896c` (2017-08-14). No lock, null-guarded. **CORRECT**.

---

### `notify_all` (LogEntry overload) — `src/mgr/PyModuleRegistry.h:215`

Same analysis as string overload. **CORRECT**.

---

### `should_notify` — `src/mgr/PyModuleRegistry.h:222`

**Purpose**: Query whether the named module wants to receive a notification of a given type.

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| Uses `modules.at(name)` — throws `std::out_of_range` if name not found | `ee4e3ecd` (2021-12-02) |
| No lock taken | `ee4e3ecd` (2021-12-02) |

**Implementation critique** (blame h:222–225): `modules.at(name)` will throw if the module name is not in the map. The caller is expected to only call this with valid module names (i.e., after a prior `get_py_commands()` check). **UNGROUNDED**: no protection against an unknown module name at the call site level. Inconsistent with `get_module()` which uses `find()` and returns empty. This is a potential runtime exception path.

---

### `get_services` — `src/mgr/PyModuleRegistry.h:227`

**Purpose**: Return map of service names/addresses from `active_modules`.

**Invariants**: `ceph_assert(active_modules)` guard present (from `ab23c506`). **CORRECT**.

---

### `register_client` — `src/mgr/PyModuleRegistry.h:233`

**Purpose**: Register a RADOS client address for potential blocklisting.

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| `std::lock_guard l(lock)` held | `a586dcc5` (2023-02-15) |
| `replace` parameter: if true, erase all existing entries for name before inserting | `e72194b4` (2023-02-27) |

**Implementation critique** (blame h:233–241): Lock, conditional erase, emplace. **CORRECT per `e72194b4`**.

---

### `unregister_client` — `src/mgr/PyModuleRegistry.h:242`

**Purpose**: Remove a specific (name, addrs) pair from the clients multimap.

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| `std::lock_guard l(lock)` held | `a586dcc5` (2023-02-15) |
| Uses `equal_range` + linear scan to find exact match | `df507cde` (2019-12-02) |
| On match: `erase(it); return;` — exits after first match found | `12375a4c` (2020-09-04) fixed endless loop |

**Implementation critique** (blame h:242–252): Lock, `equal_range`, linear match, `erase(it); return`. **CORRECT per `12375a4c`**. The prior endless-loop bug (`it = clients.erase(it)` which reset the iterator but didn't break) was fixed in `12375a4c`.

---

### `get_clients` — `src/mgr/PyModuleRegistry.h:254`

**Purpose**: Return a copy of the clients multimap.

**Invariants**: `std::lock_guard l(lock)` held (added `a586dcc5`). Returns by value.

**Implementation critique** (blame h:254–258): Lock, copy return. **CORRECT**.

---

### `is_module_active` — `src/mgr/PyModuleRegistry.h:260`

**Purpose**: Query `ActivePyModules::module_exists()`.

**Invariants**: `ceph_assert(active_modules)` present (from `ab23c506`'s general pattern, specifically added by `46de643`). **CORRECT**.

---

### `get_active_module_finisher` — `src/mgr/PyModuleRegistry.h:265`

**Purpose**: Return reference to a named module's finisher thread.

**Invariants**: `ceph_assert(active_modules)` present. Added by `46de643` (2022-10-17). **CORRECT**.

---

### `check_all_modules_started` (declaration) — `src/mgr/PyModuleRegistry.h:275`

Covered under `check_all_modules_started` `.cc` entry above. Declaration has a descriptive comment. The missing `ceph_assert(active_modules)` DIVERGED finding applies here.

---

### `get_pending_modules` — `src/mgr/PyModuleRegistry.h:279`

**Purpose**: Return a const reference to `ActivePyModules`' pending-module set. Used by `ceph tell mgr mgr_status` to show modules not yet initialized.

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| Returns `const` reference (caller must not modify) | `68221661` (2025-09-11) |
| No null guard on `active_modules` | `68221661` (2025-09-11) |

**Implementation critique** (blame h:279–281): No `ceph_assert(active_modules)`. Same DIVERGED finding as `check_all_modules_started`: both were added by Laura Flores (2025) and both omit the null guard that all prior callthroughs have.

- **DIVERGED**: Missing `ceph_assert(active_modules)` at h:279, consistent with the pattern established by `ab23c506`. If called before `active_start`, this produces a null dereference.

---

### `get_module_option` — `src/mgr/PyModuleRegistry.h:86`

**Purpose**: Thread-safe lookup of a single module config option by full key.

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| `std::lock_guard l(module_config.lock)` (not outer `lock`) | `4c7621da` (2026-06-01) |
| Returns `bool` + sets `*val` on hit | `4c7621da` (2026-06-01) |

**Implementation critique** (blame h:86–94): Correct locking on `module_config.lock`. **CORRECT**.

---

### `get_module_config_snapshot` — `src/mgr/PyModuleRegistry.h:99`

**Purpose**: Return a full copy of the module config map, protected by `module_config.lock`.

**Invariants established by commit history**

| Invariant | Established by SHA |
|---|---|
| `std::lock_guard l(module_config.lock)` | `4c7621da` (2026-06-01) |
| Returns by value (snapshot, not live reference) | `4c7621da` (2026-06-01) |

**Implementation critique** (blame h:99–102): **CORRECT**.

---

### `get_modules` — `src/mgr/PyModuleRegistry.h:108`

**Purpose**: Return a `vector<PyModuleRef>` of all modules (loaded and failed).

**Invariants**: `std::lock_guard l(lock)` held. Returns by value (snapshot). `9999ddf6` (2017-12-14) established intent; `78576c9e` (2019-12-02) changed return type to vector.

**Implementation critique** (blame h:108–117): Lock, vector copy, return. **CORRECT**.

---

### `update_kv_data` — `src/mgr/PyModuleRegistry.h:74`

**Purpose**: Forward KV subscription data to `active_modules`.

**Invariants**: `ceph_assert(active_modules)` present. Added `edf1ea2f` (2021-02-16).

**Implementation critique**: **CORRECT**.

---

### `probe_modules` (declaration) — `src/mgr/PyModuleRegistry.h:65`

Covered under `probe_modules` `.cc` entry above. Declared `private`. Return type `std::vector<std::string>` per `7d2964bf`.

---

### `get_site_packages` (declaration) — `src/mgr/PyModuleRegistry.h:61`

Covered under `get_site_packages` `.cc` entry above. Declared `static` per `51a5774a`. **OVERCAUTIOUS**: dead code.

---

## Summary of Findings

### DIVERGED

| Finding | Function | Line | Contradicting SHA |
|---|---|---|---|
| Comment "because of !can_run" but code checks `is_loaded()` | `active_start` | `.cc:242–243` | Introduced by `cf5ef59b` (2018-04-23) which changed gate from `can_run` to `is_loaded` but did not update comment |
| `upgrade_config` declaration in header with no implementation in `.cc` | `upgrade_config` | `.h:138–140` | Implementation deleted by `70e99e76` (2020-11-25); header not updated |
| Missing `ceph_assert(active_modules)` in `check_all_modules_started` | `check_all_modules_started` | `.cc:514–516` | Pattern established by `ab23c506` (2018-08-23) for all active-modules callthroughs; omitted by `cbd1726f` (2025-04-25) |
| Missing `ceph_assert(active_modules)` in `get_pending_modules` | `get_pending_modules` | `.h:279–281` | Same pattern; omitted by `68221661` (2025-09-11) |

### UNGROUNDED

| Finding | Function |
|---|---|
| `probe_modules` has no try/catch around `fs::directory_iterator`; throws on bad path | `probe_modules` |
| `handle_command` accesses `active_modules` without `lock`; inconsistent with other callthroughs | `handle_command` |
| `should_notify` uses `modules.at(name)` (throws) vs. `get_module`'s safe `find()` | `should_notify` |
| First-map path of `handle_mgr_map` returns `false` — caller ordering contract not asserted | `handle_mgr_map` |
| `have_standby_modules` / `is_standby_running` read `standby_modules` without lock | `have_standby_modules`, `is_standby_running` |
| `get_pending_modules` returns reference into `active_modules`' internal set without locking | `get_pending_modules` |

### OVERCAUTIOUS

| Finding | Function |
|---|---|
| `get_site_packages()` still exists but is never called; site-packages now injected via `PyConfig.pythonpath_env` | `get_site_packages` |
| Destructor only stops `ThreadMonitor`; no Python finalisation, relying on process exit (rationale comment gone after `dd9f9e26`) | `~PyModuleRegistry` |

---

*End of artefact.*
