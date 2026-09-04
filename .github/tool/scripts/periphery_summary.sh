#!/usr/bin/env bash
set -euo pipefail

# Summarize Periphery dead-code findings from its JSON report.
#
# Usage: periphery_summary.sh [REPORT]   # default: build/reports/periphery.json
#
# Emits, e.g.:
#   Dead code: 27 unused declaration(s)
#     unused class x8
#     unused function x11
#
# Exit code is always 0 -- the CI stage decides whether findings are fatal.

REPORT="${1:-build/reports/periphery.json}"

if [[ ! -f "$REPORT" ]]; then
  echo "Dead code: no report found at ${REPORT}"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Dead code: report present but jq unavailable"
  exit 0
fi

COUNT=$(jq 'length' "$REPORT" 2>/dev/null || echo 0)

echo "Dead code: ${COUNT} unused declaration(s)"

if [[ "$COUNT" -gt 0 ]]; then
  # Group by what Periphery calls the declaration kind.
  jq -r '.[] | "\(.kind // "unknown")"' "$REPORT" 2>/dev/null \
    | sed 's/^var\..*/property/; s/^function\..*/function/; s/^class$/class/; s/^struct$/struct/; s/^protocol$/protocol/; s/^enum$/enum/' \
    | sort | uniq -c | sort -rn | head -10 \
    | awk '{ printf "    %s x%s\n", $2, $1 }' || true

  echo "  first 15 findings:"
  jq -r '.[] | "    \(.location // "?"): \(.name // "?") (\(.kind // "?"))"' "$REPORT" 2>/dev/null \
    | head -15 || true
fi
