#!/usr/bin/env bash
set -euo pipefail

# Compose the GitHub Actions job summary for an iOS CI run.
#
# Usage: generate_summary_md.sh [REPORTS_DIR]
#   REPORTS_DIR is the directory the summary job downloaded all artifacts into.
#
# Job results and coverage arrive via environment variables set by the workflow:
#   QUALITY_RESULT SECURITY_RESULT DEAD_CODE_RESULT ANALYZE_RESULT
#   TEST_RESULT BUILD_RESULT
#   COVERAGE_PERCENT COVERAGE_THRESHOLD

REPORTS_DIR="${1:-reports}"
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/tmp/job-summary.md}"

icon () {
  case "${1:-}" in
    success)   echo "PASS" ;;
    failure)   echo "FAIL" ;;
    cancelled) echo "CANCELLED" ;;
    skipped)   echo "skipped" ;;
    *)         echo "${1:-n/a}" ;;
  esac
}

read_line () {
  local pattern="$1" fallback="$2" f
  f=$(find "$REPORTS_DIR" -name "$pattern" 2>/dev/null | head -1 || true)
  if [[ -n "$f" && -f "$f" ]]; then
    head -1 "$f"
  else
    echo "$fallback"
  fi
}

LINT_TXT=$(read_line "swiftlint-summary.txt"  "SwiftLint: no report")
FORMAT_TXT=$(read_line "swiftformat-summary.txt" "SwiftFormat: no report")
TESTS_TXT=$(read_line "test-summary.txt"      "Tests: no report")
DEAD_TXT=$(read_line "periphery-summary.txt"  "Dead code: no report")
ANALYZE_TXT=$(read_line "analyze-summary.txt" "Clang analyzer: no report")

# ---- coverage ----
COVERAGE_LINE="Coverage: n/a"
if [[ -n "${COVERAGE_PERCENT:-}" ]]; then
  if [[ "${COVERAGE_THRESHOLD:-0}" != "0" ]]; then
    COVERAGE_LINE="Coverage: ${COVERAGE_PERCENT}% line (threshold ${COVERAGE_THRESHOLD}%)"
  else
    COVERAGE_LINE="Coverage: ${COVERAGE_PERCENT}% line (ungated)"
  fi
fi

# ---- security ----
SEMGREP_TXT="Semgrep: no report"
SEMGREP_JSON=$(find "$REPORTS_DIR" -name "semgrep.json" 2>/dev/null | head -1 || true)
if [[ -n "$SEMGREP_JSON" && -f "$SEMGREP_JSON" ]] && command -v jq >/dev/null 2>&1; then
  E=$(jq '[.results[]? | select(.extra.severity == "ERROR")]   | length' "$SEMGREP_JSON" 2>/dev/null || echo 0)
  W=$(jq '[.results[]? | select(.extra.severity == "WARNING")] | length' "$SEMGREP_JSON" 2>/dev/null || echo 0)
  SEMGREP_TXT="Semgrep: ${E} error(s), ${W} warning(s)"
fi

GITLEAKS_TXT="Secrets: no report"
GITLEAKS_SARIF=$(find "$REPORTS_DIR" -name "gitleaks.sarif" 2>/dev/null | head -1 || true)
if [[ -n "$GITLEAKS_SARIF" && -f "$GITLEAKS_SARIF" ]] && command -v jq >/dev/null 2>&1; then
  G=$(jq '[.runs[]?.results[]?] | length' "$GITLEAKS_SARIF" 2>/dev/null || echo 0)
  GITLEAKS_TXT="Secrets: ${G} leak(s) detected"
fi

TRIVY_TXT="Dependencies: no report"
TRIVY_JSON=$(find "$REPORTS_DIR" -name "trivy.json" 2>/dev/null | head -1 || true)
if [[ -n "$TRIVY_JSON" && -f "$TRIVY_JSON" ]] && command -v jq >/dev/null 2>&1; then
  C=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "$TRIVY_JSON" 2>/dev/null || echo 0)
  H=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")]     | length' "$TRIVY_JSON" 2>/dev/null || echo 0)
  TRIVY_TXT="Dependencies: ${C} critical, ${H} high CVE(s)"
fi

{
  echo "## iOS CI Summary"
  echo
  echo "| Stage | Result | Detail |"
  echo "|---|---|---|"
  echo "| Lint | $(icon "${QUALITY_RESULT:-}") | ${LINT_TXT} |"
  echo "| Format | $(icon "${QUALITY_RESULT:-}") | ${FORMAT_TXT} |"
  echo "| Security | $(icon "${SECURITY_RESULT:-}") | ${SEMGREP_TXT}; ${GITLEAKS_TXT} |"
  echo "| Dependencies | $(icon "${SECURITY_RESULT:-}") | ${TRIVY_TXT} |"
  echo "| Clang Analyzer | $(icon "${ANALYZE_RESULT:-}") | ${ANALYZE_TXT} |"
  echo "| Dead Code | $(icon "${DEAD_CODE_RESULT:-}") | ${DEAD_TXT} |"
  echo "| Tests | $(icon "${TEST_RESULT:-}") | ${TESTS_TXT} |"
  echo "| Coverage | $(icon "${TEST_RESULT:-}") | ${COVERAGE_LINE} |"
  echo "| Archive | $(icon "${BUILD_RESULT:-}") | unsigned .xcarchive |"
  echo

  for f in "swiftlint-summary.txt" "periphery-summary.txt" "test-summary.txt" "coverage-summary.txt"; do
    path=$(find "$REPORTS_DIR" -name "$f" 2>/dev/null | head -1 || true)
    if [[ -n "$path" && -f "$path" && $(wc -l < "$path") -gt 1 ]]; then
      echo "<details><summary>${f%.txt}</summary>"
      echo
      echo '```'
      cat "$path"
      echo '```'
      echo
      echo "</details>"
      echo
    fi
  done

  echo "Full reports are attached as workflow artifacts."
} >> "$SUMMARY_FILE"

echo "Summary written to ${SUMMARY_FILE}"
