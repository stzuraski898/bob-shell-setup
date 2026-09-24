# Whiteboard Defense: Ceph Tracker Search Tool (`query_ceph_tracker.py`)

**Author / Maintainer:** Bob (AI Engineer)  
**Target File / Subsystem:** [`scripts/query_ceph_tracker.py`](scripts/query_ceph_tracker.py:1)  
**Context / Scope:** Internal Engineering Tooling / Upstream Issue Investigation  

---

## 1. High-Level Architecture & Mental Model

### Core Responsibility
Fetches, deduplicates, and compiles upstream Ceph Redmine issues (`tracker.ceph.com`) into an offline static HTML investigation dossier (`Outputs/TrackerSearch/`).

```mermaid
flowchart TD
    CLI[CLI: Term / Issue ID / Status] --> FetchSearch[search_issues: GET /issues.json]
    FetchSearch --> Dedupe[Deduplicate: seen: dict[int, dict]]
    Dedupe --> FetchDetail[fetch_issue: GET /issues/{id}.json]
    FetchDetail --> RenderDetail[build_issue_page: issue_{id}.html]
    Dedupe --> RenderIndex[build_index: index.html]
```

### Data & Control Flow
- **Ingress:** Accepts search queries (`--search`), single issues (`--issue`), and status filters (`--status open|closed|all`).
- **Batch Querying:** Sends HTTP GET requests to `/issues.json?subject=~<term>&status_id=<status>`.
- **Deduplication:** Aggregates multi-query results into a hash map, annotating each issue with all matched terms.
- **Detail Hydration:** Fetches complete descriptions via `/issues/<id>.json` for each unique issue.
- **Rendering:** Transpiles Redmine Textile to safe HTML and writes static `index.html` and `issue_<id>.html`.

---

## 2. Architectural Decisions & Trade-offs ("Why X instead of Y?")

| Decision Made (X) | Rejected Alternative (Y) | Whiteboard Defense |
|---|---|---|
| **Python Standard Library Only** (`urllib`, `json`, `html`, `re`) | External dependencies (`requests`, `beautifulsoup4`, `jinja2`) | Zero-setup portability across any minimal CI container or developer machine without virtualenvs. |
| **Static HTML Files** | Web server (Flask/FastAPI) or terminal-only scrollback | Generates permanent, shareable, offline-readable artifacts with zero daemon overhead. |
| **Two-Stage Hydration** (Search query list $\to$ individual `/issues/{id}.json`) | Single search query response only | Redmine's `/issues.json` search endpoint truncates description bodies; detail hydration guarantees full reproduction traces offline. |
| **Sequential HTTP Requests** | Concurrent requests (`asyncio` / `ThreadPoolExecutor`) | Prevents upstream rate-limiting (429) or IP throttling on community infrastructure (`tracker.ceph.com`). |
| **Pre-escape Sanitization** (`html.escape` before regex formatting) | Markdown parsing library or raw regex replacement | Guarantees protection against XSS from untrusted upstream ticket content while supporting safe formatting. |

---

## 3. Data Structures, Algorithms & Invariants

### Data Structures
- **`seen: dict[int, dict]` (Hash Map):**
  - *Usage:* Deduplicates issues by integer ID across multiple search query results.
  - *Complexity:* $O(1)$ lookup/insert; $O(U)$ space where $U$ = unique issues.
  - *Augmentation:* Stores `_matched_searches: list[str]` to track all search terms hitting that issue.
- **`STATUS_MAP: dict[str, str]` (Lookup Table):**
  - *Usage:* Maps CLI flags (`open`, `closed`, `all`) to Redmine query params (`o`, `c`, `*`).
- **`results: list[tuple[str, dict]]` (Ordered Sequence):**
  - *Usage:* Preserves search term execution order for structured section-by-section index rendering.

### Algorithms
- **Redmine Textile Transpilation (`redmine_to_html`):**
  - Escapes HTML entities (`&`, `<`, `>`).
  - Sequentially applies non-greedy regex substitutions for `<pre>` code blocks, inline `@code@`, `*bold*`, `_italic_`, and bare URLs (`https?://`).
  - Converts double-newlines to `<p>` tags and single newlines to `<br>`.

### Core Invariants
1. **Uniqueness:** Exactly one `issue_<id>.html` file generated per unique issue ID.
2. **Cross-Reference Accuracy:** `_matched_searches` contains the exact set of executed queries that returned that issue.
3. **DOM Safety:** No unescaped user-supplied markup reaches the output HTML.

---

## 4. Threat Model & Adversarial Handling

| Threat / Actor Behavior | Attack Vector | Defensive Countermeasure |
|---|---|---|
| **Malicious Issue Content (XSS)** | Public user embeds `<script>` or event handlers in Redmine description. | `html.escape()` applied to all fields prior to regex transformation; URL auto-linking restricted strictly to `https?://`. |
| **Upstream Service Hang** | `tracker.ceph.com` stalls connection. | Hard socket timeout (`timeout=15`) on all `urllib.request.urlopen()` calls. |
| **HTTP 4xx / 5xx / 429 Errors** | Rate limit, missing ticket, or server downtime. | Per-request `try...except` blocks log errors to `stderr` and preserve execution of remaining queue. |
| **Query Injection** | Malicious characters in CLI search term. | Strict URL parameter encoding via `urllib.parse.quote()`. |

---

## 5. Failure Modes, Edge Cases & Blast Radius

### Failure Modes & Edge Cases
- **Upstream Network Outage:** Logs error to `stderr`, returns empty dataset, and outputs empty summary index gracefully.
- **Schema / Field Omission:** Defensive dictionary access (`.get("key", default)`) handles missing authors, versions, or assignees without `KeyError`.
- **Malformed ISO Dates:** `fmt_date()` catches parse exceptions and falls back to string slicing (`iso[:10]`) or `"?"`.
- **Zero Search Results:** Outputs explicit `<p class="no-results">No matching issues found.</p>`.

### Blast Radius
- **Zero External Side Effects:** Pure client-side tool with read-only remote access.
- **Filesystem Isolation:** Writes strictly to `Outputs/TrackerSearch/`.

---

## 6. Observability & Triage Playbook

### Diagnostic Signals
- **Console Stream:** Live progress emitted to `stdout` (query term, result count, hydration progress).
- **Error Stream:** HTTP status codes and connection failures isolated to `stderr`.

### Triage Checklist
1. **HTTP 403 / 429 Errors:** Verify IP rate limits via `curl -I https://tracker.ceph.com/issues.json`.
2. **Missing Issue Descriptions:** Check if the ticket is marked private/restricted on Redmine.
3. **Empty Results:** Verify `--status` filter (`open` vs `all`) and Redmine query syntax.
