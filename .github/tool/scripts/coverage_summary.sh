#!/usr/bin/env bash
set -euo pipefail

# Compute line coverage from an .xcresult bundle and optionally gate on it.
#
# Usage:
#   coverage_summary.sh --result path/to/TestResults.xcresult \
#                       [--threshold 75] \
#                       [--exclude-pattern 'Tests|UITests'] \
#                       [--include-pattern 'MyApp']
#
# Writes coverage_percent / covered_lines / executable_lines to GITHUB_OUTPUT
# when it is set, prints a one-line summary, and exits 1 if the threshold is
# not met.
#
# Why JSON rather than the plain-text report: the text layout has shifted
# between Xcode releases and column-position parsing (awk '{print $(NF-1)}')
# silently picks up the wrong figure when a target name contains a space.
# xccov's JSON output is stable.
#
# NOTE: xccov reports LINE coverage only. There is no branch coverage in an
# .xcresult -- that is a genuine platform gap, not an omission here.

RESULT=""
THRESHOLD="0"
EXCLUDE_PATTERN='([Tt]ests?|UITests|Mock|Fixture)'
INCLUDE_PATTERN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --result)          RESULT="${2:-}";          shift 2 ;;
    --threshold)       THRESHOLD="${2:-0}";      shift 2 ;;
    --exclude-pattern) EXCLUDE_PATTERN="${2:-}"; shift 2 ;;
    --include-pattern) INCLUDE_PATTERN="${2:-}"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$RESULT" || ! -d "$RESULT" ]]; then
  echo "::error::xcresult bundle not found at '${RESULT}'"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "::error::jq is required to parse the coverage report."
  exit 1
fi

JSON=$(xcrun xccov view --report --json "$RESULT" 2>/dev/null || true)

if [[ -z "$JSON" ]]; then
  echo "::error::xccov produced no report. Was the test run built with -enableCodeCoverage YES?"
  exit 1
fi

# ---------------------------------------------------------------------------
# Aggregate over app targets only.
#
# The bundle also contains coverage for test targets and for every SPM
# dependency compiled into the run. Counting those makes the number meaningless
# -- dependencies drag it up, test targets drag it toward 100%.
# ---------------------------------------------------------------------------
FILTER='.targets[]'

if [[ -n "$INCLUDE_PATTERN" ]]; then
  FILTER="${FILTER} | select(.name | test(\"${INCLUDE_PATTERN}\"))"
fi

if [[ -n "$EXCLUDE_PATTERN" ]]; then
  FILTER="${FILTER} | select(.name | test(\"${EXCLUDE_PATTERN}\") | not)"
fi

# SPM dependencies show up as .framework targets built from checkouts.
FILTER="${FILTER} | select(.name | endswith(\".xctest\") | not)"

TOTALS=$(echo "$JSON" | jq -r "[${FILTER}] | {
  covered:    ([.[].coveredLines]    | add // 0),
  executable: ([.[].executableLines] | add // 0),
  count:      length
} | \"\(.covered) \(.executable) \(.count)\"")

COVERED=$(echo "$TOTALS" | cut -d' ' -f1)
EXECUTABLE=$(echo "$TOTALS" | cut -d' ' -f2)
TARGET_COUNT=$(echo "$TOTALS" | cut -d' ' -f3)

if [[ "$TARGET_COUNT" -eq 0 ]]; then
  echo "::warning::No targets matched the coverage filters. Targets present in the report:"
  echo "$JSON" | jq -r '.targets[].name' | sed 's/^/    /'
  echo "::error::Refusing to report a coverage figure computed from zero targets."
  exit 1
fi

if [[ "$EXECUTABLE" -eq 0 ]]; then
  PCT="0.00"
else
  PCT=$(awk -v c="$COVERED" -v t="$EXECUTABLE" 'BEGIN { printf "%.2f", (c/t)*100 }')
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "coverage_percent=$PCT"
    echo "covered_lines=$COVERED"
    echo "executable_lines=$EXECUTABLE"
  } >> "$GITHUB_OUTPUT"
fi

echo "Coverage: ${PCT}% line (${COVERED}/${EXECUTABLE} lines across ${TARGET_COUNT} target(s), threshold ${THRESHOLD}%)"

# Per-target breakdown -- a single number hides which module is dragging.
echo "$JSON" | jq -r "[${FILTER}] | .[] |
  \"    \(.name): \(((.lineCoverage // 0) * 100) | floor)% (\(.coveredLines)/\(.executableLines))\"" \
  2>/dev/null || true

if awk -v th="$THRESHOLD" 'BEGIN { exit !(th+0 > 0) }'; then
  if awk -v p="$PCT" -v th="$THRESHOLD" 'BEGIN { exit !(p+0 < th+0) }'; then
    echo "::error::Coverage ${PCT}% is below threshold ${THRESHOLD}%"
    exit 1
  fi
fi
