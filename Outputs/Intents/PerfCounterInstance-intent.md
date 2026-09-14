# Intent Artefact — `PerfCounterInstance`

**Generated:** 2026-09-11  
**HEAD SHA:** `8681fa6ebac230f86eb445bf57095c63e7f1abcc`  
**Corpus collected at:** 2026-09-11T21:40:59Z  
**Source files:** `src/mgr/PerfCounterInstance.cc`, `src/mgr/PerfCounterInstance.h`

---

## 1. Corpus Summary

### 1.1 Commit Count and Date Range

| # | SHA (short) | Date | Author | Subject |
|---|-------------|------|--------|---------|
| 1 | `35f6dd06` | 2025-08-14 | Max Kellermann | mgr/DaemonState: move PerfCounters classes to separate sources |
| 2–29 | `c1865445`–`9afeaa01` | 2004–2007 | Sage Weil | Clock.h churn (rename-chain false positives — see §1.3) |

**Total commits in corpus:** 29 (28 non-merge, 1 effective for PerfCounterInstance)  
**HEAD SHA:** `8681fa6ebac230f86eb445bf57095c63e7f1abcc`  
**Date range:** 2004-07-02 (`9afeaa01`) → 2025-08-14 (`35f6dd06`)  
**Effective date range for PerfCounterInstance logic:** 2016-06-30 → 2025-08-14

### 1.2 Rename Chain

```
src/mgr/PerfCounterInstance.cc   35f6dd06 → c1865445  (current)
trunk/ceph/common/Clock.h         c1865445 → 9b453154  (false positive)
ceph/common/Clock.h               9b453154 → 9afeaa01  (false positive)
```

`src/mgr/PerfCounterInstance.h` exists only from `35f6dd06` onward.

### 1.3 Rename-Chain False Positives

Commits `c1865445` through `9afeaa01` (28 commits) are for `ceph/common/Clock.h` and `trunk/ceph/common/Clock.h`. The rename-chain tool incorrectly linked them to `PerfCounterInstance.cc` via a distant file-rename path. **None of these commits touch any code relevant to `PerfCounterInstance`.** Every diff in that range operates exclusively on `Clock.h` (`utime_t`, `Clock` class, SVN history). They are excluded from all analysis below.

### 1.4 True Authorship (from `blame.txt`)

The PerfCounterInstance logic was **not born in these files**. It was authored in `src/mgr/DaemonState.h` and `src/mgr/DaemonState.cc` and **extracted** to its own translation unit by `35f6dd06`. Blame-attributable author SHAs:

| Blame SHA | Original File | Author | Date | Contribution |
|-----------|--------------|--------|------|--------------|
| `ac30e6cee2b2` | `src/mgr/DaemonMetadata.h` | John Spray | 2016-06-30 | Class comment, licence block, closing `};` |
| `9501bfdd7114` | `src/mgr/DaemonState.h/.cc` | John Spray | 2016-07-26 | `DataPoint`, `buffer`, `push()`, `get_current()`, `get_data()`, `push()` decl |
| `1164ef2f32d8` | `src/mgr/DaemonState.h/.cc` | Boris Ranto | 2018-05-15 | `AvgDataPoint`, `avg_buffer`, `push_avg()`, constructor logic |
| `b421142b1c6f` | `src/mgr/DaemonState.h` | Jan Fajerski | 2018-09-07 | `get_latest_data()`, `get_latest_data_avg()` |
| `a17349b87afd` | `src/mgr/DaemonState.h` | Max Kellermann | 2025-08-12 | `#include "common/perf_counters.h"` (pre-extraction include fixup) |
| `35f6dd06dd0b` | *(new file)* | Max Kellermann | 2025-08-14 | **Extraction** — created `PerfCounterInstance.cc` and `.h`; no logic changed |

---

## 2. Function Inventory

From `functions.txt` (ctags output):

| Function | File | Line | Class / Role |
|----------|------|------|--------------|
| `DataPoint` (constructor) | `.h` | 33 | Inner class ctor — stores `{utime_t t, uint64_t v}` |
| `AvgDataPoint` (constructor) | `.h` | 44 | Inner class ctor — stores `{utime_t t, uint64_t s, uint64_t c}` |
| `get_current` | `.h` | 52 | Private declaration — returns `uint64_t` current value |
| `get_data` | `.h` | 55 | Public accessor — returns const ref to full `buffer` |
| `get_latest_data` | `.h` | 59 | Public accessor — returns const ref to `buffer.back()` |
| `get_data_avg` | `.h` | 63 | Public accessor — returns const ref to full `avg_buffer` |
| `get_latest_data_avg` | `.h` | 67 | Public accessor — returns const ref to `avg_buffer.back()` |
| `push` (decl) | `.h` | 71 | Public — declares `push(utime_t, uint64_t const&)` |
| `push_avg` (decl) | `.h` | 72 | Public — declares `push_avg(utime_t, uint64_t const&, uint64_t const&)` |
| `PerfCounterInstance` (ctor) | `.h` | 74 | Public constructor — sized-buffer initialisation |
| `push` (impl) | `.cc` | 16 | Appends `DataPoint` to `buffer` |
| `push_avg` (impl) | `.cc` | 21 | Appends `AvgDataPoint` to `avg_buffer` |

---

## 3. Function-by-Function Analysis

### 3.1 `DataPoint` (constructor) — `.h` line 33

**Establishing commit:** `9501bfdd7114` (John Spray, 2016-07-26, original in `DaemonState.h`); extracted without change in `35f6dd06`.

**Intent:**  
A plain-old-data value type holding a single timestamped scalar counter sample. Fields:
- `t` (`utime_t`) — wall-clock timestamp of the sample
- `v` (`uint64_t`) — the counter value at that point in time

**Invariants established by `9501bfdd7114`:**
- `DataPoint` is an inner class of `PerfCounterInstance`; it has `public:` visibility for its members so the buffer-manipulation code in the same class can access them.
- The constructor takes `(utime_t t_, uint64_t v_)` and member-initialises both fields — no default construction.
- `v` is unsigned 64-bit; negative values are not representable.

**Error conditions:** None specified — the type is a dumb struct.

**Implementation critique (`.h` lines 33–36):**
```cpp
DataPoint(utime_t t_, uint64_t v_)
  : t(t_), v(v_)
{}
```
- Implementation matches intent exactly.
- **UNGROUNDED:** No `explicit` keyword. `DataPoint` has a two-argument constructor, so accidental implicit conversion is not an issue here, but adding `explicit` would be a stylistic improvement that no commit ever asked for — no finding.
- No issues.

---

### 3.2 `AvgDataPoint` (constructor) — `.h` line 44

**Establishing commit:** `1164ef2f32d8` (Boris Ranto, 2018-05-15, original in `DaemonState.h`); extracted without change in `35f6dd06`.

**Intent:**  
A plain-old-data value type holding a single timestamped average-counter sample. Fields:
- `t` (`utime_t`) — wall-clock timestamp
- `s` (`uint64_t`) — running sum (total accumulated value)
- `c` (`uint64_t`) — count of events (denominator for computing the average)

**Invariants established by `1164ef2f32d8`:**
- Introduced to support the `PERFCOUNTER_LONGRUNAVG` counter type, which tracks `(sum, count)` pairs rather than a scalar.
- Both `s` and `c` are unsigned 64-bit; semantically `c == 0` means "no events yet" and implies the average is undefined, but no guard is enforced in this struct.
- Constructor member-initialises all three fields.

**Error conditions:** None. This is a dumb struct; `c == 0` is a valid in-flight state.

**Implementation critique (`.h` lines 44–47):**
```cpp
AvgDataPoint(utime_t t_, uint64_t s_, uint64_t c_)
  : t(t_), s(s_), c(c_)
{}
```
- Implementation matches intent exactly.
- **UNGROUNDED:** Field name `s` for "sum" is terse. No commit ever documented this; the field name is an implementation choice not traceable to any written contract. Consumers (e.g. `DaemonServer`, Python plugin) must know that `s / c` is the average. The name `s` is underdocumented but not incorrect — low severity, no DIVERGED.

---

### 3.3 `get_current` — `.h` line 52

**Establishing commit:** `9501bfdd7114` (John Spray, 2016-07-26); extracted without change in `35f6dd06`.

**Intent:**  
Private declaration of `uint64_t get_current() const`. Intended to return the most-recent scalar value from `buffer`. Declared private — not part of the public interface.

**Invariants:**
- The function is **declared** in the header but has **no definition** in either the `.cc` file or anywhere visible in this corpus.
- `9501bfdd7114` is the sole SHA that established this declaration.

**Error conditions:** N/A (undefined).

**Implementation critique (`.h` line 52):**

> **DIVERGED — `9501bfdd7114` declares `get_current()` but no definition exists.**

The function is declared at `.h:52` but the `.cc` file (confirmed by the full diff of `35f6dd06` which shows the entire `.cc` content) contains **only** `push()` and `push_avg()` — no `get_current()` implementation. No external `.cc` file provides it either (the blame shows no SHA writing a body for it). 

This is an **ODR violation / linker error waiting to happen** if any code calls `get_current()`. It is either:
1. A function that was intended but never implemented, or
2. A function body that lived in `DaemonState.cc` before the extraction, where the body was not carried over during `35f6dd06`.

**DIVERGED:** `9501bfdd7114` established the declaration; `35f6dd06` (line `.cc:16–25`) extracted only `push` and `push_avg`, leaving `get_current()` without a body. **The declaration at `.h:52` has no corresponding implementation.**

---

### 3.4 `get_data` — `.h` line 55

**Establishing commit:** `9501bfdd7114` (John Spray, 2016-07-26); extracted without change in `35f6dd06`.

**Intent:**  
Public accessor returning `const boost::circular_buffer<DataPoint>&`. Gives callers read-only access to the full history ring-buffer.

**Invariants established by `9501bfdd7114`:**
- Returns by const reference — no copy.
- Buffer is the `boost::circular_buffer<DataPoint>` member; its size is set in the constructor to 20 entries.
- Callers must not assume the buffer is non-empty; it may have zero entries if `push()` has never been called.

**Error conditions:** None enforced. Calling code must handle an empty buffer.

**Implementation critique (`.h` lines 55–58):**
```cpp
const boost::circular_buffer<DataPoint> & get_data() const
{
  return buffer;
}
```
- Implementation matches intent exactly.
- **UNGROUNDED:** No `[[nodiscard]]`. Not a defect — no commit ever asked for it.
- No issues.

---

### 3.5 `get_latest_data` — `.h` line 59

**Establishing commit:** `b421142b1c6f` (Jan Fajerski, 2018-09-07, original in `DaemonState.h`); extracted without change in `35f6dd06`.

**Intent:**  
Returns `const DataPoint&` — the most-recently-pushed scalar sample (`buffer.back()`).

**Invariants established by `b421142b1c6f`:**
- Calls `boost::circular_buffer::back()`, which is **undefined behaviour** if the buffer is empty (`buffer.size() == 0`).
- `b421142b1c6f` did not add a precondition guard; the calling context at the time was assumed to always have at least one sample before calling this.

**Error conditions:**  
**DIVERGED — `b421142b1c6f` implicitly requires non-empty buffer, but no precondition is enforced.**

The current implementation at `.h:59–62`:
```cpp
const DataPoint& get_latest_data() const
{
  return buffer.back();
}
```
calls `buffer.back()` without checking `!buffer.empty()`. `boost::circular_buffer::back()` on an empty buffer is undefined behaviour. There is no assertion, no precondition comment, and no documentation from `b421142b1c6f` that callers must guarantee non-emptiness. If the constructor creates a `buffer` with capacity 20 but no elements have been `push()`-ed yet, calling `get_latest_data()` will invoke UB.

**DIVERGED:** `b421142b1c6f` introduced this call at `.h:59–62` without an emptiness guard. The missing pre-condition check is an unresolved hazard.

---

### 3.6 `get_data_avg` — `.h` line 63

**Establishing commit:** `1164ef2f32d8` (Boris Ranto, 2018-05-15); extracted without change in `35f6dd06`.

**Intent:**  
Public accessor returning `const boost::circular_buffer<AvgDataPoint>&`. Gives callers read-only access to the full average-counter history ring-buffer.

**Invariants established by `1164ef2f32d8`:**
- Returns by const reference — no copy.
- Buffer has capacity 20, set in the constructor when `type & PERFCOUNTER_LONGRUNAVG`.
- If `PERFCOUNTER_LONGRUNAVG` is not set, `avg_buffer` is **default-constructed** with capacity 0.

**Error conditions:** None enforced. Callers on a non-`LONGRUNAVG` instance will receive an empty/zero-capacity buffer.

**Implementation critique (`.h` lines 63–66):**
```cpp
const boost::circular_buffer<AvgDataPoint> & get_data_avg() const
{
  return avg_buffer;
}
```
- **UNGROUNDED:** `get_data_avg()` is callable on any `PerfCounterInstance`, even those where `avg_buffer` was never sized (non-`LONGRUNAVG` counters). Such callers will get a zero-capacity buffer; whether that is a bug depends on the caller. No commit ever added a type-guard or assertion here.
- Implementation matches Boris Ranto's `1164ef2f32d8` intent. No DIVERGED.

---

### 3.7 `get_latest_data_avg` — `.h` line 67

**Establishing commit:** `b421142b1c6f` (Jan Fajerski, 2018-09-07); extracted without change in `35f6dd06`.

**Intent:**  
Returns `const AvgDataPoint&` — the most-recently-pushed average-counter sample (`avg_buffer.back()`).

**Invariants established by `b421142b1c6f`:**
- Calls `boost::circular_buffer::back()`, which is **undefined behaviour** if `avg_buffer` is empty.
- Same class of hazard as `get_latest_data()` — the commit did not add an emptiness guard.

**Error conditions:**  
**DIVERGED — same pattern as `get_latest_data`.**

Current implementation at `.h:67–70`:
```cpp
const AvgDataPoint& get_latest_data_avg() const
{
  return avg_buffer.back();
}
```
No `avg_buffer.empty()` check. For a non-`LONGRUNAVG` counter, `avg_buffer` has capacity 0 and no elements; calling `avg_buffer.back()` is UB. For a `LONGRUNAVG` counter that has received no samples yet, the same applies.

**DIVERGED:** `b421142b1c6f` introduced this at `.h:67–70` without an emptiness guard or precondition contract. Calling this on an empty or uninitialized `avg_buffer` is undefined behaviour.

---

### 3.8 `push` declaration — `.h` line 71

**Establishing commit:** `9501bfdd7114` (John Spray, 2016-07-26); extracted without change in `35f6dd06`.

**Intent:**  
Declares `void push(utime_t t, uint64_t const &v)`. Public interface for appending a scalar counter sample.

**Notes:** Declaration only; see §3.10 for the definition.

---

### 3.9 `push_avg` declaration — `.h` line 72

**Establishing commit:** `1164ef2f32d8` (Boris Ranto, 2018-05-15); extracted without change in `35f6dd06`.

**Intent:**  
Declares `void push_avg(utime_t t, uint64_t const &s, uint64_t const &c)`. Public interface for appending an average-counter sample.

**Notes:** Declaration only; see §3.11 for the definition.

---

### 3.10 `PerfCounterInstance` constructor — `.h` line 74

**Establishing commit:** `1164ef2f32d8` (Boris Ranto, 2018-05-15); extracted without change in `35f6dd06`.

**Intent:**  
The sole constructor. Takes `enum perfcounter_type_d type`. Based on whether the `PERFCOUNTER_LONGRUNAVG` bit is set in `type`, sizes **exactly one** of the two ring-buffers to capacity 20; the other is left at its default-constructed state (capacity 0, size 0).

**Invariants established by `1164ef2f32d8`:**
- If `type & PERFCOUNTER_LONGRUNAVG`: only `avg_buffer` gets capacity 20; `buffer` has capacity 0.
- If `!(type & PERFCOUNTER_LONGRUNAVG)`: only `buffer` gets capacity 20; `avg_buffer` has capacity 0.
- This is a **mutually exclusive** design: a given `PerfCounterInstance` is either a scalar counter *or* an average counter, never both.
- The capacity of 20 is a hardcoded magic number; no comment in any commit explains the choice.
- The constructor ends with a semicolon (`};`) which is harmless in C++ but unusual — a style nit traceable to the original `DaemonState.h` code, carried over verbatim.

**Error conditions:**
- No validation of `type`; any bit combination is accepted.
- If `type` is 0, `buffer` gets capacity 20 — this is the scalar-counter path by default.

**Implementation critique (`.h` lines 74–80):**
```cpp
PerfCounterInstance(enum perfcounter_type_d type)
{
  if (type & PERFCOUNTER_LONGRUNAVG)
    avg_buffer = boost::circular_buffer<AvgDataPoint>(20);
  else
    buffer = boost::circular_buffer<DataPoint>(20);
};
```
- **UNGROUNDED:** The magic constant `20` is not documented. No commit comment explains why 20 samples.
- **UNGROUNDED:** The trailing semicolon after `}` on line 80 is legal C++ but inconsistent. It was present in `1164ef2f32d8`'s original and was preserved verbatim in `35f6dd06`. Not a defect.
- The assignment `avg_buffer = boost::circular_buffer<AvgDataPoint>(20)` initialises the buffer *after* default construction (capacity 0). This is correct but could be done more efficiently as a member-initializer list if the type were not runtime-branched.
- No issues that constitute a DIVERGED finding.

---

### 3.11 `push` implementation — `.cc` line 16

**Establishing commit:** `9501bfdd7114` (John Spray, 2016-07-26, in `DaemonState.cc`); extracted without change in `35f6dd06`.

**Intent:**  
Appends `{t, v}` as a `DataPoint` to the circular buffer `buffer`.

**Invariants established by `9501bfdd7114`:**
- Unconditionally calls `buffer.push_back({t, v})`.
- When `buffer` has capacity 20 and is full, `push_back` on a `boost::circular_buffer` **overwrites the oldest entry** — the circular buffer semantics are intentional; no data is lost in the sense of hard failure, but the oldest sample is silently dropped.
- The caller is responsible for only calling `push()` on a scalar-type `PerfCounterInstance` (i.e., `!(type & PERFCOUNTER_LONGRUNAVG)`). Calling `push()` on a `LONGRUNAVG` instance writes to `buffer` which has capacity 0 — `push_back` on a zero-capacity `boost::circular_buffer` is a no-op (the item is silently discarded), not a crash.

**Error conditions:**
- Calling `push()` on a `LONGRUNAVG`-typed instance silently discards the data. No commit ever added a type-check or assertion here.
- **UNGROUNDED:** No assertion that `buffer.capacity() > 0` before push. This is a silent discard if called on the wrong counter type.

**Implementation critique (`.cc` lines 16–19):**
```cpp
void PerfCounterInstance::push(utime_t t, uint64_t const &v)
{
  buffer.push_back({t, v});
}
```
- Implementation matches intent from `9501bfdd7114`.
- **UNGROUNDED:** No type-check or assertion guards the push for the wrong counter type. Silent discard is the result.
- No DIVERGED finding; the silent-discard is a design choice, not a contradiction.

---

### 3.12 `push_avg` implementation — `.cc` line 21

**Establishing commit:** `1164ef2f32d8` (Boris Ranto, 2018-05-15, in `DaemonState.cc`); extracted without change in `35f6dd06`.

**Intent:**  
Appends `{t, s, c}` as an `AvgDataPoint` to `avg_buffer`.

**Invariants established by `1164ef2f32d8`:**
- Unconditionally calls `avg_buffer.push_back({t, s, c})`.
- Symmetric to `push()`: on a non-`LONGRUNAVG` instance, `avg_buffer` has capacity 0 and the push is a no-op (silent discard).
- `c` is the event count; `c == 0` is accepted without error — the struct stores it faithfully.

**Error conditions:**
- Same silent-discard hazard as `push()` for the wrong counter type.

**Implementation critique (`.cc` lines 21–25):**
```cpp
void PerfCounterInstance::push_avg(utime_t t, uint64_t const &s,
                                   uint64_t const &c)
{
  avg_buffer.push_back({t, s, c});
}
```
- Implementation matches intent from `1164ef2f32d8`.
- **UNGROUNDED:** No type-check or assertion. Silent discard possible.
- No DIVERGED finding.

---

## 4. Findings Summary

### 4.1 DIVERGED Findings

| ID | Function | Establishing SHA | Contradicting Location | Description |
|----|----------|-----------------|----------------------|-------------|
| D-1 | `get_current` | `9501bfdd7114` | `.cc` (entire file) | Function declared at `.h:52` but **no definition exists** in `.cc` or any other file in the extraction. The body was not carried over when `35f6dd06` split `DaemonState.cc` into `PerfCounterInstance.cc`. |
| D-2 | `get_latest_data` | `b421142b1c6f` | `.h:61` | `buffer.back()` called without checking `!buffer.empty()`. Undefined behaviour when buffer has 0 elements. `b421142b1c6f` provided no precondition. |
| D-3 | `get_latest_data_avg` | `b421142b1c6f` | `.h:69` | `avg_buffer.back()` called without checking `!avg_buffer.empty()`. Undefined behaviour on empty or zero-capacity buffer. Same root cause as D-2. |

### 4.2 UNGROUNDED Code Paths

| ID | Location | Description |
|----|----------|-------------|
| U-1 | `.h:74–80` (ctor) | Magic constant `20` for buffer capacity. No commit ever documented the rationale. |
| U-2 | `.cc:16–19` (`push`) | No assertion that `buffer.capacity() > 0`. Wrong-type calls silently discard data. |
| U-3 | `.cc:21–25` (`push_avg`) | No assertion that `avg_buffer.capacity() > 0`. Wrong-type calls silently discard data. |
| U-4 | `.h:63–66` (`get_data_avg`) | Callable on non-`LONGRUNAVG` instances; returns zero-capacity buffer. No guard or note. |
| U-5 | `.h:44` (`AvgDataPoint`) | Field `s` = "sum", `c` = "count" — names are underdocumented; no commit wrote a comment. |
| U-6 | `.h:80` (ctor) | Trailing `;` after `}` is legal but unexplained; carried from `1164ef2f32d8` without remark. |

### 4.3 OVERCAUTIOUS Findings

None identified. All defensive checks (circular_buffer capacity initialisation, const-ref returns) are proportionate to the actual risks present.

---

## 5. Invariant Catalogue

The following invariants are established by the cited commits and must be preserved:

| Invariant | Established By | Statement |
|-----------|---------------|-----------|
| INV-1 | `1164ef2f32d8` | A `PerfCounterInstance` is either scalar (`buffer` capacity=20, `avg_buffer` capacity=0) **or** average (`avg_buffer` capacity=20, `buffer` capacity=0). Never both. |
| INV-2 | `9501bfdd7114` | `buffer` stores timestamped `uint64_t` values. The circular buffer silently drops oldest entry on overflow. |
| INV-3 | `1164ef2f32d8` | `avg_buffer` stores `(sum, count)` pairs. Both are unsigned 64-bit. `count==0` is a valid stored value. |
| INV-4 | `9501bfdd7114` | `get_data()` always returns a const reference — no copy is made. |
| INV-5 | `b421142b1c6f` | `get_latest_data()` / `get_latest_data_avg()` are only safe to call when the respective buffer is non-empty. (Not enforced — see D-2, D-3.) |
| INV-6 | `35f6dd06` | The class has no default constructor; the type-discriminating constructor is the only construction path. |

---

## 6. Self-Check

| Check | Status |
|-------|--------|
| Every commit in `commits.txt` read? | ✅ All 29 diffs read. 28 are Clock.h-only (rename chain false positives); 1 (`35f6dd06`) is the sole effective commit for PerfCounterInstance. |
| Every function in `functions.txt` has a section? | ✅ 12 functions covered in §3.1–3.12. |
| Every DIVERGED flag cites a SHA? | ✅ D-1: `9501bfdd7114`/`35f6dd06`; D-2: `b421142b1c6f`; D-3: `b421142b1c6f`. |
| Every invariant cites the SHA that established it? | ✅ INV-1 through INV-6 all cite SHAs. |
| All UNGROUNDED code paths flagged? | ✅ U-1 through U-6 in §4.2. |
| Blame-only SHAs (not in commits.txt) explained? | ✅ §1.4 documents `9501bfdd7114`, `1164ef2f32d8`, `b421142b1c6f`, `a17349b87afd`, `ac30e6cee2b2` with original files. |
| Rename-chain false positives identified and excluded? | ✅ §1.3. |
