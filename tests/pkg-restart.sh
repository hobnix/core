#!/usr/bin/env bash
# A package change restarts the running service it touches (hobnix/core#1129 step 4): hs pkg update, rollback, install and remove. A stubbed
# systemctl (HS_SYSTEMCTL) records calls; a stub pkg.py stands in for the repository work (the real update and rollback are tested in
# tests/pkg-repo.sh). Only active units restart, only those of the changed package or its integration users, a failed restart warns.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1 HS_STATE_DIR=$WORK/state
cur=$HS_STATE_DIR/packages/current; mkdir -p "$cur"
S=$WORK/scripts; mkdir -p "$S"; cp -r "$SCRIPTS/lib" "$S/lib"; cp "$SCRIPTS/pkg.sh" "$S/pkg.sh"
stub() { printf 'import os, sys\nif "--plan" in sys.argv:\n    print("hub\\t1.1.0\\t1.0.0")\nsys.exit(int(os.environ.get("STUB_RC", "0")))\n' > "$S/pkg.py"; }
stub
PKGSH="bash $S/pkg.sh"
mk() {   # mk <name> [toml line]...
  local n=$1; shift; mkdir -p "$cur/$n"
  printf 'name = "%s"\nversion = "1.0.0"\nkind = "extension"\ntitle = "T"\nrequires_core = ">=1"\n' "$n" > "$cur/$n/package.toml"
  [ $# -eq 0 ] || printf '%b\n' "$@" >> "$cur/$n/package.toml"
  printf '[package.%s]\nversion = "1.0.0"\nrepo = "test"\n\n' "$n" >> "$HS_STATE_DIR/packages/installed.toml"
}
SVC='[service]\nexec = "run.py"'
mk hub "$SVC"
mk idle "$SVC"
mk plain
mk prov '[integrations.media]\nsource = "x"\napi_url = "http://x"'
mk user 'permissions = ["integration:media"]' "$SVC"
mk other 'permissions = ["net"]' "$SVC"
CALLS=$WORK/calls
cat > "$WORK/ctl" <<'CTL'
#!/usr/bin/env bash
echo "$*" >> "$CALLS"
case "$1" in
  is-active) case "$3" in *"hs-ext-svc@idle."*|*"hs-ext-svc@other."*) exit 3 ;; *) exit 0 ;; esac ;;
  restart) [ -z "${CTL_FAIL:-}" ] || exit 1 ;;
esac
CTL
chmod +x "$WORK/ctl"
export CALLS HS_SYSTEMCTL=$WORK/ctl
restarts() { grep -c '^restart' "$CALLS" 2>/dev/null || true; }
: > "$CALLS"

echo "-- update"
check_out "an active service restarts after an update" "service of 'hub' restarts" $PKGSH update hub --yes
check "through systemctl restart --no-block" grep -qx 'restart --no-block hs-ext-svc@hub.service' "$CALLS"
check_eq "and nothing else restarted" 1 "$(restarts)"
: > "$CALLS"
$PKGSH update idle --yes >/dev/null 2>&1
check_eq "an inactive service is left alone" 0 "$(restarts)"
$PKGSH update plain --yes >/dev/null 2>&1
check_eq "a package without a service restarts nothing" 0 "$(restarts)"
STUB_RC=1 $PKGSH update hub --yes >/dev/null 2>&1; rc=$?
check_eq "a refused update exits 1" 1 "$rc"
check_eq "and restarts nothing" 0 "$(restarts)"
out=$(CTL_FAIL=1 $PKGSH update hub --yes 2>&1); rc=$?
check_eq "a failed restart does not fail the update" 0 "$rc"
check_out "it warns and names the way out" "did not restart" echo "$out"

echo "-- rollback"
: > "$CALLS"
check_out "rollback restarts the active service" "service of 'hub' restarts" $PKGSH rollback hub --yes
check_eq "once" 1 "$(restarts)"

echo "-- install and remove of a provider"
: > "$CALLS"
check_out "installing a provider restarts the active service that uses its integration" "service of 'user' restarts" $PKGSH install prov
check_eq "only that one" 1 "$(restarts)"
: > "$CALLS"
printf 'other\n' > "$HS_STATE_DIR/capabilities-on"
$PKGSH remove prov --yes >/dev/null 2>&1
check "removing the provider restarts the user too" grep -qx 'restart --no-block hs-ext-svc@user.service' "$CALLS"
check_eq "and no other" 1 "$(restarts)"
finish
