# Intent Artefact — `src/mgr/Gil.cc` / `src/mgr/Gil.h`

**Generated:** 2026-09-11  
**HEAD SHA:** `8681fa6ebac230f86eb445bf57095c63e7f1abcc`  
**Corpus collected at:** 2026-09-11T21:40:59Z  
**Total non-merge commits in scope:** 14  
**Date range:** 2017-05-12 → 2025-12-18  
**Files:** `src/mgr/Gil.cc` (created `23c3a075`), `src/mgr/Gil.h` (created `f36b0d9d`)

---

## Corpus Overview

| SHA (short) | Date | Author | Subject |
|---|---|---|---|
| `f36b0d9d` | 2017-05-12 | Tim Serong | mgr: use new Gil class in place of PyGILState_*() API |
| `987612a9` | 2017-07-26 | John Spray | mgr: reduce Gil verbosity at level 20 |
| `23c3a075` | 2017-08-22 | John Spray | mgr: move Gil implementation into .cc |
| `625e1b5c` | 2017-10-03 | John Spray | mgr: safety checks on pyThreadState usage |
| `39ffec28` | 2018-04-25 | Danny Al-Gaaf | misc: mark constructors as explicit |
| `ab23c506` | 2018-08-23 | Adam C. Emerson | mgr: Use ceph_assert for asserts |
| `88db7b19` | 2021-02-18 | Kefu Chai | mgr: move GIL helpers to Gil.{h,cc} |
| `6469a9a6` | 2021-11-24 | Sage Weil | mgr/ActivePyModule: avoid with_gil where possible |
| `f1bac418` | 2025-10-01 | Edwin Rodriguez | Update indent settings cc |
| `85d82faa` | 2025-10-01 | Edwin Rodriguez | Update indent settings h |
| `c8c1019d` | 2025-10-02 | Edwin Rodriguez | Add missing blank line after comment block |
| `4adaf64d` | 2025-10-02 | Edwin Rodriguez | Add blank line after header block |
| `19a9981e` | 2025-12-18 | Samuel Just | mgr/Gil.cc: do not use PyGILState_Check() |
| `fb26bcd9` | 2025-12-18 | Samuel Just | mgr/Gil.cc: simplify Gil(), ~Gil() |

---

## Rename Chain

- `src/mgr/Gil.h`: single path throughout (`f36b0d9d` → `4adaf64d`, no renames)
- `src/mgr/Gil.cc`: single path throughout (`23c3a075` → `fb26bcd9`, no renames)

---

## Design Purpose

`Gil.h`/`Gil.cc` provide RAII wrappers around Python's Global Interpreter Lock (GIL) for use in Ceph's manager daemon (`mgr`). The module was created (`f36b0d9d`) as a replacement for the `PyGILState_*()` API, which is incompatible with Python sub-interpreters. The design enforces that:

1. GIL acquisition/release is paired and stack-scoped.
2. A thread-state is always associated with the correct POSIX thread.
3. "New thread" paths (C++ threads not created by Python) get a dedicated `PyThreadState`.
4. Non-GIL sections can be explicitly delimited with `without_gil_t`/`with_gil_t`.

---

## Functions

---

### `assert_gil` — `src/mgr/Gil.cc:28`

**Establishing commits:** `19a9981e`

**Intent:**  
A file-scoped (`static`) helper that asserts the calling thread currently holds the GIL. Introduced by `19a9981e` (Fixes: https://tracker.ceph.com/issues/74220) to replace `assert(PyGILState_Check())`, which is inappropriate in sub-interpreter contexts. `PyGILState_Check()` only returns true for threads initialized via `PyGILState_Ensure()`; in a process that has ever created sub-interpreters it always returns 1, masking real errors. The replacement uses `PyThreadState_Get()` (which returns the current thread state or aborts if none) plus a `thread_id` equality check against `PyThread_get_thread_ident()`.

**Invariants:**
- Must be called only from a thread that currently holds the GIL (i.e. `PyEval_RestoreThread` has been called for this thread). Calling without a current thread state causes `PyThreadState_Get()` to abort the process — this is intentional as an always-fatal precondition failure. (Established: `19a9981e`)
- `ts->thread_id` must equal `PyThread_get_thread_ident()` for the calling OS thread. (Established: `19a9981e`)
- The comment (`19a9981e`) notes that `ts->thread_id` "isn't necessarily stable, and may need to change in the future" and that once Python < 3.13 support is dropped, `PyThreadState_GetUnchecked()` can replace `PyThreadState_Get()`. This is a documented limitation, not a bug.

**Implementation critique (Gil.cc:28–50):**

```
Gil.cc:28  static void assert_gil()
Gil.cc:47  auto *ts = PyThreadState_Get();
Gil.cc:48  ceph_assert(ts != nullptr);
Gil.cc:49  ceph_assert(ts->thread_id == PyThread_get_thread_ident());
```

- Line 48: `ceph_assert(ts != nullptr)` is dead code. `PyThreadState_Get()` itself aborts if there is no current thread state (Python C-API contract pre-3.13). The check is therefore always true when reached. **OVERCAUTIOUS** — the guard at line 48 was inherited from a defensive pattern but is never reachable. The comment at lines 44–46 documents the planned `PyThreadState_GetUnchecked()` migration path.
- Line 49: The `thread_id` check is the real assertion. Correct.
- The function is `static` — not exposed in the header. CORRECT; it is an implementation-internal invariant enforcer.

---

### `SafeThreadState` (constructor with `PyThreadState*`) — `src/mgr/Gil.h:35` / `src/mgr/Gil.cc:52`

**Establishing commits:** `625e1b5c` (class created), `ab23c506` (`assert`→`ceph_assert`), `39ffec28` (`explicit`)

**Intent:**  
Wraps a `PyThreadState*` together with the `pthread_t` of the thread on which it was created. The purpose is to give `Gil::Gil` a way to assert (at construction time) that a non-new-thread GIL acquire is happening from the correct POSIX thread. This closed a silent misuse hole where callers would pass `new_thread=false` from the wrong thread (`625e1b5c` subject: "Previously relied on the caller of Gil() to pass new_thread=true if they would be calling from a different thread. Enforce this with an assertion").

**Invariants:**
- `ts_` must not be null. (`ceph_assert(ts != nullptr)` — established `625e1b5c`, hardened `ab23c506`)
- `thread` is set to `pthread_self()` at construction, capturing the creating thread. (Established: `625e1b5c`)
- Constructor is `explicit` to prevent accidental implicit construction from a raw `PyThreadState*`. (Established: `39ffec28`)

**Implementation critique (Gil.cc:52–57 / Gil.h:35–49):**

```
Gil.cc:52  SafeThreadState::SafeThreadState(PyThreadState *ts_)
Gil.cc:53      : ts(ts_)
Gil.cc:55  ceph_assert(ts != nullptr);
Gil.cc:56  thread = pthread_self();
```

- Line 55: `ceph_assert(ts != nullptr)` — correct and grounded. (`625e1b5c`)
- Line 56: `thread = pthread_self()` — correct; captures the creating thread. (`625e1b5c`)
- The default constructor (`Gil.h:37–40`) sets `ts(nullptr)` and `thread(0)`. This creates a `SafeThreadState` that will crash if passed to `Gil::Gil` because `ceph_assert(ts != nullptr)` is in the explicit-argument constructor. However, the default constructor exists for deferred initialization via `set()`. **UNGROUNDED**: there is no guard preventing a default-constructed `SafeThreadState` (with `ts=nullptr`) from being passed to the `Gil` constructor, which would then dereference `pThreadState.ts` without checking for null. The `SafeThreadState` explicit constructor checks `ts != nullptr`, but the default constructor does not prevent `ts` from remaining null indefinitely before being passed to `Gil`. Risk is mitigated in practice because `set()` exists and callers use it, but there is no compile-time or runtime enforcement.

---

### `SafeThreadState` (default constructor) — `src/mgr/Gil.h:37`

**Establishing commits:** `625e1b5c`

**Intent:**  
Allows deferred initialization: create a `SafeThreadState` in a context where the `PyThreadState` is not yet known, then call `set()` once it is. Used by long-lived Python module objects that initialize their thread state after Python starts.

**Invariants:**
- `ts` is null and `thread` is 0 until `set()` is called. Not a contract violation by itself; the object is in an "uninitialized" state until `set()`.

**Implementation critique (Gil.h:37–40):**
- No issues with the constructor itself. The hazard (null `ts` used in `Gil`) is documented under `SafeThreadState` explicit constructor above.

---

### `SafeThreadState::set` — `src/mgr/Gil.h:45`

**Establishing commits:** `625e1b5c`

**Intent:**  
Update a default-constructed (or stale) `SafeThreadState` to a new `PyThreadState*`, capturing the current POSIX thread as the owning thread. Intended to be called from the thread that will own the GIL for the associated interpreter.

**Invariants:**
- No null check on `ts_` parameter. **UNGROUNDED** — the explicit constructor asserts `ts_ != nullptr`, but `set()` has no corresponding guard. A caller could `set(nullptr)` silently. (No commit establishes a null guard here.)
- `thread` is updated atomically to `pthread_self()` together with `ts`. (Established: `625e1b5c`)

**Implementation critique (Gil.h:45–49):**

```
Gil.h:45  void set(PyThreadState *ts_)
Gil.h:46  {
Gil.h:47    ts = ts_;
Gil.h:48    thread = pthread_self();
Gil.h:49  }
```

- No `ceph_assert(ts_ != nullptr)` guard. Inconsistent with `SafeThreadState(PyThreadState *ts_)` which has this check. **DIVERGED** from the invariant established in `625e1b5c`: that invariant covers only the explicit constructor, but the `set()` method is an alternative initialization path that bypasses it. No commit was ever made to add a null check here.

---

### `Gil::Gil` (constructor) — `src/mgr/Gil.h:69` / `src/mgr/Gil.cc:59`

**Establishing commits:** `f36b0d9d` (created), `987612a9` (log level), `23c3a075` (moved to .cc), `625e1b5c` (SafeThreadState, pthread assert), `ab23c506` (ceph_assert), `fb26bcd9` (simplify logic), `19a9981e` (add assert_gil call)

**Intent:**  
Acquires the Python GIL for the duration of the enclosing scope. Two paths:

1. **`new_thread = false` (default):** Caller is on the same POSIX thread that created the `SafeThreadState`. Calls `PyEval_RestoreThread(pThreadState.ts)` to acquire GIL, then asserts `pthread_self() == pThreadState.thread`. Finally calls `assert_gil()` to confirm GIL ownership via thread-state inspection.

2. **`new_thread = true`:** Caller is on a C++ thread not created by Python. Creates a fresh `PyThreadState` for this OS thread with `PyThreadState_New(pThreadState.ts->interp)`, then calls `PyEval_RestoreThread(pNewThreadState)` to acquire GIL and activate the new state. Also calls `assert_gil()`.

The class is copy-deleted (`Gil(const Gil&) = delete; Gil& operator=(const Gil&) = delete`) to prevent accidental duplication.

**Invariants:**
- `pThreadState.ts` must not be null before use. (Established: `625e1b5c` via `SafeThreadState` constructor assert)
- For `new_thread=false`: `pthread_self() == pThreadState.thread`. (Established: `625e1b5c`, `ceph_assert` hardened `ab23c506`)
- After either branch: `assert_gil()` must pass — GIL is held, thread state is current. (Established: `fb26bcd9`, `19a9981e`)
- Must not be nested on the same thread (would deadlock via `PyEval_RestoreThread`). (Established by comment since `f36b0d9d`)

**Key structural change (`fb26bcd9`):**  
Before `fb26bcd9`: `new_thread=true` path called `PyEval_RestoreThread(pThreadState.ts)` first (acquiring GIL on original state), then `PyThreadState_Swap(pNewThreadState)` (switching current state). After `fb26bcd9`: simply calls `PyEval_RestoreThread(pNewThreadState)` directly — equivalent result with one fewer round-trip through the original thread state.

**Implementation critique (Gil.cc:59–90):**

```
Gil.cc:59  Gil::Gil(SafeThreadState &ts, bool new_thread) : pThreadState(ts)
Gil.cc:79  if (new_thread) {
Gil.cc:80    pNewThreadState = PyThreadState_New(pThreadState.ts->interp);
Gil.cc:81    PyEval_RestoreThread(pNewThreadState);
Gil.cc:82    dout(20) << "Switched to new thread state " << pNewThreadState << dendl;
Gil.cc:83  } else {
Gil.cc:84    // Acquire the GIL, set the current thread state
Gil.cc:85    PyEval_RestoreThread(pThreadState.ts);
Gil.cc:86    dout(25) << "GIL acquired for thread state " << pThreadState.ts << dendl;
Gil.cc:87    ceph_assert(pthread_self() == pThreadState.thread);
Gil.cc:89  assert_gil();
```

- Line 80: `PyThreadState_New` may return null if the interpreter has been finalized. No null check on `pNewThreadState` before passing to `PyEval_RestoreThread`. **UNGROUNDED** — no commit ever addressed `PyThreadState_New` return null. If it returns null, `PyEval_RestoreThread(nullptr)` aborts. Acceptable in practice (finalized interpreter is a fatal condition) but the path is never documented.
- Line 87: `ceph_assert(pthread_self() == pThreadState.thread)` is placed AFTER `PyEval_RestoreThread` (line 85), meaning if the assert fires, the GIL was already acquired but the destructor will NOT run (abort). The GIL would be leaked. **DIVERGED** from the intent of `625e1b5c` which was to enforce thread correctness as a pre-condition — but the check happens post-acquisition. The commit `625e1b5c` placed the assert in the else branch without restructuring to make it a pre-acquisition check.
- Line 89: `assert_gil()` call after the if/else is grounded in `fb26bcd9` and `19a9981e`. Correct.
- Log level 20 for new_thread, 25 for existing-thread — established by `987612a9`/`23c3a075` and the arrangement is consistent with the current blame.

---

### `Gil::operator=` / copy-deleted constructors — `src/mgr/Gil.h:66–67`

**Establishing commits:** `f36b0d9d`

**Intent:**  
Prevent copying `Gil` objects, which would cause double-release of the GIL (two destructors, two `PyEval_SaveThread` calls).

**Implementation critique (Gil.h:66–67):**
- Correct. No issues.

---

### `Gil::~Gil` (destructor) — `src/mgr/Gil.h:70` / `src/mgr/Gil.cc:92`

**Establishing commits:** `f36b0d9d` (created), `23c3a075` (moved to .cc), `625e1b5c` (SafeThreadState), `88db7b19` (moved here after GIL helpers added), `fb26bcd9` (simplified; split into two branches)

**Intent:**  
Releases the GIL and, for the `new_thread` path, clears and deletes the temporary `PyThreadState`. Establishes that the thread has no current Python state after destruction.

**Two paths:**

1. **`pNewThreadState != nullptr` (new_thread path):**  
   `PyThreadState_Clear(pNewThreadState)` — clears the thread state (releases Python references held by it).  
   `PyEval_SaveThread()` — releases the GIL and nulls the current thread state.  
   `PyThreadState_Delete(pNewThreadState)` — frees the thread state memory.

2. **`pNewThreadState == nullptr` (normal path):**  
   `PyEval_SaveThread()` — releases the GIL, resets current thread state to null.

**Key structural change (`fb26bcd9`):**  
Before `fb26bcd9`: `new_thread` path did `PyThreadState_Swap(pThreadState.ts)` before clearing `pNewThreadState`, then a single `PyEval_SaveThread()` at the end that covered both branches. The swap restored the original thread state before release.  
After `fb26bcd9`: The swap is eliminated. `PyThreadState_Clear` is called while still on `pNewThreadState`, then `PyEval_SaveThread()` is called (which saves current=`pNewThreadState` and sets current to null), then `PyThreadState_Delete` frees it. The original `pThreadState.ts` is NOT restored as current — it was never made current in the new path post-`fb26bcd9` (only `pNewThreadState` was).

**Invariants:**
- GIL is released in all code paths through `PyEval_SaveThread()`. (Established: `f36b0d9d`)
- `PyThreadState_Clear` precedes `PyThreadState_Delete` for new_thread path. (Established: `f36b0d9d`)
- `PyEval_SaveThread()` is called exactly once per code path post-`fb26bcd9`. (Established: `fb26bcd9`)

**Implementation critique (Gil.cc:92–104):**

```
Gil.cc:92  Gil::~Gil()
Gil.cc:94  // Release the GIL, reset the thread state to NULL
Gil.cc:95  if (pNewThreadState != nullptr) {
Gil.cc:96    dout(20) << "Destroying new thread state " << pNewThreadState << dendl;
Gil.cc:97    PyThreadState_Clear(pNewThreadState);
Gil.cc:98    PyEval_SaveThread();
Gil.cc:99    PyThreadState_Delete(pNewThreadState);
Gil.cc:100 } else {
Gil.cc:101   PyEval_SaveThread();
Gil.cc:102 }
Gil.cc:103 dout(25) << "GIL released for thread state " << pThreadState.ts << dendl;
```

- Line 97–99: **UNGROUNDED**: `PyEval_SaveThread()` is called while the current thread state is `pNewThreadState`. Its return value (a `PyThreadState*` equal to `pNewThreadState`) is discarded. The pointer is then passed to `PyThreadState_Delete`. This is valid per CPython internals (the return value of `PyEval_SaveThread` is the same as what `PyThreadState_Delete` takes), but there is a subtle correctness assumption: after `PyEval_SaveThread`, the current thread state is NULL, so `PyThreadState_Delete` is safe to call. No commit documents this reasoning — it is implicit from the `fb26bcd9` refactor.
- Line 97: `PyThreadState_Clear(pNewThreadState)` is called while `pNewThreadState` is the current thread state. The Python docs say `PyThreadState_Clear` "Reset all information in a thread state object. The GIL must be held." GIL is held here — correct. But clearing the *current* thread state is unusual. **UNGROUNDED** — no commit comment justifies this ordering; it was the consequence of the `fb26bcd9` refactor eliminating the swap-back.
- Line 103: The log message says "GIL released for thread state `pThreadState.ts`" in both branches. In the `new_thread` path, the GIL was actually held by `pNewThreadState`, not `pThreadState.ts`. The log message is misleading in that branch. **DIVERGED** — the log accurately described the pre-`fb26bcd9` world (where `pThreadState.ts` was restored before `SaveThread`); post-`fb26bcd9`, it is inaccurate for the `new_thread` branch.

---

### `without_gil_t` (constructor) — `src/mgr/Gil.h:88` / `src/mgr/Gil.cc:106`

**Establishing commits:** `88db7b19` (created), `19a9981e` (`assert(PyGILState_Check())` → `assert_gil()`)

**Intent:**  
RAII entry to a "no-GIL" section, analogous to `Py_BEGIN_ALLOW_THREADS`. On construction: asserts the GIL is held (`assert_gil()`), then releases it via `PyEval_SaveThread()`. The saved thread state is stored in `save` for reacquisition.

The locking policy enforced (comment, `88db7b19`):
1. Do not acquire non-GIL locks while holding the GIL.
2. Always hold the GIL when calling Python functions.

**Invariants:**
- GIL must be held by the calling thread on entry. (Established: `88db7b19` as `assert(PyGILState_Check())`; replaced `19a9981e` with `assert_gil()` due to sub-interpreter incompatibility, Fixes: #74220)
- `release_gil()` is always called in the constructor — `save` is always non-null after a successful construction. (Established: `88db7b19`)

**Implementation critique (Gil.cc:106–110):**

```
Gil.cc:106  without_gil_t::without_gil_t()
Gil.cc:108  assert_gil();
Gil.cc:109  release_gil();
```

- Line 108: `assert_gil()` — grounded in `19a9981e`. Correct.
- Line 109: `release_gil()` — calls `PyEval_SaveThread()`, stores result in `save`. Correct.
- No issues.

---

### `without_gil_t::~without_gil_t` (destructor) — `src/mgr/Gil.h:89` / `src/mgr/Gil.cc:112`

**Establishing commits:** `88db7b19`

**Intent:**  
If `save` is non-null (GIL has not already been reacquired), reacquire the GIL. If `save` is null, the GIL was already reacquired (e.g. via explicit `acquire_gil()` or via `with_gil_t`), so the destructor is a no-op. This is the "idempotent release" pattern described in `6469a9a6`: allows explicit `acquire_gil()` calls without a spurious lock/unlock cycle at destruction.

**Invariants:**
- If `save != nullptr`, `acquire_gil()` is called. (Established: `88db7b19`)
- If `save == nullptr` (GIL already taken back), destructor is no-op. (Established implicitly at `88db7b19`; explicitly documented at `6469a9a6`)

**Implementation critique (Gil.cc:112–117):**

```
Gil.cc:112  without_gil_t::~without_gil_t()
Gil.cc:114  if (save) {
Gil.cc:115    acquire_gil();
Gil.cc:116  }
```

- Line 114–116: Correct. The `if (save)` guard matches the documented intent.
- No issues.

---

### `without_gil_t::release_gil` — `src/mgr/Gil.h:90` / `src/mgr/Gil.cc:119`

**Establishing commits:** `88db7b19` (created private), `6469a9a6` (made public)

**Intent:**  
Release the GIL by calling `PyEval_SaveThread()` and storing the returned thread-state pointer in `save`. Can be called explicitly post-`6469a9a6` (made public). Before `6469a9a6` it was private, callable only from the constructor and (via `friend`) from `with_gil_t`.

**Invariants:**
- After call: `save` holds the suspended thread state. (Established: `88db7b19`)
- Calling `release_gil()` when `save` is already non-null would leak a thread state (calling `PyEval_SaveThread` when GIL is not held is undefined behavior). No guard prevents double-release. **UNGROUNDED** — no commit addresses this.

**Implementation critique (Gil.cc:119–122):**

```
Gil.cc:119  void without_gil_t::release_gil()
Gil.cc:121  save = PyEval_SaveThread();
```

- Line 121: No pre-condition check that `save == nullptr` (i.e., that GIL is currently held). If `release_gil()` is called when GIL is not held, `PyEval_SaveThread()` has undefined behavior. **UNGROUNDED** — the implicit pre-condition (GIL must be held) is never asserted, even though `assert_gil()` exists and is called from the constructor path. Since `release_gil()` became public (`6469a9a6`), it is now callable from arbitrary caller contexts without the constructor's pre-condition check.

---

### `without_gil_t::acquire_gil` — `src/mgr/Gil.h:91` / `src/mgr/Gil.cc:124`

**Establishing commits:** `88db7b19` (created private), `6469a9a6` (made public)

**Intent:**  
Reacquire the GIL using the saved thread state. `PyEval_RestoreThread(save)` blocks until the GIL is available, then sets `save = nullptr` (marking that the GIL is now held and the saved state is consumed).

**Invariants:**
- `save` must be non-null on entry. (Established: `88db7b19` via `assert(save)`)
- After call: `save` is null. (Established: `88db7b19`)

**Implementation critique (Gil.cc:124–129):**

```
Gil.cc:124  void without_gil_t::acquire_gil()
Gil.cc:126  assert(save);
Gil.cc:127  PyEval_RestoreThread(save);
Gil.cc:128  save = nullptr;
```

- Line 126: `assert(save)` — plain stdlib `assert`, NOT `ceph_assert`. **DIVERGED** — the codebase uses `ceph_assert` throughout this file (lines 55, 87, 48, 49 all use `ceph_assert`). This is a `88db7b19` artifact: Kefu Chai introduced this with plain `assert` and no subsequent commit (`ab23c506` which mechanically replaced `assert` with `ceph_assert` in existing functions only touched `SafeThreadState` and `Gil::Gil`) upgraded this one. The divergence from project style is observable but not a semantic error — both abort on failure in debug builds.
- Lines 127–128: Correct — reacquires GIL and nulls save pointer.

---

### `with_gil_t` (constructor) — `src/mgr/Gil.h:98` / `src/mgr/Gil.cc:131`

**Establishing commits:** `88db7b19`

**Intent:**  
Temporarily reacquire the GIL inside a `without_gil_t` scope. Holds a reference to the enclosing `without_gil_t` so it can release the GIL again on destruction. The intent from `6469a9a6` is that when `with_gil_t` is used as the FINAL operation in a `without_gil_t` scope, the destructor of `with_gil_t` will release the GIL, and then `~without_gil_t()` sees `save == nullptr` (because `with_gil_t::~with_gil_t` calls `release_gil()`, re-setting `save`) — wait, actually the flow is: `~with_gil_t()` calls `allow_threads.release_gil()` → sets `save` to new value → then `~without_gil_t()` sees `save != nullptr` and calls `acquire_gil()` again. The `6469a9a6` optimization is about NOT using `with_gil_t` at all — instead calling `no_gil.acquire_gil()` directly, so `~without_gil_t()` is a no-op.

**Invariants:**
- `allow_threads` must have `save != nullptr` (GIL not currently held) on construction. (Implicit; if `save == nullptr`, `acquire_gil()` → `assert(save)` fires)
- After construction: GIL is held by this thread.

**Implementation critique (Gil.cc:131–135):**

```
Gil.cc:131  with_gil_t::with_gil_t(without_gil_t& allow_threads)
Gil.cc:132    : allow_threads{allow_threads}
Gil.cc:134  allow_threads.acquire_gil();
```

- Line 134: Calls `acquire_gil()`, which has `assert(save)`. If `allow_threads.save` is null (GIL already held), this fires. Correct pre-condition enforcement, though via the indirect `assert(save)` in `acquire_gil()`.
- Lines 132–133 (blame origin `9c652fb3`/`ActivePyModules.cc`): The initializer list `allow_threads{allow_threads}` is correctly capturing the reference. No issues.

---

### `with_gil_t::~with_gil_t` (destructor) — `src/mgr/Gil.h:99` / `src/mgr/Gil.cc:137`

**Establishing commits:** `88db7b19`

**Intent:**  
Release the GIL by delegating to `allow_threads.release_gil()`, restoring the `without_gil_t`'s saved state so that the enclosing `without_gil_t` destructor can re-acquire if needed.

**Invariants:**
- After call: GIL is released; `allow_threads.save` is non-null.

**Implementation critique (Gil.cc:137–140):**

```
Gil.cc:137  with_gil_t::~with_gil_t()
Gil.cc:139  allow_threads.release_gil();
```

- Line 139: `allow_threads.release_gil()` — calls `PyEval_SaveThread()`. If the GIL is not currently held (e.g., `allow_threads` was manually re-used), this is undefined behavior. No guard. **UNGROUNDED** — same root cause as `release_gil()` lacking a pre-condition check.
- No other issues.

---

### `with_gil<Func>` — `src/mgr/Gil.h:106`

**Establishing commits:** `88db7b19`

**Intent:**  
Convenience template that re-acquires the GIL for the duration of a callable `func`, using `with_gil_t` RAII. Designed as: acquire GIL → call `func` → release GIL (via `~with_gil_t`).

**Invariants:**
- Same as `with_gil_t`: `no_gil.save` must be non-null.

**Implementation critique (Gil.h:106–109):**

```
Gil.h:106  auto with_gil(without_gil_t& no_gil, Func&& func) {
Gil.h:107    with_gil_t gil{no_gil};
Gil.h:108    return std::invoke(std::forward<Func>(func));
Gil.h:109  }
```

- Lines 107–108: Correct RAII usage; `gil` is destroyed after `func` returns, releasing the GIL.
- No issues.

---

### `without_gil<Func>` — `src/mgr/Gil.h:112`

**Establishing commits:** `88db7b19`

**Intent:**  
Convenience template that releases the GIL for the duration of a callable `func`. Creates a local `without_gil_t` (which asserts GIL held and releases it), calls `func`, then `~without_gil_t` reacquires.

**Invariants:**
- GIL must be held by the calling thread. (Established: `88db7b19` via `without_gil_t()` constructor's `assert_gil()`)

**Implementation critique (Gil.h:112–115):**

```
Gil.h:112  auto without_gil(Func&& func) {
Gil.h:113    without_gil_t no_gil;
Gil.h:114    return std::invoke(std::forward<Func>(func));
Gil.h:115  }
```

- Lines 113–114: Correct. `no_gil` is destroyed after `func` returns, reacquiring the GIL.
- No issues.

---

## Findings Summary

| Finding | Type | Function | Line | SHA establishing intent | Note |
|---|---|---|---|---|---|
| `assert_gil()` line 48: `ceph_assert(ts != nullptr)` is dead code | OVERCAUTIOUS | `assert_gil` | Gil.cc:48 | `19a9981e` | `PyThreadState_Get()` aborts on null — the assert is always true when reached |
| `SafeThreadState::set()` has no null check on `ts_` | DIVERGED | `SafeThreadState::set` | Gil.h:47 | `625e1b5c` | Explicit constructor checks null; `set()` bypasses this invariant |
| `Gil::Gil` — `ceph_assert(pthread_self() == pThreadState.thread)` fires AFTER `PyEval_RestoreThread` | DIVERGED | `Gil::Gil` | Gil.cc:87 | `625e1b5c` | Thread check is a post-acquisition check, not pre-acquisition; GIL would be leaked on assertion failure |
| `Gil::Gil` — `pNewThreadState` not checked for null after `PyThreadState_New` | UNGROUNDED | `Gil::Gil` | Gil.cc:80 | None | No commit addresses null return from `PyThreadState_New` |
| `Gil::~Gil` — `PyThreadState_Clear` called on the still-current thread state (`pNewThreadState`) before `PyEval_SaveThread` | UNGROUNDED | `~Gil` | Gil.cc:97 | `fb26bcd9` refactor (no comment) | Implicit assumption that clearing current state before `SaveThread` is safe |
| `Gil::~Gil` — log message "GIL released for thread state pThreadState.ts" inaccurate for new_thread path | DIVERGED | `~Gil` | Gil.cc:103 | `fb26bcd9` | Pre-`fb26bcd9`, log was accurate (pThreadState.ts was restored); post-refactor, GIL was held by pNewThreadState, not pThreadState.ts |
| `without_gil_t::acquire_gil()` uses plain `assert(save)` not `ceph_assert` | DIVERGED | `acquire_gil` | Gil.cc:126 | `88db7b19` | All other assertions in this file use `ceph_assert`; `ab23c506` missed this one |
| `without_gil_t::release_gil()` has no pre-condition check (GIL must be held) | UNGROUNDED | `release_gil` | Gil.cc:121 | None | Became callable publicly at `6469a9a6`; no guard added |
| `with_gil_t::~with_gil_t()` calls `release_gil()` without asserting GIL is held | UNGROUNDED | `~with_gil_t` | Gil.cc:139 | None | Same root cause as `release_gil` missing pre-condition; if GIL not held, `PyEval_SaveThread` is UB |

---

## Self-Check

- [x] All 14 commits read in full
- [x] All functions in `functions.txt` have a section (14 ctags entries → 12 logical functions: `assert_gil`, `SafeThreadState`×2, `SafeThreadState::set`, `Gil`×2 (ctor+dtor), `Gil::operator=`, `without_gil_t`×4, `with_gil_t`×2, `with_gil<>`, `without_gil<>`)
- [x] Every DIVERGED flag names the specific commit and contradicting line
- [x] Every invariant cites the SHA that established it
- [x] All UNGROUNDED code paths are flagged
- [x] OVERCAUTIOUS flags are documented
