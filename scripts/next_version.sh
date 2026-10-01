#!/usr/bin/env bash
# Prints the next release version from Conventional Commits since the last
# v<major>.<minor>.<patch> tag, or nothing when no commit warrants a release.
#
#   feat!: / BREAKING CHANGE  -> major
#   feat:                     -> minor
#   fix: / perf:              -> patch
#   anything else (docs, chore, ci, ...) -> no release
#
# Usage: scripts/next_version.sh [major|minor|patch|<x.y.z>]
#   An argument forces that bump (or exact version) regardless of commits.
#   With no tag yet, the first release is the version in addon/godot4/plugin.cfg.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FORCE="${1:-}"

if [[ "$FORCE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "$FORCE"
  exit 0
fi

LAST_TAG="$(git -C "$ROOT" tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n1)"

if [ -z "$LAST_TAG" ]; then
  sed -n 's/^version="\(.*\)"/\1/p' "$ROOT/addon/godot4/plugin.cfg"
  exit 0
fi

BUMP="$FORCE"
if [ -z "$BUMP" ]; then
  LOG="$(git -C "$ROOT" log --format='%s%n%b%n--END--' "$LAST_TAG..HEAD")"
  if grep -qE '^[a-z]+(\([^)]*\))?!:|^BREAKING[ -]CHANGE:' <<<"$LOG"; then
    BUMP=major
  elif grep -qE '^feat(\([^)]*\))?:' <<<"$LOG"; then
    BUMP=minor
  elif grep -qE '^(fix|perf)(\([^)]*\))?:' <<<"$LOG"; then
    BUMP=patch
  else
    exit 0
  fi
fi

IFS=. read -r MAJOR MINOR PATCH <<<"${LAST_TAG#v}"
case "$BUMP" in
  major) echo "$((MAJOR + 1)).0.0" ;;
  minor) echo "$MAJOR.$((MINOR + 1)).0" ;;
  patch) echo "$MAJOR.$MINOR.$((PATCH + 1))" ;;
  *) echo "error: unknown bump '$BUMP'" >&2; exit 1 ;;
esac
