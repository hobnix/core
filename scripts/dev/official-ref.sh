#!/usr/bin/env bash
# Which ref of hobnix/official CI checks out (hobnix/core#1074 Q1): the branch of the same name if it exists there, else `main` (what servers get).
# A release pull request (into main) or a v* tag: `main`. Never develop.
#   official-ref.sh <head-branch> <release: true|false>
# HS_OFFICIAL_URL replaces the repository URL (tests).
set -uo pipefail
url=${HS_OFFICIAL_URL:-https://github.com/hobnix/official.git}
head=${1:-} release=${2:-false}
if [ "$release" != true ] && [ -n "$head" ] && git ls-remote --exit-code --heads "$url" "$head" >/dev/null 2>&1; then
  echo "$head"
else
  echo main
fi
