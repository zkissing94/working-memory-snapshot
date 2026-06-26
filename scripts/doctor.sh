#!/usr/bin/env bash
set -euo pipefail

echo "macOS:"
sw_vers || true
echo ""

echo "Xcode path:"
xcode-select -p || true
echo ""

echo "Xcode version:"
xcodebuild -version || true
echo ""

echo "Swift version:"
swift --version || true
echo ""

echo "Git version:"
git --version || true
echo ""

echo "SQLite version:"
sqlite3 --version || true
echo ""

echo "LM Studio local server check:"
if command -v curl >/dev/null 2>&1; then
  curl -sS http://localhost:1234/v1/models || echo "LM Studio not reachable at http://localhost:1234/v1/models"
else
  echo "curl not available"
fi
