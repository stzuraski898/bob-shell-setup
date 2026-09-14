# ThreadMonitor — Intent Artefact

**Object:** `src/mgr/ThreadMonitor.cc` / `src/mgr/ThreadMonitor.h`  
**Collected at:** 2026-09-11T21:40:59Z  
**HEAD SHA:** `8681fa6ebac230f86eb445bf57095c63e7f1abcc`  
**Commit range:** 2024-12-08 → 2026-05-27  
**Total commits analysed:** 2  

---

## Corpus Summary

| SHA (short) | Date | Author | Subject |
|---|---|---|---|
| `95a90f7d` | 2024-12-08 | Nitzan Mordechai | mgr: Add per-module performance counters to mgr |
| `28647966` | 2026-05-27 | Nitzan Mordechai | mgr/ThreadMonitor: monitor interval running in seconds and not nanoseconds |

No renames. Both files were created in `95a90f7d` and received a single follow-up fix in `28647966`. The collection HEAD `8681fa6e` did not touch either file.

---

## Design Intent

`ThreadMonitor` is a background monitor that periodically (every `mgr_module_monitor_interval` seconds) reads per-thread CPU usage from `/proc/self/task/<tid>/stat` and process-wide RSS from `/proc/self/statm`, then writes those values into existing `PerfCounters` objects that live on each registered `PyModule`. It is a `md_config_obs_t` observer so that runtime changes to `mgr_module_monitor_interval` take effect immediately without a restart.

The design separates locking into three phases per iteration: (1) under lock — read RSS, copy thread state; (2) unlocked — do slow `/proc` reads and CPU arithmetic; (3) under lock — write results back and purge dead threads. This is intentional to avoid holding the mutex during I/O.

---

## Function Sections

---

### `ThreadMonitor` (constructor) — `src/mgr/ThreadMonitor.h:21`

**Establishing commit:** `95a90f7d`  
**Last modified:** `28647966`

#### Intent

Construct the monitor bound to a `CephContext`. Initialise the `running` flag to false, read `mgr_module_monitor_interval` from config to set the initial polling interval, register as a config observer, and cache `sysconf(_SC_CLK_TCK)` / `sysconf(_SC_PAGESIZE)` for use throughout the lifetime of the object.

#### Invariants

- `running` MUST be `false` on construction so that `start_monitoring()` can be called explicitly by the caller. [established: `95a90f7d`]
- `monitoring_interval` MUST be in `std::chrono::seconds` units because the config key `mgr_module_monitor_interval` is defined in whole seconds. [established: `95a90f7d`; bug fixed: `28647966` — the original code passed the raw `int64_t` directly, which assigned nanoseconds to a `ceph::mono_clock::duration` field]
- `m_clock_ticks_per_sec` and `m_page_size` MUST be populated before `monitoring_loop()` is ever called; `monitoring_loop()` performs an explicit guard at entry against `<= 0` values. [established: `95a90f7d`]

#### Implementation critique

- **Line h:24 (blame: `28647966`):** `monitoring_interval(std::chrono::seconds(m_cct->_conf.get_val<int64_t>("mgr_module_monitor_interval")))` — correct after the fix. The original `95a90f7d` initialiser was `monitoring_interval(m_cct->_conf.get_val<int64_t>(...))`, which assigned the raw nanosecond-typed integer directly to a `ceph::mono_clock::duration` (nanoseconds resolution), causing a ~2-second config value to produce an ~2 ns interval. Fixed by `28647966`.
- **Line h:90 (blame: `95a90f7d`):** `ceph::mono_clock::duration monitoring_interval = std::chrono::seconds(2);` — the in-class member initialiser is a stale default. After `28647966` the constructor initialiser always overrides this with the live config value, so the `= std::chrono::seconds(2)` literal is never used. It is harmless but misleading. **UNGROUNDED.**
- **Lines h:27-28:** `sysconf(_SC_CLK_TCK)` and `sysconf(_SC_PAGESIZE)` return `-1` on error; the constructor stores this without validation. The monitoring_loop guard at cc:79 catches `<= 0` and aborts the loop, but the guard path has the thread-lifecycle bug described under `monitoring_loop`. **UNGROUNDED** (no documented intent for how a sysconf failure should propagate to the caller).

---

### `~ThreadMonitor` — `src/mgr/ThreadMonitor.h:31`

**Establishing commit:** `95a90f7d`  
**Last modified:** `95a90f7d`

#### Intent

Cleanly tear down the monitor: deregister from config observation so no further `handle_conf_change` callbacks arrive, then stop the background thread.

#### Invariants

- `remove_observer` MUST be called before `stop_monitoring()` to prevent a concurrent `handle_conf_change` from calling `start_monitoring()` after the thread has been stopped. [established: `95a90f7d`; order is intentional]

#### Implementation critique

- **Lines h:32-33:** Order is correct — `remove_observer` precedes `stop_monitoring()`. This prevents a race where the conf system fires a change between the two calls.
- **No DIVERGED findings.** The destructor is minimal and correct by the invariants of the two functions it calls.

---

### `start_monitoring` — `src/mgr/ThreadMonitor.cc:21`

**Establishing commit:** `95a90f7d`  
**Last modified:** `95a90f7d`

#### Intent

Start the background monitoring thread. The function must be idempotent — a second call while the monitor is already running must be a no-op.

#### Invariants

- The function MUST be idempotent via an atomic test-and-set on `running`. [established: `95a90f7d`]
- A new `std::thread` running `monitoring_loop` MUST be spawned only when the previous value of `running` was `false`. [established: `95a90f7d`]

#### Implementation critique

- **Lines cc:22-24:** `if (running.exchange(true)) { return; }` — correct atomic test-and-set. If the exchange returns `true`, the monitor was already running; early return. If it returns `false`, we proceed to start.
- **Line cc:27:** `monitor_thread = std::make_unique<std::thread>(...)` — replaces the `unique_ptr`. If `stop_monitoring` was called previously and the old thread was joined, `monitor_thread` still holds the joined thread object. Assigning a new `unique_ptr` destroys the old `std::thread` object after join, which is safe. If `stop_monitoring` was never called (a second `start_monitoring` call is impossible due to the guard), there is no scenario where the old thread is still running here.
- **UNGROUNDED:** If `monitoring_loop` exits due to the sysconf guard (sets `running=false` internally), the thread terminates but `monitor_thread` remains a joinable `std::thread`. A subsequent call to `start_monitoring` will pass the atomic guard (since `running` is now `false`), overwrite `monitor_thread` with a new `unique_ptr`, and destroy the old unjoinable-but-not-yet-destroyed thread object. `std::thread::~thread()` when joinable calls `std::terminate()`. See `monitoring_loop` for the root cause.

---

### `stop_monitoring` — `src/mgr/ThreadMonitor.cc:30`

**Establishing commit:** `95a90f7d`  
**Last modified:** `95a90f7d`

#### Intent

Stop the background monitoring thread and block until it has exited. The function must be idempotent — calling it when the monitor is not running must be a no-op.

#### Invariants

- The function MUST be idempotent via atomic exchange on `running`. [established: `95a90f7d`]
- The function MUST join the thread before returning so callers can rely on no further `/proc` reads or perf counter writes after return. [established: `95a90f7d`]

#### Implementation critique

- **Lines cc:31-33:** `if (!running.exchange(false)) { return; }` — correct guard. If `running` was already `false`, nothing to do.
- **Lines cc:35-38:** `if (monitor_thread && monitor_thread->joinable()) { monitor_thread->join(); }` — the `joinable()` check is necessary because the sysconf-failure path inside `monitoring_loop` sets `running=false` by itself, causing the thread to exit naturally. In that case, when the destructor calls `stop_monitoring`, `running` is already `false` so the `exchange(false)` returns `false` and the early return fires — the thread is **never joined**. The `unique_ptr<std::thread>` is then destroyed by the `~ThreadMonitor` destructor, calling `std::thread::~thread()` on a still-joinable thread, which invokes `std::terminate()`. **DIVERGED** from `95a90f7d` intent: the `joinable()` branch is unreachable via the normal stop path when the loop sets `running=false` internally, because `stop_monitoring` early-returns before reaching it. The `joinable()` guard here was likely intended as defence-in-depth but does not actually protect against the sysconf-failure path. This is an OVERCAUTIOUS guard that gives a false sense of safety.
- **UNGROUNDED:** There is no `condition_variable` or cancellation mechanism. `stop_monitoring` sets `running=false` and then blocks in `join()`. If the loop is currently sleeping (`sleep_for(monitoring_interval)`), the thread will not wake until the sleep expires. Maximum latency = `monitoring_interval`. No commit established any intent for a faster shutdown path.

---

### `register_thread` — `src/mgr/ThreadMonitor.cc:41`

**Establishing commit:** `95a90f7d`  
**Last modified:** `95a90f7d`

#### Intent

Register a new thread (by Linux TID) for monitoring. Associates the thread with an optional serve-thread TID, a display name, and a `PyModuleRef` whose `PerfCounters` will receive written values. Duplicate registrations on the same TID must be silently rejected.

#### Invariants

- The map MUST be mutated only under `monitored_threads_mutex`. [established: `95a90f7d`]
- A TID already in the map MUST NOT be overwritten — the caller is expected to call this once per thread. [established: `95a90f7d`]
- Both `last_snapshot.timestamp` and `last_serve_snapshot.timestamp` MUST be initialised to `mono_clock::now()` so the first CPU delta is computed from registration time, not the epoch. [established: `95a90f7d`]

#### Implementation critique

- **Lines cc:47-50:** Duplicate-TID guard with `monitored_threads.count(thread_id)` — correct, holds the lock.
- **Lines cc:52-58:** `info.last_snapshot.utime` and `info.last_snapshot.stime` are **not** initialised explicitly; they default to `0` via `ThreadSnapshot`'s member initialisers (`long long utime = 0; long long stime = 0;`). This means the first CPU computation (next loop iteration) will compute `utime_current - 0` and `stime_current - 0`, producing a large inflated first sample representing all CPU used since the thread started, not just since registration. **UNGROUNDED** — no commit establishes that the inflated first sample is intentional.
- **Line cc:59 (dout level 0):** `dout(0)` logs the registration unconditionally at the highest priority level (always visible). Other lifecycle messages use `dout(20)`. This inconsistency is **UNGROUNDED** — no commit comment explains why registration deserves level-0 vs level-20.

---

### `handle_conf_change` — `src/mgr/ThreadMonitor.cc:63`

**Establishing commit:** `95a90f7d`  
**Last modified:** `95a90f7d`

#### Intent

React to runtime config changes. When `mgr_module_monitor_interval` changes: update `monitoring_interval`, stop monitoring if the new value is 0, or start it if it was previously stopped and the new value is nonzero.

#### Invariants

- `monitoring_interval` MUST be updated to `std::chrono::seconds(interval)` — the same unit used in the constructor fix from `28647966`. [established: `95a90f7d`; the handle_conf_change path was correct from the beginning because it explicitly wraps with `std::chrono::seconds(interval)` at cc:68]
- A zero interval MUST stop monitoring. [established: `95a90f7d`]
- A nonzero interval when not running MUST restart monitoring. [established: `95a90f7d`]

#### Implementation critique

- **Line cc:68:** `monitoring_interval = std::chrono::seconds(interval)` — correct. Unlike the constructor bug fixed by `28647966`, this line was always using `std::chrono::seconds`. No divergence here.
- **Lines cc:72-75:** The `interval == 0` / `!running` branching is correct. However:
  - **UNGROUNDED:** `monitoring_interval` is written without holding any lock. `monitoring_loop` reads it at cc:91 and cc:158, also without any lock. `monitoring_interval` is a `ceph::mono_clock::duration` (a 64-bit integer typedef on Linux). On 64-bit platforms this is likely atomic at the hardware level, but no formal memory ordering is established. No commit documents this as intentional lock-free access.
  - **UNGROUNDED:** The check `!running` at cc:72 is a non-atomic load of the `std::atomic<bool>`. This is a valid relaxed read, but there is a TOCTOU window: `running` could change between the check and the `start_monitoring()` call. `start_monitoring()` is idempotent, so this only risks a redundant no-op, not a double-start. Acceptable, but undocumented.
- **No DIVERGED findings** for the core logic of this function.

---

### `monitoring_loop` — `src/mgr/ThreadMonitor.cc:78`

**Establishing commit:** `95a90f7d`  
**Last modified:** `28647966`

#### Intent

The background thread body. Continuously polls system resources and updates perf counters until `running` is set to `false`. Structured in three phases to minimise lock hold time: (1) under lock — read RSS and snapshot state; (2) unlocked — do `/proc` I/O and arithmetic; (3) under lock — write results and remove dead threads. On statm failure, sleep and retry rather than spinning.

#### Invariants

- MUST abort immediately if `sysconf` values are invalid (`<= 0`), setting `running=false` and returning. [established: `95a90f7d`]
- MUST NOT spin-loop on a `read_process_statm` failure; MUST sleep for `monitoring_interval` before retrying. [established: `28647966`; the original `95a90f7d` had a bare `continue` with no sleep on this path — Fixes: tracker.ceph.com/issues/76938]
- Phase 1 and Phase 3 MUST be executed under `monitored_threads_mutex`. [established: `95a90f7d`]
- Phase 2 MUST be executed without holding the mutex. [established: `95a90f7d`]
- Dead threads (where `read_thread_stat` returns false) MUST be removed from `monitored_threads` in Phase 3. [established: `95a90f7d`]
- A dead serve-thread (where serve `read_thread_stat` returns false) MUST be cleared (`info.serve_thread_id = 0`) rather than removing the entire entry. [established: `95a90f7d`]

#### Implementation critique

- **Lines cc:79-84:** Sysconf-failure guard — sets `running = false` from inside the thread, then returns. **DIVERGED** from lifecycle invariants: by setting `running=false` internally, any subsequent call to `stop_monitoring()` from the owning thread (e.g., `~ThreadMonitor`) will execute `if (!running.exchange(false)) { return; }` and short-circuit before reaching the `join()`. The `monitor_thread` unique_ptr then destructs a still-joinable `std::thread`, calling `std::terminate()`. Established by `95a90f7d`; not addressed by `28647966`. **This is the most critical correctness bug.**
- **Lines cc:89-94 (blame: `95a90f7d` for the error path, `28647966` for the sleep):** The sleep was added by `28647966` to prevent a tight retry loop when `/proc/self/statm` is unreadable. Current code is correct per the `28647966` intent.
- **Lines cc:97-112 (Phase 1):** RSS is updated inside Phase 1 under lock. The `info.last_snapshot.rss_pages` is updated on line 104 under lock. This is consistent.
- **Lines cc:122-156 (Phase 3):** Dead-thread removal correctly handles the "deregistered between phases" race via `monitored_threads.find(r.tid)` returning `end()` (cc:126-128).
- **Line cc:131:** `dout(0)` for dead thread removal — matches the `dout(0)` in `register_thread`. Consistent but **UNGROUNDED** as to why lifecycle events use level 0 rather than a standard debug level.
- **Line cc:158:** `std::this_thread::sleep_for(monitoring_interval)` — no interruption mechanism. Maximum response time to `stop_monitoring()` is `monitoring_interval`. **UNGROUNDED** — no commit establishes that this delay on shutdown is acceptable.
- **UNGROUNDED:** RSS counter is updated in Phase 1 (under lock), but the CPU counter is updated in Phase 3. This means RSS and CPU values written to perf counters in the same iteration are never atomically consistent — they come from different points in time. No commit establishes whether this is intentional.

---

### `process_thread_stats` — `src/mgr/ThreadMonitor.cc:162`

**Establishing commit:** `95a90f7d`  
**Last modified:** `95a90f7d`

#### Intent

Read current CPU ticks for the main thread and (if present) the serve thread, compute CPU percentage against previous snapshots, and return the results in a `ThreadResult` struct. Called without holding the mutex (Phase 2).

#### Invariants

- MUST return `main_ok = false` if `read_thread_stat` fails; caller MUST treat this as thread death. [established: `95a90f7d`]
- MUST return `serve_ok = false` if serve thread stat read fails; caller MUST clear `serve_thread_id` rather than removing the entry. [established: `95a90f7d`]
- MUST capture `new_ts = mono_clock::now()` BEFORE calling `read_thread_stat` so the timestamp is not inflated by the file-open latency. [established: `95a90f7d`]

#### Implementation critique

- **Lines cc:165-166:** `r.new_ts = ceph::mono_clock::now()` is captured before `read_thread_stat` — matches intent.
- **Lines cc:168-172:** Early return on `!r.main_ok` — correct.
- **Lines cc:183-188:** `r.new_serve_ts` is captured before the serve `read_thread_stat` — consistent with the main thread pattern.
- **UNGROUNDED:** `utime` and `stime` are declared at cc:165 as `long long utime, stime;` (uninitialised). If `read_thread_stat` succeeds but the stream extraction inside it fails silently (see `read_thread_stat` critique), these variables hold indeterminate values. The CPU percentage computation on line 174 will then be undefined behaviour.
- **No DIVERGED findings** for the function's own logic. Issues trace to `read_thread_stat`.

---

### `read_thread_stat` — `src/mgr/ThreadMonitor.cc:201`

**Establishing commit:** `95a90f7d`  
**Last modified:** `95a90f7d`

#### Intent

Parse `/proc/self/task/<tid>/stat` to extract the thread's cumulative user-mode ticks (`utime`, field 14) and kernel-mode ticks (`stime`, field 15) per `proc(5)`. The comm field (field 2) is parenthesised and may contain spaces and parentheses; the implementation skips it robustly by finding the last `)`.

#### Invariants

- MUST return `false` if the file cannot be opened (thread has exited). [established: `95a90f7d`]
- MUST return `false` if the stat line is malformed (no `(` or no `)`). [established: `95a90f7d`]
- MUST skip exactly 11 fields after the closing `)` before reading `utime` and `stime`. [established: `95a90f7d`; comment enumerates: state ppid pgrp session tty_nr tpgid flags minflt cminflt majflt cmajflt]

#### Implementation critique

- **Line cc:217:** `std::string remainder = line.substr(end + 2)` — skips the closing `)` and the space that follows. Correct per `proc(5)` format.
- **Lines cc:223-225:** Skips 11 fields then reads `utime` and `stime`. Field count matches the comment (state through cmajflt = 11 fields). Correct.
- **Line cc:226:** `ss >> utime >> stime` — **DIVERGED** (missing error condition): no check that both extractions succeeded. If the stream is in a fail state (e.g., the line was truncated, or `end + 2` offset exceeds the line), `utime` and `stime` are not written and hold whatever `process_thread_stats` left them as (uninitialised `long long`). The function returns `true` and the caller computes CPU percentage from garbage values. There is no commit that establishes this as intentional.
- **Lines cc:205/213 (dout messages):** Both diagnostic log lines are missing a space separator between `__func__` and the message string: `dout(20) << __func__ << "Could not open ..."` — the output will be `read_thread_statCould not open ...` with no space. **UNGROUNDED** (cosmetic but observable in logs).

---

### `read_process_statm` — `src/mgr/ThreadMonitor.cc:230`

**Establishing commit:** `95a90f7d`  
**Last modified:** `95a90f7d`

#### Intent

Read `/proc/self/statm` to obtain the process RSS in pages. The file format is: `size rss shared text lib data dt` — the second field is RSS in pages.

#### Invariants

- MUST return `false` if the file cannot be opened. [established: `95a90f7d`]
- The returned `rss_pages` value is used directly by the caller to compute `rss_bytes = rss_pages * m_page_size`. [established: `95a90f7d`]

#### Implementation critique

- **Lines cc:239-241:** `statm_file >> vsize_pages >> rss_pages; return true;` — **DIVERGED** (missing error condition, mirroring `read_thread_stat`): no check that the stream extraction succeeded. If the extraction of `rss_pages` fails, the out-parameter retains its caller-initialised value of `0` (cc:88: `long long process_rss_pages = 0`), and the function returns `true`. The caller's Phase 1 loop will then set `rss_bytes = 0` and push `mem_rss_current = 0` to all modules — a silent false reading. No commit establishes this as intentional; the `95a90f7d` context clearly intended the open-failure `return false` to be the only error exit.
- **Line cc:235 (dout message):** Same missing-space cosmetic issue as `read_thread_stat`: `dout(20) << __func__ << "Could not open ..."`.
- **No DIVERGED findings** for the file-not-opened path — that is handled correctly.

---

### `calculate_cpu_percentage` — `src/mgr/ThreadMonitor.cc:244`

**Establishing commit:** `95a90f7d`  
**Last modified:** `95a90f7d`

#### Intent

Convert raw jiffy deltas and elapsed wall-clock seconds to a CPU utilisation percentage. Guard against division by zero when `elapsed_seconds <= 0`.

#### Invariants

- MUST return `0.0` when `elapsed_seconds <= 0` to avoid division by zero or negative percentages. [established: `95a90f7d`]
- Formula: `(utime_diff + stime_diff) / (clock_ticks_per_sec * elapsed_seconds) * 100.0` [established: `95a90f7d`]

#### Implementation critique

- **Lines cc:246-248:** Zero/negative elapsed guard — correct.
- **Lines cc:249-250:** Formula is arithmetically correct. `m_clock_ticks_per_sec` is a `long` (typically 100); the cast to `double` via `static_cast<double>(total_jiffies)` happens implicitly through the division — but because `m_clock_ticks_per_sec` is `long` and `elapsed_seconds` is `double`, the product `m_clock_ticks_per_sec * elapsed_seconds` is `double`. The full expression is computed in floating point. Correct.
- **UNGROUNDED:** If `utime_diff + stime_diff` is negative (possible if TID is reused between loop iterations — a new thread starts with lower tick counts than the dead thread it replaced, and the same TID is in the map), the result is a negative CPU percentage. No commit establishes a clamp or sign check.
- **UNGROUNDED:** No cap at 100% or at `n_cpus * 100%`. A thread could appear to use >100% CPU on a multicore system (correct for a multithreaded module that pinned multiple cores), but no commit documents whether this is expected.

---

### `get_clock_ticks_per_sec` — `src/mgr/ThreadMonitor.h:97`

**Establishing commit:** `95a90f7d`  
**Last modified:** `95a90f7d`

#### Intent

Accessor for the cached clock ticks per second value initialised from `sysconf(_SC_CLK_TCK)`.

#### Implementation critique

- **DIVERGED:** Declared in the header (`long get_clock_ticks_per_sec() const;`) but **never defined** in either commit. No implementation body appears in `95a90f7d` diff (the `.cc` file adds 250 lines and none is this function) or in `28647966`. The constructor directly uses `m_clock_ticks_per_sec` and `monitoring_loop` accesses it directly as a data member. This accessor is declared but unused and unimplemented. Any call site would produce a link error.

---

### `get_page_size` — `src/mgr/ThreadMonitor.h:98`

**Establishing commit:** `95a90f7d`  
**Last modified:** `95a90f7d`

#### Intent

Accessor for the cached page size initialised from `sysconf(_SC_PAGESIZE)`.

#### Implementation critique

- **DIVERGED:** Same situation as `get_clock_ticks_per_sec` — declared in the header but **never defined** in either commit. No implementation body appears anywhere in the corpus. The value is accessed directly via `m_page_size` throughout the implementation. This is a dead declaration.

---

### `get_tracked_keys` — `src/mgr/ThreadMonitor.h:41`

**Establishing commit:** `95a90f7d`  
**Last modified:** `95a90f7d`

#### Intent

Satisfy the `md_config_obs_t` interface by declaring which config keys this observer cares about. Returns `{"mgr_module_monitor_interval"}`.

#### Invariants

- MUST return exactly `{"mgr_module_monitor_interval"}` so the config framework routes changes to `handle_conf_change`. [established: `95a90f7d`]

#### Implementation critique

- **Lines h:41-43:** Inline implementation, returns a single-element vector. Correct.
- **No DIVERGED findings.**

---

## Summary of Findings

| Finding | Function | Type | Establishing SHA |
|---|---|---|---|
| Constructor initialised `monitoring_interval` as nanoseconds (raw int64 assigned to duration) | `ThreadMonitor` ctor | DIVERGED — **FIXED** by `28647966` | `95a90f7d` (bug), `28647966` (fix) |
| In-member initialiser `= std::chrono::seconds(2)` is stale dead default | `ThreadMonitor` ctor | UNGROUNDED | `95a90f7d` |
| `sysconf` failure not validated in constructor | `ThreadMonitor` ctor | UNGROUNDED | `95a90f7d` |
| `monitoring_loop` sysconf guard sets `running=false` internally, causing `stop_monitoring` to short-circuit and later `~thread()` on joinable thread → `std::terminate()` | `monitoring_loop`, `stop_monitoring` | DIVERGED | `95a90f7d` |
| No sleep on `read_process_statm` failure → busy spin | `monitoring_loop` | DIVERGED — **FIXED** by `28647966` | `95a90f7d` (bug), `28647966` (fix) |
| `stop_monitoring` `joinable()` guard is OVERCAUTIOUS — unreachable via the normal stop path when loop sets `running=false` | `stop_monitoring` | OVERCAUTIOUS | `95a90f7d` |
| No condition_variable; shutdown latency up to `monitoring_interval` | `stop_monitoring`, `monitoring_loop` | UNGROUNDED | `95a90f7d` |
| First CPU sample inflated — `utime/stime` default to 0 at registration | `register_thread` | UNGROUNDED | `95a90f7d` |
| `dout(0)` for lifecycle messages (inconsistent with `dout(20)` elsewhere) | `register_thread`, `monitoring_loop` | UNGROUNDED | `95a90f7d` |
| `monitoring_interval` written in `handle_conf_change` without lock; read in `monitoring_loop` without lock | `handle_conf_change` | UNGROUNDED | `95a90f7d` |
| `ss >> utime >> stime` not checked for failure; returns `true` with garbage values | `read_thread_stat` | DIVERGED | `95a90f7d` |
| `statm_file >> vsize_pages >> rss_pages` not checked; returns `true` with `rss_pages=0` on failure | `read_process_statm` | DIVERGED | `95a90f7d` |
| Missing space in log messages: `__func__ << "Could not open..."` | `read_thread_stat`, `read_process_statm` | UNGROUNDED | `95a90f7d` |
| Negative CPU percentage possible on TID reuse; no clamp | `calculate_cpu_percentage` | UNGROUNDED | `95a90f7d` |
| `get_clock_ticks_per_sec` declared but never defined | `get_clock_ticks_per_sec` | DIVERGED | `95a90f7d` |
| `get_page_size` declared but never defined | `get_page_size` | DIVERGED | `95a90f7d` |

---

## Self-Check

- [x] Every commit in commits.txt was read (`95a90f7d` and `28647966`).
- [x] Every function in functions.txt has a section (14 unique function signatures covered; `.h` and `.cc` entries for the same function are collapsed into one section with citations from both).
- [x] Every DIVERGED finding names the specific commit SHA and the contradicting line.
- [x] All ungrounded code paths are flagged as UNGROUNDED.
- [x] The `28647966` fix (nanoseconds bug, busy-loop) is correctly attributed and marked FIXED.
- [x] The critical `std::terminate()` risk from `monitoring_loop`'s sysconf-failure path is flagged as DIVERGED with the responsible SHA.
- [x] The undeclared-but-defined `get_clock_ticks_per_sec` / `get_page_size` accessors are flagged DIVERGED.
