#!/usr/bin/env bash
# Verify every .js file under web-lib/ is listed in some jsconfig.json's
# "include" array. This ensures adding a new JS file forces a conscious
# decision about type-checking rather than silently opting out.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$here/.." && pwd)"
cd "$root"

actual=$(find web-lib -type f -name '*.js' | sed 's|^web-lib/||' | sort)

covered=$(
  while IFS= read -r cfg; do
    dir=$(dirname "$cfg" | sed 's|^web-lib/||; s|^web-lib$||')
    jq -r '.include[] | select(endswith(".js"))' "$cfg" | while IFS= read -r p; do
      if [ -n "$dir" ]; then
        printf '%s/%s\n' "$dir" "$p"
      else
        printf '%s\n' "$p"
      fi
    done
  done < <(find web-lib -name jsconfig.json) | sort -u
)

missing=$(comm -23 <(printf '%s\n' "$actual") <(printf '%s\n' "$covered") || true)
if [ -n "$missing" ]; then
  echo "Error: the following .js files under web-lib/ are not listed in any jsconfig.json 'include' array:" >&2
  printf '  %s\n' $missing >&2
  echo "Add them to the appropriate jsconfig.json so they are type-checked (or" >&2
  echo "create a new jsconfig.json if they belong in a new subdirectory)." >&2
  exit 1
fi
