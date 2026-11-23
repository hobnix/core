#!/usr/bin/env bash
# Pairing of remote shares by code (docs/PLAN-remote-shares.md): the hobnix program (rust/hobnix-core/src/pair.rs) with remote.sh as glue,
# both servers played on one machine with fake manage-users, share-perm and curl. Checks: code made and listed, claim end to end, one use,
# wrong code, taken name (Q4), rate limit, the code and the password in no argv or file, the reverse direction (receive + send).
# The binary: HOBNIX_BIN, else rust/target/debug|release/hobnix. Without one, or off Linux, the test is skipped (77).
root=$(cd "$(dirname "$0")/.." && pwd)
bin=${HOBNIX_BIN:-}
if [ -z "$bin" ]; then
  [ "$(uname -s)" = Linux ] || { echo "  skip  needs Linux (WSL) or HOBNIX_BIN"; exit 77; }
  for c in "$root/rust/target/debug/hobnix" "$root/rust/target/release/hobnix"; do [ -x "$c" ] && { bin=$c; break; }; done
fi
[ -n "$bin" ] && [ -x "$bin" ] || { echo "  skip  no hobnix binary (cargo build in rust/, or HOBNIX_BIN)"; exit 77; }
# shellcheck source=tests/lib.sh
. "$root/tests/lib.sh"
T=$'\t'
unset HOBNIX_LOG HS_GUIDED_TTY
export HOBNIX_BIN=$bin HS_SCRIPTS=$SCRIPTS HS_CALLER=test HS_PLAIN=1 HS_LANG=en HS_EVENT_NOROOT=1 HS_WEB_PORT=8480

# one fake server: its state dir, its fake manage-users (a list of logins), share-perm, host key
mkserver() {   # mkserver <dir> <name>
  local d=$1 n=$2
  mkdir -p "$d/state" "$d/bin"
  : > "$d/users"
  cat > "$d/bin/mu.sh" <<EOF
#!/usr/bin/env bash
case "\$1" in
  --list) awk '{ print \$1 "\tx" }' "$d/users" ;;
  --add) echo "\$2" >> "$d/users"; cat > "$d/last-pw" ;;
  --password) cat > "$d/last-pw" ;;
  --delete) grep -vx "\$2" "$d/users" > "$d/users.new"; mv "$d/users.new" "$d/users" ;;
  *) ;;
esac
EOF
  printf '#!/usr/bin/env bash\necho "\$@" >> "%s/perm.log"\n' "$d" > "$d/bin/sp.sh"
  printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI%s comment\n' "$(printf '%-43s' "${n}key" | tr ' ' 'A')" > "$d/hostkey.pub"
}
srv() {   # srv <dir> <name> cmd...: run remote.sh as that server
  local d=$1 n=$2; shift 2
  HS_STATE_DIR=$d/state HS_MANAGE_USERS=$d/bin/mu.sh HS_SHARE_PERM=$d/bin/sp.sh HS_HOST_NAME=$n HS_DOMAIN_SHORT=HOME \
    HS_HOST_KEY_FILE=$d/hostkey.pub HS_REMOTE_CODES=$d/codes.json HS_REMOTE_ROOT=$d/mnt HS_MOUNT_CMD=true HS_MOUNTPOINT=false \
    HS_VAULT_DIR=$d/novault bash "$SCRIPTS/remote.sh" "$@"
}
A=$WORK/a; B=$WORK/b
mkserver "$A" alpha; mkserver "$B" beta
# fake curl: the "network" is a direct call of `hobnix remote-claim|remote-accept` on server A (or B for a push)
cat > "$WORK/curl.sh" <<EOF
#!/usr/bin/env bash
url=\${@: -1}
case "\$url" in */claim) w=remote-claim; d=$A; n=alpha ;; */push) w=remote-accept; d=$B; n=beta ;; *) exit 7 ;; esac
export HS_STATE_DIR=\$d/state HS_MANAGE_USERS=\$d/bin/mu.sh HS_SHARE_PERM=\$d/bin/sp.sh HS_HOST_NAME=\$n HS_DOMAIN_SHORT=HOME \\
  HS_HOST_KEY_FILE=\$d/hostkey.pub HS_REMOTE_CODES=\$d/codes.json HS_REMOTE_ROOT=\$d/mnt HS_MOUNT_CMD=true HS_MOUNTPOINT=false HS_VAULT_DIR=\$d/novault
out=\$("$bin" \$w --source \${FAKE_SRC:-10.0.0.9}); rc=\$?
printf '%s\n%s' "\$out" "\$( [ \$rc = 0 ] && echo 200 || { case "\$out" in *code.rate*) echo 429 ;; *code.unknown*) echo 404 ;; *) echo 503 ;; esac; } )"
EOF
chmod +x "$WORK/curl.sh"
export HS_CURL=$WORK/curl.sh
# a node list without nodes
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/node.sh"; export HS_NODE=$WORK/node.sh

echo "-- offer --code: a code is made and listed, never stored in the clear"
out=$(srv "$A" alpha offer media --code --plain --yes) || fail "offer --code failed: $out"
code=$(awk -F'\t' '$2 == "code" { print $3 }' <<<"$out"); addr=$(awk -F'\t' '$2 == "address" { print $3 }' <<<"$out")
[ ${#code} -eq 19 ] && pass "a code of four groups of four" || fail "code: $code"
check_eq "the address always shows the port" "alpha.local:8480" "$addr"
lst=$(HS_REMOTE_CODES=$A/codes.json "$bin" remote-codes)
case "$lst" in "media${T}-${T}"[0-9][0-9][0-9]) pass "remote-codes lists share, server, seconds left" ;; *) fail "remote-codes: $lst" ;; esac
raw=$(tr -d '-' <<<"$code")
if grep -q "$raw" "$A/codes.json" || grep -q "$code" "$A/codes.json"; then fail "the code is in the store"; else pass "the store holds derived values only"; fi
[ "$(stat -c %a "$A/codes.json")" = 600 ] && pass "the store is 0600" || fail "store mode"

echo "-- add --code: claim, open, mount row, the password reaches B"
out=$(printf '%s\n' "$code@$addr" | srv "$B" beta add --code --stdin 2>&1) && pass "add --code ran" || fail "add --code: $out"
grep -q "^alpha${T}alpha.local${T}media${T}remote-beta" "$B/state/remote-mounts" && pass "the mount row names alpha / media / remote-beta" || fail "mounts: $(cat "$B/state/remote-mounts" 2>&1)"
grep -q "^remote-beta$" "$A/users" && pass "A has the login remote-beta" || fail "A users"
grep -q "^beta${T}media${T}remote-beta" "$A/state/remote-offers" && pass "A kept the offer with the key fingerprint" || fail "offers"
check_eq "the fingerprint column is set" "SHA256" "$(awk -F'\t' '{ print substr($5, 1, 6) }' "$A/state/remote-offers")"
echo "$out" | grep -q "Connected to alpha, key SHA256:" && pass "the key fingerprint is shown" || fail "no fingerprint line: $out"
pw=$(cat "$A/last-pw")
if grep -rq "$pw" "$A/state" "$A/codes.json" "$B/codes.json" 2>/dev/null; then fail "the password is in a state file of A"; else pass "A keeps no password"; fi
grep -q "password=$pw" "$B/state/remote-alpha.cred" && pass "the password is in B's credentials file" || fail "cred file"

echo "-- one use, wrong code, rate limit"
out=$(printf '%s\n' "$code@$addr" | srv "$B" beta add --code --stdin 2>&1) && fail "a used code worked again" || pass "a used code is refused"
echo "$out" | grep -q "does not know that code" && pass "one answer: unknown" || fail "text: $out"
out=$(srv "$A" alpha offer media --code --plain --yes) && code2=$(awk -F'\t' '$2 == "code" { print $3 }' <<<"$out")
for i in 1 2 3 4 5; do printf 'AAAA-BBBB-CCCC-DDDD@%s\n' "$addr" | srv "$B" beta add --code --stdin >/dev/null 2>&1; done
out=$(printf '%s\n' "$code2@$addr" | srv "$B" beta add --code --stdin 2>&1) && fail "rate limit did not hold" || pass "6th try from one source is refused"
echo "$out" | grep -q "Too many" && pass "the refusal is code.rate" || fail "rate text: $out"
out=$(printf '%s\n' "$code2@$addr" | FAKE_SRC=10.0.0.77 srv "$B" beta add --code --stdin 2>&1) && pass "another source still works" || fail "other source: $out"

echo "-- a name taken by another server is refused (Q4)"
out=$(srv "$A" alpha offer media --code --plain --yes) && code3=$(awk -F'\t' '$2 == "code" { print $3 }' <<<"$out")
mkserver "$WORK/c" beta   # another server that also calls itself beta: another host key
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ x\n' > "$WORK/c/hostkey.pub"
out=$(printf '%s\n' "$code3@$addr" | srv "$WORK/c" beta add --code --stdin 2>&1) && fail "a taken name was given away" || pass "the second beta is refused"

echo "-- list keeps its shape"
l=$(srv "$B" beta list); echo "$l" | grep -q "^mount${T}alpha${T}media${T}alpha.local${T}" && pass "hs remote list: mount line unchanged" || fail "list: $l"
l=$(srv "$A" alpha list); echo "$l" | grep -q "^offer${T}beta${T}media${T}remote-beta${T}given$" && pass "hs remote list: offer line unchanged" || fail "list: $l"

echo "-- reverse: receive on B, send on A"
out=$(srv "$B" beta receive --plain --yes) && rcode=$(awk -F'\t' '$2 == "code" { print $3 }' <<<"$out") || fail "receive: $out"
mkdir -p "$WORK/d"; mkserver "$WORK/d" gamma
srv "$WORK/d" gamma remove alpha --yes >/dev/null 2>&1
out=$(printf '%s\n' "$rcode@beta.local:8480" | srv "$A" alpha send docs --peer gamma --code --stdin --yes 2>&1) && pass "send ran" || fail "send: $out"
grep -q "^alpha${T}alpha.local${T}docs${T}remote-gamma" "$B/state/remote-mounts" && pass "B mounts docs of alpha" || fail "B mounts: $(cat "$B/state/remote-mounts")"
out=$(printf '%s\n' "$rcode@beta.local:8480" | srv "$A" alpha send docs --peer gamma --code --stdin --yes 2>&1) && fail "a used receive code worked" || pass "a used receive code is refused"

echo "-- no secret in argv of the programs (the code goes on stdin)"
grep -n 'pair request\|pair open\|pair push\|pair check' "$SCRIPTS/remote.sh" | grep -v '|' | grep -q . && fail "a pair call without stdin pipe" || pass "every pair call reads the code from a pipe"

finish
