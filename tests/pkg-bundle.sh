#!/usr/bin/env bash
# hs sys pkg bundle plan|start (scripts/pkg-bundle.sh, the Optional parts step of the first-run wizard): the order (what a package requires first), the
# refusals (network, locked storage, unknown, circle, added repository, role, nothing to do), one job unit, and the job body that stops at the first failure.
# Stand-ins for pkg.sh, parts.sh, part-change.sh, rebuild.sh and the job library; nothing real is touched.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1 HS_STATE_DIR=$WORK/state HS_MACHINE_FILE=$WORK/machine.toml HS_BUNDLE_NET=ok HS_LOCKED_MARKER=$WORK/locked
mkdir -p "$HS_STATE_DIR"; : > "$HS_MACHINE_FILE"
tab=$'\t'
LOG=$WORK/log; : > "$LOG"
CAPS=$WORK/caps.tsv
printf '%s\n' \
  "a${tab}caps${tab}1.0.0${tab}-${tab}new${tab}b${tab}feature${tab}A" \
  "b${tab}caps${tab}1.0.0${tab}-${tab}new${tab}corepart${tab}feature${tab}B" \
  "c${tab}caps${tab}1.0.0${tab}1.0.0${tab}current${tab}-${tab}feature${tab}C" \
  "x${tab}caps${tab}1.0.0${tab}-${tab}new${tab}nothere${tab}feature${tab}X" \
  "y${tab}caps${tab}1.0.0${tab}-${tab}new${tab}z${tab}feature${tab}Y" \
  "z${tab}caps${tab}1.0.0${tab}-${tab}new${tab}y${tab}feature${tab}Z" \
  "r${tab}caps${tab}1.0.0${tab}-${tab}new${tab}role${tab}feature${tab}R" \
  "e${tab}extra${tab}1.0.0${tab}-${tab}new${tab}-${tab}feature${tab}E" > "$CAPS"
PARTS=$WORK/parts.tsv
printf '%s\n' "corepart${tab}off${tab}part${tab}no${tab}yes${tab}Core" "c${tab}off${tab}part${tab}yes${tab}yes${tab}C" "role${tab}off${tab}part${tab}no${tab}no${tab}Role" > "$PARTS"
cat > "$WORK/pkg.sh" <<STUB
#!/usr/bin/env bash
case "\$1" in
  --capabilities) cat "$CAPS" ;;
  --repos) printf 'caps\turl\tsigned\tdefault\nextra\turl\tsigned\tadded\n' ;;
  install) echo "install \$2" >> "$LOG"; [ "\$2" != "\${FAIL_INSTALL:-}" ] ;;
esac
STUB
printf '#!/usr/bin/env bash\ncat "%s"\n' "$PARTS" > "$WORK/parts.sh"
printf '#!/usr/bin/env bash\necho "enable $3" >> "%s"\nprintf "status\tdone\n"\n' "$LOG" > "$WORK/part-change.sh"
printf '#!/usr/bin/env bash\necho rebuild >> "%s"\n' "$LOG" > "$WORK/rebuild.sh"
mkdir -p "$WORK/jl"
printf 'hs_job() { shift 2; "${@:2}" >/dev/null 2>&1; echo hs-job-test; }\n' > "$WORK/jl/job.sh"
export HS_PKG=$WORK/pkg.sh HS_PARTS=$WORK/parts.sh HS_PART_CHANGE=$WORK/part-change.sh HS_REBUILD=$WORK/rebuild.sh HS_JOB_LIB=$WORK/jl/job.sh
C="bash $SCRIPTS/pkg-bundle.sh"
run() { rc=0; out=$($C "$@" 2>&1 </dev/null) || rc=$?; }
has() { grep -q -- "$1" <<<"$out"; }

echo "-- registry"
for r in "sys pkg capabilities${tab}pkg.sh" "sys pkg bundle plan <names>${tab}pkg-bundle.sh" "sys pkg bundle start <names>${tab}pkg-bundle.sh"; do
  check "row: $r" grep -qF "sys${tab}$r" "$SCRIPTS/lib/registry.tsv"
done
check "READS has pkg/capabilities" grep -qF '("pkg", "capabilities")' "$SCRIPTS/web-serve.py"
check "CHANGES has pkg/bundle" grep -qF '"pkg/bundle":' "$SCRIPTS/web-serve.py"

echo "-- plan"
run plan a
if [ "$rc" = 0 ] && has "^status${tab}ok" && has "^step${tab}install b 1.0.0 from the signed release of caps" && has "^note${tab}also install b: a requires it" \
   && has "^step${tab}switch corepart on" && has "^step${tab}rebuild the server" && has "^long${tab}yes"; then pass "plan a: install, switch on, rebuild, long"; else fail "plan a: $out"; fi
check_eq "install order: b then a, then corepart, b, a switched on" "install b|install a|switch corepart on|switch b on|switch a on" "$(grep -E "^step${tab}(install|switch)" <<<"$out" | sed -E "s/^step${tab}//; s/ 1.0.0 from.*//; s/ \(machine.*//" | paste -sd'|')"
run plan c
if [ "$rc" = 0 ] && has "switch c on" && ! has "install c"; then pass "plan c: installed, only switch on"; else fail "plan c: $out"; fi
run plan x;       if [ "$rc" = 1 ] && has "nothere"; then pass "plan x: refused (nothing offers nothere)"; else fail "plan x: $out"; fi
run plan y;       if [ "$rc" = 1 ] && has "in a circle"; then pass "plan y: circle refused"; else fail "plan y: $out"; fi
run plan e;       if [ "$rc" = 1 ] && has "repository you added"; then pass "plan e: added repository refused"; else fail "plan e: $out"; fi
run plan r;       if [ "$rc" = 1 ] && has "follows the role"; then pass "plan r: role refused"; else fail "plan r: $out"; fi
coded() {   # coded <what> <code> <output>: the refusal carries the code and the catalogue knows it
  check_match "$1 is refused with $2" "code${tab}$2" "$3"
  check "$2 is in the catalogue" bash -c "python3 '$SCRIPTS/errors-doc-gen.py' codes | grep -qxF '$2'"
}
run plan y;       coded "a circle" pkg.require-circle "$out"
run plan nosuch;  coded "an unknown package" pkg.unknown "$out"
run plan nosuch;  if [ "$rc" = 1 ] && has "no capability package nosuch"; then pass "plan nosuch: refused"; else fail "plan nosuch: $out"; fi
run plan 'A,b';   if [ "$rc" = 1 ] && has "one comma list"; then pass "capital letter refused"; else fail "A,b: $out"; fi
run plan 'a;b';   if [ "$rc" = 1 ] && has "one comma list"; then pass "semicolon refused"; else fail "a;b: $out"; fi
many=$(printf 'p%d,' $(seq 1 17)); many=${many%,}
run plan "$many"; if [ "$rc" = 1 ] && has "one comma list"; then pass "17 names refused"; else fail "17 names: $out"; fi
run plan a b;     if [ "$rc" = 1 ] && has "extra arguments"; then pass "extra argument refused"; else fail "extra: $out"; fi
HS_BUNDLE_NET=fail run plan a
if [ "$rc" = 1 ] && has "needs the network"; then pass "no network: refused"; else fail "net: $out"; fi
: > "$WORK/locked"; run plan a
if [ "$rc" = 1 ] && has "storage is locked"; then pass "locked storage: refused"; else fail "locked: $out"; fi
rm -f "$WORK/locked"
printf '%s\n' "corepart${tab}on${tab}part${tab}no${tab}yes${tab}Core" "c${tab}on${tab}part${tab}yes${tab}yes${tab}C" > "$PARTS"
run plan c;       if [ "$rc" = 1 ] && has "installed and on already"; then pass "everything done: refused"; else fail "done: $out"; fi
printf '%s\n' "corepart${tab}off${tab}part${tab}no${tab}yes${tab}Core" "c${tab}off${tab}part${tab}yes${tab}yes${tab}C" "role${tab}off${tab}part${tab}no${tab}no${tab}Role" > "$PARTS"

echo "-- start and the job"
: > "$LOG"
run start a
if [ "$rc" = 0 ] && has "^status${tab}started" && has "^unit${tab}hs-job-test"; then pass "start a: one unit"; else fail "start a: $out"; fi
check_eq "job order" "install b|install a|enable corepart|enable b|enable a|rebuild" "$(paste -sd'|' "$LOG")"
: > "$LOG"
rc=0; FAIL_INSTALL=b bash "$SCRIPTS/pkg-bundle.sh" run b,a corepart,b,a >/dev/null 2>&1 </dev/null || rc=$?
check_eq "a failed install stops the job (no enable, no rebuild)" "install b" "$(paste -sd'|' "$LOG")"
check "and the job exits non-zero" test "$rc" != 0
rc=0; bash "$SCRIPTS/pkg-bundle.sh" run 'a;b' - >/dev/null 2>&1 </dev/null || rc=$?
check "run refuses a bad list" test "$rc" != 0
finish
