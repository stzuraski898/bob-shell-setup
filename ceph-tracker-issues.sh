#!/usr/bin/env bash
# ceph-tracker-issues.sh
# Fetches all open issues assigned to you on tracker.ceph.com (Redmine)
# and writes them to a styled, readable HTML file.
#
# Required environment variables (set one auth method):
#   CEPH_TRACKER_API_KEY   — Redmine API key (preferred; find at
#                            https://tracker.ceph.com/my/account)
#   CEPH_TRACKER_USERNAME  — Redmine username  (used only if no API key)
#   CEPH_TRACKER_PASSWORD  — Redmine password  (used only if no API key)
#
# Optional:
#   CEPH_TRACKER_OUTPUT_DIR — directory to write the file into (default: ./ceph-tracker)
#
# Flags:
#   --open-prs   Open all PR URLs in a new Chrome window (one tab per PR)

set -euo pipefail

# ── Flag parsing ──────────────────────────────────────────────────────────────
OPEN_PRS=false
for arg in "$@"; do
    case "$arg" in
        --open-prs) OPEN_PRS=true ;;
        *) echo "Unknown flag: $arg" >&2; exit 1 ;;
    esac
done

# ── Config ────────────────────────────────────────────────────────────────────
BASE_URL="https://tracker.ceph.com"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${CEPH_TRACKER_OUTPUT_DIR:-${SCRIPT_DIR}/ceph-tracker}"
TIMESTAMP_FMT="%B %-d %I:%M %p %Z"
TIMESTAMP_FILE="$OUTPUT_DIR/.last_run_ts"

# ── Dependency check ──────────────────────────────────────────────────────────
for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' is required but not installed." >&2
        exit 1
    fi
done

# ── Auth ──────────────────────────────────────────────────────────────────────
if [[ -n "${CEPH_TRACKER_API_KEY:-}" ]]; then
    AUTH_HEADER="X-Redmine-API-Key: ${CEPH_TRACKER_API_KEY}"
    AUTH_CURL_OPTS=(-H "$AUTH_HEADER")
elif [[ -n "${CEPH_TRACKER_USERNAME:-}" && -n "${CEPH_TRACKER_PASSWORD:-}" ]]; then
    AUTH_CURL_OPTS=(-u "${CEPH_TRACKER_USERNAME}:${CEPH_TRACKER_PASSWORD}")
else
    echo "ERROR: Set CEPH_TRACKER_API_KEY, or both CEPH_TRACKER_USERNAME and CEPH_TRACKER_PASSWORD." >&2
    exit 1
fi

# ── Resolve current username from the API ─────────────────────────────────────
echo "Fetching current user info..."
USER_JSON=$(curl -sf --tlsv1.2 "${AUTH_CURL_OPTS[@]}" \
    -H "Content-Type: application/json" \
    "${BASE_URL}/users/current.json") || {
    echo "ERROR: Failed to authenticate with tracker.ceph.com. Check your credentials." >&2
    exit 1
}

USERNAME=$(echo "$USER_JSON" | jq -r '.user.login')
if [[ -z "$USERNAME" || "$USERNAME" == "null" ]]; then
    echo "ERROR: Could not determine username from API response." >&2
    exit 1
fi

echo "Logged in as: $USERNAME"

# ── Output paths ──────────────────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/${USERNAME}-Open-Issues.html"

# ── Load last-run timestamp (for ***NEW*** detection) ─────────────────────────
LAST_RUN_TS=""
if [[ -f "$TIMESTAMP_FILE" ]]; then
    LAST_RUN_TS=$(cat "$TIMESTAMP_FILE")
fi
NOW_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
NOW_DISPLAY=$(date +"$TIMESTAMP_FMT")

# ── Helper: convert ISO8601 timestamp to human-readable format ────────────────
fmt_ts() {
    local iso="$1"
    [[ -z "$iso" ]] && return
    date -d "$iso" +"$TIMESTAMP_FMT" 2>/dev/null || echo "$iso"
}

# ── Fetch all open issues assigned to the current user ────────────────────────
echo "Fetching open issues..."

ISSUES_JSON="[]"
OFFSET=0
LIMIT=100

while true; do
    PAGE=$(curl -sf --tlsv1.2 "${AUTH_CURL_OPTS[@]}" \
        -H "Content-Type: application/json" \
        "${BASE_URL}/issues.json?assigned_to_id=me&status_id=open&limit=${LIMIT}&offset=${OFFSET}") || {
        echo "ERROR: Failed to fetch issues from tracker.ceph.com." >&2
        exit 1
    }

    PAGE_COUNT=$(echo "$PAGE" | jq '.issues | length')
    ISSUES_JSON=$(echo "$ISSUES_JSON $PAGE" | jq -s '.[0] + .[1].issues')

    if (( PAGE_COUNT < LIMIT )); then
        break
    fi
    (( OFFSET += LIMIT ))
done

TOTAL=$(echo "$ISSUES_JSON" | jq 'length')
echo "Found $TOTAL open issue(s)."

# ── Helper: fetch last journal (comment) timestamp for an issue ───────────────
get_last_comment_ts() {
    local issue_id="$1"
    local detail
    detail=$(curl -sf --tlsv1.2 "${AUTH_CURL_OPTS[@]}" \
        -H "Content-Type: application/json" \
        "${BASE_URL}/issues/${issue_id}.json?include=journals") || echo "{}"

    echo "$detail" | jq -r '
        [ .issue.journals[]?
          | select((.notes // "") != "")
          | .created_on ]
        | sort | last // ""'
}

# ── Helper: fetch PR updated_at timestamp from GitHub (no auth required) ──────
get_pr_ts() {
    local pr_num="$1"
    curl -sf --tlsv1.2 \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/ceph/ceph/pulls/${pr_num}" \
        2>/dev/null | jq -r '.updated_at // ""'
}

# ── Helper: check if a timestamp is newer than last run ───────────────────────
is_newer_than_last_run() {
    local ts="$1"
    if [[ -z "$LAST_RUN_TS" || -z "$ts" ]]; then
        return 1
    fi
    if [[ "$ts" > "$LAST_RUN_TS" ]]; then
        return 0
    fi
    return 1
}

# ── Process & enrich issues ───────────────────────────────────────────────────
echo "Processing issue details and timestamps..."

PR_URL_FILE=$(mktemp)
ENRICHED_TMP=$(mktemp)
trap 'rm -f "$PR_URL_FILE" "$ENRICHED_TMP"' EXIT

echo "[]" > "$ENRICHED_TMP"

if (( TOTAL > 0 )); then
    while IFS= read -r issue; do
        ISSUE_ID=$(echo "$issue"    | jq -r '.id')
        ISSUE_TITLE=$(echo "$issue" | jq -r '.subject')
        UPDATED_ON=$(echo "$issue"  | jq -r '.updated_on // empty')
        ISSUE_URL="${BASE_URL}/issues/${ISSUE_ID}"

        # Fetch last comment timestamp from Redmine journals
        LAST_COMMENT=$(get_last_comment_ts "$ISSUE_ID")

        # Pull request ID is stored in custom field "Pull request ID" (id 21)
        PR_NUM=$(echo "$issue" | jq -r '
            (.custom_fields // [])[]
            | select(.id == 21)
            | .value // ""' 2>/dev/null | head -1)

        PR_URL=""
        PR_TS=""
        PR_IS_NEW=false
        if [[ -n "$PR_NUM" && "$PR_NUM" != "null" && "$PR_NUM" =~ ^[0-9]+$ ]]; then
            PR_URL="https://github.com/ceph/ceph/pull/${PR_NUM}"
            PR_TS=$(get_pr_ts "$PR_NUM")
            if is_newer_than_last_run "$PR_TS"; then
                PR_IS_NEW=true
            fi
            echo "$PR_URL" >> "$PR_URL_FILE"
        fi

        # Determine if tracker issue has new updates
        TRACKER_IS_NEW=false
        if is_newer_than_last_run "$UPDATED_ON" || is_newer_than_last_run "$LAST_COMMENT"; then
            TRACKER_IS_NEW=true
        fi

        # Overall item has new update if tracker or PR has new updates
        ANY_IS_NEW=false
        if [[ "$TRACKER_IS_NEW" == true || "$PR_IS_NEW" == true ]]; then
            ANY_IS_NEW=true
        fi

        # Latest activity timestamp across tracker update, tracker comment, and PR update
        LATEST_TS="$UPDATED_ON"
        if [[ "$LAST_COMMENT" > "$LATEST_TS" ]]; then
            LATEST_TS="$LAST_COMMENT"
        fi
        if [[ "$PR_TS" > "$LATEST_TS" ]]; then
            LATEST_TS="$PR_TS"
        fi

        LAST_COMMENT_FMT="$(fmt_ts "$LAST_COMMENT")"
        PR_TS_FMT="$(fmt_ts "$PR_TS")"
        UPDATED_ON_FMT="$(fmt_ts "$UPDATED_ON")"

        # Append enriched item to JSON array
        jq --arg id "$ISSUE_ID" \
           --arg title "$ISSUE_TITLE" \
           --arg url "$ISSUE_URL" \
           --arg updated_on "$UPDATED_ON" \
           --arg updated_on_fmt "$UPDATED_ON_FMT" \
           --arg last_comment "$LAST_COMMENT" \
           --arg last_comment_fmt "$LAST_COMMENT_FMT" \
           --arg pr_num "$PR_NUM" \
           --arg pr_url "$PR_URL" \
           --arg pr_ts "$PR_TS" \
           --arg pr_ts_fmt "$PR_TS_FMT" \
           --arg latest_ts "$LATEST_TS" \
           --argjson tracker_is_new "$TRACKER_IS_NEW" \
           --argjson pr_is_new "$PR_IS_NEW" \
           --argjson any_is_new "$ANY_IS_NEW" \
           '. += [{
               id: $id,
               title: $title,
               url: $url,
               updated_on: $updated_on,
               updated_on_fmt: $updated_on_fmt,
               last_comment: $last_comment,
               last_comment_fmt: $last_comment_fmt,
               pr_num: $pr_num,
               pr_url: $pr_url,
               pr_ts: $pr_ts,
               pr_ts_fmt: $pr_ts_fmt,
               latest_ts: $latest_ts,
               tracker_is_new: $tracker_is_new,
               pr_is_new: $pr_is_new,
               any_is_new: $any_is_new
           }]' "$ENRICHED_TMP" > "${ENRICHED_TMP}.next" && mv "${ENRICHED_TMP}.next" "$ENRICHED_TMP"

    done < <(echo "$ISSUES_JSON" | jq -c '.[]')
fi

# ── Order trackers by last update time (descending) ───────────────────────────
SORTED_ISSUES=$(jq 'sort_by(.latest_ts) | reverse' "$ENRICHED_TMP")

# ── Write HTML file ───────────────────────────────────────────────────────────
escape_html() {
    local s="$1"
    # Note: escape & first so we do not double-escape &lt; / &gt; / &quot; / &#39;
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    s="${s//\"/&quot;}"
    s="${s//\'/&#39;}"
    printf '%s' "$s"
}

{
    cat << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Ceph Tracker Issues</title>
<style>
    :root {
        --bg: #0f172a;
        --surface: #1e293b;
        --surface-hover: #273549;
        --border: #334155;
        --text-main: #f8fafc;
        --text-muted: #94a3b8;
        --accent: #38bdf8;
        --accent-glow: rgba(56, 189, 248, 0.15);
        --badge-bg: #dc2626;
        --badge-text: #ffffff;
        --link: #60a5fa;
        --tag-bg: #1e1b4b;
        --tag-border: #4338ca;
        --tag-text: #c7d2fe;
    }

    * {
        box-sizing: border-box;
        margin: 0;
        padding: 0;
    }

    body {
        background-color: var(--bg);
        color: var(--text-main);
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
        line-height: 1.6;
        padding: 2rem 1rem;
    }

    .container {
        max-width: 900px;
        margin: 0 auto;
    }

    header {
        border-bottom: 1px solid var(--border);
        padding-bottom: 1.5rem;
        margin-bottom: 2rem;
    }

    h1 {
        font-size: 1.75rem;
        font-weight: 700;
        color: var(--text-main);
        display: flex;
        align-items: center;
        gap: 0.75rem;
        flex-wrap: wrap;
    }

    .meta-bar {
        margin-top: 0.5rem;
        color: var(--text-muted);
        font-size: 0.95rem;
        display: flex;
        gap: 1.5rem;
        flex-wrap: wrap;
    }

    .meta-bar span {
        display: inline-flex;
        align-items: center;
    }

    .issue-list {
        display: flex;
        flex-direction: column;
        gap: 1.25rem;
    }

    .issue-card {
        background: var(--surface);
        border: 1px solid var(--border);
        border-radius: 8px;
        padding: 1.25rem;
        transition: border-color 0.15s ease, transform 0.15s ease;
    }

    .issue-card:hover {
        border-color: #475569;
        background: var(--surface-hover);
    }

    .issue-card.has-new {
        border-color: rgba(239, 68, 68, 0.6);
        box-shadow: 0 0 12px rgba(239, 68, 68, 0.12);
    }

    .issue-header {
        margin-bottom: 0.75rem;
    }

    .issue-title {
        font-size: 1.1rem;
        font-weight: 600;
        color: var(--text-main);
        line-height: 1.4;
        display: inline;
    }

    .badge-new {
        background-color: var(--badge-bg);
        color: var(--badge-text);
        font-size: 0.75rem;
        font-weight: 700;
        letter-spacing: 0.05em;
        padding: 0.15rem 0.5rem;
        border-radius: 4px;
        white-space: nowrap;
        display: inline-block;
        vertical-align: middle;
        margin-left: 0.5rem;
    }

    .issue-details {
        list-style: none;
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
        font-size: 0.925rem;
    }

    .detail-row {
        display: flex;
        align-items: baseline;
        gap: 0.5rem;
        flex-wrap: wrap;
    }

    .label {
        color: var(--text-muted);
        font-weight: 600;
        min-width: 70px;
    }

    a {
        color: var(--link);
        text-decoration: none;
        font-weight: 500;
    }

    a:hover {
        text-decoration: underline;
    }

    .timestamp {
        color: var(--text-muted);
        font-size: 0.85rem;
    }

    .badge-inline-new {
        color: #f87171;
        font-weight: 700;
        font-size: 0.8rem;
        margin-left: 0.4rem;
    }

    .tabs {
        display: flex;
        gap: 0.5rem;
        margin-bottom: 1.5rem;
    }

    .tab-btn {
        background: var(--surface);
        border: 1px solid var(--border);
        border-radius: 6px;
        color: var(--text-muted);
        cursor: pointer;
        font-size: 0.9rem;
        font-weight: 600;
        padding: 0.4rem 1rem;
    }

    .tab-btn:hover {
        border-color: #475569;
        color: var(--text-main);
    }

    .tab-btn.active {
        background: var(--accent-glow);
        border-color: var(--accent);
        color: var(--accent);
    }

    .issue-card[hidden] {
        display: none;
    }

    .empty-state {
        text-align: center;
        padding: 3rem;
        color: var(--text-muted);
        background: var(--surface);
        border-radius: 8px;
        border: 1px dashed var(--border);
    }

    footer {
        margin-top: 3rem;
        padding-top: 1.25rem;
        border-top: 1px solid var(--border);
        text-align: center;
        color: var(--text-muted);
        font-size: 0.85rem;
    }
</style>
</head>
<body>
<div class="container">
EOF

    SAFE_USER=$(escape_html "$USERNAME")
    SAFE_NOW=$(escape_html "$NOW_DISPLAY")
    echo "  <header>"
    echo "    <h1>${SAFE_USER} &mdash; Open Ceph Tracker Issues</h1>"
    echo "    <div class=\"meta-bar\">"
    echo "      <span><strong>Generated:</strong>&nbsp;${SAFE_NOW}</span>"
    echo "      <span><strong>Open Issues:</strong>&nbsp;${TOTAL}</span>"
    echo "    </div>"
    echo "  </header>"

    echo "  <div class=\"tabs\">"
    echo "    <button class=\"tab-btn active\" data-tab=\"all\">All <span id=\"count-all\">${TOTAL}</span></button>"
    NEW_COUNT=$(echo "$SORTED_ISSUES" | jq '[.[] | select(.any_is_new == true)] | length')
    STALE_COUNT=$(echo "$SORTED_ISSUES" | jq '[.[] | select(.any_is_new == false)] | length')
    echo "    <button class=\"tab-btn\" data-tab=\"new\">New <span id=\"count-new\">${NEW_COUNT}</span></button>"
    echo "    <button class=\"tab-btn\" data-tab=\"stale\">Stale <span id=\"count-stale\">${STALE_COUNT}</span></button>"
    echo "  </div>"

    echo "  <main class=\"issue-list\">"

    if (( TOTAL == 0 )); then
        echo "    <div class=\"empty-state\">No open issues found.</div>"
    else
        echo "$SORTED_ISSUES" | jq -c '.[]' | while IFS= read -r item; do
            ID=$(echo "$item" | jq -r '.id')
            RAW_TITLE=$(echo "$item" | jq -r '.title')
            TITLE="$(escape_html "$RAW_TITLE")"
            URL=$(echo "$item" | jq -r '.url')
            RAW_LAST_COMMENT_FMT=$(echo "$item" | jq -r '.last_comment_fmt // ""')
            LAST_COMMENT_FMT="$(escape_html "$RAW_LAST_COMMENT_FMT")"
            PR_NUM=$(echo "$item" | jq -r '.pr_num // ""')
            PR_URL=$(echo "$item" | jq -r '.pr_url // ""')
            RAW_PR_TS_FMT=$(echo "$item" | jq -r '.pr_ts_fmt // ""')
            PR_TS_FMT="$(escape_html "$RAW_PR_TS_FMT")"
            TRACKER_IS_NEW=$(echo "$item" | jq -r '.tracker_is_new')
            PR_IS_NEW=$(echo "$item" | jq -r '.pr_is_new')
            ANY_IS_NEW=$(echo "$item" | jq -r '.any_is_new')

            CARD_CLASS="issue-card"
            CARD_TAB="stale"
            if [[ "$ANY_IS_NEW" == "true" ]]; then
                CARD_CLASS="issue-card has-new"
                CARD_TAB="new"
            fi

            cat << ITEM_EOF
    <div class="${CARD_CLASS}" data-tab="${CARD_TAB}">
      <div class="issue-header">
        <h2 class="issue-title">${TITLE}</h2>$([[ "$ANY_IS_NEW" == "true" ]] && echo " <span class=\"badge-new\">***NEW***</span>")
      </div>
      <ul class="issue-details">
        <li class="detail-row">
          <span class="label">Tracker:</span>
          <a href="${URL}" target="_blank">#${ID}</a>$([[ -n "$LAST_COMMENT_FMT" ]] && echo " <span class=\"timestamp\">&mdash; last comment: ${LAST_COMMENT_FMT}</span>")$([[ "$TRACKER_IS_NEW" == "true" ]] && echo " <span class=\"badge-inline-new\">***NEW***</span>")
        </li>
ITEM_EOF

            if [[ -n "$PR_NUM" && "$PR_NUM" != "null" ]]; then
                cat << PR_EOF
        <li class="detail-row">
          <span class="label">PR:</span>
          <a href="${PR_URL}" target="_blank">#${PR_NUM}</a>$([[ -n "$PR_TS_FMT" ]] && echo " <span class=\"timestamp\">&mdash; last comment / update: ${PR_TS_FMT}</span>")$([[ "$PR_IS_NEW" == "true" ]] && echo " <span class=\"badge-inline-new\">***NEW***</span>")
        </li>
PR_EOF
            fi

            cat << ITEM_END_EOF
      </ul>
    </div>
ITEM_END_EOF
        done
    fi

    echo "  </main>"
    echo "  <footer>"
    echo "    Generated by <code>ceph-tracker-issues.sh</code>"
    echo "  </footer>"
    echo "</div>"
    cat << 'SCRIPT_EOF'
<script>
  document.querySelectorAll('.tab-btn').forEach(function(btn) {
    btn.addEventListener('click', function() {
      var tab = this.dataset.tab;
      document.querySelectorAll('.tab-btn').forEach(function(b) { b.classList.remove('active'); });
      this.classList.add('active');
      document.querySelectorAll('.issue-card').forEach(function(card) {
        if (tab === 'all' || card.dataset.tab === tab) {
          card.removeAttribute('hidden');
        } else {
          card.setAttribute('hidden', '');
        }
      });
    });
  });
</script>
SCRIPT_EOF
    echo "</body>"
    echo "</html>"
} > "$OUTPUT_FILE"

# ── Save this run's timestamp for next time ───────────────────────────────────
echo "$NOW_TS" > "$TIMESTAMP_FILE"

echo "Done. Report written to: $OUTPUT_FILE"

# ── Open PRs in Chrome if --open-prs was passed ───────────────────────────────
if [[ "$OPEN_PRS" == true ]]; then
    mapfile -t PR_URLS < "$PR_URL_FILE"
    if (( ${#PR_URLS[@]} == 0 )); then
        echo "No PRs found to open."
    else
        echo "Opening ${#PR_URLS[@]} PR(s) in a new Chrome window..."
        # Detect Chrome binary (handles google-chrome, google-chrome-stable, chromium, chromium-browser)
        CHROME_BIN=""
        for candidate in google-chrome google-chrome-stable chromium chromium-browser; do
            if command -v "$candidate" &>/dev/null; then
                CHROME_BIN="$candidate"
                break
            fi
        done
        if [[ -z "$CHROME_BIN" ]]; then
            echo "ERROR: Could not find Chrome or Chromium. Install google-chrome or chromium." >&2
            exit 1
        fi
        "$CHROME_BIN" --new-window "${PR_URLS[@]}" &
        echo "Chrome launched."
    fi
fi
