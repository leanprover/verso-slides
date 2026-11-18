#!/usr/bin/env bash
# Verify every git-tracked lean-toolchain file specifies the same toolchain as
# the one at the repository root. The example projects build SubVerso in the
# root project's package directory, so a different toolchain there replaces
# the root build's .olean files with incompatible files.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$here/.." && pwd)"
cd "$root"

expected=$(tr -d '[:space:]' < lean-toolchain)

status=0
while IFS= read -r file; do
  actual=$(tr -d '[:space:]' < "$file")
  if [ "$actual" != "$expected" ]; then
    message="$file names '$actual', but the root lean-toolchain names '$expected'."
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
      echo "::error file=$file,line=1,title=Lean toolchain mismatch::$message"
    else
      echo "Error: $message" >&2
    fi
    status=1
  fi
done < <(git ls-files -- 'lean-toolchain' '*/lean-toolchain')

if [ "$status" -ne 0 ]; then
  echo "Set every lean-toolchain file to '$expected'." >&2
fi
exit "$status"
