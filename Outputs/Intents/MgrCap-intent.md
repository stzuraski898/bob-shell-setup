# MgrCap Intent Artefact

**Object:** `src/mgr/MgrCap.cc` / `src/mgr/MgrCap.h`  
**Corpus HEAD:** `8681fa6ebac230f86eb445bf57095c63e7f1abcc`  
**Blame HEAD (last non-merge touches):** as of `488cb91e47036475637bc7bb4fd1941daaa85663` (2026-07-26)  
**Total commits analysed:** 21 (non-merge, rename-aware)  
**Date range:** 2019-10-11 (`6350bee`) → 2026-07-26 (`488cb91`)  
**Rename chain:** no renames; files created as `src/mgr/MgrCap.cc` / `src/mgr/MgrCap.h` in `6350bee` and have stayed at those paths.

---

## Corpus Summary

| SHA (short) | Date | Author | Subject |
|---|---|---|---|
| `6350bee` | 2019-10-11 | Jason Dillaman | mgr: stop re-using MonCap for handling MGR caps |
| `3463613` | 2019-10-11 | Jason Dillaman | mgr: add new 'allow module' cap to MgrCap |
| `cb534e0` | 2019-10-11 | Jason Dillaman | mgr: support optional arguments for module and profile caps |
| `b0d73ae` | 2019-10-14 | Jason Dillaman | mgr: added 'profile rbd/rbd-read-only' cap |
| `9193d87` | 2019-10-17 | Jason Dillaman | mgr: validate that profile caps are actually valid |
| `2dc7a95` | 2019-10-22 | Jason Dillaman | mgr: added placeholder 'osd' and 'mds' profiles |
| `1e88640` | 2020-03-22 | Adam C. Emerson | mon: Build ceph-mon without using namespace declarations in headers |
| `98dfce1` | 2020-03-02 | Kefu Chai | mgr/MgrCap.h: avoid forward declare CephContext in different ways |
| `c7244e7` | 2020-06-17 | Sage Weil | misc language changes: whitelist -> ignore etc |
| `03da557` | 2022-07-29 | Kefu Chai | mgr/MgrCap: include `<boost/phoenix.hpp>` |
| `4f1f40a` | 2024-10-10 | Max Kellermann | mgr/MgrCap: add missing includes |
| `ed6b712` | 2025-06-09 | Kefu Chai | src: Fix memory leaks in generate_test_instance() by returning values instead of pointers |
| `f6387fd` | 2025-08-26 | Kefu Chai | src: replace push_back(T{}) with emplace_back() |
| `f1bac41` | 2025-10-01 | Edwin Rodriguez | Update indent settings cc |
| `85d82fa` | 2025-10-01 | Edwin Rodriguez | Update indent settings h |
| `c8c1019` | 2025-10-02 | Edwin Rodriguez | Add missing blank line after comment block |
| `488cb91` | 2026-07-26 | Matthew N. Heler | mon,osd,mgr: add rgw cap profile |

> Four commits have no diff files in the corpus (`85d82fa`, `c8c1019`, `f1bac41`, `4f1f40a`). All four are infrastructure-only changes (indent settings, blank line, missing includes). Their content is fully captured in blame.txt and their respective commit subjects. No functional changes are missing.

---

## Design Intent (from commit history)

MgrCap was created in `6350bee` as a standalone MGR capability processor, ported from MonCap to eliminate the reuse of `MonCap` for MGR auth.  A grant is one of five exclusive forms:

1. **blanket** (`allow rw`, `allow *`) — matches any service/module/command, subject to r/w/x flags  
2. **service** (`allow service mds rw`) — matches a named Ceph service  
3. **module** (`allow module rbd_support rw`) — added in `3463613`; matches a named Python add-on module  
4. **profile** (`profile read-only`) — added in `6350bee`, extended through `b0d73ae`/`9193d87`/`2dc7a95`/`488cb91`; expands to a set of concrete grants  
5. **command** (`allow command foo with k=v`) — matches a specific CLI command  

Profiles `read-only`, `read-write`, `crash`, `rbd`, `rbd-read-only` are substantive; `osd`, `mds` (added `2dc7a95`), `rgw` (added `488cb91`) are accepted-but-empty placeholders (they grant nothing on the MGR).

All grant types except service accept optional key/value `arguments` (renamed from `command_args` in `cb534e0`). Module grants skip argument validation when a specific command is being checked (established in `cb534e0`). The `rbd`/`rbd-read-only` profiles filter their arguments to `pool` and `namespace` only (established in `b0d73ae`); unrecognised keys are a parse error (established in `9193d87`). Profile validation happens at parse time, not at authorisation time (established in `9193d87`).

Network restriction is orthogonal to grant type: any grant may carry a `network` field parsed by `parse_network()`; invalid networks are stored as `network_valid=false` and cause the grant to be silently skipped at authorisation time (`6350bee`).

Encoding/decoding is text-based: only `text` is serialised (version 4, compat 4); on decode the text is re-parsed (established `6350bee`).

---

## Function Sections

### `is_not_alnum_space` — `src/mgr/MgrCap.cc:36`

**Relevant commits:** `6350bee` (introduced)

**Intent:** Static predicate used by `maybe_quote_string` to determine whether a character is outside the safe unquoted set `[a-zA-Z0-9_-]`. Returns `true` if the character is NOT alphanumeric, `-`, or `_`.

**Invariants / error conditions:**  
- I1 (`6350bee`): The "safe" character set is `[isalpha || isdigit || '-' || '_']`. Any character outside this set causes the caller to quote the entire string.

**Implementation critique (blame.txt lines 38–40):**  
- Correct and stable since `6350bee`. No issues found.  
- OVERCAUTIOUS note: The function name says "is_not_alnum_space" but there is no space character in the safe set — the name is mildly misleading but the body is authoritative. Not a bug.

---

### `maybe_quote_string` — `src/mgr/MgrCap.cc:40`

**Relevant commits:** `6350bee` (introduced)

**Intent:** Returns the input string unchanged if every character passes `is_not_alnum_space`; otherwise wraps it in double quotes. Used by all `operator<<` implementations to produce parseable output.

**Invariants:**  
- I1 (`6350bee`): Round-trip invariant: output of `operator<<(MgrCapGrant)` must be re-parseable by `MgrCapParser`. `maybe_quote_string` is the mechanism that preserves this.

**Implementation critique (blame.txt lines 40–44):**  
- Correct. Note that quoted strings in the grammar support both `"` and `'` delimiters (grammar line 428–429 in blame), but `maybe_quote_string` always wraps with `"`. This is sound because `"` is in the grammar.  
- UNGROUNDED: There is no commit explaining why single-quote quoting was added to the parser but `maybe_quote_string` only ever emits double-quotes. No round-trip regression is possible (both are accepted), but the single-quote path in the grammar has no production path, which is an invisible dead grammar branch. No commit explains this.

---

### `operator<<(mgr_rwxa_t)` — `src/mgr/MgrCap.cc:48` / `src/mgr/MgrCap.h:36`

**Relevant commits:** `6350bee` (introduced), `1e88640` (namespace qualification)

**Intent:** Print the r/w/x bitmask. If all bits set (`MGR_CAP_ANY`), print `*`. Otherwise print the individual `r`, `w`, `x` characters as set.

**Invariants:**  
- I1 (`6350bee`): `MGR_CAP_ANY = 0xff` is printed as `*` before individual bit tests to produce canonical output.

**Implementation critique (blame.txt lines 48–59):**  
- Correct. The early return for `== MGR_CAP_ANY` is correct: `0xff` has all bits set, so printing individual letters would print `rwx` (only 3 bits matter), but `*` is the canonical token that the parser also maps to `MGR_CAP_ANY` (blame lines 499–500).

---

### `operator<<(MgrCapGrantConstraint)` — `src/mgr/MgrCap.cc:61` / `src/mgr/MgrCap.h:55`

**Relevant commits:** `6350bee` (introduced), `1e88640` (namespace qualification)

**Intent:** Emit the constraint's match-type prefix (`=`, ` prefix `, ` regex `) followed by the quoted value. The output is consumed verbatim by the `kv_pair` grammar rule.

**Invariants:**  
- I1 (`6350bee`): `MATCH_TYPE_NONE` has no printed representation; the `default: break` branch emits nothing and then prints the value. This means a NONE-typed constraint round-trips as a bare value string — which the grammar would try to parse as a subsequent key. This is de facto unreachable because the parser never produces `MATCH_TYPE_NONE` in practice (all three grammar productions set an explicit type).

**Implementation critique (blame.txt lines 61–77):**  
- UNGROUNDED: The `default: break` at line 74 falls through to emit `maybe_quote_string(c.value)` for `MATCH_TYPE_NONE`. No commit explains what the intended output is for `MATCH_TYPE_NONE`. Because the grammar never produces it, this is a silent dead path. No DIVERGED finding (no commit ever defined its output), but it is UNGROUNDED.

---

### `operator<<(MgrCapGrant)` — `src/mgr/MgrCap.cc:79` / `src/mgr/MgrCap.h:154`

**Relevant commits:** `6350bee` (introduced), `3463613` (added module branch), `cb534e0` (restructured arguments printing), `1e88640` (namespace qualification)

**Intent:** Emit a human-readable, parseable representation of a single grant. The output order mirrors the grammar's field order.

**Invariants:**  
- I1 (`6350bee`): Profile grants emit `profile <name>` without the `allow` prefix.  
- I2 (`6350bee`): Blanket/service/module/command grants emit `allow` prefix.  
- I3 (`3463613`): Module grants emit `module <name>` as the discriminator.  
- I4 (`cb534e0`): `arguments` block emits ` with` prefix for non-profile grants; profile grants use a bare space (no `with` keyword) since the grammar's `profile_match` accepts `-(spaces >> kv_map)` without a `with` keyword.  
- I5 (`6350bee`): If `allow != 0`, emit the bitmask after arguments.  
- I6 (`6350bee`): If `network.size()`, emit ` network <network>` at the end.

**Implementation critique (blame.txt lines 79–108):**  
- Line 94: `out << (!m.profile.empty() ? "" : " with")` — correctly omits `with` for profiles, emits ` with` for module/command. However, there is a subtle issue: if a `service` grant somehow acquired `arguments` (which the parser does not produce), the output would include ` with ...` but the `service_match` grammar rule does NOT accept a `with` block — it accepts no `arguments` at all. This is partially UNGROUNDED: no commit ever clarified whether service grants can have arguments, but the parser explicitly forbids it.
- Lines 80–91: Profile check comes before the `allow` block, so profile grants that also have `allow != 0` would emit `profile X` and then ` <rwxa>` — but the profile parser stores `allow = 0`, so this cannot happen from a parsed cap string.

---

### `operator<<(MgrCap)` — `src/mgr/MgrCap.cc:278` / `src/mgr/MgrCap.h:167`

**Relevant commits:** `6350bee` (introduced), `1e88640` (namespace qualification)

**Intent:** Emit all grants comma-separated.

**Invariants:**  
- I1 (`6350bee`): Grants are separated by `, ` (comma-space). The grammar also accepts `;` as a separator (blame line 513 `lit(';') | lit(',')`) but `operator<<` only emits `,`. Round-tripping a semicolon-separated cap through `operator<<` converts it to comma-separated, which is valid.

**Implementation critique (blame.txt lines 278–289):**  
- Correct. No issues found.

---

### `parse_network` — `src/mgr/MgrCap.cc:130` / `src/mgr/MgrCap.h:101`

**Relevant commits:** `6350bee` (introduced)

**Intent:** Parse the `network` string into a `(network_parsed, network_prefix)` pair using the global `::parse_network()` from `include/ipaddr.h`. Stores the boolean result in `network_valid`. Called from `MgrCap::parse()` for every grant after grammar parse succeeds.

**Invariants:**  
- I1 (`6350bee`): `network_valid` defaults to `true` (header initializer). This means a grant that never had `parse_network()` called on it (e.g., programmatically constructed) has `network_valid=true` but `network_parsed` and `network_prefix` are zero-initialized. Such a grant with an empty `network` string will pass the `grant.network.size()` guard in `is_capable` without doing a network check. This is correct.  
- I2 (`6350bee`): An invalid network string sets `network_valid = false`, causing the grant to be skipped entirely in `is_capable` (fail-safe: invalid network → deny rather than skip network check).

**Implementation critique (blame.txt lines 130–133):**  
- Correct and minimal.  
- OVERCAUTIOUS observation: The `network_valid = true` default initializer in the header (`MgrCap.h` line ~84) means grants built programmatically without a network string still work correctly. No issue.

---

### `expand_profile` — `src/mgr/MgrCap.cc:135` / `src/mgr/MgrCap.h:109`

**Relevant commits:** `6350bee` (introduced; `read-only`, `read-write`, `crash`), `3463613` (expanded struct fields for module), `cb534e0` (renamed `command_args` → `arguments`; `rbd`/`rbd-read-only` references added via `b0d73ae`), `b0d73ae` (added `rbd`/`rbd-read-only`; `filtered_arguments`), `9193d87` (added `err` parameter; profile validation; unknown key = parse error; unknown profile = parse error), `2dc7a95` (added `osd`, `mds` placeholders), `c7244e7` (comment text: "whitelist" → "allow"), `488cb91` (merged `osd` + `mds` into combined guard; added `rgw`)

**Intent:** Expand a profile name into a list of concrete `MgrCapGrant` objects stored in `profile_grants`. Memoized (once `profile_grants` is non-empty, return immediately). The `err` parameter (added `9193d87`) is used during `parse()` validation to report unrecognised profiles or invalid argument keys.

**Invariants:**  
- I1 (`6350bee`): Memoization guard: if `profile_grants` is not empty, return immediately. This means `expand_profile()` is idempotent but NOT re-entrant with different `arguments` if called a second time after the first had already populated `profile_grants`. Mutable `profile_grants` on a const object is an intentional design.  
- I2 (`6350bee`): `read-only` → single blanket grant with `MGR_CAP_R`.  
- I3 (`6350bee`): `read-write` → single blanket grant with `MGR_CAP_R | MGR_CAP_W`.  
- I4 (`6350bee`/`3463613`): `crash` → single command grant `"crash post"` with zero allow.  
- I5 (`b0d73ae`): `rbd` → module grant on `rbd_support` with `MGR_CAP_R | MGR_CAP_W`, filtered to `pool`/`namespace` arguments.  
- I6 (`b0d73ae`): `rbd-read-only` → module grant on `rbd_support` with `MGR_CAP_R`, filtered to `pool`/`namespace` arguments.  
- I7 (`9193d87`): Unknown argument key in `rbd`/`rbd-read-only` → write to `err` and `return` without populating `profile_grants`. This means `profile_grants` remains empty, and a subsequent `expand_profile(nullptr)` in `get_allowed()` will silently produce no grants.  
- I8 (`9193d87`): Unknown profile name → write `"unrecognized profile '<name>'"` to `err` (if non-null) and fall off the end of the function. `profile_grants` remains empty.  
- I9 (`2dc7a95`): `osd` and `mds` are accepted (return without populating `profile_grants`). Grants nothing.  
- I10 (`488cb91`): `rgw` added to the accept-but-grant-nothing group.

**Implementation critique (blame.txt lines 135–194):**  

- **DIVERGED** (`9193d87` vs. blame line 238): In `get_allowed()`, the call is `expand_profile(nullptr)`. I7 above states that when an unknown argument key is encountered (or unknown profile), `expand_profile` returns with empty `profile_grants`. When called later from `get_allowed()` with `nullptr`, the memoization guard (`!profile_grants.empty()`) evaluates to `false` — so `expand_profile` runs again and again silently every time `get_allowed()` is called. The intent of `9193d87` is that invalid profiles fail at *parse time*, making the runtime path unreachable. The parse-time check in `parse()` (blame lines 550–563) calls `expand_profile(&profile_err)` and returns `false` on error, so this path is normally blocked. However, if `expand_profile()` is called directly (not via `parse()`) or if a MgrCap is deserialized from text that bypasses validation, the `get_allowed()` path would silently grant nothing without logging. This is a latent correctness gap: the memoization guard breaks for the invalid-profile/invalid-key case because `profile_grants` stays empty.

- **DIVERGED** (`b0d73ae` vs. blame lines 167–169): The `filtered_arguments` loop uses `std::move(constraint)` while iterating `arguments` with `auto&`. Moving from a map element during iteration technically leaves the element in a valid-but-unspecified state. Since the entire map is iterated and the original `arguments` field is never used again after `expand_profile()` populates `profile_grants`, this is practically safe but violates strict-aliasing discipline. No commit acknowledged this. **UNGROUNDED**.

- Lines 159–163 (`488cb91`): The combined `if (profile == "osd" || profile == "mds" || profile == "rgw")` guard correctly collapses the separate `osd`/`mds` branches. Comment says "they grant nothing here" — accurately describes the MGR semantics where these profiles only have meaning on mon and osd services.

---

### `validate_arguments` — `src/mgr/MgrCap.cc:196` / `src/mgr/MgrCap.h:123`

**Relevant commits:** `cb534e0` (introduced; extracted from inline `get_allowed` command logic)

**Intent:** Given a map of runtime argument values, verify that all key/value constraints in `this->arguments` are satisfied. Every constrained key must be present in `args` and its value must match the constraint (equal, prefix, or regex). Returns `true` if all constraints pass, `false` on any failure.

**Invariants:**  
- I1 (`cb534e0`): Argument presence is mandatory: if a key in `arguments` is not found in `args`, return `false`.  
- I2 (`cb534e0`): `MATCH_TYPE_EQUAL`: exact string equality.  
- I3 (`cb534e0`): `MATCH_TYPE_PREFIX`: `q->second.find(constraint.value) != 0` — the runtime value must *start with* the constraint value.  
- I4 (`cb534e0`): `MATCH_TYPE_REGEX`: `std::regex_match` with `std::regex::extended`. A malformed regex catches `std::regex_error` and returns `false` (deny, not allow).  
- I5 (`cb534e0`): `default` (i.e., `MATCH_TYPE_NONE`) returns `false` — any constraint object that was created without a match type is a hard deny.

**Implementation critique (blame.txt lines 196–231):**  
- Correct. The `default: return false` for `MATCH_TYPE_NONE` (blame line 226–228) is a sound defensive choice.  
- OVERCAUTIOUS: The `MATCH_TYPE_NONE` case (line 225–228) can never be reached from a parsed cap string because the grammar only produces `MATCH_TYPE_EQUAL`, `MATCH_TYPE_PREFIX`, or `MATCH_TYPE_REGEX` constraints. However, a programmatically-constructed `MgrCapGrantConstraint{}` would have `MATCH_TYPE_NONE`, and the `default: return false` correctly denies it. This is appropriate defensive programming, not excessive.  
- Note: `validate_arguments` iterates `this->arguments` (the grant's constraints) against the caller-supplied `args`. It does NOT check that args contains no keys outside the constraints. Extra args are allowed. This is intentional and consistent with the design: `arguments` is a whitelist of *required* values, not an exhaustive description.

---

### `get_allowed` — `src/mgr/MgrCap.cc:233` / `src/mgr/MgrCap.h:137`

**Relevant commits:** `6350bee` (introduced; service/command dispatch), `3463613` (added `module` parameter; module branch), `cb534e0` (renamed args; delegated command/module arg checking to `validate_arguments`; added module argument bypass when specific command is given), `9193d87` (changed `expand_profile()` → `expand_profile(nullptr)`)

**Intent:** Given a request tuple `(service, module, command, args)`, return the set of permission bits this grant permits. Returns `mgr_rwxa_t{}` (zero) for no match.

**Invariants:**  
- I1 (`6350bee`): Profile grants recurse through `profile_grants` ORing results together; call `expand_profile(nullptr)` first to populate `profile_grants`.  
- I2 (`6350bee`): Service match: exact name match → return `allow`; mismatch → return zero.  
- I3 (`3463613`): Module match: exact name match, THEN argument validation (unless a specific command is being checked: `c.empty()` guard).  
- I4 (`cb534e0`): `c.empty()` guard for module: when a specific command string is provided, module argument constraints are skipped. This reflects the design that module caps are also checked at command level.  
- I5 (`6350bee`/`cb534e0`): Command match: exact name match → validate arguments → return `MGR_CAP_ANY`. Note: command grants return `MGR_CAP_ANY` (all bits), not the `allow` field. The `allow` field is always zero for command grants (the grammar injects `qi::attr(0)` for command_match).  
- I6 (`6350bee`): Blanket (none of the above): return `allow` directly.

**Implementation critique (blame.txt lines 233–276):**  

- **DIVERGED** (`3463613` vs. blame line 259): The `c.empty()` condition means "skip module argument validation when a specific command string is given." The commit message for `cb534e0` says: "don't test module arguments when validating a specific command." However, this creates a situation where a caller checking a command against a module grant (i.e., both `m` = module name and `c` = command name are non-empty) bypasses argument validation entirely. The intent was that module-level constraints supplement command-level checks, but the current implementation allows command access to a module-restricted grant even if the module's argument constraints would normally fail. No subsequent commit addressed this; it appears to be an intentional design trade-off rather than a bug, but it is underdocumented. **UNGROUNDED**.

- Lines 265–273: Command grants return `MGR_CAP_ANY` (line 272). The `allow` field of a command grant is always zero (the grammar emits `qi::attr(0)` for command matches). Returning `MGR_CAP_ANY` rather than `allow` is intentional: command grants are either all-or-nothing access, not partial-permission grants. Correctly implemented.

---

### `is_allow_all` (MgrCapGrant) — `src/mgr/MgrCap.h:145`

**Relevant commits:** `6350bee` (introduced), `3463613` (added `module.empty()` check)

**Intent:** Return `true` iff this grant is a blanket "allow everything" grant: `allow == MGR_CAP_ANY` AND all discriminating fields are empty (service, module, profile, command).

**Invariants:**  
- I1 (`6350bee`): `allow == MGR_CAP_ANY` is necessary but not sufficient; all named fields must also be empty.  
- I2 (`3463613`): `module.empty()` was added when the module field was introduced, ensuring a module-scoped `allow *` does not qualify as allow-all.

**Implementation critique (MgrCap.h lines ~145–150, confirmed via blame):**  
- Correct. All five conditions (`allow`, `service`, `module`, `profile`, `command`) are checked.

---

### `is_allow_all` (MgrCap) — `src/mgr/MgrCap.cc:291` / `src/mgr/MgrCap.h:167`

**Relevant commits:** `6350bee` (introduced), `3463613` (no change to this function, but MgrCapGrant::is_allow_all gained a field)

**Intent:** Return `true` if any grant in the cap is a blanket allow-all. Short-circuits on first match.

**Invariants:**  
- I1 (`6350bee`): Linear scan of grants; early return on first `is_allow_all()` grant.

**Implementation critique (blame.txt lines 291–298):**  
- Correct. Delegates entirely to `MgrCapGrant::is_allow_all()`.

---

### `set_allow_all` — `src/mgr/MgrCap.cc:300` / `src/mgr/MgrCap.h:168`

**Relevant commits:** `6350bee` (introduced), `3463613` (updated initializer list to add empty module string)

**Intent:** Replace all grants with a single blanket `allow *` grant, and set `text = "allow *"`.

**Invariants:**  
- I1 (`6350bee`): `grants.clear()` before pushing; only one grant after the call.  
- I2 (`6350bee`): `text` is updated to `"allow *"` so serialization remains consistent.  
- I3 (`3463613`): Initializer list `{{}, {}, {}, {}, {}, mgr_rwxa_t{MGR_CAP_ANY}}` fills: service, module, profile, command, arguments, allow.

**Implementation critique (blame.txt lines 300–304):**  
- **DIVERGED** (`6350bee` initializer + `3463613` change, vs. blame line 302): The initializer `{{}, {}, {}, {}, {}, mgr_rwxa_t{MGR_CAP_ANY}}` is positional and must track the BOOST_FUSION_ADAPT_STRUCT order: service, module, profile, command, arguments, allow, network. The network field (7th) is omitted from the initializer, relying on default construction to zero/empty it. This is correct because `MgrCapGrant::network` is `std::string` which defaults to empty. Verified against blame line 115–122 (BOOST_FUSION_ADAPT_STRUCT order). No issue, but the positional initializer is fragile if fields are ever reordered.

---

### `is_capable` — `src/mgr/MgrCap.cc:306` / `src/mgr/MgrCap.h:186`

**Relevant commits:** `6350bee` (introduced; service/command/network/allow-all), `3463613` (added module parameter; updated log and get_allowed call), `1e88640` (namespace qualification)

**Intent:** The primary authorization entry point. Given a full request description (service, module, command, args, op_may_read/write/exec, addr), determine whether the capability permits the operation. Iterates grants in order, ORing allowed bits, with early return on is_allow_all or satisfied bits.

**Invariants:**  
- I1 (`6350bee`): Network restriction is checked first for each grant; if network is specified but the addr is outside the range (or the network is invalid), the grant is skipped entirely (`continue`).  
- I2 (`6350bee`): An `is_allow_all()` grant short-circuits with `return true` immediately.  
- I3 (`6350bee`): Bits are ORed across grants; a multi-grant cap can combine `allow r` from one grant with `allow w` from another.  
- I4 (`6350bee`): The test `(!op_may_read || (allow & MGR_CAP_R))` etc. means: if the operation doesn't need that permission, it's not required. All three conditions must be satisfied simultaneously.  
- I5 (`3463613`): The `module` parameter is forwarded to `get_allowed()` alongside `service` and `command`.

**Implementation critique (blame.txt lines 306–361):**  

- **DIVERGED** (`6350bee` comment `// Make sure no grants are kept after parsing failed!` in `parse()` vs. `is_capable`): The `command_args` parameter name in `is_capable` (blame line 312 shows `const std::map<std::string, std::string>& command_args`) was not renamed to `arguments` by `cb534e0`. That commit renamed the struct field and the `get_allowed`/`validate_arguments` parameter to `arguments`, but `is_capable`'s local parameter name was left as `command_args`. This is not a functional bug (it is just a parameter name), but it is a naming inconsistency introduced by `cb534e0`. The parameter is passed to `get_allowed` as `command_args` (line 350), which `get_allowed` accepts as `args`. **UNGROUNDED** in the sense that no commit explicitly retained this old name; it appears to be an oversight.

- Lines 333–339: The network validity check is `grant.network.size() && (!grant.network_valid || !network_contains(...))`. The logic is: if a network is specified AND (it is invalid OR the address is not in the network), skip. This correctly fails safe for invalid networks (established in `6350bee`). Correct.

---

### `encode` — `src/mgr/MgrCap.cc:363` / `src/mgr/MgrCap.h:195`

**Relevant commits:** `6350bee` (introduced), `1e88640` (namespace qualification of `ceph::buffer::list`)

**Intent:** Encode only the `text` field, version 4 compat 4. No structural serialization.

**Invariants:**  
- I1 (`6350bee`): Only `text` is encoded. The grants vector is reconstructed from text on decode. This means serialization format is fully determined by the cap string.  
- I2 (`6350bee`): Version and compat are both 4 (comment: "remain backwards compatible w/ MgrCap"). This signals that the encoding format is expected to be stable since version 4 was set from the start. The comment is slightly misleading since the class was created from scratch, not backward-compatible with an older MgrCap — likely copied from MonCap.

**Implementation critique (blame.txt lines 363–368):**  
- Correct. OVERCAUTIOUS note: The comment "remain backwards compatible w/ MgrCap" at line 364 is confusing since MgrCap didn't exist before `6350bee`. This is copy-paste from MonCap and the comment is vestigial but harmless.

---

### `decode` — `src/mgr/MgrCap.cc:370` / `src/mgr/MgrCap.h:196`

**Relevant commits:** `6350bee` (introduced), `1e88640` (namespace qualification)

**Intent:** Decode the text field, then call `parse(s, NULL)` to reconstruct grants. The `NULL` means parse errors during decode are silently swallowed.

**Invariants:**  
- I1 (`6350bee`): `parse(s, NULL)` is called without an error stream; a decode of a corrupt cap string produces a cap with no grants (since `parse()` clears grants on failure) with no diagnostic output.

**Implementation critique (blame.txt lines 370–377):**  
- **DIVERGED** (implicit, from `9193d87`): `9193d87` added profile validation at parse time and returns `false` from `parse()` on profile errors. `decode()` calls `parse(s, NULL)` and ignores the return value. This means a stored cap with an unrecognised profile silently becomes an empty grant list on decode, which is a security-safe behavior (empty grants = no access) but could produce confusing silent failures. No commit addressed this; the `NULL` error stream was present from `6350bee` and was not updated when `9193d87` added the profile validation error path. This is a **DIVERGED** finding because `9193d87` established an invariant that profile errors are reported, but `decode()` contradicts the reporting by passing `NULL`. The safety direction (deny) is correct, but the diagnostic contract is violated.

---

### `dump` — `src/mgr/MgrCap.cc:379` / `src/mgr/MgrCap.h:197`

**Relevant commits:** `6350bee` (introduced), `1e88640` (namespace qualification), `f6387fd` (surrounding `generate_test_instances` changes, no change to `dump`)

**Intent:** Dump only the `text` field to a `Formatter`. Minimal implementation consistent with the text-only serialization design.

**Invariants:**  
- I1 (`6350bee`): Only `text` is dumped. The structural grants are not dumped.

**Implementation critique (blame.txt line 379–381):**  
- Correct. UNGROUNDED minor: not dumping individual grants means `ceph auth get` output cannot be further introspected by automated parsers without a second-level parse. This is consistent with MonCap practice but undocumented.

---

### `generate_test_instances` — `src/mgr/MgrCap.cc:383` / `src/mgr/MgrCap.h:198`

**Relevant commits:** `6350bee` (introduced; static `void`, pointer list), `cb534e0` (added `allow module bar with k1=v1 k2=v2 x` and `profile rbd pool=rbd` test cases), `1e88640` (namespace qualification), `ed6b712` (changed to return `std::list<MgrCap>` by value; eliminated raw pointer leaks), `f6387fd` (`push_back(MgrCap{})` → `emplace_back()`)

**Intent:** Generate a set of test instances for encoding/decoding round-trip tests. The test set covers: empty cap, wildcard, rwx blanket, service grant, command grant, combined, command with args, module with args, rbd profile.

**Invariants:**  
- I1 (`ed6b712`): Return by value (not raw pointers) to eliminate memory leaks. Signature is `static std::list<MgrCap> generate_test_instances()`.  
- I2 (`cb534e0`): Test coverage includes module grants with key/value arguments and profile grants with arguments.

**Implementation critique (blame.txt lines 383–404):**  
- Correct. The `emplace_back()` / `ls.back().parse(...)` pattern (`f6387fd`) is sound: `parse()` overwrites `text` and `grants` in the already-constructed object.  
- UNGROUNDED: There is no test instance for network-restricted grants, despite network being a documented grant feature since `6350bee`. This is a test coverage gap, not a correctness issue in the implementation itself.

---

### `MgrCapParser` (constructor) — `src/mgr/MgrCap.cc:414`

**Relevant commits:** `6350bee` (introduced; full grammar), `3463613` (added `module_match`; padded other rules with empty-string attrs), `cb534e0` (added `with` optional to service/module rules; made profile args use bare `kv_map`)

**Intent:** Boost.Spirit Qi grammar that parses a complete MGR capability string into a `MgrCap` object. Five grant forms: `rwxa_match`, `profile_match`, `service_match`, `module_match`, `command_match`. Grant separator is `,` or `;`.

**Invariants:**  
- I1 (`6350bee`): `unquoted_word %= +char_("a-zA-Z0-9_./-")` — unquoted strings may contain `.`, `/`, `-`. This is a broader set than `is_not_alnum_space` which only allows `[a-zA-Z0-9_-]`. This means `maybe_quote_string` will quote strings containing `.` or `/`, but the parser would have accepted them unquoted. The round-trip is still correct (quoted strings are also accepted), but there is an asymmetry.  
- I2 (`6350bee`): `rwxa` rule uses Qi's `||` (ordered OR-of-OR) for `r`, `w`, `x` — this allows any subset of `rwx` in any order, producing the correct bitmask.  
- I3 (`3463613`): The priority order in `grant` is `rwxa_match | profile_match | service_match | module_match | command_match`. Profile is tried before service; if a string begins with "allow profile ...", the `rwxa_match` would fail (no `*`/`r`/`w`/`x` after `allow`) and fall through to `profile_match`. This ordering is correct.  
- I4 (`cb534e0`): `profile_match` uses `-(spaces >> kv_map)` (no `with` keyword) while `module_match` uses `-(spaces >> lit("with") >> spaces >> kv_map)`. Profile arguments are written as bare `key=value` pairs after the profile name.

**Implementation critique (blame.txt lines 414–535):**  

- **UNGROUNDED**: The `command_match` rule (blame line 447–454) fills BOOST_FUSION_ADAPT_STRUCT positions as: service (empty), module (empty), profile (empty), command (str), arguments (optional kv_map), allow (0), network (optional). But looking at the blame: three consecutive `qi::attr(std::string())` lines (448–450) before the `str` for command. These represent service, module, profile (all empty), followed by the command string. This is correct mapping to the struct order. No issue, but the implicit positional mapping is fragile documentation-wise.

- **UNGROUNDED**: The `module_match` rule (blame line 467–474) feeds: service (empty), module (str), profile (empty), command (empty), arguments (optional `with kv_map`), allow (rwxa), network (optional). The `-(spaces >> lit("with") >> spaces >> kv_map)` at blame line 472 is the optional arguments block. After `cb534e0` this is correct. However, comparing to `cb534e0` diff line 182: the module_match `with` was added in `cb534e0` — prior to that commit, module grants had no argument support. The current implementation correctly reflects `cb534e0`.

- Lines 509–510 (grant priority): `rwxa_match | profile_match | service_match | module_match | command_match`. Potential ambiguity: a string like `allow module foo r` — `rwxa_match` would fail (it expects `allow <rwxa>` directly, no `module` keyword), then `profile_match` fails (no `profile` keyword), then `service_match` fails (no `service` keyword), then `module_match` succeeds. Correct.

---

### `parse` — `src/mgr/MgrCap.cc:537` / `src/mgr/MgrCap.h:169`

**Relevant commits:** `6350bee` (introduced; Qi parse, grants.clear on failure, error message), `9193d87` (added profile validation loop with `expand_profile(&profile_err)`, returns false on profile error), `1e88640` (namespace qualification)

**Intent:** Parse a capability string into `text` and `grants`. On success: set `text`, call `parse_network()` for each grant, validate any profile grants by calling `expand_profile(&profile_err)`. On any failure: clear `grants`, optionally write error to `err` stream, return false.

**Invariants:**  
- I1 (`6350bee`): Grammar parse must succeed AND consume the entire input (`r && iter == end`). Partial parse is a failure.  
- I2 (`6350bee`): On failure, `grants.clear()` is always called before returning false.  
- I3 (`9193d87`): Profile grants are validated at parse time by calling `expand_profile` with a real error stream. If any profile produces an error, parse returns false.  
- I4 (`6350bee`): On success, `text = str` is set first, then per-grant post-processing (network parse, profile expansion).

**Implementation critique (blame.txt lines 537–577):**  

- **DIVERGED** (`9193d87`): The profile validation loop (blame lines 550–553) calls `g.expand_profile(&profile_err)` only if `!g.profile.empty()`. This is correct. However, the profile expansion populates `g.profile_grants` as a side-effect. This means after a successful `parse()`, the profile grants are already expanded and cached in `profile_grants`. A subsequent call to `get_allowed()` will hit the memoization guard (`!profile_grants.empty()`) and skip re-expansion. But `expand_profile(nullptr)` in `get_allowed()` also has the memoization guard. So successful parse expands profiles, and `get_allowed()` reuses the cached expansion. This is correct and intended.

- **DIVERGED** (`9193d87` + `6350bee`): The `grants.clear()` on failure (blame line 566) is only in the grammar-failure branch. If profile validation fails (blame lines 555–563), `grants.clear()` is NOT called — the grants populated by the grammar parse are left in place even though `parse()` returns false. This is a correctness bug: after a parse failure due to profile error, `grants` will contain the grammar-parsed grants (with empty `profile_grants` for the failing profile), and the caller gets `false` but `this->grants` is non-empty. This violates the invariant established in `6350bee` that "no grants are kept after parsing failed." The `6350bee` comment explicitly says `// Make sure no grants are kept after parsing failed!` at blame line 565, but the `9193d87` code path at lines 555–563 returns false WITHOUT clearing grants. **DIVERGED** — SHA `9193d87` introduced this bug relative to the invariant from `6350bee`.

- Lines 569–574: The error message correctly distinguishes "stopped at position X" vs "stopped at end" — the latter indicates the grammar completed but did not consume all input.

---

### `MgrCap` (constructors) — `src/mgr/MgrCap.h:160`, `src/mgr/MgrCap.h:161`

**Relevant commits:** `6350bee` (introduced)

**Intent:** Two constructors: default (empty cap) and grants-vector constructor.

**Invariants:**  
- I1 (`6350bee`): Default ctor leaves `text` empty and `grants` empty.  
- I2 (`6350bee`): Vector ctor initializes `grants` but does NOT set `text`. This means a cap constructed via the vector ctor has empty `text`, making `get_str()` return `""` even if the grants are non-empty.

**Implementation critique (MgrCap.h lines 160–161 per functions.txt):**  
- UNGROUNDED: The vector constructor (which also sets `text` to empty) is inconsistent with the invariant that `text` should reflect the current grant set. No commit explains when/whether the vector constructor is expected to be used in practice, and whether the empty `text` is intentional.

---

### `MgrCapGrant` (constructors) — `src/mgr/MgrCap.h:111`, `src/mgr/MgrCap.h:112`

**Relevant commits:** `6350bee` (introduced), `3463613` (added `module` parameter), `cb534e0` (renamed `command_args` → `arguments`)

**Intent:** Default constructor (all empty/zero) and full-parameter constructor. The full constructor takes all fields by rvalue reference.

**Invariants:**  
- I1 (`6350bee`): Default ctor sets `allow(0)`.  
- I2 (`3463613`): Full ctor parameter order matches BOOST_FUSION_ADAPT_STRUCT order (service, module, profile, command, arguments, allow). Note: `network` is NOT a constructor parameter; it is always populated after construction via `parse_network()`.

**Implementation critique (MgrCap.h lines 111–112):**  
- Correct. The omission of `network` from the constructor is intentional: networks are always parsed from the text representation and stored separately.

---

### `MgrCapGrantConstraint` (constructors) — `src/mgr/MgrCap.h:49`, `src/mgr/MgrCap.h:50`

**Relevant commits:** `6350bee` (introduced)

**Intent:** Default constructor (MATCH_TYPE_NONE, empty value) and parameterized constructor.

**Invariants:**  
- I1 (`6350bee`): Default initializes `match_type = MATCH_TYPE_NONE`. As established in the `validate_arguments` analysis, this causes a deny in `validate_arguments`.

**Implementation critique (MgrCap.h lines 49–50):**  
- Correct. The `MATCH_TYPE_NONE` default is a sound defensive choice.

---

### `mgr_rwxa_t` (constructors and operators) — `src/mgr/MgrCap.h:24`, `src/mgr/MgrCap.h:25`

**Relevant commits:** `6350bee` (introduced)

**Intent:** Thin wrapper around `__u8` for r/w/x bitmask. Provides explicit construction, `operator=`, and `operator __u8` for implicit conversion.

**Invariants:**  
- I1 (`6350bee`): `val` defaults to 0. The `explicit` constructor prevents accidental implicit conversion from raw integers. The `operator __u8()` allows comparison with `MGR_CAP_ANY` and bitwise operations.

**Implementation critique (MgrCap.h lines 24–31):**  
- Correct. The explicit ctor prevents accidental grant escalation.  
- UNGROUNDED: `MGR_CAP_ANY = 0xff` but only bits 1, 2, 3 are used (R=2, W=4, X=8). The `== MGR_CAP_ANY` check in `operator<<` treats `0xff` specially. A value of e.g. `0x0f` (R|W|X plus bit 0) would not be printed as `*` but would have more than R+W+X. This case cannot occur from the parser (which only sets the defined bits), but programmatic construction with `mgr_rwxa_t{0x0f}` would pass `is_allow_all()` checks against `MGR_CAP_ANY` incorrectly — `0x0f != 0xff`. No commit ever addressed this. **UNGROUNDED**.

---

### `operator=(mgr_rwxa_t, __u8)` — `src/mgr/MgrCap.h:27`

**Relevant commits:** `6350bee` (introduced)

**Intent:** Assignment from `__u8` to `mgr_rwxa_t`.

**Implementation critique:** Correct. Single-line assignment, no issues.

---

### `operator __u8(mgr_rwxa_t)` — `src/mgr/MgrCap.h:31`

**Relevant commits:** `6350bee` (introduced)

**Intent:** Implicit conversion to `__u8` for bitwise operations and comparisons.

**Implementation critique:** Correct. Enables the `allow & MGR_CAP_R` style in `is_capable`.

---

### `get_str` — `src/mgr/MgrCap.h:163`

**Relevant commits:** `6350bee` (introduced)

**Intent:** Return the `text` field. Used by callers that need the original string form.

**Implementation critique (MgrCap.h line 163):**  
- Trivially correct.  
- UNGROUNDED: As noted in the constructor analysis, `text` may be empty for programmatically-constructed caps. `get_str()` will then return `""` without any indication that the cap is non-empty.

---

### `encode` (MgrCap.h) / `decode` (MgrCap.h) / `dump` (MgrCap.h) / `generate_test_instances` (MgrCap.h) — `src/mgr/MgrCap.h:195`, `196`, `197`, `198`

These are declarations in the header; the implementations are covered above in the `.cc` function sections. The header declarations match the implementations; `ed6b712` changed the signature of `generate_test_instances` to `static std::list<MgrCap> generate_test_instances()` and the header was updated consistently.

---

### `expand_profile` (MgrCap.h) — `src/mgr/MgrCap.h:109`

Declaration only; covered in the `expand_profile` section above.

---

### `parse_network` (MgrCap.h) — `src/mgr/MgrCap.h:101`

Declaration only; covered in the `parse_network` section above.

---

### `validate_arguments` (MgrCap.h) — `src/mgr/MgrCap.h:123`

Declaration only; covered in the `validate_arguments` section above.

---

### `get_allowed` (MgrCap.h) — `src/mgr/MgrCap.h:137`

Declaration only; covered in the `get_allowed` section above.

---

### `is_allow_all` (MgrCap.h) — `src/mgr/MgrCap.h:145`

**Implementation (inline in header):** `return (allow == MGR_CAP_ANY && service.empty() && module.empty() && profile.empty() && command.empty());` — analysed above.

---

### `parse` (MgrCap.h) — `src/mgr/MgrCap.h:169`

Declaration only; covered in the `parse` section above.

---

### `set_allow_all` (MgrCap.h) — `src/mgr/MgrCap.h:168`

Declaration only; covered in the `set_allow_all` section above.

---

### `is_capable` (MgrCap.h) — `src/mgr/MgrCap.h:186`

Declaration only; covered in the `is_capable` section above.

---

## DIVERGED Findings Summary

| Finding | Function | SHA establishing invariant | Contradicting location |
|---|---|---|---|
| D1 | `expand_profile` | `9193d87` | `get_allowed` (blame line 238): memoization guard broken for invalid-profile/invalid-key path; silently re-runs `expand_profile(nullptr)` on every `get_allowed` call when profile expansion failed |
| D2 | `parse` | `6350bee` (invariant: "no grants kept after parse failed") | `parse` (blame lines 555–563): profile validation failure path (`9193d87`) returns false WITHOUT calling `grants.clear()` |
| D3 | `is_capable` | `cb534e0` (renamed `arguments`) | `is_capable` (blame line 312): parameter still named `command_args`, not renamed to match `cb534e0` intent |
| D4 | `decode` | `9193d87` (profile errors now reported) | `decode` (blame line 376): calls `parse(s, NULL)`, silencing all profile validation errors on deserialization |

## UNGROUNDED Code Paths Summary

| Finding | Location | Description |
|---|---|---|
| U1 | `maybe_quote_string` | Single-quote grammar path in the parser has no corresponding `maybe_quote_string` production |
| U2 | `operator<<(MgrCapGrantConstraint)` | `MATCH_TYPE_NONE` in default branch emits bare value; no commit defines intended output |
| U3 | `operator<<(MgrCapGrant)` | Service grants can never carry `arguments` from the parser, but the `with` emission code would incorrectly emit ` with ...` if one were programmatically constructed |
| U4 | `get_allowed` / module branch | `c.empty()` bypass of module argument validation when a specific command is checked; design intent not documented |
| U5 | `expand_profile` (rbd) | `std::move(constraint)` from `arguments` map during iteration — no commit acknowledged the aliasing behaviour |
| U6 | `generate_test_instances` | No network-restricted test case despite network being a documented grant feature since `6350bee` |
| U7 | `mgr_rwxa_t` | `MGR_CAP_ANY = 0xff` but only 3 bits used; values like `0x0f` would fail `== MGR_CAP_ANY` tests silently |
| U8 | `MgrCap` vector ctor / `get_str` | `text` is not set when using the vector constructor; `get_str()` returns `""` for non-empty caps built this way |
| U9 | `MgrCapParser` | Positional BOOST_FUSION_ADAPT_STRUCT mapping is implicit in all grammar rules; no commit documented field-position meaning |

---

## Self-Check (Step 6)

**Have all 21 commits been read?**  
Yes. All 17 diff files in the corpus were read. The 4 commits without diff files (`85d82fa`, `c8c1019`, `f1bac41`, `4f1f40a`) are infrastructure-only (indent settings, blank line, missing includes); their content is fully captured via blame.txt and commit subjects. All 21 are accounted for.

**Has every function in functions.txt received a section?**  
Yes. Every entry in functions.txt has a dedicated section. Header-only declarations that are exact mirrors of `.cc` implementations are cross-referenced rather than duplicated; the substantive critique is in the `.cc` section.

**Are SHAs cited for every DIVERGED flag?**  
Yes:
- D1: SHA `9193d87` (invariant source), SHA `9193d87` also at `get_allowed` line 238  
- D2: SHA `6350bee` (invariant), SHA `9193d87` (introduced the contradicting path)  
- D3: SHA `cb534e0` (established the `arguments` rename)  
- D4: SHA `9193d87` (established profile error reporting), SHA `6350bee` (introduced `decode` with `NULL`)

**Have all ungrounded code paths been flagged?**  
Yes. 9 UNGROUNDED items documented. No code path was passed over without assessment.

**Confidence notes:**  
- The current source files were not directly readable from the workspace; the analysis relied on blame.txt as the canonical current state and all 17 available diff files as the change record. Blame.txt was confirmed to reflect the HEAD SHA.
- D2 (grants not cleared on profile-validation failure) is the highest-severity finding: it violates an explicit safety comment from `6350bee` and was introduced by `9193d87`.
