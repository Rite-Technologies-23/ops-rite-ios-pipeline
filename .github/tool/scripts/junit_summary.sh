#!/usr/bin/env bash
set -euo pipefail

# Summarize test results from the JUnit XML that xcbeautify emits during the
# xcodebuild test run.
#
# Usage: junit_summary.sh [ROOT]     # default: current directory
#
# Emits, e.g.:
#   Tests: total=120, passed=118, failed=2, skipped=0
#
# xcbeautify's --report junit is used in preference to parsing the .xcresult
# with xcresulttool, because xcresulttool's JSON schema changed incompatibly in
# Xcode 16 and pinning to either shape breaks on the other.

ROOT="${1:-.}"

# mapfile/readarray and `local -n` namerefs need bash 4+; macOS ships /bin/bash
# 3.2 (Apple won't distribute GPLv3 bash), so lines are read into an array by
# hand with a plain while-read loop instead.
FILES=()
while IFS= read -r line; do
  FILES+=("$line")
done < <(find "$ROOT" \
  -name '*.junit' -o -name 'junit.xml' -o -name 'report.junit' \
  -not -path '*/.pipeline/*' 2>/dev/null || true)

if [[ ${#FILES[@]} -eq 0 ]]; then
  while IFS= read -r line; do
    FILES+=("$line")
  done < <(find "$ROOT" -path '*reports*' -name '*.xml' \
    -not -path '*/.pipeline/*' 2>/dev/null || true)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "Tests: no JUnit report found under ${ROOT}"
  exit 0
fi

TOTAL=0
FAIL=0
SKIP=0

for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue
  grep -q '<testsuite' "$f" 2>/dev/null || continue

  # Sum across every <testsuite> element, not just the first: xcbeautify emits
  # one suite per test class.
  while IFS= read -r header; do
    attr () {
      echo "$header" | grep -oE "$1=\"[0-9]+\"" | head -1 | grep -oE '[0-9]+' || true
    }
    t=$(attr tests);     t=${t:-0}
    f1=$(attr failures); f1=${f1:-0}
    e1=$(attr errors);   e1=${e1:-0}
    s=$(attr skipped);   s=${s:-0}

    TOTAL=$((TOTAL + t))
    FAIL=$((FAIL + f1 + e1))
    SKIP=$((SKIP + s))
  done < <(grep -o '<testsuite [^>]*>' "$f" 2>/dev/null || true)
done

PASSED=$((TOTAL - FAIL - SKIP))
echo "Tests: total=$TOTAL, passed=$PASSED, failed=$FAIL, skipped=$SKIP"

if [[ "$FAIL" -gt 0 ]]; then
  echo "  failures:"
  for f in "${FILES[@]}"; do
    [[ -f "$f" ]] || continue
    # Put every tag on its own line first. xcbeautify emits a whole testcase
    # (including its <failure/> child) on a single line, so a state machine
    # over raw lines cannot tell a pass from a failure.
    sed 's/</\n</g' "$f" 2>/dev/null | awk '
      /^<testcase/ {
        current = $0
        # A self-closing <testcase ... /> has no children, so it passed.
        if ($0 ~ /\/>[[:space:]]*$/) { current = "" }
        next
      }
      /^<(failure|error)[ >\/]/ {
        if (current != "") {
          cls = current
          sub(/.*classname="/, "", cls); sub(/".*/, "", cls)
          nm = current
          sub(/.* name="/, "", nm); sub(/".*/, "", nm)
          print "    " cls "." nm
          current = ""
        }
      }
    ' || true
  done | sort -u | head -20
fi
