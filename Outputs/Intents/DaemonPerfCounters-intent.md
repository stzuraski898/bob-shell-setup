# DaemonPerfCounters History Assessment

## Assessment scope

- Corpus: `/home/szuraski/BobOutput/Object History/v4/DaemonPerfCounters/`
- Pre-extraction history corpus: `/home/szuraski/BobOutput/Object History/v4/DaemonState/`
- Current implementation assessed: [`src/mgr/DaemonPerfCounters.cc`](src/mgr/DaemonPerfCounters.cc) and [`src/mgr/DaemonPerfCounters.h`](src/mgr/DaemonPerfCounters.h)
- Commit count: **1 non-merge commit in DaemonPerfCounters corpus** (`35f6dd06dd0b`, 2025-08-14 — the file extraction from `DaemonState`). Pre-extraction behavioral history comprises **85 non-merge commits in DaemonState corpus**, spanning 2016-06-30 through 2025-10-02.
- Corpus HEAD: `8681fa6ebac230f86eb445bf57095c63e7f1abcc`.
- Commit date range (combined): **2016-06-30 through 2025-10-02**.
- Function inventory: **8 ctags entries** (4 unique functions × .cc definition + .h declaration).
- All 1 DaemonPerfCounters corpus diffs and all DaemonState diffs relevant to `DaemonPerfCounters` methods were read. The following SHAs directly modified `DaemonPerfCounters` code: `ac30e6cee2b2`, `d9dfb436ea58`, `9501bfdd7114`, `a46690c6230b`, `750ad8340c82`, `dc415f1ae09a`, `156c941ad0d2`, `1164ef2f32d8`, `72883956c26f`, `5b6037aeb43a`, `9b6aa95ff401`, `2d2982e74209`, `d2d4c7d3f865`, `35f6dd06dd0b`.

## Historical contracts

- `ac30e6cee2b2` (John Spray, 2016-06-30): Initial creation as `DaemonMetadata.cc`/`.h`. The class holds a reference to a shared `PerfCounterTypes &types`, owns `instances` and (then) a local `declared_types` set, and `update(MMgrReport*)` loads newly declared types into both `types` and `declared_types`, parses packed binary data for every declared type path, and stores the latest value in `instances[t_path]`. The LONGRUNAVG branch decoded `avgcount` and `avgcount2` but left a `// TODO: interface for insertion of avgs, add timestamp` comment indicating they were not yet stored. `instances[t_path].push(val)` was called unconditionally regardless of counter type. A `// TODO: handle badly encoded things without asserting out` comment noted that `DECODE_FINISH` would throw on bad input.
- `d9dfb436ea58` (John Spray, 2016-07-03): Rename `DaemonMetadata` → `DaemonState` throughout; class and file renamed to `DaemonState.cc`/`.h`. No behavioral change to `DaemonPerfCounters`.
- `9501bfdd7114` (John Spray, 2016-07-26): "mgr: store some counter history." Timestamps are now captured with `ceph_clock_now(g_ceph_context)` and passed to `push(utime_t, uint64_t)`. `PerfCounterInstance` switches from a single `current` value to a `boost::circular_buffer<DataPoint>(20)`. `clear()` is added inline in the header, clearing both `instances` and `declared_types`. The LONGRUNAVG avgcount/avgcount2 are still decoded but not stored (the `// TODO: interface for insertion of avgs` comment remains); both are decoded, but only `val` is passed to `push`.
- `a46690c6230b` (Sage Weil, 2017-03-10): "mgr/MgrClient: cope with disappearing perf_counters." `undeclare_types` handling is added: the `update` debug log now includes the undeclare count and type count, and a second loop removes paths from `declared_types` when the client reports that a counter has gone away.
- `750ad8340c82` (Adam C. Emerson, 2016-11-14): "common: Unskew clock." `ceph_clock_now(g_ceph_context)` → `ceph_clock_now()`. No behavioral change.
- `dc415f1ae09a` (John Spray, 2017-09-23): "mgr: store declared_types in MgrSession." Tracker: http://tracker.ceph.com/issues/21197. The `declared_types` field is removed from `DaemonPerfCounters` and migrated to `MgrSession::declared_types`. The `update` function now retrieves the session via `MgrSessionRef session(static_cast<MgrSession*>(report->get_connection()->get_priv()))` and redirects all `declared_types` reads and writes through the session. `clear()` in the header is simplified to clear only `instances` because `declared_types` is no longer owned by this class. The rationale is that multiple sessions from daemons with the same name (e.g. rgws) were causing one daemon's types to bleed into another's decode loop.
- `156c941ad0d2` (Adam C. Emerson, 2017-12-25): "mgr: Use unqualified encode/decode." `::decode(val, p)` → `decode(val, p)` for ADL namespace usage. No behavioral change.
- `1164ef2f32d8` (Boris Ranto, 2018-05-15): "mgr: Expose avgcount for long running avgs." `PerfCounterInstance` gains `AvgDataPoint` and `avg_buffer`; `push_avg(utime_t, uint64_t, uint64_t)` is added. `update` now eagerly inserts an instance on declaration: `instances.insert(pair<string, PerfCounterInstance>(t.path, PerfCounterInstance(t.type)))`. The LONGRUNAVG branch calls `instances.at(t_path).push_avg(now, val, avgcount)` and the non-LONGRUNAVG branch calls `instances.at(t_path).push(now, val)`. `avgcount2` is still decoded but not passed to `push_avg` (only `val` and `avgcount` are passed).
- `72883956c26f` (Kefu Chai, 2018-05-29): "mds,osd,mon,msg: use intrusive_ptr for holding Connection::priv." Session retrieval changes from `MgrSessionRef session(static_cast<MgrSession*>(report->get_connection()->get_priv()))` to the two-step `auto priv = report->get_connection()->get_priv(); auto session = static_cast<MgrSession*>(priv.get())`. This ensures the `intrusive_ptr` lifetime keeps the session alive for the duration of `update`.
- `5b6037aeb43a` (Mykola Golub, 2018-12-13): "mgr: fix crash due to multiple sessions from daemons with same name." Tracker: https://tracker.ceph.com/issues/36244. The eager `instances.insert` added by `1164ef2f32d8` on declaration is removed. Instead, a lazy find-or-insert is performed in the decode loop: `auto instances_it = instances.find(t_path)` with explicit check `if (instances_it == instances.end()) { instances_it = instances.insert({t_path, t.type}).first; }`. The comment states: "Always check the instance exists, as we don't prevent yet multiple sessions from daemons with the same name, and one session clearing stats created by another on open." This replaces `instances.at(t_path)` (which would throw `out_of_range` if another session had cleared the map) with iterator-based access.
- `9b6aa95ff401` (Kefu Chai, 2019-04-15): "mgr/DaemonState: pass const by reference." `update(MMgrReport *report)` → `update(const MMgrReport& report)`, all `report->` accesses become `report.`. No behavioral change.
- `2d2982e74209` (Max Kellermann, 2024-10-26): "mgr/DaemonState: add missing includes." Adds `#include "common/Clock.h"` and `#include "common/debug.h"` to make the translation unit self-contained. No behavioral change.
- `d2d4c7d3f865` (Max Kellermann, 2025-08-14): "mgr/DaemonState: forward-declare types from MMgrReport.h." Un-inlines `DaemonStateIndex` constructor and destructor; adds forward declarations `class PerfCounterType; class MMgrReport;` to `DaemonState.h` and moves `#include "messages/MMgrReport.h"` to `.cc`. As a prerequisite for the extraction, the constructor/destructor of `DaemonPerfCounters` must now be out-of-line since the header can no longer see `PerfCounterType`'s full definition.
- `35f6dd06dd0b` (Max Kellermann, 2025-08-14): "mgr/DaemonState: move PerfCounters classes to separate sources." The `DaemonPerfCounters` class and its `update`/`clear` implementations are extracted verbatim into new files `DaemonPerfCounters.h` and `DaemonPerfCounters.cc`. The constructor and destructor become explicit out-of-line definitions in the `.cc` file. No behavioral change; pure refactor to reduce header dependencies.

## Function assessments

### `DaemonPerfCounters` (constructor) — [`src/mgr/DaemonPerfCounters.cc:26`](src/mgr/DaemonPerfCounters.cc:26); declaration [`src/mgr/DaemonPerfCounters.h:37`](src/mgr/DaemonPerfCounters.h:37)
**Status: SATISFIES.**

**Intent and history.** `ac30e6cee2b2` established the constructor as taking a `PerfCounterTypes&` reference and initializing `types` with it. The constructor was originally inline in the header. `d2d4c7d3f865` required it to be out-of-line once the header dropped the full `MMgrReport.h` include (and thus the full `PerfCounterType` definition). `35f6dd06dd0b` placed the out-of-line definition in the new `.cc` file.

**Implementation critique.** [`DaemonPerfCounters.cc:26-28`](src/mgr/DaemonPerfCounters.cc:26): the constructor takes `PerfCounterTypes &types_` and member-initializes `types(types_)`. This exactly matches the established contract. The `explicit` keyword on the declaration (`DaemonPerfCounters.h:37`) prevents unintended implicit conversions, which is consistent with the single-argument constructor pattern. No unexplained paths.

### `~DaemonPerfCounters` (destructor) — [`src/mgr/DaemonPerfCounters.cc:30`](src/mgr/DaemonPerfCounters.cc:30); declaration [`src/mgr/DaemonPerfCounters.h:38`](src/mgr/DaemonPerfCounters.h:38)
**Status: SATISFIES.**

**Intent and history.** The destructor was implicitly defaulted when the class was first created (`ac30e6cee2b2`). `d2d4c7d3f865` made it explicitly out-of-line and declared `noexcept` as a prerequisite for moving the class to a header that forward-declares rather than includes `PerfCounterType`. `35f6dd06dd0b` placed the `= default` definition in the new `.cc` file.

**Implementation critique.** [`DaemonPerfCounters.cc:30`](src/mgr/DaemonPerfCounters.cc:30): `DaemonPerfCounters::~DaemonPerfCounters() noexcept = default;`. The `noexcept` qualifier matches the declaration at `DaemonPerfCounters.h:38`. The defaulted destructor correctly releases `instances` (the only owned container) and does not touch `types` (a reference, not an owner). No divergence.

### `update` — [`src/mgr/DaemonPerfCounters.cc:32`](src/mgr/DaemonPerfCounters.cc:32); declaration [`src/mgr/DaemonPerfCounters.h:42`](src/mgr/DaemonPerfCounters.h:42)
**Status: UNGROUNDED.**

**Intent and history.**
- `ac30e6cee2b2`: created as `update(MMgrReport*)`. Loads newly declared types into both shared `types` map and local `declared_types`. Decodes packed binary, iterating over `declared_types`. LONGRUNAVG branch decoded `avgcount`/`avgcount2` but only called `push(val)` (no timestamp, no avg storage).
- `9501bfdd7114`: timestamps added via `ceph_clock_now()`. `push(utime_t, uint64_t)` replaces `push(uint64_t)`. LONGRUNAVG avgcounts decoded but still not stored; only `push(now, val)` is called. `// TODO: interface for insertion of avgs` remains.
- `a46690c6230b`: `undeclare_types` loop added. Types the daemon has stopped reporting are erased from `declared_types`. The debug log now reports undeclare count and current type count.
- `dc415f1ae09a` (Fixes: tracker.ceph.com/issues/21197): `declared_types` migrated to `MgrSession`. Session retrieved via `report->get_connection()->get_priv()`. All type tracking (declare insert, undeclare erase, iteration) goes through `session->declared_types`. This fixes cross-session type bleed for same-named daemons (e.g. rgws).
- `156c941ad0d2`: `::decode` → `decode` (ADL). No behavioral change.
- `1164ef2f32d8`: `PerfCounterInstance` gains `push_avg`. Eager `instances.insert` on type declaration. LONGRUNAVG calls `instances.at(t_path).push_avg(now, val, avgcount)`; non-LONGRUNAVG calls `instances.at(t_path).push(now, val)`. `avgcount2` still decoded but not stored.
- `72883956c26f`: Session retrieval changed to two-step `get_priv()` → `static_cast<MgrSession*>(priv.get())` to keep the `intrusive_ptr` alive for the duration of the call.
- `5b6037aeb43a` (Fixes: tracker.ceph.com/issues/36244): Eager `instances.insert` on declare removed. Lazy find-or-insert replaces `instances.at(t_path)` in the decode loop to survive instances being cleared by a concurrent session. The invariant is documented in the code comment.
- `9b6aa95ff401`: `update(MMgrReport*)` → `update(const MMgrReport&)`. All field accesses updated to use `.` instead of `->`. No behavioral change.

**Invariants established:**
1. (`dc415f1ae09a`) `declared_types` is the caller's (session's) state; `update` must not own or permanently modify it beyond the session object obtained from `report.get_connection()->get_priv()`.
2. (`dc415f1ae09a`) The decode loop iterates `session->declared_types`, not a local copy, ensuring each session's decode is scoped to exactly the types that session reported.
3. (`5b6037aeb43a`) An instance may not exist at decode time even if its type path is in `session->declared_types` (because a concurrent session's `clear()` may have wiped `instances`). The code must lazily create the instance rather than using `at()`.
4. (`a46690c6230b`) `undeclare_types` must be processed before the decode loop; types that disappear are removed from the session's declared set.
5. (`9b6aa95ff401`) The `MMgrReport` argument is not modified; `const&` is the correct signature.

**Implementation critique.**

Lines 34–37 (debug log): SATISFIES. Reports `declare_types.size()`, `undeclare_types.size()`, `types.size()`, and `packed.length()`, consistent with `a46690c6230b`.

Lines 40–41 (session retrieval): SATISFIES. Two-step intrusive_ptr pattern from `72883956c26f` is present. `auto priv = report.get_connection()->get_priv()` followed by `auto session = static_cast<MgrSession*>(priv.get())`. `priv` stays in scope for the whole function, preserving the session lifetime.

Lines 44–47 (declare loop): SATISFIES. `types.insert(std::make_pair(t.path, t))` loads the type; `session->declared_types.insert(t.path)` tracks it per-session. Consistent with `dc415f1ae09a`. The `types` map is shared across all sessions (the `PerfCounterTypes &types` reference) and receives an unconditional insert; duplicate declarations silently no-op because `std::map::insert` does not overwrite existing keys. This is consistent with historical behavior since `ac30e6cee2b2`.

Lines 49–51 (undeclare loop): SATISFIES. Erases from `session->declared_types` as established by `a46690c6230b` and `dc415f1ae09a`. Note: the corresponding type is not erased from the shared `types` map, which is intentional — the shared type registry is not per-session.

Line 53: `const auto now = ceph_clock_now()` — SATISFIES. Clock snapshot before the decode loop, consistent with `750ad8340c82`.

Lines 56–57 (decode start): SATISFIES. `auto p = report.packed.cbegin()` and `DECODE_START(1, p)` match `9b6aa95ff401` (const reference access) and `156c941ad0d2` (version 1).

Lines 58–66 (lazy instance creation): SATISFIES. The `instances.find` + conditional `instances.insert` pattern with comment is exactly the fix from `5b6037aeb43a`, preventing `out_of_range` crashes when a concurrent session has cleared `instances`.

Lines 67–69 (local decode variables): SATISFIES. `uint64_t val = 0; uint64_t avgcount = 0; uint64_t avgcount2 = 0` match the original allocation in `ac30e6cee2b2`.

Line 71: `decode(val, p)` — SATISFIES. Unqualified `decode` per `156c941ad0d2`.

Lines 72–77 (LONGRUNAVG branch): **UNGROUNDED** at line 69 (`avgcount2`). `avgcount2` has been decoded since `ac30e6cee2b2` with the comment "TODO: interface for insertion of avgs". After `1164ef2f32d8` added `push_avg`, the signature is `push_avg(now, val, avgcount)` — `avgcount2` is decoded into a local at line 74 but is never passed to `push_avg` or otherwise used. This variable has been present since the initial commit and is not explained by any subsequent commit in the corpus. The TODO comment was removed by `1164ef2f32d8` when `push_avg` was added, but the variable itself was not removed and its intended use was never implemented. **This is an UNGROUNDED code path**: `avgcount2` is consumed from the wire protocol at line 74 (ensuring the byte stream stays in sync) but the decoded value is silently discarded. No commit explains what `avgcount2` was supposed to provide or when it might be used.

Line 76: `instances_it->second.push(now, val)` for the non-LONGRUNAVG branch — SATISFIES. Uses iterator-based access from `5b6037aeb43a` and passes timestamp from `9501bfdd7114`.

Line 80: `DECODE_FINISH(p)` — SATISFIES. The original "TODO: handle badly encoded things without asserting out" comment from `ac30e6cee2b2` was removed in `9501bfdd7114`. The current code will throw on decode overrun, which is the standard Ceph decode contract.

### `clear` — [`src/mgr/DaemonPerfCounters.cc:83`](src/mgr/DaemonPerfCounters.cc:83); declaration [`src/mgr/DaemonPerfCounters.h:44`](src/mgr/DaemonPerfCounters.h:44)
**Status: SATISFIES.**

**Intent and history.**
- `9501bfdd7114`: `clear()` added inline in the header. At that time it cleared both `instances` and `declared_types`, since both fields were owned by `DaemonPerfCounters`.
- `dc415f1ae09a`: `declared_types` was removed from `DaemonPerfCounters` (moved to `MgrSession`). Accordingly, `clear()` was updated to clear only `instances`; `declared_types.clear()` was removed. The `clear()` function is called by `DaemonServer::handle_open` when a new session opens for a daemon, resetting its counter history without touching session state.
- `35f6dd06dd0b`: `clear()` moved from inline header to `.cc` file. The implementation is identical.

**Implementation critique.** [`DaemonPerfCounters.cc:83-86`](src/mgr/DaemonPerfCounters.cc:83): `void DaemonPerfCounters::clear() { instances.clear(); }`. This is the correct post-`dc415f1ae09a` implementation. The removal of `declared_types.clear()` is grounded in `dc415f1ae09a`, which explains that `declared_types` is session state and is not owned by `DaemonPerfCounters`. Clearing only `instances` allows a new session to reset the counter history while the session's own `declared_types` continues to be managed by `MgrSession`. No divergence, no ungrounded paths.

**OVERCAUTIOUS note (not a divergence):** The declaration in [`DaemonPerfCounters.h:44`](src/mgr/DaemonPerfCounters.h:44) is a plain `void clear()` with no `noexcept` qualifier. Given that `std::map::clear()` is `noexcept`, the function could be declared `noexcept` without behavioral change. However, no commit established a `noexcept` contract for `clear()`, so the absence is not a divergence.

## Self-check

- **All commits read?** Yes. The single DaemonPerfCounters corpus commit (`35f6dd06dd0b`) was read in full. All 14 DaemonState commits that touch `DaemonPerfCounters` code (identified via blame attribution) were read: `ac30e6cee2b2`, `d9dfb436ea58`, `9501bfdd7114`, `a46690c6230b`, `750ad8340c82`, `dc415f1ae09a`, `156c941ad0d2`, `1164ef2f32d8`, `72883956c26f`, `5b6037aeb43a`, `9b6aa95ff401`, `2d2982e74209`, `d2d4c7d3f865`, `35f6dd06dd0b`.
- **Critique for every function?** Yes. All 8 ctags entries have sections: `DaemonPerfCounters` (constructor) ×2, `~DaemonPerfCounters` ×2, `update` ×2, `clear` ×2.
- **SHAs cited for every DIVERGED/UNGROUNDED flag?** Yes. The single UNGROUNDED finding (`avgcount2` in `update`) cites `ac30e6cee2b2` (origin) and `1164ef2f32d8` (when the TODO was cleared but the variable retained). There are no DIVERGED findings.
- **All ungrounded code paths flagged?** Yes. The `avgcount2` variable is the only path where a value is decoded from the wire but neither stored nor explained by any commit.
