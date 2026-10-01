#!/usr/bin/env bash
# Prints Markdown release notes for the commits since the last v* tag,
# grouped by Conventional Commit type.
#
# Usage: scripts/release_notes.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAST_TAG="$(git -C "$ROOT" tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n1)"
RANGE="HEAD"
[ -n "$LAST_TAG" ] && RANGE="$LAST_TAG..HEAD"

COMMITS="$(git -C "$ROOT" log --no-merges --format='%s (%h)' "$RANGE")"

# $1 heading  $2 subject regex
section() {
  local lines
  lines="$(grep -E "$2" <<<"$COMMITS" | sed -E 's/^[a-z]+(\([^)]*\))?!?: */- /' || true)"
  if [ -n "$lines" ]; then
    printf '### %s\n\n%s\n\n' "$1" "$lines"
  fi
}

section "Breaking changes" '^[a-z]+(\([^)]*\))?!:'
section "Features" '^feat(\([^)]*\))?:'
section "Fixes" '^(fix|perf)(\([^)]*\))?:'

if [ -n "$LAST_TAG" ]; then
  echo "**Full changelog**: https://github.com/NoctuaLabs/noctua-godot-sdk/compare/$LAST_TAG...v${NOCTUA_VERSION:-HEAD}"
fi
