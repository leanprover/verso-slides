#!/usr/bin/env bash
# Build the test fixtures, check formatting, and run the Playwright browser tests.
# Exits nonzero if any step fails.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$here/.." && pwd)"

cd "$root"
lake test
lake exe test-fixtures-build

# Check prettier formatting for all git-tracked files (respects .prettierignore
# and prettier's own "can this file be formatted?" heuristic).
git ls-files -z | xargs -0 npx --no-install prettier --check --ignore-unknown

cd "$root/browser-tests"
uv run pytest "$@"
