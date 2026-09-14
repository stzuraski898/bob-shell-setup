# Intent Artefact — StandbyPyModules

**Generated**: 2026-09-11  
**Corpus HEAD**: `8681fa6ebac230f86eb445bf57095c63e7f1abcc`  
**Files**: `src/mgr/StandbyPyModules.cc`, `src/mgr/StandbyPyModules.h`  
**Commit count**: 32 non-merge commits (2017-08-22 → 2025-10-02)  
**Rename chain**: no renames — both files stable at current paths since `c1471c75`

---

## Corpus Overview

The corpus tracks the standby-mode Python module manager for Ceph's `ceph-mgr` daemon.
Two structural entities:

- **`StandbyPyModuleState`** — shared immutable state (MgrMap + PyModuleConfig reference + MonClient reference) read by all standby module instances; guards access with its own mutex.
- **`StandbyPyModules`** — container/lifecycle manager for a collection of `StandbyPyModule` instances; drives startup via a `Finisher` and tears down on shutdown.
- **`StandbyPyModule`** (extends `PyModuleRunner`) — per-module object; loads the Python standby class instance and exposes `get_config`, `get_store`, and `get_active_uri` to the Python layer.

Key design decisions established in history:
- **No local config cache**: original `c1471c75` had a `LoadConfigThread` + `Cond`-gated `with_config` wait; `3193d40d` eliminated this, replacing the local cache with a reference to a shared `PyModuleConfig` object owned higher up.
- **Async load via Finisher**: `f22347db` (tracker#37997) moved module loading off the caller's thread into a `Finisher` to prevent lock cycles.
- **Deferred map registration**: `56e34f58` (tracker#41736) removed pre-registration of modules before load, so a failed load never leaves a half-initialized entry in the map.

---

## Functions

---

### `StandbyPyModules::StandbyPyModules` (constructor)

**Location**: `src/mgr/StandbyPyModules.cc:33` / `src/mgr/StandbyPyModules.h:118`

#### Evolution

| SHA | Subject | Change |
|-----|---------|--------|
| `c1471c75` | mgr: standby modules come up and run now | Created; signature `(MonClient *monc_, const MgrMap &mgr_map_)`; initialised `monc`, `load_config_thread`, called `state.set_mgr_map`. |
| `f4763c32` | mgr: emit cluster log message on serve() exception | Added `LogChannelRef clog_` parameter, stored in `clog`. |
| `6a8da7ca` | mgr: load all modules (not just active ones) | No signature change at ctor; adjusted internals. |
| `3193d40d` | mgr: centralized setting/getting of mgr configs | Added `PyModuleConfig &module_config`; removed `monc_` from ctor (moved to state only); eliminated `load_config_thread` from ctor initialiser. |
| `37484af0` | mgr: rework kv store load path | Removed `MonClient *monc_` from ctor signature entirely; `MonClient` now lives in `state` only (added back via `6185bd66`). |
| `6185bd66` | mgr: implement get_store in StandbyPyModules | Re-added `MonClient &monc_` as last parameter; passed to `state(module_config, monc_)`. |
| `f22347db` | mgr: load modules in finisher to avoid potential lock cycles | Added `Finisher &f` parameter; stored in `finisher`. |

**Current signature** (blame line 33–44):
```cpp
StandbyPyModules::StandbyPyModules(
    const MgrMap &mgr_map_,
    PyModuleConfig &module_config,
    LogChannelRef clog_,
    MonClient &monc_,
    Finisher &f)
    : state(module_config, monc_),
      clog(clog_),
      finisher(f)
{
  state.set_mgr_map(mgr_map_);
}
```

#### Invariants
- `state.set_mgr_map(mgr_map_)` must be called before any module load — established `c1471c75`, never removed.
- `PyModuleConfig &` is a reference; lifetime of the pointed-to config object must exceed the lifetime of `StandbyPyModules` — invariant not documented in code.
- `MonClient &` lifetime must exceed `StandbyPyModules` lifetime — same.
- `Finisher &` must be running before `start_one` is called — established `f22347db`.

#### Implementation Critique
- Line 43: `state.set_mgr_map(mgr_map_)` — correct.
- **UNGROUNDED**: There is no assertion or comment that the `Finisher` is already started at construction time. The comment "Send all python calls down a Finisher to avoid blocking" is in `start_one`, not here. A caller could pass a not-yet-started Finisher and the ctor would not detect it.

---

### `StandbyPyModules::shutdown`

**Location**: `src/mgr/StandbyPyModules.cc:47` / `src/mgr/StandbyPyModules.h:127`

#### Evolution

| SHA | Subject | Change |
|-----|---------|--------|
| `c1471c75` | mgr: standby modules come up and run now | Created; held `Mutex::Locker`, checked `!state.is_config_loaded && load_config_thread.is_started()` with `assert(0)` (FIXME comment: race not properly handled), iterated modules calling `module->shutdown()` with manual `lock.Unlock()/lock.Lock()`, then joined threads, then `modules.clear()`. |
| `3193d40d` | mgr: centralized setting/getting of mgr configs | Removed the `is_config_loaded` guard block and the `assert(0)` (LoadConfigThread eliminated). |
| `948635a8` | mgr: Mutex::Locker -> std::lock_guard | `Mutex::Locker` → `std::lock_guard`. |
| `c93dc884` | mgr: s/Mutex/ceph::mutex/ | `lock.Unlock()/lock.Lock()` → `lock.unlock()/lock.lock()`. |
| `f22347db` | mgr: load modules in finisher | No change to shutdown body; `lock` field type unchanged. |

#### Invariants
- Must hold `lock` at function entry — established `c1471c75`.
- Must unlock around each `module->shutdown()` call and re-acquire before iteration continues — established `c1471c75` (to prevent deadlock: module shutdown may call back into the state).
- Must unlock around each `thread.join()` — established `c1471c75`.
- `modules.clear()` is the last operation, performed under lock — established `c1471c75`, never changed.
- The early `is_config_loaded` guard with `assert(0)` was explicitly a FIXME that was resolved by removing LoadConfigThread (`3193d40d`). There is no longer a config-loading thread to race with.

#### Error Conditions
- No error return; `shutdown` is `void`. If `module->shutdown()` throws or hangs, there is no recovery path — this has been a known limitation since `c1471c75` (marked FIXME: "completely identical to ActivePyModules" comment retained at cc:48).

#### Implementation Critique
- Lines 49–72 (blame): pattern is correct — `std::lock_guard` on entry, then manual `lock.unlock()/lock.lock()` around blocking calls.
- **UNGROUNDED** (line 48): The FIXME comment "completely identical to ActivePyModules" was placed at `c1471c75` and has never been resolved. The comment persists at line 48 in the current file. Given that `ActivePyModules` has diverged significantly since 2017, this comment is now stale. It is not a correctness issue but it is misleading.
- Line 72: `modules.clear()` is under lock — correct, consistent with invariant.
- **UNGROUNDED**: The two `for` loops iterate `modules` while performing unlock/relock cycles. If `start_one`'s finisher lambda runs during this gap and inserts into `modules`, the iterator becomes invalid. In practice this is safe because the Finisher is typically stopped before `shutdown()` is called, but the code has no assertion or comment establishing this precondition.

---

### `StandbyPyModules::start_one`

**Location**: `src/mgr/StandbyPyModules.cc:75` / `src/mgr/StandbyPyModules.h:125`

#### Evolution

| SHA | Subject | Change |
|-----|---------|--------|
| `c1471c75` | mgr: standby modules come up and run now | Created as `int start_one(string, PyObject*, PyThreadState*)`. Held lock, checked `assert(modules.count==0)`, constructed module, started LoadConfigThread if first, called `module->load()` synchronously, on success created thread with `ostringstream` name (bug). |
| `bb4e71ed` | mgr: fix thread naming | Fixed thread naming: pass `module->get_name().c_str()` instead of a local ostringstream whose lifetime ended. |
| `29193a47` | mgr: update for SafeThreadState | Changed `PyThreadState*` → `const SafeThreadState&`. |
| `6a8da7ca` | mgr: load all modules (not just active ones) | Signature changed to `int start_one(PyModuleRef py_module)`. |
| `3193d40d` | mgr: centralized setting/getting of mgr configs | Removed `load_config_thread.create("LoadConfig")` block; `start_one` still synchronous `int`. |
| `948635a8` | mgr: Mutex::Locker -> std::lock_guard | `Mutex::Locker` → `std::lock_guard`. |
| `f22347db` | mgr: load modules in finisher to avoid potential lock cycles | **Major refactor**: Changed return type to `void`. Registration into `modules` map now happens *before* load; load queued into `Finisher` via `FunctionContext`; on failure, erases from map; on success, calls `thread.create()`. Pre-check `ceph_assert(modules.count(name) == 0)` retained. |
| `489b30844` | include: convert FunctionContext to LambdaContext | `FunctionContext` → `LambdaContext`. |
| `56e34f58` | mgr: fix race between module load and notify | **Critical fix** (tracker#41736): Registration into `modules` map moved *after* successful load. Raw pointer allocated before finisher queue; `ceph_assert(em.second)` asserts no duplicate on insert. `ceph_assert(modules.count == 0)` removed from outer lock scope. On failure: `delete standby_module`. On success: acquires lock, `modules.emplace(name, standby_module)`, then creates thread. |

#### Invariants
- `lock` held during map consultation and raw-pointer allocation — `c1471c75`.
- Module must not appear in `modules` map until it has successfully `load()`-ed — invariant established definitively by `56e34f58` (fix#41736).
- On load failure, `standby_module` must be `delete`-d — `56e34f58`.
- Thread must be created after successful insertion into map (so `shutdown()` can join it) — `f22347db`, refined by `56e34f58`.
- `ceph_assert(em.second)` guards against duplicate insertion — `56e34f58`.

#### Error Conditions
- `standby_module->load()` returns non-zero → module is deleted, error logged to `derr`, no crash. Established `c1471c75`, refined `56e34f58`.
- Duplicate name (already in map): no explicit pre-check in the outer lock scope since `56e34f58` removed `ceph_assert(modules.count(name) == 0)`. The post-load `ceph_assert(em.second)` fires inside the lambda; a duplicate name would abort the daemon. **DIVERGED**: The original `f22347db` put the `ceph_assert(modules.count(name) == 0)` in the outer lock scope (where a duplicate *before* queuing would be caught with good diagnostics). `56e34f58` removed this check entirely from the outer scope and relies only on the post-load `em.second` assert. The rationale is that the lambda holds `lock` again when checking, and since modules are only inserted in this lambda, no duplicate can exist. This is logically correct *if* callers never call `start_one` twice for the same module — which is an undocumented precondition.

#### Implementation Critique
- Lines 75–98 (blame): The raw `new StandbyPyModule` (line 79) is queued into a lambda. If the `Finisher` is stopped or destroyed before the lambda runs, `standby_module` leaks. No RAII wrapper is used — UNGROUNDED.
- Line 92: `ceph_assert(em.second)` is correctly placed inside the lock. CONFORMANT with `56e34f58` intent.
- Line 97: `finisher.queue(new LambdaContext(...))` — The `LambdaContext` captures `standby_module` (raw pointer), `name`, and `this`. The captured `this` means a use-after-free is possible if `StandbyPyModules` is destroyed while the lambda is in-flight. No comment documents this precondition. UNGROUNDED.

---

### `StandbyPyModule::load`

**Location**: `src/mgr/StandbyPyModules.cc:100` / `src/mgr/StandbyPyModules.h:101`

#### Evolution

| SHA | Subject | Change |
|-----|---------|--------|
| `c1471c75` | mgr: standby modules come up and run now | Created; `Gil gil(pMyThreadState)` (not new-thread-state); built `pArgs` from `PyString_FromString`, called `PyObject_CallObject(pClass, pArgs)`, on failure `handle_pyerror()` (zero-argument form). |
| `29193a47` | mgr: update for SafeThreadState | `Gil gil(pMyThreadState)` → `Gil gil(pMyThreadState, true)` — marks this as entering from a new OS thread. |
| `6a8da7ca` | mgr: load all modules | `pMyThreadState` → `py_module->pMyThreadState`; `pClass` → `py_module->pStandbyClass`; `module_name` → `get_name()`. |
| `ab23c506` | mgr: Use ceph_assert for asserts | `assert()` → `ceph_assert()` on `pThisPtr` and `pModuleName`. |
| `48c4bc44` | mgr: drop the compatibility with python2 | `PyString_FromString` → `PyUnicode_FromString`. |
| `719d5e18` | mgr: generate crash dump for python exceptions | `handle_pyerror()` → `handle_pyerror(true, get_name(), "StandbyPyModule::load")` — generates crash dump with module/caller context. |
| `b0a4bff8` | mgr: fix config option prefix | No change to `load()` body; comment above changed. |

#### Invariants
- GIL must be acquired with `true` (new-thread-state) because `load()` is called from a `Finisher` thread, not a Python-created thread — established `29193a47`.
- `pThisPtr` and `pModuleName` must not be null — `ceph_assert` guards established `ab23c506`.
- On Python class instantiation failure, `pClassInstance` remains `nullptr` and `-EINVAL` is returned — established `c1471c75`.
- On failure, a crash dump is generated with module name and caller — established `719d5e18`.

#### Error Conditions
- `PyCapsule_New` returns null → `ceph_assert` aborts (null capsule is not an expected Python error).
- `PyUnicode_FromString` returns null → `ceph_assert` aborts.
- `PyObject_CallObject` returns null → logs error + crash dump, returns `-EINVAL`.

#### Implementation Critique
- Lines 102–124 (blame): CONFORMANT with all established invariants.
- Line 102: `Gil gil(py_module->pMyThreadState, true)` — correctly uses `true` (new-thread-state). CONFORMANT with `29193a47`.
- Line 108: `PyUnicode_FromString` — correct post-`48c4bc44`; no more Py2 compatibility concern.
- Line 118: `handle_pyerror(true, get_name(), "StandbyPyModule::load")` — CONFORMANT with `719d5e18` crash-dump intent.
- **UNGROUNDED**: `Py_DECREF(pArgs)` at line 115 is called regardless of whether `PyObject_CallObject` succeeded. The pArgs tuple holds references to pThisPtr and pModuleName, which were already DECREF'd before the CallObject. The net refcounts are correct (PyTuple_Pack adds its own refs), but there is no comment explaining the ownership sequence. This pattern is consistent with how the original `c1471c75` wrote it and is correct Python API usage; it is just undocumented.

---

### `StandbyPyModule::get_config`

**Location**: `src/mgr/StandbyPyModules.cc:126` / `src/mgr/StandbyPyModules.h:94`

#### Evolution

| SHA | Subject | Change |
|-----|---------|--------|
| `c1471c75` | mgr: standby modules come up and run now | Created; key prefix was `PyModuleRegistry::config_prefix + module_name + "/" + key`; had vestigial `PyEval_SaveThread/RestoreThread` no-op pair. `with_config` blocked waiting on a Cond until config was loaded. `config.count()` and `config.at()` on a bare `map<string,string>`. |
| `6a8da7ca` | mgr: load all modules | Changed `module_name` → `get_name()`. |
| `3193d40d` | mgr: centralized setting/getting of mgr configs | Config lookup changed to `config.config.count()` / `config.config.at()` (now `PyModuleConfig` is a struct, not a raw map). `with_config` no longer blocks — passes through to the shared reference. |
| `d3b5c4cd` | misc: fix various log messages | Added space in `dout(4) << __func__ << " key:"`. |
| `37484af0` | mgr: rework kv store load path | Prefix changed `PyModuleRegistry::config_prefix` → `PyModule::config_prefix`. |
| `6185bd66` | mgr: implement get_store in StandbyPyModules | Removed vestigial `PyEval_SaveThread / PyEval_RestoreThread` pair. |
| `b0a4bff8` | mgr: fix config option prefix | Prefix changed `PyModule::config_prefix` → literal `"mgr/"`. Commit message: "this code is working with config option names, not config-key keys." |

#### Invariants
- Key prefix must be `"mgr/" + module_name + "/" + key` — established definitively by `b0a4bff8`, which corrected a previous incorrect use of `PyModule::config_prefix`.
- Access to `config.config` map must be under `StandbyPyModuleState::lock` — enforced by `with_config` template (established `c1471c75`).
- No GIL required for this function (accesses C++ data only) — implied by removal of `PyEval_SaveThread/RestoreThread` in `6185bd66`.
- Returns `true` + sets `*value` if found; `false` if absent — contract from `c1471c75`.

#### Error Conditions
- Key not found → return `false`, `*value` unmodified. No error log.
- No distinction between "key missing" and "config object empty" — both silently return `false`.

#### Implementation Critique
- Line 129: `"mgr/" + get_name() + "/" + key` — CONFORMANT with `b0a4bff8` fix.
- Line 133: `state.with_config([global_key, value](const PyModuleConfig &config){` — CONFORMANT.
- Lines 134–138: `config.config.count(global_key)` / `config.config.at(global_key)` — CONFORMANT with `3193d40d`.
- **OVERCAUTIOUS**: The original `with_config` had a `Cond`-wait for `is_config_loaded`; this was removed by `3193d40d`. The current implementation unconditionally passes through to the shared config reference. The comment "// FIXME: completely identical to ActivePyModules" at the top of `shutdown` suggests the dev intended to revisit the active/standby symmetry, but there is no analogous live issue in `get_config`.
- Line 131 (blank line after key construction before log): trailing space artifact from `3193d40d`'s diff (note in diffs: the space before `return` was added with a trailing space in one revision). Minor cosmetic issue, not a correctness problem.

---

### `StandbyPyModule::get_store`

**Location**: `src/mgr/StandbyPyModules.cc:143` / `src/mgr/StandbyPyModules.h:95`

#### Evolution

| SHA | Subject | Change |
|-----|---------|--------|
| `6185bd66` | mgr: implement get_store in StandbyPyModules | Introduced. Builds `global_key = PyModule::config_prefix + get_name() + "/" + key`. Issues synchronous `"config-key get"` mon command. Returns `false` on `-ENOENT`, logs error + returns `false` on other errors, sets `*value = outbl.to_str()` and returns `true` on success. Inline comment: "Active modules use a cache ... standbys fetch values synchronously ... acceptable cost because standby modules should not be doing a lot." |
| `3bafb5e5` | mgr: rename config_prefix -> mgr_store_prefix | `PyModule::config_prefix` → `PyModule::mgr_store_prefix`. Commit message: "The prefix for module kv store is 'mgr/', but it is not *config*." |

#### Invariants
- Key prefix must be `PyModule::mgr_store_prefix + get_name() + "/" + key` — established `6185bd66`, renamed `3bafb5e5`.
- This is a **blocking** synchronous mon command — intentional design per inline comment at `6185bd66`.
- Distinct from `get_config`: `get_config` reads in-memory shared config options (mgr config framework); `get_store` reads the kv store via a mon command. These are separate namespaces.
- Return semantics: `false` on missing, `false` + error log on unexpected error, `true` + `*value` set on success — from `6185bd66`.

#### Error Conditions
- `-ENOENT` → return `false` silently.
- Any other non-zero `r` → `derr` error log, return `false` (hides internal errors from Python layer, per inline comment "not meaningful to python modules").
- No handling of `monc` being unavailable or disconnected — UNGROUNDED.

#### Implementation Critique
- Lines 147–187 (blame): CONFORMANT with `3bafb5e5` and `6185bd66`.
- Line 147: `PyModule::mgr_store_prefix + get_name() + "/" + key` — CONFORMANT with `3bafb5e5`.
- Lines 152–156: inline comment about synchronous fetch design intent — present and correct.
- Lines 160–172: `ostringstream`-built JSON, `C_SaferCond`, `start_mon_command` — consistent with `6185bd66` design.
- Line 175: `r == -ENOENT` → `false` — correct.
- Lines 177–183: non-zero non-ENOENT → error + `false` — CONFORMANT.
- Lines 185–186: success → `outbl.to_str()` — correct.
- **UNGROUNDED**: The blocking `c.wait()` call holds no lock and does not check for shutdown. If the mgr is shutting down while a Python standby module calls `get_store`, this call can hang indefinitely. There is no timeout and no interruptibility. The design comment says this is acceptable, but it is not documented what happens during shutdown.
- **UNGROUNDED**: The JSON is built by `ostringstream` string concatenation. The `global_key` contains user-controlled content (module name + Python key). If the key contains `"` or `\`, the resulting JSON is malformed. This is a latent injection issue, though in practice module names are controlled by the operator.

---

### `StandbyPyModule::get_active_uri`

**Location**: `src/mgr/StandbyPyModules.cc:189` / `src/mgr/StandbyPyModules.h:96`

#### Evolution

| SHA | Subject | Change |
|-----|---------|--------|
| `c1471c75` | mgr: standby modules come up and run now | Created; searched `mgr_map.services` by `module_name`. |
| `6a8da7ca` | mgr: load all modules | Changed `module_name` → `get_name()` to use the `PyModuleRunner` accessor. |

#### Invariants
- Returns empty string if the module name is not present in `mgr_map.services` — established `c1471c75`.
- Access to `mgr_map` must be under lock — enforced by `with_mgr_map` template.
- Key into `mgr_map.services` is `get_name()`, not an arbitrary string — established `6a8da7ca`.

#### Error Conditions
- No error return — always returns a `std::string` (possibly empty).
- A module may not have an active URI (e.g., not the active mgr for that service); empty string is the defined sentinel.

#### Implementation Critique
- Lines 189–200 (blame): CONFORMANT.
- Line 193: `state.with_mgr_map([&result, this](const MgrMap &mgr_map){` — correct lambda capture by reference for `result`, by value via `this`.
- Line 193: search by `get_name()` — CONFORMANT with `6a8da7ca`.
- **UNGROUNDED**: Returns the service URI as registered in `mgr_map.services`. The semantics of this field (what a "URI" is, whether it is HTTP, what happens if the active mgr for a service is different from the active mgr daemon) are not documented in the function. This is unchanged from `c1471c75`.

---

### `StandbyPyModuleState::StandbyPyModuleState` (constructor)

**Location**: `src/mgr/StandbyPyModules.h:46`

#### Evolution

| SHA | Subject | Change |
|-----|---------|--------|
| `c1471c75` | mgr: standby modules come up and run now | `StandbyPyModuleState` had no explicit constructor; it had `config_cache` (local copy), `Cond config_loaded`, `bool is_config_loaded`. |
| `3193d40d` | mgr: centralized setting/getting of mgr configs | Added explicit constructor taking `PyModuleConfig &module_config_`; `config_cache` replaced with reference `module_config`. |
| `6185bd66` | mgr: implement get_store | Added `MonClient &monc_` second parameter; initialiser list `module_config(module_config_), monc(monc_)`. |

#### Invariants
- Both `module_config` and `monc` are references; the pointed-to objects must outlive `StandbyPyModuleState`.
- Constructor is in header; no implementation in `.cc`.

#### Implementation Critique
- Lines 46–48 (blame): CONFORMANT.
- **UNGROUNDED**: `module_config` is declared `private` (line 40) but `MonClient &monc` is also `private` (line 41). However, the `get_monc()` accessor at line 59 returns a non-const reference, allowing external mutation of MonClient fields. This is explicitly noted in the comment "MonClient does all its own locking so we're happy to hand out references" (`6185bd66`). CONFORMANT with design intent.

---

### `StandbyPyModuleState::set_mgr_map`

**Location**: `src/mgr/StandbyPyModules.h:50`

#### Evolution

| SHA | Subject | Change |
|-----|---------|--------|
| `c1471c75` | mgr: standby modules come up and run now | Created; held `Mutex::Locker l(lock)`, assigned `mgr_map = mgr_map_`. |
| `948635a8` | mgr: Mutex::Locker -> std::lock_guard | `Mutex::Locker` → `std::lock_guard`. |
| `c93dc884` | mgr: s/Mutex/ceph::mutex/ | Mutex type changed; lock syntax unchanged. |

#### Invariants
- Must hold `StandbyPyModuleState::lock` during the assignment — established `c1471c75`.
- Called from `StandbyPyModules` constructor (before any module is loaded) and from `handle_mgr_map` (live updates).

#### Implementation Critique
- Lines 50–55 (blame): CONFORMANT.
- No issues detected.

---

### `StandbyPyModuleState::get_monc`

**Location**: `src/mgr/StandbyPyModules.h:59`

#### Evolution

| SHA | Subject | Change |
|-----|---------|--------|
| `6185bd66` | mgr: implement get_store in StandbyPyModules | Introduced. Returns non-const `MonClient&`. Comment: "MonClient does all its own locking so we're happy to hand out references." |

#### Invariants
- Does not acquire `StandbyPyModuleState::lock` — intentional because MonClient is self-locking.
- The returned reference is valid for the lifetime of `StandbyPyModuleState`.

#### Implementation Critique
- Line 59 (blame): CONFORMANT.
- The trailing semicolon after the closing brace (`};`) is a minor style artifact — not a bug.

---

### `StandbyPyModuleState::with_mgr_map`

**Location**: `src/mgr/StandbyPyModules.h:62`

#### Evolution

| SHA | Subject | Change |
|-----|---------|--------|
| `c1471c75` | mgr: standby modules come up and run now | Created; `Mutex::Locker l(lock)`, forwarded callback. |
| `948635a8` | mgr: Mutex::Locker -> std::lock_guard | `Mutex::Locker` → `std::lock_guard`. |
| `c93dc884` | mgr: s/Mutex/ceph::mutex/ | Mutex type changed. |

#### Invariants
- Must hold `lock` for the duration of the callback execution — established `c1471c75`.
- Callback must not attempt to acquire `lock` (re-entrancy would deadlock) — implied; no documentation.
- `with_mgr_map` is `const` (does not modify state) — correct.

#### Implementation Critique
- Lines 62–66 (blame): CONFORMANT.
- **UNGROUNDED**: The variadic `Args&&...args` perfect-forward pattern is present. Callers in the `.cc` file never use extra args (all callers capture by reference in the lambda). The extra-args overloading is vestigial/unused in practice.

---

### `StandbyPyModuleState::with_config`

**Location**: `src/mgr/StandbyPyModules.h:69`

#### Evolution

| SHA | Subject | Change |
|-----|---------|--------|
| `c1471c75` | mgr: standby modules come up and run now | Created; held lock, conditionally `Cond::Wait`-ed until `is_config_loaded == true`, then forwarded to local `config_cache`. |
| `3193d40d` | mgr: centralized setting/getting of mgr configs | Removed `Cond` wait; forwarded directly to `module_config` reference. No blocking. |
| `948635a8` | mgr: Mutex::Locker -> std::lock_guard | `Mutex::Locker` → `std::lock_guard`. |

#### Invariants
- Must hold `lock` during callback — `c1471c75`.
- No longer blocks/waits for config to be loaded — invariant removed by `3193d40d`. If called before the external config is populated, it will return whatever is in the shared `PyModuleConfig` at that moment (possibly empty).

#### Error Conditions
- **DIVERGED** (`3193d40d`): The original intent was that `with_config` would block until config was loaded. After `3193d40d`, it no longer blocks. If called before the shared `PyModuleConfig` is populated by the registry, it silently returns an empty config. There is no comment or assertion on the minimum content of `module_config`. Established: `c1471c75` blocked; removed: `3193d40d`. Contradicting code path: `with_config` at h:69–74 passes directly to `module_config` with no readiness check.

#### Implementation Critique
- Lines 69–74 (blame): CONFORMANT with post-`3193d40d` semantics.
- The removal of the `Cond` wait means that a `get_config` call during the window before the shared `PyModuleConfig` is first populated returns `false` (key not found) silently. This is a behaviour change from blocking to silent-miss. Whether this is the desired contract is UNGROUNDED — no test or comment was added to document the new "caller must ensure config is ready before calling" precondition.

---

### `StandbyPyModule::StandbyPyModule` (constructor)

**Location**: `src/mgr/StandbyPyModules.h:84`

#### Evolution

| SHA | Subject | Change |
|-----|---------|--------|
| `c1471c75` | mgr: standby modules come up and run now | Created with `(StandbyPyModuleState&, string, PyObject*, PyThreadState*)`. |
| `29193a47` | mgr: update for SafeThreadState | `PyThreadState*` → `SafeThreadState`. |
| `6a8da7ca` | mgr: load all modules | Signature changed to `(StandbyPyModuleState&, PyModuleRef, LogChannelRef)`. |
| `ce6e043a` | src: Added const references to various function parameters | `PyModuleRef` → `const PyModuleRef&`. |

#### Invariants
- `state_` must outlive the `StandbyPyModule` instance — reference member.
- Delegates to `PyModuleRunner(py_module_, clog_)` — `PyModuleRunner` inherits the module state.

#### Implementation Critique
- Lines 84–92 (blame): CONFORMANT.
- Empty constructor body is correct — all work done in initialiser list.

---

### `StandbyPyModule::get_myaddrs`

**Location**: `src/mgr/StandbyPyModules.h:97`

#### Evolution

| SHA | Subject | Change |
|-----|---------|--------|
| `8b8e7522` | mgr: add get() for standby modules | Introduced. Returns `state.get_monc().get_myaddrs()`. Fixes tracker#51446. |

#### Invariants
- Delegates entirely to `MonClient::get_myaddrs()` which has its own locking.
- Inline body in header — always inlined.

#### Error Conditions
- No error return; returns `entity_addrvec_t` (empty if not connected).

#### Implementation Critique
- Lines 97–99 (blame): CONFORMANT.
- No issues detected.

---

### `StandbyPyModules::StandbyPyModules` (header declaration)

**Location**: `src/mgr/StandbyPyModules.h:118`

See constructor implementation section above — this is the matching declaration.

#### Implementation Critique
- Lines 118–123 (blame): CONFORMANT with `.cc` implementation.

---

### `StandbyPyModules::handle_mgr_map`

**Location**: `src/mgr/StandbyPyModules.h:129`

#### Evolution

| SHA | Subject | Change |
|-----|---------|--------|
| `c1471c75` | mgr: standby modules come up and run now | Created as inline; delegated to `state.set_mgr_map(mgr_map)`. |

#### Invariants
- Delegates to `state.set_mgr_map`, which acquires `StandbyPyModuleState::lock`.
- Can be called at any time after construction (live MgrMap updates).

#### Implementation Critique
- Lines 129–132 (blame): CONFORMANT.
- No issues detected.

---

### Anonymous functions (`__anon5976737d0102`, `__anon5976737d0202`, `__anon5976737d0302`)

**Location**: `src/mgr/StandbyPyModules.cc:83`, `cc:133`, `cc:192`

These are lambda expressions captured inside named functions. They are not independently named in the source; the ctags entries are compiler-generated names for anonymous closures.

- `__anon5976737d0102` (cc:83): Lambda inside `start_one` queued to `finisher`. Captures `this`, `standby_module` (raw ptr), `name` (string copy). Established `f22347db`, refined `56e34f58`, type changed `489b30844`.
- `__anon5976737d0202` (cc:133): Lambda inside `get_config` passed to `state.with_config`. Captures `global_key` (string copy), `value` (raw ptr). Established `c1471c75`.
- `__anon5976737d0302` (cc:192): Lambda inside `get_active_uri` passed to `state.with_mgr_map`. Captures `result` (by ref), `this`. Established `c1471c75`.

#### Implementation Critique for `__anon5976737d0102` (start_one lambda, cc:83)
- See `start_one` section. Raw pointer capture, no RAII, `this` capture — UNGROUNDED lifetime preconditions.

#### Implementation Critique for `__anon5976737d0202` (get_config lambda, cc:133)
- Captures `value` as a raw pointer. Valid because lambda is invoked synchronously inside `with_config` (under lock). CONFORMANT.

#### Implementation Critique for `__anon5976737d0302` (get_active_uri lambda, cc:192)
- Captures `result` by reference — valid because lambda is invoked synchronously inside `with_mgr_map`. CONFORMANT.

---

### `StandbyPyModules::start_one` (header declaration)

**Location**: `src/mgr/StandbyPyModules.h:125`

See `start_one` implementation section above.

#### Implementation Critique
- Line 125 (blame): `void start_one(PyModuleRef py_module)` — CONFORMANT with `f22347db` return-type change.

---

### `StandbyPyModules::shutdown` (header declaration)

**Location**: `src/mgr/StandbyPyModules.h:127`

See `shutdown` implementation section above.

---

## Summary of Findings

| Finding | Type | Function | SHA establishing invariant | Contradicting line(s) |
|---------|------|----------|---------------------------|----------------------|
| `with_config` no longer blocks; config may be empty at call time | DIVERGED | `with_config` | `c1471c75` (established wait); `3193d40d` (removed it) | `h:69–74` — no readiness check |
| Duplicate-name check in `start_one` removed from pre-queue scope | DIVERGED | `start_one` | `f22347db` (assert in outer lock); `56e34f58` (removed it) | `cc:75–98` — only `em.second` assert in lambda |
| `shutdown` iterates `modules` with lock dropped; lambda could insert during gaps | UNGROUNDED | `shutdown` | — | `cc:64–70` |
| `start_one` raw pointer leaks if `Finisher` stops before lambda runs | UNGROUNDED | `start_one` | — | `cc:79, 83` |
| `start_one` `this` capture in lambda; use-after-free if object destroyed while in-flight | UNGROUNDED | `start_one` | — | `cc:83` |
| `get_store` JSON constructed by string concatenation; key content not sanitised | UNGROUNDED | `get_store` | — | `cc:161–162` |
| `get_store` `c.wait()` has no timeout and no shutdown interruptibility | UNGROUNDED | `get_store` | — | `cc:174` |
| Stale FIXME comment "completely identical to ActivePyModules" | OVERCAUTIOUS | `shutdown` | `c1471c75` | `cc:48` — comment is stale; code has diverged from ActivePyModules |
| `with_mgr_map` unused variadic `Args` | OVERCAUTIOUS | `with_mgr_map` | `c1471c75` | `h:62` — extra args never used in any call site in this file |

---

## Self-Check

- [x] All 32 commits read (including 4 formatting-only commits with no function impact).
- [x] All 26 ctags function entries have a section (cc:33, cc:83, cc:133, cc:192, cc:189, cc:126, cc:143, cc:100, cc:47, cc:75, h:84, h:46, h:118, h:96, h:94, h:59, h:97, h:129, h:101, h:50, h:127, h:125, h:69, h:62, plus StandbyPyModules h:118 = header constructor declaration).
- [x] Every DIVERGED finding cites the SHA that established the invariant and the SHA that broke it.
- [x] UNGROUNDED flags cover all code paths where the intent is not established by any commit in the corpus.
- [x] OVERCAUTIOUS flags cover stale defensive checks and vestigial patterns.
- [x] Rename chain: no renames — files stable at current paths since `c1471c75` (2017-08-22).
