#!/usr/bin/env bash
set -euo pipefail

# Installs only the CLI tools the calling job asked for.
#
# Input (env):
#   TOOLS  space-separated: swiftlint swiftformat periphery xcbeautify
#                           gitleaks trivy
#
# Every tool here is free and open source. Versions are pinned via env vars so
# a toolchain bump is a deliberate, reviewable change rather than a surprise
# on a Monday morning.

TOOLS="${TOOLS:-}"

SWIFTLINT_VERSION="${SWIFTLINT_VERSION:-0.57.0}"
SWIFTFORMAT_VERSION="${SWIFTFORMAT_VERSION:-0.55.5}"
PERIPHERY_VERSION="${PERIPHERY_VERSION:-3.0.0}"
XCBEAUTIFY_VERSION="${XCBEAUTIFY_VERSION:-2.16.0}"
GITLEAKS_VERSION="${GITLEAKS_VERSION:-8.21.2}"
# 0.58.1 no longer has downloadable release assets on GitHub -- verified 404
# on trivy_0.58.1_Linux-64bit.tar.gz as of 2026-09-10.
TRIVY_VERSION="${TRIVY_VERSION:-0.74.0}"

BIN_DIR="${RUNNER_TEMP:-/tmp}/ci-tools"
mkdir -p "$BIN_DIR"
echo "$BIN_DIR" >> "${GITHUB_PATH:-/dev/null}"
export PATH="$BIN_DIR:$PATH"

is_macos () { [ "$(uname -s)" = "Darwin" ]; }

have () { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Download a GitHub release asset and unpack a single binary from it.
# ---------------------------------------------------------------------------
fetch_binary () {
  local url="$1" archive_name="$2" binary="$3"
  local tmp
  tmp="$(mktemp -d)"

  echo "  downloading $url"
  curl -sSLo "$tmp/$archive_name" "$url"

  case "$archive_name" in
    *.tar.gz|*.tgz) tar -xzf "$tmp/$archive_name" -C "$tmp" ;;
    *.zip)          unzip -qo "$tmp/$archive_name" -d "$tmp" ;;
    *)              cp "$tmp/$archive_name" "$tmp/$binary" ;;
  esac

  local found
  found=$(find "$tmp" -type f -name "$binary" -perm -u+x 2>/dev/null | head -1 || true)
  if [ -z "$found" ]; then
    found=$(find "$tmp" -type f -name "$binary" 2>/dev/null | head -1 || true)
  fi

  if [ -z "$found" ]; then
    echo "::error::Could not find '$binary' inside $archive_name"
    ls -R "$tmp" | head -40
    return 1
  fi

  install -m 0755 "$found" "$BIN_DIR/$binary"
  rm -rf "$tmp"
}

install_swiftlint () {
  if have swiftlint; then echo "swiftlint already present: $(swiftlint version)"; return; fi
  echo "Installing SwiftLint $SWIFTLINT_VERSION"
  fetch_binary \
    "https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/portable_swiftlint.zip" \
    "portable_swiftlint.zip" "swiftlint"
  swiftlint version
}

install_swiftformat () {
  if have swiftformat; then echo "swiftformat already present: $(swiftformat --version)"; return; fi
  echo "Installing SwiftFormat $SWIFTFORMAT_VERSION"
  fetch_binary \
    "https://github.com/nicklockwood/SwiftFormat/releases/download/${SWIFTFORMAT_VERSION}/swiftformat.zip" \
    "swiftformat.zip" "swiftformat"
  swiftformat --version
}

install_periphery () {
  if have periphery; then echo "periphery already present: $(periphery version)"; return; fi
  echo "Installing Periphery $PERIPHERY_VERSION"
  fetch_binary \
    "https://github.com/peripheryapp/periphery/releases/download/${PERIPHERY_VERSION}/periphery-${PERIPHERY_VERSION}.zip" \
    "periphery.zip" "periphery"
  periphery version
}

install_xcbeautify () {
  if have xcbeautify; then echo "xcbeautify already present: $(xcbeautify --version)"; return; fi
  echo "Installing xcbeautify $XCBEAUTIFY_VERSION"
  local arch="arm64"
  [ "$(uname -m)" = "x86_64" ] && arch="x86_64"
  fetch_binary \
    "https://github.com/cpisciotta/xcbeautify/releases/download/${XCBEAUTIFY_VERSION}/xcbeautify-${XCBEAUTIFY_VERSION}-${arch}-apple-macosx.zip" \
    "xcbeautify.zip" "xcbeautify"
  xcbeautify --version
}

install_gitleaks () {
  if have gitleaks; then echo "gitleaks already present: $(gitleaks version)"; return; fi
  echo "Installing gitleaks $GITLEAKS_VERSION"
  local os="linux" arch="x64"
  if is_macos; then os="darwin"; fi
  case "$(uname -m)" in
    arm64|aarch64) arch="arm64" ;;
    x86_64)        arch="x64" ;;
  esac
  fetch_binary \
    "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_${os}_${arch}.tar.gz" \
    "gitleaks.tar.gz" "gitleaks"
  gitleaks version
}

install_trivy () {
  if have trivy; then echo "trivy already present: $(trivy --version | head -1)"; return; fi
  echo "Installing Trivy $TRIVY_VERSION"
  local platform="Linux-64bit"
  if is_macos; then
    platform="macOS-ARM64"
    [ "$(uname -m)" = "x86_64" ] && platform="macOS-64bit"
  fi
  fetch_binary \
    "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_${platform}.tar.gz" \
    "trivy.tar.gz" "trivy"
  trivy --version | head -1
}

for tool in $TOOLS; do
  case "$tool" in
    swiftlint)   install_swiftlint ;;
    swiftformat) install_swiftformat ;;
    periphery)   install_periphery ;;
    xcbeautify)  install_xcbeautify ;;
    gitleaks)    install_gitleaks ;;
    trivy)       install_trivy ;;
    "")          ;;
    *) echo "::warning::Unknown tool '$tool' -- skipping" ;;
  esac
done

echo "Tools installed into $BIN_DIR"
