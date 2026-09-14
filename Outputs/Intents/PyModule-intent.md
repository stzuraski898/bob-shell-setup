# Intent Assessment: PyModule

**Source files:** `src/mgr/PyModule.cc`, `src/mgr/PyModule.h`
**Corpus HEAD:** `8681fa6ebac230f86eb445bf57095c63e7f1abcc` (2026-08-11)
**Assessment date:** 2026-09-11
**Commits analysed:** 49
**Functions assessed:** 66

> This artefact was produced by an AI assessment agent reading the raw git
> corpus in `/home/szuraski/BobOutput/Object History/v4/PyModule/`.
> It describes the *intended* behaviour of each function as reconstructed from
> commit history — not necessarily what the current code does.
> Test-writing agents should use this as the ground truth for what to test,
> and treat divergences as likely bugs.

## Class overview

`PyModule` manages the lifecycle, discovery, inspection, and execution context of a Ceph Manager Python plugin module. It loads module definitions, extracts command specs (`COMMANDS`), option schemas (`MODULE_OPTIONS`), and notification subscriptions (`NOTIFY_TYPES`), tests module runnability via `can_run()`, and manages subinterpreter or main-interpreter thread state (`SafeThreadState`). `PyModuleConfig` manages module configuration persistence to the monitor store and local cache.

---

## `PyModule::PyModule(const std::string&)` — [`src/mgr/PyModule.cc:290`](../../../ceph/src/mgr/PyModule.cc:290); declaration [`src/mgr/PyModule.h:114`](../../../ceph/src/mgr/PyModule.h:114)

**Introduced:** `6a8da7ca734726315c06929635c25dbb88599654` — mgr: load all modules (not just active ones)
**Last modified:** `95a90f7da8a32dd2a5a1e3b381aaeacea378437b` — mgr: Add per-module performance counters to mgr
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Initialize a `PyModule` instance with its canonical module name, keeping all status flags (`enabled`, `always_on`, `loaded`, `can_run`, `failed`) initialized to `false` and pointers to `nullptr`.

### Invariants and contracts
- `module_name` is initialized to the provided name and is immutable thereafter. (Established: `6a8da7ca7347`)
- Module starts in an unloaded, non-running, non-failed state. (Established: `6a8da7ca7347`)

### Error conditions
- None.

### Evolution summary
Originally initialized `enabled` from constructor parameters in `6a8da7ca7347`. Refactored when module loading and activation were decoupled. `95a90f7da8a3` moved definition from header to cc file.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 290–292 initialize `module_name` in member initializer list. All member flags default to `false` and pointer fields to `nullptr` in class declaration.

---

## `PyModule::~PyModule()` — [`src/mgr/PyModule.cc:809`](../../../ceph/src/mgr/PyModule.cc:809); declaration [`src/mgr/PyModule.h:116`](../../../ceph/src/mgr/PyModule.h:116)

**Introduced:** `6a8da7ca734726315c06929635c25dbb88599654` — mgr: load all modules (not just active ones)
**Last modified:** `239b0dc8a9c42449ee1faa1bf78bdcc380345ae2` — mgr: add mgr_subinterpreter_modules config
**Change count:** 4 commits touched this function
**Divergence:** DIVERGED

### Intent
Clean up Python objects (`pClass`, `pStandbyClass`, `pPickleModule`) while acquiring GIL. If the module ran in a subinterpreter, terminate that subinterpreter with `Py_EndInterpreter`. If it ran in the main interpreter, do NOT call `Py_EndInterpreter` on the shared main interpreter state. (Established: `3366ef5153f3`, `239b0dc8a9c4`)

### Invariants and contracts
- Must acquire GIL before releasing Python object references. (Established: `6a8da7ca7347`)
- Must decref `pClass`, `pStandbyClass`, and `pPickleModule`. (Established: `6a8da7ca7347`, `f69069e114ea`)
- Must terminate subinterpreters to prevent memory leaks. (Established: `3366ef5153f3`)
- Must NOT terminate the main interpreter when running in main interpreter mode. (Established: `239b0dc8a9c4`)

### Error conditions
- None.

### Evolution summary
`3366ef5153f3` added `Py_EndInterpreter(pMyThreadState.ts)` to prevent interpreter memory leaks. `f69069e114ea` added `pPickleModule` cleanup. `239b0dc8a9c4` made main interpreter the default and added conditional interpreter cleanup.

### Deferred / known incomplete
None.

### Implementation critique
DIVERGED — In [`src/mgr/PyModule.cc:816-818`](../../../ceph/src/mgr/PyModule.cc:816), the condition reads:
```cpp
if (use_main_interpreter) {
  Py_EndInterpreter(pMyThreadState.ts);
}
```
This is inverted: `Py_EndInterpreter` is called when `use_main_interpreter` is `true`, and NOT called when `use_main_interpreter` is `false` (i.e. when running in a subinterpreter). The intended contract from commit `239b0dc8a9c4` requires calling `Py_EndInterpreter` only for subinterpreters (`if (!use_main_interpreter)`). Citing establishing SHA `239b0dc8a9c4` and contradicting line [`src/mgr/PyModule.cc:816`](../../../ceph/src/mgr/PyModule.cc:816).

---

## `PyModule::load(PyThreadState*)` — [`src/mgr/PyModule.cc:363`](../../../ceph/src/mgr/PyModule.cc:363); declaration [`src/mgr/PyModule.h:127`](../../../ceph/src/mgr/PyModule.h:127)

**Introduced:** `6a8da7ca734726315c06929635c25dbb88599654` — mgr: load all modules (not just active ones)
**Last modified:** `a89074c6bee999a10952c24c5b6afc2bc05e54bf` — mgr: replace deprecated PyImport_ImportModuleNoBlock with PyImport_ImportModule
**Change count:** 14 commits touched this function
**Divergence:** OK

### Intent
Load and initialize the Python module: determine whether to run in main interpreter or create a subinterpreter based on `mgr_subinterpreter_modules`, import `pickle`, find the `MgrModule` subclass, load commands, load options, load notify types, optionally load `MgrStandbyModule`, and evaluate `can_run()`.

### Invariants and contracts
- `pMainThreadState` must not be null (`ceph_assert(pMainThreadState != nullptr)`). (Established: `6a8da7ca7347`)
- Module runs in main interpreter unless listed in `mgr_subinterpreter_modules` or `*` is configured. (Established: `239b0dc8a9c4`)
- When running in subinterpreter, must create new thread state via `Py_NewInterpreter()`. (Established: `6a8da7ca7347`)
- `loaded` is set to true as soon as `MgrModule` subclass and metadata are successfully loaded. (Established: `6a8da7ca7347`)
- `can_run` result and explanation string are extracted from `can_run()` tuple `(bool, str)`. (Established: `712ad57d09a2`)

### Error conditions
- Returns `-EINVAL` if `Py_NewInterpreter()` fails. (Established: `6a8da7ca7347`)
- Returns `-EINVAL` if `pickle` module fails to import. (Established: `f69069e114ea`)
- Returns error code from `load_subclass_of("MgrModule", &pClass)` if primary class is not found. (Established: `6a8da7ca7347`)
- Returns error code and sets `error_string` if `load_commands()` or `load_options()` fails. (Established: `6a8da7ca7347`, `6c8fba975831`)

### Evolution summary
Evolution moved Python system path and argv initialization to registry (`51a5774aa605`, `07773617f339`), added option loading (`6c8fba975831`), notify type loading (`ee4e3ecd6e07`), pickle module importing (`f69069e114ea`), and subinterpreter selection (`239b0dc8a9c4`).

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 365–484 enforce thread state checks, subinterpreter config parsing, pickle import, class inspection, and error handling.

---

## `PyModule::load_subclass_of(const char*, PyObject**)` — [`src/mgr/PyModule.cc:749`](../../../ceph/src/mgr/PyModule.cc:749); declaration [`src/mgr/PyModule.h:64`](../../../ceph/src/mgr/PyModule.h:64)

**Introduced:** `6a8da7ca734726315c06929635c25dbb88599654` — mgr: load all modules (not just active ones)
**Last modified:** `c1614fe7b89374095c4b434946d221ecfe512fb9` — PyModule: Fix memory leak in load_subclass_of
**Change count:** 5 commits touched this function
**Divergence:** OK

### Intent
Import `mgr_module` to find `base_class`, import the plugin module `module_name`, iterate over module attributes to locate a unique subclass of `base_class` (excluding the base class itself), and return it via `py_class`.

### Invariants and contracts
- Must import `mgr_module` and find `base_class` attribute. (Established: `6a8da7ca7347`)
- Must import `module_name` and inspect dictionary symbols. (Established: `6a8da7ca7347`)
- Ignores types that are not subclasses or are identical to `base_class`. (Established: `6a8da7ca7347`)
- If multiple subclasses are found, logs error and keeps only the first. (Established: `6a8da7ca7347`)
- Cleanly decrefs `mgr_module_type` on all return paths. (Established: `c1614fe7b893`)

### Error conditions
- Returns `-EINVAL` if `mgr_module` cannot be imported or `base_class` attribute missing. (Established: `6a8da7ca7347`)
- Returns `-ENOENT` if `module_name` plugin module cannot be imported. (Established: `6a8da7ca7347`)
- Returns `-EINVAL` if no subclass is found in the plugin module. (Established: `6a8da7ca7347`)

### Evolution summary
`7c80548dba38` added `peek_pyerror()` into `error_string`. `719d5e1836c9` forwarded crash dump context. `c1614fe7b893` fixed memory leak of `mgr_module_type` when plugin module import fails.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 751–807 implement all import checks, dictionary iteration, error recording, and reference counting without leaks.

---

## `PyModule::walk_dict_list(const std::string&, std::function<int(PyObject*)>)` — [`src/mgr/PyModule.cc:487`](../../../ceph/src/mgr/PyModule.cc:487); declaration [`src/mgr/PyModule.h:88`](../../../ceph/src/mgr/PyModule.h:88)

**Introduced:** `6c8fba9758319a173fd479263e6242b36817685d` — mgr: load MgrModule.OPTIONS and use it in upgrade
**Last modified:** `3eeaefddb98b76e319b47891d6cb41cff48cccff` — mgr/PyModule: initialize options on standby class too
**Change count:** 4 commits touched this function
**Divergence:** OK

### Intent
Retrieve a list attribute (such as `COMMANDS` or `MODULE_OPTIONS`) from `pClass`, verify it is a list of dictionaries, and invoke the callback `fn` on each dictionary entry.

### Invariants and contracts
- Target attribute must exist on `pClass` and must be of type `PyList_Type`. (Established: `6c8fba975831`)
- Every element in the list must be a `PyDict_Type`. (Established: `6c8fba975831`)
- Aborts traversal early if `fn` returns non-zero. (Established: `6c8fba975831`)
- Decrefs `command_list` before returning. (Established: `6c8fba975831`)

### Error conditions
- Returns `-EINVAL` if attribute is missing, not a list, or contains a non-dict entry. (Established: `6c8fba975831`)

### Evolution summary
`ab23c5069647` replaced assert with `ceph_assert`. `3eeaefddb98b` retained utility for option and command loading across class types.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 487–526 check attribute presence, list type, element dict type, decref `command_list`, and propagate callback status.

---

## `PyModule::load_commands()` — [`src/mgr/PyModule.cc:585`](../../../ceph/src/mgr/PyModule.cc:585); declaration [`src/mgr/PyModule.h:92`](../../../ceph/src/mgr/PyModule.h:92)

**Introduced:** `834bc27940507737f064bca7362b4c7f4cd54c98` — mgr: load command definitions earlier
**Last modified:** `719d5e1836c95bcbc446dbeb7d8f03adefd02a3e` — mgr: generate crash dump for python exceptions
**Change count:** 6 commits touched this function
**Divergence:** OK

### Intent
Invoke `_register_commands` on `pClass` to allow dynamic command registration, then read the `COMMANDS` list using `walk_dict_list` and populate `commands`.

### Invariants and contracts
- Calls `_register_commands(module_name)` method on `pClass` if present. (Established: `a5e9eb018947`)
- Parses `cmd`, `desc`, and `perm` string fields from each command dict into `ModuleCommand`. (Established: `834bc2794050`)
- Parses optional `poll` boolean flag defaulting to `false`. (Established: `78e884dfb042`, `1453f0ff1f57`)
- Sets `ModuleCommand::module_name` to `this->module_name`. (Established: `834bc2794050`)

### Error conditions
- Propagates error return from `walk_dict_list("COMMANDS", ...)`. (Established: `834bc2794050`)

### Evolution summary
Added `poll` attribute handling in `78e884dfb042` and `1453f0ff1f57`. Added `_register_commands` hook in `a5e9eb018947`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 585–631 invoke `_register_commands`, parse `cmd`, `desc`, `perm`, `poll`, assign `module_name`, and append to `commands`.

---

## `PyModule::register_options(PyObject*)` — [`src/mgr/PyModule.cc:528`](../../../ceph/src/mgr/PyModule.cc:528); declaration [`src/mgr/PyModule.h:95`](../../../ceph/src/mgr/PyModule.h:95)

**Introduced:** `3eeaefddb98b76e319b47891d6cb41cff48cccff` — mgr/PyModule: initialize options on standby class too
**Last modified:** `719d5e1836c95bcbc446dbeb7d8f03adefd02a3e` — mgr: generate crash dump for python exceptions
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Call `_register_options(module_name)` on the specified module class object (`pClass` or `pStandbyClass`) to trigger Python-side option schema registration.

### Invariants and contracts
- Calls `_register_options` method with `module_name` as parameter. (Established: `3eeaefddb98b`)
- Non-fatal if `_register_options` raises an exception; logs error via `handle_pyerror` and returns 0. (Established: `3eeaefddb98b`)

### Error conditions
- Exception during method call is caught and logged; returns 0. (Established: `3eeaefddb98b`)

### Evolution summary
Extracted into helper in `3eeaefddb98b` to allow option registration for both active and standby module classes.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 528–542 call `_register_options`, manage `PyObject*` refcounts, and handle exceptions.

---

## `PyModule::load_options()` — [`src/mgr/PyModule.cc:633`](../../../ceph/src/mgr/PyModule.cc:633); declaration [`src/mgr/PyModule.h:96`](../../../ceph/src/mgr/PyModule.h:96)

**Introduced:** `6c8fba9758319a173fd479263e6242b36817685d` — mgr: load MgrModule.OPTIONS and use it in upgrade
**Last modified:** `0d94eebb0dd1b3e2afdde92e1c1051affded46f2` — mgr: allow specifying module option level
**Change count:** 6 commits touched this function
**Divergence:** OK

### Intent
Read the `MODULE_OPTIONS` list using `walk_dict_list` and populate `options` with parsed `MgrMap::ModuleOption` records including type, level, description, default, min/max bounds, enum values, tags, see_also, and runtime flags.

### Invariants and contracts
- Option `name` is required. (Established: `6c8fba975831`)
- Option `type` defaults to `Option::TYPE_STR` unless converted by `Option::str_to_type()`. (Established: `6c8fba975831`)
- Option `level` defaults to `Option::level_t::LEVEL_ADVANCED` unless specified as an integer. (Established: `0d94eebb0dd1`)
- Populates `enum_allowed`, `see_also`, `tags` from Python list attributes if present. (Established: `1f3e9d4811b8`)
- Handles `runtime` bool flag setting/clearing `Option::FLAG_RUNTIME`. (Established: `1f3e9d4811b8`)

### Error conditions
- Returns error code if `walk_dict_list("MODULE_OPTIONS", ...)` fails. (Established: `6c8fba975831`)

### Evolution summary
Added enum/tags/see_also/runtime handling (`1f3e9d4811b8`), renamed `OPTIONS` to `MODULE_OPTIONS` (`641d9e42ba14`), fixed `Py_ssize_t` indices (`52d1473f13eb`), and added `level` parsing (`0d94eebb0dd1`).

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 633–729 comprehensively parse module options into `options` map.

---

## `PyModule::load_notify_types()` — [`src/mgr/PyModule.cc:544`](../../../ceph/src/mgr/PyModule.cc:544); declaration [`src/mgr/PyModule.h:99`](../../../ceph/src/mgr/PyModule.h:99)

**Introduced:** `ee4e3ecd6e0754854c00f3dfa0eaaa17bbf3603d` — mgr: only queue notify events that modules ask for
**Last modified:** `18cb6bf5ad94b7452b0f4e3a558913f662246c9b` — mgr/PyModule: clear Python exception when NOTIFY_TYPES is missing
**Change count:** 3 commits touched this function
**Divergence:** OK

### Intent
Read the optional `NOTIFY_TYPES` attribute from `pClass` and populate `notify_types` set with notification event names. If `NOTIFY_TYPES` is not defined on the class, treat as optional, clear the `AttributeError`, and return 0.

### Invariants and contracts
- If `NOTIFY_TYPES` is missing (raises `AttributeError`), must clear Python exception indicator and return 0. (Established: `18cb6bf5ad94`)
- If `NOTIFY_TYPES` is present, it must be a `PyList_Type` containing `PyUnicode_Type` elements. (Established: `ee4e3ecd6e07`)
- Non-list or non-string entries are fatal to notification loading and return `-EINVAL`. (Established: `ee4e3ecd6e07`)

### Error conditions
- Returns 0 when `NOTIFY_TYPES` is missing (`AttributeError`). (Established: `4589c4d8ac52`, `18cb6bf5ad94`)
- Returns `-EINVAL` if getting attribute causes an unexpected Python exception. (Established: `18cb6bf5ad94`)
- Returns `-EINVAL` if `NOTIFY_TYPES` is not a list or contains non-string items. (Established: `ee4e3ecd6e07`)

### Evolution summary
Introduced in `ee4e3ecd6e07` as a mandatory list. `4589c4d8ac52` made it optional. `18cb6bf5ad94` fixed pending `AttributeError` exception leak on missing attribute.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 544–583 correctly check for `PyExc_AttributeError`, clear it via `PyErr_Clear()`, parse strings into `notify_types`, and manage reference counts.

---

## `PyModule::is_option(const std::string&)` — [`src/mgr/PyModule.cc:731`](../../../ceph/src/mgr/PyModule.cc:731); declaration [`src/mgr/PyModule.h:118`](../../../ceph/src/mgr/PyModule.h:118)

**Introduced:** `2e8f9e690141641c06a6dc8e62ec4c63a2efebe9` — mgr: return options as appropriate python type
**Last modified:** `c4e2965a4b83f39927e1cfc47ff6941cac76afb7` — mgr: hold GIL while generating a typed option value
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Query whether an option named `option_name` exists in `options`.

### Invariants and contracts
- Acquires `lock` to safely check `options` map membership. (Established: `2e8f9e690141`)

### Error conditions
- None. Returns boolean.

### Evolution summary
Unchanged since introduction in `2e8f9e690141`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 731–735 acquire `std::lock_guard l(lock)` and check `options.count(option_name) > 0`.

---

## `PyModule::get_options()` — [`src/mgr/PyModule.h:119`](../../../ceph/src/mgr/PyModule.h:119)

**Introduced:** `6c8fba9758319a173fd479263e6242b36817685d` — mgr: load MgrModule.OPTIONS and use it in upgrade
**Last modified:** `6c8fba9758319a173fd479263e6242b36817685d`
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Return a const reference to the `options` map.

### Invariants and contracts
- Returns const reference to `options`. (Established: `6c8fba975831`)

### Error conditions
- None.

### Evolution summary
Unchanged since introduction.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 119–121 return `const std::map<std::string, MgrMap::ModuleOption>&`.

---

## `PyModule::get_typed_option_value(const std::string&, const std::string&)` — [`src/mgr/PyModule.cc:737`](../../../ceph/src/mgr/PyModule.cc:737); declaration [`src/mgr/PyModule.h:123`](../../../ceph/src/mgr/PyModule.h:123)

**Introduced:** `2e8f9e690141641c06a6dc8e62ec4c63a2efebe9` — mgr: return options as appropriate python type
**Last modified:** `845ca9c10df70ed1f441b47dcdbc2d1eb5da697e` — mgr: return get_ceph_option result as typed Py object (not string)
**Change count:** 3 commits touched this function
**Divergence:** OK

### Intent
Convert a string option value into its typed Python representation based on the option's registered schema type, or fall back to `PyUnicode_FromString` if the option is not recognized.

### Invariants and contracts
- Must be called while holding the Python GIL. (Established: `c4e2965a4b83`)
- Does not lock `lock` because `MODULE_OPTIONS` are immutable after startup. (Established: `c4e2965a4b83`)
- If option is found in `options`, delegates type conversion to `get_python_typed_option_value`. (Established: `845ca9c10df7`)
- If option is not found, returns `PyUnicode_FromString(value.c_str())`. (Established: `2e8f9e690141`, `48c4bc445fc`)

### Error conditions
- Unknown option returns a unicode Python string of the raw value. (Established: `2e8f9e690141`)

### Evolution summary
Originally contained an inline switch on type (`2e8f9e690141`). Refactored to `get_python_typed_option_value` in `845ca9c10df7`. Python 2 string conversions converted to Python 3 Unicode in `48c4bc445fc`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 737–747 look up option name in `options`, delegate to `get_python_typed_option_value` if found, and return unicode string fallback otherwise.

---

## `PyModule::init_ceph_logger()` — [`src/mgr/PyModule.cc:294`](../../../ceph/src/mgr/PyModule.cc:294); declaration [`src/mgr/PyModule.h:128`](../../../ceph/src/mgr/PyModule.h:128)

**Introduced:** `6a8da7ca734726315c06929635c25dbb88599654` — mgr: load all modules (not just active ones)
**Last modified:** `0a183082e5d66a4895b90e9dee8989d6f12bec25` — mgr: drop python2 support
**Change count:** 4 commits touched this function
**Divergence:** OK

### Intent
Create the `ceph_logger` Python module and bind it to Python's `sys.stderr` and `sys.stdout` so that standard Python print/logging outputs redirect to the Ceph logging subsystem.

### Invariants and contracts
- Creates module using `ceph_logger_module` definition (`log_write` and `log_flush` methods). (Established: `6a8da7ca7347`)
- Replaces `stderr` and `stdout` objects in `sys`. (Established: `6a8da7ca7347`)
- Returns the created `PyObject*` module pointer. (Established: `46003075924b`)

### Error conditions
- None explicitly handled; relies on Python C API.

### Evolution summary
`46003075924b` and `0a183082e5d6` adapted logger creation from Python 2 `Py_InitModule` to Python 3 `PyModule_Create`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 294–300 create the module and set `stderr`/`stdout` on `PySys`.

---

## `ceph_mgr_log(PyObject*, PyObject*)` — [`src/mgr/PyModule.cc:306`](../../../ceph/src/mgr/PyModule.cc:306)

**Introduced:** `3705db897484743849dd9ec417a7aa94f4e0f77b` — mgr: route the root-logger fallback through a module-independent sink
**Last modified:** `e61de15ddb8502abcd74c01617e0c8416bd77bd1` — mgr: forward the root-logger fallback at the record's own level
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Provide a free C-function Python binding (`ceph_module.mgr_log`) as a module-independent sink for root-logger fallback messages, emitting records to Ceph logging at their dynamically mapped debug level without depending on an active module instance.

### Invariants and contracts
- Parses arguments `(int level, char *record)` using format `"is:mgr_log"`. (Established: `e61de15ddb85`)
- Clamps negative log levels to 0 (`if (level < 0) level = 0;`). (Established: `e61de15ddb85`)
- Emits to `dout(ceph::dout::need_dynamic(level))` without module prefix. (Established: `e61de15ddb85`)
- Returns `Py_None`. (Established: `3705db897484`)

### Error conditions
- Returns `nullptr` if argument parsing fails. (Established: `3705db897484`)

### Evolution summary
Introduced in `3705db897484` as `dout(0)` fallback sink. Upgraded in `e61de15ddb85` to forward the record's own dynamic debug level.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 306–322 parse `(level, record)`, normalize negative levels, log via `need_dynamic(level)`, and return `Py_None`.

---

## `PyModule::init_ceph_module()` — [`src/mgr/PyModule.cc:324`](../../../ceph/src/mgr/PyModule.cc:324); declaration [`src/mgr/PyModule.h:129`](../../../ceph/src/mgr/PyModule.h:129)

**Introduced:** `6a8da7ca734726315c06929635c25dbb88599654` — mgr: load all modules (not just active ones)
**Last modified:** `e61de15ddb8502abcd74c01617e0c8416bd77bd1` — mgr: forward the root-logger fallback at the record's own level
**Change count:** 6 commits touched this function
**Divergence:** OK

### Intent
Create the built-in `ceph_module` Python module exposing C++ wrapper types (`BaseMgrModule`, `BaseMgrStandbyModule`, `BasePyOSDMap`, `BasePyOSDMapIncremental`, `BasePyCRUSH`) and module functions like `mgr_log`.

### Invariants and contracts
- Initializes and readies `BaseMgrModuleType`, `BaseMgrStandbyModuleType`, `BasePyOSDMapType`, `BasePyOSDMapIncrementalType`, and `BasePyCRUSHType`. (Established: `6a8da7ca7347`)
- Aborts via `ceph_abort()` if `PyType_Ready()` fails on any built-in class. (Established: `eb59c69674eb`)
- Adds all classes and method definitions to the module and returns the module object. (Established: `6a8da7ca7347`, `3705db897484`)

### Error conditions
- Aborts if `PyType_Ready` fails. (Established: `eb59c69674eb`)

### Evolution summary
`eb59c69674eb` replaced assert with `ceph_abort()`. `0a183082e5d6` dropped Python 2 compatibility. `3705db897484` and `e61de15ddb85` added and documented `mgr_log`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 324–361 build the module definition with `mgr_log`, prepare the 5 base types, check `PyType_Ready`, and return `ceph_module`.

---

## `PyModule::set_enabled(const bool)` — [`src/mgr/PyModule.h:131`](../../../ceph/src/mgr/PyModule.h:131)

**Introduced:** `cf292dfa8f9254e5095689c45a3d5e895e5df333` — mgr: create always_on class of modules
**Last modified:** `cf292dfa8f9254e5095689c45a3d5e895e5df333`
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Update the `enabled` state flag for the module.

### Invariants and contracts
- Modifies `enabled`. (Established: `cf292dfa8f92`)

### Error conditions
- None.

### Evolution summary
Introduced in `cf292dfa8f92`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 131–134 assign `enabled = enabled_`. UNGROUNDED: Unlike getter methods (`is_enabled()`, `is_loaded()`), `set_enabled()` does not acquire `lock`; callers in `PyModuleRegistry` synchronize externally.

---

## `PyModule::set_always_on(const bool)` — [`src/mgr/PyModule.h:136`](../../../ceph/src/mgr/PyModule.h:136)

**Introduced:** `18f253aa3f1b0693c5345756ecca7ca365c389e5` — mgr: monitor-controlled always on modules
**Last modified:** `18f253aa3f1b0693c5345756ecca7ca365c389e5`
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Update the `always_on` flag for the module.

### Invariants and contracts
- Modifies `always_on`. (Established: `18f253aa3f1b`)

### Error conditions
- None.

### Evolution summary
Introduced in `18f253aa3f1b`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 136–138 assign `always_on = always_on_`.

---

## `PyModule::get_commands(std::vector<ModuleCommand>*) const` — [`src/mgr/PyModule.h:143`](../../../ceph/src/mgr/PyModule.h:143)

**Introduced:** `834bc27940507737f064bca7362b4c7f4cd54c98` — mgr: load command definitions earlier
**Last modified:** `948635a8b2130b561fae08bd5b2405a2dc6d3e9f` — mgr: Mutex::Locker -> std::lock_guard
**Change count:** 3 commits touched this function
**Divergence:** OK

### Intent
Append the module's registered `ModuleCommand` list into the caller-provided vector `out`.

### Invariants and contracts
- Caller must provide a non-null pointer (`ceph_assert(out != nullptr)`). (Established: `834bc2794050`, `ab23c5069647`)
- Must hold `lock` while accessing `commands`. (Established: `834bc2794050`)
- Extends `out` without clearing existing elements. (Established: `834bc2794050`)

### Error conditions
- Asserts on null `out`.

### Evolution summary
`ab23c5069647` replaced assert with `ceph_assert`. `948635a8b213` switched to `std::lock_guard`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 143–149 lock the mutex, assert `out != nullptr`, and append `commands` to `out`.

---

## `PyModule::fail(const std::string&)` — [`src/mgr/PyModule.h:155`](../../../ceph/src/mgr/PyModule.h:155)

**Introduced:** `6a8da7ca734726315c06929635c25dbb88599654` — mgr: load all modules (not just active ones)
**Last modified:** `948635a8b2130b561fae08bd5b2405a2dc6d3e9f` — mgr: Mutex::Locker -> std::lock_guard
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Mark the module as failed (`failed = true`) and record the failure reason in `error_string`.

### Invariants and contracts
- Acquires `lock` before updating `failed` and `error_string`. (Established: `6a8da7ca7347`)

### Error conditions
- None.

### Evolution summary
`948635a8b213` adopted `std::lock_guard`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 155–160 lock the mutex, set `failed = true`, and store `reason` in `error_string`.

---

## `PyModule::is_enabled() const` — [`src/mgr/PyModule.h:162`](../../../ceph/src/mgr/PyModule.h:162)

**Introduced:** `6a8da7ca734726315c06929635c25dbb88599654` — mgr: load all modules (not just active ones)
**Last modified:** `cf292dfa8f9254e5095689c45a3d5e895e5df333` — mgr: create always_on class of modules
**Change count:** 3 commits touched this function
**Divergence:** OK

### Intent
Return true if the module is either explicitly enabled or marked as always-on.

### Invariants and contracts
- Acquires `lock` for thread-safe access. (Established: `6a8da7ca7347`)
- Returns `enabled || always_on`. (Established: `cf292dfa8f92`)

### Error conditions
- None.

### Evolution summary
`cf292dfa8f92` added `|| always_on` evaluation.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 162–165 acquire `std::lock_guard l(lock)` and return `enabled || always_on`.

---

## `PyModule::is_failed() const` — [`src/mgr/PyModule.h:167`](../../../ceph/src/mgr/PyModule.h:167)

**Introduced:** `6a8da7ca734726315c06929635c25dbb88599654` — mgr: load all modules (not just active ones)
**Last modified:** `948635a8b2130b561fae08bd5b2405a2dc6d3e9f` — mgr: Mutex::Locker -> std::lock_guard
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Return whether the module has encountered a runtime failure.

### Invariants and contracts
- Acquires `lock` and returns `failed`. (Established: `6a8da7ca7347`)

### Error conditions
- None.

### Evolution summary
`948635a8b213` updated lock guard.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Line 167 locks mutex and returns `failed`.

---

## `PyModule::is_loaded() const` — [`src/mgr/PyModule.h:168`](../../../ceph/src/mgr/PyModule.h:168)

**Introduced:** `6a8da7ca734726315c06929635c25dbb88599654` — mgr: load all modules (not just active ones)
**Last modified:** `948635a8b2130b561fae08bd5b2405a2dc6d3e9f` — mgr: Mutex::Locker -> std::lock_guard
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Return whether the Python module was successfully imported and loaded.

### Invariants and contracts
- Acquires `lock` and returns `loaded`. (Established: `6a8da7ca7347`)

### Error conditions
- None.

### Evolution summary
`948635a8b213` updated lock guard.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Line 168 locks mutex and returns `loaded`.

---

## `PyModule::is_always_on() const` — [`src/mgr/PyModule.h:169`](../../../ceph/src/mgr/PyModule.h:169)

**Introduced:** `cf292dfa8f9254e5095689c45a3d5e895e5df333` — mgr: create always_on class of modules
**Last modified:** `948635a8b2130b561fae08bd5b2405a2dc6d3e9f` — mgr: Mutex::Locker -> std::lock_guard
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Return whether the module is marked always-on.

### Invariants and contracts
- Acquires `lock` and returns `always_on`. (Established: `cf292dfa8f92`)

### Error conditions
- None.

### Evolution summary
`948635a8b213` updated lock guard.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Line 169 locks mutex and returns `always_on`.

---

## `PyModule::should_notify(const std::string&) const` — [`src/mgr/PyModule.h:171`](../../../ceph/src/mgr/PyModule.h:171)

**Introduced:** `ee4e3ecd6e0754854c00f3dfa0eaaa17bbf3603d` — mgr: only queue notify events that modules ask for
**Last modified:** `ee4e3ecd6e0754854c00f3dfa0eaaa17bbf3603d`
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Query whether the module registered interest in receiving notifications for a specific `notify_type`.

### Invariants and contracts
- Returns non-zero/true if `notify_type` is present in `notify_types` set. (Established: `ee4e3ecd6e07`)
- Immutable after startup initialization; does not acquire lock. (Established: `ee4e3ecd6e07`)

### Error conditions
- None.

### Evolution summary
Introduced in `ee4e3ecd6e07`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 171–173 return `notify_types.count(notify_type) > 0`.

---

## `PyModule::get_name() const` — [`src/mgr/PyModule.h:175`](../../../ceph/src/mgr/PyModule.h:175)

**Introduced:** `6a8da7ca734726315c06929635c25dbb88599654` — mgr: load all modules (not just active ones)
**Last modified:** `2cdb67c2fe1c8d21759bda5b2ca7acbd61746148` — mgr/PyModule: do not lock in get_name()
**Change count:** 3 commits touched this function
**Divergence:** OK

### Intent
Return a const reference to `module_name`.

### Invariants and contracts
- Returns `const std::string&` referring to the immutable `module_name`. (Established: `6a8da7ca7347`)
- No lock needed since `module_name` is const. (Established: `2cdb67c2fe1c`)

### Error conditions
- None.

### Evolution summary
`2cdb67c2fe1c` removed unnecessary mutex lock because `module_name` is immutable.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 175–177 return `module_name` directly without locking.

---

## `PyModule::get_error_string() const` — [`src/mgr/PyModule.h:178`](../../../ceph/src/mgr/PyModule.h:178)

**Introduced:** `6a8da7ca734726315c06929635c25dbb88599654` — mgr: load all modules (not just active ones)
**Last modified:** `92aa60e999609f8bfd79e76ca811f66ba4cb7280` — mgr/PyModule: get_error_string() returns copy
**Change count:** 3 commits touched this function
**Divergence:** OK

### Intent
Return a copy of `error_string` under lock protection.

### Invariants and contracts
- Acquires `lock` and returns a string copy (by value) to prevent data races. (Established: `92aa60e99960`)

### Error conditions
- None.

### Evolution summary
`92aa60e99960` fixed thread-safety bug by returning `std::string` by value instead of `const std::string&`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 178–180 lock mutex and return `error_string` by value.

---

## `PyModule::get_can_run() const` — [`src/mgr/PyModule.h:181`](../../../ceph/src/mgr/PyModule.h:181)

**Introduced:** `712ad57d09a2a96dc1e21cd245fbf1a6372867ba` — mgr: evaluate `can_run` method on modules
**Last modified:** `948635a8b2130b561fae08bd5b2405a2dc6d3e9f` — mgr: Mutex::Locker -> std::lock_guard
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Return whether the module reported itself capable of running.

### Invariants and contracts
- Acquires `lock` and returns `can_run`. (Established: `712ad57d09a2`)

### Error conditions
- None.

### Evolution summary
`948635a8b213` updated lock guard.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 181–183 lock mutex and return `can_run`.

---

## `PyModule::perf_counter_build(CephContext*)` — [`src/mgr/PyModule.cc:823`](../../../ceph/src/mgr/PyModule.cc:823); declaration [`src/mgr/PyModule.h:197`](../../../ceph/src/mgr/PyModule.h:197)

**Introduced:** `95a90f7da8a32dd2a5a1e3b381aaeacea378437b` — mgr: Add per-module performance counters to mgr
**Last modified:** `95a90f7da8a32dd2a5a1e3b381aaeacea378437b`
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Create and register per-module performance counters (`mgr_module_<name>`) in the CephContext performance counters collection.

### Invariants and contracts
- `perfcounter` must be uninitialized prior to call (`ceph_assert(perfcounter == nullptr)`). (Established: `95a90f7da8a3`)
- Registers counters from `l_pym_first` to `l_pym_last`: `notify_avg_usec`, `cmd_avg_usec`, `alive`, `cpu_usage`, `mem_rss_change`, `mem_rss_current`, `serve_cpu_usage`. (Established: `95a90f7da8a3`)
- Adds created counter group to `cct->get_perfcounters_collection()`. (Established: `95a90f7da8a3`)
- Returns 0. (Established: `95a90f7da8a3`)

### Error conditions
- Asserts if `perfcounter` is already non-null.

### Evolution summary
Introduced in `95a90f7da8a3`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 823–839 assert `perfcounter == nullptr`, build counters, register with `cct`, and return 0.

---

## `handle_pyerror(bool, std::string, std::string)` — [`src/mgr/PyModule.cc:67`](../../../ceph/src/mgr/PyModule.cc:67); declaration [`src/mgr/PyModule.h:32`](../../../ceph/src/mgr/PyModule.h:32)

**Introduced:** `6a8da7ca734726315c06929635c25dbb88599654` — mgr: load all modules (not just active ones)
**Last modified:** `18c4e08ccddde9710cded2df7e0becc2dde7e56c` — mgr: don't record a crash dump for NotImplementedError from dispatch_remote
**Change count:** 8 commits touched this function
**Divergence:** OK

### Intent
Extract and format the active Python exception into a printable string traceback using Python's `traceback` module, normalizing exceptions when needed. If `crash_dump` is true and `module` is non-empty, generate a crash dump structure with backtrace and metadata.

### Invariants and contracts
- Calls `PyErr_Fetch` and `PyErr_NormalizeException` to normalize unnormalized exception values into exception instances. (Established: `dee598087a37`)
- Catches formatting failures and falls back to string representation + `peek_pyerror()`. (Established: `072699d863e5`, `dee598087a37`)
- Generates crash dump ONLY when `crash_dump == true` and `!module.empty()`. (Established: `719d5e1836c9`, `18c4e08ccdd`)
- Strips trailing newlines from backtrace frame strings. (Established: `719d5e1836c9`)
- Includes full traceback lines including the last line for operator crash dumps. (Established: `1ecda507eb35`)

### Error conditions
- Fallback string formatting returned if Python traceback formatter raises an exception. (Established: `072699d863e5`)

### Evolution summary
`072699d863e5` added try/catch around traceback formatters. `dee598087a37` added `PyErr_NormalizeException` and fallback peek. `719d5e1836c9` added crash dump generation. `1ecda507eb35` restored last backtrace line. `18c4e08ccdd` conditioned crash dump on `crash_dump` parameter.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 67–140 implement exception extraction, normalization, formatted traceback assembly, conditional crash dump generation, and string extraction.

---

## `peek_pyerror()` — [`src/mgr/PyModule.cc:146`](../../../ceph/src/mgr/PyModule.cc:146); declaration [`src/mgr/PyModule.h:36`](../../../ceph/src/mgr/PyModule.h:36)

**Introduced:** `dee598087a37623238c35d7595348a4c674c43f3` — mgr/PyModule: fix missing tracebacks in handle_pyerror()
**Last modified:** `dee598087a37623238c35d7595348a4c674c43f3`
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Fetch and format the single-line string representation of the active Python exception without clearing or destroying the interpreter's exception state.

### Invariants and contracts
- Asserts that exception type and value are non-null (`ceph_assert(ptype); ceph_assert(pvalue);`). (Established: `dee598087a37`)
- Restores original exception state via `PyErr_Restore(ptype, pvalue, ptraceback)`. (Established: `dee598087a37`)

### Error conditions
- Asserts on missing exception state.

### Evolution summary
Introduced in `dee598087a37` as error debugging helper.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 146–158 fetch the error, extract its UTF-8 string, restore the error via `PyErr_Restore`, and return the string.

---

## `py_bytes_as_span(PyObject*)` — [`src/mgr/PyModule.cc:160`](../../../ceph/src/mgr/PyModule.cc:160); declaration [`src/mgr/PyModule.h:38`](../../../ceph/src/mgr/PyModule.h:38)

**Introduced:** `f69069e114ea8c785d6c27c57560a0b9bb8c16be` — mgr: serialize python objects sent between subinterpreters via remote
**Last modified:** `d3c8d3fc6566d3c909d36875d9ba05345fc90cb2` — crimson,mgr: mark assert-only variables [[maybe_unused]]
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Convert a Python bytes object into a non-owning `std::span<const std::byte>`.

### Invariants and contracts
- `bytes` must be non-null and an exact `PyBytes` instance (`assert(bytes); assert(PyBytes_CheckExact(bytes));`). (Established: `f69069e114ea`)
- `PyBytes_AsStringAndSize` must return 0. (Established: `f69069e114ea`)
- Returns non-owning span over the underlying bytes buffer. (Established: `f69069e114ea`)

### Error conditions
- Asserts on invalid input.

### Evolution summary
`d3c8d3fc6566` marked `int r` as `[[maybe_unused]]` for release builds.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 160–170 assert preconditions and return `std::span<const std::byte>`.

---

## `py_bytes_from_span(std::span<std::byte const>)` — [`src/mgr/PyModule.cc:172`](../../../ceph/src/mgr/PyModule.cc:172); declaration [`src/mgr/PyModule.h:39`](../../../ceph/src/mgr/PyModule.h:39)

**Introduced:** `f69069e114ea8c785d6c27c57560a0b9bb8c16be` — mgr: serialize python objects sent between subinterpreters via remote
**Last modified:** `f69069e114ea8c785d6c27c57560a0b9bb8c16be`
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Construct a new Python bytes object from a `std::span<const std::byte>`.

### Invariants and contracts
- Creates a Python bytes object matching span length and data. (Established: `f69069e114ea`)
- Asserts that allocation succeeded (`assert(ret)`). (Established: `f69069e114ea`)

### Error conditions
- Asserts on allocation failure.

### Evolution summary
Introduced in `f69069e114ea`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 172–178 call `PyBytes_FromStringAndSize` and assert result is non-null.

---

## `py_bytes_as_vec(PyObject*)` — [`src/mgr/PyModule.cc:180`](../../../ceph/src/mgr/PyModule.cc:180); declaration [`src/mgr/PyModule.h:41`](../../../ceph/src/mgr/PyModule.h:41)

**Introduced:** `f69069e114ea8c785d6c27c57560a0b9bb8c16be` — mgr: serialize python objects sent between subinterpreters via remote
**Last modified:** `d3c8d3fc6566d3c909d36875d9ba05345fc90cb2` — crimson,mgr: mark assert-only variables [[maybe_unused]]
**Change count:** 2 commits touched this function
**Divergence:** OK

### Intent
Copy data from a Python bytes object into a newly allocated `std::vector<std::byte>`.

### Invariants and contracts
- `bytes` must be non-null and exact `PyBytes` instance. (Established: `f69069e114ea`)
- Constructs owning vector copy of data. (Established: `f69069e114ea`)

### Error conditions
- Asserts on invalid input.

### Evolution summary
`d3c8d3fc6566` marked `r` as `[[maybe_unused]]`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 180–192 copy buffer contents into a `std::vector<std::byte>`.

---

## `py_bytes_from_vec(const std::vector<std::byte>&)` — [`src/mgr/PyModule.cc:194`](../../../ceph/src/mgr/PyModule.cc:194); declaration [`src/mgr/PyModule.h:42`](../../../ceph/src/mgr/PyModule.h:42)

**Introduced:** `f69069e114ea8c785d6c27c57560a0b9bb8c16be` — mgr: serialize python objects sent between subinterpreters via remote
**Last modified:** `f69069e114ea8c785d6c27c57560a0b9bb8c16be`
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Construct a new Python bytes object containing a copy of vector bytes.

### Invariants and contracts
- Creates a Python bytes object from vector data. (Established: `f69069e114ea`)
- Asserts non-null result (`assert(ret)`). (Established: `f69069e114ea`)

### Error conditions
- Asserts on allocation failure.

### Evolution summary
Introduced in `f69069e114ea`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 194–200 call `PyBytes_FromStringAndSize` and assert non-null.

---

## `log_write(PyObject*, PyObject*)` — [`src/mgr/PyModule.cc:204`](../../../ceph/src/mgr/PyModule.cc:204)

**Introduced:** `6a8da7ca734726315c06929635c25dbb88599654` — mgr: load all modules (not just active ones)
**Last modified:** `6a8da7ca734726315c06929635c25dbb88599654`
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
C-function implementation for `ceph_logger.write(msg)`: strips trailing newline and outputs message to `dout(4)`.

### Invariants and contracts
- Parses single string argument `"s"`. (Established: `6a8da7ca7347`)
- Strips trailing newline before logging. (Established: `6a8da7ca7347`)
- Emits to `dout(4)`. (Established: `6a8da7ca7347`)
- Returns `Py_None`. (Established: `6a8da7ca7347`)

### Error conditions
- None. Returns `Py_None` even if parse fails.

### Evolution summary
Unchanged since introduction in `6a8da7ca7347`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 204–214 parse `"s"`, strip newline, log at level 4, and return `Py_None`.

---

## `log_flush(PyObject*, PyObject*)` — [`src/mgr/PyModule.cc:216`](../../../ceph/src/mgr/PyModule.cc:216)

**Introduced:** `6a8da7ca734726315c06929635c25dbb88599654` — mgr: load all modules (not just active ones)
**Last modified:** `6a8da7ca734726315c06929635c25dbb88599654`
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
C-function implementation for `ceph_logger.flush()` no-op.

### Invariants and contracts
- Returns `Py_None`. (Established: `6a8da7ca7347`)

### Error conditions
- None.

### Evolution summary
Unchanged since introduction in `6a8da7ca7347`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 216–218 return `Py_None`.

---

## `PyModuleConfig::PyModuleConfig()` — [`src/mgr/PyModule.cc:235`](../../../ceph/src/mgr/PyModule.cc:235); declaration [`src/mgr/PyModule.h:207`](../../../ceph/src/mgr/PyModule.h:207)

**Introduced:** `37484af0b86083c02a7a506a0c9be02b3fd67b28` — mgr: rework kv store load path
**Last modified:** `37484af0b86083c02a7a506a0c9be02b3fd67b28`
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Default construct `PyModuleConfig` with an empty config map.

### Invariants and contracts
- Initializes empty `config` map. (Established: `37484af0b860`)

### Error conditions
- None.

### Evolution summary
Introduced in `37484af0b860`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Line 235 defaulted.

---

## `PyModuleConfig::PyModuleConfig(PyModuleConfig&)` — [`src/mgr/PyModule.cc:237`](../../../ceph/src/mgr/PyModule.cc:237); declaration [`src/mgr/PyModule.h:209`](../../../ceph/src/mgr/PyModule.h:209)

**Introduced:** `37484af0b86083c02a7a506a0c9be02b3fd67b28` — mgr: rework kv store load path
**Last modified:** `37484af0b86083c02a7a506a0c9be02b3fd67b28`
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Copy construct `PyModuleConfig` by copying the `config` key-value map.

### Invariants and contracts
- Copies `mconfig.config` without modifying the source or copying the mutex. (Established: `37484af0b860`)

### Error conditions
- None.

### Evolution summary
Introduced in `37484af0b860`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 237–239 initialize `config(mconfig.config)`. UNGROUNDED: Source `mconfig.lock` is not locked during copy; caller must ensure exclusive access.

---

## `PyModuleConfig::~PyModuleConfig()` — [`src/mgr/PyModule.cc:241`](../../../ceph/src/mgr/PyModule.cc:241); declaration [`src/mgr/PyModule.h:211`](../../../ceph/src/mgr/PyModule.h:211)

**Introduced:** `37484af0b86083c02a7a506a0c9be02b3fd67b28` — mgr: rework kv store load path
**Last modified:** `37484af0b86083c02a7a506a0c9be02b3fd67b28`
**Change count:** 1 commit touched this function
**Divergence:** OK

### Intent
Clean up `PyModuleConfig` instance.

### Invariants and contracts
- Default destruction of `config` map and `lock`. (Established: `37484af0b860`)

### Error conditions
- None.

### Evolution summary
Introduced in `37484af0b860`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Line 241 defaulted.

---

## `PyModuleConfig::set_config(MonClient*, const std::string&, const std::string&, const std::optional<std::string>&)` — [`src/mgr/PyModule.cc:244`](../../../ceph/src/mgr/PyModule.cc:244); declaration [`src/mgr/PyModule.h:213`](../../../ceph/src/mgr/PyModule.h:213)

**Introduced:** `37484af0b86083c02a7a506a0c9be02b3fd67b28` — mgr: rework kv store load path
**Last modified:** `a41b62bd85688bec566a7760cea95341bcb7a953` — mgr,mon: s/boost::optional/std::optional/
**Change count:** 6 commits touched this function
**Divergence:** OK

### Intent
Persist a module configuration change to the monitor via `config set mgr <global_key> <val>` or `config rm mgr <global_key>`. If monitor command succeeds, atomically update the local cached `config` map and return `{0, ""}`. If monitor command fails, leave local cache untouched, log failure, and return error pair `{set_cmd.r, set_cmd.outs}`.

### Invariants and contracts
- Global key format is `"mgr/" + module_name + "/" + key`. (Established: `37484af0b860`, `b0a4bff845be`)
- Constructs JSON command with `"who": "mgr"`, `"name": global_key`, and `"prefix": "config set"` (if `val` is present) or `"prefix": "config rm"` (if `val` is nullopt). (Established: `0520ff571cfb`)
- Local `config` map is updated under `lock` ONLY after `set_cmd.run` finishes with return code 0 (`set_cmd.r == 0`). (Established: `0520ff571cfb`)
- Returns `std::pair<int, std::string>{0, ""}` on success, or `{set_cmd.r, set_cmd.outs}` on monitor failure. (Established: `75bbe6863f5f`)

### Error conditions
- Returns non-zero return code and monitor output string if monitor rejects command. (Established: `75bbe6863f5f`)

### Evolution summary
`3bc9850e6f56` fixed prefix formatting. `0520ff571cfb` fixed "config rm" parameters and deferred local map update until after monitor success. `75bbe6863f5f` returned `{r, outs}` pair to caller. `b0a4bff845be` and `3bafb5e57168` updated key prefixes. `a41b62bd8568` migrated from `boost::optional` to `std::optional`.

### Deferred / known incomplete
None.

### Implementation critique
SATISFIES — Lines 244–288 format JSON command, run via `monc`, wait for reply, conditionally update `config` under lock on success, and return `{r, outs}`.

---

## Self-check & Verification Summary
- [x] Read all 49 non-merge commits in `commits.txt`.
- [x] Built list of all functions from `functions.txt`.
- [x] Scanned diffs and blame records for each function.
- [x] Critically evaluated current source lines against historical contracts.
- [x] Set `DIVERGED` only when an establishing commit and contradicting line are confirmed:
  - `PyModule::~PyModule()`: Establishing SHA `239b0dc8a9c4` (intended to call `Py_EndInterpreter` only for subinterpreters) contradicts line [`src/mgr/PyModule.cc:816`](../../../ceph/src/mgr/PyModule.cc:816) (`if (use_main_interpreter)`).
- [x] Flagged UNGROUNDED cases (unlocked copies/setters).
- [x] Verified and cited specific line numbers for all functions.
