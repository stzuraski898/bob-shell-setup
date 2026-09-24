# Whiteboard Defense Prompts for Repository Scripts

This document aggregates standardized Bob AI prompts to generate comprehensive, human-readable, and concise **Whiteboard Defense** HTML documents for every script in this repository, structured according to [`Inputs/whiteboard-defense-prompt-guide.md`](Inputs/whiteboard-defense-prompt-guide.md:1).

Outputs are written as standalone HTML files to: `Outputs/WhiteboardDefense/<ITEM_NAME>/whiteboard-defense-<shortdesc>.html`

---

## 1. `scripts/query_ceph_tracker.py`

```markdown
You are tasked with generating a comprehensive Whiteboard Defense document for: `query_ceph_tracker.py` (`scripts/query_ceph_tracker.py`).

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
1. Read `scripts/query_ceph_tracker.py` and analyze its search query logic, Redmine API querying, HTML generation, and issue deduplication.
2. Analyze the system architecture, design decisions, failure boundaries, and security considerations.
3. Write a concise, scannable, to-the-point Whiteboard Defense HTML document to:
   `Outputs/WhiteboardDefense/query_ceph_tracker/whiteboard-defense-tracker-search-tool.html`
4. Strict Tone & Formatting Directives:
   - **Self-Contained HTML Document:** Single HTML document with clean inline CSS, high-contrast tables, clear typography, and optional ASCII or Mermaid JS/SVG diagrams.
   - **Concise & Punchy:** Avoid fluff, walls of narrative text, or generic essay prose. Use bullet points and tight phrasing.
   - **Technical Precision:** Explicitly state the exact data structures (e.g. `seen: dict[int, dict]`), algorithms ($O(1)$ hashing, regex Textile transpilation), invariants, and design choices.
   - **Human-Readable:** Format tables and lists for quick whiteboard recall and fast technical triage.
5. Follow the standard Whiteboard Defense Schema:
   - High-Level Architecture & Mental Model (with flow diagram)
   - Architectural Decisions & Trade-offs ("Why X instead of Y?" table)
   - Data Structures, Algorithms & Invariants
   - Threat Model & Adversarial Handling ("What if an actor behaves maliciously?" table)
   - Failure Modes, Edge Cases & Blast Radius ("Where does this fail?")
   - Observability & Triage Playbook
6. Do not invent details — ground your defense entirely in the actual codebase, invariants, and architectural constraints.
```

---

## 2. `scripts/query_ceph_tracker.sh`

```markdown
You are tasked with generating a comprehensive Whiteboard Defense document for: `query_ceph_tracker.sh` (`scripts/query_ceph_tracker.sh`).

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
1. Read `scripts/query_ceph_tracker.sh` and note how it handles CLI execution, argument forwarding (`"$@"`), Python interpreter resolution, and environment variable propagation.
2. Analyze the system architecture, design decisions, failure boundaries, and security considerations.
3. Write a concise, scannable, to-the-point Whiteboard Defense HTML document to:
   `Outputs/WhiteboardDefense/query_ceph_tracker_sh/whiteboard-defense-tracker-shell-wrapper.html`
4. Strict Tone & Formatting Directives:
   - **Self-Contained HTML Document:** Single HTML document with clean inline CSS, high-contrast tables, clear typography, and optional ASCII or Mermaid JS/SVG diagrams.
   - **Concise & Punchy:** Avoid fluff, walls of narrative text, or generic essay prose. Use bullet points and tight phrasing.
   - **Technical Precision:** Explicitly state process models, argument forwarding mechanics, invariants, and design choices.
   - **Human-Readable:** Format tables and lists for quick whiteboard recall and fast technical triage.
5. Follow the standard Whiteboard Defense Schema:
   - High-Level Architecture & Mental Model (with flow diagram)
   - Architectural Decisions & Trade-offs ("Why X instead of Y?" table)
   - Data Structures, Algorithms & Invariants
   - Threat Model & Adversarial Handling ("What if an actor behaves maliciously?" table)
   - Failure Modes, Edge Cases & Blast Radius ("Where does this fail?")
   - Observability & Triage Playbook
6. Do not invent details — ground your defense entirely in the actual codebase, invariants, and architectural constraints.
```

---

## 3. `collect-object-history-v4.sh`

```markdown
You are tasked with generating a comprehensive Whiteboard Defense document for: `collect-object-history-v4.sh` (`collect-object-history-v4.sh`).

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
1. Read `collect-object-history-v4.sh` and examine its rename-aware git history extraction pipeline (`git log --follow --name-status`), ctags invocation, scoped diff extraction, and filesystem layout.
2. Analyze the system architecture, design decisions, failure boundaries, and security considerations.
3. Write a concise, scannable, to-the-point Whiteboard Defense HTML document to:
   `Outputs/WhiteboardDefense/collect_object_history_v4/whiteboard-defense-rename-aware-history-collector.html`
4. Strict Tone & Formatting Directives:
   - **Self-Contained HTML Document:** Single HTML document with clean inline CSS, high-contrast tables, clear typography, and optional ASCII or Mermaid JS/SVG diagrams.
   - **Concise & Punchy:** Avoid fluff, walls of narrative text, or generic essay prose. Use bullet points and tight phrasing.
   - **Technical Precision:** Explicitly state data structures (associative arrays, commit queues), algorithmic steps ($O(N)$ commit traversal), invariants, and design choices.
   - **Human-Readable:** Format tables and lists for quick whiteboard recall and fast technical triage.
5. Follow the standard Whiteboard Defense Schema:
   - High-Level Architecture & Mental Model (with flow diagram)
   - Architectural Decisions & Trade-offs ("Why X instead of Y?" table)
   - Data Structures, Algorithms & Invariants
   - Threat Model & Adversarial Handling ("What if an actor behaves maliciously?" table)
   - Failure Modes, Edge Cases & Blast Radius ("Where does this fail?")
   - Observability & Triage Playbook
6. Do not invent details — ground your defense entirely in the actual codebase, invariants, and architectural constraints.
```

---

## 4. `launch-bob-agents.sh`

```markdown
You are tasked with generating a comprehensive Whiteboard Defense document for: `launch-bob-agents.sh` (`launch-bob-agents.sh`).

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
1. Read `launch-bob-agents.sh` and examine its Tilix multi-tab orchestration, local vs SSH remote modes, worktree management (`--no-worktrees`), dry-run introspection, credential injection (`BOBSHELL_API_KEY`), and instruction parsing.
2. Analyze the system architecture, design decisions, failure boundaries, and security considerations.
3. Write a concise, scannable, to-the-point Whiteboard Defense HTML document to:
   `Outputs/WhiteboardDefense/launch_bob_agents/whiteboard-defense-agent-worktree-orchestrator.html`
4. Strict Tone & Formatting Directives:
   - **Self-Contained HTML Document:** Single HTML document with clean inline CSS, high-contrast tables, clear typography, and optional ASCII or Mermaid JS/SVG diagrams.
   - **Concise & Punchy:** Avoid fluff, walls of narrative text, or generic essay prose. Use bullet points and tight phrasing.
   - **Technical Precision:** Explicitly state data structures (parallel bash arrays), process orchestration primitives (DBus/Tilix), invariants, and design choices.
   - **Human-Readable:** Format tables and lists for quick whiteboard recall and fast technical triage.
5. Follow the standard Whiteboard Defense Schema:
   - High-Level Architecture & Mental Model (with flow diagram)
   - Architectural Decisions & Trade-offs ("Why X instead of Y?" table)
   - Data Structures, Algorithms & Invariants
   - Threat Model & Adversarial Handling ("What if an actor behaves maliciously?" table)
   - Failure Modes, Edge Cases & Blast Radius ("Where does this fail?")
   - Observability & Triage Playbook
6. Do not invent details — ground your defense entirely in the actual codebase, invariants, and architectural constraints.
```

---

## 5. `ceph-tracker-issues.sh`

```markdown
You are tasked with generating a comprehensive Whiteboard Defense document for: `ceph-tracker-issues.sh` (`ceph-tracker-issues.sh`).

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
1. Read `ceph-tracker-issues.sh` and examine its API authentication mechanisms (API key vs basic auth fallback), curl querying with TLS 1.2 enforcement, jq filtering, HTML report rendering, and browser launching.
2. Analyze the system architecture, design decisions, failure boundaries, and security considerations.
3. Write a concise, scannable, to-the-point Whiteboard Defense HTML document to:
   `Outputs/WhiteboardDefense/ceph_tracker_issues/whiteboard-defense-user-assigned-issues-fetcher.html`
4. Strict Tone & Formatting Directives:
   - **Self-Contained HTML Document:** Single HTML document with clean inline CSS, high-contrast tables, clear typography, and optional ASCII or Mermaid JS/SVG diagrams.
   - **Concise & Punchy:** Avoid fluff, walls of narrative text, or generic essay prose. Use bullet points and tight phrasing.
   - **Technical Precision:** Explicitly state data structures (JSON objects, bash arrays), jq transformations, invariants, and design choices.
   - **Human-Readable:** Format tables and lists for quick whiteboard recall and fast technical triage.
5. Follow the standard Whiteboard Defense Schema:
   - High-Level Architecture & Mental Model (with flow diagram)
   - Architectural Decisions & Trade-offs ("Why X instead of Y?" table)
   - Data Structures, Algorithms & Invariants
   - Threat Model & Adversarial Handling ("What if an actor behaves maliciously?" table)
   - Failure Modes, Edge Cases & Blast Radius ("Where does this fail?")
   - Observability & Triage Playbook
6. Do not invent details — ground your defense entirely in the actual codebase, invariants, and architectural constraints.
```

---

## 6. `get-object-history.sh`

```markdown
You are tasked with generating a comprehensive Whiteboard Defense document for: `get-object-history.sh` (`get-object-history.sh`).

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
1. Read `get-object-history.sh` and examine its on-demand lazy fetching of object history archives over SSH/SCP, local cache inspection, temporary directory lifecycle management (`trap`), and per-method / signal filtering.
2. Analyze the system architecture, design decisions, failure boundaries, and security considerations.
3. Write a concise, scannable, to-the-point Whiteboard Defense HTML document to:
   `Outputs/WhiteboardDefense/get_object_history/whiteboard-defense-lazy-history-fetcher.html`
4. Strict Tone & Formatting Directives:
   - **Self-Contained HTML Document:** Single HTML document with clean inline CSS, high-contrast tables, clear typography, and optional ASCII or Mermaid JS/SVG diagrams.
   - **Concise & Punchy:** Avoid fluff, walls of narrative text, or generic essay prose. Use bullet points and tight phrasing.
   - **Technical Precision:** Explicitly state caching mechanisms, cleanup handlers, invariants, and design choices.
   - **Human-Readable:** Format tables and lists for quick whiteboard recall and fast technical triage.
5. Follow the standard Whiteboard Defense Schema:
   - High-Level Architecture & Mental Model (with flow diagram)
   - Architectural Decisions & Trade-offs ("Why X instead of Y?" table)
   - Data Structures, Algorithms & Invariants
   - Threat Model & Adversarial Handling ("What if an actor behaves maliciously?" table)
   - Failure Modes, Edge Cases & Blast Radius ("Where does this fail?")
   - Observability & Triage Playbook
6. Do not invent details — ground your defense entirely in the actual codebase, invariants, and architectural constraints.
```

---

## 7. `sync-object-history.sh`

```markdown
You are tasked with generating a comprehensive Whiteboard Defense document for: `sync-object-history.sh` (`sync-object-history.sh`).

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
1. Read `sync-object-history.sh` and inspect its corpus synchronization pipeline, rsync delta-transfer mechanisms over SSH, optional intent artifact syncing (`--intent`), and dry-run capabilities.
2. Analyze the system architecture, design decisions, failure boundaries, and security considerations.
3. Write a concise, scannable, to-the-point Whiteboard Defense HTML document to:
   `Outputs/WhiteboardDefense/sync_object_history/whiteboard-defense-corpus-synchronizer.html`
4. Strict Tone & Formatting Directives:
   - **Self-Contained HTML Document:** Single HTML document with clean inline CSS, high-contrast tables, clear typography, and optional ASCII or Mermaid JS/SVG diagrams.
   - **Concise & Punchy:** Avoid fluff, walls of narrative text, or generic essay prose. Use bullet points and tight phrasing.
   - **Technical Precision:** Explicitly state synchronization flags, delta-transfer algorithms, invariants, and design choices.
   - **Human-Readable:** Format tables and lists for quick whiteboard recall and fast technical triage.
5. Follow the standard Whiteboard Defense Schema:
   - High-Level Architecture & Mental Model (with flow diagram)
   - Architectural Decisions & Trade-offs ("Why X instead of Y?" table)
   - Data Structures, Algorithms & Invariants
   - Threat Model & Adversarial Handling ("What if an actor behaves maliciously?" table)
   - Failure Modes, Edge Cases & Blast Radius ("Where does this fail?")
   - Observability & Triage Playbook
6. Do not invent details — ground your defense entirely in the actual codebase, invariants, and architectural constraints.
```

---

## 8. `parse_data.py`

```markdown
You are tasked with generating a comprehensive Whiteboard Defense document for: `parse_data.py` (`parse_data.py`).

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
1. Read `parse_data.py` and inspect its markdown parsing and JSON serialisation pipeline, section extraction regexes, status tag parsing (`DIVERGED`, `UNGROUNDED`, `OVERCAUTIOUS`), and non-function header exclusion tables.
2. Analyze the system architecture, design decisions, failure boundaries, and security considerations.
3. Write a concise, scannable, to-the-point Whiteboard Defense HTML document to:
   `Outputs/WhiteboardDefense/parse_data/whiteboard-defense-intent-markdown-parser.html`
4. Strict Tone & Formatting Directives:
   - **Self-Contained HTML Document:** Single HTML document with clean inline CSS, high-contrast tables, clear typography, and optional ASCII or Mermaid JS/SVG diagrams.
   - **Concise & Punchy:** Avoid fluff, walls of narrative text, or generic essay prose. Use bullet points and tight phrasing.
   - **Technical Precision:** Explicitly state data structures (`dict[str, list[dict]]`, tag sets), regex state machine logic, invariants, and design choices.
   - **Human-Readable:** Format tables and lists for quick whiteboard recall and fast technical triage.
5. Follow the standard Whiteboard Defense Schema:
   - High-Level Architecture & Mental Model (with flow diagram)
   - Architectural Decisions & Trade-offs ("Why X instead of Y?" table)
   - Data Structures, Algorithms & Invariants
   - Threat Model & Adversarial Handling ("What if an actor behaves maliciously?" table)
   - Failure Modes, Edge Cases & Blast Radius ("Where does this fail?")
   - Observability & Triage Playbook
6. Do not invent details — ground your defense entirely in the actual codebase, invariants, and architectural constraints.
```

---

## 9. `build_dataset.py`

```markdown
You are tasked with generating a comprehensive Whiteboard Defense document for: `build_dataset.py` (`build_dataset.py`).

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
1. Read `build_dataset.py` and examine its multi-source data aggregation, line range extraction heuristics from unstructured text, source file matching/caching, and markdown-to-HTML compilation.
2. Analyze the system architecture, design decisions, failure boundaries, and security considerations.
3. Write a concise, scannable, to-the-point Whiteboard Defense HTML document to:
   `Outputs/WhiteboardDefense/build_dataset/whiteboard-defense-assessment-dataset-builder.html`
4. Strict Tone & Formatting Directives:
   - **Self-Contained HTML Document:** Single HTML document with clean inline CSS, high-contrast tables, clear typography, and optional ASCII or Mermaid JS/SVG diagrams.
   - **Concise & Punchy:** Avoid fluff, walls of narrative text, or generic essay prose. Use bullet points and tight phrasing.
   - **Technical Precision:** Explicitly state data structures (caching dicts, nested record schemas), line-extraction heuristics, invariants, and design choices.
   - **Human-Readable:** Format tables and lists for quick whiteboard recall and fast technical triage.
5. Follow the standard Whiteboard Defense Schema:
   - High-Level Architecture & Mental Model (with flow diagram)
   - Architectural Decisions & Trade-offs ("Why X instead of Y?" table)
   - Data Structures, Algorithms & Invariants
   - Threat Model & Adversarial Handling ("What if an actor behaves maliciously?" table)
   - Failure Modes, Edge Cases & Blast Radius ("Where does this fail?")
   - Observability & Triage Playbook
6. Do not invent details — ground your defense entirely in the actual codebase, invariants, and architectural constraints.
```

---

## 10. `generate_html.py`

```markdown
You are tasked with generating a comprehensive Whiteboard Defense document for: `generate_html.py` (`generate_html.py`).

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
1. Read `generate_html.py` and examine how it embeds dataset JSON into an interactive static HTML explorer with client-side filtering, collapsible diff views, and zero external dependencies.
2. Analyze the system architecture, design decisions, failure boundaries, and security considerations.
3. Write a concise, scannable, to-the-point Whiteboard Defense HTML document to:
   `Outputs/WhiteboardDefense/generate_html/whiteboard-defense-html-assessment-explorer.html`
4. Strict Tone & Formatting Directives:
   - **Self-Contained HTML Document:** Single HTML document with clean inline CSS, high-contrast tables, clear typography, and optional ASCII or Mermaid JS/SVG diagrams.
   - **Concise & Punchy:** Avoid fluff, walls of narrative text, or generic essay prose. Use bullet points and tight phrasing.
   - **Technical Precision:** Explicitly state client-side data structures (JS state arrays, filter sets), DOM rendering pipeline, invariants, and design choices.
   - **Human-Readable:** Format tables and lists for quick whiteboard recall and fast technical triage.
5. Follow the standard Whiteboard Defense Schema:
   - High-Level Architecture & Mental Model (with flow diagram)
   - Architectural Decisions & Trade-offs ("Why X instead of Y?" table)
   - Data Structures, Algorithms & Invariants
   - Threat Model & Adversarial Handling ("What if an actor behaves maliciously?" table)
   - Failure Modes, Edge Cases & Blast Radius ("Where does this fail?")
   - Observability & Triage Playbook
6. Do not invent details — ground your defense entirely in the actual codebase, invariants, and architectural constraints.
```

---

## 11. `gemma-agents/generate_tests.py`

```markdown
You are tasked with generating a comprehensive Whiteboard Defense document for: `generate_tests.py` (`gemma-agents/generate_tests.py`).

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
1. Read `gemma-agents/generate_tests.py` and examine its Ollama API communication, automated pytest feedback loop, code extraction regexes, iterative correction loop, and fallback strategies.
2. Analyze the system architecture, design decisions, failure boundaries, and security considerations.
3. Write a concise, scannable, to-the-point Whiteboard Defense HTML document to:
   `Outputs/WhiteboardDefense/generate_tests_gemma/whiteboard-defense-gemma-pytest-feedback-loop.html`
4. Strict Tone & Formatting Directives:
   - **Self-Contained HTML Document:** Single HTML document with clean inline CSS, high-contrast tables, clear typography, and optional ASCII or Mermaid JS/SVG diagrams.
   - **Concise & Punchy:** Avoid fluff, walls of narrative text, or generic essay prose. Use bullet points and tight phrasing.
   - **Technical Precision:** Explicitly state data structures (iteration history lists, prompt payload dicts), loop termination invariants, and design choices.
   - **Human-Readable:** Format tables and lists for quick whiteboard recall and fast technical triage.
5. Follow the standard Whiteboard Defense Schema:
   - High-Level Architecture & Mental Model (with flow diagram)
   - Architectural Decisions & Trade-offs ("Why X instead of Y?" table)
   - Data Structures, Algorithms & Invariants
   - Threat Model & Adversarial Handling ("What if an actor behaves maliciously?" table)
   - Failure Modes, Edge Cases & Blast Radius ("Where does this fail?")
   - Observability & Triage Playbook
6. Do not invent details — ground your defense entirely in the actual codebase, invariants, and architectural constraints.
```

---

## 12. `gemma-agents/launch-gemma-agents.sh` & Remote Suite

```markdown
You are tasked with generating a comprehensive Whiteboard Defense document for: Gemma Agent Launchers (`gemma-agents/launch-gemma-agents.sh`, `gemma-agents/setup-gemma-remote.sh`, `gemma-agents/launch-gemma-remote.sh`, `gemma-agents/run-remaining.sh`).

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
1. Read `gemma-agents/launch-gemma-agents.sh` and its companion remote deployment scripts in `gemma-agents/` to analyze multi-tab terminal launching, local vs remote SSH offloading, resource contention management for local LLMs, and batch execution tracking.
2. Analyze the system architecture, design decisions, failure boundaries, and security considerations.
3. Write a concise, scannable, to-the-point Whiteboard Defense HTML document to:
   `Outputs/WhiteboardDefense/launch_gemma_agents/whiteboard-defense-gemma-agent-launcher.html`
4. Strict Tone & Formatting Directives:
   - **Self-Contained HTML Document:** Single HTML document with clean inline CSS, high-contrast tables, clear typography, and optional ASCII or Mermaid JS/SVG diagrams.
   - **Concise & Punchy:** Avoid fluff, walls of narrative text, or generic essay prose. Use bullet points and tight phrasing.
   - **Technical Precision:** Explicitly state process models, resource contention limits, environment propagation, invariants, and design choices.
   - **Human-Readable:** Format tables and lists for quick whiteboard recall and fast technical triage.
5. Follow the standard Whiteboard Defense Schema:
   - High-Level Architecture & Mental Model (with flow diagram)
   - Architectural Decisions & Trade-offs ("Why X instead of Y?" table)
   - Data Structures, Algorithms & Invariants
   - Threat Model & Adversarial Handling ("What if an actor behaves maliciously?" table)
   - Failure Modes, Edge Cases & Blast Radius ("Where does this fail?")
   - Observability & Triage Playbook
6. Do not invent details — ground your defense entirely in the actual codebase, invariants, and architectural constraints.
```
