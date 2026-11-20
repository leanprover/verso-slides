#!/usr/bin/env bash
# Build the test fixtures, check formatting, and run the Playwright browser tests.
# Exits nonzero if any step fails.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$here/.." && pwd)"

cd "$root"

# Every lean-toolchain file must specify the same toolchain as the root.
"$here/check-toolchains.sh"

lake test
lake exe test-fixtures-build

# Every .js file under web-lib/ must be listed in some jsconfig.json.
"$here/check-jsconfig-coverage.sh"

# Type-check every tracked jsconfig.json and tsconfig*.json, then lint the JS.
# web-lib/animate/jsconfig.json includes Illuminate's anim_core.js and
# anim_data.d.ts from .lake/packages, which the Lake commands above fetch.
git ls-files -z -- ':(glob)**/jsconfig.json' ':(glob)**/tsconfig*.json' |
  xargs -0 -n 1 npx --no-install tsc --noEmit -p
npm run lint

# Check prettier formatting for all git-tracked files (respects .prettierignore
# and prettier's own "can this file be formatted?" heuristic).
git ls-files -z | xargs -0 npx --no-install prettier --check --ignore-unknown

cd "$root/browser-tests"
# `-n auto` hits Chromium timeouts on machines with many cores because of
# browser-process contention. Four workers is a reliable default that still
# gives a 3–4× speedup; override with `PYTEST_WORKERS=... scripts/test.sh`.
uv run pytest -n "${PYTEST_WORKERS:-4}" "$@"
