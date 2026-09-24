#!/usr/bin/env python3
"""
query_ceph_tracker.py — search and inspect tracker.ceph.com (Redmine REST API)

Writes to Outputs/TrackerSearch/:
  index.html          — summary of all unique matching issues across all searches
  issue_<id>.html     — per-issue detail page (title, description, author/metadata)

Usage:
    python3 query_ceph_tracker.py                              # default searches
    python3 query_ceph_tracker.py --issue 80660                # fetch a specific issue (terminal)
    python3 query_ceph_tracker.py --search "DeviceState" "utime_t underflow"
    python3 query_ceph_tracker.py --search "life_expectancy" --status open
    python3 query_ceph_tracker.py --search "life_expectancy" --status all
"""

import argparse
import html as html_lib
import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone

BASE_URL = "https://tracker.ceph.com"
HTML_OUT = "Outputs/TrackerSearch"

STATUS_MAP = {
    "open":   "o",
    "closed": "c",
    "all":    "*",
}

DEFAULT_SEARCHES = [
    "life_expectancy",
    "set-life-expectancy",
    "DeviceState life expectancy",
    "set_life_expectancy",
    "get_life_expectancy_str",
    "DaemonServer life expectancy",
    "utime_t underflow",
    "inverted range life expectancy",
]

# ── Shared CSS ────────────────────────────────────────────────────────────────

SHARED_CSS = """
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, "Segoe UI", system-ui, sans-serif;
    font-size: 14px;
    line-height: 1.6;
    background: #f7f8fa;
    color: #1f2328;
  }
  .page { max-width: 860px; margin: 0 auto; padding: 32px 16px 64px; }
  a { color: #3b82d4; text-decoration: none; }
  a:hover { text-decoration: underline; }
  header {
    border-bottom: 2px solid #e5e7eb;
    padding-bottom: 16px;
    margin-bottom: 28px;
  }
  header h1 { font-size: 20px; font-weight: 700; }
  header .subtitle { color: #57606a; font-size: 13px; margin-top: 4px; }
  .badge {
    display: inline-block;
    font-size: 11px; padding: 1px 7px; border-radius: 10px;
    white-space: nowrap; font-weight: 500;
  }
  .badge-new      { background: #dbeafe; color: #1d4ed8; }
  .badge-progress { background: #fef9c3; color: #854d0e; }
  .badge-resolved { background: #dcfce7; color: #166534; }
  .badge-rejected { background: #fee2e2; color: #991b1b; }
  .badge-other    { background: #f3f4f6; color: #374151; }
  .pri-urgent { background: #fee2e2; color: #991b1b; }
  .pri-high   { background: #ffedd5; color: #9a3412; }
  .pri-normal { background: #f3f4f6; color: #374151; }
  .pri-low    { background: #f0fdf4; color: #166534; }
  footer {
    margin-top: 48px; padding-top: 12px;
    border-top: 1px solid #e5e7eb;
    text-align: center; font-size: 12px; color: #57606a;
  }
"""


# ── HTTP helpers ──────────────────────────────────────────────────────────────

def fetch_json(url: str) -> dict:
    req = urllib.request.Request(
        url,
        headers={"Accept": "application/json", "User-Agent": "ceph-tracker-query/1.0"},
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode())


def search_issues(term: str, status: str = "*", limit: int = 25) -> dict:
    encoded = urllib.parse.quote(term)
    url = (
        f"{BASE_URL}/issues.json"
        f"?subject=~{encoded}"
        f"&status_id={status}"
        f"&limit={limit}"
        f"&sort=updated_on:desc"
    )
    return fetch_json(url)


def fetch_issue(issue_id: int) -> dict:
    url = f"{BASE_URL}/issues/{issue_id}.json"
    return fetch_json(url)


# ── Formatting helpers ────────────────────────────────────────────────────────

def fmt_date(iso: str) -> str:
    try:
        return datetime.fromisoformat(iso.replace("Z", "+00:00")).strftime("%Y-%m-%d")
    except Exception:
        return iso[:10] if iso else "?"


def status_class(status_name: str) -> str:
    s = status_name.lower()
    if s in ("new", "open"):
        return "badge-new"
    if s in ("in progress", "in_progress"):
        return "badge-progress"
    if s in ("resolved", "closed", "fixed"):
        return "badge-resolved"
    if s in ("rejected", "wont fix"):
        return "badge-rejected"
    return "badge-other"


def priority_class(priority_name: str) -> str:
    p = priority_name.lower()
    if p in ("urgent", "immediate"):
        return "pri-urgent"
    if p == "high":
        return "pri-high"
    if p == "normal":
        return "pri-normal"
    return "pri-low"


def redmine_to_html(text: str) -> str:
    """Minimal Redmine textile → HTML: code blocks, pre blocks, line breaks."""
    import re
    if not text:
        return "<em>(no description)</em>"

    escaped = html_lib.escape(text)

    # <pre>…</pre> blocks (preserve whitespace)
    escaped = re.sub(
        r"&lt;pre&gt;(.*?)&lt;/pre&gt;",
        lambda m: f'<pre><code>{m.group(1)}</code></pre>',
        escaped,
        flags=re.DOTALL,
    )
    # inline @code@
    escaped = re.sub(r"@([^@\n]+)@", r"<code>\1</code>", escaped)
    # *bold*
    escaped = re.sub(r"\*([^*\n]+)\*", r"<strong>\1</strong>", escaped)
    # _italic_
    escaped = re.sub(r"_([^_\n]+)_", r"<em>\1</em>", escaped)
    # bare URLs → clickable links
    escaped = re.sub(
        r"(https?://[^\s&<>\"']+)",
        r'<a href="\1" target="_blank">\1</a>',
        escaped,
    )
    # blank lines → paragraph breaks
    escaped = re.sub(r"\n{2,}", "</p><p>", escaped)
    # single newlines → <br>
    escaped = escaped.replace("\n", "<br>")

    return f"<p>{escaped}</p>"


# ── Terminal output ───────────────────────────────────────────────────────────

def print_issue_list(data: dict, search_term: str) -> None:
    total  = data.get("total_count", 0)
    issues = data.get("issues", [])

    print(f"\n{'='*70}")
    print(f"  Search: \"{search_term}\"  —  {total} total result(s)")
    print(f"{'='*70}")

    if not issues:
        print("  (no matching issues)\n")
        return

    for issue in issues:
        iid      = issue.get("id")
        subject  = issue.get("subject", "")
        status   = issue.get("status", {}).get("name", "?")
        priority = issue.get("priority", {}).get("name", "?")
        tracker  = issue.get("tracker", {}).get("name", "?")
        updated  = fmt_date(issue.get("updated_on", ""))
        created  = fmt_date(issue.get("created_on", ""))
        assignee = issue.get("assigned_to", {}).get("name", "unassigned")

        print(f"\n  #{iid}  {subject}")
        print(f"  Status  : {status:<15}  Priority : {priority}")
        print(f"  Type    : {tracker:<15}  Assignee : {assignee}")
        print(f"  Created : {created:<15}  Updated  : {updated}")
        print(f"  URL     : {BASE_URL}/issues/{iid}")

    print()


def print_issue_detail(data: dict) -> None:
    issue    = data.get("issue", {})
    iid      = issue.get("id")
    subject  = issue.get("subject", "")
    status   = issue.get("status", {}).get("name", "?")
    priority = issue.get("priority", {}).get("name", "?")
    author   = issue.get("author", {}).get("name", "?")
    assignee = issue.get("assigned_to", {}).get("name", "unassigned")
    created  = fmt_date(issue.get("created_on", ""))
    updated  = fmt_date(issue.get("updated_on", ""))
    desc     = issue.get("description", "").strip()

    print(f"\n{'='*70}")
    print(f"  Issue #{iid}: {subject}")
    print(f"{'='*70}")
    print(f"  Status   : {status}   Priority : {priority}")
    print(f"  Author   : {author}   Assignee : {assignee}")
    print(f"  Created  : {created}  Updated  : {updated}")
    print(f"  URL      : {BASE_URL}/issues/{iid}")
    print(f"\n--- Description ---\n")
    print(desc if desc else "(no description)")
    print()


# ── Per-issue detail HTML page ────────────────────────────────────────────────

def build_issue_page(issue: dict, generated_at: str) -> str:
    iid      = issue.get("id")
    subject  = html_lib.escape(issue.get("subject", ""))
    status   = issue.get("status", {}).get("name", "?")
    priority = issue.get("priority", {}).get("name", "?")
    tracker  = html_lib.escape(issue.get("tracker", {}).get("name", "?"))
    author   = html_lib.escape(issue.get("author", {}).get("name", "?"))
    assignee = html_lib.escape(issue.get("assigned_to", {}).get("name", "unassigned"))
    category = html_lib.escape((issue.get("category") or {}).get("name", "—"))
    version  = html_lib.escape((issue.get("fixed_version") or {}).get("name", "—"))
    created  = fmt_date(issue.get("created_on", ""))
    updated  = fmt_date(issue.get("updated_on", ""))
    desc     = redmine_to_html(issue.get("description", ""))
    tracker_url = f"{BASE_URL}/issues/{iid}"
    sc       = status_class(status)
    pc       = priority_class(priority)

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>#{iid} — {html_lib.escape(issue.get("subject", ""))}</title>
<style>
{SHARED_CSS}
  .breadcrumb {{ font-size: 12px; color: #57606a; margin-bottom: 20px; }}
  .breadcrumb a {{ color: #3b82d4; }}
  .issue-title {{ font-size: 22px; font-weight: 700; margin-bottom: 10px; }}
  .issue-id {{ font-size: 14px; color: #57606a; font-weight: 400; }}
  .meta-grid {{
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
    gap: 10px 24px;
    background: #fff;
    border: 1px solid #e5e7eb;
    border-radius: 6px;
    padding: 16px 20px;
    margin-bottom: 28px;
    font-size: 13px;
  }}
  .meta-grid dt {{ color: #57606a; font-size: 11px; text-transform: uppercase;
                   letter-spacing: 0.04em; margin-bottom: 2px; }}
  .meta-grid dd {{ font-weight: 600; color: #1f2328; }}
  .section-heading {{
    font-size: 13px; font-weight: 600; text-transform: uppercase;
    letter-spacing: 0.05em; color: #57606a;
    border-bottom: 1px solid #e5e7eb;
    padding-bottom: 6px; margin-bottom: 16px;
  }}
  .description {{
    background: #fff; border: 1px solid #e5e7eb;
    border-radius: 6px; padding: 20px 24px;
    font-size: 14px; line-height: 1.7;
    color: #1f2328;
  }}
  .description p {{ margin-bottom: 12px; }}
  .description p:last-child {{ margin-bottom: 0; }}
  .description pre {{
    background: #f7f8fa; border: 1px solid #e5e7eb;
    border-radius: 4px; padding: 12px 14px;
    overflow-x: auto; font-size: 13px;
    margin: 10px 0;
  }}
  .description code {{
    background: #f0f1f3; border-radius: 3px;
    padding: 1px 4px; font-size: 12px; font-family: monospace;
  }}
  .description pre code {{
    background: none; padding: 0; font-size: 13px;
  }}
  .external-link {{
    display: inline-block; margin-top: 20px;
    font-size: 13px; color: #3b82d4;
    border: 1px solid #3b82d4; border-radius: 4px;
    padding: 5px 12px;
  }}
  .external-link:hover {{ background: #3b82d4; color: #fff; text-decoration: none; }}
</style>
</head>
<body>
<div class="page">
  <div class="breadcrumb">
    <a href="index.html">&#8592; Back to search results</a>
  </div>

  <header>
    <div class="issue-id">Bug #{iid} &mdash; {html_lib.escape(tracker)}</div>
    <h1 class="issue-title">{subject}</h1>
    <div>
      <span class="badge {sc}">{html_lib.escape(status)}</span>
      <span class="badge {pc}">{html_lib.escape(priority)}</span>
    </div>
  </header>

  <dl class="meta-grid">
    <div>
      <dt>Author</dt>
      <dd>{author}</dd>
    </div>
    <div>
      <dt>Assignee</dt>
      <dd>{assignee}</dd>
    </div>
    <div>
      <dt>Created</dt>
      <dd>{created}</dd>
    </div>
    <div>
      <dt>Updated</dt>
      <dd>{updated}</dd>
    </div>
    <div>
      <dt>Priority</dt>
      <dd>{html_lib.escape(priority)}</dd>
    </div>
    <div>
      <dt>Category</dt>
      <dd>{category}</dd>
    </div>
    <div>
      <dt>Target version</dt>
      <dd>{version}</dd>
    </div>
  </dl>

  <p class="section-heading">Description</p>
  <div class="description">
    {desc}
  </div>

  <a class="external-link" href="{tracker_url}" target="_blank">
    View on tracker.ceph.com &#8599;
  </a>

  <footer>Made with IBM Bob &mdash; generated {generated_at}</footer>
</div>
</body>
</html>"""


# ── Summary index HTML page ───────────────────────────────────────────────────

def _summary_card_html(issue: dict) -> str:
    iid      = issue.get("id")
    subject  = html_lib.escape(issue.get("subject", ""))
    status   = issue.get("status", {}).get("name", "?")
    priority = issue.get("priority", {}).get("name", "?")
    tracker  = html_lib.escape(issue.get("tracker", {}).get("name", "?"))
    author   = html_lib.escape(issue.get("author", {}).get("name", "?"))
    assignee = html_lib.escape(issue.get("assigned_to", {}).get("name", "unassigned"))
    created  = fmt_date(issue.get("created_on", ""))
    updated  = fmt_date(issue.get("updated_on", ""))
    sc       = status_class(status)
    pc       = priority_class(priority)
    matched  = html_lib.escape(", ".join(issue.get("_matched_searches", [])))

    return f"""
    <div class="card">
      <div class="card-header">
        <a class="issue-num" href="issue_{iid}.html">#{iid}</a>
        <a class="issue-subject" href="issue_{iid}.html">{subject}</a>
        <span class="badge {sc}">{html_lib.escape(status)}</span>
        <span class="badge {pc}">{html_lib.escape(priority)}</span>
      </div>
      <div class="card-meta">
        <span>Type: <strong>{tracker}</strong></span>
        <span>Author: <strong>{author}</strong></span>
        <span>Assignee: <strong>{assignee}</strong></span>
        <span>Created: <strong>{created}</strong></span>
        <span>Updated: <strong>{updated}</strong></span>
      </div>
      <div class="matched-searches">Matched: {matched}</div>
    </div>"""


def build_index(
    results: list[tuple[str, dict]],
    unique_issues: list[dict],
    generated_at: str,
) -> str:
    total_searches = len(results)
    total_unique   = len(unique_issues)
    total_raw      = sum(r.get("total_count", 0) for _, r in results)

    # Group cards by search term for the per-section view
    sections_html = ""
    for term, data in results:
        count  = data.get("total_count", 0)
        issues = data.get("issues", [])
        if issues:
            cards = "".join(_summary_card_html(i) for i in issues)
        else:
            cards = '<p class="no-results">No matching issues found.</p>'

        sections_html += f"""
  <section>
    <h2 class="section-title">
      <em>{html_lib.escape(term)}</em>
      <span class="result-count">{count} result(s)</span>
    </h2>
    {cards}
  </section>"""

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Ceph Tracker Search Results</title>
<style>
{SHARED_CSS}
  .summary-bar {{
    display: flex; gap: 24px; flex-wrap: wrap;
    background: #fff; border: 1px solid #e5e7eb;
    border-radius: 6px; padding: 12px 16px; margin-bottom: 28px;
    font-size: 13px; color: #57606a;
  }}
  .summary-bar strong {{ color: #1f2328; }}
  section {{ margin-bottom: 36px; }}
  .section-title {{
    font-size: 15px; font-weight: 600; margin-bottom: 12px;
    display: flex; align-items: center; gap: 10px;
    border-left: 3px solid #3b82d4; padding-left: 10px;
  }}
  .section-title em {{ font-style: normal; color: #3b82d4; }}
  .result-count {{
    font-size: 12px; font-weight: 400;
    background: #e5e7eb; color: #57606a;
    border-radius: 10px; padding: 1px 8px;
  }}
  .card {{
    background: #fff; border: 1px solid #e5e7eb;
    border-radius: 6px; padding: 12px 14px; margin-bottom: 10px;
  }}
  .card:hover {{ border-color: #3b82d4; }}
  .card-header {{
    display: flex; flex-wrap: wrap; align-items: baseline;
    gap: 8px; margin-bottom: 6px;
  }}
  .issue-num {{
    font-weight: 700; color: #3b82d4; white-space: nowrap; font-size: 13px;
  }}
  .issue-subject {{ flex: 1; font-weight: 600; font-size: 14px; color: #1f2328; }}
  .issue-subject:hover {{ color: #3b82d4; }}
  .card-meta {{
    display: flex; flex-wrap: wrap; gap: 12px;
    font-size: 12px; color: #57606a; margin-bottom: 4px;
  }}
  .card-meta strong {{ color: #1f2328; }}
  .matched-searches {{
    font-size: 11px; color: #57606a; font-style: italic; margin-top: 2px;
  }}
  .no-results {{ color: #57606a; font-style: italic; padding: 6px 0; }}
</style>
</head>
<body>
<div class="page">
  <header>
    <h1>Ceph Tracker Search Results</h1>
    <div class="subtitle">tracker.ceph.com &mdash; generated {generated_at}</div>
  </header>

  <div class="summary-bar">
    <span>Searches run: <strong>{total_searches}</strong></span>
    <span>Unique issues: <strong>{total_unique}</strong></span>
    <span>Total matches (with duplicates): <strong>{total_raw}</strong></span>
  </div>

  {sections_html}

  <footer>Made with IBM Bob &mdash; generated {generated_at}</footer>
</div>
</body>
</html>"""


# ── Write output files ────────────────────────────────────────────────────────

def write_html_output(results: list[tuple[str, dict]], out_dir: str) -> str:
    """
    1. Deduplicate issues across all search results.
    2. Fetch full detail for each unique issue (for description).
    3. Write one detail page per issue.
    4. Write the summary index.html.
    Returns path to index.html.
    """
    os.makedirs(out_dir, exist_ok=True)
    ts           = datetime.now(timezone.utc)
    generated_at = ts.strftime("%Y-%m-%d %H:%M UTC")

    # Deduplicate: collect unique issue IDs, track which searches matched each
    seen: dict[int, dict] = {}
    for term, data in results:
        for issue in data.get("issues", []):
            iid = issue.get("id")
            if iid not in seen:
                seen[iid] = dict(issue)
                seen[iid]["_matched_searches"] = []
            if term not in seen[iid]["_matched_searches"]:
                seen[iid]["_matched_searches"].append(term)

    unique_issues = list(seen.values())
    print(f"\n  Unique issues across all searches: {len(unique_issues)}")

    # Fetch full details and write per-issue pages
    for issue in unique_issues:
        iid = issue.get("id")
        print(f"  Fetching full details for #{iid} …", end=" ", flush=True)
        try:
            detail = fetch_issue(iid).get("issue", {})
            # Preserve matched search metadata
            detail["_matched_searches"] = issue["_matched_searches"]
            page = build_issue_page(detail, generated_at)
            path = os.path.join(out_dir, f"issue_{iid}.html")
            with open(path, "w", encoding="utf-8") as f:
                f.write(page)
            print("done")
        except Exception as exc:
            print(f"ERROR: {exc}", file=sys.stderr)

    # Also annotate the search-result issues with matched searches for the index cards
    for term, data in results:
        for issue in data.get("issues", []):
            iid = issue.get("id")
            issue["_matched_searches"] = seen.get(iid, {}).get("_matched_searches", [term])

    # Write index
    index_html = build_index(results, unique_issues, generated_at)
    index_path = os.path.join(out_dir, "index.html")
    with open(index_path, "w", encoding="utf-8") as f:
        f.write(index_html)

    return index_path


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Query tracker.ceph.com (Redmine)")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--issue", type=int, help="Fetch a specific issue by ID (terminal only)")
    group.add_argument(
        "--search",
        type=str,
        nargs="+",
        metavar="TERM",
        help="One or more search terms (each searched independently)",
    )
    parser.add_argument(
        "--status",
        choices=["open", "closed", "all"],
        default="all",
        help="Filter by issue status (default: all)",
    )
    parser.add_argument("--limit", type=int, default=25, help="Max results per search")
    args = parser.parse_args()

    status_id = STATUS_MAP[args.status]

    if args.issue:
        print(f"Fetching issue #{args.issue} from tracker.ceph.com …")
        data = fetch_issue(args.issue)
        print_issue_detail(data)
        return

    terms = args.search if args.search else DEFAULT_SEARCHES
    print(f"Running {len(terms)} search(es) on tracker.ceph.com [{args.status}] …")

    results: list[tuple[str, dict]] = []
    for term in terms:
        print(f"  → \"{term}\"", end=" ", flush=True)
        try:
            data = search_issues(term, status=status_id, limit=args.limit)
            results.append((term, data))
            print(f"({data.get('total_count', 0)} result(s))")
            print_issue_list(data, term)
        except Exception as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            results.append((term, {"issues": [], "total_count": 0}))

    index_path = write_html_output(results, HTML_OUT)
    print(f"\nHTML output written → {HTML_OUT}/")
    print(f"  Open: {index_path}")


if __name__ == "__main__":
    main()
