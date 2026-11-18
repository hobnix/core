#!/usr/bin/env bash
# Which ref of hobnix/capabilities CI checks out (docs/PLAN-capabilities-repo.md Q5; ADR 0017 decision 7). Prints one ref.
#   caps-ref.sh <head-branch> <release: true|false>
# A release pull request (into main) or a v* tag: the newest vX.Y.Z tag of the repository (its signature is not checked here: `hs pkg` does that on a server), `main` while it has none (what stable servers get).
# Anything else: the branch of the same name if it exists there, else `develop`. HS_CAPS_URL replaces the repository URL (tests).
set -uo pipefail
url=${HS_CAPS_URL:-https://github.com/hobnix/capabilities.git}
head=${1:-} release=${2:-false}
if [ "$release" = true ]; then
  ref=$(git ls-remote --tags --refs "$url" 'v*' | sed 's#.*refs/tags/##' | grep -E '^v[0-9]+[.][0-9]+[.][0-9]+$' | sort -V | tail -n 1)
  echo "${ref:-main}"
elif [ -n "$head" ] && git ls-remote --exit-code --heads "$url" "$head" >/dev/null 2>&1; then
  echo "$head"
else
  echo develop
fi
