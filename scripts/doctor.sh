#!/usr/bin/env bash
set -euo pipefail

missing=0

ok() {
  printf 'OK       %s\n' "$1"
}

error() {
  printf 'ERROR    %s\n' "$1"
  missing=1
}

optional() {
  printf 'OPTIONAL %s\n' "$1"
}

echo "Working Memory Snapshot development environment"
echo ""

if command -v sw_vers >/dev/null 2>&1; then
  macos_version="$(sw_vers -productVersion)"
  macos_major="${macos_version%%.*}"
  if [[ "$macos_major" =~ ^[0-9]+$ ]] && (( macos_major >= 14 )); then
    ok "macOS $macos_version"
  else
    error "macOS $macos_version found; macOS 14 or later is required"
  fi
else
  error "macOS version could not be determined"
fi

if xcode_path="$(xcode-select -p 2>/dev/null)"; then
  ok "Xcode Command Line Tools selected at $xcode_path"
else
  error "Xcode Command Line Tools are not selected; install Xcode and run xcode-select"
fi

if command -v xcodebuild >/dev/null 2>&1; then
  if xcode_output="$(xcodebuild -version 2>/dev/null)"; then
    xcode_version="$(printf '%s\n' "$xcode_output" | awk 'NR == 1 { print $2 }')"
    xcode_major="${xcode_version%%.*}"
    if [[ "$xcode_major" =~ ^[0-9]+$ ]] && (( xcode_major >= 26 )); then
      ok "Xcode $xcode_version"
    else
      error "Xcode $xcode_version found; Xcode 26 or later is required"
    fi
  else
    error "xcodebuild is installed but could not run; verify the selected developer directory and Xcode license"
  fi
else
  error "xcodebuild is unavailable; install Xcode"
fi

for tool in swift git sqlite3; do
  if command -v "$tool" >/dev/null 2>&1; then
    if version="$($tool --version 2>/dev/null)"; then
      version="${version%%$'\n'*}"
      ok "$version"
    else
      error "$tool is installed but could not run"
    fi
  else
    error "$tool is unavailable"
  fi
done

if command -v curl >/dev/null 2>&1; then
  if curl --fail --silent --show-error --max-time 2 \
    http://localhost:1234/v1/models >/dev/null 2>&1; then
    optional "LM Studio is reachable at http://localhost:1234/v1"
  else
    optional "LM Studio may be stopped, unreachable, or require authentication; builds and tests do not require it"
  fi
else
  optional "curl is unavailable, so LM Studio connectivity was not checked"
fi

echo ""
if (( missing != 0 )); then
  echo "Required toolchain checks failed. Resolve the ERROR items before building."
  exit 1
fi

echo "Required toolchain checks passed."
