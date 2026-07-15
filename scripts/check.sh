#!/usr/bin/env bash
set -euo pipefail

MODE="full"
if [[ "${1:-}" == "--quick" ]]; then
  MODE="quick"
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--quick]" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

required=(
  AGENTS.md
  CODEX_START_HERE.md
  docs/00-product-prd.md
  docs/01-system-architecture.md
  docs/02-ui-spec.md
  docs/03-data-model.md
  docs/04-local-ai-spec.md
  docs/05-mvp-roadmap.md
  docs/06-codex-workflow.md
  docs/07-macos-build-compile.md
  docs/07-testing-strategy.md
  docs/08-decision-log.md
  docs/09-risk-register.md
  .agents/skills/milestone-execution/SKILL.md
)

for path in "${required[@]}"; do
  if [[ ! -f "$path" ]]; then
    echo "Missing required file: $path" >&2
    exit 1
  fi
done

bash -n scripts/*.sh
bash -n .githooks/pre-commit

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git diff --check
  git diff --cached --check

  blocked_regex='(^|/)(DerivedData|\.derivedData|xcuserdata)(/|$)|\.(sqlite|sqlite3|db|pem|key)$|(^|/)\.env($|\.)'
  staged="$(git diff --cached --name-only --diff-filter=ACMR || true)"
  if [[ -n "$staged" ]] && printf '%s\n' "$staged" | grep -E "$blocked_regex" >/dev/null; then
    echo "Blocked generated, local-data, or secret-like files are staged:" >&2
    printf '%s\n' "$staged" | grep -E "$blocked_regex" >&2
    exit 1
  fi
fi

if [[ "$MODE" == "quick" ]]; then
  echo "Quick checks passed."
  exit 0
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild not found. Install Xcode and select it with xcode-select." >&2
  exit 1
fi

workspace="${XCODE_WORKSPACE:-}"
project="${XCODE_PROJECT:-}"

if [[ -z "$workspace" && -z "$project" && -d "WorkingMemorySnapshot.xcodeproj" ]]; then
  project="WorkingMemorySnapshot.xcodeproj"
fi

if [[ -z "$workspace" && -z "$project" ]]; then
  workspace="$(find . -maxdepth 2 -name '*.xcworkspace' -not -path '*/xcuserdata/*' | head -n 1 || true)"
fi

if [[ -n "$project" && ! -d "$project" ]]; then
  echo "error: XCODE_PROJECT was set to '$project', but that directory does not exist." >&2
  exit 1
fi

if [[ -z "$workspace" && -z "$project" ]]; then
  project="$(find . -maxdepth 3 -name '*.xcodeproj' | head -n 1 || true)"
fi

if [[ -z "$workspace" && -z "$project" ]]; then
  echo "No Xcode workspace or project exists yet; documentation checks passed."
  exit 0
fi

container_args=()
if [[ -n "$workspace" ]]; then
  container_args=(-workspace "$workspace")
else
  container_args=(-project "$project")
fi

scheme="${SCHEME:-}"
if [[ -z "$scheme" && -f "WorkingMemorySnapshot.xcodeproj/xcshareddata/xcschemes/WorkingMemorySnapshot.xcscheme" ]]; then
  scheme="WorkingMemorySnapshot"
fi

if [[ -z "$scheme" ]] && command -v python3 >/dev/null 2>&1; then
  scheme="$(
    xcodebuild "${container_args[@]}" -list -json 2>/dev/null |
    python3 -c '
import json, sys
data = json.load(sys.stdin)
schemes = []
for key in ("workspace", "project"):
    schemes.extend(data.get(key, {}).get("schemes", []))
if "WorkingMemorySnapshot" in schemes:
    print("WorkingMemorySnapshot")
elif schemes:
    print(schemes[0])
' || true
  )"
fi

if [[ -z "$scheme" ]]; then
  echo "Could not determine a shared Xcode scheme. Set SCHEME=<name> or install python3 for scheme discovery." >&2
  exit 1
fi

configuration="${CONFIGURATION:-Debug}"
derived_data="${DERIVED_DATA_PATH:-.derivedData}"

echo "Using Xcode:"
xcodebuild -version
echo ""
echo "Available schemes:"
xcodebuild "${container_args[@]}" -list
echo ""
echo "Building scheme: $scheme"
xcodebuild \
  "${container_args[@]}" \
  -scheme "$scheme" \
  -configuration "$configuration" \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ "${RUN_TESTS:-1}" == "1" ]]; then
  if pgrep -x WorkingMemorySnapshot >/dev/null 2>&1; then
    echo "error: quit all running WorkingMemorySnapshot copies before running tests." >&2
    echo "The app is single-instance, and the XCTest host must launch its own validated copy." >&2
    exit 1
  fi

  echo "Running tests for scheme: $scheme"
  xcodebuild \
    "${container_args[@]}" \
    -scheme "$scheme" \
    -configuration "$configuration" \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO \
    test
fi

echo "Full checks passed."
