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

echo "-- Python and Rust emit only listed codes"
# the Python and Rust programs name a code as a string ("binary.hash", "ext.state-move-failed: text", "code.rate"); a name typed differently from the
# tsv would pass the shell check above. Only the area prefixes that these programs use are scanned (a literal like "pkg.toml" is not a code).
# ext.service-failed is an event kind, not an error code
ROOT=$(dirname "$SCRIPTS")
EMIT_PREFIX='binary|ext|integration|code|pkg|run'
srcfiles() { { find "$SCRIPTS" -name '*.py' -o -name '*.sh'; find "$ROOT/rust" -name '*.rs' -not -path '*/target/*' 2>/dev/null; } | grep -v "^$SCRIPTS/dev/" | sort; }
mapfile -t SRC < <(srcfiles)
badpy=
while IFS= read -r c; do
  [ -n "$c" ] || continue
  grep -qxF "$c" <<<"$known" || badpy="$badpy $c"
done < <(grep -hoE "[\"'](${EMIT_PREFIX})\.[a-z][a-z0-9-]*[\"':]" "${SRC[@]}" | tr -d "\"':" | grep -vxE 'pkg\.(toml|py|json|sh)|code\.json|run\.sh|ext\.service-failed' | sort -u)
if [ -z "$badpy" ]; then pass "all Python and Rust codes are listed"; else fail "codes in Python or Rust, not in scripts/lib/error-codes.tsv:$badpy"; fi

echo "-- a code in a variable cannot be checked"
# Baseline, may only shrink: scripts/pkg.sh relays the code that pkg_repo.py chose (HS_PKG_REFUSAL); the Python scan above covers those codes.
VARCODE_OK=" scripts/pkg.sh "
varcode=
while IFS= read -r f; do
  case "$VARCODE_OK" in *" ${f#"$ROOT"/} "*) continue ;; esac
  varcode="$varcode ${f#"$ROOT"/}"
done < <(grep -rlE 'refuse_code "?\$' "$SCRIPTS" --include='*.sh')
if [ -z "$varcode" ]; then pass "every refuse_code names its code literally"; else fail "refuse_code with a variable as code (write the code as a literal word):$varcode"; fi

echo "-- every script code of the catalogue is emitted somewhere"
# Allowed without an emitter: the generic fallback of refuse (plain text, no code of its own). Add nothing here without a reason; the list may only shrink.
ALLOW_UNEMITTED=" refused "
unused=
while IFS= read -r c; do
  case "$ALLOW_UNEMITTED" in *" $c "*) continue ;; esac
  grep -qF -- "$c" "${SRC[@]}" || unused="$unused $c"
done < <(awk -F'\t' '!/^#/ && $2=="script" {print $1}' "$CAT")
if [ -z "$unused" ]; then pass "every catalogue code is used"; else fail "in scripts/lib/error-codes.tsv but emitted by no script or program (name differs?):$unused"; fi

echo "-- every code has a German text"
DE=$SCRIPTS/lib/i18n/errors.de.tsv
de_rows=$(grep -v '^#' "$DE")
bad=$(awk -F'\t' 'NF != 2 || $2 == ""' <<<"$de_rows")
check_eq "every German line is a code, one tab and a text" "" "$bad"
check_eq "no code has two German lines" "" "$(cut -f1 <<<"$de_rows" | sort | uniq -d)"
check_eq "codes without a German text (add a line to scripts/lib/i18n/errors.de.tsv)" "" "$(comm -23 <(sort <<<"$known") <(cut -f1 <<<"$de_rows" | sort))"
check_eq "German lines for codes the catalogue does not have" "" "$(comm -13 <(sort <<<"$known") <(cut -f1 <<<"$de_rows" | sort))"
# a <placeholder> of the English text stays as it is in the German one
ph=$(awk -F'\t' '/^#/ { next } NR == FNR { de[$1] = $2; next } { s = $4; while (match(s, /<[a-z]+>/)) { p = substr(s, RSTART, RLENGTH); if (!index(de[$1], p)) print $1 " " p; s = substr(s, RSTART + RLENGTH) } }' "$DE" "$CAT")
check_eq "the placeholders are kept" "" "$ph"

echo "-- report: plain refusals without a code (not a failure)"
total=0
while IFS=$'\t' read -r n f; do
  total=$((total + n))
  printf '   %s\t%s\n' "$n" "$f"
done < <(cd "$ROOT" && for f in scripts/*.sh scripts/lib/*.sh; do n=$(grep -cE '(^|[^_a-z])refuse "' "$f"); [ "$n" -gt 0 ] && printf '%s\t%s\n' "$n" "$f"; done | sort -rn | head -15)
all=$(grep -rcE '(^|[^_a-z])refuse "' "$SCRIPTS" --include='*.sh' | awk -F: '{s+=$2} END {print s+0}')
printf '   plain refuse total in scripts: %s\n' "$all"

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
  [ "$n" != vault ] || continue   # hs sys secrets is the Rust binary (rust:secrets); it keeps its own plain refusals until ported
  case "$n" in docker-app) a=(plan app1 nosuchaction) ;; docker-registry) a=(plan nosuchaction ghcr.io) ;; *) a=(plan nosuchaction) ;; esac
  out=$(HS_PLAIN=1 timeout 20 bash "$f" "${a[@]}" </dev/null 2>/dev/null)
  if grep -q $'^status	refused' <<<"$out" && grep -q $'^code	[a-z][a-z0-9.-]*$' <<<"$out"; then pass "$n: refused with a code"; else fail "$n: no code line in: $out"; fi
done
# the catalogue knows every code a core area can answer with
for c in action.unknown option.unknown job.start-failed confirm.missing disk.unknown install.failed plan.changed; do
  grep -qxF "$c" <<<"$known" && pass "catalogue has $c" || fail "catalogue lacks $c"
done

finish
