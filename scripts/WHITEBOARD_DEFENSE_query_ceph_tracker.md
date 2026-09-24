# Whiteboard Defense — `query_ceph_tracker.py`

> **File:** [`scripts/query_ceph_tracker.py`](scripts/query_ceph_tracker.py)  
> **Author of document:** IBM Bob  
> **Purpose:** Full technical walkthrough suitable for a whiteboard-style interview or code-review defense.

---

## 1. What Does This Script Do? (30-second pitch)

`query_ceph_tracker.py` is a CLI tool that hits the **Redmine REST API** exposed by [tracker.ceph.com](https://tracker.ceph.com) and presents the results in two ways:

| Mode | Trigger | Output |
|---|---|---|
| **Issue detail** | `--issue <id>` | Formatted terminal output for a single issue |
| **Batch search** | `--search TERM …` or no args | Terminal summary **+** static HTML report written to `Outputs/TrackerSearch/` |

The HTML report is a fully self-contained local website: one `index.html` summary page and one `issue_<id>.html` detail page per unique issue discovered.

---

## 2. Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────┐
│                        main()                               │
│  argparse → --issue | --search | DEFAULT_SEARCHES           │
└────────────────────┬────────────────────────────────────────┘
                     │
          ┌──────────▼──────────┐
          │   HTTP Layer        │
          │  fetch_json(url)    │  ← urllib.request (stdlib only)
          │  search_issues()    │  subject=~<term>&status_id=…
          │  fetch_issue()      │  /issues/<id>.json
          └──────────┬──────────┘
                     │
       ┌─────────────┴───────────────┐
       │                             │
┌──────▼───────┐            ┌────────▼─────────────┐
│ Terminal I/O │            │ HTML Generation       │
│ print_issue_ │            │ build_issue_page()    │
│ list/detail  │            │ build_index()         │
│              │            │ _summary_card_html()  │
└──────────────┘            └────────┬──────────────┘
                                     │
                            ┌────────▼──────────────┐
                            │  write_html_output()  │
                            │  • deduplication      │
                            │  • per-issue fetch    │
                            │  • file I/O           │
                            └───────────────────────┘
```

**No third-party dependencies.** Every import — `argparse`, `html`, `json`, `os`, `sys`, `urllib`, `datetime`, `re` — is Python 3 standard library.

---

## 3. Module-by-Module Walkthrough

### 3.1 Constants

```python
BASE_URL  = "https://tracker.ceph.com"
HTML_OUT  = "Outputs/TrackerSearch"
STATUS_MAP = {"open": "o", "closed": "c", "all": "*"}
```

- `STATUS_MAP` translates human-readable CLI choices (`open|closed|all`) to the Redmine query-parameter values expected by the API.  
- `HTML_OUT` is a **relative path**, so outputs land next to wherever the script is invoked from.

### 3.2 `DEFAULT_SEARCHES`

Eight hardcoded search terms all related to a specific Ceph feature area: **device life-expectancy tracking** in the manager daemon. These drive the "no args" mode, making the script usable as a zero-config daily query.

### 3.3 `SHARED_CSS`

A ~40-line embedded CSS string shared by both HTML templates. Keeps the tool **single-file** (no external assets) and ensures the local website works offline. It implements:
- A GitHub-style color palette (grays, blue links)
- `.badge-*` classes mapped to Redmine status names
- `.pri-*` classes mapped to Redmine priority names

### 3.4 HTTP Layer

#### [`fetch_json(url)`](scripts/query_ceph_tracker.py:91)
```python
req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "…"})
with urllib.request.urlopen(req, timeout=15) as resp:
    return json.loads(resp.read().decode())
```
- Sets a `User-Agent` header (polite API citizenship).
- Hard 15-second timeout to avoid indefinite hangs.
- No authentication — tracker.ceph.com exposes read-only data publicly.

#### [`search_issues(term, status, limit)`](scripts/query_ceph_tracker.py:100)
Builds a Redmine subject-search URL:
```
/issues.json?subject=~<encoded_term>&status_id=<status>&limit=<n>&sort=updated_on:desc
```
- `subject=~` means "subject **contains** term" (Redmine wildcard prefix).
- Results sorted newest-updated first.
- `urllib.parse.quote` prevents injection / malformed URLs.

#### [`fetch_issue(issue_id)`](scripts/query_ceph_tracker.py:112)
Simple `GET /issues/<id>.json`. Returns the full issue object including `description` (which search results omit).

### 3.5 Formatting Helpers

| Function | Purpose |
|---|---|
| [`fmt_date(iso)`](scripts/query_ceph_tracker.py:119) | ISO-8601 → `YYYY-MM-DD`; graceful fallback on parse failure |
| [`status_class(name)`](scripts/query_ceph_tracker.py:126) | Maps Redmine status string → CSS badge class |
| [`priority_class(name)`](scripts/query_ceph_tracker.py:139) | Maps Redmine priority string → CSS badge class |
| [`redmine_to_html(text)`](scripts/query_ceph_tracker.py:150) | Minimal textile → HTML renderer (see §3.6) |

### 3.6 `redmine_to_html` — The Textile Mini-Renderer

Redmine stores descriptions in [Textile](https://textile-lang.com/) markup. This function converts the most common constructs:

```
Input (Textile / raw text)         → Output HTML
───────────────────────────────────────────────────────────────
<pre>…</pre>                       → <pre><code>…</code></pre>
@inline_code@                      → <code>inline_code</code>
*bold*                             → <strong>bold</strong>
_italic_                           → <em>italic</em>
https://…                          → <a href="…">…</a>
blank lines                        → </p><p>
single newlines                    → <br>
```

**Crucially**, `html.escape()` is applied **first**, before any regex substitutions. This prevents stored XSS: if a tracker description contains `<script>alert(1)</script>`, it becomes `&lt;script&gt;` and is never executed when the page is opened locally.

The function is intentionally minimal — it doesn't attempt full Textile support (headings, tables, lists), only the constructs most commonly seen in Ceph tracker descriptions.

### 3.7 Terminal Output Functions

- [`print_issue_list(data, term)`](scripts/query_ceph_tracker.py:187): Iterates `data["issues"]`, prints a formatted block per issue.
- [`print_issue_detail(data)`](scripts/query_ceph_tracker.py:218): Prints full metadata + raw description text for a single `--issue` lookup.

### 3.8 HTML Generation

#### [`build_issue_page(issue, generated_at)`](scripts/query_ceph_tracker.py:244)
Returns a complete standalone HTML document for one issue. Notable design choices:
- All user-supplied strings pass through `html.escape()` before being embedded.
- `SHARED_CSS` inlined in `<style>` tag — no external stylesheet dependency.
- A breadcrumb `← Back to search results` links to `index.html` (relative path).
- "View on tracker.ceph.com ↗" link uses `target="_blank"` for external navigation.

#### [`_summary_card_html(issue)`](scripts/query_ceph_tracker.py:386)
Returns an HTML `<div class="card">` fragment for use in the index. Reads `issue["_matched_searches"]` — a synthetic metadata key injected during deduplication — to show which search terms surfaced each issue.

#### [`build_index(results, unique_issues, generated_at)`](scripts/query_ceph_tracker.py:419)
Renders the `index.html` page. Structure:
1. Summary bar: searches run, unique issues, total raw matches (with duplicates).
2. Per-search-term `<section>` containing cards for that term's results.

The index is **grouped by search term**, not deduplicated — so the same issue can appear in multiple sections if it matched multiple terms. This is intentional: it shows the user *why* each issue was surfaced.

### 3.9 `write_html_output` — The Deduplication + Write Pipeline

```
results: list[(term, API response dict)]
         │
         ▼
 Build seen: dict[issue_id → issue + _matched_searches list]
         │
         ▼
 For each unique issue:
   fetch full detail (description not in search results)
   build_issue_page() → write issue_<id>.html
         │
         ▼
 Annotate search-result issues with _matched_searches
         │
         ▼
 build_index() → write index.html
         │
         ▼
 return path to index.html
```

**Two-phase fetch design:** search results contain only summary fields; full descriptions require a separate per-issue `GET`. The function makes `N+1` HTTP calls (1 search per term + 1 detail per unique issue). For the default 8 searches, this is typically 8 search calls + ~10–30 detail calls.

### 3.10 `main()` — Argument Dispatch

```
--issue INT          → fetch_issue() → print_issue_detail() → exit
--search TERM …      → user-supplied terms
(no args)            → DEFAULT_SEARCHES

--status open|closed|all   (default: all)
--limit INT                (default: 25 per search)
```

`--issue` and `--search` are **mutually exclusive** (enforced by `argparse.add_mutually_exclusive_group()`).

---

## 4. Data Flow Diagram

```
CLI args
  │
  ├─ --issue N ──────────────────────────────────────────────────────► terminal
  │     └── fetch_issue(N) → print_issue_detail()
  │
  └─ terms (--search or DEFAULT_SEARCHES)
        │
        ├─ for each term:
        │     search_issues(term) → print_issue_list() → results[]
        │
        └─ write_html_output(results)
              │
              ├─ deduplicate → unique_issues[]
              ├─ for each unique issue: fetch_issue() → issue_<id>.html
              └─ build_index() → index.html
```

---

## 5. Error Handling Strategy

| Location | Error | Handling |
|---|---|---|
| `fetch_json` | Network / HTTP error | Propagates (caught by callers) |
| Search loop | Any exception per term | `print(ERROR)` + append empty result; loop continues |
| Detail fetch loop | Any exception per issue | `print(ERROR, file=sys.stderr)`; issue detail page skipped |
| `fmt_date` | Malformed ISO string | `except Exception` → `iso[:10]` fallback or `"?"` |
| `redmine_to_html` | Empty/None description | Returns `"<em>(no description)</em>"` |

The philosophy is **best-effort output**: if one search or one detail fetch fails, the rest of the report is still written. The script never hard-crashes mid-run on network errors.

---

## 6. Security Considerations

| Concern | Mitigation |
|---|---|
| **XSS in generated HTML** | `html.escape()` applied to all Redmine content before embedding in HTML templates |
| **URL injection** | `urllib.parse.quote(term)` encodes search terms before URL construction |
| **Network timeout** | `timeout=15` in `urlopen` prevents indefinite hangs |
| **No secrets / credentials** | Tracker API is read-only public; no API keys or auth tokens |
| **No `eval`/`exec`** | No dynamic code execution anywhere |
| **Local file output only** | Writes to relative `Outputs/` directory; no server, no remote write |

One minor note: the bare-URL regex in `redmine_to_html` does not sanitize `javascript:` URLs. However, since Ceph tracker content is trusted (authoritative upstream) and the output is a local file (not served over HTTP), this is an acceptable, minimal risk.

---

## 7. Design Decisions & Trade-offs

### No third-party libraries
**Decision:** Use only Python stdlib.  
**Trade-off:** Avoids dependency management, pip, virtual environments. The cost is a hand-rolled mini Textile renderer and manual HTML templating instead of using `requests` + a proper Textile parser.

### No authentication
**Decision:** Rely on tracker.ceph.com's public read-only API.  
**Trade-off:** Zero setup for the user. Limitation: no access to private issues, no write operations.

### Static HTML output (no server)
**Decision:** Write self-contained HTML files instead of launching an HTTP server.  
**Trade-off:** Output works offline, no port management, easy to `open` in a browser. Limitation: no search/filter interactivity in the browser.

### N+1 fetches for descriptions
**Decision:** Search results omit `description`; detail pages fetch it individually.  
**Trade-off:** Correct and necessary given the Redmine API shape. Makes the tool slightly slow for large result sets, but each call is bounded by `--limit`.

### Index grouped by search term (not deduplicated)
**Decision:** Index shows each term's section with cards, even if an issue appears in multiple sections.  
**Trade-off:** Intentional — the user sees *why* each issue was surfaced. The summary bar shows "unique issues" count for the deduplicated total.

---

## 8. Extension Points (How to Grow This)

| Want to add | Where to change |
|---|---|
| New default search terms | `DEFAULT_SEARCHES` list |
| Support for authenticated (private) issues | Add `X-Redmine-API-Key` header in `fetch_json()` from env var |
| Paginate beyond `--limit` | Loop `search_issues()` with `offset` parameter while `offset < total_count` |
| Full Textile rendering | Replace `redmine_to_html()` with a proper `textile` library call |
| JSON export alongside HTML | Add a `write_json_output()` call in `main()` |
| Filter by project | Add `&project_id=ceph` to the search URL in `search_issues()` |

---

## 9. Quick-Reference: Key Functions

| Function | Signature | Returns |
|---|---|---|
| `fetch_json` | `(url: str) → dict` | Parsed JSON response |
| `search_issues` | `(term, status, limit) → dict` | Redmine issues list response |
| `fetch_issue` | `(issue_id: int) → dict` | Single issue response |
| `fmt_date` | `(iso: str) → str` | `YYYY-MM-DD` string |
| `status_class` | `(status_name: str) → str` | CSS class name |
| `priority_class` | `(priority_name: str) → str` | CSS class name |
| `redmine_to_html` | `(text: str) → str` | HTML string |
| `print_issue_list` | `(data, term) → None` | Terminal side-effect |
| `print_issue_detail` | `(data) → None` | Terminal side-effect |
| `build_issue_page` | `(issue, generated_at) → str` | Full HTML document string |
| `_summary_card_html` | `(issue) → str` | HTML fragment string |
| `build_index` | `(results, unique_issues, generated_at) → str` | Full HTML document string |
| `write_html_output` | `(results, out_dir) → str` | Path to `index.html` |
| `main` | `() → None` | Entry point |

---

## 10. Sample Invocations

```bash
# Fetch a specific issue and print to terminal
python3 query_ceph_tracker.py --issue 80660

# Run default 8 searches, generate HTML report
python3 query_ceph_tracker.py

# Search two custom terms, open issues only
python3 query_ceph_tracker.py --search "DeviceState" "utime_t underflow" --status open

# One term, all statuses, up to 50 results
python3 query_ceph_tracker.py --search "life_expectancy" --status all --limit 50
```

Output files after a batch run:
```
Outputs/TrackerSearch/
  index.html          ← summary of all search results
  issue_78900.html    ← detail page for issue #78900
  issue_79112.html    ← detail page for issue #79112
  …
```

---

*Generated by IBM Bob*
