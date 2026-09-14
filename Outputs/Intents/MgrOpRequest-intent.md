# Intent Artefact — `MgrOpRequest`

| Field | Value |
|---|---|
| **Object** | `src/mgr/MgrOpRequest.cc` / `src/mgr/MgrOpRequest.h` |
| **Corpus HEAD** | `8681fa6ebac230f86eb445bf57095c63e7f1abcc` |
| **Corpus date range** | 2023-12-21 → 2025-10-02 |
| **Total commits analysed** | 7 |
| **Generated** | 2026-09-11 (corpus collected_at) |

---

## Corpus overview

| SHA (short) | Date | Author | Subject |
|---|---|---|---|
| `66efcaae` | 2023-12-21 | Prashant D | mgr: integrate optracker in ceph-mgr |
| `16b3343b` | 2024-06-14 | Mohit Agrawal | mgr: Convert the last_event_detail data_type to std::string |
| `5c70e38a` | 2024-10-26 | Max Kellermann | mgr/MgrOpRequest: add missing includes |
| `941c5eda` | 2025-04-04 | Milind Changire | mgr: avoid explicitly dropping ref of MgrOpRequest.request |
| `f1bac418` | 2025-10-01 | Edwin Rodriguez | Update indent settings cc |
| `85d82faa` | 2025-10-01 | Edwin Rodriguez | Update indent settings h |
| `4adaf64d` | 2025-10-02 | Edwin Rodriguez | Add blank line after header block |

The three Edwin Rodriguez commits (`f1bac418`, `85d82faa`, `4adaf64d`) are mechanical style-only changes; they touch no function bodies.
`5c70e38a` adds three missing includes to the header; no function bodies changed.
All substantive logic was established in `66efcaae` with two targeted fixes in `16b3343b` and `941c5eda`.

---

## Class-level invariants

| Invariant | Established by |
|---|---|
| `request` is a `MessageRef` (intrusive-ptr); non-null for the entire tracked lifetime | `66efcaae` |
| `req_src_inst` is snapshotted at construction from `req->get_source_inst()`; immutable thereafter | `66efcaae` |
| `hit_flag_points` accumulates all flags ever set (bitwise OR); never cleared | `66efcaae` |
| `latest_flag_point` holds the most recently set flag; overwritten on each `mark_flag_point` call | `66efcaae` |
| `last_event_detail` is `std::string`; set only by `mark_flag_point(const char*)`, not by `mark_flag_point_string` | `16b3343b` (type), `66efcaae` (asymmetry) |
| `request` ref-count is managed entirely by `MessageRef` RAII; `put()` must not be called explicitly | `941c5eda` (Fixes: tracker #70618) |

---

## Function sections

### `MgrOpRequest` (constructor) — `src/mgr/MgrOpRequest.cc:29` / `src/mgr/MgrOpRequest.h:47`

**Intent (established by `66efcaae`):**  
Construct a `TrackedOp` wrapper around an incoming `MessageRef`. Initialise the tracker base with `req->get_recv_stamp()` (the time the message arrived at the messenger). Copy-construct `request` from `req` (incrementing the intrusive-ptr ref-count). Snapshot `req_src_inst` for thread-safe later use.

**Invariants:**
- `req` must be non-null; the code unconditionally calls `req->get_recv_stamp()` in the base-class initialiser list — a null `req` is undefined behaviour (`66efcaae`).
- `request` is value-initialised to `req` before the constructor body runs.
- `hit_flag_points` and `latest_flag_point` are `uint8_t` members with no explicit initialiser in the member list — they are zero-initialised by the aggregate/value-init rules for `struct` members when the object is allocated via `new` by `OpTracker::create_request`. This is implicit and relies on `OpTracker`'s allocation path.

**Implementation critique:**  
`src/mgr/MgrOpRequest.cc:29–33` (blame: `66efcaae`):
- Line 30: `TrackedOp(tracker, req->get_recv_stamp())` — correct.
- Line 31: `request(req)` — correct ref-count increment.
- Line 32: `req_src_inst = req->get_source_inst()` — safe, `req` is guaranteed non-null here.
- `hit_flag_points` and `latest_flag_point` have no explicit zero-initialisation in the member initialiser list. **UNGROUNDED**: relying on zero-init via `OpTracker`'s allocator path is fragile; an explicit `hit_flag_points(0), latest_flag_point(0)` initialiser was never added and no commit documents the intent.

---

### `_dump` — `src/mgr/MgrOpRequest.cc:35` / `src/mgr/MgrOpRequest.h:32`

**Intent (established by `66efcaae`):**  
Serialise the tracked operation to a `Formatter` for `dump_ops_in_flight` / `dump_historic_ops`. Emits:
1. `flag_point` — current state string.
2. `client_info` object — only when the source is a client entity; contains `client` (name), `client_addr`, `tid`.
3. `events` array — the full event log with per-event duration (delta from previous event; first event has duration 0).

**Invariants:**
- The `lock` (`TrackedOp::lock`) must be held when iterating `events` (`66efcaae`).
- Duration for the first event is defined as 0 (`66efcaae`).
- `client_info` section is emitted only when `m->get_orig_source().is_client()` (`66efcaae`).

**Implementation critique:**  
`src/mgr/MgrOpRequest.cc:35–71` (blame: `66efcaae`):
- Line 37: `MessageRef m = request` — copies the intrusive-ptr (increments ref-count) before the lock. The copy itself is not protected by `lock`; this is safe because `request` is immutable after construction, but the pattern looks racy to a reader without that context. **UNGROUNDED**.
- Line 38: `state_string()` call is outside the lock. `state_string()` calls `_get_state_string()` which reads `latest_flag_point` and `last_event_detail`. Both fields are written by `mark_flag_point` which in turn calls `mark_event` (which acquires `lock`) — but `latest_flag_point` and `last_event_detail` themselves are not protected by `lock`. **UNGROUNDED**: the lack of synchronisation on these two reads is unexplained.
- Lines 50–70: `lock` held only around the `events` iteration — consistent with `TrackedOp` pattern.
- Lines 61–64: `i - 1` arithmetic requires `events` to be a random-access container. This is an implicit structural requirement on `TrackedOp::events` never documented here.

---

### `_dump_op_descriptor` — `src/mgr/MgrOpRequest.cc:73` / `src/mgr/MgrOpRequest.h:50`

**Intent (established by `66efcaae`):**  
Emit a human-readable one-line descriptor of the tracked operation to an `ostream`, delegating to `Message::print()`.

**Invariants:**
- `request` is non-null (invariant of the class); `get_req()` is safe to call unconditionally (`66efcaae`).

**Implementation critique:**  
`src/mgr/MgrOpRequest.cc:73–76` (blame: `66efcaae`):
- Line 75: `get_req()->print(stream)` — correct delegation, no issues.
- No lock held; `request` is read-only after construction, safe.

---

### `_unregistered` — `src/mgr/MgrOpRequest.cc:78` / `src/mgr/MgrOpRequest.h:51`

**Intent (established by `66efcaae`):**  
Called by `OpTracker` when the op is removed from the tracking table. Release heavyweight resources held by the `Message`: payload data, raw data buffers, messenger throttle, and the connection reference. This allows memory to be reclaimed even while the `MgrOpRequest` object itself may still be referenced by consumers (e.g. `dump_historic_ops`).

**Invariants:**
- Called exactly once, after the op has been deregistered (`66efcaae`).
- `request` is non-null (class invariant); no null guard is needed or present (`66efcaae`).
- Does not call `request->put()` — ownership is managed by `MessageRef` RAII (`941c5eda`, Fixes tracker #70618).

**Implementation critique:**  
`src/mgr/MgrOpRequest.cc:78–83` (blame: `66efcaae`):
- Lines 79–82: four calls on `request` — all correct and complete for resource release.
- No null check on `request` — correct per class invariant.
- Consistent with `941c5eda`'s intent: the message's lifetime is managed by `request` (intrusive-ptr); `_unregistered` clears heavyweight fields only, not the allocation.

---

### `filter_out` — `src/mgr/MgrOpRequest.cc:106` / `src/mgr/MgrOpRequest.h:52`

**Intent (established by `66efcaae`):**  
Used by `OpTracker::dump_ops_in_flight` to decide whether to include this op in the output given a set of address-filter strings. Returns `true` (include) if:
1. No parseable addresses are in `filters` (show all).
2. The source address matches any filter at full precision.
3. The source address matches after zeroing the nonce.
4. The source address matches after zeroing the nonce and port.

Returns `false` (exclude) only when parseable filters exist and none match.

**Invariants:**
- `req_src_inst.addr` is the address to match against; captured at construction (`66efcaae`).
- Three-pass matching (exact → nonce-0 → nonce+port-0) is the same algorithm used in `OSD`'s `OpRequest::filter_out` — copied without attribution or comment (`66efcaae`).

**Implementation critique:**  
`src/mgr/MgrOpRequest.cc:106–132` (blame: `66efcaae`):
- Lines 109–114: parses each filter string as `entity_addr_t`; silently ignores un-parseable strings.
- Line 115–116: empty-addrs early return (`true`) is correct — no filter means show everything.
- Lines 118–129: three-pass matching is correctly implemented.
- **UNGROUNDED**: the three-pass relaxation (nonce=0, then port=0) is not explained. The nonce is a per-session identifier; zeroing it allows matching on IP:port regardless of session. Zeroing the port further allows matching on IP only. This logic is borrowed from OSD but no comment or commit message documents the intent in the mgr context.

---

### `mark_flag_point` — `src/mgr/MgrOpRequest.cc:85` / `src/mgr/MgrOpRequest.h:128`

**Intent (established by `66efcaae`):**  
Record a named lifecycle milestone. Updates `last_event_detail` (the state string for `flag_reached_module`), OR-accumulates the flag into `hit_flag_points`, sets `latest_flag_point`, fires a LTTng tracepoint, and calls `TrackedOp::mark_event` (which appends to the event log under `lock`).

**Invariants:**
- `last_event_detail` is updated to `s` unconditionally — overwriting any prior value (`66efcaae`).
- After `16b3343b`: `s` is implicitly converted to `std::string` on assignment; no longer a dangling pointer risk.
- `old_flags` is captured before the OR for the tracepoint only; it is `[[maybe_unused]]` in non-LTTng builds (`66efcaae`).

**Error conditions / bugs from history:**  
- **Pre-`16b3343b`**: `last_event_detail` was `const char*` and stored the raw pointer `s`. If `s` pointed to a stack-allocated or short-lived string, subsequent reads of `last_event_detail` in `_get_state_string` would produce garbage. Fixed by `16b3343b` (tracker #66268).

**Implementation critique:**  
`src/mgr/MgrOpRequest.cc:85–94` (blame: `66efcaae`):
- Line 88: `last_event_detail = s` — now `std::string` assignment from `const char*`; correct after `16b3343b`.
- Line 89: `hit_flag_points |= flag` — OR accumulation, correct.
- Line 90: `latest_flag_point = flag` — overwrites; correct.
- Lines 87/88 vs. `mark_flag_point_string`: the string variant does NOT update `last_event_detail`. **DIVERGED** from the symmetry contract implied by the two overloads: `mark_flag_point_string` is the string-argument version of the same operation but omits the `last_event_detail` update. If `mark_flag_point_string` is ever called with `flag_reached_module`, `_get_state_string` returns the previously-set `last_event_detail` (possibly empty), not `s`. No commit ever corrected this asymmetry (established `66efcaae`, never fixed).

---

### `mark_flag_point_string` — `src/mgr/MgrOpRequest.cc:96` / `src/mgr/MgrOpRequest.h:129`

**Intent (established by `66efcaae`):**  
String-argument variant of `mark_flag_point`: accepts `const std::string&` instead of `const char*`. Intended for callers holding a `std::string` without a `const char*` lifetime guarantee. Updates `hit_flag_points`, `latest_flag_point`, and fires the LTTng tracepoint. Calls `TrackedOp::mark_event(s)`.

**Invariants:**
- Does **not** update `last_event_detail` (established and never changed, `66efcaae`).

**Implementation critique:**  
`src/mgr/MgrOpRequest.cc:96–104` (blame: `66efcaae`):
- Lines 99–100: `hit_flag_points |= flag`, `latest_flag_point = flag` — correct.
- Lines 98: `mark_event(s)` — correct.
- **DIVERGED**: missing `last_event_detail = s` assignment. If this overload is invoked with `flag_reached_module`, the `_get_state_string` case for `flag_reached_module` returns `last_event_detail` which will be stale or empty. The asymmetry was introduced in `66efcaae` and never addressed. No commit documents why the two overloads differ on `last_event_detail` assignment.

---

### `~MgrOpRequest` — `src/mgr/MgrOpRequest.h:55`

**Intent (established `66efcaae`, fixed `941c5eda`):**  
Destroy the `MgrOpRequest`. After `941c5eda` the destructor is intentionally empty: `request` is a `MessageRef` (`boost::intrusive_ptr<Message>`), whose destructor automatically calls `put()`. The original code (`66efcaae`) explicitly called `request->put()` which caused a double-decrement of the ref-count when `request`'s own destructor also ran. `941c5eda` removed the explicit `put()` call (Fixes tracker #70618).

**Invariants:**
- The `MessageRef` destructor handles release; no manual `put()` (`941c5eda`).

**Implementation critique:**  
`src/mgr/MgrOpRequest.h:55–56` (blame: `66efcaae` body, `941c5eda` removed line):
- Destructor body is now empty — correct.
- **DIVERGED**: the class doc comment at `h:24–27` (blame `66efcaae`) still reads: *"The MgrOpRequest takes in a MessageRef and takes over a single reference to it, which it puts() when destroyed."* The `puts() when destroyed` clause is false after `941c5eda`. The `MessageRef` RAII does the release, but the comment implies a manual `put()`. No commit updated the comment.

---

### `get_req` (template) — `src/mgr/MgrOpRequest.h:59`

**Intent (established by `66efcaae`):**  
Provide typed access to the underlying `Message*` without dynamic dispatch overhead. Casts the stored `Message*` to `const T*` via `static_cast`.

**Invariants:**
- Caller must ensure `T` is the correct dynamic type of the stored message; no runtime check is performed (`66efcaae`).

**Implementation critique:**  
`src/mgr/MgrOpRequest.h:58–59` (blame `66efcaae`):
- `static_cast<const T*>(request)` — the cast operates on the raw pointer extracted from the `MessageRef`. If `T` is not the correct type this is undefined behaviour.
- **UNGROUNDED**: the choice of `static_cast` over `dynamic_cast` is unexplained. The pattern is consistent with OSD's `OpRequest` (performance-sensitive path) but no comment documents the requirement that the caller guarantee type correctness.

---

### `get_req` (non-template) — `src/mgr/MgrOpRequest.h:61`

**Intent (established by `66efcaae`):**  
Return the underlying `MessageRef` as a `const` reference, giving read-only access to the raw message.

**Invariants:**
- `request` is always non-null post-construction; return is always valid (`66efcaae`).

**Implementation critique:**  
`src/mgr/MgrOpRequest.h:61` (blame `66efcaae`): trivially correct. Returns by value (ref-count increment), safe.

---

### `get_nonconst_req` — `src/mgr/MgrOpRequest.h:62`

**Intent (established by `66efcaae`):**  
Provide mutable access to the underlying `MessageRef` for callers that need to modify the message (e.g., to call `set_connection`).

**Invariants:**
- Same as `get_req` non-template; `request` is always valid (`66efcaae`).

**Implementation critique:**  
`src/mgr/MgrOpRequest.h:62` (blame `66efcaae`): returns by value (copy of `MessageRef`), mutable. Correct.

---

### `get_source` — `src/mgr/MgrOpRequest.h:64`

**Intent (established by `66efcaae`):**  
Return the `entity_name_t` identifying the source of the request.

**Invariants:**
- `request` is always non-null post-construction (`66efcaae`).

**Implementation critique:**  
`src/mgr/MgrOpRequest.h:64–70` (blame `66efcaae`):
- Lines 65–69: null-check `if (request)` — **OVERCAUTIOUS**. `request` is guaranteed non-null by the constructor (which calls `req->get_recv_stamp()` without a null check), so the branch `else { return {}; }` is unreachable. No commit explains why a null check was added here but not in other accessors like `get_req()` or `get_nonconst_req()`. The inconsistency is unexplained.

---

### `state_flag` — `src/mgr/MgrOpRequest.h:71`

**Intent (established by `66efcaae`):**  
Return the raw `uint8_t` value of `latest_flag_point` for external consumers (e.g., the `dump_historic_ops_by_duration` sort path).

**Invariants:**
- Returns the most recently set flag, not the accumulated bitmask (`66efcaae`).

**Implementation critique:**  
`src/mgr/MgrOpRequest.h:71–73` (blame `66efcaae`): trivially correct accessor, no issues.

---

### `_get_state_string` — `src/mgr/MgrOpRequest.h:75`

**Intent (established by `66efcaae`):**  
Override `TrackedOp::_get_state_string()` to provide a human-readable description of the current lifecycle stage, called by `TrackedOp::state_string()` which is called from `_dump`.

**Invariants:**
- `flag_reached_module` state returns `last_event_detail` — the module name or event string passed to `mark_reached()` (`66efcaae`).
- All other flags return fixed string literals (`66efcaae`).
- Default (no flag set, `latest_flag_point == 0`) returns `"no flag points reached"` (`66efcaae`).

**Implementation critique:**  
`src/mgr/MgrOpRequest.h:75–85` (blame `66efcaae`):
- Line 79: `return last_event_detail` — was dangling pointer pre-`16b3343b`; now safe `std::string` copy after `16b3343b`.
- Lines 77–81: all five flag constants covered.
- **DIVERGED** (copy-paste bug in caller): `mark_finish_mon_command` at `h:121–123` passes `flag_start_mon_command` (not `flag_finish_mon_command`) to `mark_flag_point`. Therefore when the op is in the "finish mon command" state, `latest_flag_point == flag_start_mon_command` and `_get_state_string` returns `"start mon command"` instead of `"mon command finished"`. This misattribution was introduced in `66efcaae` and never corrected. The bug lies in `mark_finish_mon_command`, not in `_get_state_string` itself, but the effect is visible here.

---

### `get_state_string` (static) — `src/mgr/MgrOpRequest.h:87`

**Intent (established by `66efcaae`):**  
Static utility that maps a flag constant to a fixed string. Used by external code (e.g. `ceph tell mgr dump_historic_ops_by_duration` display path) that has the raw `uint8_t` flag value from `state_flag()` and needs a displayable string.

**Invariants:**
- Returns empty string for unknown/unrecognised flag values (no default case in switch) (`66efcaae`).
- For `flag_reached_module` returns the fixed literal `"reached module"` — **not** the dynamic `last_event_detail`. This is semantically different from `_get_state_string()` which returns the per-instance detail string (`66efcaae`).

**Implementation critique:**  
`src/mgr/MgrOpRequest.h:87–107` (blame `66efcaae`):
- The switch has no `default:` branch; unrecognised flags return `""`. **UNGROUNDED**: silent empty-string return on unknown flags is not documented. A `default: return "unknown";` would be more informative.
- **UNGROUNDED**: the divergence between `_get_state_string` (returns `last_event_detail` for `flag_reached_module`) and `get_state_string` (returns `"reached module"` fixed string) is never explained in any commit. External callers using the static form lose the per-op module detail.

---

### `mark_started` — `src/mgr/MgrOpRequest.h:109`

**Intent (established by `66efcaae`):**  
Record that the op has been accepted and started processing. Sets `flag_started`, records `"started"` as the event string and `last_event_detail`.

**Implementation critique:**  
`src/mgr/MgrOpRequest.h:109–111` (blame `66efcaae`): correct delegation to `mark_flag_point`.

---

### `mark_queued_for_module` — `src/mgr/MgrOpRequest.h:112`

**Intent (established by `66efcaae`):**  
Record that the op has been placed in the module dispatch queue. Sets `flag_queued_for_module`, records `"queued_for_module"` as the event string and `last_event_detail`.

**Implementation critique:**  
`src/mgr/MgrOpRequest.h:112–114` (blame `66efcaae`): correct delegation. Note: event string is `"queued_for_module"` (underscored) while `_get_state_string` returns `"queued for module"` (spaced). **UNGROUNDED**: the inconsistency (underscore vs space) between the event log and the state string is unexplained. It means event log entries and state strings cannot be trivially compared.

---

### `mark_reached` — `src/mgr/MgrOpRequest.h:115`

**Intent (established by `66efcaae`):**  
Record that the op has been dispatched into a specific module. The `s` argument names the module or handler. Sets `flag_reached_module`, stores `s` in `last_event_detail` (via `mark_flag_point`), and records `s` in the event log.

**Invariants:**
- `s` must remain valid for the duration of the op's tracked lifetime — **pre-`16b3343b` only**. After `16b3343b` a `std::string` copy is stored.

**Implementation critique:**  
`src/mgr/MgrOpRequest.h:115–117` (blame `66efcaae`): correct post-`16b3343b`. Previously passing a stack string or temporary was a dangling-pointer bug (tracker #66268, fixed by `16b3343b`).

---

### `mark_start_mon_command` — `src/mgr/MgrOpRequest.h:118`

**Intent (established by `66efcaae`):**  
Record that the op has begun executing as a mon command. Sets `flag_start_mon_command`, records `"start_mon_command"` event string and `last_event_detail`.

**Implementation critique:**  
`src/mgr/MgrOpRequest.h:118–120` (blame `66efcaae`): correct delegation. Event string `"start_mon_command"` (underscored) vs state string `"start mon command"` (spaced) — same underscore/space inconsistency as `mark_queued_for_module`.

---

### `mark_finish_mon_command` — `src/mgr/MgrOpRequest.h:121`

**Intent (established by `66efcaae`):**  
Record that the mon command has finished. Should set `flag_finish_mon_command`.

**Invariants:**
- **DIVERGED** (`66efcaae`, never fixed): the implementation passes `flag_start_mon_command` to `mark_flag_point` instead of `flag_finish_mon_command`. This means:
  1. `hit_flag_points` gets bit 3 (`flag_start_mon_command`) OR'd in again (idempotent but incorrect semantically).
  2. `latest_flag_point` is set to `flag_start_mon_command` (value 8), not `flag_finish_mon_command` (value 16).
  3. `_get_state_string()` returns `"start mon command"` after `mark_finish_mon_command()` is called.
  4. The `flag_finish_mon_command` bit (16) is never set in `hit_flag_points` via this path, so `get_state_string(flag_finish_mon_command)` would return `"mon command finished"` but `state_flag()` never returns 16 after a `mark_finish_mon_command()` call.

**Implementation critique:**  
`src/mgr/MgrOpRequest.h:121–123` (blame `66efcaae`):
- Line 122: `mark_flag_point(flag_start_mon_command, "mon_command_finished")` — **DIVERGED**. Should be `mark_flag_point(flag_finish_mon_command, "mon_command_finished")`. This is a copy-paste bug from `66efcaae` that was never corrected in any subsequent commit.

---

## Cross-cutting findings

### DIVERGED findings

| # | Finding | Affected function | SHA that established | Contradicting line |
|---|---|---|---|---|
| D1 | Class doc comment still claims `put()` on destroy; behaviour removed by `941c5eda` | `~MgrOpRequest` | `66efcaae` (comment), `941c5eda` (fix) | `h:25–27` |
| D2 | `mark_flag_point_string` does not update `last_event_detail`; `mark_flag_point` does. If `mark_flag_point_string` is called with `flag_reached_module`, `_get_state_string` returns stale/empty `last_event_detail` | `mark_flag_point_string`, `_get_state_string` | `66efcaae` | `cc:96–104` (absent assignment) |
| D3 | `mark_finish_mon_command` passes `flag_start_mon_command` instead of `flag_finish_mon_command`; state reporting is wrong after this call | `mark_finish_mon_command`, `_get_state_string` | `66efcaae` | `h:122` |

### UNGROUNDED findings

| # | Finding | Affected function | Line |
|---|---|---|---|
| U1 | `hit_flag_points` and `latest_flag_point` have no explicit zero-initialiser in constructor member-init list; correctness relies on `OpTracker` allocation path | Constructor | `cc:29–33` |
| U2 | `MessageRef m = request` copy taken outside `lock` in `_dump`; reads of `latest_flag_point`/`last_event_detail` in `state_string()` not lock-protected | `_dump` | `cc:37–38` |
| U3 | Three-pass address matching (exact, nonce=0, nonce+port=0) in `filter_out` not explained in any commit | `filter_out` | `cc:118–129` |
| U4 | Template `get_req<T>()` uses `static_cast` without documenting the caller-must-guarantee-type contract | `get_req` (template) | `h:59` |
| U5 | `get_state_string` (static) returns fixed `"reached module"` while `_get_state_string` (instance) returns dynamic `last_event_detail` for `flag_reached_module`; divergence undocumented | `get_state_string` | `h:97–98` |
| U6 | Event log strings use underscores (`"queued_for_module"`, `"start_mon_command"`) while state strings use spaces (`"queued for module"`, `"start mon command"`); inconsistency unexplained | `mark_queued_for_module`, `mark_start_mon_command` | `h:113`, `h:119` |

### OVERCAUTIOUS findings

| # | Finding | Affected function | Line |
|---|---|---|---|
| O1 | Null-check `if (request)` in `get_source` is unreachable — `request` is always non-null post-construction; all other accessors omit this guard | `get_source` | `h:65` |

---

## Self-check

- [x] All 7 commits in corpus read (including 3 style-only commits that touch no function bodies).
- [x] All 27 function entries in `functions.txt` covered (some are header declarations paired with `.cc` definitions; each unique function has one section above).
- [x] Every DIVERGED finding cites the specific SHA and contradicting line number.
- [x] All UNGROUNDED code paths flagged.
- [x] `commit_function_map.txt` noted: all entries map to `(no functions)` because ctags-matched @@ context did not intersect current function lines for the style and include-only commits. The `66efcaae` initial-creation commit established all functions; `16b3343b` changed the `last_event_detail` type; `941c5eda` removed `request->put()`. These are captured in each relevant function section.
- [x] No source file exists in the workspace (live `src/mgr/MgrOpRequest.cc` / `.h` not present); analysis is fully based on blame.txt (definitive HEAD content at collection time) and diff corpus.
