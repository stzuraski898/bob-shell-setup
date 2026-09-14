# Intent Assessment: MgrMapCache

**Source files:** `src/mgr/MgrMapCache.cc`, `src/mgr/MgrMapCache.h`
**Corpus HEAD:** `8681fa6ebac230f86eb445bf57095c63e7f1abcc` (2025-07-17)
**Assessment date:** 2026-09-11
**Commits analysed:** 1
**Functions assessed:** 64

> This artefact was produced by an AI assessment agent reading the raw git
> corpus in `/home/szuraski/BobOutput/Object History/v4/MgrMapCache/`.
> It describes the *intended* behaviour of each function as reconstructed from
> commit history — not necessarily what the current code does.
> Test-writing agents should use this as the ground truth for what to test,
> and treat divergences as likely bugs.

## Class overview

`MgrMapCache` is the July 2025 replacement for `TTLCache`; the corpus explicitly says it has no prior file history and that `TTLCache` was a semantic predecessor in different source files. It provides a generic LFU cache and a `PyObject*` specialization for manager API results, restricted to an allow-list and controlled by `mgr_map_cache_enabled`. The establishing commit also requires read-only protection for cached Python results, runtime invalidation, safe Python reference-count handling, and hit/miss accounting. All current lines are attributed by blame to `403340bcf8c2122afff708519f176baa6b646fc1`; the function map reports no matched functions, so the full introduction diff and blame were used for every function.

## `MgrMapCache::MgrMapCache(uint16_t size)`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Construct the generic cache with the configured enable state and manager API allow-list, log its capacity, and register it as a configuration observer. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- The initial enabled state comes from `mgr_map_cache_enabled`. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)
- The cache observes configuration changes after construction. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced with the new cache in the sole corpus commit. No later change exists.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.cc:133`](../../ceph/src/mgr/MgrMapCache.cc:133) initializes `CacheImp` from the allow-list, capacity, and configuration; lines 135–136 log and register the observer. No ungrounded significant path is present.

### Test-writing notes
Test both initial configuration states and observer registration effects.

## `MgrMapCache<PyObject*>::MgrMapCache(uint16_t size)`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commits touched this function
**Divergence:** OK

### Intent
Construct the Python-specialized cache with the same configured enable state, capacity, allow-list, logging, and observer registration as the generic cache. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Python cache construction uses `mgr_map_cache_enabled`. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)
- The instance registers for runtime configuration updates. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced in the replacement commit; no subsequent evolution is recorded.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.cc:147-150`](../../ceph/src/mgr/MgrMapCache.cc:147) performs the configured initialization, logging, and registration. No ungrounded path.

### Test-writing notes
Verify that the specialization follows the same enable and allow-list initialization contract.

## `__anonbb8f163e0102()`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Compare two cache entries by their per-entry hit counts so insertion can select the least-used entry. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Eviction ordering is ascending by atomic hit count. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced as the comparator in the LFU insertion path.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.cc:119-122`](../../ceph/src/mgr/MgrMapCache.cc:119) loads both counters and returns the lower-count relation. No unexplained behavior.

### Test-writing notes
Test ties and distinct hit counts; tie winner is not historically specified.

## `__anonbb8f163e0202()`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Invoke the pending-call callback that decrements a Python reference. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- The callback decrements the object reference on the Python pending-call path. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced inside the Python replacement/eviction cleanup helper.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.cc:192-194`](../../ceph/src/mgr/MgrMapCache.cc:192) invokes `Py_DECREF` and returns zero. No ungrounded behavior beyond the callback mechanism explicitly described by the implementation commit.

### Test-writing notes
Test cleanup for replaced and evicted objects.

## `__anonbb8f163e0302()`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Run the fallback pending-call cleanup callback while ensuring Python thread state, then release the reference. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Fallback cleanup acquires and releases Python thread state around `Py_DECREF`. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced solely as the `Py_AddPendingCall` failure fallback.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.cc:193-196`](../../ceph/src/mgr/MgrMapCache.cc:193) ensures thread state before decrementing and releases it afterward. No ungrounded path.

### Test-writing notes
Exercise pending-call failure if the test harness can control it.

## `__anonbb8f163e0402()`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Return early when the object passed to deferred cleanup is null. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Null cleanup inputs produce no Python operation. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Null object is ignored. (Added: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced as the first guard in the deferred decref helper.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.cc:191-192`](../../ceph/src/mgr/MgrMapCache.cc:191) checks `obj` before scheduling cleanup. No stale defensive check is established by history.

### Test-writing notes
Test null cleanup input.

## `clear()` — `MgrMapCache<PyObject*>::clear`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Drain all Python entries, reset cache counters, and decref the drained objects while holding Python thread state. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Cache entries are removed and counters reset during a clear. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)
- Python references are released with Python thread state held. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Empty cache returns without acquiring Python thread state. (Added: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced as the Python-safe override of generic clearing.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.cc:219-225`](../../ceph/src/mgr/MgrMapCache.cc:219) drains and returns for empty output, otherwise acquires thread state, decrefs each object, and releases it. The drain reset is implemented at lines 51–58.

### Test-writing notes
Verify both empty and populated clearing, including reference counts.

## `drain(std::vector<Value>& out)`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Move all cached values into an output vector, clear storage, and reset hit/miss counters under the cache lock. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Extraction of all entries and counter reset occur under exclusive locking. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced to support Python-safe clear and destruction.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.cc:51-58`](../../ceph/src/mgr/MgrMapCache.cc:51) reserves, copies values, clears the map, and resets counters under `unique_lock`. No ungrounded behavior.

### Test-writing notes
Verify output receives every value and counters become zero.

## `erase(std::string_view key)` — `MgrMapCache<PyObject*>::erase`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Invalidate an allowed Python cache entry and defer its decref to Python's pending-call mechanism. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`; the commit also documents runtime cache flushing.)

### Invariants and contracts
- Non-cacheable keys are not removed. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)
- Removal does not directly decref outside the Python-safe deferred path. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Unknown/missing entries return without further action. (Added: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced with runtime individual cache invalidation. The implementation logs hit/miss totals after successful extraction.

### Deferred / known incomplete
The return value of `Py_AddPendingCall` is ignored at [`ceph/src/mgr/MgrMapCache.cc:212`](../../ceph/src/mgr/MgrMapCache.cc:212); the corpus does not explain this path. This is UNGROUNDED behavior, not a DIVERGED finding because no commit establishes a required failure fallback for `erase`.

### Implementation critique
SATISFIES — lines 207–210 reject non-cacheable and missing keys; lines 210–212 extract and defer decref. UNGROUNDED — line 212 has no failure handling, unlike the insertion helper at lines 192–196; no history establishes whether that asymmetry is intentional.

### Test-writing notes
Test non-cacheable, missing, and successful invalidation; separately consider pending-call failure.

## `erase(std::string_view key)` — `LFUCache<Value>::erase`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Remove an existing generic entry under exclusive locking and report whether removal occurred. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Map mutation is protected by the unique lock. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Missing key returns false. (Added: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced as the generic primitive; the public generic wrapper discards its result.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:115-120`](../../ceph/src/mgr/MgrMapCache.h:115) locks, checks absence, erases, and returns the corresponding boolean. No ungrounded behavior.

### Test-writing notes
Test absent and present keys and concurrent safety where applicable.

## `extract(std::string_view k, Value* out)`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Atomically obtain and remove a cached value under exclusive locking, returning success only when the key exists. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Output assignment and entry removal occur while holding the exclusive lock. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Missing key returns false and does not assign output. (Added: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced for safe ownership transfer and Python cleanup.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.cc:41-47`](../../ceph/src/mgr/MgrMapCache.cc:41) locks, checks, assigns, erases, and returns the documented result.

### Test-writing notes
Verify output is unchanged on a miss.

## `get(std::string_view k)` — `LFUCache<Value>::get`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Return an enabled cache entry, count a hit, and throw when the cache is disabled or the key is absent. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Successful retrieval increments both the entry and aggregate hit counts. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)
- Disabled and missing retrievals do not return a cached value. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Disabled cache throws `std::out_of_range("cache disabled")`. (Added: `403340bcf8c2122afff708519f176baa6b646fc1`.)
- Missing key throws `std::out_of_range` containing the key. (Added: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced as the exception-based generic retrieval API.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.cc:61-70`](../../ceph/src/mgr/MgrMapCache.cc:61) enforces both error paths, updates entry and aggregate hit counts, and returns the value under a shared lock.

### Test-writing notes
Test disabled, missing, and successful retrieval separately.

## `get(std::string_view key)` — `MgrMapCache<PyObject*>::get`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Return a retained Python cache result only when enabled, cacheable, and called with the GIL; misses return null and count as misses. Cached results are retained under the lock to prevent erase from dropping the final reference. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Disabled, non-cacheable, or non-GIL calls return null. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)
- A hit increments the Python object's reference count while the shared lock is held. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)
- Hits and misses update cache accounting. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Absent entry returns null and records a miss. (Added: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced as the GIL-aware replacement for Python API cache reads, with read-only output protection supplied by surrounding manager code.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.cc:158-173`](../../ceph/src/mgr/MgrMapCache.cc:158) enforces enable, allow-list, and GIL checks; records misses; performs `Py_INCREF` under lock; and records hits. No DIVERGED finding is warranted.

### Test-writing notes
Test all three preconditions, misses, reference retention, and hit counters.

## `get_hits() const`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Read the aggregate hit counter atomically. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- The returned value is an atomic snapshot of aggregate hits. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced for cache metrics and logging.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:138-140`](../../ceph/src/mgr/MgrMapCache.h:138) returns `hits.load()`.

### Test-writing notes
Verify reset after clear.

## `get_misses() const`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Read the aggregate miss counter atomically. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- The returned value is an atomic snapshot of aggregate misses. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced for cache metrics and logging.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:142-144`](../../ceph/src/mgr/MgrMapCache.h:142) returns `misses.load()`.

### Test-writing notes
Verify reset after clear.

## `handle_conf_change(...)` — generic

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Apply changes to `mgr_map_cache_enabled` by updating cache enablement. Disabling clears the cache. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Unrelated configuration changes do not alter cache state. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)
- Disabling invokes the cache clear behavior. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced as the generic configuration observer callback.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.cc:140-144`](../../ceph/src/mgr/MgrMapCache.cc:140) filters on the tracked key and delegates to `set_enabled`; [`ceph/src/mgr/MgrMapCache.h:396-400`](../../ceph/src/mgr/MgrMapCache.h:396) clears on disable.

### Test-writing notes
Test unrelated and enable/disable changes.

## `handle_conf_change(...)` — Python specialization

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Apply runtime changes to `mgr_map_cache_enabled` using the Python-safe enable/clear behavior. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Only the tracked enable option changes cache state. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)
- Disabling releases Python entries through the specialization's clear path. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced as the Python-specific observer callback.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.cc:229-233`](../../ceph/src/mgr/MgrMapCache.cc:229) filters the tracked key and calls `set_enabled`; virtual dispatch reaches Python `clear`.

### Test-writing notes
Verify disabling releases cached Python objects.

## `insert(std::string_view key, Value value)` — `LFUCache<Value>::insert`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Reject disabled or non-cacheable writes, recheck enablement under the write lock, replace an existing value, or insert a new value while counting a miss and evicting the least-used entry at capacity. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Writes are accepted only when enabled and the key is allowed. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)
- Capacity is enforced by evicting the minimum-hit entry before a new insertion. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)
- Replacements preserve the key and return the old value through `InsertRes`. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Disabled or non-cacheable writes return `InsertRes{false}`. (Added: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced the LFU write path with a lock-time enable recheck, replacement/eviction ownership transfer, and lazy key allocation.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.cc:93-128`](../../ceph/src/mgr/MgrMapCache.cc:93) enforces prechecks, lock-time recheck, replacement, miss accounting, minimum-hit eviction, capacity, and insertion. The `!cache_data.empty()` guard is a documented safety condition in the implementation; it is not stale according to this corpus.

### Test-writing notes
Test disabled races, replacement, zero capacity, eviction ties, and miss accounting.

## `insert(std::string_view key, PyObject* value)` — Python specialization

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Accept only enabled, allowed, GIL-held writes; retain the inserted object; undo that retain if the cache rejects the write; and defer decrefs for replaced or evicted objects. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Python reference ownership is balanced for insertion, replacement, eviction, and rejection. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)
- Python operations requiring interpreter state are performed through the GIL/pending-call mechanisms. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Disabled, non-cacheable, or non-GIL writes return without retaining the value. (Added: `403340bcf8c2122afff708519f176baa6b646fc1`.)
- A disable race causes the temporary `Py_INCREF` to be undone. (Added: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced with explicit reference-count ownership transfer and logging. The helper falls back to `PyGILState_Ensure` when pending-call scheduling fails.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.cc:176-199`](../../ceph/src/mgr/MgrMapCache.cc:176) enforces preconditions, balances rejected references, and schedules replacement/eviction decrefs with a fallback. No DIVERGED finding is supported.

### Test-writing notes
Test GIL absence, rejection during disable race, replacement, eviction, and pending-call fallback.

## `try_get(std::string_view k, Value* out, bool count_hit)` — LFU

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Attempt non-throwing retrieval under a shared lock; optionally count a hit or miss. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- A miss returns false; a hit copies the value and returns true. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)
- `count_hit=false` suppresses both aggregate and per-entry hit/miss accounting. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Missing key returns false without writing output. (Added: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced as the no-exception generic lookup primitive.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.cc:74-88`](../../ceph/src/mgr/MgrMapCache.cc:74) implements the miss, optional counting, output assignment, and success result under a shared lock.

### Test-writing notes
Test both values of `count_hit` on hits and misses.

## `try_get(...)` — generic `MgrMapCache` forwarding wrapper

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Expose the generic LFU non-throwing lookup through `MgrMapCache`. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Forwarding preserves lookup result and `count_hit`. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Inherits LFU miss behavior. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced as a thin public wrapper.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:158-160`](../../ceph/src/mgr/MgrMapCache.h:158) forwards all arguments directly. No ungrounded behavior.

### Test-writing notes
Covered by LFU lookup tests plus a wrapper smoke test.

## `~LFUCache()`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Provide polymorphic destruction for cache implementations. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Destruction is virtual. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced as a default virtual destructor.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:76`](../../ceph/src/mgr/MgrMapCache.h:76) declares a virtual default destructor.

### Test-writing notes
Test destruction through the base type where relevant.

## `~MgrMapCache()` — generic

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Unregister the generic cache from configuration observation before destruction. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- A destroyed cache is not left registered as an observer. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced with observer registration.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.cc:35-38`](../../ceph/src/mgr/MgrMapCache.cc:35) removes the observer.

### Test-writing notes
Verify observer deregistration during destruction.

## `~MgrMapCache()` — Python specialization

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Unregister the observer and clear the Python cache so retained objects are released during destruction. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Observer removal precedes destruction. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)
- Cached Python references are released through `clear`. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced as the Python-specific cleanup extension.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.cc:153-155`](../../ceph/src/mgr/MgrMapCache.cc:153) removes the observer and invokes the Python-safe clear path.

### Test-writing notes
Verify destruction releases all cached references.

## `Entry()`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Default-construct a cache entry and its zero hit count. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- New entries start with zero per-entry hits. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced as the default entry constructor.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:45`](../../ceph/src/mgr/MgrMapCache.h:45) defaults the value and atomic counter.

### Test-writing notes
Verify zero initial hit count.

## `Entry(Value v)`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Move a value into a new entry with zero hits. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Constructed entries own the supplied value and begin with zero hits. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced as the insertion entry constructor.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:46`](../../ceph/src/mgr/MgrMapCache.h:46) moves `v` and initializes `hits(0)`.

### Test-writing notes
Verify move and counter initialization.

## `Entry(const Entry& o)`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Copy an entry's value and snapshot its hit count. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Copying preserves the current hit-count value. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced to make entries usable in container operations despite atomic hits.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:47`](../../ceph/src/mgr/MgrMapCache.h:47) copies the value and loads the counter.

### Test-writing notes
Verify copied hit count is a snapshot.

## `Entry(Entry&& o)`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Move an entry's value while snapshotting its hit count. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Moving preserves the source hit count in the destination snapshot. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced for moving entries into optional eviction/replacement results.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:48`](../../ceph/src/mgr/MgrMapCache.h:48) moves the value and loads the hit count.

### Test-writing notes
Verify moved values and hit-count snapshot behavior.

## `LFUCache(...)`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Initialize allowed keys, capacity, and enabled state for an LFU cache. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Allowed keys, capacity, and initial enable state are stored for subsequent operations. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced as the generic cache foundation.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:72-75`](../../ceph/src/mgr/MgrMapCache.h:72) initializes all three constructor inputs. No unexplained behavior.

### Test-writing notes
Test custom allow-list, capacity, and disabled initialization.

## `can_read_cache(std::string_view key)`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Report whether a key is enabled, allowed, and already present. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Read eligibility requires all three conditions. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Added explicitly as a read-side cache guard.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:98-100`](../../ceph/src/mgr/MgrMapCache.h:98) combines enable, allow-list, and existence checks. No ungrounded path.

### Test-writing notes
Test each false condition independently.

## `can_write_cache(std::string_view key)`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Report whether a key is enabled and allowed for insertion. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Write eligibility does not require prior existence. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Disabled or disallowed keys return false. (Added: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Added with the explicit cache logic tightening described in the commit.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:102-104`](../../ceph/src/mgr/MgrMapCache.h:102) checks exactly enablement and cacheability. No ungrounded behavior.

### Test-writing notes
Test disabled, allowed, and disallowed keys.

## `clear()` — `LFUCache<Value>::clear`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Clear all entries and reset aggregate hit/miss counters under exclusive locking. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- No entries remain after clear and both aggregate counters are zero. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced as virtual base behavior; Python specialization overrides it to release references safely.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:126-131`](../../ceph/src/mgr/MgrMapCache.h:126) performs all operations under the unique lock. No ungrounded path.

### Test-writing notes
Verify entries and counters are reset.

## `clear()` — generic `MgrMapCache` wrapper

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Expose base cache clearing through the generic wrapper. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Clearing preserves base clear semantics. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced as a thin public wrapper.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:164`](../../ceph/src/mgr/MgrMapCache.h:164) calls `CacheImp::clear()`.

### Test-writing notes
Covered by base clear tests.

## `clear()` — Python `MgrMapCache` override

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Clear Python entries and release references under Python thread state while resetting cache accounting. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Python decrefs occur with interpreter state held. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Empty cache returns without Python state acquisition. (Added: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced as Python-safe override.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.cc:219-225`](../../ceph/src/mgr/MgrMapCache.cc:219) implements the contract; base `drain` resets counters at lines 51–58.

### Test-writing notes
Test empty and populated cases.

## `exists(std::string_view key)`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Test presence of a key under a shared lock. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Presence checks do not mutate cache state. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Missing keys return false. (Added: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced to support `can_read_cache`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:133-136`](../../ceph/src/mgr/MgrMapCache.h:133) performs a shared-locked lookup and boolean result.

### Test-writing notes
Test present and absent keys.

## `extract(...)` — generic wrapper

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Expose the base atomic extract operation. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Forwarding preserves extraction and ownership-transfer semantics. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Inherits false on a missing key. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced as a thin wrapper.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:162`](../../ceph/src/mgr/MgrMapCache.h:162) forwards to `CacheImp::extract`.

### Test-writing notes
Covered by base extraction tests.

## `get_tracked_keys() const` — generic

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Declare `mgr_map_cache_enabled` as the configuration option observed by the generic cache. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- The tracked set contains the cache enable option. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced with runtime toggling.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:166`](../../ceph/src/mgr/MgrMapCache.h:166) returns exactly the required option.

### Test-writing notes
Verify tracked-key declaration.

## `get_tracked_keys() const` — Python specialization

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Declare the same cache enable option for Python cache observation. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- The Python specialization tracks `mgr_map_cache_enabled`. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced with the Python-specific observer.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:187`](../../ceph/src/mgr/MgrMapCache.h:187) returns the required option.

### Test-writing notes
Verify tracked-key declaration.

## `insert(...)` — generic wrapper

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Expose generic insertion while discarding the internal ownership result. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Base insertion still enforces enablement, allow-list, capacity, and LFU eviction. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Rejected writes are silently represented by the void API. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced as the generic public convenience API.

### Deferred / known incomplete
Discarding `InsertRes` is observable but not explained separately in the commit message; this is UNGROUNDED API behavior, not DIVERGED.

### Implementation critique
UNGROUNDED — [`ceph/src/mgr/MgrMapCache.h:161`](../../ceph/src/mgr/MgrMapCache.h:161) passes `v` as an lvalue to the base insertion and discards the result. The history establishes the base semantics but does not explain this wrapper's copy behavior or result suppression.

### Test-writing notes
Test rejected writes and verify replacement/eviction still occur despite the void wrapper.

## `insert(...)` — Python specialization declaration

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Expose Python-safe insertion with GIL and reference ownership rules. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Python callers use the specialized insertion implementation rather than the generic one. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Inherits specialized precondition failures. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced as the specialization declaration; implementation is in the source file.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:182`](../../ceph/src/mgr/MgrMapCache.h:182) declares the specialized method, whose implementation is assessed above at lines 176–204.

### Test-writing notes
Use Python-object ownership tests.

## `invalidate(std::string_view key)`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Provide a named invalidation operation that delegates to Python-safe erase. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Invalidation has the same key filtering and deferred-decref behavior as erase. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Inherits erase's no-op behavior for invalid or missing keys. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced for explicit cache-flush API terminology.

### Deferred / known incomplete
None beyond the ungrounded pending-call failure handling documented under Python erase.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:183-185`](../../ceph/src/mgr/MgrMapCache.h:183) delegates directly to `erase`, preserving its contract.

### Test-writing notes
Test invalidation as the public alias of erase.

## `is_cacheable(std::string_view key)`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Determine whether a key belongs to the configured manager API allow-list without allocating a string. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Only allow-listed keys are cacheable. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Non-allow-listed keys return false. (Added: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced with transparent string-view lookup and cache key restriction.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:94-96`](../../ceph/src/mgr/MgrMapCache.h:94) performs the transparent allow-list lookup. No ungrounded behavior.

### Test-writing notes
Test every configured key and an unknown key.

## `is_enabled() const`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Read the runtime enable flag atomically. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Enablement reads are safe across configuration updates. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced for runtime toggling.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:85-87`](../../ceph/src/mgr/MgrMapCache.h:85) uses `enabled.load()`.

### Test-writing notes
Test transitions through `set_enabled`.

## `mark_hit()`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Increment aggregate hits and the hit performance counter when available. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Hit metrics are incremented without dereferencing a null performance counter. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- A null performance counter skips the optional metric update. (Added: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
The introduction commit explicitly added guarded perf-counter increments and used this helper in read paths.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:65-69`](../../ceph/src/mgr/MgrMapCache.h:65) increments the atomic aggregate counter and guards `perfcounter` before incrementing.

### Test-writing notes
Test with and without a performance counter.

## `mark_miss()`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Increment aggregate misses and the miss performance counter when available. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Miss metrics are incremented without dereferencing a null performance counter. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- A null performance counter skips the optional metric update. (Added: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced with guarded cache metrics.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:59-63`](../../ceph/src/mgr/MgrMapCache.h:59) increments misses and checks `perfcounter` before use.

### Test-writing notes
Test with and without a performance counter.

## `operator()(std::string_view)`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Hash a string view for transparent unordered-container lookup. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Equivalent string-view contents produce the standard string-view hash. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced to avoid constructing temporary strings for lookup.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:32-36`](../../ceph/src/mgr/MgrMapCache.h:32) delegates to `std::hash<std::string_view>` and is `noexcept`.

### Test-writing notes
Test equivalent string and string-view lookups.

## `set_enabled(bool e)`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Atomically set cache enablement and clear all entries when disabling. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Disabled caches do not retain stale entries. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced as the runtime-toggle implementation and used by both observer callbacks.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:78-82`](../../ceph/src/mgr/MgrMapCache.h:78) stores the flag and calls virtual `clear()` when false.

### Test-writing notes
Test disable clears data and re-enable starts empty.

## `size() const`

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Return the number of stored entries under a shared lock. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- The size snapshot is obtained without racing map mutation. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced as a cache inspection helper.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:89-92`](../../ceph/src/mgr/MgrMapCache.h:89) takes a shared lock and returns `cache_data.size()`.

### Test-writing notes
Test size after insert, erase, and clear.

## `StringViewHash` constructor / type initialization

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Provide the transparent-hash type marker needed for heterogeneous lookup. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- `is_transparent` is present for heterogeneous unordered lookup. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Introduced with `StringViewHash`; ctags lists the type initialization as a function-like entry.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:33-36`](../../ceph/src/mgr/MgrMapCache.h:33) provides the marker and hash operation. No callable constructor body is present in the source.

### Test-writing notes
The ctags entry is a type-related entry rather than a separately defined callable.

## `MgrMapCache(uint16_t sz = UINT16_MAX)` — generic declaration

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Declare the generic cache constructor with a default maximum capacity. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- The declaration exposes the generic constructor and default capacity. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
The header declaration accompanies the source definition.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:156`](../../ceph/src/mgr/MgrMapCache.h:156) declares the constructor implemented at [`ceph/src/mgr/MgrMapCache.cc:133`](../../ceph/src/mgr/MgrMapCache.cc:133).

### Test-writing notes
None beyond the constructor tests above.

## `~MgrMapCache()` — generic declaration

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Declare generic destruction for the configuration-observing cache. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- The declaration matches the observer-removing destructor. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Header declaration accompanies the source definition.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:157`](../../ceph/src/mgr/MgrMapCache.h:157) declares the destructor implemented at [`ceph/src/mgr/MgrMapCache.cc:35`](../../ceph/src/mgr/MgrMapCache.cc:35).

### Test-writing notes
None.

## `MgrMapCache(uint16_t size = UINT16_MAX)` — Python declaration

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Declare the Python specialization constructor with a default maximum capacity. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- The declaration selects the Python-specialized constructor. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Header declaration accompanies the source definition.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:176`](../../ceph/src/mgr/MgrMapCache.h:176) declares the implementation at [`ceph/src/mgr/MgrMapCache.cc:147`](../../ceph/src/mgr/MgrMapCache.cc:147).

### Test-writing notes
None beyond specialization construction tests.

## `~MgrMapCache()` — Python declaration

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Declare Python-specialized destruction and reference cleanup. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- The declaration matches the Python-safe destructor. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Header declaration accompanies the source definition.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:177`](../../ceph/src/mgr/MgrMapCache.h:177) declares the destructor implemented at [`ceph/src/mgr/MgrMapCache.cc:153`](../../ceph/src/mgr/MgrMapCache.cc:153).

### Test-writing notes
None.

## `try_get(...)` — deleted Python overload

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Prevent the generic non-GIL-aware lookup API from being used for `PyObject*`. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Python callers must use the GIL-aware `get` path. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Calls to this overload are compile-time rejected. (Added: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
The specialization deletes the inherited try-get overload as part of the Python safety boundary.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:178`](../../ceph/src/mgr/MgrMapCache.h:178) explicitly marks the overload deleted.

### Test-writing notes
Verify the deleted API is not callable.

## `drain(std::vector<Value>& out)` — declaration

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Declare the locked value-drain primitive used by clear. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- The declaration is `noexcept` and exposes bulk extraction. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Header declaration accompanies the source definition.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:124`](../../ceph/src/mgr/MgrMapCache.h:124) matches the implementation at [`ceph/src/mgr/MgrMapCache.cc:51`](../../ceph/src/mgr/MgrMapCache.cc:51).

### Test-writing notes
None.

## `extract(std::string_view k, Value* out)` — declaration

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Declare the no-throw atomic extraction primitive. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- The declaration preserves `noexcept` ownership transfer. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Header declaration accompanies the source definition.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:123`](../../ceph/src/mgr/MgrMapCache.h:123) matches the implementation at [`ceph/src/mgr/MgrMapCache.cc:41`](../../ceph/src/mgr/MgrMapCache.cc:41).

### Test-writing notes
None.

## `erase(std::string_view k)` — generic wrapper declaration

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Expose a void generic erase wrapper that removes an entry through extraction. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- The wrapper does not throw and removes at most the requested key. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Missing keys are ignored. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Introduced as the generic public convenience wrapper.

### Deferred / known incomplete
None.

### Implementation critique
UNGROUNDED — [`ceph/src/mgr/MgrMapCache.h:163`](../../ceph/src/mgr/MgrMapCache.h:163) discards extraction success and constructs a default `Value`; the history does not separately explain this wrapper's ownership behavior.

### Test-writing notes
Test the wrapper with present and missing keys.

## `erase(std::string_view key)` — Python declaration

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Declare Python-safe erase/invalidation. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- The declaration is `noexcept` and selects deferred Python cleanup. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Header declaration accompanies the specialization definition.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:180`](../../ceph/src/mgr/MgrMapCache.h:180) declares the implementation at [`ceph/src/mgr/MgrMapCache.cc:207`](../../ceph/src/mgr/MgrMapCache.cc:207).

### Test-writing notes
None.

## `extract(std::string_view k, Value* out)` — generic declaration

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Declare the generic public extraction wrapper. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- Forwarding preserves the base extraction result. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Missing keys return false. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Header declaration accompanies the inline wrapper.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:162`](../../ceph/src/mgr/MgrMapCache.h:162) forwards to the base primitive.

### Test-writing notes
None.

## `get(std::string_view key)` — Python declaration

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Declare the GIL-aware Python retrieval API. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- The Python API is separate from the generic copy-out lookup. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- None documented.

### Evolution summary
Header declaration accompanies the specialized source implementation.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:179`](../../ceph/src/mgr/MgrMapCache.h:179) declares the implementation at [`ceph/src/mgr/MgrMapCache.cc:158`](../../ceph/src/mgr/MgrMapCache.cc:158).

### Test-writing notes
None.

## `get(std::string_view k)` — generic declaration

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Declare the exception-based generic retrieval API. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- The declaration exposes the generic value-returning lookup. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Inherits disabled and missing-key exceptions from the source implementation. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Header declaration accompanies the source implementation.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:146`](../../ceph/src/mgr/MgrMapCache.h:146) matches [`ceph/src/mgr/MgrMapCache.cc:61`](../../ceph/src/mgr/MgrMapCache.cc:61).

### Test-writing notes
None.

## `try_get(...)` — deleted-specialization declaration

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Declare the disabled Python `try_get` overload. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- The deleted overload remains unavailable to Python-specialized callers. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Compile-time use is rejected. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Header entry records the specialization's API restriction.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:178`](../../ceph/src/mgr/MgrMapCache.h:178) marks the overload deleted.

### Test-writing notes
None.

## `try_get(...)` — generic declaration

**Introduced:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with MgrMapCache and protect api with readonly
**Last modified:** `403340bcf8c2122afff708519f176baa6b646fc1` — mgr: replace TTLCache with readonly
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Declare the generic no-throw lookup. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Invariants and contracts
- The declaration preserves the optional hit-count parameter. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Error conditions
- Missing keys return false through the source implementation. (Established: `403340bcf8c2122afff708519f176baa6b646fc1`.)

### Evolution summary
Header declaration accompanies the source definition.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — [`ceph/src/mgr/MgrMapCache.h:112`](../../ceph/src/mgr/MgrMapCache.h:112) matches [`ceph/src/mgr/MgrMapCache.cc:74`](../../ceph/src/mgr/MgrMapCache.cc:74).

### Test-writing notes
None.

## Self-check

- [x] Read every non-comment commit in `commits.txt`: 1 commit, `403340bcf8c2122afff708519f176baa6b646fc1`, date range 2025-07-17 to 2025-07-17; HEAD metadata is `8681fa6ebac230f86eb445bf57095c63e7f1abcc`.
- [x] Read `functions.txt` in full and assessed every listed function entry; duplicate overloads/specializations are separately covered above.
- [x] Read the sole full scoped diff and its complete commit subject/body; `commit_function_map.txt` reports no matched functions, so the introduction diff and blame were used directly.
- [x] Used `blame.txt`; all current implementation lines are attributed to `403340bcf8c2122afff708519f176baa6b646fc1`.
- [x] Every invariant and error condition cites `403340bcf8c2122afff708519f176baa6b646fc1`.
- [x] Every function section contains an Implementation critique with current-source line references.
- [x] No DIVERGED flag is set without a specific contradictory commit and line; the available history supports OK rather than a divergence.
- [x] Flagged the unexplained pending-call failure path in Python `erase` and the unexplained copy/result-discard behavior in the generic wrapper as UNGROUNDED.
- [x] No OVERCAUTIOUS finding is supported: the corpus contains no later fix that makes an existing defensive check stale.
