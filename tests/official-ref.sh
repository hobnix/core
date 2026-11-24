#!/usr/bin/env bash
# scripts/dev/official-ref.sh: the ref of hobnix/official CI uses (same-name branch else main, never develop; a release: main).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have git || { skip "needs git"; finish; exit 0; }
OR="bash $SCRIPTS/dev/official-ref.sh"
R=$WORK/official; mkdir -p "$R"; cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
git commit -q --allow-empty -m one && git branch develop && git branch feature/x
export HS_OFFICIAL_URL=file://$R
check_eq "a branch of the same name" "feature/x" "$($OR feature/x false)"
check_eq "no such branch: main, not develop" "main" "$($OR feature/other false)"
check_eq "a release pull request: main even with a branch of that name" "main" "$($OR feature/x true)"
check_eq "no head ref: main" "main" "$($OR "" false)"
check_match "the default repository is hobnix/official" 'hobnix/official[.]git' "$(grep '^url=' "$SCRIPTS/dev/official-ref.sh")"
finish
