#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not inside a Git repository. Run scripts/bootstrap_repo.sh first." >&2
  exit 1
fi

chmod +x .githooks/pre-commit scripts/check.sh scripts/doctor.sh scripts/bootstrap_repo.sh scripts/install_hooks.sh
git config core.hooksPath .githooks

echo "Installed repository hooks from .githooks."
