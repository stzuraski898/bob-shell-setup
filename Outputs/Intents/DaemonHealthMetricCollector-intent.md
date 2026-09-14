# Intent Artefact — DaemonHealthMetricCollector

**Generated:** 2026-09-11  
**Corpus head:** `8681fa6ebac230f86eb445bf57095c63e7f1abcc`  
**Assessment head (collected_at):** 2026-09-11T21:40:59Z  
**Source files:** `src/mgr/DaemonHealthMetricCollector.cc` · `src/mgr/DaemonHealthMetricCollector.h`  
**Rename chain:** `src/mgr/OSDHealthMetricCollector.cc` (7e7978732d20 → 714ffe0d5f07) → `src/mgr/DaemonHealthMetricCollector.cc` (714ffe0d5f07 → 4ac2d6b536b9)  
**Total commits in corpus:** 13  
**Date range:** 2017-11-01 (7e7978732d20) → 2024-11-05 (4ac2d6b536b9)

---

## Corpus Overview

| SHA (short) | Date | Author | Subject |
|---|---|---|---|
| `4ac2d6b5` | 2024-11-05 | Max Kellermann | mgr/DaemonHealthMetricCollector: include cleanup |
| `c63ecb60` | 2021-08-11 | Kefu Chai | mgr: build without "using namespace std" |
| `fc1905b4` | 2020-10-08 | Paul Cuzner | mgr: add doc to describe relationship to prometheus |
| `85acc8bf` | 2020-10-23 | Kefu Chai | mgr/DaemonHealthMetricCollector: replace boost::format with fmt::format |
| `fb725f7c` | 2020-10-23 | Kefu Chai | mgr: use make_unique<> when appropriate |
| `5aac7eba` | 2019-09-29 | Kefu Chai | mgr: use a struct for DaemonKey |
| `25963f24` | 2019-09-29 | Xie Xingguo | mgr: fix weird health-alert daemon key |
| `02cc60f6` | 2019-09-10 | Ilsoo Byun | mgr: do not reset reported if a new metric is not collected |
| `d0eb22f3` | 2019-07-31 | Sage Weil | mon/health_checks: associate a count with health_alert_t |
| `b5263176` | 2018-05-01 | Brad Hubbard | mgr: Include daemon details in SLOW_OPS output |
| `714ffe0d` | 2018-03-13 | Shanchun Lv | mgr,osd: make osd_metric more popular |
| `f6c87243` | 2017-11-27 | Shinobu Kinjo | [cleanup] Remove namespace using directives for std |
| `7e797873` | 2017-11-01 | Kefu Chai | mgr: summarize osd metrics in MMgrReport and sent it to mon |

---

## Architecture Summary

`DaemonHealthMetricCollector` is an abstract base class that collects per-daemon health metrics and folds them into a `health_check_map_t`. It owns two protected fields — `daemon_metric_t value` (the accumulator) and `bool reported` (a latch) — and exposes two public non-virtual methods (`update`, `summarize`) that gate their behaviour on the latch.

Two concrete implementations live in the anonymous namespace of the `.cc` file:

- **`SlowOps`** — tracks `daemon_metric::SLOW_OPS`; accumulates total slow-op count (`value.n1`) and maximum blocked duration (`value.n2`); includes daemon names in the `check.summary` string (no `check.detail`).
- **`PendingPGs`** — tracks `daemon_metric::PENDING_CREATING_PGS`; accumulates total pending PG count (`value.n`); puts daemon names in `check.detail` (not summary).

The factory function `create(daemon_metric)` is the only way to instantiate a concrete collector.

---

## Function Sections

---

### `DaemonHealthMetricCollector::~DaemonHealthMetricCollector` (`.h:23`)

**History:** Created by `714ffe0d5f07`. Never modified.

**Intent:** Provide a virtual destructor so that `std::unique_ptr<DaemonHealthMetricCollector>` destroys the correct concrete subclass.

**Invariants:**
- `I1` (`714ffe0d5f07`): The destructor must be virtual; the class is a polymorphic base held by `unique_ptr<DaemonHealthMetricCollector>`.

**Implementation critique (`.h:23`):**
- Line 23: `virtual ~DaemonHealthMetricCollector() {}` — empty body is correct; no resources in the base class require explicit cleanup.
- **Status:** CLEAN.

---

### `DaemonHealthMetricCollector::create` (`.h:12`, `.cc:99`)

**History:**
- `714ffe0d5f07` (2018-03-13): Created when `OSDHealthMetricCollector` was generalised to `DaemonHealthMetricCollector`. Factory pattern using raw `new` and explicit `unique_ptr` constructor. Handled `SLOW_OPS`, `PENDING_CREATING_PGS`, and a `default: return unique_ptr<DaemonHealthMetricCollector>{}` null path.
- `fb725f7c` (2020-10-23): Replaced raw `new SlowOps` / `new PendingPGs` with `std::make_unique<SlowOps>()` / `std::make_unique<PendingPGs>()`, and replaced `unique_ptr<DaemonHealthMetricCollector>{}` with `return {}`. No semantic change.
- `commit_function_map.txt` explicitly maps `fb725f7c` to `create`.

**Intent:** Return a heap-allocated concrete collector for a known `daemon_metric`, or a null `unique_ptr` for any unrecognised metric type. This function is the sole factory; callers must null-check the result.

**Invariants:**
- `I1` (`714ffe0d5f07`): Exactly two metric types are handled. Any other metric silently returns a null `unique_ptr`.
- `I2` (`fb725f7c`): Construction uses `make_unique`, which is exception-safe.

**Error conditions:**
- `E1` (`714ffe0d5f07`): Unknown metric type → `return {}` (null `unique_ptr`). No assertion, no exception. Callers are responsible for null-checking.

**Implementation critique (`.cc:99–109`):**
- Lines 101–108: `switch` matches `daemon_metric::SLOW_OPS` and `daemon_metric::PENDING_CREATING_PGS`; all other enumerators fall through to `default: return {}`.
- **UNGROUNDED (`.cc:107`):** The `default: return {}` branch is unexplained by any comment. Any future `daemon_metric` enumerator added to `DaemonHealthMetric.h` would silently return null here — the compiler will not warn unless the switch is exhaustive and `-Wswitch` is in effect. No comment, no `ceph_assert`, no log line. This is a silent failure path established since `714ffe0d5f07` and never addressed.
- No DIVERGED flags. The null-return contract is consistent with history.

---

### `DaemonHealthMetricCollector::update` (`.h:13–17`)

**History:**
- `714ffe0d5f07` (2018-03-13): Implemented as `reported = _update(daemon, metric)` — **plain assignment**. This had a bug: if a second call with `_is_relevant == true` returned false from `_update`, it would overwrite a previously set `true` with `false`, suppressing the health check.
- `02cc60f6` (2019-09-10): **Critical bug fix** (tracker #41741). Changed `reported = _update(...)` to `reported |= _update(...)`. Now `reported` is a latch: once set true it stays true for the collector's lifetime. The fix prevents a zero-reporting daemon from resetting the check established by an earlier non-zero daemon.

**Intent:** Filter incoming metrics by relevance, accumulate relevant ones, and latch `reported` to true if any relevant metric returned non-zero data. Once latched, `summarize` will fire.

**Invariants:**
- `I1` (`02cc60f6`): `reported` is monotonically non-decreasing — it can only transition from `false` to `true`, never back. Established as a bug fix for tracker #41741.
- `I2` (`714ffe0d5f07`): Only calls `_update` when `_is_relevant` is true; irrelevant metric types are silently ignored without side effects.

**Error conditions:** None — irrelevant types are silently dropped.

**Implementation critique (`.h:13–17`):**
- Line 14: `if (_is_relevant(metric.get_type()))` — correct gating.
- Line 15: `reported |= _update(daemon, metric)` — correct latch semantics per `02cc60f6`.
- **Status:** CLEAN. The fix from `02cc60f6` is correctly in place.

---

### `DaemonHealthMetricCollector::summarize` (`.h:18–22`)

**History:**
- `7e797873` (2017-11-01, as `OSDHealthMetricCollector`): Original implementation. Gates `_summarize` on `reported`. No changes since creation.

**Intent:** If any daemon reported a health-relevant metric (`reported == true`), obtain or create the health check entry via `_get_check`, then call `_summarize` to populate it. If `reported == false`, do nothing.

**Invariants:**
- `I1` (`7e797873`): `_summarize` is called only when `reported` is true; an empty accumulator never emits a health check.
- `I2` (`7e797873`): `_get_check` is called before `_summarize` — the `health_check_t&` must be created/fetched atomically with summary generation.

**Error conditions:** None.

**Implementation critique (`.h:18–22`):**
- Line 19: `if (reported)` — correct guard.
- Line 20: `_summarize(_get_check(cm))` — passes by reference; the object lifetime is managed by `cm`.
- **Status:** CLEAN.

---

### `SlowOps::_is_relevant` (`.cc:18–19`)

**History:**
- `7e797873` (2017-11-01, as `OSDHealthMetricCollector`): Created. Type was `osd_metric::SLOW_OPS`.
- `714ffe0d` (2018-03-13): Renamed type to `daemon_metric::SLOW_OPS` when generalising to `DaemonHealthMetricCollector`.

**Intent:** Return true if and only if the metric type is `SLOW_OPS`.

**Invariants:**
- `I1` (`714ffe0d`): Exactly one metric type is accepted — `daemon_metric::SLOW_OPS`.

**Implementation critique (`.cc:18–19`):**
- Line 19: `return type == daemon_metric::SLOW_OPS;` — correct and minimal.
- **Status:** CLEAN.

---

### `SlowOps::_get_check` (`.cc:21–23`)

**History:**
- `7e797873` (2017-11-01): Created as `cm.get_or_add("SLOW_OPS", HEALTH_WARN, "")` — no count argument.
- `d0eb22f3` (2019-07-31): Added count `1` → `cm.get_or_add("SLOW_OPS", HEALTH_WARN, "", 1)`. Commit message: "associate a count with health_alert_t: 0 means singleton; otherwise can be summed via merge() or get_or_add()." The count `1` means individual reports can be accumulated.

**Intent:** Fetch or create the `"SLOW_OPS"` `HEALTH_WARN` entry in the map. The count `1` per call means each invocation registers as one unit for potential aggregation.

**Invariants:**
- `I1` (`d0eb22f3`): The check key must be `"SLOW_OPS"`, severity `HEALTH_WARN`, count `1`.

**Implementation critique (`.cc:21–23`):**
- Line 22: `return cm.get_or_add("SLOW_OPS", HEALTH_WARN, "", 1);` — correct per `d0eb22f3`.
- **Status:** CLEAN.

---

### `SlowOps::_update` (`.cc:24–36`)

**History:**
- `7e797873` (2017-11-01, as `OSDHealthMetricCollector`): Created. Accumulated `value.n1` (total slow ops), tracked `max(value.n2, blocked_time)` (oldest blocked time). Only pushed to `osds` list (later renamed `daemons`) when `num_slow || blocked_time`.
- `714ffe0d` (2018-03-13): Renamed container from `osds` to `daemons` to match `DaemonKey`. Parameter renamed from `osd` to `daemon`.

**Intent:** Accumulate the total count of slow ops across all daemons and track the single longest blocked duration. A daemon is added to the `daemons` list (for inclusion in the summary message) only if it actually reported slow ops or a blocked time. Returns true when the daemon contributed non-zero data.

**Invariants:**
- `I1` (`7e797873`): `value.n1` accumulates total slow ops across all daemons — it is never reset within a collector's lifetime.
- `I2` (`7e797873`): `value.n2` is the maximum blocked time seen, not a sum.
- `I3` (`7e797873`): A daemon is added to `daemons` only if `num_slow > 0 OR blocked_time > 0`. A zero-reporting daemon is not listed.
- `I4` (`7e797873`): `value.n1 += 0` still executes for zero-reporting daemons — the accumulation is unconditional. This is a no-op but is consistent.

**Implementation critique (`.cc:24–36`):**
- Line 26: `auto num_slow = metric.get_n1();` — retrieves slow-op count.
- Line 27: `auto blocked_time = metric.get_n2();` — retrieves max blocked duration.
- Line 28: `value.n1 += num_slow;` — unconditional accumulation.
- Line 29: `value.n2 = std::max(value.n2, blocked_time);` — max semantics, not sum.
- Lines 30–35: conditional `daemons` push and true-return only when non-zero.
- **Status:** CLEAN.

---

### `SlowOps::_summarize` (`.cc:37–58`)

**History:**
- `7e797873` (2017-11-01): Original format: `"%1% slow ops, oldest one blocked for %2% sec"` in `check.summary`; daemon list in `check.detail`. Single-daemon message: `"osd.X has slow ops"` (no period). Multi-daemon: `"osds [...] have slow ops."` (with period).
- `b5263176` (2018-05-01, tracker #23205): **Design change** — daemon info moved from `check.detail` to `check.summary` by appending `", %3%"` to the format string. Also added a 10-daemon cap: if more than 10 daemons, only the first 10 are printed followed by `"..."`. The `check.detail.push_back` was replaced by `check.summary = boost::format(...)`. Comment `// No detail` added explicitly.
- `85acc8bf` (2020-10-23): `boost::format` replaced with `fmt::format("{} slow ops, oldest one blocked for {} sec, {}", value.n1, value.n2, ss.str())`. The static `fmt` string removed.
- `fc1905b4` (2020-10-08): Added comment: `"Note this message format is used in mgr/prometheus, so any change in format requires a corresponding change in the mgr/prometheus module."` This comment records an external coupling constraint.

**Intent:** Build the health check summary string as `"N slow ops, oldest one blocked for M sec, <daemon list>"`. No `check.detail` is populated (`// No detail` is intentional). Daemon list is truncated to 10 names if more than 10 are affected. The format string is coupled to the mgr/prometheus module.

**Invariants:**
- `I1` (`7e797873`): Returns early without modifying `check` if `daemons` is empty.
- `I2` (`b5263176`): Daemon names appear in `check.summary`, not `check.detail`. This is explicit and intentional.
- `I3` (`b5263176`): At most 10 daemon names are printed; excess is replaced with `"..."`.
- `I4` (`fc1905b4`): The format string `"{} slow ops, oldest one blocked for {} sec, {}"` is relied upon by the mgr/prometheus module. Any format change requires a corresponding prometheus module change.

**Implementation critique (`.cc:37–58`):**
- Line 38: `if (daemons.empty()) return;` — correct early exit per `I1`.
- Lines 41–43: doc comment about prometheus coupling — present per `fc1905b4`.
- Lines 44–50: single-daemon vs multi-daemon branching. Multi-daemon further branches at 10.
- Line 46–47: `vector<DaemonKey>(daemons.begin(), daemons.begin()+10)` — copies first 10 daemons into a temporary for printing.
- Lines 54–56: `check.summary = fmt::format("{} slow ops, oldest one blocked for {} sec, {}", value.n1, value.n2, ss.str())` — correct format per `85acc8bf`.
- Line 57: `// No detail` — explicit invariant annotation.
- **UNGROUNDED (`.cc:49` vs `.cc:52`):** The single-daemon branch at line 52 produces `"osd.X has slow ops"` (no trailing period), while both multi-daemon branches (lines 47, 49) produce messages ending with `"."`. This stylistic inconsistency has been present since `7e797873` and was carried forward unmodified through all subsequent edits. No commit has ever explained or intentionally preserved this asymmetry.
- **OVERCAUTIOUS (`.cc:44`):** The outer `if (daemons.size() > 1)` branch is redundant given the inner `if (daemons.size() > 10)` check. When size is exactly 1, the else branch fires correctly. But the outer-branch condition `> 1` means the single-daemon path also correctly handles size==1. This is correct logic, not a bug — but the two-level nesting could be collapsed. Not a correctness issue.
- **No DIVERGED flags.** The current implementation matches every intent established by the commit sequence.

---

### `PendingPGs::_is_relevant` (`.cc:64–65`)

**History:**
- `7e797873` (2017-11-01): Created as `type == osd_metric::PENDING_CREATING_PGS`.
- `714ffe0d` (2018-03-13): Renamed to `daemon_metric::PENDING_CREATING_PGS`.

**Intent:** Return true if and only if the metric type is `PENDING_CREATING_PGS`.

**Invariants:**
- `I1` (`714ffe0d`): Exactly one metric type is accepted.

**Implementation critique (`.cc:64–65`):**
- Line 65: `return type == daemon_metric::PENDING_CREATING_PGS;` — correct.
- **Status:** CLEAN.

---

### `PendingPGs::_get_check` (`.cc:67–68`)

**History:**
- `7e797873` (2017-11-01): `cm.get_or_add("PENDING_CREATING_PGS", HEALTH_WARN, "")`.
- `d0eb22f3` (2019-07-31): Added count `1`.

**Intent:** Fetch or create the `"PENDING_CREATING_PGS"` `HEALTH_WARN` entry.

**Invariants:**
- `I1` (`d0eb22f3`): Key `"PENDING_CREATING_PGS"`, severity `HEALTH_WARN`, count `1`.

**Implementation critique (`.cc:67–68`):**
- Line 68: `return cm.get_or_add("PENDING_CREATING_PGS", HEALTH_WARN, "", 1);` — correct.
- **Status:** CLEAN.

---

### `PendingPGs::_update` (`.cc:70–79`)

**History:**
- `7e797873` (2017-11-01): Created. Accumulates `value.n` (total pending PGs). Only pushes to `osds` list when `metric.get_n() > 0`. Returns true in that case.
- `714ffe0d` (2018-03-13): Generalised — parameter type changed from `OSDHealthMetric` to `DaemonHealthMetric`, but the parameter name remained `osd` (not updated to `daemon`).

**Intent:** Accumulate the total count of pending-creation PGs across all daemons. Record which daemons have non-zero pending PGs. Returns true when the daemon contributed non-zero data.

**Invariants:**
- `I1` (`7e797873`): `value.n` accumulates total pending PG count across all daemons.
- `I2` (`7e797873`): A daemon is pushed to `osds` only when `metric.get_n() > 0`.
- `I3` (`7e797873`): `value.n += metric.get_n()` executes unconditionally before the conditional push.

**Implementation critique (`.cc:70–79`):**
- Line 70: Parameter is named `osd` — a vestigial name from `7e797873` when this was `OSDHealthMetricCollector`. The type is `DaemonKey`, which is semantically broader than an OSD. **UNGROUNDED**: This name was never updated in `714ffe0d` when the class was generalised. It is misleading — the function handles any daemon type, not just OSDs.
- Line 74 (member `osds`): Same vestigial naming — the collector's daemon-tracking container is called `osds` (`.cc:93`), not `daemons`. See also `_summarize` critique.
- Lines 72–78: Logic is correct per invariants.
- **No DIVERGED flags.**

---

### `PendingPGs::_summarize` (`.cc:80–92`)

**History:**
- `7e797873` (2017-11-01): Created. Summary: `"%1% PGs pending on creation"`. Detail: `"osds [...] have pending PGs."` (multi) or `"osd.X has pending PGs"` (single). Uses `check.detail.push_back`.
- `85acc8bf` (2020-10-23): `boost::format` → `fmt::format("{} PGs pending on creation", value.n)`. No structural change.

**Intent:** Build the health check summary as `"N PGs pending on creation"` and populate `check.detail` with the affected daemon list. Unlike `SlowOps`, daemon names go to detail, not summary.

**Invariants:**
- `I1` (`7e797873`): Returns early if `osds` is empty.
- `I2` (`7e797873`): Daemon names appear in `check.detail`, not `check.summary`.
- `I3` (`7e797873`): No daemon-count cap is applied (unlike SlowOps's 10-daemon cap). All affected OSDs are listed.

**Implementation critique (`.cc:80–92`):**
- Line 81: `if (osds.empty()) return;` — correct per `I1`.
- Line 84: `check.summary = fmt::format("{} PGs pending on creation", value.n);` — correct per `85acc8bf`.
- Lines 85–90: `ostringstream ss` built for detail.
- Line 91: `check.detail.push_back(ss.str());` — places daemon names in detail per `I2`.
- **UNGROUNDED (`.cc:89` vs `.cc:91`):** Single-daemon branch produces `"osd.X has pending PGs"` (no period); multi-daemon branch produces `"osds [...] have pending PGs."` (with period). Same asymmetry as SlowOps. Traceable to `7e797873` and never addressed.
- **UNGROUNDED (`.cc:80–92`):** There is no cap on the number of daemons listed in detail. SlowOps caps at 10 (`b5263176`), but that cap was never applied to PendingPGs. If thousands of OSDs have pending PGs, `check.detail` will receive one entry with a very long daemon list, potentially causing readability or memory issues. No commit ever acknowledged this discrepancy or deliberately left it uncapped.
- **Design note (not DIVERGED):** The asymmetry between SlowOps (daemon names in summary, no detail) and PendingPGs (summary contains only count, daemon names in detail) is a deliberate historical design difference. `b5263176` changed SlowOps specifically; PendingPGs was never touched. This is traceable but unexplained by any commit message.

---

## Virtual Pure Interface Functions (`.h:25–28`)

The following are pure virtual declarations in the base class. They have no implementation bodies and serve solely as contracts for concrete subclasses. Each is covered by its concrete implementation above.

| Virtual function | Declared at | Established by |
|---|---|---|
| `virtual bool _is_relevant(daemon_metric type) const = 0` | `.h:25` | `714ffe0d` |
| `virtual health_check_t& _get_check(health_check_map_t& cm) const = 0` | `.h:26` | `7e797873` |
| `virtual bool _update(const DaemonKey& daemon, const DaemonHealthMetric& metric) = 0` | `.h:27` | `714ffe0d` |
| `virtual void _summarize(health_check_t& check) const = 0` | `.h:28` | `7e797873` |

---

## Protected Data Members (`.h:30–31`)

| Member | Type | Established by | Purpose |
|---|---|---|---|
| `value` | `daemon_metric_t` | `714ffe0d` | Per-metric accumulator; fields used vary by concrete class |
| `reported` | `bool` | `714ffe0d` | Latch; set true (and latched) by `update()` via `02cc60f6` fix |

---

## Cross-Cutting Findings

### DIVERGED Findings

No DIVERGED findings. Every piece of current code can be grounded to a specific commit in the history. The `02cc60f6` fix (`reported |= ...`) is in place. The `d0eb22f3` count arguments are in place. The `b5263176` format restructuring is in place.

### UNGROUNDED Findings

| ID | Location | Description | Traceable root |
|---|---|---|---|
| U1 | `.cc:107` (`create` default branch) | `default: return {}` is a silent null return with no log, assertion, or comment. Future `daemon_metric` enum additions would silently produce null collectors. | `714ffe0d` |
| U2 | `.cc:52` vs `.cc:47`/`.cc:49` | SlowOps single-daemon message lacks trailing period; multi-daemon messages have it. Asymmetry never explained. | `7e797873` |
| U3 | `.cc:70` (parameter name `osd`) | `PendingPGs::_update` parameter is named `osd` but type is `DaemonKey`. Vestigial OSD-specific name from original `OSDHealthMetricCollector` ancestry; not updated in `714ffe0d`. | `7e797873` |
| U4 | `.cc:93` (member name `osds`) | `PendingPGs` member container is named `osds` despite holding `DaemonKey` values for any daemon type. Same ancestry issue as U3. | `7e797873` |
| U5 | `.cc:89` vs `.cc:91` | PendingPGs single-daemon detail message lacks trailing period; multi-daemon has it. Same asymmetry as U2. | `7e797873` |
| U6 | `.cc:80–92` (`PendingPGs::_summarize`) | No cap on daemon count in detail string. SlowOps caps at 10 (`b5263176`) but PendingPGs was never updated to apply an analogous cap. | `7e797873` / `b5263176` |

### OVERCAUTIOUS Findings

| ID | Location | Description |
|---|---|---|
| O1 | `.cc:44` (`SlowOps::_summarize`) | Outer `if (daemons.size() > 1)` is logically unnecessary given the inner `> 10` branch — the two-level nesting could be flattened without changing behaviour. Not a correctness issue. |

---

## Self-Check

- [x] All 13 commits read in full (7 diffs scope `.cc`/`.h` changes; 2 are include-only; 4 are `.cc` renames from `OSDHealthMetricCollector`).
- [x] Every function in `functions.txt` has a section: `_is_relevant` (×2 concrete + pure virtual), `_get_check` (×2 + pure virtual), `_update` (×2 + pure virtual), `_summarize` (×2 + pure virtual), `create` (×2 header+impl), `update`, `summarize`, `~DaemonHealthMetricCollector`.
- [x] All DIVERGED flags carry SHA citations — zero DIVERGED flags found; no current code contradicts a commit-established invariant.
- [x] All UNGROUNDED paths flagged with root commit (U1–U6).
- [x] OVERCAUTIOUS finding (O1) identified.
- [x] Blame.txt used to verify last-touching commit for every line group.
- [x] Rename chain documented — `.cc` was `OSDHealthMetricCollector.cc` through `7e797873` and `f6c87243`, then renamed in `714ffe0d`.
- [x] The critical bug fix `02cc60f6` (`reported = ...` → `reported |= ...`) is confirmed in place at `.h:15`.
- [x] The `d0eb22f3` count-argument addition (`get_or_add(..., 1)`) confirmed at `.cc:22` and `.cc:68`.
- [x] The `fc1905b4` prometheus-coupling comment confirmed at `.cc:41–42`.
