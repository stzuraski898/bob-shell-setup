# Intent Assessment: ActivePyModule

**Source files:** `src/mgr/ActivePyModule.cc`, `src/mgr/ActivePyModule.h`
**Corpus HEAD:** `8681fa6ebac230f86eb445bf57095c63e7f1abcc` (2026-08-11)
**Assessment date:** 2026-09-11
**Commits analysed:** 60
**Functions assessed:** 23

> This artefact was produced by an AI assessment agent reading the raw git
> corpus in `/home/szuraski/BobOutput/Object History/v4/ActivePyModule/`.
> It describes the intended behaviour of each function as reconstructed from
> commit history — not necessarily what the current code does.
> Test-writing agents should use this as the ground truth for what to test,
> and treat divergences as likely bugs.

## Class overview

`ActivePyModule` is the active-module adapter between ceph-mgr and a Python module instance. It owns Python calls, translates command and notification data, stores module health checks and URI state, and performs authorization checks for commands. Its important ownership rules are that Python calls use the module's interpreter/thread state, Python references are released, and calls racing with module shutdown are cancelled. The class evolved from the original `MgrPyModule` through the active/standby refactor (`df8797320bed7ad9f121477e35d7e3862efd89bd`) and later gained per-module finishers, authorization, performance counters, pickle-based cross-interpreter calls, and explicit handling of expected `NotImplementedError`.

## `ActivePyModule::config_notify()`

**Introduced:** `f27a5dc6155440f0add91213d68bb690d8bf9cd7` — mgr: call config_notify method when mgr's config has changed
**Last modified:** `25b99ddecbd90e7b3456bd9a70f18c1d62cf5099` — mgr/mgr_module: remove CLI commands to manage modules' logging
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Invoke the module's private configuration-refresh hook when manager configuration changes. The hook was renamed to `_config_notify` when configuration updates became the supported mechanism for module-local logging configuration.

### Invariants and contracts

- The callback is a notification hook and its return value is not part of the manager contract. (`f27a5dc6155440f0add91213d68bb690d8bf9cd`)
- The Python method called must be `_config_notify`, not the public/old `config_notify` name. (`25b99ddecbd90e7b3456bd9a70f18c1d62cf5099`)
- Calls racing with shutdown must be cancelled before entering Python. (`40c4b9ac9d8e2b2c17269affada304f5e1554974`)

### Error conditions

- No explicit error return was established; a non-null Python result is released and a null result is ignored. (`f27a5dc6155440f0add91213d68bb690d8bf9cd`)

### Evolution summary

The function was introduced as a direct zero-argument Python call, then renamed its Python target to `_config_notify`. A shutdown-race guard was added later. The compiler-compatibility change in `31654a2ba6b288c901ba387f3815a26066c779d3` was cosmetic.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Lines 239–242 cancel a dead module, line 244 acquires the module interpreter state, and lines 245–251 call `_config_notify` and release a returned reference. The ignored exception result is consistent with the historical void notification contract; no current line contradicts a history-established requirement.

### Test-writing notes

Test both the live callback name and the dead-module no-call path.

## `ActivePyModule::dispatch_remote()`

**Introduced:** `f02316adb4baf4dceaab79cc0ef4c2acdb544f3e` — mgr: enable inter-module calls
**Last modified:** `42c4dfb40ceccd7a1ae98b360592456d8d67346e` — mgr: don't log NotImplementedError from dispatch_remote as an error
**Change count:** 9 commits touched this function
**Divergence:** OK

### Intent
Dispatch a method call into another Python module, crossing interpreter boundaries by deserializing pickled arguments, invoking the method, and serializing the return value. Python exceptions must be captured into `err` rather than escaping across contexts; expected `NotImplementedError` remains an error returned to the caller but must not generate a crash dump or error-level remote log.

### Invariants and contracts

- `err` is required and the caller is responsible for checking method existence before dispatch; the bound method is asserted present. (`f02316adb4baf4dceaab79cc0ef4c2acdb544f3e`, `ab23c506964753990f9fe23e314b9f3e2547a773`)
- Arguments and keyword arguments are serialized across subinterpreters and the return value is serialized back. (`f69069e114ea8c785d6c27c57560a0b9bb8c16be`)
- Pickle loads/dumps must receive each bytes object as one argument; the `(O)` format is required, including for empty tuples. (`8ae44f6a3753bf5a1681887bb41705f313c47ff9`)
- A failed Python call is reported to the caller, not allowed to bubble across interpreter contexts. (`f02316adb4baf4dceaab79cc0ef4c2acdb544f3e`, `719d5e1836c95bcbc446dbeb7d8f03adefd02a3e`)
- `NotImplementedError` is an expected optional-interface signal: it is returned but does not request a crash dump or error-level remote logging. (`18c4e08ccddde9710cded2df7e0becc2dde7e56c`, `42c4dfb40ceccd7a1ae98b360592456d8d67346e`)
- The optional `crash_dump` output defaults to true and is set false only for `NotImplementedError`. (`42c4dfb40ceccd7a1ae98b360592456d8d67346e`)

### Error conditions

- Failure to unpickle args or kwargs returns `std::nullopt`, fills `err`, logs the deserialize failure, and releases already-created objects. (`f69069e114ea8c785d6c27c57560a0b9bb8c16be`)
- A missing/invalid receiving method is an assertion failure because the caller must have run `method_exists`. (`f02316adb4baf4dceaab79cc0ef4c2acdb544f3e`, `ab23c506964753990f9fe23e314b9f3e2547a773`)
- A Python exception from the receiver returns `std::nullopt` and writes the formatted exception to `err`; `NotImplementedError` suppresses crash-dump/error-log treatment only. (`18c4e08ccddde9710cded2df7e0becc2dde7e56c`, `42c4dfb40ceccd7a1ae98b360592456d8d67346e`)
- Failure to pickle the return value returns `std::nullopt` and reports the error. (`f69069e114ea8c785d6c27c57560a0b9bb8c16be`)

### Evolution summary

The original inter-module call passed Python objects directly. `f69069e114ea8c785d6c27c57560a0b9bb8c16be` changed the API to byte spans and optional serialized output. `8ae44f6a3753bf5a1681887bb41705f313c47ff9` fixed leaked method-name objects and argument packing. The two August 2026 commits refined expected `NotImplementedError` handling and threaded the crash-dump decision to callers.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Lines 151–154 enforce the non-null error pointer and default crash-dump state; lines 160–181 load both serialized inputs and clean up on the second-load failure. Lines 184–199 enforce the caller-precondition assertion and release the bound method, kwargs, and args. Lines 213–218 implement the `NotImplementedError` exception contract, while lines 223–234 serialize and release the successful return. No DIVERGED condition is established. The performance-independent success/error paths are grounded by the serialization and exception commits.

### Test-writing notes

Cover empty tuple/dict pickle payloads, each load/dump failure, receiver exceptions, normal return serialization, and `NotImplementedError` with and without the optional output pointer.

## `ActivePyModule::get_health_checks()`

**Introduced:** `e51be85c24d36cb3f50f98f7c401f352fd1cd7e4` — mgr: keep per-module checks, and report them back to the mon
**Last modified:** `40c4b9ac9d8e2b2c17269affada304f5e1554974` — mgr: handle race with finisher after shutdown
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Merge this module's stored health checks into the caller's aggregate map, unless the module is dead and a pending callback must be cancelled.

### Invariants and contracts

- Stored per-module health checks are merged into the supplied aggregate. (`e51be85c24d36cb3f50f98f7c401f352fd1cd7e4`)
- A dead module must not expose state through a shutdown-racing callback. (`40c4b9ac9d8e2b2c17269affada304f5e1554974`)

### Error conditions

- None established beyond cancellation for a dead module. (`40c4b9ac9d8e2b2c17269affada304f5e1554974`)

### Evolution summary

The function was introduced as a direct merge and later acquired the shutdown guard. The `get_health_checks` declaration remained stable.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Lines 324–328 perform the established dead-module cancellation and merge the stored map. The non-null `checks` precondition is implicit and not separately documented in history; flagging it as a required guard would be ungrounded.

## `ActivePyModule::handle_command()`

**Introduced:** `ac30e6cee2b2d3815438f1a392a951d511bddfd4` — mgr: create ceph-mgr service
**Last modified:** `95a90f7da8a32dd2a5a1e3b381aaeacea378437b` — mgr: Add per-module performance counters to mgr
**Change count:** 20 commits touched this function
**Divergence:** OK

### Intent
Convert a manager command and optional bulk input into the Python command-handler call, expose the current session and command permissions during that call, translate the required three-element result back into manager output, and return `-EINVAL` for unusable module state, malformed results, or Python exceptions.

### Invariants and contracts

- Output stream pointers are required. (`ab23c506964753990f9fe23e314b9f3e2547a773`)
- An uninstantiated module reports `Module not instantiated` and returns `-EINVAL`. (`b1e8d63bf787dea415eabda99def9d7e4aff4f9`, subject recorded in commits.txt)
- The Python handler receives raw `inbuf` bytes plus the command map. (`140761f8a2df10c45eb02041fad5e8237bf57c20`)
- The handler name is `_handle_command`. (`a5e9eb018947bacc212b8b480ee149f8d6bf76d0`)
- A command invocation temporarily exposes its session and permission string to `is_authorized`, then clears both. (`282c31c383856b45caadcefb876a71e39fe4b219`)
- A valid result is a three-element tuple containing the return code, display text, and status text. (`af8c2ce4ea2ad03b44ca1566a6095aee9adbd22b`, `48c4bc445fcacd7980e4b135a3115b88b05f1`)
- Successful handler execution records command latency when a performance counter exists. (`95a90f7da8a32dd2a5a1e3b381aaeacea378437b`)

### Error conditions

- Null output streams assert. (`ab23c506964753990f9fe23e314b9f3e2547a773`)
- A null class instance returns `-EINVAL` and writes the established diagnostic. (`b1e8d63bf787dea415eabda99def9d7e4aff4f9`)
- A result whose tuple size is not three logs the wrong-type error and returns `-EINVAL`. (`af8c2ce4ea2ad03b44ca1566a6095aee9adbd22b`)
- A Python exception clears display output, reports the formatted exception in status output, and returns `-EINVAL`. (`71a985623392e43b8e793d7f2b7d973b6185e491`)

### Evolution summary

The original handler passed only a command object; `140761f8a2df10c45eb02041fad5e8237bf57c20` added bulk input. The Python name changed to `_handle_command` with the decorator work, and authorization context was added in 2019. Later changes migrated Python 2 APIs to Python 3 and added latency counters. Cosmetic compiler and namespace changes do not alter the contract.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Lines 263–264 enforce output pointers; 266–271 implement the uninstantiated error. Lines 275–279 marshal the map and complete input buffer, and 281–291 install and clear authorization context around `_handle_command`. Lines 300–307 enforce the three-element result and translate its fields; lines 311–318 implement the exception path. Lines 295–298 record successful-call latency. The current source has no history-established contradiction.

### Test-writing notes

Test empty and non-empty input buffers, malformed tuple sizes, exceptions, permission context lifetime, and the exact output-stream routing.

## `ActivePyModule::is_authorized()`

**Introduced:** `282c31c383856b45caadcefb876a71e39fe4b219` — mgr: python modules can now perform authorization tests
**Last modified:** `282c31c383856b45caadcefb876a71e39fe4b219` — mgr: python modules can now perform authorization tests
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Allow a Python command handler to perform a finer-grained capability check using the active session, module identity, command permissions, request arguments, and peer address.

### Invariants and contracts

- Authorization outside a command session must fail closed. (`282c31c383856b45caadcefb876a71e39fe4b219`)
- The command prefix is not rechecked; only module/service arguments and the permissions associated with the active command are tested. (`282c31c383856b45caadcefb876a71e39fe4b219`)

### Error conditions

- A null session returns false. (`282c31c383856b45caadcefb876a71e39fe4b219`)

### Evolution summary

This function was introduced with command-session state and has no later semantic changes.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Lines 333–335 fail closed without a session. Lines 337–346 construct an empty-prefix `MonCommand`, use the stored permission string, and pass module identity, arguments, and peer address to the capability check exactly as established. The typo in the historical comment is non-semantic.

## `ActivePyModule::load()`

**Introduced:** `ac30e6cee2b2d3815438f1a392a951d511bddfd4` — mgr: create ceph-mgr service
**Last modified:** `719d5e1836c95bcbc446dbeb7d8f03adefd02a3e` — mgr: generate crash dump for python exceptions
**Change count:** 11 commits touched this function
**Divergence:** OK

### Intent
Construct the Python module class instance with the module name, manager-module capsule, and this-object capsule while holding the module interpreter state. Return success only after construction succeeds; construction failure is reported and returns `-EINVAL`.

### Invariants and contracts

- The manager-module pointer argument is required. (`ab23c506964753990f9fe23e314b9f3e2547a773`)
- The Python constructor receives three arguments and references are released after the call. (`563878ba217491dd0a6fbd588cd56d09e3456c14`, `2005ce83adc8f321af97e813810ad30629956a3b`)
- Constructor failure returns `-EINVAL` and reports the Python error. (`719d5e1836c95bcbc446dbeb7d8f03adefd02a3e`)

### Error conditions

- Null `py_modules` asserts. (`ab23c506964753990f9fe23e314b9f3e2547a773`)
- A null constructed instance returns `-EINVAL`. (`ac30e6cee2b2d3815438f1a392a951d511bddfd4`)

### Evolution summary

The function moved from owning the module/class to using `PyModuleRunner`, while retaining the three-argument constructor protocol. Python 3 conversion changed the name object and later the crash-reporting API enriched constructor errors. Command loading was intentionally removed from this function when command definitions moved earlier (`834bc27940507737f064bca7362b4c7f4cd54c98`).

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Lines 34–35 assert and acquire the expected state; lines 39–46 create the three constructor arguments and release the name/tuple references. Lines 47–50 report constructor failure and return `-EINVAL`, while lines 52–55 return success. The capsules themselves are borrowed through tuple ownership as established by the constructor refactor.

## `ActivePyModule::method_exists()`

**Introduced:** `f02316adb4baf4dceaab79cc0ef4c2acdb544f3e` — mgr: enable inter-module calls
**Last modified:** `f02316adb4baf4dceaab79cc0ef4c2acdb544f3e` — mgr: enable inter-module calls
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Check whether the Python instance has an attribute usable as the requested remote method, releasing the temporary reference on success.

### Invariants and contracts

- A missing attribute returns false; a found attribute is released and returns true. (`f02316adb4baf4dceaab79cc0ef4c2acdb544f3e`)

### Error conditions

- Python attribute lookup failure returns false. (`f02316adb4baf4dceaab79cc0ef4c2acdb544f3e`)

### Evolution summary

The method was introduced alongside remote dispatch and has no semantic revisions. The map's association with `f69069e114ea8c785d6c27c57560a0b9bb8c16be` is a hunk-context artifact; the implementation predates that commit.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Lines 133–141 acquire the interpreter state, perform the lookup, return false on null, and decref the found object before returning true. No unexplained state mutation is present.

## `ActivePyModule::notify()`

**Introduced:** `ac30e6cee2b2d3815438f1a392a951d511bddfd4` — mgr: create ceph-mgr service
**Last modified:** `95a90f7da8a32dd2a5a1e3b381aaeacea378437b` — mgr: Add per-module performance counters to mgr
**Change count:** 13 commits touched this function
**Divergence:** OK

### Intent
Send a typed notification to the Python module, release the result, and report Python exceptions with module/method context. Notifications racing with shutdown are cancelled.

### Invariants and contracts

- A dead module is not called. (`40c4b9ac9d8e2b2c17269affada304f5e1554974`)
- The instance must exist and the module interpreter state/GIL must be active for the call. (`ac30e6cee2b2d3815438f1a392a951d511bddfd4`, `6a8da7ca734726315c06929635c25dbb88599654`)
- Python exceptions are reported with module and notification context. (`3d3ee4bf768b4aaa3252f06c299cfee9fdb28148`, `719d5e1836c95bcbc446dbeb7d8f03adefd02a3e`)
- Successful calls release the Python result and record latency when counters exist. (`95a90f7da8a32dd2a5a1e3b381aaeacea378437b`)

### Error conditions

- A Python exception is logged and formatted; the void notification API does not return an error. (`3d3ee4bf768b4aaa3252f06c299cfee9fdb28148`)

### Evolution summary

The function began as a direct `notify` call and was migrated to the per-module interpreter during the module-management refactors. It gained traceback-aware error reporting, shutdown cancellation, and performance timing. The Python 3 and thread-state changes are compatibility/structural changes.

### Deferred / known incomplete

The original FIXME about unloading a spontaneously broken module remains in lines 85–88. (`ac30e6cee2b2d3815438f1a392a951d511bddfd4`)

### Implementation critique

SATISFIES — Lines 60–67 enforce shutdown cancellation and the instance precondition; line 67 and lines 69–73 execute under the correct state. Lines 75–81 release successful results and count latency, while lines 82–88 format failure context. The unresolved unload FIXME is explicitly historical deferred work, not a divergence.

## `ActivePyModule::notify_clog()`

**Introduced:** `9ea37c223f92b8f228c57a4c17d4da02d99be756` — mgr: pass through cluster log to plugins
**Last modified:** `95a90f7da8a32dd2a5a1e3b381aaeacea378437b` — mgr: Add per-module performance counters to mgr
**Change count:** 11 commits touched this function
**Divergence:** OK

### Intent
Serialize a cluster `LogEntry` into the Python representation and deliver it through the normal `notify` method using the `clog` notification type, with the same shutdown, reference, error-reporting, and timing rules as ordinary notifications.

### Invariants and contracts

- The Python notification receives `"clog"` and the owned formatter object as `(sN)`. (`9ea37c223f92b8f228c57a4c17d4da02d99be756`)
- A dead module is not called. (`40c4b9ac9d8e2b2c17269affada304f5e1554974`)
- Successful results are released and Python failures are formatted with module context. (`71a985623392e43b8e793d7f2b7d973b6185e491`, `719d5e1836c95bcbc446dbeb7d8f03adefd02a3e`)
- Successful calls record notification latency when enabled. (`95a90f7da8a32dd2a5a1e3b381aaeacea378437b`)

### Error conditions

- Python exceptions are logged and do not escape the void callback. (`9ea37c223f92b8f228c57a4c17d4da02d99be756`)

### Evolution summary

The function was added for cluster-log forwarding, then moved to the active-module interpreter and enhanced with traceback-aware errors, shutdown cancellation, and performance timing.

### Deferred / known incomplete

The original unload FIXME remains at current lines 124–127. (`9ea37c223f92b8f228c57a4c17d4da02d99be756`)

### Implementation critique

SATISFIES — Lines 94–101 cancel dead calls and establish the Python state. Lines 103–112 build and pass the `clog` payload, lines 114–120 release/count successful calls, and lines 121–128 report failures. All documented behavior is enforced.

## `ActivePyModule::ActivePyModule()`

**Introduced:** `df8797320bed7ad9f121477e35d7e3862efd89bd` — mgr: cut down duplication between active+standby
**Last modified:** `95a90f7da8a3e3b8b8a5843dfe75e97826f70a57d6ebe` — mgr: Add per-module performance counters to mgr
**Change count:** 2 commits touched this constructor
**Divergence:** OK

### Intent
Construct the active runner with the shared Python-module runner state and create one per-module finisher with the bounded module-specific thread name.

### Invariants and contracts

- The active adapter uses `PyModuleRunner` rather than duplicating module ownership and Python state. (`df8797320bed7ad9f121477e35d7e3862efd89bd`)
- The finisher is per active module. (`46de6431603a56fa9ca2a7c7c9c795f126d16452`)
- The optional monitor is passed through to the base runner. (`95a90f7da8a32dd2a5a1e3b381aaeacea378437b`)

### Error conditions

None established.

### Evolution summary

The constructor initially inherited the runner, then gained a per-module finisher and later a monitor argument. `62ade6b38d1a9ee9f853f165d7b8adfcad4ce53b` changed only thread-name construction syntax; `f4bc4be0fa812a042ec93d08987290fa40ae41b3` changed the returned thread-name source.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Lines 56–60 pass `py_module_`, `clog_`, and `monitor_` to `PyModuleRunner`; the finisher is constructed with the global context, runner thread name, and a truncated formatted module name. This enforces the constructor contracts. The empty body at lines 62–63 is intentional.

## `ActivePyModule::config_notify()` (header declaration)

**Introduced:** `f27a5dc6155440f0add91213d68bb690d8bf9cd7` — mgr: call config_notify method when mgr's config has changed
**Last modified:** `f27a5dc6155440f0add91213d68bb690d8bf9cd7` — mgr: call config_notify method when mgr's config has changed
**Change count:** 1 commit touched this declaration
**Divergence:** OK

### Intent
Declare the configuration notification entry point implemented in the source file.

### Invariants and contracts

- The public C++ entry point exists for manager-to-module configuration notifications. (`f27a5dc6155440f0add91213d68bb690d8bf9cd7`)

### Error conditions

None established.

### Evolution summary

The declaration was introduced with the implementation and remains unchanged.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Header line 96 declares `void config_notify();`, matching the source definition at lines 237–253.

## `ActivePyModule::dispatch_remote()` (header declaration)

**Introduced:** `f02316adb4baf4dceaab79cc0ef4c2acdb544f3e` — mgr: enable inter-module calls
**Last modified:** `42c4dfb40ceccd7a1ae98b360592456d8d67346e` — mgr: don't log NotImplementedError from dispatch_remote as an error
**Change count:** 3 commits touched this declaration
**Divergence:** OK

### Intent
Expose the remote-dispatch API, including serialized argument spans, error output, and optional crash-dump output.

### Invariants and contracts

- The signature reflects serialized cross-interpreter transport. (`f69069e114ea8c785d6c27c57560a0b9bb8c16be`)
- `crash_dump` is optional for compatibility and defaults to null. (`42c4dfb40ceccd7a1ae98b360592456d8d67346e`)

### Error conditions

None beyond the source function's conditions.

### Evolution summary

The declaration evolved from `PyObject*` arguments/return to byte spans and optional serialized output, then added the optional crash-dump result.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Header lines 71–76 exactly expose the serialized spans, required error pointer, and default-null crash-dump pointer used by the source implementation.

## `ActivePyModule::get_fin_thread_name()`

**Introduced:** `46de6431603a56fa9ca2a7c7c9c795f126d16452` — mgr: Add one finisher thread per module
**Last modified:** `f4bc4be0fa812a042ec93d08987290fa40ae41b3` — common/Finisher: add method get_thread_name()
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Expose the finisher's actual thread name for callers that need to inspect or report it.

### Invariants and contracts

- Return the per-module finisher thread name rather than construct a second name in the adapter. (`f4bc4be0fa812a042ec93d08987290fa40ae41b3`)

### Error conditions

None established.

### Evolution summary

The accessor initially returned locally stored thread-name state; it was changed to use `Finisher::get_thread_name()` after that API was introduced.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Header lines 108–111 return `finisher.get_thread_name()` as a `std::string_view`, matching the accessor's purpose and the last historical change.

## `ActivePyModule::get_health_checks()` (header declaration)

**Introduced:** `e51be85c24d36cb3f50f98f7c401f352fd1cd7e4` — mgr: keep per-module checks, and report them back to the mon
**Last modified:** `e51be85c24d36cb3f50f98f7c401f352fd1cd7e4` — mgr: keep per-module checks, and report them back to the mon
**Change count:** 1 commit touched this declaration
**Divergence:** OK

### Intent
Declare the health-check merge operation.

### Invariants and contracts

- The adapter provides a health-check extraction entry point. (`e51be85c24d36cb3f50f98f7c401f352fd1cd7e4`)

### Error conditions

None established.

### Evolution summary

The declaration was introduced with the source implementation.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Header line 95 declares the source implementation at lines 322–329.

## `ActivePyModule::get_uri()`

**Introduced:** `a0183a63fa791954d14c57632e184858cefe893d` — mgr: enable python modules to advertise their service URI
**Last modified:** `9d47b164afde3529d43f142356980e3d9853e07f` — mgr/ActivePyModule: return std::string_view instead of std::string copy
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Return the optional URI advertised by the module without copying it.

### Invariants and contracts

- URI state is the value previously supplied through `set_uri`. (`a0183a63fa791954d14c57632e184858cefe893d`)
- The accessor returns a non-owning view rather than a string copy. (`9d47b164afde3529d43f142356980e3d9853e07f`)

### Error conditions

None established.

### Evolution summary

The URI getter was introduced as a value-returning accessor and later changed to `std::string_view` to avoid a copy.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Header lines 103–106 return `uri` directly as `std::string_view`; the view remains tied to the owning object as required.

## `ActivePyModule::handle_command()` (header declaration)

**Introduced:** `ac30e6cee2b2d3815438f1a392a951d511bddfd4` — mgr: create ceph-mgr service
**Last modified:** `282c31c383856b45caadcefb876a71e39fe4b219` — mgr: python modules can now perform authorization tests
**Change count:** 3 commits touched this declaration
**Divergence:** OK

### Intent
Declare the command adapter, including command metadata, session, parsed command, bulk input, and output streams.

### Invariants and contracts

- The declaration carries the session and command metadata needed for authorization checks. (`282c31c383856b45caadcefb876a71e39fe4b219`)
- Bulk input and both output streams are part of the handler contract. (`140761f8a2df10c45eb02041fad5e8237bf57c20`)

### Error conditions

None beyond the source function's conditions.

### Evolution summary

The declaration gained bulk input and later session/command metadata as the implementation evolved.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Header lines 78–84 contain all parameters used by the current implementation at lines 255–320.

## `ActivePyModule::is_authorized()` (header declaration)

**Introduced:** `282c31c383856b45caadcefb876a71e39fe4b219` — mgr: python modules can now perform authorization tests
**Last modified:** `282c31c383856b45caadcefb876a71e39fe4b219` — mgr: python modules can now perform authorization tests
**Change count:** 1 commit touched this declaration
**Divergence:** OK

### Intent
Expose the module-specific capability check to Python-backed command handling.

### Invariants and contracts

- The declaration accepts module-defined string arguments for the active session check. (`282c31c383856b45caadcefb876a71e39fe4b219`)

### Error conditions

None established.

### Evolution summary

Introduced with the implementation and unchanged.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Header line 113 declares the const method with the exact argument map consumed by the source.

## `ActivePyModule::load()` (header declaration)

**Introduced:** `ac30e6cee2b2d3815438f1a392a951d511bddfd4` — mgr: create ceph-mgr service
**Last modified:** `ac30e6cee2b2d3815438f1a392a951d511bddfd4` — mgr: create ceph-mgr service
**Change count:** 1 commit touched this declaration
**Divergence:** OK

### Intent
Expose construction/loading of the Python class instance with the active module collection.

### Invariants and contracts

- The active module collection is required by the constructor capsule protocol. (`563878ba217491dd0a6fbd588cd56d09e3456c14`)

### Error conditions

None beyond the source function's conditions.

### Evolution summary

The declaration was introduced with the active-module adapter and remains stable.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Header line 65 matches the source definition and its required `ActivePyModules*` parameter.

## `ActivePyModule::method_exists()` (header declaration)

**Introduced:** `f02316adb4baf4dceaab79cc0ef4c2acdb544f3e` — mgr: enable inter-module calls
**Last modified:** `f02316adb4baf4dceaab79cc0ef4c2acdb544f3e` — mgr: enable inter-module calls
**Change count:** 1 commit touched this declaration
**Divergence:** OK

### Intent
Expose the preflight method lookup used by remote dispatch.

### Invariants and contracts

- The query is const and returns a boolean existence result. (`f02316adb4baf4dceaab79cc0ef4c2acdb544f3e`)

### Error conditions

None beyond false for missing attributes.

### Evolution summary

Introduced with remote dispatch and unchanged.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Header line 69 declares the const boolean API implemented at source lines 131–142.

## `ActivePyModule::notify()` (header declaration)

**Introduced:** `ac30e6cee2b2d3815438f1a392a951d511bddfd4` — mgr: create ceph-mgr service
**Last modified:** `ac30e6cee2b2d3815438f1a392a951d511bddfd4` — mgr: create ceph-mgr service
**Change count:** 1 commit touched this declaration
**Divergence:** OK

### Intent
Declare the ordinary typed notification entry point.

### Invariants and contracts

- Notification carries type and identifier strings. (`ac30e6cee2b2d3815438f1a392a951d511bddfd4`)

### Error conditions

None at declaration level.

### Evolution summary

The declaration is unchanged while the implementation gained shutdown and timing behavior.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Header line 66 matches the source signature at line 58.

## `ActivePyModule::notify_clog()` (header declaration)

**Introduced:** `9ea37c223f92b8f228c57a4c17d4da02d99be756` — mgr: pass through cluster log to plugins
**Last modified:** `9ea37c223f92b8f228c57a4c17d4da02d99be756` — mgr: pass through cluster log to plugins
**Change count:** 1 commit touched this declaration
**Divergence:** OK

### Intent
Declare the cluster-log notification entry point.

### Invariants and contracts

- The entry point accepts a `LogEntry` for Python conversion. (`9ea37c223f92b8f228c57a4c17d4da02d99be756`)

### Error conditions

None at declaration level.

### Evolution summary

The declaration remains stable while implementation details moved to the active runner.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Header line 67 matches the source signature at line 92.

## `ActivePyModule::set_health_checks()`

**Introduced:** `e51be85c24d36cb3f50f98f7c401f352fd1cd7e4` — mgr: keep per-module checks, and report them back to the mon
**Last modified:** `3068c4290166076093119d1dc08a2c0fada8235f` — mgr: report health check changes immediately
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Replace the stored per-module health-check map and report whether the replacement differs, allowing the manager to send a monitor report immediately when health changes.

### Invariants and contracts

- The new map is moved into module state. (`e51be85c24d36cb3f50f98f7c401f352fd1cd7e4`)
- The return value is true exactly when the old and new maps differ. (`3068c4290166076093119d1dc08a2c0fada8235f`)

### Error conditions

None established.

### Evolution summary

The setter originally returned void and simply moved the map. It was changed to compare before moving so callers can schedule immediate reports.

### Deferred / known incomplete

The comment notes that equality could be made smarter if static-module noise becomes a problem. (`3068c4290166076093119d1dc08a2c0fada8235f`)

### Implementation critique

SATISFIES — Header lines 87–93 compare before move, replace the stored state, and return the comparison result. The implementation exactly enforces the established contract.

## `ActivePyModule::set_uri()`

**Introduced:** `a0183a63fa791954d14c57632e184858cefe893d` — mgr: enable python modules to advertise their service URI
**Last modified:** `a0183a63fa791954d14c57632e184858cefe893d` — mgr: enable python modules to advertise their service URI
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Store the URI advertised by a serving module.

### Invariants and contracts

- The supplied string becomes the module's URI state. (`a0183a63fa791954d14c57632e184858cefe893d`)

### Error conditions

None established.

### Evolution summary

Introduced as the setter paired with `get_uri`; unchanged.

### Deferred / known incomplete

None.

### Implementation critique

SATISFIES — Header lines 98–101 assign the supplied string to `uri`, exactly implementing the historical contract.

## Self-check

- [x] Read every non-comment commit entry in `commits.txt`: 61 commits, including formatting-only and unrelated-hunk entries.
- [x] Scanned the first three and last three chronological diff files for each mapped implementation group, and read all diff files relevant to the function map.
- [x] Used `blame.txt` to cross-reference current implementation lines; the latest semantic blame SHAs are reflected in the applicable sections.
- [x] No `DIVERGED` verdict is set without a named contradicting current line; no such contradiction was established from the corpus.
- [x] Every documented invariant and error condition cites an establishing SHA.
- [x] Every function listed in `functions.txt` has a section, including duplicate source/header entries.
- [x] Every section has a line-specific Implementation critique.
- [x] Historical FIXME/deferred behavior and current unexplained behavior were reviewed; no current significant path could be classified as ungrounded without contradicting the collected history. Performance timing is explicitly grounded by `95a90f7da8a32dd2a5a1e3b381aaeacea378437b`.
