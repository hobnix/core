#!/usr/bin/env bash
# help: share a folder with another homeserver, or mount one of theirs read-only (e.g. their films for Jellyfin)
# help.de: einen Ordner mit einem anderen Homeserver teilen oder einen von dessen Ordnern nur lesend einbinden (z. B. dessen Filme für Jellyfin)
# args: list | offer <share> --peer <name> [--new-password] [--yes] | revoke <peer> [<share>] [--yes]
#       add <peer> <host> <share> --user <login> [--domain <DOMAIN>] [--stdin] [--yes] | remove <peer> [<share>] [--yes]
#       attach <peer> <instance> [--path <inside>] | detach <peer> <instance> | mount-all
#       offer <share> --code [--peer <name>] [--minutes N] | add --code [--server <name|host>] [--stdin] | codes [--cancel]
#       receive [--minutes N] | send <share> --peer <name> --code [--server <host>] [--stdin]
# Two sides, both with this tool. The side that GIVES access runs `offer`: a domain user `remote-<peer>` is made (or
# reused) and gets READ on the one share; the command prints host, user, domain and the password (shown once). The side
# that USES it runs `add`: the password goes into a credentials file (in the vault, like the other secrets), and the
# share is mounted read-only at /mnt/remote/<peer>/<share> (SMB 3, by `mount-all`, which the timer hs-remote-mount
# repeats every 2 minutes, so a peer that is off never blocks anything). `attach` hands the folder
# /mnt/remote/<peer> to an instance as a disk device with rslave propagation. recursive=true is needed (a plain bind carries only the empty folder, a container started after the mount saw nothing) and Incus refuses it together with readonly=true, so the read-only part is the SMB mount itself (mount option ro); a mount that comes later
# shows up inside without a restart. The mounts are NOT part of /bulk, SnapRAID, the backup or the share list.
# Pairing by code (docs/PLAN-remote-shares.md): `offer --code` makes a code of 16 letters and digits that the OTHER server types with
# `add --code` (the code never goes through argv: one line on stdin, or asked). The code store, the key derivation, the box and the rate limit
# are the hobnix program (rust/hobnix-core/src/pair.rs); this script is the glue: the login, the vault file, the mount, the transport (curl, or
# the node link `hs node --pair`). `receive` + `send` are the reverse direction: this server shows a code, the other one types it and picks the share.
# `grant` and `accept-mount` are internal words (called by `hobnix remote-claim|remote-accept`, never by a person).
# State: /var/lib/hs/remote-offers (peer, share, login, date, host key fingerprint or -), /var/lib/hs/remote-mounts (peer, host, share, login, domain, fingerprint),
# /var/lib/hs/remote-<peer>.cred (secret). Test knobs: HS_STATE_DIR, HS_REMOTE_ROOT, HS_MANAGE_USERS, HS_SHARE_PERM,
# HS_MOUNT_CMD, HS_UMOUNT, HS_MOUNTPOINT, HS_INCUS, HS_DOMAIN_SHORT, HS_HOST_NAME, HOBNIX_BIN, HS_CURL, HS_NODE, HS_HOST_KEY_FILE, HS_WEB_PORT.
set -euo pipefail
here=$(dirname "$0")
. "$here/lib/ui.sh"
. "$here/lib/secret.sh"
. "$here/lib/instance.sh"
. "$here/lib/event.sh"
state=${HS_STATE_DIR:-/var/lib/hs}
root=${HS_REMOTE_ROOT:-/mnt/remote}
mu=${HS_MANAGE_USERS:-$here/manage-users.sh}
sp=${HS_SHARE_PERM:-$here/share-perm.sh}
incus_bin=${HS_INCUS:-incus}
OFFERS=$state/remote-offers
MOUNTS=$state/remote-mounts
node_sh=${HS_NODE:-$here/node.sh}

usage() {
  say "usage: hs remote list"
  say "       hs remote offer <share> --peer <name> [--new-password] [--yes]   (this server gives access)"
  say "       hs remote offer <share> --code [--peer <name>] [--minutes N]   (a code the other server types)"
  say "       hs remote revoke <peer> [<share>] [--yes]"
  say "       hs remote add --code [--server <name|host>] [--stdin]            (type the code of the other server)"
  say "       hs remote codes [--cancel]   |   hs remote receive [--minutes N]   |   hs remote send <share> --peer <name> --code [--server <host>]"
  say "       hs remote add <peer> <host> <share> --user <login> [--domain <DOMAIN>] [--stdin] [--yes]   (this server uses theirs)"
  say "       hs remote remove <peer> [<share>] [--yes]"
  say "       hs remote attach <peer> <instance> [--path <inside>]     |  hs remote detach <peer> <instance>"
  exit 1
}
interactive() { [ -t 0 ] && [ -t 1 ] && [ -z "${HS_CALLER:-}" ] || [ -n "${HS_GUIDED_TTY:-}" ]; }
sure() {   # sure <yes> <question>: the question unless --yes; no terminal without --yes = refuse
  [ "$1" = true ] && return 0
  interactive || fail "Nothing is changed without --yes when there is no terminal."
  confirm "$2" || fail "cancelled"
}
valid() {   # valid <what> <value> <regex>
  [[ "$2" =~ $3 ]] || fail "$(t "Invalid %s '%s'." "$1" "$2")"
}
v_peer()  { valid "peer name (lowercase letters, digits, -; at most 20)" "$1" '^[a-z0-9][a-z0-9-]{0,19}$'; }
v_share() { valid "share name" "$1" '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'; }
v_host()  { valid "host" "$1" '^[A-Za-z0-9][A-Za-z0-9._:-]{0,252}$'; }
v_login() { valid "login" "$1" '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'; }
v_ct()    { valid "instance name" "$1" '^[A-Za-z0-9][A-Za-z0-9-]{0,62}$'; }
today() { date +%F; }
need_root() { [ "$(id -u)" -eq 0 ] || [ "${HS_CALLER:-}" = test ] || fail "Run this with sudo (hs does that for you)."; }
cred_file() { echo "$state/remote-$1.cred"; }
user_of() { echo "remote-$1"; }
mnt_of() { echo "$root/$1/$2"; }
is_mounted() { timeout 10 ${HS_MOUNTPOINT:-mountpoint} -q "$1" 2>/dev/null; }
rows() { [ -f "$1" ] && grep -v '^[[:space:]]*#' "$1" || true; }   # rows <file>: the records
drop() {   # drop <file> <field=value>... : delete the records whose first N fields match
  local f=$1; shift
  [ -f "$f" ] || return 0
  awk -F'\t' -v OFS='\t' -v want="$(IFS=$'\x01'; echo "$*")" '
    BEGIN { n = split(want, w, "\001") }
    { keep = 0; for (i = 1; i <= n; i++) if ($i != w[i]) keep = 1; if (keep) print }' "$f" > "$f.new"
  mv "$f.new" "$f"
}
gen_password() { local p; p=$(head -c 24 /dev/urandom | base64 | tr -d '/+=\n'); echo "${p}-Aa1"; }

write_cred() {   # write_cred <peer> <login> <domain> [<exit code for a failure to save, default 1>]; password on stdin (one line)
  local f pw rcx=${4:-1}; f=$(cred_file "$1")
  IFS= read -r pw || pw=""
  # the pairing paths ask for exit 4 (their callers read exit 1 as "the name is taken"); the manual `add` keeps the plain fail (exit 1)
  if [ "$rcx" -eq 1 ]; then
    [ -n "$pw" ] || fail "No password."
    secret_prepare "remote-$1.cred" "$state" || fail_fix "The vault is closed." "hs unlock"
  else
    [ -n "$pw" ] || { warn "No password." >&2; exit "$rcx"; }
    secret_prepare "remote-$1.cred" "$state" || { warn "The vault is closed (hs unlock)." >&2; exit "$rcx"; }
  fi
  ( umask 077
    { printf 'username=%s\n' "$2"; printf 'password=%s\n' "$pw"; [ -z "$3" ] || printf 'domain=%s\n' "$3"; } > "$f" )
  chmod 600 "$f"
}

domain_short() {
  if [ -n "${HS_DOMAIN_SHORT:-}" ]; then echo "$HS_DOMAIN_SHORT"; return; fi
  wbinfo --own-domain 2>/dev/null || true
}
has_user() { bash "$mu" --list 2>/dev/null | awk -F'	' -v n="$1" 'tolower($1) == tolower(n) { f = 1 } END { exit !f }'; }   # awk reads all input: no SIGPIPE under pipefail (as grep -q would)

# ---------------------------------------------------------------- mounting
mount_one() {   # mount_one <peer> <host> <share> <login> <domain>: 0 mounted (now or before), 1 not
  local peer=$1 host=$2 share=$3 m cred
  m=$(mnt_of "$peer" "$share"); cred=$(cred_file "$peer")
  is_mounted "$m" && return 0
  case "$(secret_state "$cred")" in ok) ;; locked) note "$(t '%s/%s: the vault is closed, not mounted.' "$peer" "$share")"; return 1 ;; *) warn "$(t '%s/%s: no credentials file.' "$peer" "$share")"; return 1 ;; esac
  mkdir -p "$m"
  # soft + short echo interval: a peer that goes away gives errors after a while instead of hanging every reader
  # shellcheck disable=SC2086
  if timeout 25 ${HS_MOUNT_CMD:-mount -t cifs} "//$host/$share" "$m" \
       -o "credentials=$cred,vers=3,ro,nosuid,nodev,noexec,soft,echo_interval=10,actimeo=30,uid=0,gid=0,file_mode=0444,dir_mode=0555" >/dev/null 2>&1; then
    ok "$(t 'Mounted %s/%s' "$peer" "$share")"
  else
    warn "$(t '%s/%s: %s is not reachable or refused the login; it is tried again.' "$peer" "$share" "$host")"
    return 1
  fi
}

# ---------------------------------------------------------------- pairing by code (the crypto and the code store are the hobnix program)
pair_bin() {   # the hobnix program (HOBNIX_BIN, else the PATH); the pairing needs it
  local b=${HOBNIX_BIN:-}
  [ -n "$b" ] || b=$(command -v hobnix 2>/dev/null || true)
  [ -n "$b" ] && [ -x "$b" ] || fail_fix "The pairing needs the hobnix program; it arrives with the next rebuild." "hs rebuild"
  printf '%s' "$b"
}
pair() { local b; b=$(pair_bin) || exit $?; "$b" pair "$@"; }
# pair_body: like pair, but stdout only is the body (a debug log line on stderr, HOBNIX_LOG=debug, must never end up in a request or an answer);
# when it fails the "hobnix: ..." error line is printed instead, for the caller to show
pair_body() {
  local e rc=0 o; e=$(mktemp) || return 1
  o=$(pair "$@" 2>"$e") || rc=$?
  if [ "$rc" -eq 0 ]; then printf '%s' "$o"; else grep '^hobnix: ' "$e" | tail -n 1 || true; fi
  rm -f "$e"; return "$rc"
}
web_port() { printf '%s' "${HS_WEB_PORT:-8480}"; }
own_name() { local n=${HS_HOST_NAME:-$(hostname)}; printf '%s' "${n,,}"; }
own_hostkey() {   # the public SSH host key of this server: "ssh-ed25519 AAAA..."
  awk 'NF >= 2 { print $1 " " $2; exit }' "${HS_HOST_KEY_FILE:-/etc/ssh/ssh_host_ed25519_key.pub}" 2>/dev/null
}
tagged() { awk -F'\t' -v k="$1" '$1 == k { sub(/^[^\t]*\t/, ""); print; exit }'; }   # the value of one key<TAB>value line on stdin
fp_of_peer() { rows "$OFFERS" | awk -F'\t' -v p="$1" '$1 == p && $5 != "" && $5 != "-" { print $5; exit }'; }
vault_ready() { if vault_configured && ! vault_is_open; then vault_locked_note >&2; fail_fix "The vault is closed." "hs unlock"; fi; }

read_code() {   # read_code <what>: one line from stdin (--stdin) or asked; the code never goes through argv
  local line
  if $stdin_pw; then IFS= read -r line || line=""
  else
    interactive || fail "Missing: the code (give it on standard input with --stdin)."
    line=$(ask_secret "$1")
  fi
  printf '%s' "$line"
}

setup_mount() {   # setup_mount <peer> <host> <share> <login> <domain> <fingerprint|-> <new|reconnect>; the password on stdin. 1 = the name is taken
  # one writer at a time: the count check, the .cred file and the rewrite of the rows are one step (two pairings at once must not both pass)
  mkdir -p "$state"
  if command -v flock >/dev/null 2>&1; then ( flock 8; setup_mount_locked "$@" ) 8>"$state/.remote.lock"
  else setup_mount_locked "$@"; fi
}
setup_mount_locked() {
  local p=$1 h=$2 s=$3 l=$4 d=$5 fp=${6:--} mode=${7:-new} old="" n oldhost
  # The name is taken (Q4) when this server has any mount from it: the credentials file is ONE per name, so the check is per name, not per share.
  # The name and the host key in the answer come from the sender's own box, and a public host key proves nothing (ssh-keyscan), so a taken name is
  # never given away because the box says so. Only the owner of THIS server, who typed `--reconnect <name>` for that existing server, may reuse it,
  # and then the key must still be the stored one. A pushed share (accept-mount) is always `new`.
  n=$(rows "$MOUNTS" | awk -F'\t' -v p="$p" '$1 == p { c++ } END { print c + 0 }')
  old=$(rows "$MOUNTS" | awk -F'\t' -v p="$p" '$1 == p && $6 != "" && $6 != "-" { print $6; exit }')
  if [ "$n" -gt 0 ]; then
    if [ "$mode" != reconnect ] || [ -z "$old" ] || [ "$fp" = "-" ] || [ "$old" != "$fp" ]; then cat >/dev/null; return 1; fi
    # The stored key came from the first answer and a public key proves nothing, so the owner's own record is the anchor: a reconnect never changes
    # the host of an existing server. A server that moved is a new pairing under a new name (remove the old one first).
    oldhost=$(rows "$MOUNTS" | awk -F'\t' -v p="$p" -v h="$h" '$1 == p && $2 != h { print $2; exit }')
    if [ -n "$oldhost" ]; then cat >/dev/null; return 1; fi
  fi
  write_cred "$p" "$l" "$d" 4
  mkdir -p "$state"; touch "$MOUNTS"
  awk -F'\t' -v p="$p" -v s="$s" '!($1 == p && $3 == s)' "$MOUNTS" > "$MOUNTS.new" || true
  mv "$MOUNTS.new" "$MOUNTS"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$p" "$h" "$s" "$l" "$d" "$fp" >> "$MOUNTS"
  mount_one "$p" "$h" "$s" "$l" "$d" || true
}

grant_login() {   # grant_login <peer> <share> <fingerprint|-> <bound|free|new>: sets g_login g_dsh g_pw. 1 = the name belongs to another server, 3 = not possible now
  local p=$1 s=$2 fp=$3 mode=$4 stored exists=false rowsn
  g_login=$(user_of "$p"); g_dsh=$(domain_short)
  [ -n "$g_dsh" ] || return 3
  has_user "$g_login" && exists=true
  rowsn=$(rows "$OFFERS" | awk -F'\t' -v p="$p" '$1 == p { n++ } END { print n + 0 }')
  stored=$(fp_of_peer "$p")
  # A name that is taken (Q4) is given again only for a code the owner BOUND to it (a new code for that server, "Reconnect"), and then only to the server
  # with the stored host key (a legacy offer without a key: the owner's word). A free code (the other server chose the name) and a new name typed by the
  # owner (`send`) never touch an existing login: its password would be reset and boxed to whoever holds the code.
  if $exists || [ "$rowsn" -gt 0 ]; then
    [ "$mode" = bound ] || return 1
    if [ -n "$stored" ]; then [ "$fp" != "-" ] && [ "$fp" = "$stored" ] || return 1; fi
  fi
  g_pw=$(gen_password)
  if $exists; then printf '%s\n' "$g_pw" | bash "$mu" --password "$g_login" --stdin >/dev/null 2>&1 || return 3
  else printf '%s\n' "$g_pw" | bash "$mu" --add "$g_login" --full "Remote $p" --stdin >/dev/null 2>&1 || return 3; fi
  bash "$mu" --flush >/dev/null 2>&1 || true
  bash "$sp" "$s" "$g_login=read" >/dev/null 2>&1 || return 3
  [ "$fp" != "-" ] || fp=${stored:--}
  mkdir -p "$state"; touch "$OFFERS"
  drop "$OFFERS" "$p" "$s"
  printf '%s\t%s\t%s\t%s\t%s\n' "$p" "$s" "$g_login" "$(today)" "$fp" >> "$OFFERS"
}

split_server() {   # split_server <name|host[:port]>: sets s_url_base (http://host:port, or https://host for a tailnet name)
  local h=$1
  v_host "$h"
  case "$h" in
    *.ts.net) s_url_base="https://$h" ;;
    *:*) s_url_base="http://$h" ;;
    *) s_url_base="http://$h:$(web_port)" ;;
  esac
}

post_json() {   # post_json <url> <body>: sets p_status and p_body (the body is not secret: an id and a box)
  local resp
  resp=$(printf '%s' "$2" | ${HS_CURL:-curl} -sS --max-time 20 --connect-timeout 8 -w '\n%{http_code}' \
    -H 'Content-Type: application/json' --data-binary @- "$1" 2>/dev/null) || { p_status=000; p_body=""; return 0; }
  p_status=${resp##*$'\n'}; p_body=${resp%$'\n'*}
}

refusal_text() {   # refusal_text <status> <body>: why a server said no (never more than the error name)
  case "$2" in
    *code.rate*) t "Too many wrong codes from here. Wait a minute and try again." ;;
    *code.unavailable*) t "The other server cannot make the access now (is its storage unlocked?)." ;;
    *code.unknown*) t "The other server does not know that code: wrong, already used or expired." ;;
    *) if [ "$1" = nodelink ]; then t "The node link cannot reach the pairing service of the other server (it needs no password for hs there). Use its address: --server <host>."; else
       if [ "$1" = 000 ]; then t "The other server did not answer."; else t "The other server answered with an error (%s)." "$1"; fi; fi ;;
  esac
}

is_node() { bash "$node_sh" --list 2>/dev/null | awk -F'\t' -v n="$1" '$1 == n && $2 == "peer" && $6 == "ok" { f = 1 } END { exit !f }'; }

offer_code() {   # offer <share> --code: make a code the other server types
  [ $# -eq 1 ] || usage
  local share=$1 srv=${peer:--} mins=${minutes:--} out c exp addr
  v_share "$share"; [ "$srv" = "-" ] || v_peer "$srv"
  { [ "$mins" = "-" ] || [[ "$mins" =~ ^[0-9]{1,2}$ ]]; } || fail "The life time is a number of minutes (1 to 60)."
  need_root
  sure "$yes" "$(t 'Make a code for %s?' "$share")"
  out=$(pair_body make offer "$share" "$srv" "$mins") || fail "${out#hobnix: }"
  c=$(tagged code <<<"$out"); exp=$(tagged expires_in <<<"$out")
  addr="$(own_name).local:$(web_port)"
  event_emit remote.code.made "$share" "" --payload "{\"share\":\"$share\",\"server\":\"$srv\"}" || true
  if $plain; then
    printf 'code-result\tcode\t%s\ncode-result\taddress\t%s\ncode-result\texpires_in\t%s\n' "$c" "$addr" "$exp"
    return 0
  fi
  box <<EOT
$(say "Type this on the other server (it works once, for $((exp / 60)) minutes):")

  hs remote add --code --server $addr

$(say "when it asks for the code:")  $c@$addr

$(say "Take back later with:")  hs remote revoke ${peer:-<name>} $share
EOT
  note "$(t 'If the other server is in your node list, hs remote add --code --server <node name> uses the node link.')"
}

receive_code() {   # receive [--minutes N]: this server shows a code, the other one types it and picks the share
  [ $# -eq 0 ] || usage
  local mins=${minutes:--} out c exp addr
  { [ "$mins" = "-" ] || [[ "$mins" =~ ^[0-9]{1,2}$ ]]; } || fail "The life time is a number of minutes (1 to 60)."
  need_root
  vault_ready
  sure "$yes" "Make a code?"
  out=$(pair_body make receive - - "$mins") || fail "${out#hobnix: }"
  c=$(tagged code <<<"$out"); exp=$(tagged expires_in <<<"$out")
  addr="$(own_name).local:$(web_port)"
  event_emit remote.code.made "-" "" --payload '{"share":"-","server":"-"}' || true
  if $plain; then
    printf 'code-result\tcode\t%s\ncode-result\taddress\t%s\ncode-result\texpires_in\t%s\n' "$c" "$addr" "$exp"
    return 0
  fi
  box <<EOT
$(say "On the server that gives the share (the code works once, for $((exp / 60)) minutes):")

  hs remote send <share> --peer <a name for this server> --code --server $addr

$(say "and type this code when asked:")  $c
EOT
}

add_code() {   # add --code [--server <name|host>] [--reconnect <server>] [--stdin]: type the code another server made
  [ $# -eq 0 ] || usage
  local line fields c at srv hostn hk req inner p h s l d pw fp rc=0
  need_root
  vault_ready
  line=$(read_code "Code (as shown on the other server)")
  fields=$(printf '%s\n' "$line" | pair check 2>/dev/null) || fail "That is not a code (16 letters and digits, as shown on the other server)."
  c=${fields%%$'\t'*}; at=${fields#*$'\t'}
  srv=$server; if [ -z "$srv" ] && [ "$at" != "-" ]; then srv=$at; fi
  [ -n "$srv" ] || fail "Missing: the server (--server <name|address>, or <code>@<address>)."
  hostn=$(own_name); v_peer "$hostn"
  hk=$(own_hostkey) || true
  [ -n "$hk" ] || fail "This server has no SSH host key to show the other side."
  req=$(printf 'code\t%s\nname\t%s\nhostkey\t%s\n' "$c" "$hostn" "$hk" | pair_body request) || fail "${req#hobnix: }"
  if is_node "$srv"; then   # the node link: SSH with the node key, the host key is pinned already
    p_body=$(printf '%s' "$req" | bash "$node_sh" --pair "$srv" 2>/dev/null) || rc=$?
    case "$rc" in 0) p_status=200 ;; 1) p_status=404 ;; 3) p_status=nodelink; p_body="" ;; *) p_status=000; p_body="" ;; esac
  else
    split_server "$srv"
    post_json "$s_url_base/api/remote/claim" "$req"
  fi
  [ "$p_status" = 200 ] || fail "$(refusal_text "$p_status" "$p_body")"
  inner=$(printf 'code\t%s\nrequest\t%s\nanswer\t%s\n' "$c" "$req" "$p_body" | pair_body open) || fail "${inner#hobnix: }"
  p=$(tagged server <<<"$inner"); h=$(tagged host <<<"$inner"); s=$(tagged share <<<"$inner"); l=$(tagged login <<<"$inner")
  d=$(tagged domain <<<"$inner"); pw=$(tagged password <<<"$inner"); fp=$(tagged fingerprint <<<"$inner")
  v_peer "$p"; v_host "$h"; v_share "$s"; v_login "$l"; [ -z "$d" ] || v_login "$d"
  step "$(t 'Mount %s from %s' "$s" "$p")"
  kv "Address" "//$h/$s"
  kv "Where" "$(mnt_of "$p" "$s")"
  if [ -n "$reconnect" ]; then
    # anchored to what this server already knows: the address the code points to AND the host in the answer must be the stored host of that server
    local want shost; want=$(rows "$MOUNTS" | awk -F'\t' -v p="$reconnect" '$1 == p { print $2; exit }'); shost=${srv%:*}
    [ "$reconnect" = "$p" ] || fail "$(t "The answer comes from '%s', not from '%s'. Not changed." "$p" "$reconnect")"
    [ -n "$want" ] || fail "$(t "Nothing is mounted from '%s': use hs remote add --code without --reconnect." "$reconnect")"
    # ONE rule for every path: the host the code points to (HTTP: the address typed; node link: the host of that node in the node list; a label proves
    # nothing) and the host in the answer must both be the stored host of that server
    local addr_ok=false nh=$shost
    if is_node "$srv"; then nh=$(bash "$node_sh" --list 2>/dev/null | awk -F'\t' -v n="$srv" '$1 == n { print $3; exit }'); fi
    [ "${nh,,}" = "${want,,}" ] && addr_ok=true
    if [ "$h" != "$want" ] || ! $addr_ok; then
      fail_fix "$(t "A reconnect must reach the address stored for %s (%s); the code points to %s and the answer says %s. Nothing is changed. If the server moved, remove it first." "$p" "$want" "$srv" "$h")" "hs remote remove $p"
    fi
  fi
  local smrc=0
  printf '%s\n' "$pw" | setup_mount "$p" "$h" "$s" "$l" "$d" "$fp" "${reconnect:+reconnect}" || smrc=$?
  [ "$smrc" -ne 4 ] || fail "The login could not be saved (is the vault open? hs unlock). Nothing is changed."
  [ "$smrc" -eq 0 ] \
    || fail_fix "$(t "'%s' is already mounted here and the answer does not prove it is the same server. Nothing is changed. To renew it, use a code of that server with --reconnect %s; for a different server, remove it first." "$p" "$p")" "hs remote remove $p"
  ok "$(t 'Connected to %s, key %s' "$p" "$fp")"
  note "$(t 'Compare the key with the screen of %s.' "$p")"
  next_step "hs remote attach $p <instance>"
}

send_code() {   # send <share> --peer <name> --code [--server <host>] [--stdin]: the other server showed a code, this one gives the share
  [ $# -eq 1 ] && [ -n "$peer" ] || usage
  local share=$1 line fields c at srv body rc=0
  v_share "$share"; v_peer "$peer"
  need_root
  line=$(read_code "Code (as shown on the other server)")
  fields=$(printf '%s\n' "$line" | pair check 2>/dev/null) || fail "That is not a code (16 letters and digits, as shown on the other server)."
  c=${fields%%$'\t'*}; at=${fields#*$'\t'}
  srv=$server; if [ -z "$srv" ] && [ "$at" != "-" ]; then srv=$at; fi
  [ -n "$srv" ] || fail "Missing: the server (--server <address>, or <code>@<address>)."
  split_server "$srv"
  step "$(t 'Give %s read access to %s' "$peer" "$share")"
  sure "$yes" "Go ahead?"
  grant_login "$peer" "$share" "-" new || rc=$?
  [ "$rc" -ne 1 ] || fail "$(t "'%s' has an access from this server already. Take it back first (hs remote revoke %s), or make a code with hs remote offer <share> --code --peer %s on this server and type it there." "$peer" "$peer" "$peer")"
  [ "$rc" -eq 0 ] || fail "The access could not be made (is the storage unlocked and the domain up?)."
  body=$(printf 'code\t%s\nserver\t%s\nhost\t%s\nshare\t%s\nlogin\t%s\ndomain\t%s\npassword\t%s\nhostkey\t%s\n' \
    "$c" "$(own_name)" "$(own_name).local" "$share" "$g_login" "$g_dsh" "$g_pw" "$(own_hostkey || true)" | pair_body push) \
    || { bash "$0" revoke "$peer" "$share" --yes >/dev/null 2>&1 || true; fail "${body#hobnix: }"; }
  post_json "$s_url_base/api/remote/push" "$body"
  if [ "$p_status" != 200 ]; then
    bash "$0" revoke "$peer" "$share" --yes >/dev/null 2>&1 || true   # nothing was handed over: take the login back
    fail "$(refusal_text "$p_status" "$p_body")"
  fi
  ok "$(t '%s can read %s.' "$peer" "$share")"
  note "$(t 'Take back later with: hs remote revoke %s %s' "$peer" "$share")"
}

# ---------------------------------------------------------------- commands
cmd=${1:-}
[ -n "$cmd" ] || usage
shift

yes=false; stdin_pw=false; newpw=false; plain=false; code=false; cancel=false
peer=""; login=""; domain=""; path=""; server=""; minutes=""; reconnect=""; pos=()
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) yes=true ;;
    --plain) plain=true ;;
    --stdin) stdin_pw=true ;;
    --new-password) newpw=true ;;
    --code) code=true ;;
    --cancel) cancel=true ;;
    --server) [ $# -ge 2 ] || usage; server=$2; shift ;;
    --reconnect) [ $# -ge 2 ] || usage; reconnect=$2; shift ;;
    --minutes) [ $# -ge 2 ] || usage; minutes=$2; shift ;;
    --peer)   [ $# -ge 2 ] || usage; peer=$2; shift ;;
    --user)   [ $# -ge 2 ] || usage; login=$2; shift ;;
    --domain) [ $# -ge 2 ] || usage; domain=$2; shift ;;
    --path)   [ $# -ge 2 ] || usage; path=$2; shift ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) pos+=("$1") ;;
  esac
  shift
done
set -- "${pos[@]+"${pos[@]}"}"

case "$cmd" in
  list)
    if [ -t 1 ] && [ -z "${HS_CALLER:-}" ]; then
      step "Access given"
      if [ -n "$(rows "$OFFERS")" ]; then { thead 'Peer' 'Share' 'Login' 'Since' 'Host key'; rows "$OFFERS"; } | table; else note "Nothing is shared with another server."; fi
      step "Mounted from other servers"
      if [ -n "$(rows "$MOUNTS")" ]; then
        { thead 'Peer' 'Share' 'Host' 'State'
          while IFS=$'\t' read -r p h s _; do
            printf '%s\t%s\t%s\t%s\n' "$p" "$s" "$h" "$(if is_mounted "$(mnt_of "$p" "$s")"; then _tr mounted; else _tr 'not mounted'; fi)"
          done < <(rows "$MOUNTS"); } | table
      else note "Nothing is mounted from another server."; fi
    else
      # machine-readable: kind, peer, share, host-or-login, state
      while IFS=$'\t' read -r p s l _; do printf 'offer\t%s\t%s\t%s\tgiven\n' "$p" "$s" "$l"; done < <(rows "$OFFERS")
      while IFS=$'\t' read -r p h s _; do
        printf 'mount\t%s\t%s\t%s\t%s\n' "$p" "$s" "$h" "$(if is_mounted "$(mnt_of "$p" "$s")"; then echo mounted; else echo down; fi)"
      done < <(rows "$MOUNTS")
    fi ;;

  offer)
    if $code; then offer_code "$@"; exit 0; fi
    [ $# -eq 1 ] && [ -n "$peer" ] || usage
    share=$1; v_share "$share"; v_peer "$peer"
    need_root
    login=$(user_of "$peer")
    dsh=$(domain_short)
    exists=false; has_user "$login" && exists=true
    pw=""
    if ! $exists || $newpw; then pw=$(gen_password); fi
    step "$(t 'Give %s read access to %s' "$peer" "$share")"
    kv "Login" "${dsh:+$dsh\\}$login"
    if $exists && ! $newpw; then note "The login exists already; its password stays as it is (--new-password makes a new one)."; fi
    note "$(t 'The login can only read the share %s, nothing else.' "$share")"
    sure "$yes" "Go ahead?"
    if [ -n "$pw" ]; then
      if $exists; then printf '%s\n' "$pw" | bash "$mu" --password "$login" --stdin
      else printf '%s\n' "$pw" | bash "$mu" --add "$login" --full "Remote $peer" --stdin; fi
      bash "$mu" --flush >/dev/null 2>&1 || true
    fi
    bash "$sp" "$share" "$login=read" >/dev/null
    mkdir -p "$state"; touch "$OFFERS"
    drop "$OFFERS" "$peer" "$share"
    printf '%s\t%s\t%s\t%s\t%s\n' "$peer" "$share" "$login" "$(today)" "$(fp_of_peer "$peer" | awk '{ print } END { if (NR == 0) print "-" }')" >> "$OFFERS"
    ok "$(t '%s can read %s.' "$peer" "$share")"
    hostn=${HS_HOST_NAME:-$(hostname)}; hostn=${hostn,,}
    if $plain; then   # for the web interface (peer-change.sh): tagged lines, the password only when a new one was made
      printf 'offer-result\tlogin\t%s\n' "$login"
      [ -z "$dsh" ] || printf 'offer-result\tdomain\t%s\n' "$dsh"
      printf 'offer-result\thost\t%s\n' "$hostn.local"
      [ -z "$pw" ] || printf 'offer-result\tpassword\t%s\n' "$pw"
      exit 0
    fi
    pwline=""
    if [ -n "$pw" ]; then pwline="$(say 'Password (shown once, they type it when asked):')  $pw"; fi
    box <<EOF
$(say "Tell the other person (on their server):")

  hs remote add $hostn $hostn.local $share --user $login${dsh:+ --domain $dsh}

$pwline
$(say "Revoke later with:")  hs remote revoke $peer $share
EOF
    ;;

  revoke)
    [ $# -ge 1 ] || usage
    p=$1; s=${2:-}; v_peer "$p"; [ -z "$s" ] || v_share "$s"
    need_root
    login=$(user_of "$p")
    shares=$(rows "$OFFERS" | awk -F'\t' -v p="$p" -v s="$s" '$1 == p && (s == "" || $2 == s) { print $2 }')
    [ -n "$shares" ] || fail_fix "$(t "Nothing is shared with '%s'." "$p")" "hs remote list"
    step "$(t 'Take access away from %s' "$p")"
    while read -r sh; do kv "Share" "$sh"; done <<<"$shares"
    note "$(t "Their login '%s' is deleted when no share is left." "$login")"
    sure "$yes" "Go ahead?"
    while read -r sh; do
      bash "$sp" "$sh" "$login=none" >/dev/null || warn "$(t 'Could not change the permissions of %s.' "$sh")"
      drop "$OFFERS" "$p" "$sh"
    done <<<"$shares"
    if [ -z "$(rows "$OFFERS" | awk -F'\t' -v p="$p" '$1 == p')" ] && has_user "$login"; then
      bash "$mu" --delete "$login" --yes
    fi
    ok "$(t 'Access of %s revoked. Open connections end when they are closed.' "$p")" ;;

  add)
    if $code; then add_code "$@"; exit 0; fi
    [ $# -eq 3 ] && [ -n "$login" ] || usage
    p=$1; h=$2; s=$3; v_peer "$p"; v_host "$h"; v_share "$s"; v_login "$login"
    [ -z "$domain" ] || v_login "$domain"
    need_root
    ! rows "$MOUNTS" | awk -F'\t' -v p="$p" -v s="$s" '$1 == p && $3 == s { f = 1 } END { exit !f }' || fail_fix "$(t "'%s' / '%s' is set up already." "$p" "$s")" "hs remote remove $p $s"
    step "$(t 'Mount %s from %s' "$s" "$p")"
    kv "Address" "//$h/$s"
    kv "Login" "${domain:+$domain\\}$login"
    kv "Where" "$(mnt_of "$p" "$s")"
    note "Read only. Not part of /bulk, the parity or the backup."
    sure "$yes" "Go ahead?"
    if $stdin_pw; then IFS= read -r pw || pw=""
    else
      interactive || fail "Missing: the password (give it on standard input with --stdin)."
      pw=$(ask_secret "$(t 'Password of %s' "$login")")
    fi
    printf '%s\n' "$pw" | write_cred "$p" "$login" "$domain"
    mkdir -p "$state"; touch "$MOUNTS"
    printf '%s\t%s\t%s\t%s\t%s\t-\n' "$p" "$h" "$s" "$login" "$domain" >> "$MOUNTS"
    if mount_one "$p" "$h" "$s" "$login" "$domain"; then
      next_step "hs remote attach $p <instance>"
    else
      warn "The login or the address may be wrong. It stays set up and is tried every 2 minutes (hs remote list)."
    fi ;;

  remove)
    [ $# -ge 1 ] || usage
    p=$1; s=${2:-}; v_peer "$p"; [ -z "$s" ] || v_share "$s"
    need_root
    list=$(rows "$MOUNTS" | awk -F'\t' -v p="$p" -v s="$s" '$1 == p && (s == "" || $3 == s) { print $3 }')
    [ -n "$list" ] || fail_fix "$(t "Nothing is mounted from '%s'." "$p")" "hs remote list"
    step "$(t 'Stop using %s' "$p")"
    while read -r sh; do kv "Share" "$sh"; done <<<"$list"
    note "Instances that got the folder with 'attach' keep an empty folder."
    sure "$yes" "Go ahead?"
    while read -r sh; do
      m=$(mnt_of "$p" "$sh")
      if is_mounted "$m"; then ${HS_UMOUNT:-umount} "$m" || fail "$(t '%s is in use: stop what reads it first.' "$m")"; fi
      rmdir "$m" 2>/dev/null || true
      awk -F'\t' -v p="$p" -v s="$sh" '!($1 == p && $3 == s)' "$MOUNTS" > "$MOUNTS.new" || true
      mv "$MOUNTS.new" "$MOUNTS"
    done <<<"$list"
    if [ -z "$(rows "$MOUNTS" | awk -F'\t' -v p="$p" '$1 == p')" ]; then
      rm -f "$(cred_file "$p")"; rmdir "$root/$p" 2>/dev/null || true
    fi
    ok "$(t 'Removed. Files on the other server are untouched.')" ;;

  attach)
    [ $# -eq 2 ] || usage
    p=$1; c=$2; v_peer "$p"; v_ct "$c"
    need_root
    [ -n "$(rows "$MOUNTS" | awk -F'\t' -v p="$p" '$1 == p')" ] || fail_fix "$(t "Nothing is mounted from '%s'." "$p")" "hs remote list"
    [ -n "$path" ] || path=/media-$p
    case "$path" in /*) ;; *) fail "The path inside the instance starts with /." ;; esac
    mkdir -p "$root/$p"
    dev=remote-$p
    "$incus_bin" info "$c" >/dev/null 2>&1 || fail_fix "$(t "No instance called '%s'." "$c")" "hs ct list"
    refuse_if_locked "$c" "$(t 'adding a device')"
    if "$incus_bin" config device get "$c" "$dev" source >/dev/null 2>&1; then fail_fix "$(t "'%s' has the device %s already." "$c" "$dev")" "hs remote detach $p $c"; fi
    "$incus_bin" config device add "$c" "$dev" disk source="$root/$p" path="$path" recursive=true propagation=rslave >/dev/null
    ok "$(t '%s sees the shares of %s under %s (read only).' "$c" "$p" "$path")" ;;

  detach)
    [ $# -eq 2 ] || usage
    p=$1; c=$2; v_peer "$p"; v_ct "$c"
    need_root
    refuse_if_locked "$c" "$(t 'removing a device')"
    "$incus_bin" config device remove "$c" "remote-$p" >/dev/null 2>&1 || fail "$(t "'%s' has no device remote-%s." "$c" "$p")"
    ok "$(t 'Removed from %s.' "$c")" ;;

  codes)
    [ $# -eq 0 ] || usage
    b=$(pair_bin) || exit $?
    if $cancel; then
      need_root
      n=$(pair cancel | tagged cancelled)
      ok "$(t 'Ended %s open codes.' "${n:-0}")"; exit 0
    fi
    lines=$("$b" remote-codes) || exit $?
    if [ -t 1 ] && [ -z "${HS_CALLER:-}" ]; then
      step "Open codes"
      if [ -n "$lines" ]; then
        { thead 'Share' 'Server' 'Expires in'
          while IFS=$'\t' read -r sh sv ex; do printf '%s\t%s\t%s min\n' "$sh" "$sv" "$(( (ex + 59) / 60 ))"; done <<<"$lines"; } | table
      else note "No code is open."; fi
    elif [ -n "$lines" ]; then printf '%s\n' "$lines"; fi ;;

  receive) receive_code "$@" ;;
  send) send_code "$@" ;;

  grant)   # internal (hobnix remote-claim): grant <server> <share> <fingerprint> <bound|free>; tagged lines on stdout, exit 1 = the name belongs to another server, 3 = not possible
    [ $# -eq 4 ] || exit 3
    v_peer "$1"; v_share "$2"
    need_root
    rc=0; grant_login "$1" "$2" "$3" "$4" || rc=$?
    [ "$rc" -eq 0 ] || exit "$rc"
    printf 'server\t%s\nhost\t%s\nlogin\t%s\ndomain\t%s\npassword\t%s\nhostkey\t%s\n' "$(own_name)" "$(own_name).local" "$g_login" "$g_dsh" "$g_pw" "$(own_hostkey || true)" ;;

  accept-mount)   # internal (hobnix remote-accept): accept-mount <server> <host> <share> <login> <domain> <fingerprint|->, the password on stdin; exit 1 = the name is taken, 3 = not possible
    [ $# -eq 6 ] || exit 3
    v_peer "$1"; v_host "$2"; v_share "$3"; v_login "$4"; [ -z "$5" ] || v_login "$5"
    need_root
    if vault_configured && ! vault_is_open; then exit 3; fi
    rc=0; setup_mount "$1" "$2" "$3" "$4" "$5" "$6" new || rc=$?   # a pushed share never reuses a name: the sender's box proves nothing
    [ "$rc" -eq 0 ] || exit "$rc"
    note "$(t 'Mounted %s from %s as %s (pushed by that server).' "$3" "$2" "$1")"
    exit 0 ;;

  mount-all)   # the timer: mount what is configured and not mounted; never fails the unit because a peer is off
    [ -n "$(rows "$MOUNTS")" ] || exit 0
    while IFS=$'\t' read -r p h s l d _; do mount_one "$p" "$h" "$s" "$l" "$d" || true; done < <(rows "$MOUNTS")
    exit 0 ;;

  *) usage ;;
esac
