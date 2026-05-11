#!/bin/bash
# Point this clone's git hooks at the versioned .githooks directory.
# Run once after cloning. Re-running is harmless.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

git config core.hooksPath .githooks
chmod +x .githooks/pre-commit scripts/check.sh

echo "Hooks installed: core.hooksPath = .githooks"
echo "Pre-commit will run scripts/check.sh. Bypass with: git commit --no-verify"
