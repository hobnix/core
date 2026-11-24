#!/usr/bin/env bash
# scripts/dev/caps-ref.sh: the ref of hobnix/capabilities CI uses (same-name branch else develop; release: newest tag, main without one).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have git || { skip "needs git"; finish; exit 0; }
CR="bash $SCRIPTS/dev/caps-ref.sh"
R=$WORK/caps; mkdir -p "$R"; cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
git commit -q --allow-empty -m one && git branch develop && git branch feature/x
export HS_CAPS_URL=file://$R
check_eq "a branch of the same name" "feature/x" "$($CR feature/x false)"
check_eq "no such branch: develop" "develop" "$($CR feature/other false)"
check_eq "a release without a tag: main" "main" "$($CR develop true)"
git tag v0.1.0 && git tag v0.10.0 && git tag v0.2.0 && git tag v0.11.0-beta.1
check_eq "a release: the newest stable tag, sorted as versions, no beta" "v0.10.0" "$($CR develop true)"
check_match "the default repository is hobnix/official" 'hobnix/official[.]git' "$(grep '^url=' "$SCRIPTS/dev/caps-ref.sh")"
finish
