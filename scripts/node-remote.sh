#!/usr/bin/env bash
# help: forced command for the key another server uses to look at this one (authorized_keys: restrict,command="/etc/nixos/scripts/node-remote.sh" ssh-ed25519 ...)
# help.de: erzwungener Befehl für den Schlüssel, mit dem ein anderer Server diesen ansieht (authorized_keys: restrict,command="/etc/nixos/scripts/node-remote.sh" ssh-ed25519 ...)
# Receiving side of `hs node status`. It reads $SSH_ORIGINAL_COMMAND and accepts EXACTLY the words below, nothing else
# (no arguments, no shell, no pattern). A word runs one fixed command and prints plain data. Anything else: exit 2 and a line in the journal.
#   status   the status document of this server (JSON, the same as `hs sys deck`; on an edge node `hs sys edge status`)
#   pair     remote shares by code (docs/PLAN-remote-shares.md): the claim request on standard input, the answer (the box, or the one refusal shape) on
#            standard output; exit 0 answered, 1 refused, 3 not reachable (no passwordless root for this key). It runs `hs sys remote claim --source node`; the code itself is never in the request, only its derived id.
# To allow more, add a word here AND to NODE_WORDS in scripts/node.sh, each with a test; never a pattern.
# Test knobs: HS_DECK_FILE (default /run/hs-deck/deck.json), HS_DECK_STATUS (the script that makes the document), HS_BIN (the hs program).
set -euo pipefail
here=$(dirname "$0")
. "$here/lib/capability.sh"
word=${SSH_ORIGINAL_COMMAND:-}
log() { logger -t hs-node-remote -- "$*" 2>/dev/null || true; }
case "$word" in
  status)
    f=${HS_DECK_FILE:-/run/hs-deck/deck.json}
    # an edge node (capability edge-status) keeps the same file; without it the document is made on the spot by ITS script
    fresh=deck-status.sh; if capability_on edge-status; then fresh=edge-status.sh; fi
    if [ -s "$f" ]; then cat "$f"; else bash "${HS_DECK_STATUS:-$here/$fresh}"; fi ;;
  pair)
    # This key belongs to the admin user, not to root: `hs` has to sudo, which asks for a password there and fails without a terminal. We do not widen
    # sudo for it and the key never gets a shell. So the word works only where hs runs without a password; otherwise it says so (exit 3) and the
    # other side shows "node link cannot reach the pairing service".
    rc=0
    out=$("${HS_BIN:-hs}" sys remote claim --source node 2>/dev/null) || rc=$?
    case "$out" in
      *'"v":1'*) printf '%s\n' "$out"; [ "$rc" -le 1 ] && exit "$rc"; exit 3 ;;
      *) log "pair: the pairing service is not reachable (exit $rc)"; echo "node-remote: pair is not reachable from this key" >&2; exit 3 ;;
    esac ;;
  *)
    log "refused: $(printf '%s' "$word" | head -c 60 | tr -c '[:alnum:] ._-' '?')"
    echo "node-remote: not allowed (only: status, pair)" >&2
    exit 2 ;;
esac
