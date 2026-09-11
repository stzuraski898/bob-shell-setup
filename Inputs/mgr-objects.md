# ceph-mgr Object Inventory

Reference list of all C++ classes in `src/mgr/` for use by curator and test-writing
agents. Each entry records the source files, a description, implementation size, test
coverage status, and whether a git history artefact has been curated.

**Test status key**
- `covered` — a `test_<name>.cc` exists in `src/test/mgr/`
- `in-progress` — a `wip-sz-*` branch exists with active test work (see tracker)
- `none` — no test file exists yet

**History curated key**
- `yes` — `BobOutput/git-history/<ClassName>.md` exists and has passed its self-check
- `no` — history artefact not yet generated; run the curator task before writing tests

---

## Core daemon communication

### `DaemonServer`
| Field | Value |
|---|---|
| Header | `src/mgr/DaemonServer.h` |
| Source | `src/mgr/DaemonServer.cc` (~3867 lines) |
| Description | The central message-dispatch server inside ceph-mgr. Handles `MMgrReport`, `MMgrOpen`, `MMgrUpdate`, and `MMgrClose` messages from all connected daemons (OSDs, MDSs, etc.). Owns the `DaemonStateIndex` and routes perf counter updates and health metric reports. |
| Test status | `in-progress` — tracker [#80176](https://tracker.ceph.com/issues/80176) |
| History curated | `no` |

### `MgrClient`
| Field | Value |
|---|---|
| Header | `src/mgr/MgrClient.h` |
| Source | `src/mgr/MgrClient.cc` (~664 lines) |
| Description | Client-side stub used by non-mgr daemons (OSDs, MDSs, MONs) to connect to the active mgr. Sends `MMgrOpen` on startup, streams `MMgrReport` perf-counter updates, and handles `MMgrConfigure` to negotiate which counters to report. |
| Test status | `in-progress` — tracker [#77535](https://tracker.ceph.com/issues/77535) |
| History curated | `no` |

### `MgrSession`
| Field | Value |
|---|---|
| Header | `src/mgr/MgrSession.h` |
| Source | `src/mgr/MgrSession.cc` (header-only, no .cc) |
| Description | Session state associated with an active Connection inside `DaemonServer`. Stores the authenticated entity name, caps, and the set of subscribed perf counter schema keys. |
| Test status | `none` |
| History curated | `no` |

### `MgrOpRequest`
| Field | Value |
|---|---|
| Header | `src/mgr/MgrOpRequest.h` |
| Source | `src/mgr/MgrOpRequest.cc` (~132 lines) |
| Description | Wraps an in-flight operation request in the mgr, tracking timing and state for latency accounting and op-tracking display. |
| Test status | `none` |
| History curated | `no` |

---

## Daemon state

### `DaemonState`
| Field | Value |
|---|---|
| Header | `src/mgr/DaemonState.h` |
| Source | `src/mgr/DaemonState.cc` (~387 lines) |
| Description | Stores the live state of one connected daemon: perf counter schema + values, health metrics, last-seen time, and metadata (e.g. version, hostname). |
| Test status | `covered` — `src/test/mgr/test_daemonstate.cc` |
| History curated | `no` |

### `DaemonStateIndex`
| Field | Value |
|---|---|
| Header | `src/mgr/DaemonState.h` (same file as `DaemonState`) |
| Source | `src/mgr/DaemonState.cc` (~387 lines) |
| Description | Thread-safe index over all `DaemonState` objects, keyed by `DaemonKey`. Provides lookup, insertion, removal, and bulk iteration used by `DaemonServer` and Python modules. |
| Test status | `covered` — `src/test/mgr/test_daemonstate.cc` |
| History curated | `no` |

### `DaemonKey`
| Field | Value |
|---|---|
| Header | `src/mgr/DaemonKey.h` |
| Source | `src/mgr/DaemonKey.cc` (~37 lines) |
| Description | Unique identifier for a daemon within the cluster: a `(type, id)` pair (e.g. `("osd", "0")`). Used as the map key in `DaemonStateIndex`. |
| Test status | `in-progress` — tracker [#80175](https://tracker.ceph.com/issues/80175) |
| History curated | `no` |

### `DaemonPerfCounters`
| Field | Value |
|---|---|
| Header | `src/mgr/DaemonPerfCounters.h` |
| Source | `src/mgr/DaemonPerfCounters.cc` (~86 lines) |
| Description | Holds the perf counter schema (types/names) and current values for one daemon, as reported via `MMgrReport`. Provides encode/decode for the schema and value payloads. |
| Test status | `none` |
| History curated | `no` |

### `DaemonHealthMetric`
| Field | Value |
|---|---|
| Header | `src/mgr/DaemonHealthMetric.h` |
| Source | `src/mgr/DaemonHealthMetric.cc` (~27 lines) |
| Description | A single health metric emitted by a daemon (e.g. slow ops, scrub errors). Carries a code, summary string, and severity. Encoded into `MMgrReport`. |
| Test status | `none` |
| History curated | `no` |

### `DaemonHealthMetricCollector`
| Field | Value |
|---|---|
| Header | `src/mgr/DaemonHealthMetricCollector.h` |
| Source | `src/mgr/DaemonHealthMetricCollector.cc` (~109 lines) |
| Description | Aggregates `DaemonHealthMetric` objects across all daemons into cluster-level health checks. Used by the active mgr to synthesise the `HEALTH_*` output seen by operators. |
| Test status | `none` |
| History curated | `no` |

---

## Cluster state

### `ClusterState`
| Field | Value |
|---|---|
| Header | `src/mgr/ClusterState.h` |
| Source | `src/mgr/ClusterState.cc` (~387 lines) |
| Description | Caches cluster-scope maps (OSDMap, PGMap, MgrMap, FSMap, ServiceMap) received from the monitors via `MMonMgrReport` and `MMgrDigest`. Provides locked access to these maps for Python modules and other mgr subsystems. |
| Test status | `covered` — `src/test/mgr/test_clusterstate.cc` |
| History curated | `no` |

### `ServiceMap`
| Field | Value |
|---|---|
| Header | `src/mgr/ServiceMap.h` |
| Source | `src/mgr/ServiceMap.cc` (~250 lines) |
| Description | Encodes and decodes the cluster's service map — a registry of active daemon services (e.g. RGW, RBD mirror) with their metadata, endpoints, and last-seen epochs. Distributed from the monitor to mgr via `MServiceMap`. |
| Test status | `in-progress` — tracker [#80174](https://tracker.ceph.com/issues/80174) |
| History curated | `no` |

---

## Python module infrastructure

### `ActivePyModules`
| Field | Value |
|---|---|
| Header | `src/mgr/ActivePyModules.h` |
| Source | `src/mgr/ActivePyModules.cc` (~1821 lines) |
| Description | Lifecycle manager for all Python mgr modules running in the active mgr. Starts and stops module threads, dispatches commands, health checks, and notify callbacks, and provides the C→Python upcall interface used by `DaemonServer`. |
| Test status | `in-progress` — tracker [#76261](https://tracker.ceph.com/issues/76261) |
| History curated | `no` |

### `ActivePyModule`
| Field | Value |
|---|---|
| Header | `src/mgr/ActivePyModule.h` |
| Source | `src/mgr/ActivePyModule.cc` (~339 lines) |
| Description | Represents one running Python module instance inside the active mgr. Owns the module's thread (via `PyModuleRunner`), dispatches commands and notify events into Python, and collects the module's health checks. |
| Test status | `none` |
| History curated | `no` |

### `PyModule`
| Field | Value |
|---|---|
| Header | `src/mgr/PyModule.h` |
| Source | `src/mgr/PyModule.cc` (~812 lines) |
| Description | Loads and introspects a Python module file on disk. Parses `COMMANDS`, `OPTIONS`, and module metadata. Shared between the active and standby mgr instances to avoid re-importing on failover. |
| Test status | `none` |
| History curated | `no` |

### `PyModuleRegistry`
| Field | Value |
|---|---|
| Header | `src/mgr/PyModuleRegistry.h` |
| Source | `src/mgr/PyModuleRegistry.cc` (~516 lines) |
| Description | Owns all `PyModule` instances for the lifetime of the mgr process. Sets up the Python runtime environment, discovers modules from the configured path, and hands them off to `ActivePyModules` or `StandbyPyModules` on role transitions. |
| Test status | `none` |
| History curated | `no` |

### `PyModuleRunner`
| Field | Value |
|---|---|
| Header | `src/mgr/PyModuleRunner.h` |
| Source | `src/mgr/PyModuleRunner.cc` (~120 lines) |
| Description | Base class that calls `serve()` on a Python module in a dedicated C++ thread, handling GIL acquisition, thread startup/shutdown, and crash detection. Subclassed by `ActivePyModule` and `StandbyPyModule`. |
| Test status | `none` |
| History curated | `no` |

### `StandbyPyModules`
| Field | Value |
|---|---|
| Header | `src/mgr/StandbyPyModules.h` |
| Source | `src/mgr/StandbyPyModules.cc` (~201 lines) |
| Description | Runs a reduced set of Python modules in standby mgr instances (those not currently active). Modules run `standby_tick()` instead of `serve()` so they remain warm for fast failover. |
| Test status | `none` |
| History curated | `no` |

### `PyFormatter`
| Field | Value |
|---|---|
| Header | `src/mgr/PyFormatter.h` |
| Source | `src/mgr/PyFormatter.cc` (~140 lines) |
| Description | Implementation of `ceph::Formatter` that writes output into a Python dict/list tree rather than a text stream. Used to pass structured data from C++ into Python module callbacks. |
| Test status | `covered` — `src/test/mgr/test_pyformatter.cc` |
| History curated | `no` |

### `Gil`
| Field | Value |
|---|---|
| Header | `src/mgr/Gil.h` |
| Source | `src/mgr/Gil.cc` (~140 lines) |
| Description | RAII wrapper for acquiring and releasing the CPython Global Interpreter Lock (GIL). Required before any C→Python call. `SafeThreadState` manages per-thread state for threads that did not originate from Python. |
| Test status | `none` |
| History curated | `no` |

---

## Capability and access control

### `MgrCap`
| Field | Value |
|---|---|
| Header | `src/mgr/MgrCap.h` |
| Source | `src/mgr/MgrCap.cc` (~583 lines) |
| Description | Parses and evaluates mgr capability strings (e.g. `profile rbd`). Determines whether an authenticated entity is permitted to execute a given mgr command. |
| Test status | `covered` — `src/test/mgr/test_mgrcap.cc` |
| History curated | `no` |

---

## Performance metrics

### `PerfCounterInstance`
| Field | Value |
|---|---|
| Header | `src/mgr/PerfCounterInstance.h` |
| Source | `src/mgr/PerfCounterInstance.cc` (~25 lines) |
| Description | Stores the current value and history of a single perf counter for one daemon. Tracks both instantaneous values and ring-buffer averages. |
| Test status | `none` |
| History curated | `no` |

### `MetricCollector`
| Field | Value |
|---|---|
| Header | `src/mgr/MetricCollector.h` |
| Source | `src/mgr/MetricCollector.cc` (~191 lines) |
| Description | Template base class for OSD and MDS perf metric collectors. Manages active queries, processes incoming metric reports, and dispatches results to registered listeners. |
| Test status | `none` |
| History curated | `no` |

### `OSDPerfMetricCollector`
| Field | Value |
|---|---|
| Header | `src/mgr/OSDPerfMetricCollector.h` |
| Source | `src/mgr/OSDPerfMetricCollector.cc` (~39 lines) |
| Description | Specialisation of `MetricCollector` for OSD performance queries. Registers queries with OSDs, receives histogram data from `MMgrReport`, and forwards to Python modules. |
| Test status | `none` |
| History curated | `no` |

### `MDSPerfMetricCollector`
| Field | Value |
|---|---|
| Header | `src/mgr/MDSPerfMetricCollector.h` |
| Source | `src/mgr/MDSPerfMetricCollector.cc` (~64 lines) |
| Description | Specialisation of `MetricCollector` for MDS performance queries. Same role as `OSDPerfMetricCollector` but for MDS latency/throughput histograms. |
| Test status | `none` |
| History curated | `no` |

---

## Mgr lifecycle

### `Mgr`
| Field | Value |
|---|---|
| Header | `src/mgr/Mgr.h` |
| Source | `src/mgr/Mgr.cc` (~868 lines) |
| Description | The active mgr process object. Orchestrates startup: initialises `ClusterState`, `DaemonServer`, `ActivePyModules`, connects to monitors, and drives the main tick loop. |
| Test status | `none` |
| History curated | `no` |

### `MgrStandby`
| Field | Value |
|---|---|
| Header | `src/mgr/MgrStandby.h` |
| Source | `src/mgr/MgrStandby.cc` (~513 lines) |
| Description | The standby mgr process object. Monitors the MgrMap for an active→standby transition, runs `StandbyPyModules`, and triggers a role switch when this instance is elected active. |
| Test status | `none` |
| History curated | `no` |

### `ThreadMonitor`
| Field | Value |
|---|---|
| Header | `src/mgr/ThreadMonitor.h` |
| Source | `src/mgr/ThreadMonitor.cc` (~250 lines) |
| Description | Monitors registered C++ threads for liveness and responsiveness. Detects hung threads (those that have not checked in within a configurable deadline) and emits health warnings. Implements `md_config_obs_t` to react to config changes at runtime. |
| Test status | `none` |
| History curated | `no` |

---

## Cache

### `MgrMapCache`
| Field | Value |
|---|---|
| Header | `src/mgr/MgrMapCache.h` |
| Source | `src/mgr/MgrMapCache.cc` (~237 lines) |
| Description | LFU (Least Frequently Used) cache for decoded MgrMap objects, with a `PyObject*` specialisation for the Python-facing path. Avoids repeated deserialization of the same map epoch. |
| Test status | `covered` — `src/test/mgr/test_mgrmapcache.cc` |
| History curated | `no` |

---

## Summary table

| Class | Source lines | Test status | History curated | Tracker |
|---|---|---|---|---|
| `ActivePyModule` | ~339 | none | `no` | — |
| `ActivePyModules` | ~1821 | in-progress | `no` | [#76261](https://tracker.ceph.com/issues/76261) |
| `ClusterState` | ~387 | covered | `no` | — |
| `DaemonHealthMetric` | ~27 | none | `no` | — |
| `DaemonHealthMetricCollector` | ~109 | none | `no` | — |
| `DaemonKey` | ~37 | in-progress | `no` | [#80175](https://tracker.ceph.com/issues/80175) |
| `DaemonPerfCounters` | ~86 | none | `no` | — |
| `DaemonServer` | ~3867 | in-progress | `no` | [#80176](https://tracker.ceph.com/issues/80176) |
| `DaemonState` | ~387 | covered | `no` | — |
| `DaemonStateIndex` | (in DaemonState.cc) | covered | `no` | — |
| `Gil` | ~140 | none | `no` | — |
| `MDSPerfMetricCollector` | ~64 | none | `no` | — |
| `MetricCollector` | ~191 | none | `no` | — |
| `MgrCap` | ~583 | covered | `no` | — |
| `MgrClient` | ~664 | in-progress | `no` | [#77535](https://tracker.ceph.com/issues/77535) |
| `MgrMapCache` | ~237 | covered | `no` | — |
| `MgrOpRequest` | ~132 | none | `no` | — |
| `MgrSession` | header-only | none | `no` | — |
| `MgrStandby` | ~513 | none | `no` | — |
| `Mgr` | ~868 | none | `no` | — |
| `OSDPerfMetricCollector` | ~39 | none | `no` | — |
| `PerfCounterInstance` | ~25 | none | `no` | — |
| `PyFormatter` | ~140 | covered | `no` | — |
| `PyModule` | ~812 | none | `no` | — |
| `PyModuleRegistry` | ~516 | none | `no` | — |
| `PyModuleRunner` | ~120 | none | `no` | — |
| `ServiceMap` | ~250 | in-progress | `no` | [#80174](https://tracker.ceph.com/issues/80174) |
| `StandbyPyModules` | ~201 | none | `no` | — |
| `ThreadMonitor` | ~250 | none | `no` | — |
