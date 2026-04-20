#!/usr/bin/env bash
# Build the test fixtures and run the Playwright browser tests.
# Exits nonzero if either step fails.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$here/.." && pwd)"

cd "$root"
lake test
lake exe test-fixtures-build

cd "$root/browser-tests"
uv run pytest "$@"
