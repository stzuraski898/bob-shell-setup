# Intent Artefact — DaemonHealthMetric

**Corpus path:** `BobOutput/Object History/v4/DaemonHealthMetric/`  
**Assessment date:** 2026-09-11 (corpus collected_at)  
**HEAD SHA:** `8681fa6ebac230f86eb445bf57095c63e7f1abcc`  
**Total non-merge commits in corpus:** 11  
**Date range:** 2017-10-23 (`f4b74125`) → 2026-03-19 (`55da168f`)  
**Files covered:** `src/mgr/DaemonHealthMetric.h`, `src/mgr/DaemonHealthMetric.cc`  
**Rename chain:** `src/osd/OSDHealthMetric.h` → `src/mgr/DaemonHealthMetric.h` (at `714ffe0d`); `src/mgr/DaemonHealthMetric.cc` created at `437e8949`

---

## Commit Inventory

| # | SHA (short) | Date | Author | Subject |
|---|-------------|------|--------|---------|
| 1 | `f4b74125` | 2017-10-23 | Kefu Chai | osd: send health-checks to mgr |
| 2 | `714ffe0d` | 2018-03-13 | Shanchun Lv | mgr,osd: make osd_metric more popular |
| 3 | `adc480e3` | 2018-04-30 | Sage Weil | mgr: print daemon_health_metrics to debug log |
| 4 | `550c8102` | 2019-03-28 | Adam C. Emerson | mgr: Update DaemonHealthMetric.h to work without using namespace |
| 5 | `5a2b7c25` | 2022-11-11 | Pere Diaz Bou | mgr/prometheus: expose daemon health metrics |
| 6 | `899276a5` | 2023-06-28 | Nitzan Mordechai | ceph-dencoder: osd - Add missing types |
| 7 | `09f3c879` | 2023-07-25 | Nitzan Mordechai | ceph-dencoder: MDS - Add missing types |
| 8 | `ed6b7124` | 2025-06-09 | Kefu Chai | src: Fix memory leaks in generate_test_instance() by returning values instead of pointers |
| 9 | `437e8949` | 2025-08-14 | Max Kellermann | mgr/DaemonHealthMetric: un-inline methods to reduce header dependencies |
| 10 | `85d82faa` | 2025-10-01 | Edwin Rodriguez | Update indent settings h |
| 11 | `55da168f` | 2026-03-19 | Max Kellermann | mgr/DaemonHealthMetric: add missing includes |

---

## Rename Chain

- `src/osd/OSDHealthMetric.h` introduced at `f4b74125` (2017-10-23) with types `osd_metric`, `osd_metric_t`, `OSDHealthMetric`.
- `src/mgr/DaemonHealthMetric.h` created at `714ffe0d` (2018-03-13) as a copy-rename: all OSD-specific names replaced with daemon-generic names (`daemon_metric`, `daemon_metric_t`, `DaemonHealthMetric`). The header became a manager-layer type, decoupled from OSD.
- `src/mgr/DaemonHealthMetric.cc` created at `437e8949` (2025-08-14) by moving three previously inline methods out of the header.

---

## Data Model

### `enum class daemon_metric : uint8_t`

Established at `f4b74125` (as `osd_metric`), renamed to `daemon_metric` at `714ffe0d`.

| Enumerator | Established | Description |
|------------|-------------|-------------|
| `SLOW_OPS` | `f4b74125` | OSD/MON slow-op count |
| `PENDING_CREATING_PGS` | `f4b74125` | PGs waiting to be created (uses n1+n2 pair) |
| `NONE` | `f4b74125` | Default / unset value |

**Encoding contract (established `f4b74125`):** enum is encoded as `uint8_t` in DENC; the encoded payload for the `uint64_t n` field is the raw union value (which overlaps n1/n2). Schema version is locked at `DENC_START(1, 1, p)` — no version migrations have ever been applied.

### `union daemon_metric_t`

Established at `f4b74125`. A `uint64_t n` overlapping a struct of two `uint32_t` (`n1`, `n2`). Constructor `daemon_metric_t(uint32_t, uint32_t)` initialises via the struct members; constructor `daemon_metric_t(uint64_t = 0)` initialises via `n`. This union is architecture-endian-sensitive when the pair interpretation is used: n1 occupies the low word and n2 the high word on little-endian platforms, but no endian annotation is present in the code.

### `class DaemonHealthMetric`

Private members: `daemon_metric type = daemon_metric::NONE`, `daemon_metric_t value` (unordered initialisation via default constructor leaves `value.n` uninitialised — only `type` has a brace-or-equal initialiser).

---

## Function Analyses

### `daemon_metric_name` (`src/mgr/DaemonHealthMetric.h:20`)

**Established:** `adc480e3` (2018-04-30) — added to support printing metrics to the debug log.  
**Blame:** all lines in the function attributed to `adc480e3`.

**Contract:**
- Maps every known `daemon_metric` enumerator to a C-string literal.
- `default: return "???"` — intentional fallback for unknown/future values, established at `adc480e3`.
- Is `static inline` — header-only linkage.

**Invariants:**
- Every enumerator listed in the `daemon_metric` enum must have a matching `case` in this switch; `NONE` is explicitly covered (`adc480e3`).
- The `default` arm is not dead: it is load-bearing for any future enumerator added to the enum without updating this function.

**Implementation critique (blame.txt h:20–27):**

The current implementation covers `SLOW_OPS`, `PENDING_CREATING_PGS`, and `NONE`, matching the full `daemon_metric` enum. The `default: return "???"` arm is correctly present.

- **OVERCAUTIOUS — minor:** The `default` arm at h:26 is sound and load-bearing (not overcautious), but the function signature is `static inline const char*`. Because it is called from `get_type_name()` (which constructs a `std::string`) and from the `operator<<` defined in `DaemonHealthMetric.cc`, the `static inline` means every translation unit that transitively includes the header gets its own copy. The `437e8949` un-inline pass did not un-inline this function. This is not a correctness divergence but is inconsistent with the stated goal of `437e8949`.

No DIVERGED finding.

---

### `daemon_metric_t(uint32_t, uint32_t)` (`src/mgr/DaemonHealthMetric.h:35`)  
### `daemon_metric_t(uint64_t = 0)` (`src/mgr/DaemonHealthMetric.h:38`)

**Established:** `f4b74125` (2017-10-23) on the structurally identical `osd_metric_t`; carried forward at `714ffe0d` verbatim.  
**Blame:** constructor bodies attributed to `f4b74125`.

**Contract:**
- `daemon_metric_t(uint32_t x, uint32_t y)`: initialises the pair `(n1=x, n2=y)`. Intended for `PENDING_CREATING_PGS` and any future two-field metric.
- `daemon_metric_t(uint64_t x = 0)`: initialises `n` to `x`. Intended for single-value metrics like `SLOW_OPS`. Default of `0` represents the empty/unset state.
- The union provides a view aliasing between `n` and `(n1,n2)`. No formal contract on endianness.

**Invariants:**
- When `daemon_metric_t(uint32_t, uint32_t)` is used, `n1` and `n2` are the semantically meaningful fields; `n` reads back their combined bit pattern.
- When `daemon_metric_t(uint64_t)` is used, `n1` and `n2` read back the low/high halves of `n` (platform-dependent split).
- DENC always serialises `v.value.n` (the full 64-bit field), regardless of which constructor was used — established at `f4b74125`.

**Implementation critique (blame.txt h:35–40):**

The constructors are correct per contract.

- **UNGROUNDED:** The use of `n1`/`n2` from a `uint64_t`-constructed union, and `n` from a pair-constructed union, relies on the C++ union aliasing rules. For `SLOW_OPS`, `generate_test_instances` constructs `DaemonHealthMetric(daemon_metric::SLOW_OPS, 1)` using the `uint64_t` path, so `get_n()` returns `1` and `get_n1()`/`get_n2()` return the low/high 32-bit halves (i.e., `get_n1() == 1`, `get_n2() == 0` on little-endian). `dump()` emits all three, which means `n1=1, n2=0` for a SLOW_OPS metric. There is no comment or assertion constraining which interpretation applies to which `daemon_metric` value. The pairing between metric type and value constructor is UNGROUNDED — no commit has ever documented it.

No DIVERGED finding.

---

### `DaemonHealthMetric()` (default constructor, `src/mgr/DaemonHealthMetric.h:46`)

**Established:** `f4b74125` (as `OSDHealthMetric() = default`), renamed at `714ffe0d`.  
**Blame:** line h:46 attributed to `714ffe0d`.

**Contract:**
- Produces a metric with `type = daemon_metric::NONE` (from the brace initialiser on the member) and `value` uninitialised (no brace-or-equal initialiser on `daemon_metric_t value`).

**Invariants:**
- The default-constructed `type` is always `daemon_metric::NONE` (invariant established `f4b74125`/`714ffe0d`).
- `value` is intentionally uninitialised after default construction. No commit has ever added a zero-initialisation for `value` in the default constructor, and `daemon_metric_t(uint64_t = 0)` is not called by `= default`.

**Implementation critique (blame.txt h:46):**

The `= default` constructor leaves `value.n` uninitialised. Because `daemon_metric_t` has no user-provided default constructor (only the `uint64_t = 0` converting constructor), the `= default` synthesised constructor does not call it. Reading `get_n()`, `get_n1()`, or `get_n2()` on a default-constructed `DaemonHealthMetric` produces undefined behaviour.

- **UNGROUNDED:** No commit has documented whether this is intentional (callers always check `type != NONE` before reading `value`) or accidental. The `generate_test_instances` function does not include a default-constructed instance, which suggests callers are not expected to encounter one — but this is never enforced by assertion or `[[nodiscard]]` contract. This is UNGROUNDED.

No DIVERGED finding relative to any specific commit — the uninitialised state has been present since `f4b74125` and was never corrected.

---

### `DaemonHealthMetric(daemon_metric type_, uint64_t n)` (`src/mgr/DaemonHealthMetric.h:47`)

**Established:** `f4b74125` (as `OSDHealthMetric(osd_metric, uint64_t)`), renamed `714ffe0d`.  
**Blame:** h:47 attributed to `714ffe0d`, initialiser list h:48 attributed to `f4b74125`.

**Contract:**
- Sets `type` and `value.n`. Used for single-value metrics (`SLOW_OPS`).
- No precondition on the value of `type_`; any `daemon_metric` enumerator (including `NONE`) is accepted.

**Implementation critique (blame.txt h:47–49):**

No divergence from the original contract. Correctly delegates to `daemon_metric_t(uint64_t)`.

---

### `DaemonHealthMetric(daemon_metric type_, uint32_t n1, uint32_t n2)` (`src/mgr/DaemonHealthMetric.h:50`)

**Established:** `f4b74125` (as `OSDHealthMetric(osd_metric, uint32_t, uint32_t)`), renamed `714ffe0d`.  
**Blame:** h:50 attributed to `714ffe0d`, initialiser list h:51 attributed to `f4b74125`, h:52 attributed to `f4b74125`, with trailing whitespace introduced at `5a2b7c25` (the prometheus commit which added only cosmetic space).

**Contract:**
- Sets `type` and `value(n1, n2)`. Used for two-value metrics (`PENDING_CREATING_PGS`).

**Implementation critique (blame.txt h:50–52):**

- **UNGROUNDED (minor):** Trailing whitespace character on h:51 introduced by `5a2b7c25` has no functional effect but the diff shows `value(n1, n2) ` with trailing space. This is cosmetic noise with no documented intent.

No DIVERGED finding.

---

### `get_type()` (`src/mgr/DaemonHealthMetric.h:54`)

**Established:** `f4b74125`, renamed `714ffe0d`.  
**Blame:** h:54–56 attributed to `714ffe0d` (signature) and `f4b74125` (body).

**Contract:**
- Returns the `daemon_metric` enumerator of this metric instance.
- `const` — does not modify state.

**Implementation critique (blame.txt h:54–56):**

Implementation is exact per contract. No divergence.

---

### `get_n()` (`src/mgr/DaemonHealthMetric.h:57`)

**Established:** `f4b74125`.  
**Blame:** h:57–59 attributed to `f4b74125`.

**Contract:**
- Returns `value.n` — the full 64-bit union view.
- For a pair-constructed metric (`PENDING_CREATING_PGS`), this returns the combined 64-bit value of `(n1, n2)`, not a single meaningful counter.

**Implementation critique (blame.txt h:57–59):**

- **UNGROUNDED:** No commit documents whether `get_n()` is safe to call on a pair-constructed metric. `dump()` emits `n`, `n1`, and `n2` for all metric types (established `899276a5`), meaning consumers of the dump format will see a redundant and potentially confusing `n` field for `PENDING_CREATING_PGS` metrics (where the meaningful data is in `n1` and `n2`). The `operator<<` also emits all three fields for all types. No commit has ever added a type-gate.

No DIVERGED finding.

---

### `get_n1()` (`src/mgr/DaemonHealthMetric.h:60`)

**Established:** `f4b74125`.  
**Blame:** h:60–62 attributed to `f4b74125`.

**Contract:**
- Returns `value.n1` — the low 32-bit word of the union.
- For a `uint64_t`-constructed metric (`SLOW_OPS`), returns the low 32 bits of the value (meaningful only if the original value fit in 32 bits).

**Implementation critique:** No divergence. See UNGROUNDED note under `get_n()`.

---

### `get_n2()` (`src/mgr/DaemonHealthMetric.h:63`)

**Established:** `f4b74125`.  
**Blame:** h:63–65 attributed to `f4b74125`.

**Contract:**
- Returns `value.n2` — the high 32-bit word of the union.
- For a `uint64_t`-constructed metric where the value fits in 32 bits, this returns 0.

**Implementation critique:** No divergence. See UNGROUNDED note under `get_n()`.

---

### `DENC` (`src/mgr/DaemonHealthMetric.h:67`)

**Established:** `f4b74125` (as part of `OSDHealthMetric`), renamed at `714ffe0d`.  
**Blame:** h:67 `DENC` macro line attributed to `714ffe0d`; h:68–72 body attributed to `f4b74125`.

**Contract:**
- Schema version `DENC_START(1, 1, p)`: v=1, compat=1. No backwards-compatibility read path for any future version change. Established at `f4b74125`.
- Encodes `v.type` (as `uint8_t`) then `v.value.n` (as `uint64_t`).
- Encoding always uses `v.value.n` regardless of whether the metric was constructed with the pair or the scalar path — this is intentional per the original design (`f4b74125`).
- `WRITE_CLASS_DENC(DaemonHealthMetric)` at h:84 (attributed `714ffe0d`) registers this class for denc-based serialisation.

**Invariants:**
- The encoding schema version is frozen at 1/1. Any field addition would require bumping the version and adding a conditional decode path.
- The encoded `n` field is the union `uint64_t` — it subsumes both `n1` and `n2`. This means pair-constructed metrics round-trip correctly via DENC.

**Implementation critique (blame.txt h:67–72):**

Implementation is exact per contract.

- **OVERCAUTIOUS — note:** The `DENC_START(1, 1, p)` with compat==1 means any version bump would require all readers to be updated simultaneously. No migration path has ever been added. This is consistent with the history but represents a brittleness in the schema that was never addressed.

No DIVERGED finding.

---

### `dump` (declaration: `src/mgr/DaemonHealthMetric.h:73`; definition: `src/mgr/DaemonHealthMetric.cc:10`)

**History:**
1. `899276a5` (2023-06-28, Nitzan Mordechai): Added `dump(Formatter *f)` as an inline method in the header, using unqualified `Formatter*`. Also added `#include "common/Formatter.h"` to the header. Motivation: ceph-dencoder requires `dump` for encode/decode testing (tracker issue #61788).
2. `09f3c879` (2023-07-25, Nitzan Mordechai): Added a duplicate `#include "common/Formatter.h"` — the diff shows the include was already present from `899276a5` and was added again. The resulting header had two identical `#include "common/Formatter.h"` lines. Motivation was unrelated (MDS types) but the file was touched.
3. `437e8949` (2025-08-14, Max Kellermann): Moved `dump` out of the header into `DaemonHealthMetric.cc`. Changed `Formatter*` to `ceph::Formatter*` (forward-declared in header via `namespace ceph { class Formatter; }`). Removed the duplicate `#include "common/Formatter.h"` from the header, adding `<iosfwd>` and `<string>` instead. Removed the heavy `#include "common/Formatter.h"` from the header entirely (replaced by forward declaration). The duplicate `#include "common/Formatter.h"` was introduced by `09f3c879` and eliminated by `437e8949`.

**Blame (DaemonHealthMetric.cc:10–15):**
- Line 10 (function signature): `437e8949`
- Lines 11–14 (body): `899276a5` (copied from old inline position in the header)
- Line 15 (`}`): `437e8949`

**Contract:**
- Emits four fields to the formatter: `"type"` (string, via `get_type_name()`), `"n"` (int, via `get_n()`), `"n1"` (int, via `get_n1()`), `"n2"` (int, via `get_n2()`). Established at `899276a5`.
- Required for ceph-dencoder compatibility (tracker #61788). Function must not be removed without updating ceph-dencoder registration.
- Uses `ceph::Formatter*` (qualified name) — established at `437e8949` when the forward declaration replaced the full include.

**Invariants:**
- Must emit exactly the four fields `type`, `n`, `n1`, `n2` in that order — this is the dencoder contract. Any reordering or addition/removal must be treated as a schema change.

**Implementation critique (`DaemonHealthMetric.cc:10–15`):**

Implementation at cc:10–15 matches the contract exactly: four fields in the correct order, all via public accessor methods.

- **UNGROUNDED:** `dump()` emits all three of `n`, `n1`, `n2` unconditionally. For `SLOW_OPS` (scalar-constructed), `n1` and `n2` are the low/high halves of the slow-op count; for `PENDING_CREATING_PGS` (pair-constructed), `n` is the combined 64-bit view of `(n1,n2)`. A consumer reading `"n"` for `PENDING_CREATING_PGS` or reading `"n1"`/`"n2"` for `SLOW_OPS` gets technically valid but semantically misleading data. No commit has added a comment or conditional to make this explicit.

No DIVERGED finding.

---

### `generate_test_instances` (declaration: `src/mgr/DaemonHealthMetric.h:74`; definition: `src/mgr/DaemonHealthMetric.cc:17`)

**History:**
1. `899276a5` (2023-06-28, Nitzan Mordechai): Added as `static void generate_test_instances(std::list<DaemonHealthMetric*>& o)` — raw-pointer list output parameter, heap-allocates instances with `new`. Motivation: ceph-dencoder compatibility (tracker #61788).
2. `ed6b7124` (2025-06-09, Kefu Chai): Changed signature to `static std::list<DaemonHealthMetric> generate_test_instances()` — returns a value-type list, eliminates `new`. Motivation: ASan memory leak reports; callers were not reliably freeing the raw pointers. The body was rewritten to push value instances directly.
3. `437e8949` (2025-08-14, Max Kellermann): Moved the function body out of the header into `DaemonHealthMetric.cc`. No semantic change.

**Blame (DaemonHealthMetric.cc:17–24):**
- Line 17 (signature): `437e8949`
- Lines 18–21 (body): `ed6b7124`
- Line 22 (`}`): `899276a5` (closing brace survived as pre-existing line)

**Contract:**
- Returns a `std::list<DaemonHealthMetric>` (value semantics, since `ed6b7124`).
- Must include at least one instance per semantically distinct constructor path: one scalar (`SLOW_OPS, 1`) and one pair (`PENDING_CREATING_PGS, 1, 2`). Established at `899276a5`.
- Used by ceph-dencoder to exercise round-trip encode/decode. Adding a new `daemon_metric` enumerator without adding a corresponding test instance constitutes a gap in dencoder coverage.

**Invariants (from `ed6b7124`):**
- Return type is `std::list<DaemonHealthMetric>` (not a pointer list). Callers must not cast to pointer-list.
- The function must be `static`.

**Implementation critique (`DaemonHealthMetric.cc:17–24`):**

Implementation matches the contract.

- **OVERCAUTIOUS:** The list constructs only two instances — `SLOW_OPS` and `PENDING_CREATING_PGS`. `NONE` is never included. Since `NONE` can be default-constructed and the DENC round-trip of a `NONE`-typed metric is valid, not including it is a minor gap in dencoder coverage. However, no commit has ever stated that `NONE` should be tested, so this is not a DIVERGED finding — it is a coverage note.

No DIVERGED finding.

---

### `operator<<` (declaration: `src/mgr/DaemonHealthMetric.h:79`; definition: `src/mgr/DaemonHealthMetric.cc:24`)

**History:**
1. `adc480e3` (2018-04-30, Sage Weil): Introduced as an inline `friend` of `DaemonHealthMetric` inside the class body. Used unqualified `ostream`. Format: `NAME(n|(n1,n2))`.
2. `550c8102` (2019-03-28, Adam C. Emerson): Changed `ostream` to `std::ostream` (qualified). Motivation: file was used in contexts without `using namespace std`.
3. `437e8949` (2025-08-14, Max Kellermann): Moved body out of the header; the header retains `friend std::ostream& operator<<(std::ostream& out, const DaemonHealthMetric& m);` as a non-inline declaration. The implementation in `DaemonHealthMetric.cc` is a free function (not a member), consistent with the friend declaration pattern.

**Blame (DaemonHealthMetric.cc:24–27):**
- Line 24 (signature): `437e8949`
- Lines 25–26 (body): `adc480e3` (copied from the old inline position)
- Line 27 (`}`): `adc480e3`

**Contract:**
- Produces a human-readable string in the format: `TYPE_NAME(n|(n1,n2))`.
- Must use `daemon_metric_name()` for the type field (established `adc480e3`).
- Must include all three numeric fields in the specified format.

**Implementation critique (`DaemonHealthMetric.cc:24–27`):**

Implementation matches contract exactly.

- **UNGROUNDED:** The format `name(n|(n1,n2))` outputs the combined 64-bit view `n` alongside the pair `(n1,n2)`. For `SLOW_OPS`, `n1` and `n2` represent the low/high 32-bit halves of a slow-op count, which is likely to confuse log readers who see `SLOW_OPS(42|(42,0))`. No commit has explained whether this format is intentional for diagnostic purposes or is simply a consequence of the union structure being exposed uniformly. This is UNGROUNDED.

No DIVERGED finding.

---

### `get_type_name()` (`src/mgr/DaemonHealthMetric.h:75`)

**Established:** `5a2b7c25` (2022-11-11, Pere Diaz Bou) — added to support the prometheus metrics exposition path.  
**Blame:** h:75–77 attributed to `5a2b7c25`.

**Contract:**
- Wraps `daemon_metric_name(get_type())`, returning a `std::string`.
- Must always delegate to `daemon_metric_name` — the string representation must be consistent between `dump()`, `operator<<`, and this method (all three use `daemon_metric_name` as the source of truth).

**Invariants:**
- The return type is `std::string` (not `const char*`). This was chosen to allow Prometheus label string construction (`5a2b7c25`).
- The function is `const`.

**Implementation critique (blame.txt h:75–77):**

Implementation is correct per contract. Delegation to `daemon_metric_name` ensures consistency with `dump()` and `operator<<`.

- **Note:** `get_type_name()` is the only public method that returns a `std::string` (rather than a fixed-size integer or a `const char*`). It remains inline in the header even after the `437e8949` un-inline pass. The inline body calls `daemon_metric_name()` (also inline), resulting in a trivial construction of a `std::string` from a string literal. There is no observable inconsistency with the `437e8949` intent — `get_type_name()` does not pull in heavy headers (it calls only `daemon_metric_name` which is already in the header). Not flagged.

No DIVERGED finding.

---

## Cross-Cutting Observations

### Include Hygiene (not a function, but structurally important)

**History:**
- `f4b74125`: Header included `<cstdint>` and `"include/denc.h"`. No `<ostream>` (no streaming operator yet).
- `adc480e3`: Added `<ostream>` for the inline `operator<<`.
- `899276a5`: Added `#include "common/Formatter.h"` for `dump()`.
- `09f3c879`: Added a **duplicate** `#include "common/Formatter.h"` — a clear oversight, not intentional.
- `55da168f` (2026-03-19): Added `<list>` and `<string>` to fix transitive-include breakage.
- `437e8949`: Replaced `#include "common/Formatter.h"` (both copies) with a forward declaration `namespace ceph { class Formatter; }`, replaced `<ostream>` with `<iosfwd>` to reduce header weight.

**DIVERGED — `09f3c879` (2023-07-25):**  
The MDS missing-types commit introduced a duplicate `#include "common/Formatter.h"` at h:9 (already present from `899276a5`). This was an unclean copy-paste error. The duplicate existed from `09f3c879` until it was cleaned up by `437e8949`. Between those two commits the header compiled correctly (duplicate includes are idempotent due to `#pragma once` on the included file), but the duplicate was a code smell. It is now resolved.

**Note on `55da168f` ordering:** The `55da168f` commit (2026-03-19, "add missing includes") added `<list>` and `<string>` to the header *before* `437e8949`'s un-inline pass in the git log. However, the corpus records `55da168f` as the newest non-merge commit (HEAD is `8681fa6e`, and the corpus was collected with `55da168f` as the most recent touching commit). The index trail in the diffs shows:

- `85d82faa` (`6a2eb337`→parent): indent-only  
- `55da168f` (`6a2eb337`→`8081d0a6`): adds `<list>`, `<string>`, `<ostream>`, `"common/Formatter.h"` × 2  
- `437e8949` (`8081d0a6`→`26381375`): un-inlines, replaces `<ostream>` with `<iosfwd>`, removes both `Formatter.h` copies

So the correct sequence is: `85d82faa` → `55da168f` → `437e8949`, which matches the commit dates (2025-10-01 → 2026-03-19 → 2025-08-14 as recorded, but the index chain confirms the patch ordering). The commits.txt lists them newest-first as `437e8949` (2025-08), `55da168f` (2026-03), `85d82faa` (2025-10) — the 2026-03-19 date on `55da168f` post-dates `437e8949`'s 2025-08-14 date, which means the current HEAD state has `55da168f` applied on top of `437e8949`. The current header (from blame.txt) includes `<list>` (from `55da168f`) and `<iosfwd>` (from `437e8949`), confirming both are active.

---

## DIVERGED Findings Summary

| ID | Function / Element | Commit establishing contract | Contradicting line | Description |
|----|--------------------|-----------------------------|--------------------|-------------|
| D1 | Include header | `899276a5` | header (pre-`437e8949`) | Duplicate `#include "common/Formatter.h"` introduced by `09f3c879`; existed until `437e8949`. Now **resolved**. |

No currently active DIVERGED findings remain in the HEAD state.

---

## UNGROUNDED Findings Summary

| ID | Location | Description |
|----|----------|-------------|
| U1 | `daemon_metric_t` union; `get_n()`, `get_n1()`, `get_n2()` | No documented invariant linking `daemon_metric` type to the appropriate value-constructor path. `SLOW_OPS` → scalar, `PENDING_CREATING_PGS` → pair, but this is only derivable by reading callers, not from any assertion or comment in the class. |
| U2 | Default constructor `DaemonHealthMetric()` | `value` field is uninitialised. No assertion prevents reading `get_n()` on a default-constructed instance. No commit has documented that this is intentionally unsafe or safe. |
| U3 | `dump()` and `operator<<` | Emit all three of `n`, `n1`, `n2` unconditionally. For `SLOW_OPS` the pair fields are unintuitive; for `PENDING_CREATING_PGS` the `n` field is unintuitive. No commit explains whether this is by design for dencoder completeness or is an artefact of the union structure. |
| U4 | `operator<<` format | The format `NAME(n|(n1,n2))` was established purely for debug-log legibility (`adc480e3`). No formal format specification exists. Consumers that parse this output (e.g. log scrapers) are relying on undocumented formatting. |

---

## OVERCAUTIOUS Findings Summary

| ID | Location | Description |
|----|----------|-------------|
| OC1 | `daemon_metric_name()` | `static inline` function was not moved to the `.cc` file by the `437e8949` un-inline pass, while `dump()`, `generate_test_instances()`, and `operator<<` were. The function is header-only but small; this is a minor inconsistency with the stated goal of `437e8949`, not a bug. |
| OC2 | `generate_test_instances()` | Only exercises `SLOW_OPS` and `PENDING_CREATING_PGS`; `NONE` type is not tested. Minor dencoder coverage gap. |

---

## Self-Check

- [x] All 11 commits read and noted in inventory
- [x] Every function in functions.txt has a section: `dump` (cc:10), `generate_test_instances` (cc:17), `operator<<` (cc:24), `DENC` (h:67), `DaemonHealthMetric()` (h:46), `DaemonHealthMetric(type,n)` (h:47), `DaemonHealthMetric(type,n1,n2)` (h:50), `daemon_metric_name` (h:20), `daemon_metric_t(uint32,uint32)` (h:35), `daemon_metric_t(uint64)` (h:38), `dump` (h:73 — declaration), `generate_test_instances` (h:74 — declaration), `get_n` (h:57), `get_n1` (h:60), `get_n2` (h:63), `get_type` (h:54), `get_type_name` (h:75)
- [x] Every DIVERGED flag cites the specific commit (D1 → `09f3c879`, resolved by `437e8949`)
- [x] All UNGROUNDED code paths flagged (U1–U4)
- [x] Rename chain traced (OSD → DaemonHealthMetric)
- [x] commit_function_map.txt noted: all 11 commits map to "(no functions)" — ctags hunk-matching did not fire because commits touched structural elements (includes, class layout, whitespace) not captured as discrete named functions by ctags at their exact hunk lines. All commits were nevertheless fully analysed via direct diff reading.
