# PyFormatter History Assessment

## Assessment scope

- Corpus: `/home/szuraski/BobOutput/Object History/v4/PyFormatter/`
- Current implementation assessed: [`src/mgr/PyFormatter.cc`](../../../ceph/src/mgr/PyFormatter.cc) and [`src/mgr/PyFormatter.h`](../../../ceph/src/mgr/PyFormatter.h)
- Commit count: **26 non-merge commits**.
- Corpus HEAD: `8681fa6ebac230f86eb445bf57095c63e7f1abcc`.
- Commit date range: **2016-06-30 through 2026-01-21**.
- Function inventory: **48 ctags entries** (including overloads and declaration/definition entries).
- All 26 commit subjects and all 26 scoped diffs were read. Formatting-only commits are included in the history but establish no behavioral contract.

## Historical contracts

- `ac30e6cee2b2`: construct a Python dict or list root, maintain a cursor/section stack, insert values into the current list/dict, defer stream materialization until completion, and return a new reference from `get()`.
- `9ea37c223f92`: construction must occur while holding the Python GIL because it immediately creates Python objects.
- `61fca96c2910`: unsupported namespace sections, formatting, serialization, raw-data, and invalid cursor states are fatal rather than silently accepted.
- `86c851e138ae`: `dump_format_va` formats into a bounded 1024-byte buffer and stores the formatted Python string.
- `0c8ec93af7d7437d1ffd646be407c4bf64f505b4`: string interfaces use `std::string_view`.
- `ab23c506964753990f9fe23e314b9f3e2547a773` and `5009d9ecc692`: internal assertions use Ceph assertion facilities and the renamed `ceph_assert` header.
- `938189e8f280`: copying `PyFormatter` is forbidden because it owns Python references and mutable cursor state.
- `ac8b016b7237`: unsigned values must use an unsigned Python conversion, preserving the full `uint64_t` domain.
- `48c4bc445fc`: Python 3 Unicode objects are used for strings, formatted output, stream output, and dictionary keys.
- `6712393fbc534c6c7040bfc9ee2d1268f3adc9dd`: names are UTF-8 decoded with their explicit `string_view` length; names and values do not require NUL termination.
- `992829d38cb89732f6994642c1bdaa2448e610b7`: line-break requests are accepted as a no-op.
- `5f57c526b22a`: null values map to Python `None`.
- `15dfa71cf7c8`: the separate JSON formatter returns Python bytes after flushing/closing JSON sections; this contract was removed by `403340bcf8c2122afff708519f176baa6b646fc1` when the implementation was replaced by `PyFormatterRO`.
- `403340bcf8`: readonly retrieval flushes pending streams, converts nested mutable containers once, returns a new reference, and resets conversion state when the formatter resets. The conversion helpers recursively freeze lists, dict values, sets, and tuple contents, with fallback to the original object on conversion failure.
- `7c68a00cce5b`: invalid Python object creation must not reach `dump_pyobject`; `dump_pyobject` has a defensive null-object guard. The commit subject and message describe Latin-1 fallback, but the scoped patch actually clears the error and drops the string; no Latin-1 fallback was added.

## Function assessments

### `dump_bool` — [`src/mgr/PyFormatter.cc:82`](../../../ceph/src/mgr/PyFormatter.cc:82); declaration [`src/mgr/PyFormatter.h:90`](../../../ceph/src/mgr/PyFormatter.h:90)
**Status: SATISFIES.**

**Intent and history.** Store a Python boolean under the supplied name or append it to the current list. The original implementation in `ac30e6cee2b2` explicitly incref'd the borrowed singleton before passing it to the stealing `dump_pyobject` helper; `6712393fbc53` changed only the name type.

**Implementation critique.** Lines 84–90 select `Py_True`/`Py_False`, increment the singleton, and delegate insertion. This satisfies the ownership contract and current list/dict routing. The current implementation has no unexplained path.

### `dump_float` — [`src/mgr/PyFormatter.cc:67`](../../../ceph/src/mgr/PyFormatter.cc:67); declaration [`src/mgr/PyFormatter.h:94`](../../../ceph/src/mgr/PyFormatter.h:94)
**Status: UNGROUNDED.**

**Intent and history.** Create a Python float and insert it; the behavior originates in `ac30e6cee2b2`, with the name becoming `string_view` in `6712393fbc53`.

**Implementation critique.** Lines 69–70 pass the result of `PyFloat_FromDouble` directly to `dump_pyobject`. There is no mapped commit establishing how allocation failure should be handled for this constructor, and no local check explains that path. The null result is nevertheless caught by the general guard at lines 120–122, so this is not marked DIVERGED.

### `dump_format_va` — [`src/mgr/PyFormatter.cc:107`](../../../ceph/src/mgr/PyFormatter.cc:107); declaration [`src/mgr/PyFormatter.h:97`](../../../ceph/src/mgr/PyFormatter.h:97)
**Status: DIVERGED.**

**Intent and history.** `86c851e138ae` established bounded formatting into `LARGE_SIZE` (1024) and insertion of the resulting Python string. `48c4bc445fc` established Python 3 Unicode output. `7c68a00cce5b` established that a null Python object must not be passed to `dump_pyobject`.

**Implementation critique.** Lines 109–112 use the required 1024-byte buffer and Unicode conversion, but pass the conversion result directly to `dump_pyobject`. If `PyUnicode_FromString` fails, line 112 contradicts the null-object invariant established by `7c68a00cce5b` and reaches the abort guard at lines 120–122. The function also does not inspect `vsnprintf` truncation; the bounded-buffer behavior is historical, but truncation policy is not established in the corpus.

### `dump_int` — [`src/mgr/PyFormatter.cc:60`](../../../ceph/src/mgr/PyFormatter.cc:60); declaration [`src/mgr/PyFormatter.h:93`](../../../ceph/src/mgr/PyFormatter.h:93)
**Status: SATISFIES.**

**Intent and history.** Store a signed 64-bit integer using Python's signed long-long constructor. This originates in `ac30e6cee2b2`; `ab23c5069647` replaced the allocation assertion with `ceph_assert`, and `6712393fbc53` changed the name type.

**Implementation critique.** Lines 62–64 create the signed value, assert successful allocation, and pass ownership to `dump_pyobject`. The implementation enforces the established allocation and ownership contracts.

### `dump_null` — [`src/mgr/PyFormatter.cc:48`](../../../ceph/src/mgr/PyFormatter.cc:48); declaration [`src/mgr/PyFormatter.h:91`](../../../ceph/src/mgr/PyFormatter.h:91)
**Status: SATISFIES.**

**Intent and history.** `5f57c526b22a` established that a null formatter value is Python `None`.

**Implementation critique.** Lines 50–51 pass `Py_None` to the stealing helper. The helper decref balances the explicit incref required for a borrowed singleton? **UNGROUNDED:** unlike `dump_bool`, this function does not explicitly `Py_INCREF(Py_None)`, and the corpus does not explain the ownership convention for this newly added path. The implementation therefore relies on an unexplained reference-count assumption even though the history documents that `dump_pyobject` steals its argument.

### `dump_pyobject` — [`src/mgr/PyFormatter.cc:118`](../../../ceph/src/mgr/PyFormatter.cc:118); declaration [`src/mgr/PyFormatter.h:128`](../../../ceph/src/mgr/PyFormatter.h:128)
**Status: SATISFIES.**

**Intent and history.** The helper steals `p`, appends it to lists, inserts it under a UTF-8-decoded key in dicts, and aborts for any other cursor type. These contracts originate in `ac30e6cee2b2`; UTF-8 name decoding and explicit lengths come from `6712393fbc53`; the invalid-object guard comes from `7c68a00cce5b`.

**Implementation critique.** Lines 120–122 enforce the non-null precondition. Lines 123–130 implement list/dict ownership transfer and UTF-8 key construction. Lines 131–133 retain the fatal invalid-cursor path established by `61fca96c2910`. **UNGROUNDED:** `PyUnicode_DecodeUTF8` and `PyDict_SetItem` failures are not checked, and the corpus does not explain their error policy. The null guard itself satisfies its establishing commit.

### `dump_stream` — [`src/mgr/PyFormatter.cc:93`](../../../ceph/src/mgr/PyFormatter.cc:93); declaration [`src/mgr/PyFormatter.h:96`](../../../ceph/src/mgr/PyFormatter.h:96)
**Status: SATISFIES.**

**Intent and history.** Return an ostream, remember its destination cursor and name, and materialize its contents during pending-stream completion. This is established by `ac30e6cee2b2`; `6712393fbc53` changed the name type.

**Implementation critique.** Lines 98–104 record the current cursor and name in a shared pending-stream object, retain it in the list, and return its stream. This directly implements the historical deferred-write contract.

### `dump_string` — [`src/mgr/PyFormatter.cc:72`](../../../ceph/src/mgr/PyFormatter.cc:72); declaration [`src/mgr/PyFormatter.h:95`](../../../ceph/src/mgr/PyFormatter.h:95)
**Status: DIVERGED.**

**Intent and history.** `ac30e6cee2b2` introduced string insertion; `0c8ec93af7d` adopted length-aware `string_view`; `48c4bc445fc` switched to Unicode; `7c68a00cce5b` addressed non-printable input and established that failed object creation must not reach `dump_pyobject`.

**Implementation critique.** Lines 74–79 correctly use `PyUnicode_FromStringAndSize`, clear the Python error, and return on failure. That prevents the segfault, but it silently drops the value. The commit message explicitly says the fix falls back to Latin-1, while the actual diff does not implement that fallback; against that stated contract, line 77 is DIVERGED, with the contradicting SHA `7c68a00cce5b`. The explicit-length conversion satisfies the `string_view` contract.

### `dump_unsigned` — [`src/mgr/PyFormatter.cc:53`](../../../ceph/src/mgr/PyFormatter.cc:53); declaration [`src/mgr/PyFormatter.h:92`](../../../ceph/src/mgr/PyFormatter.h:92)
**Status: SATISFIES.**

**Intent and history.** Preserve unsigned values using an unsigned Python conversion. `ac8b016b7237` corrected the original signed conversion; `ab23c5069647` established `ceph_assert`; `6712393fbc53` changed the name type.

**Implementation critique.** Lines 55–57 use `PyLong_FromUnsignedLong`, assert success, and transfer ownership. This enforces the corrected unsigned-domain contract.

### `finish_pending_streams` — [`src/mgr/PyFormatter.cc:136`](../../../ceph/src/mgr/PyFormatter.cc:136); declaration [`src/mgr/PyFormatter.h:126`](../../../ceph/src/mgr/PyFormatter.h:126)
**Status: UNGROUNDED.**

**Intent and history.** `ac30e6cee2b2` established that every deferred stream is inserted into the cursor captured at stream creation, with cursor restoration and list cleanup. `48c4bc445fc` established Unicode stream values; `403340bcf8` retained flush-before-read semantics for the formatter API.

**Implementation critique.** Lines 138–147 temporarily switch to each saved cursor, insert a Unicode object, restore the cursor, and clear the pending list. The main lifecycle contract is satisfied. The unchecked Unicode allocation and unchecked insertion result are unexplained error paths, so they are UNGROUNDED rather than DIVERGED.

### `open_array_section` — [`src/mgr/PyFormatter.cc:32`](../../../ceph/src/mgr/PyFormatter.cc:32); declaration [`src/mgr/PyFormatter.h:81`](../../../ceph/src/mgr/PyFormatter.h:81)
**Status: SATISFIES.**

**Intent and history.** Create a Python list, insert it into the current container, push the prior cursor, and make the list current. This originates in `ac30e6cee2b2`; `6712393fbc53` changed the name to `string_view`.

**Implementation critique.** Lines 34–37 implement the exact create/insert/push/switch sequence. The operation is grounded and satisfies the section-stack invariant.

### `open_object_section` — [`src/mgr/PyFormatter.cc:40`](../../../ceph/src/mgr/PyFormatter.cc:40); declaration [`src/mgr/PyFormatter.h:82`](../../../ceph/src/mgr/PyFormatter.h:82)
**Status: SATISFIES.**

**Intent and history.** Create and insert a Python dict, then push and switch the cursor. This originates in `ac30e6cee2b2`; `5f57c526b22a` separately added null support; `6712393fbc53` changed the name type.

**Implementation critique.** Lines 42–45 implement the established section-stack transition. Allocation and insertion failures are delegated to the helper; no separate error policy is established for this function.

### `PyFormatter` — [`src/mgr/PyFormatter.h:37`](../../../ceph/src/mgr/PyFormatter.h:37) (copy constructor)
**Status: SATISFIES.**

**Intent and history.** `938189e8f280` forbids copying the formatter because copying its Python ownership and cursor state is unsafe.

**Implementation critique.** Line 37 deletes the copy constructor, directly enforcing the contract.

### `PyFormatter` — [`src/mgr/PyFormatter.h:39`](../../../ceph/src/mgr/PyFormatter.h:39) (constructor)
**Status: SATISFIES.**

**Intent and history.** `ac30e6cee2b2` establishes a dict root by default and list root when `array` is true. `9ea37c223f92` establishes the GIL precondition. `403340bcf8` keeps the constructor available to `PyFormatterRO`.

**Implementation critique.** Lines 39–49 select and own the correct root type. Lines 41–42 document the GIL precondition, but do not enforce it; the history treats it as a caller contract. No divergence is present.

### `close_section` — [`src/mgr/PyFormatter.h:83`](../../../ceph/src/mgr/PyFormatter.h:83)
**Status: SATISFIES.**

**Intent and history.** Close only a nested section, require a non-root cursor and non-empty stack, then restore/pop the parent. `ac30e6cee2b2` established the behavior; `ab23c5069647` established Ceph assertions.

**Implementation critique.** Lines 85–88 enforce both preconditions and restore the saved cursor. This satisfies the section-stack invariant.

### `convert_dict_to_proxy` — [`src/mgr/PyFormatter.h:213`](../../../ceph/src/mgr/PyFormatter.h:213)
**Status: UNGROUNDED.**

**Intent and history.** `403340bcf8` established recursive conversion of dict values into a new immutable/read-only representation, with fallback to the original dict if a child conversion or insertion fails.

**Implementation critique.** Lines 214–233 create a new dict, recursively convert values, handle child failure, check `PyDict_SetItem`, and return the original dict with a new reference on failure. The implementation matches the documented fallback. **UNGROUNDED:** failure of `PyDict_New` itself is not checked before use at line 218; the corpus does not specify this allocation failure path.

### `convert_list_to_tuple` — [`src/mgr/PyFormatter.h:196`](../../../ceph/src/mgr/PyFormatter.h:196)
**Status: UNGROUNDED.**

**Intent and history.** `403340bcf8` established recursive list-to-tuple conversion and fallback to the original list if a child cannot be converted.

**Implementation critique.** Lines 197–211 implement recursive conversion and fallback. **UNGROUNDED:** `PyTuple_New` failure is not checked before the loop, and the corpus gives no policy for that allocation failure.

### `convert_set_to_frozenset` — [`src/mgr/PyFormatter.h:236`](../../../ceph/src/mgr/PyFormatter.h:236)
**Status: SATISFIES.**

**Intent and history.** `403340bcf8` established conversion of sets to frozensets with fallback to the original set when conversion fails.

**Implementation critique.** Lines 237–245 return the frozenset on success or incref and return the original set on failure. This exactly implements the recorded fallback contract.

### `convert_to_readonly` — [`src/mgr/PyFormatter.h:166`](../../../ceph/src/mgr/PyFormatter.h:166)
**Status: SATISFIES.**

**Intent and history.** `403340bcf8` established one-time conversion of the root, replacement/decref when a new root is produced, cursor reset to the replacement, and a converted flag.

**Implementation critique.** Lines 167–175 implement all four transitions. The function is called only through the readonly getter's flag check, and reset clears that flag.

### `convert_tuple_contents` — [`src/mgr/PyFormatter.h:247`](../../../ceph/src/mgr/PyFormatter.h:247)
**Status: UNGROUNDED.**

**Intent and history.** `403340bcf8` established recursively replacing tuple contents with immutable equivalents, falling back to the original tuple if allocation or child conversion fails.

**Implementation critique.** Lines 249–267 handle tuple allocation failure, child failure, and recursive replacement. This satisfies the recorded fallback. The use of `PyTuple_SET_ITEM` is consistent with ownership of each newly returned reference. No additional unexplained path is identified beyond the generic recursive conversion behavior.

### `dump_bool` — [`src/mgr/PyFormatter.h:90`](../../../ceph/src/mgr/PyFormatter.h:90) (declaration)
**Status: SATISFIES.**

**Implementation critique.** The declaration matches the `string_view` interface established by `6712393fbc53` and the override contract added by `ecbcd591b785`. The implementation is assessed above at [`src/mgr/PyFormatter.cc:82`](../../../ceph/src/mgr/PyFormatter.cc:82).

### `dump_float` — [`src/mgr/PyFormatter.h:94`](../../../ceph/src/mgr/PyFormatter.h:94) (declaration)
**Status: SATISFIES.**

**Implementation critique.** The declaration matches the historical override and `string_view` name contract. See [`src/mgr/PyFormatter.cc:67`](../../../ceph/src/mgr/PyFormatter.cc:67) for the implementation critique.

### `dump_format_va` — [`src/mgr/PyFormatter.h:97`](../../../ceph/src/mgr/PyFormatter.h:97) (declaration)
**Status: SATISFIES.**

**Implementation critique.** The declaration preserves the formatter interface and `string_view` name introduced by `6712393fbc53`. The implementation divergence is at [`src/mgr/PyFormatter.cc:107`](../../../ceph/src/mgr/PyFormatter.cc:107), not in this declaration.

### `dump_int` — [`src/mgr/PyFormatter.h:93`](../../../ceph/src/mgr/PyFormatter.h:93) (declaration)
**Status: SATISFIES.**

**Implementation critique.** The declaration matches the signed integer override and name type contract. See [`src/mgr/PyFormatter.cc:60`](../../../ceph/src/mgr/PyFormatter.cc:60).

### `dump_null` — [`src/mgr/PyFormatter.h:91`](../../../ceph/src/mgr/PyFormatter.h:91) (declaration)
**Status: SATISFIES.**

**Implementation critique.** The declaration is the override added by `5f57c526b22a` and matches the implementation's `None` mapping. The ownership concern is assessed at [`src/mgr/PyFormatter.cc:48`](../../../ceph/src/mgr/PyFormatter.cc:48).

### `dump_pyobject` — [`src/mgr/PyFormatter.h:128`](../../../ceph/src/mgr/PyFormatter.h:128) (declaration)
**Status: SATISFIES.**

**Implementation critique.** `7c68a00cce5b` intentionally made this helper accessible to the readonly subclass and retained its null-object guard. The declaration matches that design.

### `dump_stream` — [`src/mgr/PyFormatter.h:96`](../../../ceph/src/mgr/PyFormatter.h:96) (declaration)
**Status: SATISFIES.**

**Implementation critique.** The declaration matches the deferred-stream override and `string_view` contract. See [`src/mgr/PyFormatter.cc:93`](../../../ceph/src/mgr/PyFormatter.cc:93).

### `dump_string` — [`src/mgr/PyFormatter.h:95`](../../../ceph/src/mgr/PyFormatter.h:95) (declaration)
**Status: SATISFIES.**

**Implementation critique.** The declaration correctly carries the explicit-length `string_view` interface established by `0c8ec93af7d` and `6712393fbc53`. The DIVERGED behavior is in the implementation at [`src/mgr/PyFormatter.cc:72`](../../../ceph/src/mgr/PyFormatter.cc:72).

### `dump_unsigned` — [`src/mgr/PyFormatter.h:92`](../../../ceph/src/mgr/PyFormatter.h:92) (declaration)
**Status: SATISFIES.**

**Implementation critique.** The declaration matches the corrected unsigned implementation and override contract. See [`src/mgr/PyFormatter.cc:53`](../../../ceph/src/mgr/PyFormatter.cc:53).

### `enable_line_break` — [`src/mgr/PyFormatter.h:79`](../../../ceph/src/mgr/PyFormatter.h:79)
**Status: SATISFIES.**

**Intent and history.** `992829d38cb8` added this override so formatter callers can request a line break without changing Python-object output.

**Implementation critique.** Line 79 is an explicit no-op, which matches the established behavior. No output-side line-break invariant was established for this object formatter.

### `finish_pending_streams` — [`src/mgr/PyFormatter.h:126`](../../../ceph/src/mgr/PyFormatter.h:126) (declaration)
**Status: SATISFIES.**

**Implementation critique.** The declaration exposes the lifecycle operation used by `get()` and by the readonly getter. Its implementation at [`src/mgr/PyFormatter.cc:136`](../../../ceph/src/mgr/PyFormatter.cc:136) is assessed above.

### `flush` — [`src/mgr/PyFormatter.h:99`](../../../ceph/src/mgr/PyFormatter.h:99)
**Status: SATISFIES.**

**Intent and history.** `61fca96c2910` established that this class is not a serializer and flushing it is unsupported/fatal; `34975103eae6` only corrected the explanatory comment.

**Implementation critique.** Lines 101–103 retain the explanatory contract and call `ceph_abort`. This is intentional, not an incomplete implementation.

### `get` — [`src/mgr/PyFormatter.h:118`](../../../ceph/src/mgr/PyFormatter.h:118)
**Status: SATISFIES.**

**Intent and history.** `ac30e6cee2b2` established finishing pending streams and returning a new reference to the root. `403340bcf8` made the method virtual so readonly retrieval could override it.

**Implementation critique.** Lines 120–123 flush deferred values, incref the root, and return it. This satisfies the ownership and visibility contract.

### `get` — [`src/mgr/PyFormatter.h:149`](../../../ceph/src/mgr/PyFormatter.h:149) (readonly override)
**Status: SATISFIES.**

**Intent and history.** `403340bcf8` established flush, one-time recursive freezing, a new reference, and reuse until reset.

**Implementation critique.** Lines 150–155 implement that sequence. The override does not mutate the root again after the conversion flag is set, and line 158–161 reset re-enables conversion for the next result.

### `get_len` — [`src/mgr/PyFormatter.h:105`](../../../ceph/src/mgr/PyFormatter.h:105)
**Status: SATISFIES.**

**Intent and history.** `61fca96c2910` established that serialized length is meaningless and the operation is fatal.

**Implementation critique.** Lines 107–109 abort and leave the historical unreachable `return 0`. This is the documented unsupported-operation behavior, not a missing implementation.

### `make_immutable` — [`src/mgr/PyFormatter.h:178`](../../../ceph/src/mgr/PyFormatter.h:178)
**Status: SATISFIES.**

**Intent and history.** `403340bcf8` established dispatch to list, dict, set, and tuple recursive converters, with incref for already immutable objects.

**Implementation critique.** Lines 179–193 cover all four mutable/container cases and the immutable fallback. This satisfies the dispatch invariant.

### `open_array_section` — [`src/mgr/PyFormatter.h:81`](../../../ceph/src/mgr/PyFormatter.h:81) (declaration)
**Status: SATISFIES.**

**Implementation critique.** The declaration matches the `string_view` override established by `6712393fbc53`; behavior is implemented at [`src/mgr/PyFormatter.cc:32`](../../../ceph/src/mgr/PyFormatter.cc:32).

### `open_array_section_in_ns` — [`src/mgr/PyFormatter.h:60`](../../../ceph/src/mgr/PyFormatter.h:60)
**Status: SATISFIES.**

**Intent and history.** `61fca96c2910` established unsupported namespace sections as fatal; `6712393fbc53` changed the name type.

**Implementation critique.** Lines 60–61 immediately abort. This explicitly enforces the unsupported-operation contract.

### `open_object_section` — [`src/mgr/PyFormatter.h:82`](../../../ceph/src/mgr/PyFormatter.h:82) (declaration)
**Status: SATISFIES.**

**Implementation critique.** The declaration matches the `string_view` override established by `6712393fbc53`; behavior is implemented at [`src/mgr/PyFormatter.cc:40`](../../../ceph/src/mgr/PyFormatter.cc:40).

### `open_object_section_in_ns` — [`src/mgr/PyFormatter.h:62`](../../../ceph/src/mgr/PyFormatter.h:62)
**Status: SATISFIES.**

**Intent and history.** `61fca96c2910` established namespace object sections as unsupported and fatal.

**Implementation critique.** Lines 62–63 abort immediately, satisfying the contract.

### `operator =` — [`src/mgr/PyFormatter.h:38`](../../../ceph/src/mgr/PyFormatter.h:38)
**Status: SATISFIES.**

**Intent and history.** `938189e8f280` forbids assignment for the same ownership and mutable-state reasons as copying.

**Implementation critique.** Line 38 deletes assignment, directly enforcing the historical safety rule.

### `output_footer` — [`src/mgr/PyFormatter.h:78`](../../../ceph/src/mgr/PyFormatter.h:78)
**Status: SATISFIES.**

**Intent and history.** `ecbcd591b785` records this formatter override as a no-op; the class returns Python objects rather than serialized footer text.

**Implementation critique.** Line 78 is an explicit no-op. No unexplained output path exists.

### `output_header` — [`src/mgr/PyFormatter.h:77`](../../../ceph/src/mgr/PyFormatter.h:77)
**Status: SATISFIES.**

**Intent and history.** `ecbcd591b785` records this formatter override as a no-op.

**Implementation critique.** Line 77 is an explicit no-op consistent with object-oriented output rather than serialization.

### `reset` — [`src/mgr/PyFormatter.h:65`](../../../ceph/src/mgr/PyFormatter.h:65)
**Status: SATISFIES.**

**Intent and history.** `ac30e6cee2b2` established replacing the root with an empty object of the same container kind; `ecbcd591b785` made it an override.

**Implementation critique.** Lines 67–73 detect the original root kind, decref the old root, and create a fresh matching root/cursor. The stack is not cleared; the corpus does not establish a reset-with-open-sections contract, so that path is UNGROUNDED rather than DIVERGED.

### `reset` — [`src/mgr/PyFormatter.h:158`](../../../ceph/src/mgr/PyFormatter.h:158) (readonly override)
**Status: SATISFIES.**

**Intent and history.** `403340bcf8` requires readonly conversion state to be invalidated after reset.

**Implementation critique.** Lines 159–160 delegate root recreation and clear the conversion flag, satisfying the readonly reuse invariant.

### `set_status` — [`src/mgr/PyFormatter.h:76`](../../../ceph/src/mgr/PyFormatter.h:76)
**Status: SATISFIES.**

**Intent and history.** `ecbcd591b785` records the status callback as an intentionally empty formatter override.

**Implementation critique.** Line 76 is an explicit no-op; no status-output contract is established for PyFormatter.

### `write_raw_data` — [`src/mgr/PyFormatter.h:112`](../../../ceph/src/mgr/PyFormatter.h:112)
**Status: SATISFIES.**

**Intent and history.** `61fca96c2910` established raw serialized writes as unsupported/fatal; `34975103eae6` only corrected the comment.

**Implementation critique.** Lines 114–116 abort, enforcing the unsupported serializer operation.

### `~PyFormatter` — [`src/mgr/PyFormatter.h:52`](../../../ceph/src/mgr/PyFormatter.h:52)
**Status: SATISFIES.**

**Intent and history.** `ac30e6cee2b2` established clearing the cursor and decref'ing the owned root; `ecbcd591b785` added the virtual destructor override.

**Implementation critique.** Lines 54–56 clear the cursor, release the root, and null the root field. The GIL precondition is documented by `9ea37c223f92` for all Python-object lifetime operations and is caller-enforced.

## Self-check

- Every commit listed in `commits.txt` was read, including formatting-only commits and commits mapped to no function.
- The complete 48-entry `functions.txt` inventory has a section above, including duplicate names at distinct declaration/definition lines.
- Every behavior claim is tied to the establishing SHA in the historical-contract or function section text.
- Every DIVERGED finding names the specific establishing SHA and contradicting current line: `dump_format_va` cites `7c68a00cce5b` / line 112; `dump_string` cites `7c68a00cce5b` / line 77.
- Ungrounded paths are explicitly marked where the corpus does not establish allocation/error behavior, including unchecked Python API failures and reset-with-open-sections behavior.
- Current implementation line numbers were checked against the current [`PyFormatter.cc`](../../../ceph/src/mgr/PyFormatter.cc) and [`PyFormatter.h`](../../../ceph/src/mgr/PyFormatter.h).
