#!/usr/bin/env bash
# Example command extension in shell: `hs ext hello greet [name]` and `hs ext hello count <n>` (docs/extensions-sdk.md).
# Try it without the core: python3 scripts/lib/ext_proto.py call --command greet --arg Ada -- sdk/examples/shell/hello.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/lib/ext_sdk.sh
. "${HS_SCRIPTS:-$here/../../../scripts}/lib/ext_sdk.sh"
ext_init

case "${EXT_WORDS[0]:-}" in
  greet)
    name=${EXT_ARGV[0]:-world}
    ext_log info "greeting"
    ext_event pkg.hello.greeted "$name"
    ext_ok "hello $name" "$(jq -nc --arg g "hello $name" '{greeting:$g}')" ;;
  count)
    n=${EXT_ARGV[0]:-}
    case "$n" in ''|*[!0-9]*) ext_fail bad_request "count needs a number from 1 to 10" ;; esac
    { [ "$n" -ge 1 ] && [ "$n" -le 10 ]; } || ext_fail bad_request "count needs a number from 1 to 10"
    for ((i = 1; i <= n; i++)); do ext_progress "$(awk -v i="$i" -v n="$n" 'BEGIN { printf "%.3f", i / n }')" "step $i of $n"; done
    ext_ok "" "$(jq -nc --argjson n "$n" '{counted:$n}')" ;;
  *) ext_fail not_found "no such command" ;;
esac
