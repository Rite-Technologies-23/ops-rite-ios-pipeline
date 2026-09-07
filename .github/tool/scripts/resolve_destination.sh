#!/usr/bin/env bash
set -euo pipefail

# Resolve an xcodebuild -destination for the simulator.
#
# Usage: resolve_destination.sh [OVERRIDE]
#
# A hardcoded 'name=iPhone 16' breaks every time the runner image ships a new
# Xcode: the device either does not exist yet or has been retired. This picks
# the newest available iPhone simulator on the runner and pins the destination
# by UDID, which is unambiguous.
#
# Writes destination= and destination_name= to GITHUB_OUTPUT when set.

OVERRIDE="${1:-}"

out () { echo "$1=$2" >> "${GITHUB_OUTPUT:-/dev/stdout}"; }

if [[ -n "$OVERRIDE" ]]; then
  echo "Using caller-supplied destination: $OVERRIDE"
  out destination "$OVERRIDE"
  out destination_name "$OVERRIDE"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "::warning::jq unavailable -- falling back to a generic iOS Simulator destination."
  out destination "platform=iOS Simulator,name=iPhone 15"
  out destination_name "iPhone 15 (fallback)"
  exit 0
fi

JSON=$(xcrun simctl list devices available --json 2>/dev/null || echo '{}')

# Pick the newest iOS runtime that actually has an available iPhone, then the
# highest-numbered iPhone within it.
SELECTED=$(echo "$JSON" | jq -r '
  .devices
  | to_entries
  | map(select(.key | test("iOS")))
  | map({
      runtime: .key,
      version: (.key | capture("iOS-(?<v>[0-9]+(-[0-9]+)*)") | .v | gsub("-"; ".") | tonumber? // 0),
      devices: (.value | map(select(.isAvailable == true and (.name | startswith("iPhone")))))
    })
  | map(select(.devices | length > 0))
  | sort_by(.version)
  | last
  | if . == null then empty else
      .devices
      | sort_by(
          (.name | capture("iPhone (?<n>[0-9]+)") | .n | tonumber? // 0),
          (.name | length)
        )
      | last
      | "\(.udid)|\(.name)"
    end
' 2>/dev/null || true)

if [[ -z "$SELECTED" || "$SELECTED" == "null" ]]; then
  echo "::warning::Could not resolve a simulator from simctl. Available runtimes:"
  echo "$JSON" | jq -r '.devices | keys[]' 2>/dev/null | sed 's/^/    /' || true
  out destination "platform=iOS Simulator,name=iPhone 15"
  out destination_name "iPhone 15 (fallback)"
  exit 0
fi

UDID="${SELECTED%%|*}"
NAME="${SELECTED##*|}"

echo "Resolved simulator: $NAME ($UDID)"
out destination "platform=iOS Simulator,id=${UDID}"
out destination_name "$NAME"
