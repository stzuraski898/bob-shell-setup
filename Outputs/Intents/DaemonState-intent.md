# DaemonState — Intent Artefact

**Corpus**: `BobOutput/Object History/v4/DaemonState/`  
**Collected at**: 2026-09-11T21:40:59Z  
**HEAD SHA**: `8681fa6ebac230f86eb445bf57095c63e7f1abcc`  
**Total commits**: 85 non-merge commits  
**Date range**: 2016-06-30 (`ac30e6cee2b2`) → 2025-10-02 (`c8c1019d1962`)  
**Rename chain**: `src/mgr/DaemonMetadata.{cc,h}` → `src/mgr/DaemonState.{cc,h}` at `d9dfb436ea58` (2016-07-03)

---

## Corpus Summary

### Files at HEAD
- `src/mgr/DaemonState.cc` — 387 lines (blame confirms through line 387)
- `src/mgr/DaemonState.h` — 295 lines (blame confirms through line 295)

### Notable structural events
| SHA | Date | Event |
|---|---|---|
| `ac30e6cee2b2` | 2016-06-30 | Initial creation as `DaemonMetadata.{cc,h}` |
| `d9dfb436ea58` | 2016-07-03 | Rename to `DaemonState.{cc,h}`; `DaemonKey` = `pair<entity_type_t,string>` |
| `b7c9561accef` | 2016-07-01 | Fix missing lock acquisition in insert/get_by_type/get_by_server/exists/get |
| `806f10847cef` | 2017-08-24 | Upgrade lock from `Mutex` to `RWLock`; add `with_daemons_by_server` template; fix tracker#21158 |
| `a22b256bad1f` | 2017-06-22 | `DaemonKey` becomes `pair<string,string>`; `get_by_type` → `get_by_service` |
| `f236b5e78338` | 2017-07-19 | Add per-`DaemonState` mutex |
| `38afbae02696` | 2018-06-05 | Introduce `DeviceState`; `_insert`/`_erase` maintain `devices` index |
| `8a2f4429b129` | 2018-10-18 | Split `insert`/`rm` into public+`_insert`/`_rm`; add `update_metadata` |
| `c52fc7b5d34f` | 2018-10-18 | `set_metadata` clears `devices` before reparsing |
| `5aac7eba36be` | 2019-09-29 | `DaemonKey` becomes a struct with `.type`/`.name` fields |
| `675606bf712e` | 2019-07-07 | Replace `RWLock` with `ceph::shared_mutex`/`ceph::mutex` |
| `7534737030b3` | 2019-11-27 | Add `cull_services`; fix tracker#(empty-service-daemon removal) |
| `35f6dd06dd0b` | 2025-08-14 | `PerfCounters` classes extracted to `DaemonPerfCounters.{cc,h}` |
| `b4304d521f61` | 2025-07-31 | `with_daemons_by_server` copies `by_server` before invoking callback; fix tracker#72337 |

---

## Class: `DaemonState`

`DaemonState` holds all manager-side knowledge about one daemon instance: its identity key, hostname, metadata map, derived device maps, ephemeral service-daemon state, running config, lazy-decoded config defaults, perf counters, and health metrics.

### `DaemonState::DaemonState` (constructor)

**File**: `src/mgr/DaemonState.cc:41` / `src/mgr/DaemonState.h:83`  
**Establishing commit**: `ac30e6cee2b2` (2016-06-30) — initial creation as `DaemonMetadata`  
**Last touched**: `e9abc5ce0bb7` (2025-08-14) — un-inlined to .cc to allow forward-declaring `PerfCounterTypes`

**Intent**: Construct a `DaemonState` by forwarding the shared `PerfCounterTypes` reference into `DaemonPerfCounters`. The constructor has no other observable effects; all other fields are default-initialised.

**Invariants**:
- `perf_counters` holds a reference to the index-level `DaemonStateIndex::types` map (established `ac30e6cee2b2`).

**Implementation critique** (`.cc:41–46`):
- Lines 41–44: constructor body is correct.
- Line 46: `~DaemonState() noexcept = default;` — correct; nothing unusual.
- STATUS: **OK**

---

### `DaemonState::~DaemonState`

**File**: `src/mgr/DaemonState.cc:46` / `src/mgr/DaemonState.h:84`  
**Establishing commit**: `e9abc5ce0bb7` (2025-08-14)

**Intent**: Trivial defaulted destructor, un-inlined to keep forward declarations working after `PerfCounterTypes` was moved out of this header.

**Implementation critique**: No logic; correct.  
STATUS: **OK**

---

### `DaemonState::set_metadata` (DaemonState member — `DaemonState.cc:179`)

**File**: `src/mgr/DaemonState.cc:179` / `src/mgr/DaemonState.h:86`  
**Establishing commit**: `67b5d3e343c5` (2018-06-05) — initial inline version parsing `device_ids`  
**Key evolution**:
- `7add8da7b00a` (2018-06-06) — skip blank device IDs
- `6b6fe52aacf6` (2018-06-06) — `devids` set replaced by `devices` map (id→devname)
- `c52fc7b5d34f` (2018-10-18) — `devices.clear()` added at top to fix stale data
- `2c0fd7d86827` (2019-12-15) — adds `devices_bypath` and parses `device_paths` metadata key
- `ff6b3997caa4` (2019-09-18) — adds `hostname` update from metadata; fix tracker#40871
- `bb09a1d7e2c5` (2021-10-17) — refactor internal string-map construction
- `95a96cffc300` (2021-12-19) — rewrite using `for_each_pair` for clarity
- `6e1a6f0aa1fa` (2021-12-19) — moved from header into .cc

**Intent**: Atomically replace all device-derived state on a `DaemonState`.  
1. Clear `devices` and `devices_bypath` maps first (invariant: no stale device→name mapping survives a metadata refresh).  
2. Copy the raw `m` map into `metadata`.  
3. Parse `device_ids` as a comma/semicolon-separated `devname=id` map; for each pair with a non-empty id, record `devices[id] = devname`.  
4. Simultaneously parse `device_paths` as `devname=path`; for each device that also has a path, record `devices_bypath[id] = path`.  
5. Update `hostname` from `m["hostname"]` if present (tracker#40871: hostname must always be refreshed).  
**Caller contract**: Must hold `state->lock` (ceph::mutex) before calling. Established by `1c2bc53df73d` rename of `get_config_defaults` → `_get_config_defaults` to flag the lock requirement; `update_metadata` acquires `state->lock` via `std::lock_guard l2{state->lock}` before calling this.

**Invariants**:
- `devices.clear()` before any parsing: established `c52fc7b5d34f`.  
- `devices_bypath.clear()` before any parsing: established `2c0fd7d86827`.
- Blank IDs are skipped: established `7add8da7b00a`.
- `hostname` always updated from metadata: established `ff6b3997caa4`.

**Implementation critique** (blame lines 179–208):
- Line 181: `devices.clear()` — correct per `c52fc7b5d34f`.
- Line 182: `devices_bypath.clear()` — correct.
- Line 183: `metadata = m` — correct; stores raw map.
- Lines 184–203: `for_each_pair` loop — correct; handles blank ids and by-path.
- Lines 205–207: `hostname` update — correct per `ff6b3997caa4`.
- **UNGROUNDED**: There is no handling for the key `"device_ids"` where `id` contains whitespace but is otherwise non-blank. The `for_each_pair` delimiter string `",; "` treats space as a delimiter, which means a device_id value cannot contain spaces. This is an undocumented contract with the wire format that is never explicitly asserted.
- STATUS: **OK** for the documented paths; **UNGROUNDED** for space-in-id edge case.

---

### `DaemonState::_get_config_defaults` (DaemonState member — `DaemonState.cc:210`)

**File**: `src/mgr/DaemonState.cc:210` / `src/mgr/DaemonState.h:87`  
**Establishing commit**: `86cf85e0a2c5` (2018-01-05) — originally `get_config_defaults()`  
**Key evolution**:
- `1c2bc53df73d` (2018-10-17) — renamed to `_get_config_defaults()` to make the lock requirement explicit; fix tracker#36590  
- `6e1a6f0aa1fa` (2021-12-19) — moved from header into .cc

**Intent**: Lazily decode `config_defaults_bl` (a bufferlist received from the daemon on session open) into `config_defaults` map on first access. The bufferlist is stored encoded to avoid the ~50 kB decode cost on every session — decode is deferred until actually needed.

**Invariants**:
- Caller must hold `DaemonState::lock` before calling (leading underscore convention, established `1c2bc53df73d`).
- Returns a reference to the lazily-populated `config_defaults` cache.
- `buffer::error` during decode is silently swallowed; in that case `config_defaults` remains empty (established `62382040ee9b`, 2018-05-06 — exception type change from generic to `buffer::error`).

**Implementation critique** (blame lines 210–221):
- Lines 212–213: double-condition (`config_defaults.empty() && config_defaults_bl.length()`) — OVERCAUTIOUS for the `empty()` half: if decoding produced no entries but succeeded, every subsequent call will re-attempt decode. In practice, an empty config-defaults bufferlist is pathological, so this is unlikely to fire but remains technically incorrect.
- Line 216: `decode(config_defaults, p)` — uses unqualified `decode` (established `156c941ad0d2`, 2017-12-25: "use unqualified encode/decode").
- Line 217: `catch (buffer::error& e) {}` — silent swallow. This means a corrupt `config_defaults_bl` silently produces an empty map with no log output. No caller checks for this failure mode.  
- **UNGROUNDED**: No `dout` or logging on decode failure; corruption would be invisible.
- STATUS: **OVERCAUTIOUS** (re-decode on empty-but-valid decode), **UNGROUNDED** (silent decode failure)

---

## Class: `DeviceState`

`DeviceState` holds manager-side knowledge about one physical storage device: its unique ID, set of (server, devname, path) attachment tuples, set of daemon keys that reference it, persistent key-value metadata (loaded from config-key store), life-expectancy range, and optional SSD wear level.

### `DeviceState::DeviceState` (constructor)

**File**: `src/mgr/DaemonState.h:126`  
**Establishing commit**: `38afbae02696` (2018-06-05) — original `DeviceState(const std::string& n) : devid(n) {}`  
**Key evolution**:
- `0b14f926ec23` (2018-11-08) — explicit `RefCountedObject(nullptr, 0)` to set initial refcount to 0 (fix initial refcount bug)
- `517bdca529db` (2019-02-06) — `FRIEND_MAKE_REF`; constructor moved to private; `ceph::make_ref<DeviceState>()` factory enforces correct initial refcount

**Intent**: Create a `DeviceState` with the given `devid`; all other fields are default-initialised.  
**Invariant**: Constructor is private; only `ceph::make_ref<DeviceState>()` (via `FRIEND_MAKE_REF`) may create instances. This prevents the initial-refcount bug from recurring (tracker fix in `0b14f926ec23`).

**Implementation critique** (blame h:125–126):
- Line 125: `FRIEND_MAKE_REF(DeviceState)` — correct.
- Line 126: `DeviceState(const std::string& n) : devid(n) {}` — correct.
- STATUS: **OK**

---

### `DeviceState::set_metadata` (DeviceState member — `DaemonState.cc:48`)

**File**: `src/mgr/DaemonState.cc:48`  
**Establishing commit**: `47abea157cf4` (2018-06-05) — initial version parsed `expected_failure`/`expected_failure_stamp`  
**Key evolution**:
- `4920bbd6cb49` (2018-06-07) — renamed fields to `life_expectancy_min/max/stamp`
- `c52fcb51afb6` (2021-02-08) — added `wear_level` parsing via `atof`

**Intent**: Deserialise persistent device metadata from a `map<string,string>&&` (loaded from config-key store). Parse known fields (`life_expectancy_min`, `life_expectancy_max`, `life_expectancy_stamp`, `wear_level`) into typed members. Metadata is moved in to avoid a copy.

**Invariants**:
- Takes a moved map — caller relinquishes ownership.
- `utime_t::parse()` is called on life-expectancy fields; failures are silently ignored (no check on return value).

**Implementation critique** (blame lines 48–67):
- Lines 50–66: parse `life_expectancy_min`, `life_expectancy_max`, `life_expectancy_stamp`, `wear_level` — correct correspondence with `set_life_expectancy` / `set_wear_level` storage.
- Line 65: `wear_level = atof(p->second.c_str())` — **UNGROUNDED**: `atof` returns `0.0` on parse failure, which is a valid wear level. A corrupt or empty `wear_level` string silently becomes `0.0f`. A more robust parse (e.g., checking for empty before calling `atof`) would be consistent with the rest of the code.
- **UNGROUNDED**: No validation that `life_expectancy_min <= life_expectancy_max` when both are parsed. Callers of `set_life_expectancy` do enforce `from`/`to` semantics but the deserialisation path does not.
- STATUS: **UNGROUNDED** (atof-zero ambiguity; no min≤max assertion on deserialise)

---

### `DeviceState::set_life_expectancy` (`DaemonState.cc:69`)

**File**: `src/mgr/DaemonState.cc:69`  
**Establishing commit**: `4920bbd6cb49` (2018-06-07) — renamed from `set_expected_failure`; changed to range  
**Key evolution**:
- `a9b04900366d` (2018-10-12) — empty `utime_t` written as `""` in metadata instead of `"0.000000"`; fix tracker cosmetic issue
- `78b72b0be752` (2021-02-08) — `stringify(from)` and `stringify(to)` used instead of direct assignment (fix for serialisation; tracker#49215 — life expectancy was forgotten on mgr restart)

**Intent**: Record a new life-expectancy prediction for a device. Stores the `(from, to)` utime range and the `now` timestamp in both the in-memory typed fields and the persistent `metadata` map (so it survives a mgr restart via config-key). Empty `utime_t()` values are stored as empty strings to avoid `"0.000000"` noise.

**Invariants**:
- All three metadata keys (`life_expectancy_min`, `life_expectancy_max`, `life_expectancy_stamp`) are always updated atomically (lines 71–87).
- The serialised values use `stringify()` for non-zero times and `""` for zero times (`78b72b0be752` fix).

**Implementation critique** (blame lines 69–88):
- Lines 73–87: correct; both in-memory and serialised state are written.
- **OVERCAUTIOUS**: No assertion that `from <= to`. Callers (in `ActivePyModules.cc`) are expected to pass valid ranges, but the API permits `from > to` silently.
- STATUS: **OVERCAUTIOUS** (no from≤to assertion)

---

### `DeviceState::rm_life_expectancy` (`DaemonState.cc:90`)

**File**: `src/mgr/DaemonState.cc:90`  
**Establishing commit**: `4920bbd6cb49` (2018-06-07) — renamed from `rm_expected_failure`  
**Last touched**: `c52fcb51afb6` (2021-02-08) — added `wear_level` support nearby but no change to this function

**Intent**: Clear life-expectancy prediction: reset in-memory fields to `utime_t()` (zero) and erase all three metadata keys so the prediction is not re-persisted.

**Invariants**:
- All three metadata keys (`life_expectancy_min`, `life_expectancy_max`, `life_expectancy_stamp`) are erased (not set to empty string) — diverges from `set_life_expectancy` which sets them to `""` for zero values. This means `rm_life_expectancy` produces a metadata map that, on the next `set_metadata` reload, will not parse any life-expectancy fields (correct behaviour via absence vs. empty-string).

**Implementation critique** (blame lines 90–97):
- Lines 92–96: correctly resets in-memory and serialised state.
- STATUS: **OK**

---

### `DeviceState::set_wear_level` (`DaemonState.cc:99`)

**File**: `src/mgr/DaemonState.cc:99`  
**Establishing commit**: `c52fcb51afb6` (2021-02-08)

**Intent**: Record SSD wear level. A negative `wear` clears the field; non-negative values are stored in both the in-memory `wear_level` and `metadata["wear_level"]` for persistence.

**Invariants**:
- `wear_level >= 0` check: negative → erase from metadata; non-negative → stringify and store.
- Sentinel `-1` for "unknown" is initialised in the header (`float wear_level = -1` — blame h:105).

**Implementation critique** (blame lines 99–107):
- Line 102: `if (wear >= 0)` — correct; uses `>=` so `0.0` is a valid level.
- **UNGROUNDED**: No upper-bound check (valid SSD wear is 0.0–1.0 or 0–100 depending on source). The invariant `wear >= 0` is enforced but `wear > 1.0` (or whatever the domain maximum is) is not; callers from Python modules pass arbitrary floats.
- STATUS: **UNGROUNDED** (no upper-bound validation)

---

### `DeviceState::get_life_expectancy_str` (`DaemonState.cc:109`)

**File**: `src/mgr/DaemonState.cc:109`  
**Establishing commit**: `4920bbd6cb49` (2018-06-07) — initial version returning raw timestamps  
**Key evolution**:
- `f222375cbced` (2018-06-07) — rewritten to produce human-readable relative strings; takes `utime_t now` parameter; added `"now"` path when `now >= min`
- `c52fcb51afb6` (2021-02-08) — signature `get_life_expectancy_str(utime_t now)` standardised

**Intent**: Produce a human-readable duration string for the device's life expectancy, relative to `now`. Returns `""` if no expectancy is set. Returns `"now"` if `now >= life_expectancy.first`. Returns `">X"` if only a lower bound exists. Returns `"X to Y"` or just `"X"` if both bounds are identical after timespan formatting.

**Invariants**:
- `life_expectancy.first == utime_t()` → return `""`.
- `now >= life_expectancy.first` → return `"now"` (device has already exceeded minimum expectancy).
- `life_expectancy.second == utime_t()` → return `">min"` (no upper bound).

**Implementation critique** (blame lines 109–128):
- Line 119: `if (life_expectancy.second == utime_t())` check — this occurs *after* computing `max = life_expectancy.second - now`. When `life_expectancy.second == utime_t()`, the subtraction `utime_t() - now` produces a wrapped/underflow value for `max`. The `max` variable is computed but then discarded by the early `return` on line 120. This is not a bug (value is unused), but the order — compute then check — is **UNGROUNDED** and misleading; the guard should logically come before the subtraction.
- STATUS: **UNGROUNDED** (dead computation of `max` before the guard at line 119)

---

### `DeviceState::dump` (`DaemonState.cc:130`)

**File**: `src/mgr/DaemonState.cc:130`  
**Establishing commit**: `46ab713e1f23` (2018-06-05) — initial dump outputting `devid`, `host`, `daemons`, `expected_failure`  
**Key evolution**:
- `6b6fe52aacf6` (2018-06-06) — `host` → `location` array of `{host,dev}` objects
- `2c0fd7d86827` (2019-12-15) — location attachments now include `path`; `devnames` set → `attachments` 3-tuple
- `5aac7eba36be` (2019-09-29) — `to_string(i)` for daemons → `f->dump_stream("daemon") << i`
- `4920bbd6cb49` (2018-06-07) — `expected_failure` → `life_expectancy_min/max/stamp`
- `c52fcb51afb6` (2021-02-08) — added `wear_level` conditional field

**Intent**: Serialise `DeviceState` to a `Formatter` for JSON/XML output. Fields emitted: `devid`, `location` array (each attachment: `host`, `dev`, `path`), `daemons` array, optionally `life_expectancy_min/max/stamp`, optionally `wear_level`.

**Implementation critique** (blame lines 130–156):
- Line 134: iterates `attachments` (3-tuple) — correct per `2c0fd7d86827`.
- Line 144: `f->dump_stream("daemon") << i` — correct use of `DaemonKey::operator<<` (established `5aac7eba36be`).
- Line 147: guard `if (life_expectancy.first != utime_t())` — emits both min/max/stamp only when min is set; if only a max were set (theoretically possible), it would not be emitted. In practice `set_life_expectancy` always sets both; no path sets only max.
- STATUS: **OK**

---

### `DeviceState::print` (`DaemonState.cc:158`)

**File**: `src/mgr/DaemonState.cc:158`  
**Establishing commit**: `46ab713e1f23` (2018-06-05)  
**Key evolution**: same as `dump` above

**Intent**: Human-readable text output of device state for `device info` CLI output.

**Implementation critique** (blame lines 158–177):
- Lines 161–165: `for (auto& i : attachments)` — iterates 3-tuples, prints `"attachment host dev path\n"` then emits a redundant blank line (`out << "\n";` on line 164 after the newline already in the format string). **UNGROUNDED**: double newline per attachment produces inconsistent output. Established in `2c0fd7d86827`.
- Lines 166–168: `std::copy` with `make_ostream_joiner(out, ",")` — emits daemons comma-separated on one line. This differs from `dump`'s per-element array structure. No bug, but the visual inconsistency is unexplained.
- STATUS: **UNGROUNDED** (double newline per attachment at blame line 163–164)

---

## Class: `DaemonStateIndex`

`DaemonStateIndex` is the authoritative in-process registry of all known daemon states and device states visible to the manager. It exposes a two-level locking model: index-wide `ceph::shared_mutex lock` for structural changes and per-`DaemonState` `ceph::mutex lock` for field-level mutations.

### `DaemonStateIndex::DaemonStateIndex` / `~DaemonStateIndex`

**File**: `src/mgr/DaemonState.cc:223–224` / `src/mgr/DaemonState.h:161–162`  
**Establishing commit**: `d9dfb436ea58` (2016-07-03) — originally `DaemonStateIndex() : lock("DaemonState") {}`  
**Key evolution**:
- `806f10847cef` (2017-08-24) — switched to RWLock; `DaemonStateIndex() {}`
- `675606bf712e` (2019-07-07) — `ceph::shared_mutex` in-class initialiser
- `d2d4c7d3f865` (2025-08-14) — un-inlined to allow forward-declaring `PerfCounterTypes`

**Intent**: Default constructor/destructor; all members are default-initialised by their own constructors.

**Implementation critique**: Trivially correct. STATUS: **OK**

---

### `DaemonStateIndex::_insert` (`DaemonState.cc:232`)

**File**: `src/mgr/DaemonState.cc:232`  
**Establishing commit**: `8a2f4429b129` (2018-10-18) — split from `insert` so `update_metadata` can call it without re-acquiring the lock  
**Key evolution**:
- `6b6fe52aacf6` (2018-06-06) — `devices` index maintenance added (iterates `dm->devices`, creates/updates DeviceState)
- `2c0fd7d86827` (2019-12-15) — `attachments` 3-tuple replaces `devnames` pair

**Intent**: Insert a `DaemonState` into all three indexes (`all`, `by_server`, `devices`) without acquiring the outer `lock`. **Requires caller to hold `lock` exclusively** (write lock).

**Invariants**:
- If `all` already contains the key, `_erase` is called first (established `b7c9561accef`, 2016-07-01 — original locking fix).
- `by_server[dm->hostname][dm->key] = dm` — `dm->hostname` must already be set before `_insert` (extracted from metadata by `DaemonState::set_metadata`).
- For every `(devid, devname)` in `dm->devices`, the device index is updated: `_get_or_create_device(devid)` then `d->daemons.insert(dm->key)` and appropriate attachment tuple insertion.

**Implementation critique** (blame lines 232–252):
- Line 234: `if (all.count(dm->key))` — uses `count` instead of `find`; results in two lookups. This is consistent with the original (first written `b7c9561accef`). Not a correctness issue.
- Lines 241–251: `for (auto& i : dm->devices)` device-index update — the attachment key is `(hostname, devname, path)`. If `devices_bypath` does not contain the devid (line 244), path is `""`. This is correct: path is optional per `2c0fd7d86827`.
- **UNGROUNDED**: There is no assertion that `dm->hostname` is non-empty before inserting into `by_server`. An empty `hostname` would insert into `by_server[""]`, contaminating that bucket. The only protection is that `DaemonState::set_metadata` sets `hostname` from `m["hostname"]`; if metadata never arrives, `hostname` remains `""`.
- STATUS: **UNGROUNDED** (no empty-hostname guard before `by_server` insertion)

---

### `DaemonStateIndex::insert` (`DaemonState.cc:226`)

**File**: `src/mgr/DaemonState.cc:226`  
**Establishing commit**: `d9dfb436ea58` (2016-07-03)  
**Key evolution**:
- `806f10847cef` (2017-08-24) — lock upgraded to `RWLock::WLocker`
- `8a2f4429b129` (2018-10-18) — delegated to `_insert` after taking write lock
- `675606bf712e` (2019-07-07) — `std::unique_lock`

**Intent**: Public write-locked entry point: acquire exclusive lock, delegate to `_insert`.

**Implementation critique** (blame lines 226–230):
- Line 228: `std::unique_lock l{lock}` — correct.
- Line 229: `_insert(dm)` — correct delegation.
- STATUS: **OK**

---

### `DaemonStateIndex::_erase` (`DaemonState.cc:254`)

**File**: `src/mgr/DaemonState.cc:254`  
**Establishing commit**: `ac30e6cee2b2` (2016-06-30) — initial version, no device index  
**Key evolution**:
- `0e7137aa6a1f` (2017-05-05) — use `find` instead of `at` (avoid double lookup); `assert` key exists
- `38afbae02696` (2018-06-05) — add device index maintenance loop
- `ab23c5069647` (2018-08-23) — `assert` → `ceph_assert`
- `6b6fe52aacf6` (2018-06-06) — device attachment: `devnames` pair
- `2c0fd7d86827` (2019-12-15) — `devnames` → `attachments` 3-tuple
- `45d4dfed1ded` (2018-06-05) — `d->daemons.empty()` → `d->empty()` (prune device when no persistent metadata either)
- `c93dc8849145` (2019-07-07) — `lock.is_wlocked()` → `ceph_mutex_is_wlocked(lock)`

**Intent**: Remove `dmk` from all indexes (`all`, `by_server`, `devices`). **Requires exclusive lock.** For each device the daemon referenced, remove the daemon from the device's `daemons` set and the appropriate attachment tuple; if the device is now `empty()` (no daemons and no persistent metadata), prune it from `devices`.

**Invariants**:
- `ceph_assert(ceph_mutex_is_wlocked(lock))` — exclusive lock must be held (established `d9dfb436ea58`, updated `ab23c5069647`, `c93dc8849145`).
- `ceph_assert(to_erase != all.end())` — key must exist (established `0e7137aa6a1f`).
- `ceph_assert(d->daemons.count(dmk))` — daemon must be registered with each of its devices (established `38afbae02696`, `ab23c5069647`).
- `by_server` bucket erased when empty (established `ac30e6cee2b2`).
- Device erased when `empty()` — both daemon-set and metadata empty (established `45d4dfed1ded`).

**Implementation critique** (blame lines 254–284):
- Line 256: `ceph_assert(ceph_mutex_is_wlocked(lock))` — correct.
- Lines 262–275: device index cleanup — correct with 3-tuple matching, consistent with `_insert`.
- Line 264: `ceph_assert(d->daemons.count(dmk))` — this assertion can theoretically fail if the device is shared across two daemons and one daemon's `dm->devices` map is out of sync with `d->daemons`. The only safe path is that both maps are always updated together. History shows they are (insert and erase are always paired), so the assertion is sound.
- **UNGROUNDED**: After `d->daemons.erase(dmk)` (line 265), the `attachments` erase (lines 266–271) reconstructs the tuple from `dm->devices_bypath`. If `dm->devices_bypath` was modified between `_insert` and `_erase` (which cannot happen in practice because `update_metadata` always `_rm` then `_insert`), the tuple lookup would not match. In the current call pattern this is safe, but is not enforced by a data structure constraint.
- STATUS: **OK** with **UNGROUNDED** note on attachment tuple consistency

---

### `DaemonStateIndex::_get_or_create_device` (`DaemonState.h:148`)

**File**: `src/mgr/DaemonState.h:148`  
**Establishing commit**: `38afbae02696` (2018-06-05) — original two-step find-then-insert  
**Key evolution**:
- `517bdca529db` (2019-02-06) — rewritten with `try_emplace`; `ceph::make_ref<DeviceState>()` factory (private constructor enforcement)

**Intent**: Find or create a `DeviceState` for `dev`. Uses `try_emplace` for a single map operation. **Requires exclusive lock.**

**Implementation critique** (blame h:148–154):
- Line 149: `devices.try_emplace(dev, nullptr)` — inserts null sentinel on first access; line 152 replaces it.
- STATUS: **OK**

---

### `DaemonStateIndex::_erase_device` (`DaemonState.h:156`)

**File**: `src/mgr/DaemonState.h:156`  
**Establishing commit**: `38afbae02696` (2018-06-05)  
**Key evolution**: `517bdca529db` — parameter type changed from `DeviceStateRef` to `ceph::ref_t<DeviceState>`

**Intent**: Remove the device from the `devices` map. **Requires exclusive lock.**

**Implementation critique**: Single-line erase. Correct.  
STATUS: **OK**

---

### `DeviceState::empty` (`DaemonState.h:117`)

**File**: `src/mgr/DaemonState.h:117`
**Establishing commit**: `45d4dfed1ded` (2018-06-05) — introduced alongside `DeviceState::set_metadata` and the concept of persistent device metadata

**Intent**: Predicate that returns `true` when a `DeviceState` holds no daemon references (`daemons.empty()`) and no persistent metadata (`metadata.empty()`). Used as the prune sentinel: `_erase` (via `_insert`→`_erase` or direct call) prunes devices from the `devices` index when `empty()` returns `true`. The predicate was added specifically because devices that have persistent metadata (life expectancy etc.) should survive even when no daemons currently reference them (tracker context: persistent device metadata loaded from config-key store).

**Invariants**:
- Both conditions must be `true` for pruning (not just `daemons.empty()`): established `45d4dfed1ded`.

**Implementation critique** (blame h:117–119):
- `return daemons.empty() && metadata.empty()` — correct; `wear_level` and `life_expectancy` typed fields are not checked directly, but those fields are only set when `metadata` is non-empty (both `set_life_expectancy` and `set_wear_level` write into `metadata`), so the predicate correctly infers their state from `metadata.empty()`.
- **UNGROUNDED**: If a caller clears `metadata` manually (bypassing `rm_life_expectancy`/`set_wear_level`) while typed fields (`life_expectancy`, `wear_level`) remain non-zero, `empty()` would return `true` and the device would be pruned with stale in-memory state. No current caller does this, but it is an undocumented coupling.
- STATUS: **OK** with **UNGROUNDED** note on typed-field/metadata coupling

---

### `DaemonStateIndex::_rm` (`DaemonState.cc:339`)

**File**: `src/mgr/DaemonState.cc:339`  
**Establishing commit**: `8a2f4429b129` (2018-10-18) — split from `rm` for `update_metadata`

**Intent**: Remove a daemon from all indexes if it exists, without acquiring the outer lock. **Requires caller to hold exclusive lock.**

**Invariants**:
- Conditional: if `all.count(key) == 0`, no-op (established `a6832cb610ba`). This is intentional for `update_metadata` where the daemon may not be in the index yet (first-time update path).

**Implementation critique** (blame lines 339–344):
- Line 341: `if (all.count(key))` — defensive check; avoids the `ceph_assert(to_erase != all.end())` in `_erase`. Correct.
- STATUS: **OK**

---

### `DaemonStateIndex::rm` (`DaemonState.cc:333`)

**File**: `src/mgr/DaemonState.cc:333`  
**Establishing commit**: `a6832cb610ba` (2018-03-06)  
**Key evolution**:
- `8a2f4429b129` (2018-10-18) — delegated to `_rm`
- `675606bf712e` (2019-07-07) — `std::unique_lock`

**Intent**: Public write-locked entry point: acquire exclusive lock, delegate to `_rm` (which is a no-op if key not found).

**Implementation critique** (blame lines 333–337): Correct.  
STATUS: **OK**

---

### `DaemonStateIndex::exists` (`DaemonState.cc:314`)

**File**: `src/mgr/DaemonState.cc:314`  
**Establishing commit**: `d9dfb436ea58` (2016-07-03); locking fixed `b7c9561accef` (2016-07-01 — had no lock in original `DaemonMetadata`)  
**Key evolution**: lock upgraded `806f10847cef` → `675606bf712e`

**Intent**: Shared-locked test for daemon presence.

**Implementation critique** (blame lines 314–319):
- Returns `all.count(key) > 0`. Correct and safe under shared lock.
- STATUS: **OK**

---

### `DaemonStateIndex::get` (`DaemonState.cc:321`)

**File**: `src/mgr/DaemonState.cc:321`  
**Establishing commit**: `d9dfb436ea58` (2016-07-03) — original: `return all.at(key)` (throws on miss)  
**Key evolution**:
- `f9a4ca07acec` (2017-09-08) — changed to `find`+`nullptr` return on miss; fix tracker#21253 ("py calls for dne service perf counters")
- `8a2f4429b129` (2018-10-18) — no change to get itself
- `675606bf712e` (2019-07-07) — lock upgrade

**Intent**: Return a shared pointer to the named daemon's state, or `nullptr` if not found. Shared-locked.

**Invariants**:
- Returns `nullptr` (not a thrown exception) for missing keys: established `f9a4ca07acec` (tracker#21253).

**Implementation critique** (blame lines 321–331):
- Correct: `find`, not `at`. Returns `nullptr` on miss.
- **OVERCAUTIOUS**: Callers sometimes use `exists()` then `get()` in sequence (two separate shared-lock acquisitions and two map lookups). The double-check pattern is not enforced at the API level and is not technically safe under the threading model (the daemon could be removed between the two calls). This is a caller-side deficiency, not a bug in `get` itself.
- STATUS: **OK** for `get`; **OVERCAUTIOUS** note on calling pattern

---

### `DaemonStateIndex::get_by_service` (`DaemonState.cc:286`)

**File**: `src/mgr/DaemonState.cc:286`  
**Establishing commit**: `a22b256bad1f` (2017-06-22) — renamed from `get_by_type(uint8_t)` when `DaemonKey` changed to string  
**Key evolution**:
- `806f10847cef` (2017-08-24) — RWLock, comment "returns by value to avoid callers holding lock"
- `5aac7eba36be` (2019-09-29) — `i.first.first == svc` → `key.type == svc`
- `675606bf712e` (2019-07-07) — `std::shared_lock`

**Intent**: Return a by-value copy of all daemons of a given service type, under a shared lock. Callers do not need to hold the index lock after this returns; they must still acquire each `DaemonState::lock` on retrieved entries.

**Invariants**:
- Return by value (not reference): established `806f10847cef` to avoid callers needing to hold the index lock.
- Linear scan of `all` — O(n).

**Implementation critique** (blame lines 286–300):
- Lines 293–297: structured binding `[key, state]` linear scan — correct but O(n) over all daemons. The `cull` function exploits `lower_bound` for O(log n) start; `get_by_service` does not. For large clusters this is a performance concern but was never optimised.
- **UNGROUNDED**: No explanation for why `get_by_service` uses linear scan while `cull` uses sorted range. The difference predates `5aac7eba36be` and has never been addressed.
- STATUS: **UNGROUNDED** (linear scan unoptimised relative to `cull`)

---

### `DaemonStateIndex::get_by_server` (`DaemonState.cc:302`)

**File**: `src/mgr/DaemonState.cc:302`  
**Establishing commit**: `d9dfb436ea58` (2016-07-03); locking fixed `b7c9561accef`  
**Key evolution**:
- `806f10847cef` (2017-08-24) — RWLock
- `f9a11737ea5c` (2020-08-28) — `count`+`at` → single `find` (avoid double lookup)
- `675606bf712e` (2019-07-07) — `std::shared_lock`

**Intent**: Return by-value copy of all daemons on a given server, or `{}` if none.

**Implementation critique** (blame lines 302–312):
- Single `find` call: correct and optimal per `f9a11737ea5c`.
- STATUS: **OK**

---

### `DaemonStateIndex::get_all` (`DaemonState.h:180`)

**File**: `src/mgr/DaemonState.h:180`  
**Establishing commit**: `806f10847cef` (2017-08-24) — changed from returning a const reference to returning by value (`DaemonStateCollection get_all() const {return all;}`)

**Intent**: Return a copy of the entire daemon index. Callers must still lock individual entries.

**Implementation critique** (blame h:180):
- Inline; no locking. **DIVERGED**: Returns `all` by value but takes no lock. The original `const DaemonStateCollection &get_all()` (pre-`806f10847cef`) was explicitly changed to return by value to avoid callers needing to hold the lock, but the current implementation does not acquire `lock` before copying `all`. Other methods (`get_by_service`, `get_by_server`) acquire a shared lock for the same reason.
- **DIVERGED** from `806f10847cef`: The comment added by that commit says "Note that these return by value rather than reference to avoid callers needing to stay in lock while using result" — but `get_all()` now returns by value *without* taking the lock first, making the copy itself unprotected during a concurrent write.
- SHA that established the inconsistency: `806f10847cef` (the inline was kept when all other methods were updated to use RWLock).
- STATUS: **DIVERGED** (`get_all` copies `all` without holding `lock`)

---

### `DaemonStateIndex::with_daemons_by_server` (`DaemonState.h:183`)

**File**: `src/mgr/DaemonState.h:183`  
**Establishing commit**: `806f10847cef` (2017-08-24) — introduced to allow safe access to `by_server` without exposing a reference  
**Key evolution**:
- `675606bf712e` (2019-07-07) — `std::shared_lock`
- `b4304d521f61` (2025-07-31) — copy `by_server` inside lock, release lock before invoking callback; fix tracker#72337 (GIL deadlock: callback into Python while holding lock caused extended delays)

**Intent**: Allow callers to iterate `by_server` without holding the lock during the callback. The `by_server` map is copied under a shared lock; the callback receives the copy and runs without the lock. This prevents the GIL-deadlock scenario (tracker#72337).

**Invariants**:
- Lock is released before the callback executes (established `b4304d521f61`).
- Callback receives a copy, so modifications to the original index during the callback are not reflected (and cannot cause data races).

**Implementation critique** (blame h:183–191):
- Lines 185–189: lambda captures `by_server` under `shared_lock l{lock}`, returns it, lock released on `}()` — correct.
- Line 190: callback receives `by_server_copy` — correct.
- **UNGROUNDED**: The comment "Don't hold the lock any longer than necessary" explains the mechanism but does not document the consequence: the snapshot may be stale by the time the callback runs. Callers must tolerate stale snapshots.
- STATUS: **OK**

---

### `DaemonStateIndex::with_device` (`DaemonState.h:194`)

**File**: `src/mgr/DaemonState.h:194`  
**Establishing commit**: `946e1803453a` (2018-06-05) — initial version  
**Key evolution**: `47abea157cf4` (2018-06-05) — return type changed from `auto` to `bool`; `675606bf712e` — lock upgrade

**Intent**: Read-only callback on a named device under shared lock. Returns `false` if device not found, `true` after callback.

**Implementation critique** (blame h:194–203):
- Correct. Callback receives `DeviceState&` (via `*p->second`).
- **UNGROUNDED**: Callback may modify `DeviceState` fields through the non-const reference despite the method being `const` and holding a shared lock. The `DeviceState` itself has no lock, so concurrent writes through the callback while holding shared lock could race with other callers. In practice callers of `with_device` use it read-only.
- STATUS: **UNGROUNDED** (non-const callback on shared lock)

---

### `DaemonStateIndex::with_device_write` (`DaemonState.h:206`)

**File**: `src/mgr/DaemonState.h:206`  
**Establishing commit**: `47abea157cf4` (2018-06-05)  
**Key evolution**: `675606bf712e` — lock upgrade

**Intent**: Writable callback on a named device under exclusive lock. If the device becomes `empty()` after the callback, it is pruned from the index. Returns `false` if not found.

**Invariants**:
- After callback, checks `p->second->empty()` and prunes if so (established `47abea157cf4`).

**Implementation critique** (blame h:206–218):
- Correct.
- STATUS: **OK**

---

### `DaemonStateIndex::with_device_create` (`DaemonState.h:221`)

**File**: `src/mgr/DaemonState.h:221`  
**Establishing commit**: `47abea157cf4` (2018-06-05)

**Intent**: Get-or-create a device under exclusive lock, then invoke callback. Used by callers that need to set persistent device metadata on a device that may not yet exist.

**Implementation critique** (blame h:221–226):
- Correct. No pruning after callback (device was just created).
- **UNGROUNDED**: Unlike `with_device_write`, `with_device_create` never prunes after the callback. If the callback leaves the device `empty()`, the device remains in the index permanently until the next `_erase` of a referencing daemon. This diverges from the intent of `empty()` as the "safe to prune" sentinel (established `45d4dfed1ded`).
- STATUS: **UNGROUNDED** (no post-callback empty check; stale empty device possible)

---

### `DaemonStateIndex::with_devices` (`DaemonState.h:229`)

**File**: `src/mgr/DaemonState.h:229`  
**Establishing commit**: `946e1803453a` (2018-06-05)  
**Key evolution**: `675606bf712e` — lock upgrade

**Intent**: Iterate all devices under shared lock, invoking callback for each.

**Implementation critique** (blame h:229–234): Correct.  
STATUS: **OK**

---

### `DaemonStateIndex::with_devices2` (`DaemonState.h:237`)

**File**: `src/mgr/DaemonState.h:237`  
**Establishing commit**: `dac649753bcb` (2019-01-18) — fix tracker#37736  
**Key evolution**: `675606bf712e` — lock upgrade

**Intent**: Two-callback variant: `cbi()` is called first (under lock, for initialisation), then `cb()` is called for each device (under lock). Used by Python module active-thread restore for `get('devices')`.

**Implementation critique** (blame h:237–245):
- Both callbacks run under the shared lock. Unlike `with_daemons_by_server`, no copy is made before releasing the lock. If `cbi` or `cb` calls back into Python, the GIL deadlock risk noted in tracker#72337 also applies here.
- **UNGROUNDED**: `with_daemons_by_server` was fixed (tracker#72337, `b4304d521f61`) to copy before releasing the lock; `with_devices2` was not. The same GIL-deadlock pattern could occur if `cbi` or `cb` call into Python.
- STATUS: **UNGROUNDED** (potential GIL deadlock not fixed, unlike `with_daemons_by_server`)

---

### `DaemonStateIndex::list_devids_by_server` (`DaemonState.h:247`)

**File**: `src/mgr/DaemonState.h:247`  
**Establishing commit**: `946e1803453a` (2018-06-05) — original version iterated `devids` set  
**Key evolution**: `6b6fe52aacf6` (2018-06-06) — updated to iterate `devices` map (after `devids` set was replaced)

**Intent**: Populate a `set<string>` with all device IDs referenced by daemons on a given server.

**Implementation critique** (blame h:247–256):
- Line 249: `auto m = get_by_server(server)` — acquires and releases shared lock to get a copy of the server's daemon map.
- Line 251: `std::lock_guard l(i.second->lock)` — acquires each daemon's per-object mutex before reading `i.second->devices`.
- **UNGROUNDED**: The function signature is not `const` (no lock on outer `devices` map), but it iterates `i.second->devices` through DaemonState locks only. The outer `devices` index (device→DeviceState) is not consulted; instead the per-daemon `devices` map (devid→devname on `DaemonState`) is iterated. This is a different data structure from `DaemonStateIndex::devices`. The naming overlap is confusing but the logic is correct.
- STATUS: **OK**

---

### `DaemonStateIndex::notify_updating` / `clear_updating` / `is_updating` (`DaemonState.h:258/262/266`)

**File**: `src/mgr/DaemonState.h:258`, `262`, `266`  
**Establishing commit**: `d9dfb436ea58` (2016-07-03) — originally inline no-lock  
**Key evolution**: `806f10847cef` (2017-08-24) — all three methods now take the appropriate lock (`WLocker`/`RLocker`)  
**Current lock types**: `notify_updating` and `clear_updating` use `unique_lock`; `is_updating` uses `shared_lock`

**Intent**: Track which daemon keys are currently undergoing a metadata update (to let callers poll for completion). The `updating` set is protected by the same `lock` as the rest of the index.

**Implementation critique** (blame h:258–269):
- Correct; consistent lock pairing.
- STATUS: **OK**

---

### `DaemonStateIndex::update_metadata` (`DaemonState.h:271`)

**File**: `src/mgr/DaemonState.h:271`  
**Establishing commit**: `8a2f4429b129` (2018-10-18) — introduced specifically to fix a window where old device metadata could be visible; fix commit message: "Do the whole thing under the DaemonState lock so there isn't a window where the osd metadata isn't present at all."

**Intent**: Atomically update the metadata of an existing daemon: remove from all indexes, update the daemon's fields under the per-daemon lock, re-insert. This prevents the window where the daemon has no entry in the index during the update.

**Invariants**:
- Outer exclusive lock is held for the entire remove→update→re-insert sequence (established `8a2f4429b129`).
- Per-daemon `state->lock` is taken *inside* the outer exclusive lock — lock ordering is `lock` (index) then `state->lock` (per-daemon). This ordering must be consistent across all callers to avoid deadlock.

**Implementation critique** (blame h:271–281):
- Line 274: `std::unique_lock l{lock}` — outer exclusive lock acquired.
- Line 275: `_rm(state->key)` — removes from index (no-op if not present).
- Line 277: `std::lock_guard l2{state->lock}` — per-daemon lock acquired while already holding index lock. This lock ordering is consistent with no other code path that acquires both locks.
- Line 278: `state->set_metadata(meta)` — updates metadata.
- Line 280: `_insert(state)` — re-inserts.
- **UNGROUNDED**: If `state->key` has changed (e.g., a daemon restarted with a different name), `_rm(state->key)` would try to remove the old key. In practice callers never change the key in this path; the precondition is undocumented.
- STATUS: **OK** with **UNGROUNDED** note on key-change invariant

---

### `DaemonStateIndex::cull` (`DaemonState.cc:346`)

**File**: `src/mgr/DaemonState.cc:346`  
**Establishing commit**: `ac30e6cee2b2` (2016-06-30) — initial linear scan with `set<DaemonKey>`  
**Key evolution**:
- `0e7137aa6a1f` (2017-05-05) — `lower_bound` start; `vector<string>` for victims; lock taken once for full scan+erase
- `a22b256bad1f` (2017-06-22) — `entity_type_t` → `string` service name
- `5aac7eba36be` (2019-09-29) — `.first`/`.second` → `.type`/`.name` field access
- `7534737030b3` (2019-11-27) — second half of function: erase loop now constructs `DaemonKey{svc_name, i}` and logs with the full key

**Intent**: Remove all daemons of a given service type whose names do not appear in `names_exist`. Uses `lower_bound` to scope the scan to the relevant prefix of the sorted `all` map. Called when the cluster map is updated to remove stale entries.

**Invariants**:
- `all` is sorted by `DaemonKey`; `lower_bound({svc_name, ""})` begins the scan at the first key of that service.
- Early break when `daemon_key.type != svc_name` (past the service prefix).
- Victims are collected first, then erased (to avoid iterator invalidation during iteration).

**Implementation critique** (blame lines 346–368):
- Line 352: `all.lower_bound({svc_name, ""})` — correct for DaemonKey's ordering (`type` then `name`).
- Line 356: `daemon_key.type != svc_name` break — correct.
- Line 364: `DaemonKey daemon_key{svc_name, i}` — reconstructs full key from victim name. Correct.
- **OVERCAUTIOUS**: The `victims` vector holds only names (strings), then reconstructs `DaemonKey` during erase. The original code (pre-`0e7137aa6a1f`) held full `DaemonKey` values. The `vector<string>` approach saves a tiny amount of memory but requires reconstruction; this is a minor code smell (introduced `0e7137aa6a1f`).
- STATUS: **OK** with minor **OVERCAUTIOUS** note on victim reconstruction

---

### `DaemonStateIndex::cull_services` (`DaemonState.cc:370`)

**File**: `src/mgr/DaemonState.cc:370`  
**Establishing commit**: `7534737030b3` (2019-11-27) — fix: service daemons were not removed when the last instance was stopped; caused `ceph service dump` vs. dashboard inconsistency  
**Last touched**: `35f6dd06dd0b` (2025-08-14) — no logic change (PerfCounters extraction removed unrelated code)

**Intent**: Remove daemons whose `service_daemon == true` and whose type does not appear in `types_exist`. This is distinct from `cull` (which operates on first-party cluster-map daemons); `cull_services` handles third-party service daemons.

**Invariants**:
- Only daemons with `service_daemon == true` are considered.
- Must hold exclusive lock during full scan and erase (uses `std::unique_lock`).
- Victims collected as full `DaemonKey` values (unlike `cull` which collects names), then erased.

**Implementation critique** (blame lines 370–387):
- Line 374: `std::unique_lock l{lock}` — correct.
- Lines 375–381: collects full `DaemonKey` values into `victims` set.
- Lines 383–386: erases each victim.
- **UNGROUNDED**: The lock is held across both the scan and the erase phase. For clusters with many service daemons, this can hold the lock for an extended time. `cull` has the same pattern. The `b4304d521f61` fix (copy `by_server` before releasing lock) addressed a specific Python-callout path; the general scan+erase pattern remains long-lived under lock.
- STATUS: **OK** with **UNGROUNDED** note on lock hold duration under large victim counts

---

### `DaemonStateIndex::__anonbfc773bb0102` (`DaemonState.cc:192`)

ctags-identified anonymous function at line 192. This corresponds to the lambda inside `DaemonState::set_metadata`'s `for_each_pair` call. It captures `paths` and `this`; its body was established by `95a96cffc300` (2021-12-19).

**Implementation critique**: See `DaemonState::set_metadata` — the lambda is inlined in that analysis. No additional critique.  
STATUS: **OK** (see `set_metadata` section)

---

### `DaemonStateIndex::__anonb07a685d0102` (`DaemonState.h:185`)

ctags-identified anonymous function at line 185 of the header. This corresponds to the lambda inside `with_daemons_by_server` that captures `by_server` and the `shared_lock`, returning the copy. Established `b4304d521f61`.

**Implementation critique**: See `with_daemons_by_server`. Correct.  
STATUS: **OK**

---

## Cross-Cutting Invariants

### Lock ordering
Two locks exist: `DaemonStateIndex::lock` (index-wide shared_mutex) and `DaemonState::lock` (per-daemon ceph::mutex). The only code that takes both simultaneously is `update_metadata` (established `8a2f4429b129`, `675606bf712e`): index lock first, then per-daemon lock. This ordering must never be inverted. No historical violation found.

### `PerfCounterTypes` shared reference (PerfCounters classes now in `DaemonPerfCounters.{cc,h}`)
`DaemonStateIndex::types` (public `PerfCounterTypes` map) is still present in the header (blame h:166). The original FIXME comment ("shouldn't really be public") from `d9dfb436ea58` remains present as of HEAD. The `DaemonPerfCounters` constructor takes a reference to this map, creating a lifetime coupling: `DaemonState` must not outlive `DaemonStateIndex`. This is enforced only by convention (all `DaemonStatePtr` objects are owned by the index); no RAII guarantee exists.

### `DeviceState::empty()` sentinel
Defined at `h:117–119` as `daemons.empty() && metadata.empty()`. Devices are pruned from `devices` map when `empty()` (established `45d4dfed1ded`). The `with_device_create` template does not check `empty()` post-callback (see **UNGROUNDED** flag above), creating the possibility of empty-but-not-pruned devices.

---

## DIVERGED Findings

| Function | SHA | Contradicting line | Description |
|---|---|---|---|
| `get_all` (h:180) | `806f10847cef` | `h:180` (inline, no lock) | `get_all()` returns `all` by value without acquiring `lock`, contradicting the stated rationale of `806f10847cef` that all by-value returns exist to let callers safely drop the lock. The copy itself is unprotected. |

---

## UNGROUNDED Code Paths

| Function | Location | Description |
|---|---|---|
| `DaemonState::set_metadata` | `cc:190–203` | Space as delimiter in `device_ids` value means no device ID can contain a space; this is an undocumented wire-format contract. |
| `DaemonState::_get_config_defaults` | `cc:217` | Silent `buffer::error` swallow; no log output on corrupt `config_defaults_bl`. |
| `DaemonState::_get_config_defaults` | `cc:212` | Re-decode attempted on every call when `config_defaults.empty()` even if a prior decode succeeded but produced empty map. |
| `DeviceState::set_metadata` | `cc:65` | `atof` returns `0.0f` on parse failure; a corrupt `wear_level` string silently becomes a valid `0.0` wear level. |
| `DeviceState::set_metadata` | `cc:51–62` | No validation that parsed `life_expectancy_min <= life_expectancy_max`. |
| `DeviceState::set_life_expectancy` | `cc:69` | No assertion that `from <= to`; API permits inverted ranges silently. |
| `DeviceState::set_wear_level` | `cc:102` | No upper-bound check; arbitrary floats above `1.0` (or whatever domain max is) are stored without validation. |
| `DeviceState::get_life_expectancy_str` | `cc:118` | `max = life_expectancy.second - now` is computed before the guard `if (life_expectancy.second == utime_t())` at line 119; the computed value is discarded by the early return. Dead computation. |
| `DeviceState::print` | `cc:163–164` | Double newline per attachment: format string emits `\n` and then `out << "\n"` is also called, producing a blank line between each attachment line. |
| `DaemonStateIndex::_insert` | `cc:238` | No assertion that `dm->hostname` is non-empty before inserting into `by_server`; empty hostname would contaminate `by_server[""]`. |
| `DaemonStateIndex::_erase` | `cc:266–271` | Attachment tuple reconstruction from `devices_bypath` at erase time must match the tuple inserted; no structural guarantee that `devices_bypath` hasn't changed between insert and erase (safe only because `update_metadata` always `_rm`+`_insert` atomically). |
| `DaemonStateIndex::with_device` | `h:201` | Callback receives non-const `DeviceState&` under shared lock; callback could modify `DeviceState` while concurrent readers also hold shared lock and observe the device. |
| `DaemonStateIndex::with_device_create` | `h:225` | No post-callback `empty()` check; a device created then left empty by the callback is never pruned until a referencing daemon is erased. |
| `DaemonStateIndex::with_devices2` | `h:237–245` | Both callbacks run under shared lock while holding the index lock; if either calls into Python (as was the case for `get('devices')`), the GIL-deadlock risk identified in tracker#72337 applies here too (not fixed in `b4304d521f61`, which only fixed `with_daemons_by_server`). |
| `DaemonStateIndex::update_metadata` | `h:275` | Key-change precondition undocumented: `_rm(state->key)` assumes `state->key` is still the key under which the daemon was last inserted. |
| `DaemonStateIndex::get_by_service` | `cc:293` | Linear scan of `all`; `cull` uses `lower_bound` for O(log n) start on the same sorted map. Inconsistency is unexplained. |
| `DaemonStateIndex::cull_services` | `cc:374–386` | Lock held across full scan+erase; can hold exclusive lock for extended time under large service daemon counts. |
| `DeviceState::empty` | `h:117–119` | If `metadata` is cleared manually (bypassing `rm_life_expectancy`/`set_wear_level`), `empty()` returns `true` while typed fields (`life_expectancy`, `wear_level`) remain non-zero; device would be pruned with stale in-memory state. |

---

## OVERCAUTIOUS Findings

| Function | Location | Description |
|---|---|---|
| `DaemonState::_get_config_defaults` | `cc:212` | `config_defaults.empty()` check causes repeated decode attempts after an empty-but-valid decode. |
| `DeviceState::set_life_expectancy` | `cc:69` | No from≤to assertion; defensive validation absent. |
| `DaemonStateIndex::get` | `cc:321` | Callers sometimes use `exists()` then `get()` as two separate operations; the pattern is not safe under the threading model (daemon could be removed between calls) but is not guarded at the API level. |
| `DaemonStateIndex::cull` | `cc:358–362` | Victim names collected as strings then reconstructed into `DaemonKey`; minor overhead vs. collecting full keys. |

---

## Self-Check

| Check | Result |
|---|---|
| Every commit in `commits.txt` read? | ✅ All 85 diffs read |
| Every function in `functions.txt` has a section? | ✅ All 70 entries covered (duplicates in .h/.cc are combined; anonymous lambdas addressed; `DeviceState::empty` added in self-check pass) |
| Every DIVERGED flag cites a specific SHA and contradicting line? | ✅ One DIVERGED: `get_all` → `806f10847cef` / `h:180` |
| Every UNGROUNDED code path flagged? | ✅ 17 UNGROUNDED entries (1 added in self-check for `DeviceState::empty`) |
| Blame consulted for last-touched lines on every function? | ✅ Blame read for all functions in both files |
| PerfCounters classes covered? | ✅ Corpus note: moved to `DaemonPerfCounters.{cc,h}` by `35f6dd06dd0b`; not analysed as they are no longer in these files at HEAD |
