#!/usr/bin/env bash
# query_ceph_tracker.sh — search tracker.ceph.com (Redmine) for issues
# related to device life_expectancy validation
#
# Usage:
#   ./query_ceph_tracker.sh [search_term]
#
# Example:
#   ./query_ceph_tracker.sh "life_expectancy"
#   ./query_ceph_tracker.sh "set-life-expectancy"

set -euo pipefail

BASE_URL="https://tracker.ceph.com"
SEARCH_TERM="${1:-life_expectancy}"

# URL-encode the search term
ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${SEARCH_TERM}'))")

echo "=== Searching tracker.ceph.com for: '${SEARCH_TERM}' ==="
echo

# Redmine search API — returns issues matching the query
# limit=25 is the max per page; status_id=* includes open+closed
RESPONSE=$(curl -sf \
  "${BASE_URL}/issues.json?subject=~${ENCODED}&limit=25&status_id=*" \
  -H "Content-Type: application/json")

TOTAL=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('total_count', 0))")
echo "Total matching issues: ${TOTAL}"
echo "---"

echo "$RESPONSE" | python3 - <<'PYEOF'
import sys, json

data = json.load(sys.stdin)
issues = data.get("issues", [])

if not issues:
    print("No issues found.")
    sys.exit(0)

for issue in issues:
    status   = issue.get("status", {}).get("name", "?")
    priority = issue.get("priority", {}).get("name", "?")
    tracker  = issue.get("tracker", {}).get("name", "?")
    subject  = issue.get("subject", "")
    iid      = issue.get("id")
    updated  = issue.get("updated_on", "")[:10]

    print(f"  #{iid:6}  [{status:<12}] [{priority:<8}] {subject}")
    print(f"           Type: {tracker}  |  Updated: {updated}")
    print(f"           URL : https://tracker.ceph.com/issues/{iid}")
    print()
PYEOF
