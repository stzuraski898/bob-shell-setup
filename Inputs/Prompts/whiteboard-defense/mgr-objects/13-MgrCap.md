---
tracker: none
---
You are tasked with generating a comprehensive Whiteboard Defense document for: `MgrCap` (`src/mgr/MgrCap.cc`, `src/mgr/MgrCap.h`).

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
1. Read the intent analysis for this class:
   `~/BobOutput/Object History/MgrCap-intent.md`
   This contains the function-by-function intent derived from the full git history, DIVERGED/UNGROUNDED/OVERCAUTIOUS findings, and invariant citations. Use it as the authoritative ground truth for design intent.
2. Read the raw git corpus at `~/BobOutput/Object History/v4/MgrCap/`:
   - `commits.txt` — all non-merge commits, newest first
   - `blame.txt` — git blame on `.cc` and `.h`
   - `functions.txt` — ctags function list
   - `rename_chain.txt` — file rename history
   - `diffs/<sha>.diff` — per-commit scoped diffs
   Use the corpus to ground architectural decisions in specific commits and confirm or expand on the intent findings.
3. Using the intent file and corpus as your sole sources, analyze the architecture, design decisions, failure boundaries, and security considerations of this class.
4. Write a concise, scannable, to-the-point Whiteboard Defense HTML document to:
   `~/BobOutput/WhiteboardDefense/MgrCap/whiteboard-defense-mgr-cap-authz.html`
5. Strict Tone & Formatting Directives:
   - **Self-Contained HTML Document:** Single HTML document with clean inline CSS, high-contrast tables, clear typography, and optional ASCII or SVG diagrams.
   - **Concise & Punchy:** Avoid fluff, walls of narrative text, or generic essay prose. Use bullet points and tight phrasing.
   - **Technical Precision:** Explicitly state grammar production rules, grant struct fields, allow-list evaluation complexity, and design choices. Cite commit SHAs from the corpus where they illuminate a decision.
   - **Human-Readable:** Format tables and lists for quick whiteboard recall and fast technical triage.
6. Follow the standard Whiteboard Defense Schema:
   - High-Level Architecture & Mental Model (with flow diagram)
   - Architectural Decisions & Trade-offs ("Why X instead of Y?" table)
   - Data Structures, Algorithms & Invariants
   - Threat Model & Adversarial Handling ("What if an actor behaves maliciously?" table)
   - Failure Modes, Edge Cases & Blast Radius ("Where does this fail?")
   - Observability & Triage Playbook
7. Do not invent details — ground your defense entirely in the intent file, corpus commits, and architectural constraints.
