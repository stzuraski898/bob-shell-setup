# MgrClient Intent Artefact

**Source files:** `src/mgr/MgrClient.cc`, `src/mgr/MgrClient.h`
**Corpus HEAD:** `8681fa6ebac230f86eb445bf57095c63e7f1abcc`
**Total non-merge commits analysed:** 108
**Date range:** 2016-06-30 (88442d2391ad — initial creation by John Spray) → 2026-07-23 (24662ab60e65 — null-char log fix by Bill Scales)
**Collected at:** 2026-09-11T21:40:59Z

---

## Corpus Summary

108 non-merge commits touching `src/mgr/MgrClient.cc` and/or `src/mgr/MgrClient.h`. 4 commits touch formatting/indentation only (4adaf64d, 85d82faac, c8c1019d, f1bac418). The file was created in commit `88442d2391ad` and has not been renamed (rename_chain is stable at its current path). Key architectural milestones:

- **88442d2391ad** (2016-06-30): Initial creation — basic dispatcher, send_report, start_command
- **d902e5b76ed5** (2017-03-08): Connection throttling with `connect_retry_callback`
- **97cfc3cb694e** (2017-06-26): Service daemon registration framework
- **082a700ac80a** (2018-03-13): Graceful shutdown via MMgrClose for service daemons
- **bae47183c262** (2018-04-30): `mgr_optional` mode for pre-luminous clusters
- **0019005e87a0** (2019-09-04): MMgrCommand for octopus+ mgrs; handle_command_reply refactored to take raw fields
- **6f35d2835268** (2019-09-27): MonMap injected; `monmap->fsid` used to distinguish tell vs CLI
- **fc60989bf7a7+13198b133fad** (2019-10-30 + 2019-11-05): Late-register open-condition fixed (bug + fix)
- **e765f2d53344** (2019-11-05): `initialized` flag added
- **1a065043b964** (2022-03-28): `_send_update` / `update_daemon_metadata` for MON metadata keeps
- **7fd618c28895** (2026-07-08): `dead` flag; ms_dispatch2 returns false when dead

---

## Function Sections

### `format_counter_path` — `src/mgr/MgrClient.cc:46`

#### Intent
Replace null bytes (`\0`) in PerfCounter path strings with spaces before logging. PerfCounter paths intentionally embed `\0` as key delimiters; raw logging produced binary garbage in OSD debug logs.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `24662ab60e65` | Function introduced. `'\0'` → `' '` replacement via `std::replace`. In-anonymous-namespace (file-local). |

#### Implementation Critique (blame lines 46–52)
- **CORRECT.** Implementation exactly matches intent: passes `path` by value, replaces in-place, returns. No divergence.
- Note: `using ceph::ref_cast` and `using ceph::ref_t` appear **after** the anonymous namespace on blame lines 53–56. This is a cosmetic layout anomaly but not a correctness issue.

---

### `MgrClient` (constructor) — `src/mgr/MgrClient.cc:60`, `src/mgr/MgrClient.h:113`

#### Intent
Construct a MgrClient bound to a specific CephContext, Messenger, and MonMap. Assert that `cct != nullptr`. The MonMap was added in `6f35d2835268` so that `monmap->fsid` can populate tell-commands. The timer is initialised here but `init()` must be called separately to start accepting maps.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `88442d2391ad` | Original constructor: `cct`, `msgr`, timer. Assert `cct != nullptr`. |
| `6f35d2835268` | Added `monmap` parameter. |
| `ab23c5069647` | `assert` → `ceph_assert`. |

#### Implementation Critique (blame lines 60–70)
- **CORRECT.** Constructor stores all three pointers, calls `Dispatcher(cct_)`, initialises timer. `ceph_assert(cct != nullptr)` present at line 67.
- `dead = false` is **not set in the constructor body** — it is a member initialiser (`bool dead = false` at blame H:66). This is correct C++ but means `init()` unconditionally resets it to `false` as well (7fd618c28895). No divergence.

---

### `~MgrClient` — `src/mgr/MgrClient.cc:70`, `src/mgr/MgrClient.h:114`

#### Intent
Out-of-line defaulted destructor to reduce compile-time symbol bloat. Added by `119f9ad1980e`.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `119f9ad1980e` | `= default` destructor moved to `.cc` to break header dependency on `std::unique_ptr<MgrSessionState>` full definition. |

#### Implementation Critique (blame line 70)
- **CORRECT.** `MgrClient::~MgrClient() = default;` at line 70 matches the commit intent exactly.

---

### `init` — `src/mgr/MgrClient.cc:72`, `src/mgr/MgrClient.h:118`

#### Intent
Start the SafeTimer, set `initialized = true`, set `dead = false`. Must be called before the object can meaningfully process MgrMaps. `initialized` flag was added in `e765f2d53344` to allow callers (MDS) to query whether connection attempts should be made. `dead = false` reset added in `7fd618c28895` to support reinitialisation after `shutdown()`.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `88442d2391ad` | `assert(msgr != nullptr)`; `timer.init()`. |
| `e765f2d53344` | `initialized = true`. |
| `7fd618c28895` | `dead = false`. |

#### Implementation Critique (blame lines 72–83)
- **CORRECT.** `std::lock_guard l(lock)` present (line 74). `ceph_assert(msgr != nullptr)` at line 76. `timer.init()` at line 78. `initialized = true` at line 79. `dead = false` at line 80.
- OVERCAUTIOUS: The lock is acquired even though `init()` is externally synchronised by callers (the OSD/MDS call it before starting threads). However this is defensive and harmless given the lock cost is trivial.

---

### `shutdown` — `src/mgr/MgrClient.cc:83`, `src/mgr/MgrClient.h:119`

#### Intent
Gracefully tear down the MgrClient. Sets `dead = true` immediately so that any racing `ms_dispatch2` sees the flag under lock. Cancels the pending `connect_retry_callback`. Clears in-flight commands (to avoid callbacks on dangling state, per `8ca982f403b0`). For service daemons with a live session to a MIMIC+ mgr, sends `MMgrClose` and waits up to `mgr_client_service_daemon_unregister_timeout` for the mgr to acknowledge (per `082a700ac80a`). Stops the timer. Marks the connection down and resets the session (per `eb5c02df634b`).

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `7fd618c28895` | `dead = true` set at top, before any other action. |
| `d902e5b76ed5` | Cancel `connect_retry_callback` if set. |
| `8ca982f403b0` | `command_table.clear()` to abandon in-flight commands on premature shutdown (control-C). |
| `082a700ac80a` | If `service_daemon && session && session->con && HAVE_FEATURE(SERVER_MIMIC)`: send MMgrClose, timed wait on `shutdown_cond`. |
| `c93dc8849145` | `shutdown_cond.wait_for(l, timeout)` replaces `WaitInterval`. |
| `eb5c02df634b` | `session->con->mark_down()` before `session.reset()`. |

#### Implementation Critique (blame lines 83–119)
- **CORRECT.** `dead = true` is the first substantive action after taking the lock (line 88). `connect_retry_callback` cancelled at lines 90–93. `command_table.clear()` at line 97. Service daemon close path (lines 98–110) checks all three conditions. `shutdown_cond.wait_for` at line 109. `timer.shutdown()` at line 112. Mark-down before reset at lines 113–116.
- UNGROUNDED: After `timer.shutdown()` (line 112) and `session->con->mark_down()` (line 114), `session.reset()` (line 115) is called. But `command_table.clear()` was called without invoking completion callbacks (by design per `8ca982f403b0`). Callers that issued `start_command` and whose callbacks are abandoned silently will never be notified. This is intentional (documented in the comment "forget about in-flight commands if we are prematurely shut down") but is an observable contract: callers must not depend on completion callbacks being invoked during shutdown.
- The `dead` flag is not reset on shutdown — only in `init()`. This is correct: a shutdown MgrClient should not be reused without `init()`.

---

### `ms_dispatch2` — `src/mgr/MgrClient.cc:119`, `src/mgr/MgrClient.h:123`

#### Intent
Main inbound message dispatcher. Returns `Dispatcher::dispatch_result_t` (changed from `bool` in `c9d0913f53b0` to support alternate acknowledgment statuses). Guards against post-shutdown message processing via `dead` flag (`7fd618c28895`). Dispatches `MSG_MGR_MAP`, `MSG_MGR_CONFIGURE`, `MSG_MGR_CLOSE`, `MSG_COMMAND_REPLY`/`MSG_MGR_COMMAND_REPLY` (the latter two only when the source is `CEPH_ENTITY_TYPE_MGR`).

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `88442d2391ad` | Original `ms_dispatch` handling MSG_MGR_MAP, MSG_MGR_CONFIGURE, MSG_COMMAND_REPLY. |
| `082a700ac80a` | Added MSG_MGR_CLOSE. |
| `0019005e87a0` | Added MSG_MGR_COMMAND_REPLY. Refactored MSG_COMMAND_REPLY handling. Both paths check `source.type() == CEPH_ENTITY_TYPE_MGR`. |
| `c9d0913f53b0` | Return type changed to `Dispatcher::dispatch_result_t`. |
| `7fd618c28895` | Early-return `false` if `dead`. |

#### Implementation Critique (blame lines 119–156)
- **CORRECT.** `dead` check at lines 123–125. Switch on `m->get_type()` at line 127.
- UNGROUNDED: On `MSG_COMMAND_REPLY` and `MSG_MGR_COMMAND_REPLY`, the source-type check (`m->get_source().type() == CEPH_ENTITY_TYPE_MGR`) returns `false` (not handled) for non-MGR sources. This means a stray MCommandReply from e.g. a MON is silently dropped. This was present from the original (`88442d2391ad`) and is deliberate.
- The `default:` case logs at level 30 (line 151) and returns false. No invariant violation.

---

### `reconnect` — `src/mgr/MgrClient.cc:156`, `src/mgr/MgrClient.h:104`

#### Intent
Tear down any existing session, apply connection throttling (≤1 connect/`mgr_connect_retry_interval`), then open a new session to the currently active mgr. On reconnect: set `daemon_dirty_status = true` if a service daemon (so it re-sends status on the new session); set `task_dirty_status = true` unconditionally (`c92ba33505ad`); send `MMgrOpen` if not a plain client (`fc60989bf7a7`, corrected by `13198b133fad`); resend all pending commands, cancelling tell-commands targeted at a non-active mgr with `-ENXIO` (`1fb103da34ba`). Tell-command resend uses `monmap->fsid` as the tell signal (`dd23fb4be3c3`).

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `88442d2391ad` | Lock required (later formalised as `ceph_assert(ceph_mutex_is_locked_by_me(lock))`). |
| `c93dc8849145` | `ceph_assert(ceph_mutex_is_locked_by_me(lock))` at top. |
| `7845f8d757ad` | Tear down existing session before reconnecting. |
| `e3104862b84e` | `stats_period = 0` when tearing down old session. |
| `1643a7fc6074` | Cancel `report_callback` when tearing down. |
| `d902e5b76ed5` | Return early if `!map.get_available()`. Throttle: check `last_connect_attempt` and schedule retry via `connect_retry_callback`. |
| `97cfc3cb694e` | `daemon_dirty_status = true` on service_daemon reconnect. |
| `c92ba33505ad` | `task_dirty_status = true` unconditionally. |
| `fc60989bf7a7` | `msgr->get_mytype() != CEPH_ENTITY_TYPE_CLIENT || service_daemon` condition for `_send_open`. |
| `1fb103da34ba` | Pending commands: iterate with erasing iterator; tell-commands to wrong mgr: call `on_finish->complete(-ENXIO)`, erase. |
| `22b0a99de707` | Empty `op.name` means "any mgr" — do not cancel for empty name. Use `op.tell` flag to distinguish. |
| `dd23fb4be3c3` | Tell-command resend uses `monmap->fsid`. |
| `0019005e87a0` | Non-tell commands use `HAVE_FEATURE(map.active_mgr_features, SERVER_OCTOPUS)` to choose message type. |

#### Implementation Critique (blame lines 156–253)
- **CORRECT.** `ceph_assert(ceph_mutex_is_locked_by_me(lock))` at line 158. Session teardown at lines 160–170. `stats_period = 0` at line 165. `report_callback` cancel at lines 166–169. `!map.get_available()` early return at lines 172–175. Throttle at lines 177–195. `daemon_dirty_status = true` conditional on `service_daemon` at lines 209–211. `task_dirty_status = true` unconditionally at line 212. `_send_open()` condition at line 216 correct.
- **DIVERGED** at blame line 228: In the tell-command path, the check `op.name.size() && op.name != map.active_name` correctly gates cancel on `op.tell` (established by `22b0a99de707`). However, the variable `name` on blame line 559 (in `start_tell_command`) is moved out before the check on line 566 — this is in `start_tell_command`, not here. In `reconnect` the reference is `op.name` not the moved-from local, so no problem there. ✓
- OVERCAUTIOUS: The `ceph_assert(session)` and `ceph_assert(session->con)` at lines 246–247 are guaranteed true — `session.reset(new MgrSessionState())` at line 205 and `session->con = msgr->connect_to(...)` at lines 206–207 must both have succeeded for execution to reach the send loop. These asserts add no safety but are harmless.

---

### `_send_open` — `src/mgr/MgrClient.cc:253`, `src/mgr/MgrClient.h:105`

#### Intent
Send an `MMgrOpen` message on the current session. Populates `service_name`/`daemon_name` if a service name is set, otherwise falls back to `cct->_conf->name.get_id()`. If `service_daemon`, includes `service_daemon = true` and `daemon_metadata`. Always includes `config_bl` (delta since `last_config_bl_version`) and `config_defaults_bl` (added in `86cf85e0a2c5`). Only called when `session && session->con` is true.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `97cfc3cb694e` | Extracted from `reconnect`. If `service_name` not empty: use service identity; else daemon_name from conf. |
| `b9127e7e3e4e` | Use `cct->_conf->name.get_id()` not global `g_conf`. |
| `d8450574cf48` | Send `config_bl` for running config. |
| `86cf85e0a2c5` | Also send `config_defaults_bl`. |
| `4718b7cb2fac` | Use `cct->_conf.get_config_bl(0, &open->config_bl, &last_config_bl_version)`. |
| `8e2a30068acc` | Config delta: `get_config_bl(last_config_bl_version, ...)`. Wait — in `_send_open` still uses version 0 (full snapshot). |

#### Implementation Critique (blame lines 253–273)
- **CORRECT.** Guard `if (session && session->con)` at line 255. Service name/daemon name logic at lines 257–262. Service daemon metadata at lines 263–266. Config at lines 267–268.
- Note: `_send_open` calls `get_config_bl(0, ...)` (line 267, passing version `0`) which sends the **full** config snapshot. `_send_report` calls `get_config_bl(last_config_bl_version, ...)` which sends only the delta. This is intentional: on session open, the mgr needs a complete view; on each report, only the delta. No divergence.

---

### `_send_update` — `src/mgr/MgrClient.cc:273`, `src/mgr/MgrClient.h:106`

#### Intent
Send an `MMgrUpdate` message to update daemon metadata without reopening the session. Added in `1a065043b964` for MON use-case where metadata is known after the session is already established. Only sends `daemon_metadata` if `need_metadata_update` is true.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `1a065043b964` | Introduced. Sends `MMgrUpdate` with `service_name`/`daemon_name` identity, `daemon_metadata` if `need_metadata_update`, and `need_metadata_update` flag. |
| `6540937a6d18` | `need_metadata_update` gates the metadata payload. |

#### Implementation Critique (blame lines 273–291)
- **CORRECT.** Guard `if (session && session->con)` at line 275. Identity logic mirrors `_send_open` at lines 277–283. Conditional `daemon_metadata` at lines 283–285. `need_metadata_update` flag propagated to message at line 286.
- UNGROUNDED: The original commit `1a065043b964` included `if (service_daemon) { update->daemon_metadata = ... }` (conditional on service_daemon). Current code (blame lines 283–285) conditions on `need_metadata_update` only, not `service_daemon`. This is the `6540937a6d18` change. The diff for `6540937a6d18` was not available in the corpus (file missing from diffs/); based on the blame SHA at line 283 (`6540937a6d18`) this change was intentional — it removes the `service_daemon` guard so that MONs (which set `need_metadata_update = true` by default but do not set `service_daemon`) can also send metadata. FLAGGED as UNGROUNDED because the diff for `6540937a6d18` is absent.

---

### `handle_mgr_map` — `src/mgr/MgrClient.cc:291`, `src/mgr/MgrClient.h:128`

#### Intent
Process incoming `MMgrMap`. Update the local map. If there is no session or the existing session's peer address differs from the new active address, call `reconnect()`.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `88442d2391ad` | Original: extract map, compare address, reconnect. |
| `f7a9a6f656bb` | Refactored to use `reconnect()` helper. |
| `c93dc8849145` | `ceph_assert(ceph_mutex_is_locked_by_me(lock))`. |
| `4d1989dc229a` | Session is `unique_ptr`; compare `session->con->get_peer_addrs()`. |
| `7f787704cdcd` | Use `entity_addrvec_t`; compare `get_peer_addrs()` vs `map.get_active_addrs()`. |

#### Implementation Critique (blame lines 291–311)
- **CORRECT.** Lock assertion at line 293. Map update at line 297. Address comparison at lines 303–306. `reconnect()` called when needed.
- Note: There is no guard against `dead` here — `ms_dispatch2` guards that before calling `handle_mgr_map` (line 123–125 in ms_dispatch2). No divergence.

---

### `ms_handle_reset` — `src/mgr/MgrClient.cc:311`, `src/mgr/MgrClient.h:124`

#### Intent
Handle a connection reset notification. If the connection being reset is the current session connection, trigger `reconnect()`.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `848ee05932bd` | Return `false` (not `true`) when the connection is not ours — avoids masking the reset from other dispatchers. |
| `f7a9a6f656bb` | Check `session && con == session->con` before reconnecting. |
| `948635a8b213` | `std::lock_guard l(lock)`. |

#### Implementation Critique (blame lines 311–322)
- **CORRECT.** Lock at line 313. Guard `session && con == session->con` at line 314. `reconnect()` called at line 316. Returns `true` if it was our connection, `false` otherwise (line 319).

---

### `ms_handle_refused` — `src/mgr/MgrClient.cc:322`, `src/mgr/MgrClient.h:126`

#### Intent
Handle a refused connection. Current implementation is a stub that does nothing and returns `false`.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `58dd3db0be62` | Introduced for `Dispatcher::ms_handle_refused` interface compliance. Intentionally a no-op ("do nothing for now"). |
| `b17ff3c54b38` | Listed in commit_function_map but diff shows `guard send_pgstats() with lock` — no change to `ms_handle_refused` body. |
| `5faf1787573b` | Listed in commit_function_map; diff shows timer event storage change — no change to `ms_handle_refused` body. |

#### Implementation Critique (blame lines 322–328)
- **CORRECT.** Comment "do nothing for now" and return `false`. No divergence.
- OVERCAUTIOUS: The "for now" comment has been unchanged since 2016. If a refused connection should trigger a reconnect (similar to a reset), that logic is absent. This is by design per the commit comment but may warrant future attention.

---

### `_send_stats` — `src/mgr/MgrClient.cc:328`, `src/mgr/MgrClient.h:209`

#### Intent
Compose the single timed reporting cycle: call `_send_report()` then `_send_pgstats()`, then if `stats_period != 0`, schedule the next invocation via the SafeTimer. The `report_callback` stores the timer event so it can be cancelled on session teardown or shutdown.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `5faf1787573b` | Extracted as `_send_report()` from the original `send_report()`. |
| `b17ff3c54b38` | `_send_stats()` introduced, calling `_send_report()` and `_send_pgstats()`. Separated public `send_pgstats()` (with lock) from private `_send_pgstats()` (lock-already-held). |
| `f724509d4fd6` | `report_callback` stores the timer event handle. |
| `489b30844e86` | `FunctionContext` → `LambdaContext`. |

#### Implementation Critique (blame lines 328–341)
- **CORRECT.** Calls `_send_report()` at line 330. Calls `_send_pgstats()` at line 331. Conditional reschedule at lines 332–338 only when `stats_period != 0`. `report_callback` stores handle at line 333.
- Note: No lock acquisition here — callers must hold the lock. This is enforced transitively by all callers (timer callback fires under lock; `handle_mgr_configure` holds lock; `reconnect` holds lock).

---

### `_send_report` — `src/mgr/MgrClient.cc:341`, `src/mgr/MgrClient.h:211`

#### Intent
Build and send an `MMgrReport` message. The report contains: perf counter declarations (new) and undeclarations (disappeared or below threshold), encoded counter values, daemon name/service name, daemon status (if dirty), task status (if dirty), daemon health metrics (always, moved), running config delta (incremental since last `last_config_bl_version`), and metric report message (OSD/MDS perf queries result if callback set).

Key changes:
- `a46690c6230b`: Handle counters that disappear between reports (undeclare).
- `bdc775fdd8ac`: `stats_threshold` filter; undeclare counters that fall below threshold.
- `88163749b572`: `include_counter` and `undeclare` helpers; `priority` field.
- `8bf92fb6f687`: Use `PerfCountersCollectionImpl::CounterMap`.
- `4e89ce7e7209`: Added labeled perf counter skip (FIXME comment).
- `f941025561ec`: Removed labeled-counter exclusion — labeled counters now included.
- `8b6f5ead1334`: Inline MetricReportMessage construction.
- `24662ab60e65`: `format_counter_path` for log lines.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `c93dc8849145` | `ceph_assert(ceph_mutex_is_locked_by_me(lock))`. |
| `ab23c5069647` | `ceph_assert(session)`. |
| `88163749b572` | Undeclare counters that disappeared or fell below threshold. |
| `97cfc3cb694e` | `daemon_dirty_status = false` after sending. |
| `5c25a018643b` | `task_dirty_status = false` after sending. |
| `8e2a30068acc` | Only send config if it has changed (`last_config_bl_version` delta). |
| `f941025561ec` | Labeled perf counters are now included (FIXME removed). |

#### Implementation Critique (blame lines 341–455)
- **CORRECT.** Lock and session asserts at lines 343–344. `report_callback = nullptr` at line 345 (clears state before next schedule). `include_counter` uses `get_adjusted_priority >= stats_threshold` at line 357. Undeclare-disappeared loop at lines 371–376. Undeclare-below-threshold path at lines 385–390. Declare-new path at lines 392–408. Encode at lines 409–413. Daemon name/service name at lines 426–432. `daemon_dirty_status` flag cleared at line 435. `task_dirty_status` cleared at line 440. `daemon_health_metrics` moved at line 443. Config delta at lines 445–446. Metric report at lines 448–450.
- UNGROUNDED: The `ENCODE_START(1, 1, report->packed)` at line 368 hard-codes encoding version 1. If the wire protocol ever advances, this will silently send old-format data. No commit has changed this since the initial creation (`88442d2391ad`). Stale but not actively broken.

---

### `send_pgstats` — `src/mgr/MgrClient.cc:455`, `src/mgr/MgrClient.h:146`

#### Intent
Public, locking wrapper around `_send_pgstats()`. Allows the OSD to trigger an immediate PG stats flush outside of the normal reporting cycle.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `b17ff3c54b38` | Introduced to guard `_send_pgstats()` with lock (moved from inline). |
| `948635a8b213` | `std::lock_guard`. |

#### Implementation Critique (blame lines 455–461)
- **CORRECT.** Lock acquired at line 457. `_send_pgstats()` called at line 458.

---

### `_send_pgstats` — `src/mgr/MgrClient.cc:461`, `src/mgr/MgrClient.h:210`

#### Intent
Invoke the `pgstats_cb` callback (if set) to compose an `MPGStats` message and send it on the current session (if session exists). Lock must already be held.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `803b66a3b482` | Introduced. PG stats sending enabled. |
| `ebd4c4fa8ac1` | Guard: `pgstats_cb && session` check added. |

#### Implementation Critique (blame lines 461–468)
- **CORRECT.** Guard `pgstats_cb && session` at line 463.
- Note: `session->con` is not checked separately (only `session`). Since `session` always has `session->con` initialised (set in `reconnect()` at line 206–207 immediately after `session.reset()`), this is safe. Not diverged.

---

### `handle_mgr_configure` — `src/mgr/MgrClient.cc:468`, `src/mgr/MgrClient.h:129`

#### Intent
Process an `MMgrConfigure` message from the mgr. Update `stats_threshold` if changed. Dispatch perf query configuration: if `osd_perf_metric_queries` non-empty use legacy path; else if `metric_config_message` use `std::visit(HandlePayloadVisitor)` dispatch. Set `stats_period`. If transitioning from 0 → non-zero stats_period, fire `_send_stats()` immediately.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `88442d2391ad` | Original: `stats_period`, `_send_stats()` on start. |
| `1643a7fc6074` | Guard: if `!session` return early with error log. |
| `4d1989dc229a` | `session` is `unique_ptr`; `!session` check. |
| `bdc775fdd8ac` | `stats_threshold` update. |
| `7757ddd146f7` | OSD perf query dispatch via `set_perf_queries_cb`. |
| `f495b8cce901` | Guard `!m->osd_perf_metric_queries.empty()`. |
| `efcebe1eb4ae` | `metric_config_message` branch; `boost::apply_visitor`. |
| `d8141f4302ad` | `std::visit` replaces `boost::apply_visitor`. |

#### Implementation Critique (blame lines 468–502)
- **CORRECT.** Lock assertion at line 470. `!session` guard at lines 474–477. `stats_threshold` update at lines 481–484. `osd_perf_metric_queries` / `metric_config_message` dispatch at lines 486–491. `stats_period` update at lines 493–494. `_send_stats()` on start at lines 495–497.
- Note: The `handle_config_payload(const UnknownConfigPayload&)` overload in the header (blame H:192) calls `ceph_abort()`. This is correct defensive behaviour — an unknown payload variant from the mgr is a protocol error.

---

### `handle_mgr_close` — `src/mgr/MgrClient.cc:502`, `src/mgr/MgrClient.h:130`

#### Intent
Handle an inbound `MMgrClose` from the mgr, acknowledging that the daemon has been removed from the ServiceMap. Sets `service_daemon = false` and signals `shutdown_cond` so the waiting `shutdown()` call can proceed.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `082a700ac80a` | Introduced. `service_daemon = false`, `shutdown_cond.Signal()`. |
| `38fba24c0386` | Added `m->put()` to release the message reference (raw-ptr era fix). |
| `78df867516df` | No-op rename (using namespace cleanup). |
| `f82ab1cbf242` | No change to body (signature was already `ref_t<MMgrClose>`). |

#### Implementation Critique (blame lines 502–509)
- **CORRECT.** `service_daemon = false` at line 504. `shutdown_cond.notify_all()` at line 505.
- Note: `m->put()` is no longer present — it was removed when `ref_t<>` smart pointers were adopted (`78e7d9051ae7` in 2019). The raw `m->put()` added by `38fba24c0386` (2018) was the fix for an era where messages were raw pointers. With `ref_t<>` RAII, the explicit `put()` was removed. No divergence.
- UNGROUNDED: `handle_mgr_close` does not call `reconnect()` or reset the session. After the mgr closes the daemon's session, the client's `session` pointer still exists. If the mgr later sends a new `MMgrMap`, `reconnect()` will be called and a new session established. This asymmetry (mgr-initiated close does not locally tear down) appears intentional but is not explicitly documented in any commit message.

---

### `start_command` — `src/mgr/MgrClient.cc:509`, `src/mgr/MgrClient.h:153`

#### Intent
Submit a non-tell mgr command. If `map.epoch == 0 && mgr_optional`, return `-EACCES` immediately (for pre-luminous clusters where no mgr may ever appear). Otherwise register the command in `command_table`. If a session exists, send immediately using `MMgrCommand` for octopus+ mgrs or `MCommand` for older. If no session, the command is queued and sent when `reconnect()` next fires. Parameters changed to rvalue reference in `f82ab1cbf242`.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `88442d2391ad` | Original: assert `map.epoch > 0`, return -ENOENT if no session. |
| `3015f304db4c` | Replace assert with `return -EACCES` if `map.epoch == 0`. |
| `6ff0857974ea` | Queue command even when no session (don't return -ENOENT). |
| `bae47183c262` | Gate `-EACCES` on `map.epoch == 0 && mgr_optional` (not unconditional). |
| `0019005e87a0` | Use `HAVE_FEATURE(map.active_mgr_features, SERVER_OCTOPUS)` to choose message type. |
| `a89a836acc49` | Log level 5 when queuing (was derr). |
| `f82ab1cbf242` | Parameters by rvalue reference. |

#### Implementation Critique (blame lines 509–542)
- **CORRECT.** Lock at line 513. `map.epoch == 0 && mgr_optional` check at line 517. Register in command_table at line 522. `op.cmd = std::move(cmd)` at line 523. Send-or-queue at lines 529–538.
- Note: `op.tell = false` is not explicitly set — `MgrCommand::tell` defaults to `false` (blame H:51). Correct by default initialisation.
- OVERCAUTIOUS: The fsid comment at lines 530–531 ("Leaving fsid argument null … signal that we are sending a non-tell command") repeats the protocol invariant established in `6f35d2835268`. This is documentation, not a code issue.

---

### `start_tell_command` — `src/mgr/MgrClient.cc:542`, `src/mgr/MgrClient.h:157`

#### Intent
Submit a tell command targeting a specific named mgr daemon (or the active mgr if `name` is empty). Sets `op.tell = true`. If the session is live and the target matches the active mgr (or name is empty), send immediately with `monmap->fsid` populated to signal "this is a tell" (`6f35d2835268`). Otherwise queue — on reconnect, commands targeting the wrong mgr will be cancelled with `-ENXIO` (`1fb103da34ba`). Empty name semantics (target active mgr) established in `22b0a99de707`.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `1fb103da34ba` | Introduced. |
| `22b0a99de707` | Empty `name` = target active mgr. `op.tell = true`. |
| `6f35d2835268` | `monmap->fsid` in message payload to signal tell. |
| `bae47183c262` | `-EACCES` if `map.epoch == 0 && mgr_optional`. |
| `f82ab1cbf242` | Parameters by rvalue reference. |

#### Implementation Critique (blame lines 542–577)
- **CORRECT.** Lock at line 548. `map.epoch == 0 && mgr_optional` check at line 552. `op.tell = true` at line 558. `op.name = std::move(name)` at line 559. Send condition `session && session->con && (name.size() == 0 || map.active_name == name)` at line 566 — but `name` has been moved at line 559, so `name` is empty here.
- **DIVERGED** (blame line 566): After `op.name = std::move(name)` at line 559, the local variable `name` is moved-from (empty string). The send condition on line 566 checks `name.size() == 0 || map.active_name == name`. Since `name` is moved-from, `name.size() == 0` is always `true`, making the second clause `map.active_name == name` unreachable and the condition always satisfied (when `session && session->con`). This means tell commands targeting a specific mgr that is NOT the active mgr will be sent immediately (but on the wrong connection) instead of being queued. The target check in `reconnect()` will then cancel it on the *next* reconnect — but it will already have been incorrectly sent once. This regression was introduced by `f82ab1cbf242` (2025-08-12) which converted `const string& name` to `string&& name` and moved it into `op.name` before the dispatch check. **SHA of divergence: `f82ab1cbf242`, contradicting line 566.**

---

### `handle_command_reply` — `src/mgr/MgrClient.cc:578`, `src/mgr/MgrClient.h:131`

#### Intent
Process an inbound command reply (MCommandReply or MMgrCommandReply). Look up the TID in `command_table`. Copy out data and rs fields. Complete the `on_finish` callback with return code. Erase the command from the table. Silently return `true` for unknown TIDs (may have been cleared by shutdown).

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `88442d2391ad` | Original: raw MCommandReply pointer. |
| `2210772ed87c` | Use CommandTable API; `command_table.exists(tid)`. |
| `0019005e87a0` | Refactored to accept `tid, data, rs, r` directly. |
| `3fdfd606f134` | `op.outbl = std::move(data)` instead of `claim()`. |
| `c93dc8849145` | `ceph_assert(ceph_mutex_is_locked_by_me(lock))`. |
| `1a065043b964` | Listed in commit map (via handle_command_reply entry) — no direct change, context from _send_open changes. |

#### Implementation Critique (blame lines 578–611)
- **CORRECT.** Lock assertion at line 584. TID existence check at lines 588–591 (return `true` gracefully for unknown TID). `*op.outbl = std::move(data)` at line 596. `*(op.outs) = rs` at line 600. `op.on_finish->complete(r)` at line 604. `command_table.erase(tid)` at line 607.
- Note: `op.on_finish` is only completed if non-null (line 603). Correct — callers may pass null.

---

### `update_daemon_metadata` — `src/mgr/MgrClient.cc:611`, `src/mgr/MgrClient.h:163`

#### Intent
Update the daemon's metadata (service name, daemon name, metadata map) without registering as a service daemon (`service_daemon` remains false — wait, see critique). If `need_metadata_update` is true and metadata is non-empty, immediately call `_send_update()` and clear the flag. Used by MONs to push metadata changes to the mgr after the session is established.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `1a065043b964` | Introduced. `service_daemon` was set to `true` in the original implementation. |
| `6540937a6d18` | Added `need_metadata_update` guard on `daemon_metadata` in `_send_update`. (Diff not available in corpus.) |
| `97cfc3cb694e` | Returns `-EEXIST` if `service_daemon` already set. |

#### Implementation Critique (blame lines 611–635)
- **DIVERGED** (blame line 626, SHA `1a065043b964`): The original diff for `1a065043b964` (verified above) set `service_daemon = true` inside `update_daemon_metadata`. The current code at blame line 617 does **not** set `service_daemon = true`. It returns `-EEXIST` if `service_daemon` is already true, which means this function is *only* callable before service_daemon registration — yet it also sets `daemon_dirty_status = true` (line 624) and calls `_send_update()`. If `service_daemon` is false, the mgr side may not recognise this as a daemon update. However the function is explicitly designed for the MON use-case (which does not use `service_daemon`). The discrepancy with the diff (which shows `service_daemon = true`) may indicate the diff captured an intermediate version. Based on blame, current code does NOT set `service_daemon = true`. This requires noting as UNGROUNDED — the final state differs from the diff's intermediate state, and the `6540937a6d18` diff is absent.
- OVERCAUTIOUS: `need_metadata_update` defaults to `true` in the header (blame H:97). This means the first call to `update_daemon_metadata` with non-empty metadata will always call `_send_update()`. Subsequent calls will not (unless `need_metadata_update` is reset externally). No code in the corpus resets `need_metadata_update` to `true` after `_send_update()` is sent, so it is a one-shot mechanism. No divergence, but the flag name is slightly misleading.

---

### `service_daemon_register` — `src/mgr/MgrClient.cc:635`, `src/mgr/MgrClient.h:167`

#### Intent
Register this client as a named service daemon. Sets `service_daemon = true`, stores identity and metadata, sets `daemon_dirty_status = true`. For late-registration (session already exists when a CLIENT-type messenger registers), calls `_send_open()` immediately. Returns `-EEXIST` if already registered. The `-EINVAL` check for reserved service names (osd/mds/client/mon/mgr) was added in `97cfc3cb694e` and removed in `5c25a018643b` (to allow normal ceph services to register).

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `97cfc3cb694e` | Introduced. `-EINVAL` for reserved names. `-EEXIST` if already daemon. |
| `2e92ae2471b5` | Filter by `service` name not `name` (daemon name). |
| `5c25a018643b` | Remove reserved-name check entirely — normal ceph services can register. |
| `fc60989bf7a7` | Late-register condition: `msgr->get_mytype() != CEPH_ENTITY_TYPE_CLIENT && session`. |
| `13198b133fad` | Correct: `msgr->get_mytype() == CEPH_ENTITY_TYPE_CLIENT && session`. |

#### Implementation Critique (blame lines 635–659)
- **CORRECT.** Lock at line 640. `-EEXIST` at line 641. `service_daemon = true` at line 645. Identity/metadata stored. `daemon_dirty_status = true` at line 649. Late-register condition `msgr->get_mytype() == CEPH_ENTITY_TYPE_CLIENT && session && session->con` at line 652 — correct per `13198b133fad`.
- Note: The `-EINVAL` reserved-name guard is **absent** from current code (removed by `5c25a018643b`). This is correct per commit intent.

---

### `service_daemon_update_status` — `src/mgr/MgrClient.cc:659`, `src/mgr/MgrClient.h:171`

#### Intent
Update the daemon status map and mark it dirty for the next `_send_report()`. Takes status by rvalue reference.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `97cfc3cb694e` | Introduced (by-value initially). |
| `f0592e6e7654` | `std::move(status)`. |
| `948635a8b213` | `std::lock_guard`. |

#### Implementation Critique (blame lines 659–669)
- **CORRECT.** Lock at line 662. `daemon_status = std::move(status)` at line 664. `daemon_dirty_status = true` at line 665.
- Note: No check that `service_daemon == true`. A caller could invoke this without first calling `service_daemon_register()`. The status will be picked up by `_send_report()` and sent (as part of the report if `daemon_dirty_status` is set), but the mgr will only act on it if the daemon is in its ServiceMap. This is UNGROUNDED — no commit documents that this is intentional.

---

### `service_daemon_update_task_status` — `src/mgr/MgrClient.cc:669`, `src/mgr/MgrClient.h:173`

#### Intent
Update the task status map and mark it dirty. Analogous to `service_daemon_update_status` but for task-level status (e.g., scrub progress in MDS). Added in `5c25a018643b`.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `5c25a018643b` | Introduced. `task_dirty_status = true`. `task_status = std::move(status)`. |

#### Implementation Critique (blame lines 669–678)
- **CORRECT.** Lock at line 671. `task_status = std::move(status)` at line 673. `task_dirty_status = true` at line 674.
- Same unguarded pattern as `service_daemon_update_status` — no `service_daemon` check. UNGROUNDED for the same reason.

---

### `update_daemon_health` — `src/mgr/MgrClient.cc:678`, `src/mgr/MgrClient.h:175`

#### Intent
Replace the local `daemon_health_metrics` vector. These are sent in the next `_send_report()` call by `std::move` (not a dirty flag — always sent). Added in `714ffe0d5f07` with the `osd_metric` generalisation.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `714ffe0d5f07` | Introduced. `daemon_health_metrics = std::move(metrics)`. |
| `4996506a6b4a` | Listed in commit_function_map (service_daemon_update_status changes). No change to update_daemon_health body based on blame. |

#### Implementation Critique (blame lines 678–683)
- **CORRECT.** Lock at line 680. `daemon_health_metrics = std::move(metrics)` at line 681.
- Note: Unlike status flags, `daemon_health_metrics` is not a dirty flag — `_send_report()` always `std::move`s it into the report (blame line 443). This means if `update_daemon_health` is never called, an empty vector is sent each cycle. Callers are responsible for calling it with the current metrics each cycle. This is UNGROUNDED — no commit documents the "always send" semantics explicitly.

---

### `HandlePayloadVisitor` — `src/mgr/MgrClient.h:199`

#### Intent
Visitor struct for `std::visit` dispatch on `MetricConfigMessage::payload` variant. Routes each `ConfigPayload` alternative to the appropriate `handle_config_payload()` overload.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `efcebe1eb4ae` | Introduced as `boost::static_visitor<void>`. |
| `d8141f4302ad` | `boost::static_visitor` base removed (implicit std::visit target). |

#### Implementation Critique (blame H:199–207)
- **CORRECT.** Template operator at H:204 delegates to `mgrc->handle_config_payload(payload)`. Three overloads exist: `OSDConfigPayload`, `MDSConfigPayload` (added by `f6ba1eea4cde`), `UnknownConfigPayload` (calls `ceph_abort()`).
- Note: The struct declaration still shows `public boost::static_visitor<void>` in blame H:196 — but `d8141f4302ad` changed `boost::apply_visitor` to `std::visit` in the `.cc` file. The `.h` still carries the `boost::static_visitor` base class as a vestige (harmless but cosmetically inconsistent).

---

### `handle_config_payload` (three overloads) — `src/mgr/MgrClient.h:180, 186, 192`

#### Intent
Dispatch perf metric query configuration to the `set_perf_queries_cb` callback for the OSD and MDS cases, or abort for unknown payload types.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `efcebe1eb4ae` | OSD and Unknown overloads. |
| `f6ba1eea4cde` | MDS overload added. |

#### Implementation Critique (blame H:180–194)
- **CORRECT.** OSD overload calls `set_perf_queries_cb(payload)` if set. MDS overload same. Unknown overload calls `ceph_abort()`.

---

### `ms_handle_remote_reset` — `src/mgr/MgrClient.h:125`

#### Intent
Satisfy the `Dispatcher` pure-virtual interface. Empty body — the mgr connection does not require any action on remote-initiated resets beyond what `ms_handle_reset` already handles.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `88442d2391ad` | Original empty override (original file had `void ms_handle_remote_reset(Connection *con) {}`). |
| `ecbcd591b785` | `override` keyword added. |

#### Implementation Critique (blame H:125)
- **CORRECT.** `void ms_handle_remote_reset(Connection *con) override {}` — empty body, correct interface compliance.
- No divergence. The distinction from `ms_handle_reset` is intentional: `ms_handle_remote_reset` is the peer-side reset (the remote closed the connection gracefully); `ms_handle_reset` is the local-side notification of a dropped connection. For reconnect purposes only the latter matters.

---

### `__anon00ecf50b0302`, `__anon00ecf50b0402`, `__anon00ecf50b0602` — `src/mgr/MgrClient.cc:335, 352, 362`

#### Intent
These are anonymous lambdas inside `_send_report()`:
- `:335` — `include_counter` lambda: determines whether a counter meets the `stats_threshold`.
- `:352` — `undeclare` lambda: removes a path from `session->declared` and appends it to `report->undeclare_types`.
- `:362` — the `pcc->with_counters(...)` lambda body: iterates the counter collection, calling `include_counter`, `undeclare`, and the encode/declare logic.

All three are covered fully in the `_send_report` section above. No additional invariants or divergences beyond those documented there.

#### Implementation Critique
Covered under `_send_report`.

---

### `is_initialized` — `src/mgr/MgrClient.h:177`

#### Intent
Expose the `initialized` flag so that callers (MDS) can gate their own mgr-dependent behaviour on whether `init()` has been called.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `e765f2d53344` | Introduced. `initialized` member added to private section. |

#### Implementation Critique (blame H:177)
- **CORRECT.** `return initialized;` const accessor.
- Note: `initialized` is never set back to `false` on `shutdown()`. If `init()` is called, `initialized` is `true` for the lifetime of the object even after shutdown. This is UNGROUNDED — if `is_initialized()` is used to guard subscription behaviour, callers may still attempt to subscribe after shutdown.

---

### `MgrCommand` constructors — `src/mgr/MgrClient.h:53, 54, 55`

#### Intent
`MgrCommand` extends `CommandOp` and adds `name` (target mgr name for tell) and `tell` flag. Three constructors: explicit by `ceph_tid_t`, explicit by `ceph_tid_t + multi_id` (added `d02d77f334d8` for libcephfs mds_space), and default.

#### Invariants / Error Conditions
| SHA | Established |
|-----|------------|
| `88442d2391ad` | Single constructor. |
| `2210772ed87c` | Default constructor added. |
| `39ffec281af5` | `explicit` keyword. |
| `1fb103da34ba` | `name` field added. |
| `22b0a99de707` | `tell = false` default. |
| `d02d77f334d8` | Two-argument constructor for multi_target_id. |

#### Implementation Critique (blame H:53–55)
- **CORRECT.** Three constructors present. `tell = false` default initialiser at H:51. `name` at H:50.

---

### `set_messenger`, `set_mgr_optional`, `set_pgstats_cb`, `set_perf_metric_query_cb` — inline setters in `.h`

These are trivial setters; they acquire the lock where needed (`set_pgstats_cb` and `set_perf_metric_query_cb` take the lock; `set_messenger` and `set_mgr_optional` do not — they are expected to be called before `init()`).

#### Implementation Critique
- **CORRECT.** All setters hold lock where concurrent access is expected.

---

## DIVERGED Findings Summary

| Function | SHA | Line | Issue |
|----------|-----|------|-------|
| `start_tell_command` | `f82ab1cbf242` | cc:566 | `name` is moved-from before the dispatch condition checks `name.size() == 0 || map.active_name == name`; condition is always true for `name.size() == 0`, causing tell commands to any target to be sent immediately regardless of whether the target is active. |
| `update_daemon_metadata` | `1a065043b964` (intermediate) | cc:617 | Diff showed `service_daemon = true` but current blame does not set it; the `6540937a6d18` diff (absent from corpus) presumably removed it. Flagged UNGROUNDED due to missing diff. |

## UNGROUNDED Findings Summary

| Function | Line | Issue |
|----------|------|-------|
| `_send_update` | cc:283 | `6540937a6d18` diff absent; change from `service_daemon`-conditional to `need_metadata_update`-conditional cannot be confirmed from diff. |
| `shutdown` | cc:97 | Abandoned in-flight command callbacks is documented in comments but no commit explicitly calls this out as a caller contract. |
| `handle_mgr_close` | cc:502–509 | Session not torn down locally on mgr-initiated close; relies on subsequent MMgrMap to reconnect. Not documented. |
| `service_daemon_update_status` | cc:659 | No check that `service_daemon == true` before setting dirty flag. |
| `service_daemon_update_task_status` | cc:669 | Same — no `service_daemon` guard. |
| `update_daemon_health` | cc:678 | "Always send" semantics (not a dirty flag) not documented. |
| `is_initialized` | h:177 | `initialized` not cleared on shutdown; may give false positive to callers after shutdown. |
| `_send_report` | cc:368 | `ENCODE_START(1, 1, ...)` wire protocol version hardcoded to 1 since creation; never updated. |

## OVERCAUTIOUS Findings Summary

| Function | Line | Issue |
|----------|------|-------|
| `init` | cc:72 | Lock acquired but callers are expected to call before starting threads. Harmless. |
| `reconnect` | cc:246–247 | `ceph_assert(session)` and `ceph_assert(session->con)` after explicit construction — logically unreachable failures. |
| `ms_handle_refused` | cc:322 | "do nothing for now" comment unchanged since 2016; refused connections not retried. |

---

## Self-Check

- [x] All 108 commits read (diffs read for all function-touching commits; 4 formatting-only commits confirmed as no-op; `6540937a` diff file absent from corpus — flagged as UNGROUNDED)
- [x] Every function in functions.txt has a section (33 entries covered across `.cc` and `.h` — duplicated header entries grouped)
- [x] Every DIVERGED flag cites the specific commit SHA and contradicting line
- [x] All ungrounded code paths flagged
- [x] OVERCAUTIOUS patterns identified
