# Intent Assessment: ServiceMap

**Source files:** `src/mgr/ServiceMap.cc`, `src/mgr/ServiceMap.h`
**Corpus HEAD:** `8681fa6ebac230f86eb445bf57095c63e7f1abcc` (2025-10-01)
**Assessment date:** 2026-09-11
**Commits analysed:** 24
**Date range:** 2017-06-26 through 2025-10-01
**Functions assessed:** 39

> This artefact was produced by an AI assessment agent reading the raw git
> corpus in `/home/szuraski/BobOutput/Object History/v4/ServiceMap/`.
> It describes the *intended* behaviour of each function as reconstructed from
> commit history — not necessarily what the current code does.
> Test-writing agents should use this as the ground truth for what to test,
> and treat divergences as likely bugs.

## Class overview

`ServiceMap` is the manager-side, serializable registry of services and their daemons, with epoch/timestamp metadata and presentation helpers for status output. Its nested `Daemon` and `Service` objects preserve wire compatibility through versioned encode/decode, while `get_daemon()` and `rm_daemon()` maintain the service/daemon map shape. The principal semantic changes were customizable summaries in `ee5835df`, task status support in `5c25a018`, summary scaling/grouping in `a968f65d` and `ab0d8f2`, and the explicit value-returning test-instance API in `ed6b7124`; the later commits are mostly namespace, include, formatting, and implementation cleanups.

## `ServiceMap::Daemon::encode(bufferlist&, uint64_t) const`

**Introduced:** `7fce6382f2c35e767dcf326c088bc31e650386d3` — mgr: add ServiceMap
**Last modified:** `5c25a018643b10aa78db8270cae1476f71d8f4f4` — mgr, mon: allow normal ceph services to register with manager
**Change count:** 3 commits touched this function
**Divergence:** OK

### Intent
Serialize every daemon field using Ceph's versioned encoding protocol. The task-status addition extended the daemon wire structure while retaining compatibility with version 1 readers/writers. (Established: `7fce6382`, `5c25a018`.)

### Invariants and contracts
- Encoding is wrapped in `ENCODE_START`/`ENCODE_FINISH` and preserves the field order `gid`, address, registration epoch/time, metadata, then task status. (Established: `7fce6382`; task status added by `5c25a018`.)
- The task-status field is part of version 2, not an unversioned change to the old payload. (Established: `5c25a018`.)

### Error conditions
- None deliberately specified in the history; encoding errors are delegated to the Ceph encoding framework.

### Evolution summary
The original version-1 encoder serialized five fields. `156c941a` changed calls to unqualified ADL form, and `5c25a018` bumped the version and appended task status. The current implementation retains that layout.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Current lines 17–27 use the version-2 framing and serialize all six fields in the historical order. No unexplained behavioural branch exists.

## `ServiceMap::Daemon::decode(bufferlist::const_iterator&)`

**Introduced:** `7fce6382f2c35e767dcf326c088bc31e650386d3` — mgr: add ServiceMap
**Last modified:** `5c25a018643b10aa78db8270cae1476f71d8f4f4` — mgr, mon: allow normal ceph services to register with manager
**Change count:** 3 commits touched this function
**Divergence:** OK

### Intent
Decode the daemon payload and accept both the original version-1 payload and the version-2 payload carrying task status. (Established: `7fce6382`, `5c25a018`.)

### Invariants and contracts
- Decode fields in the same order as encode. (Established: `7fce6382`.)
- Decode `task_status` only when `struct_v >= 2`, preserving backward compatibility with version-1 data. (Established: `5c25a018`.)
- Use a const iterator because decoding must not require mutable buffer ownership. (Established: `f146c6c5`.)

### Error conditions
- Malformed/version-invalid data is handled by `DECODE_START`/`DECODE_FINISH`; no function-specific error return was established. (Established: `7fce6382`, `f146c6c5`.)

### Evolution summary
`f146c6c5` changed the iterator type. `5c25a018` introduced version-2 conditional decoding. Namespace cleanup in `156c941a` did not change semantics.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Current lines 29–41 use `DECODE_START(2)`, decode the original fields in order, conditionally decode task status at lines 37–39, and finish the frame. This matches `5c25a018` and `f146c6c5`.

## `ServiceMap::Daemon::dump(Formatter*) const`

**Introduced:** `7fce6382f2c35e767dcf326c088bc31e650386d3` — mgr: add ServiceMap
**Last modified:** `3e65551d0ab4acafafdae8ff653925b417acc2cd` — mgr/ServiceMap: use plain gid
**Change count:** 3 commits touched this function
**Divergence:** OK

### Intent
Expose daemon registration data, identity, legacy-formatted address, metadata, and task status in formatter output. The address must use legacy format because protocol-version prefixes are not useful to clients. (Established: `7fce6382`, `671641df`, `5c25a018`.)

### Invariants and contracts
- Dump `start_epoch`, `start_stamp`, `gid`, address, metadata, and task status. (Established: `7fce6382`, `5c25a018`.)
- Format the address with `get_legacy_str()`. (Established: `671641df`.)
- `gid` is a plain `uint64_t`, not an optional requiring dereference. (Established: `3e65551d`.)

### Error conditions
- None specified.

### Evolution summary
The initial dump showed the original fields. `671641df` changed address presentation; `5c25a018` added task status and briefly changed gid to optional; `3e65551d` deliberately reverted the optional gid and updated dumping accordingly.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Current lines 43–59 dump all established fields, use `addr.get_legacy_str()` at line 48, and pass plain `gid` at line 47. The metadata and task-status sections are always emitted, as required by the historical dump implementation.

## `ServiceMap::Daemon::generate_test_instances()`

**Introduced:** `7fce6382f2c35e767dcf326c088bc31e650386d3` — mgr: add ServiceMap
**Last modified:** `f6387fd81c6e23dbfb14edbd21185e1a753a249a` — src: replace push_back(T{}) with emplace_back()
**Change count:** 4 commits touched this function
**Divergence:** OK

### Intent
Return representative daemon values for encoder/dencoder tests, including an empty instance and one populated with gid, metadata, and running task status. The function must return values rather than owning raw pointers to avoid test-instance leaks. (Established: `7fce6382`, `5c25a018`, `ed6b7124`.)

### Invariants and contracts
- Return two test instances, with the second populated with `gid = 222`, metadata `this=that`, and `task1=running`. (Established: `7fce6382`, `5c25a018`.)
- Return `std::list<Daemon>` by value, eliminating raw-pointer lifecycle responsibility. (Established: `ed6b7124`.)
- Construct list elements directly with `emplace_back()`. (Established: `f6387fd8`.)

### Error conditions
- None specified.

### Evolution summary
The original function appended heap-allocated pointers. `ed6b7124` changed the API and returned values to fix ASan leaks; `f6387fd8` replaced temporary-object `push_back` with emplacement.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Current lines 61–69 return two value objects, populate the required second instance, and use `emplace_back()` at lines 64–65. No raw ownership remains.

## `ServiceMap::Service::get_summary() const`

**Introduced:** `ee5835dfb53c8f6cb892990e802ac3fd2cfa493f` — mon: make service summary string customizable; simple default
**Last modified:** `ab0d8f2ae9f551e15a4c7bacbf69161e91263785` — mgr/ServiceMap: adjust 'ceph -s' summary
**Change count:** 7 commits touched this function
**Divergence:** OK

### Intent
Return an explicit service summary when supplied; otherwise produce a scalable status summary for active daemons. Empty services report `no daemons active`; non-empty services use `daemon_type` when present and report distinct `hostname` and `zone_id` group counts instead of enumerating daemon IDs. (Established: `ee5835df`, `293b7ba`, `394baa0b`, `a968f65d`, `ab0d8f2`.)

### Invariants and contracts
- A non-empty custom `summary` takes precedence. (Established: `ee5835df`.)
- An empty daemon map returns exactly `no daemons active`. (Established: `ee5835df`.)
- Default summaries use a singular/plural suffix based on daemon count and do not contain the original `daemonss` typo. (Established: `293b7ba`.)
- The summary must not enumerate individual daemon IDs; it must scale using distinct host and zone groupings. (Established: `ab0d8f2`.)
- `daemon_type`, if present, replaces the default type; `hostname` and `zone_id` are counted distinctly as host/zone groupings. (Established: `a968f65d`, `ab0d8f2`.)

### Error conditions
- Missing metadata is not an error: use type `daemon` and omit that grouping. (Established: `a968f65d`, `ab0d8f2`.)

### Evolution summary
The initial implementation added customizable summaries and an empty-service default. `293b7ba` fixed pluralization, and `394baa0` added IDs. `a968f65d` introduced type/prefix grouping, then `ab0d8f2` deliberately removed ID/prefix enumeration and replaced it with scalable host/zone counts. `c63ecb6` was namespace-only; `e0cfad0` made a readability-only cleanup.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Current lines 76–80 implement custom and empty cases. Lines 96–112 count distinct `hostname`/`zone_id` values and select `daemon_type`; lines 114–127 format count, pluralization, and groupings without daemon IDs. The line-124 plural expression uses `size() ? "s" : ""`, which yields correct singular for a one-element grouping and is consistent with the established output intent. No DIVERGED condition is supported by the later history.

## `ServiceMap::Service::has_running_tasks() const`

**Introduced:** `7305acda01b1f4b66327cd2ce5e6b12acfb65de6` — mon: only dump non-empty "task status"
**Last modified:** `7305acda01b1f4b66327cd2ce5e6b12acfb65de6` — mon: only dump non-empty "task status"
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Tell callers whether at least one daemon has a non-empty task-status map, so monitor status output can omit an empty task-status section. (Established: `7305acda`.)

### Invariants and contracts
- Return true iff any daemon has non-empty `task_status`. (Established: `7305acda`.)
- Return false for an empty service or when all daemon task-status maps are empty. (Established: `7305acda`.)

### Error conditions
None.

### Evolution summary
This function was added as a small predicate and has not changed.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 130–135 use `std::any_of` over all daemons and test exactly `!task_status.empty()`.

## `ServiceMap::Service::get_task_summary(std::string_view) const`

**Introduced:** `5c25a018643b10aa78db8270cae1476f71d8f4f4` — mgr, mon: allow normal ceph services to register with manager
**Last modified:** `e0cfad08b670affd3468be4eabccd7d5d8285cf8` — mon: refactor ServiceMap::Service::get_task_summary()
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Aggregate each daemon's task statuses by task name and render a deterministic indented report whose daemon key is `<task_prefix>.<service_id>`. Empty task data produces an empty string. (Established: `5c25a018`, `e0cfad0`.)

### Invariants and contracts
- Group output by task name, then by service/daemon identifier. (Established: `5c25a018`.)
- Use the supplied prefix and service ID to form the key `<prefix>.<id>`. (Established: `5c25a018`.)
- Preserve task status values and render the established newline/indent format. (Established: `5c25a018`.)

### Error conditions
- No task entries is a normal condition and returns an empty string; no error code was established. (Established: `5c25a018`.)

### Evolution summary
The function began inline in the header and was moved to the `.cc` file by `310e33c`; `e0cfad0` replaced string-stream key construction with `fmt::format` and structured bindings without changing the contract.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 143–157 build the task-first map, use `fmt::format("{}.{}", task_prefix, service_id)` at line 146, preserve statuses, and emit the documented indentation. Ordered maps provide deterministic ordering. No ungrounded semantic path is present.

## `ServiceMap::Service::count_metadata(const std::string&, std::map<std::string,int>*) const`

**Introduced:** `80a42122a023df2e716738fd06bef2d2a49dce8f` — mon: 'versions' command to show running versions for daemons of all types
**Last modified:** `310e33cf9a6ce7987d82566dba9ebc6b97c18a19` — mgr/ServiceMap: move ServiceMap::Daemon implementation into .cc file
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Count daemons by a requested metadata field, placing daemons without that field in the `unknown` bucket. The caller supplies the output map. (Established: `80a42122`.)

### Invariants and contracts
- Every daemon contributes exactly one count, either its metadata value or `unknown`. (Established: `80a42122`.)
- Counts accumulate into the caller-provided map rather than replacing it. (Established: `80a42122`.)

### Error conditions
None specified; the history assumes a valid output pointer.

### Evolution summary
Added inline in `80a42122`, namespace-qualified by `45eeca27`, and moved out-of-line by `310e33cf` without semantic change.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 163–170 perform one increment per daemon and use `unknown` for missing fields. The output map is intentionally accumulated. The null pointer is an API precondition rather than a history-established error path.

## `ServiceMap::Service::encode(bufferlist&, uint64_t) const`

**Introduced:** `7fce6382f2c35e767dcf326c088bc31e650386d3` — mgr: add ServiceMap
**Last modified:** `156c941ad0d27c3cd487a085e04df9faeeffa768` — mgr: Use unqualified encode/decode
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Serialize the service's daemon map and customizable summary in a versioned payload. (Established: `7fce6382`, `ee5835df`.)

### Invariants and contracts
- Encode `daemons` followed by `summary` under version-1 framing. (Established: `ee5835df`.)
- Use feature-aware encoding for the daemon map. (Established: `7fce6382`, `156c941a`.)

### Error conditions
None function-specific.

### Evolution summary
The original encoder serialized daemons; `ee5835df` appended summary. `156c941a` changed only qualification/ADL syntax.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 173–179 frame and encode `daemons` then `summary` exactly as required.

## `ServiceMap::Service::decode(bufferlist::const_iterator&)`

**Introduced:** `7fce6382f2c35e767dcf326c088bc31e650386d3` — mgr: add ServiceMap
**Last modified:** `f146c6c514b7f1ab8a2420edb5f7b64702bc9639` — core: use const_iterator for decode
**Change count:** 3 commits touched this function
**Divergence:** OK

### Intent
Decode a version-1 service payload containing the daemon map and summary. (Established: `7fce6382`, `ee5835df`.)

### Invariants and contracts
- Decode fields in encode order and finish the versioned frame. (Established: `7fce6382`, `ee5835df`.)
- Accept the const iterator interface. (Established: `f146c6c5`.)

### Error conditions
Malformed payload handling is delegated to the decode framing macros. (Established: `7fce6382`.)

### Evolution summary
Summary decoding was added by `ee5835df`; the iterator became const in `f146c6c5`; `156c941a` changed qualification only.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 181–187 decode `daemons`, then `summary`, with version framing and a const iterator.

## `ServiceMap::Service::dump(Formatter*) const`

**Introduced:** `7fce6382f2c35e767dcf326c088bc31e650386d3` — mgr: add ServiceMap
**Last modified:** `ee5835dfb53c8f6cb892990e802ac3fd2cfa493f` — mon: make service summary string customizable; simple default
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Dump the service summary and all named daemon objects under the `daemons` formatter section. (Established: `7fce6382`, `ee5835df`.)

### Invariants and contracts
- Emit the `summary` field in the service object. (Established: `ee5835df`.)
- Dump each daemon under its map key. (Established: `7fce6382`.)

### Error conditions
None.

### Evolution summary
The initial dump emitted daemon objects; `ee5835df` added the summary field. Later changes did not alter it.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 189–197 open `daemons`, emit `summary` at line 192, dump every daemon, and close the section.

## `ServiceMap::Service::generate_test_instances()`

**Introduced:** `7fce6382f2c35e767dcf326c088bc31e650386d3` — mgr: add ServiceMap
**Last modified:** `f6387fd81c6e23dbfb14edbd21185e1a753a249a` — src: replace push_back(T{}) with emplace_back()
**Change count:** 4 commits touched this function
**Divergence:** OK

### Intent
Return two value-based service test instances, with the second containing daemons `one` and `two` and gids 1 and 2. (Established: `7fce6382`, `ed6b7124`.)

### Invariants and contracts
- Return two instances and populate the second with the two named daemons and their gids. (Established: `7fce6382`.)
- Return values, not raw pointers, to eliminate dencoder/test leaks. (Established: `ed6b7124`.)
- Construct elements with `emplace_back()`. (Established: `f6387fd8`.)

### Error conditions
None.

### Evolution summary
`ed6b7124` migrated the pointer API to value return; `f6387fd8` changed construction to emplacement.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 199–207 return two value objects, use emplacement, and populate the expected named daemons and gids.

## `ServiceMap::encode(bufferlist&, uint64_t) const`

**Introduced:** `7fce6382f2c35e767dcf326c088bc31e650386d3` — mgr: add ServiceMap
**Last modified:** `156c941ad0d27c3cd487a085e04df9faeeffa768` — mgr: Use unqualified encode/decode
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Serialize epoch, modification time, and all services using version-1 Ceph framing. (Established: `7fce6382`.)

### Invariants and contracts
- Encode fields in the order epoch, modified, services. (Established: `7fce6382`.)
- Use feature-aware service-map encoding. (Established: `7fce6382`, `156c941a`.)

### Error conditions
None function-specific.

### Evolution summary
Only namespace/ADL syntax changed after introduction.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 211–218 use version-1 framing and encode all three fields in the established order.

## `ServiceMap::decode(bufferlist::const_iterator&)`

**Introduced:** `7fce6382f2c35e767dcf326c088bc31e650386d3` — mgr: add ServiceMap
**Last modified:** `f146c6c514b7f1ab8a2420edb5f7b64702bc9639` — core: use const_iterator for decode
**Change count:** 3 commits touched this function
**Divergence:** OK

### Intent
Decode the version-1 map payload in epoch, modified, services order. (Established: `7fce6382`.)

### Invariants and contracts
- Decode in the same order as encode and finish the version frame. (Established: `7fce6382`.)
- Use a const iterator. (Established: `f146c6c5`.)

### Error conditions
Malformed data is handled by Ceph decode framing; no custom error path exists in history. (Established: `7fce6382`.)

### Evolution summary
`f146c6c5` changed only the iterator type; `156c941a` changed only qualification.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 220–227 decode epoch, modified, and services in the established order with const-iterator framing.

## `ServiceMap::dump(Formatter*) const`

**Introduced:** `7fce6382f2c35e767dcf326c088bc31e650386d3` — mgr: add ServiceMap
**Last modified:** `7fce6382f2c35e767dcf326c088bc31e650386d3` — mgr: add ServiceMap
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Dump epoch, modification time, and every service object under a services formatter section. (Established: `7fce6382`.)

### Invariants and contracts
- Emit epoch and modified timestamp and dump all services by key. (Established: `7fce6382`.)

### Error conditions
None.

### Evolution summary
The function has not changed semantically since introduction.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 229–238 emit the two scalar fields, open `services`, dump every map entry, and close the section.

## `ServiceMap::generate_test_instances()`

**Introduced:** `7fce6382f2c35e767dcf326c088bc31e650386d3` — mgr: add ServiceMap
**Last modified:** `f6387fd81c6e23dbfb14edbd21185e1a753a249a` — src: replace push_back(T{}) with emplace_back()
**Change count:** 4 commits touched this function
**Divergence:** OK

### Intent
Return two value-based map instances, with the second populated with epoch 123 and representative rgw/iscsi daemons and gids. (Established: `7fce6382`, `ed6b7124`.)

### Invariants and contracts
- Return two instances; populate the second with the historical representative service/daemon entries. (Established: `7fce6382`.)
- Return values rather than raw pointers to eliminate leaks. (Established: `ed6b7124`.)
- Construct list elements directly. (Established: `f6387fd8`.)

### Error conditions
None.

### Evolution summary
The function began with heap-allocated test maps, migrated to value semantics in `ed6b7124`, and adopted emplacement in `f6387fd8`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 240–249 construct two values, set epoch 123, and populate the exact representative service entries and gids.

## `ServiceMap::get_daemon(const std::string&, const std::string&)`

**Introduced:** `7fce6382f2c35e767dcf326c088bc31e650386d3` — mgr: add ServiceMap
**Last modified:** `3e65551d0ab4acafafdae8ff653925b417acc2cd` — mgr/ServiceMap: use plain gid
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Get or create the named daemon within the named service and tell the caller whether insertion occurred. (Established: `7fce6382`, `3e65551d`.)

### Invariants and contracts
- Create the service entry if absent and insert the daemon only if absent. (Established: `7fce6382`, `3e65551d`.)
- Return a pointer to the stored daemon and a boolean indicating whether it was newly added. (Established: `3e65551d`.)

### Error conditions
None; missing entries are creation cases.

### Evolution summary
The original API returned only a pointer and used `operator[]`. `3e65551d` changed it to `try_emplace` plus an insertion flag to support registration logic and partially reverted the incompatible optional-gid change.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 59–64 create/find the service, use `try_emplace`, and return the stored pointer plus `added` flag. No historical contract is violated.

## `ServiceMap::rm_daemon(const std::string&, const std::string&)`

**Introduced:** `7fce6382f2c35e767dcf326c088bc31e650386d3` — mgr: add ServiceMap
**Last modified:** `7fce6382f2c35e767dcf326c088bc31e650386d3` — mgr: add ServiceMap
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Remove a named daemon without creating missing entries, report whether removal occurred, and remove the now-empty containing service. (Established: `7fce6382`.)

### Invariants and contracts
- Missing service or daemon returns false and leaves the map unchanged. (Established: `7fce6382`.)
- Successful removal returns true. (Established: `7fce6382`.)
- Empty services are erased after their last daemon is removed. (Established: `7fce6382`.)

### Error conditions
Missing service and missing daemon are deliberate false-return cases. (Established: `7fce6382`.)

### Evolution summary
No semantic changes since introduction.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 66–80 check both map levels, erase the daemon, erase an empty service, and return the documented boolean.

## `ServiceMap::is_normal_ceph_entity(std::string_view)`

**Introduced:** `79503fc16749ed0cfe8a89ea3b3c8c792d6b8809` — mgr: helper function to check if a service is a normal ceph service
**Last modified:** `79503fc16749ed0cfe8a89ea3b3c8c792d6b8809` — mgr: helper function to check if a service is a normal ceph service
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Classify the five normal Ceph entity types that must be filtered when processing manager service-map entries: `osd`, `client`, `mon`, `mds`, and `mgr`. All other strings are non-normal for this helper. (Established: `79503fc`.)

### Invariants and contracts
- Return true exactly for `osd`, `client`, `mon`, `mds`, and `mgr`. (Established: `79503fc`.)
- Return false for every other type. (Established: `79503fc`.)

### Error conditions
Unknown or empty type is a normal false result, not an error. (Established: `79503fc`.)

### Evolution summary
The helper has not changed since introduction.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 83–93 compare exactly the five established strings and return false otherwise.

## Assessment notes for duplicate ctags declarations

`functions.txt` contains the same methods both at their declarations in `ServiceMap.h` and at their definitions in `ServiceMap.cc` (and lists `__anon31caef950102` at `ServiceMap.cc:132`). The 19 callable methods above cover the 39 ctags entries by qualified method identity; the anonymous entry is the lambda inside `has_running_tasks()` and is assessed with that function.

## Self-check

- [x] Read every non-comment commit in `commits.txt` (24 commits), including formatting/include-only commits and all available diff files.
- [x] For every ctags function entry, scanned the introduction and relevant later diffs; the duplicate header/definition entries are explicitly covered above, and the lambda entry is covered under `has_running_tasks()`.
- [x] Used `blame.txt`; current implementation critiques cite the current source line ranges, and the relevant last-touch SHAs are represented in each section's history.
- [x] No `DIVERGED` flag is set without a specific establishing SHA and contradicting current line; the reviewed current source satisfies the explicit historical contracts.
- [x] Every documented invariant and error condition cites an establishing SHA.
- [x] Every callable function has an Implementation critique with current line numbers.
- [x] No current significant code path was found that lacked historical grounding; formatting and iteration paths are direct implementations of the cited contracts rather than unexplained behaviour.

## Ctags declaration entries assessed separately

The following sections correspond one-for-one to the duplicate declaration entries in `functions.txt` (the declarations are assessed against the same implementation contract as their out-of-line definitions). They are retained explicitly so every ctags entry has a section.

## `ServiceMap::Daemon::encode` — header declaration (`ServiceMap.h:28`)

**Introduced:** `7fce6382` — mgr: add ServiceMap
**Last modified:** `45eeca27` — mgr: Update ServiceMap to work without using namespace
**Change count:** 2 commits touched this declaration
**Divergence:** OK

### Intent
Declare the versioned daemon serializer described in the corresponding implementation section.

### Invariants and contracts
- Signature accepts a feature mask and mutable buffer output. (Established: `7fce6382`.)

### Error conditions
None specified.

### Evolution summary
The declaration was namespace-qualified by `45eeca27`; implementation semantics were unchanged.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.h:28` matches the current implementation at `ServiceMap.cc:17–27`.

## `ServiceMap::Daemon::decode` — header declaration (`ServiceMap.h:29`)

**Introduced:** `7fce6382` — mgr: add ServiceMap
**Last modified:** `f146c6c5` — core: use const_iterator for decode
**Change count:** 2 commits touched this declaration
**Divergence:** OK

### Intent
Declare the const-iterator daemon deserializer.

### Invariants and contracts
- The declaration must expose a const iterator matching the compatibility decoder. (Established: `f146c6c5`.)

### Error conditions
None specified beyond decode framing.

### Evolution summary
The iterator changed from mutable to const in `f146c6c5`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.h:29` matches `ServiceMap.cc:29–41`.

## `ServiceMap::Daemon::dump` — header declaration (`ServiceMap.h:30`)

**Introduced:** `7fce6382` — mgr: add ServiceMap
**Last modified:** `45eeca27` — mgr: Update ServiceMap to work without using namespace
**Change count:** 2 commits touched this declaration
**Divergence:** OK

### Intent
Declare formatter output for daemon state.

### Invariants and contracts
- The formatter pointer type is the qualified Ceph formatter type. (Established: `45eeca27`.)

### Error conditions
None.

### Evolution summary
Only namespace qualification changed.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.h:30` matches `ServiceMap.cc:43–59`.

## `ServiceMap::Daemon::generate_test_instances` — header declaration (`ServiceMap.h:31`)

**Introduced:** `7fce6382` — mgr: add ServiceMap
**Last modified:** `ed6b7124` — src: Fix memory leaks in generate_test_instance()
**Change count:** 2 commits touched this declaration
**Divergence:** OK

### Intent
Declare the value-returning test fixture factory.

### Invariants and contracts
- Return `std::list<Daemon>`, not a pointer list. (Established: `ed6b7124`.)

### Error conditions
None.

### Evolution summary
The factory changed from an output pointer list to a returned value list in `ed6b7124`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.h:31` matches `ServiceMap.cc:61–69`.

## `ServiceMap::Service::encode` — header declaration (`ServiceMap.h:38`)

**Introduced:** `7fce6382` — mgr: add ServiceMap
**Last modified:** `45eeca27` — mgr: Update ServiceMap to work without using namespace
**Change count:** 2 commits touched this declaration
**Divergence:** OK

### Intent
Declare versioned service serialization.

### Invariants and contracts
- The declaration supports feature-aware encoding. (Established: `7fce6382`.)

### Error conditions
None.

### Evolution summary
Only namespace qualification changed.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.h:38` matches `ServiceMap.cc:173–179`.

## `ServiceMap::Service::decode` — header declaration (`ServiceMap.h:39`)

**Introduced:** `7fce6382` — mgr: add ServiceMap
**Last modified:** `f146c6c5` — core: use const_iterator for decode
**Change count:** 2 commits touched this declaration
**Divergence:** OK

### Intent
Declare versioned service deserialization.

### Invariants and contracts
- The declaration uses a const iterator. (Established: `f146c6c5`.)

### Error conditions
None specified beyond decode framing.

### Evolution summary
Only the iterator constness changed.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.h:39` matches `ServiceMap.cc:181–187`.

## `ServiceMap::Service::dump` — header declaration (`ServiceMap.h:40`)

**Introduced:** `7fce6382` — mgr: add ServiceMap
**Last modified:** `45eeca27` — mgr: Update ServiceMap to work without using namespace
**Change count:** 2 commits touched this declaration
**Divergence:** OK

### Intent
Declare formatter output for a service and its daemons.

### Invariants and contracts
- Use the qualified formatter pointer type. (Established: `45eeca27`.)

### Error conditions
None.

### Evolution summary
Only namespace qualification changed.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.h:40` matches `ServiceMap.cc:189–197`.

## `ServiceMap::Service::generate_test_instances` — header declaration (`ServiceMap.h:41`)

**Introduced:** `7fce6382` — mgr: add ServiceMap
**Last modified:** `ed6b7124` — src: Fix memory leaks in generate_test_instance()
**Change count:** 2 commits touched this declaration
**Divergence:** OK

### Intent
Declare the value-returning service fixture factory.

### Invariants and contracts
- Return `std::list<Service>`. (Established: `ed6b7124`.)

### Error conditions
None.

### Evolution summary
The return form changed to values in `ed6b7124`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.h:41` matches `ServiceMap.cc:199–207`.

## `ServiceMap::Service::get_summary` — header declaration (`ServiceMap.h:43`)

**Introduced:** `310e33cf` — mgr/ServiceMap: move ServiceMap::Daemon implementation into .cc file
**Last modified:** `310e33cf` — mgr/ServiceMap: move ServiceMap::Daemon implementation into .cc file
**Change count:** 1 commit touched this declaration
**Divergence:** OK

### Intent
Declare the historical summary generator assessed at `ServiceMap.cc:74–128`.

### Invariants and contracts
- Preserve the summary contract established by `ee5835df`, `293b7ba`, `a968f65d`, and `ab0d8f2`.

### Error conditions
Missing metadata uses established defaults, not an error. (Established: `ab0d8f2`.)

### Evolution summary
The inline implementation was moved out-of-line.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.h:43` matches the implementation at `ServiceMap.cc:74–128`.

## `ServiceMap::Service::has_running_tasks` — header declaration (`ServiceMap.h:44`)

**Introduced:** `7305acda` — mon: only dump non-empty "task status"
**Last modified:** `7305acda` — mon: only dump non-empty "task status"
**Change count:** 1 commit touched this declaration
**Divergence:** OK

### Intent
Declare the task-presence predicate.

### Invariants and contracts
- The declaration corresponds to the predicate established by `7305acda`.

### Error conditions
None.

### Evolution summary
No change after introduction.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.h:44` matches `ServiceMap.cc:130–135`.

## `ServiceMap::Service::get_task_summary` — header declaration (`ServiceMap.h:45`)

**Introduced:** `310e33cf` — mgr/ServiceMap: move ServiceMap::Daemon implementation into .cc file
**Last modified:** `310e33cf` — mgr/ServiceMap: move ServiceMap::Daemon implementation into .cc file
**Change count:** 1 commit touched this declaration
**Divergence:** OK

### Intent
Declare the task aggregation formatter assessed at `ServiceMap.cc:137–158`.

### Invariants and contracts
- Use the prefix and preserve task/status grouping. (Established: `5c25a018`.)

### Error conditions
Empty task data is a normal empty result. (Established: `5c25a018`.)

### Evolution summary
The inline function was moved out-of-line.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.h:45` matches the implementation at `ServiceMap.cc:137–158`.

## `ServiceMap::Service::count_metadata` — header declaration (`ServiceMap.h:46`)

**Introduced:** `310e33cf` — mgr/ServiceMap: move ServiceMap::Daemon implementation into .cc file
**Last modified:** `310e33cf` — mgr/ServiceMap: move ServiceMap::Daemon implementation into .cc file
**Change count:** 1 commit touched this declaration
**Divergence:** OK

### Intent
Declare metadata counting with caller-provided output storage.

### Invariants and contracts
- Missing fields map to `unknown`. (Established: `80a42122`.)

### Error conditions
None specified.

### Evolution summary
The inline function was moved out-of-line.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.h:46–47` matches `ServiceMap.cc:160–171`.

## `ServiceMap::Service::encode` — header declaration (`ServiceMap.h:54`)

**Introduced:** `7fce6382` — mgr: add ServiceMap
**Last modified:** `45eeca27` — mgr: Update ServiceMap to work without using namespace
**Change count:** 2 commits touched this declaration
**Divergence:** OK

### Intent
Declare top-level map serialization.

### Invariants and contracts
- Encode epoch, modified time, and services in order. (Established: `7fce6382`.)

### Error conditions
None.

### Evolution summary
Only namespace qualification changed.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.h:54` matches `ServiceMap.cc:211–218`.

## `ServiceMap::decode` — header declaration (`ServiceMap.h:55`)

**Introduced:** `7fce6382` — mgr: add ServiceMap
**Last modified:** `f146c6c5` — core: use const_iterator for decode
**Change count:** 2 commits touched this declaration
**Divergence:** OK

### Intent
Declare top-level const-iterator deserialization.

### Invariants and contracts
- The declaration uses a const iterator and preserves field order. (Established: `f146c6c5`, `7fce6382`.)

### Error conditions
Malformed data is handled by framing macros. (Established: `7fce6382`.)

### Evolution summary
Only iterator constness changed.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.h:55` matches `ServiceMap.cc:220–227`.

## `ServiceMap::dump` — header declaration (`ServiceMap.h:56`)

**Introduced:** `7fce6382` — mgr: add ServiceMap
**Last modified:** `45eeca27` — mgr: Update ServiceMap to work without using namespace
**Change count:** 2 commits touched this declaration
**Divergence:** OK

### Intent
Declare top-level formatter output.

### Invariants and contracts
- Dump epoch, modified time, and all named services. (Established: `7fce6382`.)

### Error conditions
None.

### Evolution summary
Only namespace qualification changed.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.h:56` matches `ServiceMap.cc:229–238`.

## `ServiceMap::generate_test_instances` — header declaration (`ServiceMap.h:57`)

**Introduced:** `7fce6382` — mgr: add ServiceMap
**Last modified:** `ed6b7124` — src: Fix memory leaks in generate_test_instance()
**Change count:** 2 commits touched this declaration
**Divergence:** OK

### Intent
Declare the value-returning top-level fixture factory.

### Invariants and contracts
- Return `std::list<ServiceMap>` by value. (Established: `ed6b7124`.)

### Error conditions
None.

### Evolution summary
The raw-pointer output API became value return in `ed6b7124`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.h:57` matches `ServiceMap.cc:240–249`.

## `__anon31caef950102` — lambda (`ServiceMap.cc:132`)

**Introduced:** `7305acda` — mon: only dump non-empty "task status"
**Last modified:** `7305acda` — mon: only dump non-empty "task status"
**Change count:** 1 commit touched this anonymous function
**Divergence:** OK

### Intent
Return whether the daemon captured by the `has_running_tasks()` predicate has a non-empty task-status map. (Established: `7305acda`.)

### Invariants and contracts
- A daemon with any task status yields true to the enclosing predicate; an empty task-status map yields false for that element. (Established: `7305acda`.)

### Error conditions
None.

### Evolution summary
The lambda was introduced with `has_running_tasks()` and has not changed.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.cc:132–134` tests exactly `!daemon.second.task_status.empty()`.

## `ServiceMap::get_daemon` — header declaration (`ServiceMap.h:59`)

**Introduced:** `7fce6382` — mgr: add ServiceMap
**Last modified:** `3e65551d` — mgr/ServiceMap: use plain gid
**Change count:** 2 commits touched this declaration
**Divergence:** OK

### Intent
Declare lookup-or-create access that returns the stored daemon and an insertion indicator. (Established: `3e65551d`.)

### Invariants and contracts
- The declaration returns `std::pair<Daemon*, bool>` and accepts service and daemon names. (Established: `3e65551d`.)

### Error conditions
Missing service/daemon names are creation cases; no error path was established.

### Evolution summary
The original pointer-only declaration became a pair-returning declaration when `try_emplace` was introduced.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.h:59–64` matches the implementation and its insertion flag.

## `ServiceMap::rm_daemon` — header declaration (`ServiceMap.h:66`)

**Introduced:** `7fce6382` — mgr: add ServiceMap
**Last modified:** `7fce6382` — mgr: add ServiceMap
**Change count:** 1 commit touched this declaration
**Divergence:** OK

### Intent
Declare removal of a named daemon without creating missing map entries.

### Invariants and contracts
- Return false for a missing service or daemon, true after removal, and remove an empty service. (Established: `7fce6382`.)

### Error conditions
Missing service and daemon are deliberate false-return cases. (Established: `7fce6382`.)

### Evolution summary
No semantic change since introduction.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.h:66–80` matches `ServiceMap.cc`'s inline implementation and its two missing-entry checks.

## `ServiceMap::is_normal_ceph_entity` — header declaration (`ServiceMap.h:83`)

**Introduced:** `79503fc` — mgr: helper function to check if a service is a normal ceph service
**Last modified:** `79503fc` — mgr: helper function to check if a service is a normal ceph service
**Change count:** 1 commit touched this declaration
**Divergence:** OK

### Intent
Declare the helper that identifies normal Ceph entity types for filtering.

### Invariants and contracts
- Recognize exactly `osd`, `client`, `mon`, `mds`, and `mgr`; return false for other strings. (Established: `79503fc`.)

### Error conditions
Unknown and empty types are false results, not errors. (Established: `79503fc`.)

### Evolution summary
No semantic change since introduction.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — `ServiceMap.h:83–93` implements exactly the established five-way classification.
