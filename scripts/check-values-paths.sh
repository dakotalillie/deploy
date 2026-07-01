#!/usr/bin/env bash
#
# check-values-paths.sh
#
# Guardrail for the app-of-apps setup: an Argo CD Application manifest under
# <env>/apps/ may only reference Helm values files that live under <env>/.
#
# This catches the easy-to-miss mistake of copying an app definition from
# dev/apps/ to prod/apps/ and forgetting to repoint valueFiles from
# ../../dev/... to ../../prod/... — which would otherwise silently deploy prod
# using dev values, with no error from Argo CD.
#
# Run it locally exactly the way CI does:
#
#     ./scripts/check-values-paths.sh
#
# Requires: yq (https://github.com/mikefarah/yq) and awk.
#   macOS:  brew install yq
set -euo pipefail

# Operate from the repo root so resolved paths are repo-root-relative no matter
# where the script is invoked from.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(dirname "$SCRIPT_DIR")
cd "$REPO_ROOT"

if ! command -v yq >/dev/null 2>&1; then
  echo "error: 'yq' is required but not installed (macOS: brew install yq)" >&2
  exit 2
fi

# Collapse '.' and '..' segments in a path without touching the filesystem.
# Pure awk so it's portable across macOS (bash 3.2 + BSD awk) and Linux CI —
# realpath --relative-to is GNU-only and not available on stock macOS.
normalize_path() {
  printf '%s\n' "$1" | awk -F/ '{
    n = 0
    for (i = 1; i <= NF; i++) {
      s = $i
      if (s == "" || s == ".") continue
      if (s == "..") {
        if (n > 0 && stack[n] != "..") { n-- } else { stack[++n] = s }
      } else {
        stack[++n] = s
      }
    }
    out = ""
    for (i = 1; i <= n; i++) out = (out == "" ? stack[i] : out "/" stack[i])
    print out
  }'
}

fail=0

for env in dev prod; do
  for f in "$env"/apps/*.yaml "$env"/apps/*.yml; do
    [ -e "$f" ] || continue

    # Multi-source (.spec.sources[]) isn't handled yet. Fail loudly rather than
    # silently pass — a no-op check is worse than no check.
    if [ "$(yq '.spec.sources' "$f")" != "null" ]; then
      echo "⚠️  $f uses .spec.sources (multi-source); extend check-values-paths.sh to cover it" >&2
      fail=1
      continue
    fi

    src=$(yq '.spec.source.path' "$f")
    [ "$src" = "null" ] && src=""

    while IFS= read -r vf; do
      [ -z "$vf" ] && continue

      case "$vf" in
        /*) candidate="${vf#/}" ;;   # repo-root absolute (unusual, handled defensively)
        *)  candidate="$src/$vf" ;;  # relative to the source's chart path
      esac

      resolved=$(normalize_path "$candidate")

      case "$resolved" in
        "$env"/*) : ;;  # ok — references its own environment
        *)
          echo "❌ $f references values outside $env/: $resolved"
          fail=1
          ;;
      esac
    done < <(yq '.spec.source.helm.valueFiles[]' "$f" 2>/dev/null || true)
  done
done

if [ "$fail" -ne 0 ]; then
  echo >&2
  echo "Each Application under <env>/apps/ must only reference values under <env>/." >&2
  exit 1
fi

echo "✅ all app value paths point at their own environment"
