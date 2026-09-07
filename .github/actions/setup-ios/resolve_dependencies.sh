#!/usr/bin/env bash
set -euo pipefail

# Resolves SPM packages and/or CocoaPods before any build step.
#
# Inputs (env): PROJECT_TYPE, PROJECT_FILE, SCHEME, DEPENDENCY_MANAGER

PROJECT_TYPE="${PROJECT_TYPE:-}"
PROJECT_FILE="${PROJECT_FILE:-}"
SCHEME="${SCHEME:-}"
DEPENDENCY_MANAGER="${DEPENDENCY_MANAGER:-none}"

# ---------------------------------------------------------------------------
# CocoaPods first: `pod install` can regenerate the .xcworkspace that the SPM
# resolve step then needs to read.
# ---------------------------------------------------------------------------
if [ "$DEPENDENCY_MANAGER" = "cocoapods" ] || [ "$DEPENDENCY_MANAGER" = "both" ]; then
  echo "Installing CocoaPods dependencies..."

  if [ -f "Gemfile" ]; then
    # A Gemfile pins the CocoaPods version; honour it rather than the
    # runner's preinstalled one.
    bundle install --quiet || gem install cocoapods --no-document
    bundle exec pod install --repo-update || pod install --repo-update
  else
    pod install --repo-update
  fi
fi

if [ "$DEPENDENCY_MANAGER" = "spm" ] || [ "$DEPENDENCY_MANAGER" = "both" ]; then
  echo "Resolving Swift Package Manager dependencies..."

  # Not fatal: some projects legitimately have no package graph attached to the
  # scheme, and the build step will surface a genuine resolution failure.
  xcodebuild -resolvePackageDependencies \
    -"$PROJECT_TYPE" "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    || echo "::warning::xcodebuild -resolvePackageDependencies returned non-zero; continuing."
fi

if [ "$DEPENDENCY_MANAGER" = "none" ]; then
  echo "No dependency manager detected -- nothing to resolve."
fi
