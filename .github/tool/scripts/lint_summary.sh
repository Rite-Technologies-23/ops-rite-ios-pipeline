#!/usr/bin/env bash
set -euo pipefail

# Summarize SwiftLint findings from its JSON report.
#
# Usage: lint_summary.sh [REPORT]    # default: build/reports/swiftlint.json
#
# Emits, e.g.:
#   SwiftLint: 3 error(s), 41 warning(s)
#     force_unwrapping x12
#     line_length x9

REPORT="${1:-build/reports/swiftlint.json}"

if [[ ! -f "$REPORT" ]]; then
  echo "SwiftLint: no report found at ${REPORT}"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "SwiftLint: report present but jq unavailable"
  exit 0
fi

# An empty run produces `[]`, which is valid and means zero findings.
ERRORS=$(jq '[.[] | select(.severity == "Error")]   | length' "$REPORT" 2>/dev/null || echo 0)
WARNINGS=$(jq '[.[] | select(.severity == "Warning")] | length' "$REPORT" 2>/dev/null || echo 0)

echo "SwiftLint: ${ERRORS} error(s), ${WARNINGS} warning(s)"

TOTAL=$((ERRORS + WARNINGS))
if [[ "$TOTAL" -gt 0 ]]; then
  jq -r '.[].rule_id' "$REPORT" 2>/dev/null \
    | sort | uniq -c | sort -rn | head -10 \
    | awk '{ printf "    %s x%s\n", $2, $1 }' || true
fi
