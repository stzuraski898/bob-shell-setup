# Whiteboard Defense Prompt Guide

A prompt template and engineering guide for generating **Whiteboard Defense** documentation for changes, scripts, modules, refactorings, and customer-facing components authored or modified by Bob (AI coding agents).

---

## 1. Philosophy & Purpose

### The "Whiteboard Defense" Standard

> **The Benchmark for Responsible AI Usage:**
> *"I should be able to pull you aside at any moment and ask you to explain any customer-facing system you've shipped. You should be able to clearly explain how it works and defend the decisions you made."*

When shipping customer-facing work, developers cannot ship code they do not understand at a high architectural and operational level.

- **What is NOT expected:** Line-by-line memorization of code, exact internal variable names, or walls of narrative text/essay fluff.
- **What IS expected:** Crisp, human-readable, scannable, and to-the-point answers covering:
  1. *"Why did you do X instead of Y?"* (Trade-offs & Alternatives Considered in clean comparison tables)
  2. *"What data structures and concurrency primitives did you use here and why?"* (Explicit container names, complexity, memory profile, invariants)
  3. *"What happens if this actor behaves maliciously or unpredictably?"* (Security threat matrix, input validation, boundaries)
  4. *"Where does this fail, degrade, or bottleneck?"* (Failure modes, edge cases, blast radius, actionable triage checklist)

---

## 2. Output Location and File Naming Conventions

All Whiteboard Defense artefacts must be written to:

```
Outputs/WhiteboardDefense/<ITEM_NAME>/whiteboard-defense-<shortdesc>.html
```

### Examples:
- Target item `query_ceph_tracker.py`:
  `Outputs/WhiteboardDefense/query_ceph_tracker/whiteboard-defense-tracker-search-tool.html`
- Target item `DaemonServer`:
  `Outputs/WhiteboardDefense/DaemonServer/whiteboard-defense-connection-routing.html`
- Target item `ThreadMonitor`:
  `Outputs/WhiteboardDefense/ThreadMonitor/whiteboard-defense-thread-hang-detector.html`

---

## 3. Whiteboard Defense Document Schema

Every generated Whiteboard Defense markdown document must follow this standardized schema:

```markdown
# Whiteboard Defense: <Item Name / Component>

**Author / Maintainer:** Bob (AI Engineer)
**Target File / Subsystem:** `<path/to/file_or_module>`
**Context / Scope:** Production / Customer-Facing | Internal Tooling | Core Subsystem

---

## 1. High-Level Architecture & Mental Model
*How does this work in 2-3 minutes at a whiteboard? Include a simple diagram or flowchart.*

- **Core Responsibility:** (1-2 sentences on what this system does)
- **Mental Model:** (Analogy or conceptual explanation)
- **Data Flow / Control Flow:**
  - Ingress / Triggers
  - Processing / Transformations
  - State Transitions / Output

---

## 2. Architectural Decisions & Trade-offs ("Why X instead of Y?")

| Decision / Choice Made (X) | Rejected Alternative (Y) | Justification & Trade-off Defense |
|---|---|---|
| *e.g., SQLite in-memory cache* | *Direct disk scan per query* | *O(1) lookups vs O(N) I/O bottleneck; accepts startup indexing cost for interactive responsiveness.* |
| *e.g., Mutex over Lockless Ring* | *Atomic CAS lock-free queue* | *Contention frequency is low; simpler lock semantics prevent subtle memory-ordering bugs on multi-arch.* |

---

## 3. Data Structures, Algorithms & Invariants

- **Key Data Structures:** What containers/structs were chosen and why (complexity, memory footprint, cache locality).
- **Core Invariants:** What state guarantees must ALWAYS hold true across operations.
- **Concurrency & Synchronization:** Lock ordering, re-entrancy, thread safety boundaries, or async task models.

---

## 4. Threat Model & Adversarial Handling ("What if an actor behaves maliciously?")

- **Malicious / Unpredictable Actor Inputs:**
  - How malformed inputs, oversized payloads, injection attacks, or corrupt state streams are handled.
- **Trust Boundaries:**
  - Where inputs are sanitized and validated vs where internal trust is assumed.
- **Defensive Safeguards:**
  - Rate limiting, bounded buffers, timeouts, privilege separation, and non-root execution constraints.

---

## 5. Failure Modes, Edge Cases & Blast Radius ("Where does this fail?")

- **Known Failure Points:**
  - Network timeouts / unreachable remotes
  - Memory exhaustion / resource constraints
  - Disk / filesystem corruption
  - Partial writes / interrupted operations
- **Degradation & Recovery Strategy:**
  - Fail-safe vs fail-secure behavior
  - Retry policies with exponential backoff / jitter
  - Crash recovery & state reconciliation
- **Blast Radius:**
  - Does a crash here bring down the entire daemon/cluster, or is it isolated to a worker/session?

---

## 6. Observability, Metrics & Triage Playbook

- **Key Metrics / Health Indicators:** Logs, counters, and traces emitted.
- **Triage Checklist:** 3 questions to ask immediately when debugging this system in production.
```

---

## 4. Reusable Bob Agent Prompt Template & Multi-Agent Orchestration

### Prompt File Layout (One File Per Item)

Prompts are split into two subfolders by target type:

```
Inputs/Prompts/whiteboard-defense/scripts/        ← repo scripts & tooling
Inputs/Prompts/whiteboard-defense/mgr-objects/    ← Ceph src/mgr/ C++ classes
```

Within each subfolder files are zero-padded and numbered sequentially from `01`:

```
scripts/01-query_ceph_tracker_py.md
scripts/02-query_ceph_tracker_sh.md
...
mgr-objects/01-ActivePyModule.md
mgr-objects/02-ActivePyModules.md
...
```

- Each file begins with YAML frontmatter: `tracker: none` (or a tracker URL if one exists).
- The prompt body starts immediately after the frontmatter — no enclosing markdown fences.

### Multi-Agent Orchestration & No-Worktree Execution

Because Whiteboard Defense analysis is a **read-only documentation generation task** that writes standalone HTML artifacts without compiling code, checking out branches, or running test suites, it does not require isolated Git worktrees.

Launch a specific suite across concurrent agent sessions using:
```bash
# Repo scripts
./launch-bob-agents.sh --local --no-worktrees --instructions Inputs/Prompts/whiteboard-defense/scripts/

# Ceph mgr objects
./launch-bob-agents.sh --local --no-worktrees --instructions Inputs/Prompts/whiteboard-defense/mgr-objects/
```

### Standard Prompt Template (Per File)

**File:** `Inputs/Prompts/whiteboard-defense/<NN>-<ItemName>.md`

```markdown
---
tracker: none
---
You are tasked with generating a comprehensive Whiteboard Defense document for: `<ITEM_NAME>` (`<PATH_TO_FILES_OR_CHANGES>`).

### Standard & Context
The Whiteboard Defense standard:
"I should be able to pull you aside at any moment and ask you to explain any customer-facing system you've shipped. You should be able to clearly explain how it works and defend the decisions you made.
I don't expect line-level familiarity with the code. I don't care if you remember the exact function name or implementation detail.
But if I ask:
1. 'Why did you do X instead of Y?'
2. 'What happens if this actor behaves maliciously or unexpectedly?'
3. 'What data structure did you use here and why?'
4. 'Where does this fail or bottleneck?'
You must be able to answer confidently and defensively."

### Instructions:
1. Read the target files, implementation diffs, and context around `<ITEM_NAME>`.
2. Analyze the system architecture, design decisions, failure boundaries, and security considerations.
3. Write a concise, scannable, to-the-point Whiteboard Defense HTML document to:
   `Outputs/WhiteboardDefense/<ITEM_NAME>/whiteboard-defense-<shortdesc>.html`
4. Strict Tone & Formatting Directives:
   - **Self-Contained HTML Document:** Single HTML document with clean inline CSS, high-contrast tables, clear typography, and optional ASCII or Mermaid JS/SVG diagrams.
   - **Concise & Punchy:** Avoid fluff, walls of narrative text, or generic essay prose. Use bullet points and tight phrasing.
   - **Technical Precision:** Explicitly state the exact data structures, complexity ($O(1)$, $O(N)$), invariants, and design choices.
   - **Human-Readable:** Format tables and lists for quick whiteboard recall and fast technical triage.
5. Follow the standard Whiteboard Defense Schema:
   - High-Level Architecture & Mental Model (with flow diagram)
   - Architectural Decisions & Trade-offs ("Why X instead of Y?" table)
   - Data Structures, Algorithms & Invariants
   - Threat Model & Adversarial Handling ("What if an actor behaves maliciously?")
   - Failure Modes, Edge Cases & Blast Radius ("Where does this fail?")
   - Observability & Triage Playbook
6. Do not invent details — ground your defense entirely in the actual codebase, invariants, and architectural constraints.
```
