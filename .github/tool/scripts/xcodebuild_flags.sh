#!/usr/bin/env bash
set -euo pipefail

# Emits the xcodebuild build-setting overrides that tighten the Swift compiler.
#
# This is the iOS analogue of the Android pipeline's Gradle init scripts:
# xcodebuild accepts SETTING=value overrides on the command line, so the
# pipeline can enforce compiler strictness WITHOUT editing the caller's
# .xcodeproj or .xcconfig files.
#
# Usage:  eval "STRICT_FLAGS=( $(bash xcodebuild_flags.sh) )"
#     or: xcodebuild ... $(bash xcodebuild_flags.sh)
#
# Inputs (env):
#   SWIFT_WARNINGS_AS_ERRORS  "true"/"false"  (default false)
#   SWIFT_STRICT_CONCURRENCY  off|minimal|targeted|complete (default targeted)
#   DISABLE_CODE_SIGNING      "true"/"false"  (default true -- CI never signs)

WARNINGS_AS_ERRORS="${SWIFT_WARNINGS_AS_ERRORS:-false}"
STRICT_CONCURRENCY="${SWIFT_STRICT_CONCURRENCY:-targeted}"
DISABLE_SIGNING="${DISABLE_CODE_SIGNING:-true}"

FLAGS=()

# ---------------------------------------------------------------------------
# Type-safety strictness. The Swift compiler is already the type checker; these
# stop it from downgrading real problems to warnings nobody reads.
# ---------------------------------------------------------------------------
if [ "$WARNINGS_AS_ERRORS" = "true" ]; then
  FLAGS+=("SWIFT_TREAT_WARNINGS_AS_ERRORS=YES")
  FLAGS+=("GCC_TREAT_WARNINGS_AS_ERRORS=YES")
fi

# Data-race safety. `targeted` is the honest default: `complete` produces
# hundreds of errors on any pre-Swift-6 codebase.
case "$STRICT_CONCURRENCY" in
  off|minimal|targeted|complete)
    FLAGS+=("SWIFT_STRICT_CONCURRENCY=${STRICT_CONCURRENCY}")
    ;;
  *)
    echo "::warning::Unknown SWIFT_STRICT_CONCURRENCY '${STRICT_CONCURRENCY}', using targeted" >&2
    FLAGS+=("SWIFT_STRICT_CONCURRENCY=targeted")
    ;;
esac

# Surface implicit-conversion and shadowing mistakes the default template hides.
FLAGS+=("CLANG_WARN_DOCUMENTATION_COMMENTS=YES")
FLAGS+=("CLANG_WARN_UNGUARDED_AVAILABILITY=YES_AGGRESSIVE")
FLAGS+=("GCC_WARN_SHADOW=YES")
FLAGS+=("GCC_WARN_ABOUT_RETURN_TYPE=YES_ERROR")
FLAGS+=("CLANG_WARN_STRICT_PROTOTYPES=YES")

# ---------------------------------------------------------------------------
# CI never has signing identities, and an unsigned build is all any analysis
# stage needs.
# ---------------------------------------------------------------------------
if [ "$DISABLE_SIGNING" = "true" ]; then
  FLAGS+=("CODE_SIGNING_ALLOWED=NO")
  FLAGS+=("CODE_SIGNING_REQUIRED=NO")
  FLAGS+=("CODE_SIGN_IDENTITY=")
  FLAGS+=("CODE_SIGN_ENTITLEMENTS=")
  FLAGS+=("DEVELOPMENT_TEAM=")
  FLAGS+=("PROVISIONING_PROFILE_SPECIFIER=")
fi

printf '%s\n' "${FLAGS[@]}"
