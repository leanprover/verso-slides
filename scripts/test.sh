#!/usr/bin/env bash
# Build the test fixtures, check formatting, and run the Playwright browser tests.
# Exits nonzero if any step fails.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$here/.." && pwd)"

cd "$root"
lake test
lake exe test-fixtures-build

# Every .js file under web-lib/ must be listed in some jsconfig.json.
"$here/check-jsconfig-coverage.sh"

# Type-check the JS bundles that have a full set of declarations available.
# (animate/ references types from the illuminate package's anim_core.d.ts,
# which isn't wired up here — its jsconfig.json exists only to register the
# file for the coverage check above.)
npx --no-install tsc --noEmit -p web-lib/panel/jsconfig.json
npx --no-install tsc --noEmit -p web-lib/widget/jsconfig.json

# Check prettier formatting for all git-tracked files (respects .prettierignore
# and prettier's own "can this file be formatted?" heuristic).
git ls-files -z | xargs -0 npx --no-install prettier --check --ignore-unknown

cd "$root/browser-tests"
uv run pytest "$@"
