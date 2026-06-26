#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git init -b main
fi

./scripts/install_hooks.sh
./scripts/check.sh --quick

SEED_PATHS=(
  .agents
  .github
  .githooks
  .gitignore
  AGENTS.md
  CODEX_START_HERE.md
  MANIFEST.md
  README.md
  docs
  prompts
  scripts
)

git add -- "${SEED_PATHS[@]}"

if git diff --cached --quiet; then
  echo "No seed changes to commit."
  exit 0
fi

git diff --cached --stat
git commit -m "docs: seed product and Codex workflow"
