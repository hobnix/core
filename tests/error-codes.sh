#!/usr/bin/env bash
# Error codes (ADR 0028): every code a script or the web server emits is in scripts/lib/error-codes.tsv, and docs/errors.md is generated from it.
# No root, no server.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
GEN="python3 $SCRIPTS/errors-doc-gen.py"
CAT=$SCRIPTS/lib/error-codes.tsv

echo "-- the committed table is current"
check "docs/errors.md is up to date (else: python3 scripts/errors-doc-gen.py write)" $GEN check

echo "-- a new code makes it stale"
tmp=$(mktemp)
cp "$CAT" "$tmp"
printf 'x.new\tscript\ta test code\tA test.\t-\n' >>"$tmp"
if $GEN check --tsv "$tmp" >/dev/null 2>&1; then fail "a tsv row missing in docs/errors.md was not noticed"; else pass "a stale table is detected"; fi
printf 'Bad_Code\tscript\tx\ty\t-\n' >"$tmp"
if $GEN codes --tsv "$tmp" >/dev/null 2>&1; then fail "a badly named code was accepted"; else pass "a badly named code is refused"; fi
rm -f "$tmp"

echo "-- every emitted code is in the catalogue"
known=$($GEN codes)
bad=
while IFS= read -r c; do
  [ -n "$c" ] || continue
  grep -qxF "$c" <<<"$known" || bad="$bad $c"
done < <({
  grep -rhoE 'refuse_code [a-z][a-z0-9.-]*' "$SCRIPTS" --include='*.sh' | grep -v 'refuse_code <' | awk '{print $2}'
  grep -rhoE "code\\t[a-z][a-z0-9.-]*" "$SCRIPTS" --include='*.sh' | sed 's/^code\t//'
  grep -hoE '"run\.[a-z-]+"' "$SCRIPTS/web-serve.py" | tr -d '"'
} | sort -u)
if [ -z "$bad" ]; then pass "all emitted codes are listed"; else fail "codes not in scripts/lib/error-codes.tsv:$bad"; fi

echo "-- refuse_code prints the lines of the contract"
out=$(bash -c '. "$1/lib/ui.sh"; refuse_code vault.locked' _ "$SCRIPTS"; echo "rc=$?")
check_match "status, catalogue reason, fix and code, exit 1" 'status.refused' "$out"
check_match "the catalogue reason is used" 'reason.The vault is closed' "$out"
check_match "the fix comes from the catalogue" 'fix.hs vault open' "$out"
check_match "the code line is there" 'code.vault.locked' "$out"
check_match "exit 1" 'rc=1' "$out"
out=$(bash -c '. "$1/lib/ui.sh"; refuse_code docker.off "Docker is off."' _ "$SCRIPTS")
check_match "a given reason wins" 'reason.Docker is off\.' "$out"
if grep -q '^fix' <<<"$out"; then fail "a code without a fix printed a fix line"; else pass "no fix line without a fix"; fi

echo "-- a failing command of each core area ends with a coded error"
# every change script: an action it does not know is refused with the code action.unknown (the two docker scripts take the app or host first)
for f in "$SCRIPTS"/*-change.sh; do
  n=$(basename "$f" -change.sh)
  case "$n" in docker-app) a=(plan app1 nosuchaction) ;; docker-registry) a=(plan nosuchaction ghcr.io) ;; *) a=(plan nosuchaction) ;; esac
  out=$(HS_PLAIN=1 timeout 20 bash "$f" "${a[@]}" </dev/null 2>/dev/null)
  if grep -q $'^status	refused' <<<"$out" && grep -q $'^code	[a-z][a-z0-9.-]*$' <<<"$out"; then pass "$n: refused with a code"; else fail "$n: no code line in: $out"; fi
done
# the catalogue knows every code a core area can answer with
for c in action.unknown option.unknown job.start-failed confirm.missing disk.unknown install.failed plan.changed; do
  grep -qxF "$c" <<<"$known" && pass "catalogue has $c" || fail "catalogue lacks $c"
done

finish
