#!/usr/bin/env bash
set -euo pipefail

# Detects the Xcode workspace/project, the scheme to build, and which
# dependency manager the repo uses.
#
# Inputs (env):
#   INPUT_WORKSPACE  explicit .xcworkspace path, or empty to auto-detect
#   INPUT_PROJECT    explicit .xcodeproj path, or empty to auto-detect
#   INPUT_SCHEME     explicit scheme, or empty to auto-detect
#
# Outputs (GITHUB_OUTPUT): type, file, scheme, dependency_manager

INPUT_WORKSPACE="${INPUT_WORKSPACE:-}"
INPUT_PROJECT="${INPUT_PROJECT:-}"
INPUT_SCHEME="${INPUT_SCHEME:-}"

out () { echo "$1=$2" >> "${GITHUB_OUTPUT:-/dev/stdout}"; }

# ---------------------------------------------------------------------------
# 1. Workspace / project
#
# Pods and SPM checkouts contain their own .xcodeproj files, so an unfiltered
# `find` regularly picks the wrong one. Exclude the usual suspects and prefer
# the shallowest match.
# ---------------------------------------------------------------------------
PRUNE=(
  -path '*/Pods/*' -o
  -path '*/.build/*' -o
  -path '*/.pipeline/*' -o
  -path '*/DerivedData/*' -o
  -path '*/Carthage/*' -o
  -path '*/SourcePackages/*' -o
  -path '*/.git/*'
)

find_shallowest () {
  # shellcheck disable=SC2086
  find . \( "${PRUNE[@]}" \) -prune -o -name "$1" -print 2>/dev/null \
    | awk -F/ '{ print NF-1, $0 }' \
    | sort -n \
    | head -1 \
    | cut -d' ' -f2-
}

TYPE=""
FILE=""

if [ -n "$INPUT_WORKSPACE" ] && [ -d "$INPUT_WORKSPACE" ]; then
  TYPE="workspace"; FILE="$INPUT_WORKSPACE"
elif [ -n "$INPUT_PROJECT" ] && [ -d "$INPUT_PROJECT" ]; then
  TYPE="project";   FILE="$INPUT_PROJECT"
else
  WS=$(find_shallowest '*.xcworkspace')
  # An .xcodeproj always contains a project.xcworkspace -- that is not a real
  # workspace and must not be selected.
  if [ -n "$WS" ] && [[ "$WS" != *".xcodeproj/project.xcworkspace" ]]; then
    TYPE="workspace"; FILE="$WS"
  else
    PROJ=$(find_shallowest '*.xcodeproj')
    if [ -n "$PROJ" ]; then
      TYPE="project"; FILE="$PROJ"
    fi
  fi
fi

if [ -z "$TYPE" ] || [ -z "$FILE" ]; then
  echo "::error::No .xcworkspace or .xcodeproj found. Pass workspace: or project: explicitly."
  exit 1
fi

# Normalise ./Foo.xcodeproj -> Foo.xcodeproj
FILE="${FILE#./}"

echo "Detected $TYPE: $FILE"
out type "$TYPE"
out file "$FILE"

# ---------------------------------------------------------------------------
# 2. Scheme
# ---------------------------------------------------------------------------
SCHEME="$INPUT_SCHEME"

if [ -z "$SCHEME" ]; then
  echo "No scheme supplied -- reading the scheme list from $FILE"

  LIST=$(xcodebuild -list -"$TYPE" "$FILE" -json 2>/dev/null || true)

  if [ -n "$LIST" ] && command -v jq >/dev/null 2>&1; then
    KEY="$TYPE"
    SCHEME=$(echo "$LIST" | jq -r ".${KEY}.schemes[]?" 2>/dev/null | head -1 || true)
  fi

  if [ -z "$SCHEME" ]; then
    # Fall back to the plain-text listing.
    SCHEME=$(xcodebuild -list -"$TYPE" "$FILE" 2>/dev/null \
      | awk '/Schemes:/{flag=1; next} /^$/{flag=0} flag' \
      | sed 's/^[[:space:]]*//' \
      | grep -v '^$' \
      | head -1 || true)
  fi
fi

if [ -z "$SCHEME" ]; then
  echo "::error::Could not determine a scheme. Pass scheme: explicitly."
  echo "Available:"
  xcodebuild -list -"$TYPE" "$FILE" 2>&1 | head -40 || true
  exit 1
fi

echo "Using scheme: $SCHEME"
out scheme "$SCHEME"

# ---------------------------------------------------------------------------
# 3. Dependency manager -- drives caching and the CVE scan.
# ---------------------------------------------------------------------------
HAS_SPM="false"
HAS_PODS="false"

if find . \( "${PRUNE[@]}" \) -prune -o -name 'Package.resolved' -print -quit 2>/dev/null | grep -q .; then
  HAS_SPM="true"
elif find . \( "${PRUNE[@]}" \) -prune -o -name 'Package.swift' -print -quit 2>/dev/null | grep -q .; then
  HAS_SPM="true"
fi

if [ -f "Podfile" ] || [ -f "Podfile.lock" ]; then
  HAS_PODS="true"
fi

if [ "$HAS_SPM" = "true" ] && [ "$HAS_PODS" = "true" ]; then
  DM="both"
elif [ "$HAS_SPM" = "true" ]; then
  DM="spm"
elif [ "$HAS_PODS" = "true" ]; then
  DM="cocoapods"
else
  DM="none"
fi

echo "Dependency manager: $DM"
out dependency_manager "$DM"
