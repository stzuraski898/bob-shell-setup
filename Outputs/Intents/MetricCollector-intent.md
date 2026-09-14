# Intent Assessment: MetricCollector

**Source files:** `src/mgr/MetricCollector.cc`, `src/mgr/MetricCollector.h`
**Corpus HEAD:** `8681fa6ebac230f86eb445bf57095c63e7f1abcc` (2025-10-01)
**Assessment date:** 2026-09-11
**Commits analysed:** 7
**Date range:** 2019-08-26 through 2025-10-01
**Functions assessed:** 13

> This artefact was produced by an AI assessment agent reading the raw git
> corpus in `/home/szuraski/BobOutput/Object History/v4/MetricCollector/`.
> It describes the *intended* behaviour of each function as reconstructed from
> commit history — not necessarily what the current code does.
> Test-writing agents should use this as the ground truth for what to test,
> and treat divergences as likely bugs.

## Class overview

`MetricCollector<Query, Limit, Key, Report>` is an abstract template class in the Ceph Manager daemon (`ceph-mgr`) that generalizes querying routines and performance metric aggregation across Ceph subsystems (principally OSD and MDS performance metrics). It provides thread-safe registration, tracking, and removal of client performance metric queries with optional query limits, dispatches notifications to a `MetricListener` when query subscriptions or limits change, unpacks incoming packed performance counter reports, and maintains active performance counter maps indexed by query ID and entity key. Structural milestones in its history include extraction and templatization from `OSDPerfMetricCollector` in `efcebe1eb4ae`, multi-subsystem MDS metrics support in `f6ba1eea`, migration of counter retrieval to the locking contract in `7523aef6`, dynamic failover reregistration via `reregister_queries()` in `c2470f27`, and defensive optional-limit handling in `9a05872f`.

---

## `MetricCollector<Query, Limit, Key, Report>::MetricCollector(MetricListener &listener)`

**Introduced:** `efcebe1eb4ae16ea9c633436e3e105add4a2662c` — mgr: templatize/generalize metrics collection interface  
**Last modified:** `efcebe1eb4ae16ea9c633436e3e105add4a2662c` — mgr: templatize/generalize metrics collection interface  
**Change count:** 1 commit touched this function  
**Divergence:** OK  

### Intent
Construct a new `MetricCollector` instance and bind the reference to the `MetricListener` callback interface that receives notification whenever active metric queries are added, removed, or updated. (Established: `efcebe1eb4ae`.)

### Invariants and contracts
- Binds and stores a reference to `MetricListener &listener`. (Established: `efcebe1eb4ae`.)
- Initializes `next_query_id` to 0. (Established: `efcebe1eb4ae`.)

### Error conditions
- None. Construction does not throw and assumes a valid `MetricListener` reference.

### Evolution summary
Introduced during the generalization of `MetricCollector` in `efcebe1eb4ae`. The implementation has remained unchanged.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`src/mgr/MetricCollector.cc:17-21`](../../../ceph/src/mgr/MetricCollector.cc:17) and [`src/mgr/MetricCollector.h:29`](../../../ceph/src/mgr/MetricCollector.h:29) properly initialize the member `listener(listener)`.

---

## `MetricCollector<Query, Limit, Key, Report>::~MetricCollector()`

**Introduced:** `efcebe1eb4ae16ea9c633436e3e105add4a2662c` — mgr: templatize/generalize metrics collection interface  
**Last modified:** `efcebe1eb4ae16ea9c633436e3e105add4a2662c` — mgr: templatize/generalize metrics collection interface  
**Change count:** 1 commit touched this function  
**Divergence:** OK  

### Intent
Virtual destructor allowing safe polymorphic destruction of specialized collector derived classes (`OSDPerfMetricCollector`, `MDSPerfMetricCollector`). (Established: `efcebe1eb4ae`.)

### Invariants and contracts
- Must be `virtual` to allow clean polymorphic destruction through base pointers/references. (Established: `efcebe1eb4ae`.)

### Error conditions
- None. Destructor is noexcept/trivial.

### Evolution summary
Introduced inline in the header in `efcebe1eb4ae` and unchanged.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`src/mgr/MetricCollector.h:24-25`](../../../ceph/src/mgr/MetricCollector.h:24) declares an empty virtual destructor.

---

## `MetricCollector<Query, Limit, Key, Report>::add_query(const Query &query, const std::optional<Limit> &limit)`

**Introduced:** `efcebe1eb4ae16ea9c633436e3e105add4a2662c` — mgr: templatize/generalize metrics collection interface  
**Last modified:** `efcebe1eb4ae16ea9c633436e3e105add4a2662c` — mgr: templatize/generalize metrics collection interface  
**Change count:** 1 commit touched this function  
**Divergence:** OK  

### Intent
Register a new metric query with an optional limit, allocate a unique monotonic `MetricQueryID`, track it under the `queries` table, allocate an empty entry in the `counters` table for that query ID, and trigger `listener.handle_query_updated()` outside the lock if the query is new or if existing registrations for that query are limited. (Established: `efcebe1eb4ae`.)

### Invariants and contracts
- Acquires `lock` before accessing or modifying `next_query_id`, `queries`, and `counters`. (Established: `efcebe1eb4ae`.)
- Increments `next_query_id` monotonically to produce a unique ID per call. (Established: `efcebe1eb4ae`.)
- Sets `notify = true` if `queries.find(query) == queries.end()` (new query being registered) or if `is_limited(it->second)` is true for existing registrations. (Established: `efcebe1eb4ae`.)
- Registers the new `query_id -> limit` mapping in `queries[query]`. (Established: `efcebe1eb4ae`.)
- Initializes `counters[query_id]` to an empty counter map. (Established: `efcebe1eb4ae`.)
- Releases `lock` before invoking `listener.handle_query_updated()`. (Established: `efcebe1eb4ae`.)
- Always returns the allocated `query_id`. (Established: `efcebe1eb4ae`.)

### Error conditions
- None. Returns allocated `MetricQueryID` unconditionally.

### Evolution summary
Originally adapted from `OSDPerfMetricCollector` in `efcebe1eb4ae` into the generic template method. Header declaration at line 31, implementation at line 23.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`src/mgr/MetricCollector.cc:23-56`](../../../ceph/src/mgr/MetricCollector.cc:23) acquires `lock` at line 31, allocates `query_id` at line 33, determines `notify` status at lines 35–42, emplaces into `queries` and `counters` at lines 44–45, releases `lock` at block exit line 46, invokes `listener.handle_query_updated()` at line 52 if `notify` is true, and returns `query_id` at line 55.

---

## `MetricCollector<Query, Limit, Key, Report>::remove_query(MetricQueryID query_id)`

**Introduced:** `efcebe1eb4ae16ea9c633436e3e105add4a2662c` — mgr: templatize/generalize metrics collection interface  
**Last modified:** `efcebe1eb4ae16ea9c633436e3e105add4a2662c` — mgr: templatize/generalize metrics collection interface  
**Change count:** 1 commit touched this function  
**Divergence:** OK  

### Intent
Unregister an existing query by its `MetricQueryID`, purge its associated counter map, update the query sets, and notify the listener if the query was erased completely or remaining registrations for that query are limited. (Established: `efcebe1eb4ae`.)

### Invariants and contracts
- Acquires `lock` before modifying internal state. (Established: `efcebe1eb4ae`.)
- Searches all query buckets in `queries` for `query_id`. (Established: `efcebe1eb4ae`.)
- If `query_id` is found, removes it from the inner map. If the inner map becomes empty, erases the query entirely from `queries` and sets `notify = true`. (Established: `efcebe1eb4ae`.)
- If other sub-queries remain for that query and `is_limited(it->second)` holds true, sets `notify = true`. (Established: `efcebe1eb4ae`.)
- Erases `counters[query_id]`. (Established: `efcebe1eb4ae`.)
- Releases `lock` before notifying `listener.handle_query_updated()` or returning. (Established: `efcebe1eb4ae`.)
- If `query_id` is not found, returns `-ENOENT` without notifying listener. (Established: `efcebe1eb4ae`.)
- If found, returns 0. (Established: `efcebe1eb4ae`.)

### Error conditions
- Returns `-ENOENT` if `query_id` does not exist in `queries`. (Established: `efcebe1eb4ae`.)

### Evolution summary
Generalised into template form in `efcebe1eb4ae`. Declaration in header at line 33, definition in `.cc` at line 57.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`src/mgr/MetricCollector.cc:57-100`](../../../ceph/src/mgr/MetricCollector.cc:57) locks `lock` at line 65, traverses `queries` at lines 67–84, erases query ID, conditionally erases empty query bucket at line 76 or checks `is_limited` at line 78, erases `counters[query_id]` at line 85, drops lock at line 86, returns `-ENOENT` at line 90 if not found, invokes `listener.handle_query_updated()` at line 96 if `notify`, and returns 0 at line 99.

---

## `MetricCollector<Query, Limit, Key, Report>::remove_all_queries()`

**Introduced:** `efcebe1eb4ae16ea9c633436e3e105add4a2662c` — mgr: templatize/generalize metrics collection interface  
**Last modified:** `efcebe1eb4ae16ea9c633436e3e105add4a2662c` — mgr: templatize/generalize metrics collection interface  
**Change count:** 1 commit touched this function  
**Divergence:** OK  

### Intent
Clear all registered queries from the collector and notify the listener if any queries were active prior to clearing. (Established: `efcebe1eb4ae`.)

### Invariants and contracts
- Acquires `lock` during map inspection and clearing. (Established: `efcebe1eb4ae`.)
- Sets `notify = !queries.empty()`. (Established: `efcebe1eb4ae`.)
- Clears `queries`. (Established: `efcebe1eb4ae`.)
- Note: `counters` map is not cleared in `remove_all_queries()`, only `queries` is cleared (matching historical behavior in `efcebe1eb4ae`).
- Invokes `listener.handle_query_updated()` outside the lock if `notify` was true. (Established: `efcebe1eb4ae`.)

### Error conditions
- None. Returns void.

### Evolution summary
Templatized in `efcebe1eb4ae`. Header declaration at line 35, implementation at line 101.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`src/mgr/MetricCollector.cc:101-117`](../../../ceph/src/mgr/MetricCollector.cc:101) locks `lock` at line 108, checks non-empty and clears `queries` at lines 110–111, releases lock at line 112, and invokes `listener.handle_query_updated()` at line 115 if `notify` is true.

---

## `MetricCollector<Query, Limit, Key, Report>::reregister_queries()`

**Introduced:** `c2470f271cce4d512f2cf00552c9b753e4c69f71` — mgr, pybind/mgr, mgr/stats: be resilient to offline rank0 MDS  
**Last modified:** `c2470f271cce4d512f2cf00552c9b753e4c69f71` — mgr, pybind/mgr, mgr/stats: be resilient to offline rank0 MDS  
**Change count:** 1 commit touched this function  
**Divergence:** OK  

### Intent
Trigger a query update notification to the listener (`listener.handle_query_updated()`) to reregister existing user queries with daemons following a failover or reconnect event (e.g., rank 0 MDS failover). (Established: `c2470f27`.)

### Invariants and contracts
- Unconditionally calls `listener.handle_query_updated()`. (Established: `c2470f27`.)
- Does not modify or require holding `lock` because it only triggers listener notification of currently registered queries. (Established: `c2470f27`.)

### Error conditions
- None.

### Evolution summary
Added in `c2470f27` to address tracker issue 50033 so that manager performance statistic gathering remains resilient when daemon failover occurs.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`src/mgr/MetricCollector.cc:118-123`](../../../ceph/src/mgr/MetricCollector.cc:118) and [`src/mgr/MetricCollector.h:37`](../../../ceph/src/mgr/MetricCollector.h:37) log at dout(20) and invoke `listener.handle_query_updated()` directly at line 122.

---

## `MetricCollector<Query, Limit, Key, Report>::get_queries() const`

**Introduced:** `efcebe1eb4ae16ea9c633436e3e105add4a2662c` — mgr: templatize/generalize metrics collection interface  
**Last modified:** `9a05872fdd499575961ee1a8d188d19054841eb8` — MetricCollector.h: Add check to prevent mgr from crashing  
**Change count:** 2 commits touched this function  
**Divergence:** OK  

### Intent
Return a snapshot mapping of all registered queries to their combined set of active limits (`std::map<Query, std::set<Limit>>`). If a query has only unlimited registrations, the limit set in the returned map is empty; if any registration is limited, all valid limits for that query are collected. (Established: `efcebe1eb4ae`, `9a05872f`.)

### Invariants and contracts
- Acquires `lock` before accessing `queries`. (Established: `efcebe1eb4ae`.)
- Iterates over each `[query, limits]` entry in `queries` and creates a corresponding key in the `result` map. (Established: `efcebe1eb4ae`.)
- If `is_limited(limits)` is true, iterates over `limits` and inserts `*limit.second` into the result set only if `limit.second.has_value() == true` / `limit.second` is non-empty. (Established: `9a05872f`.)
- Returns the resulting `map<Query, Limits>` by value. (Established: `efcebe1eb4ae`.)

### Error conditions
- None.

### Evolution summary
Introduced inline in `src/mgr/MetricCollector.h` in `efcebe1eb4ae`. In `9a05872f`, the guard `if (limit.second)` was added inside the limit insertion loop to prevent crashing from dereferencing null/empty `std::optional<Limit>` entries when some query registrations have limits and others are unlimited.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`src/mgr/MetricCollector.h:39-55`](../../../ceph/src/mgr/MetricCollector.h:39) acquires `lock` with `std::lock_guard` at line 40, iterates `queries` at line 43, evaluates `is_limited` at line 45, checks `if (limit.second)` at line 47 before dereferencing at line 48 (matching `9a05872f`), and returns `result` at line 54.

---

## `MetricCollector<Query, Limit, Key, Report>::process_reports(const MetricPayload &payload)`

**Introduced:** `efcebe1eb4ae16ea9c633436e3e105add4a2662c` — mgr: templatize/generalize metrics collection interface  
**Last modified:** `efcebe1eb4ae16ea9c633436e3e105add4a2662c` — mgr: templatize/generalize metrics collection interface  
**Change count:** 1 commit touched this function  
**Divergence:** OK  

### Intent
Pure virtual method interface to be implemented by derived collector classes to unpack subsystem-specific metric report payloads (e.g., `OSDMetricPayload`, `MDSMetricPayload`) received from daemons and forward them to `process_reports_generic`. (Established: `efcebe1eb4ae`.)

### Invariants and contracts
- Subclasses must implement `process_reports` to decode payload and invoke `process_reports_generic`. (Established: `efcebe1eb4ae`.)

### Error conditions
- Polymorphic abstract interface.

### Evolution summary
Introduced in `efcebe1eb4ae` as the generalization point for incoming metric report handling.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`src/mgr/MetricCollector.h:57`](../../../ceph/src/mgr/MetricCollector.h:57) declares `virtual void process_reports(const MetricPayload &payload) = 0;`.

---

## `MetricCollector<Query, Limit, Key, Report>::get_counters(PerfCollector *collector)`

**Introduced:** `7523aef6e8656952418d17227c877952f9370f95` — mgr/stats: mds performance stats module  
**Last modified:** `7523aef6e8656952418d17227c877952f9370f95` — mgr/stats: mds performance stats module  
**Change count:** 1 commit touched this function  
**Divergence:** OK  

### Intent
Pure virtual method interface for derived collectors to retrieve performance counters into a subsystem-specific collector container (such as MDS or OSD perf collector), delegating to `get_counters_generic` under the collector lock. (Established: `7523aef6`.)

### Invariants and contracts
- Replaces earlier non-virtual `get_counters(MetricQueryID, ...)` with a pure virtual hook accepting `PerfCollector *`. (Established: `7523aef6`.)

### Error conditions
- Derived class implementations return 0 on success or negative error code (e.g. `-ENOENT`).

### Evolution summary
In `efcebe1eb4ae`, `get_counters` was a concrete public method. In `7523aef6`, the concrete logic was renamed to `get_counters_generic` (protected), and `get_counters(PerfCollector*)` became pure virtual in `MetricCollector.h`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`src/mgr/MetricCollector.h:58`](../../../ceph/src/mgr/MetricCollector.h:58) declares `virtual int get_counters(PerfCollector *collector) = 0;`.

---

## `MetricCollector<Query, Limit, Key, Report>::get_counters_generic(MetricQueryID query_id, std::map<Key, PerformanceCounters> *c)`

**Introduced:** `7523aef6e8656952418d17227c877952f9370f95` — mgr/stats: mds performance stats module  
**Last modified:** `7523aef6e8656952418d17227c877952f9370f95` — mgr/stats: mds performance stats module  
**Change count:** 1 commit touched this function  
**Divergence:** OK  

### Intent
Extract and transfer (via move) the aggregated performance counters for a given `query_id` into the output map `*c`, and clear the internal counter storage for that query ID. (Established: `efcebe1eb4ae`, `7523aef6`.)

### Invariants and contracts
- The caller MUST hold `lock` before invoking `get_counters_generic` (`ceph_assert(ceph_mutex_is_locked(lock))`). (Established: `7523aef6`.)
- If `query_id` is not present in `counters`, returns `-ENOENT`. (Established: `efcebe1eb4ae`.)
- On success, moves `counters[query_id]` into `*c`, calls `clear()` on the map in `counters`, and returns 0. (Established: `efcebe1eb4ae`.)

### Error conditions
- Returns `-ENOENT` if `query_id` is not found in `counters`. (Established: `efcebe1eb4ae`.)

### Evolution summary
Originally introduced as `get_counters` in `efcebe1eb4ae`, which acquired `lock` locally. In `7523aef6`, it was converted to `get_counters_generic` with `ceph_assert(ceph_mutex_is_locked(lock))` to allow derived classes to coordinate locking across composite queries.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`src/mgr/MetricCollector.cc:124-141`](../../../ceph/src/mgr/MetricCollector.cc:124) asserts `ceph_mutex_is_locked(lock)` at line 129, searches for `query_id` at line 131, returns `-ENOENT` at line 134 if missing, moves the counters map to `*c` at line 137, clears the entry at line 138, and returns 0 at line 140.

---

## `MetricCollector<Query, Limit, Key, Report>::process_reports_generic(const std::map<Query, Report> &reports, UpdateCallback callback)`

**Introduced:** `efcebe1eb4ae16ea9c633436e3e105add4a2662c` — mgr: templatize/generalize metrics collection interface  
**Last modified:** `f6ba1eea4cde2354e639518210a56d157081ecac` — mds: forward mds metrics to ceph manager w/ quering interfaces  
**Change count:** 2 commits touched this function  
**Divergence:** OK  

### Intent
Process packed performance reports received from daemons for matching queries. For each report and key, iterates over the registered query descriptors, unpacks packed counters from bufferlists, and invokes `callback(&key_counters[i], c)` to update/accumulate performance counters for every registered listener query ID. (Established: `efcebe1eb4ae`.)

### Invariants and contracts
- Caller MUST hold `lock` (`ceph_assert(ceph_mutex_is_locked(lock))`). (Established: `efcebe1eb4ae`.)
- If `reports` is empty, returns immediately. (Established: `efcebe1eb4ae`.)
- For each `[query, report]` in `reports`, iterates through `report.group_packed_performance_counters`. (Established: `efcebe1eb4ae`.)
- For every registered query ID `p.first` in `queries[query]`, ensures `counters[p.first][key]` is resized to match `query.performance_counter_descriptors.size()`. (Established: `efcebe1eb4ae`.)
- Iterates through descriptors, breaks if `desc_it == report.performance_counter_descriptors.end()`, skips descriptor mismatch with `continue`, unpacks counter `c` using `desc_it->unpack_counter(bl_it, &c)`, and invokes `callback` on all query IDs registered for that query. (Established: `efcebe1eb4ae`.)

### Error conditions
- Missing/empty reports return early with no effect. (Established: `efcebe1eb4ae`.)
- Mismatched or truncated descriptors in report are skipped safely. (Established: `efcebe1eb4ae`.)

### Evolution summary
Introduced as generic report processor in `efcebe1eb4ae`. In `f6ba1eea`, explicit template instantiation for `MDSPerfMetricQuery` types was added to support MDS metrics forwarding.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`src/mgr/MetricCollector.cc:142-187`](../../../ceph/src/mgr/MetricCollector.cc:142) asserts lock held at line 146, returns if empty at lines 148–150, unpacks each counter with `desc_it->unpack_counter(bl_it, &c)` at line 177, updates matching counter slots via `callback` at lines 178–183, and increments `desc_it` at line 184.

---

## `MetricCollector<Query, Limit, Key, Report>::is_limited(const std::map<MetricQueryID, OptionalLimit> &limits) const`

**Introduced:** `efcebe1eb4ae16ea9c633436e3e105add4a2662c` — mgr: templatize/generalize metrics collection interface  
**Last modified:** `efcebe1eb4ae16ea9c633436e3e105add4a2662c` — mgr: templatize/generalize metrics collection interface  
**Change count:** 1 commit touched this function  
**Divergence:** OK  

### Intent
Determine whether any of the registered query instances in the `limits` map has a defined limit (`std::optional<Limit>::has_value() == true`). (Established: `efcebe1eb4ae`.)

### Invariants and contracts
- Evaluates predicate `limits.second.has_value()` across all elements using `std::any_of`. (Established: `efcebe1eb4ae`.)
- Returns `true` if at least one query has a limit configured; `false` otherwise. (Established: `efcebe1eb4ae`.)

### Error conditions
- None.

### Evolution summary
Introduced in `MetricCollector.h` private section during templatization in `efcebe1eb4ae`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`src/mgr/MetricCollector.h:79-82`](../../../ceph/src/mgr/MetricCollector.h:79) evaluates `std::any_of` checking `limits.second.has_value()`.

---

## `MetricCollector<Query, Limit, Key, Report>::is_limited(const std::map<MetricQueryID, OptionalLimit> &limits) const [lambda __anon8d438db30102]`

**Introduced:** `efcebe1eb4ae16ea9c633436e3e105add4a2662c` — mgr: templatize/generalize metrics collection interface  
**Last modified:** `efcebe1eb4ae16ea9c633436e3e105add4a2662c` — mgr: templatize/generalize metrics collection interface  
**Change count:** 1 commit touched this function  
**Divergence:** OK  

### Intent
Predicate lambda within `is_limited` checking whether an individual `(MetricQueryID, OptionalLimit)` map entry has a limit set (`has_value()`). (Established: `efcebe1eb4ae`.)

### Invariants and contracts
- Returns `limits.second.has_value()`. (Established: `efcebe1eb4ae`.)

### Error conditions
- None.

### Evolution summary
Generated as ctags entry `__anon8d438db30102` for the inline lambda in `is_limited` in `src/mgr/MetricCollector.h:81`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`src/mgr/MetricCollector.h:81`](../../../ceph/src/mgr/MetricCollector.h:81) correctly returns `limits.second.has_value()`.
