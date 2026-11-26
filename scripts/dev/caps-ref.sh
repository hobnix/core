#!/usr/bin/env bash
# Which ref of hobnix/official (the old hobnix/capabilities until it is archived) CI checks out (docs/PLAN-capabilities-repo.md Q5; ADR 0017 decision 7). Prints one ref.
#   caps-ref.sh <head-branch> <release: true|false>
# A release pull request (into main) or a v* tag: `main` when the repository has no vX.Y.Z tag (hobnix/official has none, ever: what stable servers get), else the newest vX.Y.Z tag (an old repository; its signature is not checked here: `hs pkg` does that on a server).
# Anything else: the branch of the same name if it exists there, else `develop`. HS_CAPS_URL replaces the repository URL (tests).
set -uo pipefail
url=${HS_CAPS_URL:-https://github.com/hobnix/official.git}
head=${1:-} release=${2:-false}
if [ "$release" = true ]; then
  ref=$(git ls-remote --tags --refs "$url" 'v*' | sed 's#.*refs/tags/##' | grep -E '^v[0-9]+[.][0-9]+[.][0-9]+$' | sort -V | tail -n 1)
  echo "${ref:-main}"
elif [ -n "$head" ] && git ls-remote --exit-code --heads "$url" "$head" >/dev/null 2>&1; then
  echo "$head"
else
  echo develop
fi
