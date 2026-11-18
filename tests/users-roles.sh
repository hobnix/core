#!/usr/bin/env bash
# hs group roles (scripts/users-roles.sh): the groups of the web roles are made only after a plan and the typed domain name. Fake manage-users.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_PLAIN=1 HS_LANG=en HS_USERS_BACKEND=ad
unset HS_CALLER HS_GUIDED_TTY
export WORK HS_SETTINGS_DIR=$WORK/settings HS_MACHINE_FILE=$WORK/machine.toml
mkdir -p "$HS_SETTINGS_DIR"
printf 'adDomain = { realm = "AD.HOME.LAN", workgroup = "HOME" }\n' > "$HS_MACHINE_FILE"
cat > "$WORK/mu" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$WORK/mucalls"
case "$1" in
  --groups) cat "$WORK/groups" ;;
  --group-add) echo "Create the group '$2'." ;;
esac
FAKE
chmod +x "$WORK/mu"; export HS_MANAGE_USERS=$WORK/mu
printf 'Domain Admins\tAdministrator\nStaff\tanna\n' > "$WORK/groups"
run() { rc=0; : > "$WORK/mucalls"; out=$(timeout 20 bash "$SCRIPTS/users-roles.sh" "$@" </dev/null 2>&1) || rc=$?; }
made() { grep -c -- '^--group-add' "$WORK/mucalls" || true; }

echo "-- the plan changes nothing"
run --dry-run
check_eq "dry run: exit 0" 0 "$rc"
grep -q 'hn-viewers.*will be created' <<<"$out" && grep -q 'hn-app-managers.*will be created' <<<"$out" && pass "both groups are named as missing" || fail "plan: $out"
check_eq "dry run creates nothing" 0 "$(made)"

echo "-- no terminal and no typed name: nothing is created"
run
check_eq "refused" 1 "$rc"
check_eq "nothing created" 0 "$(made)"

echo "-- a wrong name is refused, the right one goes on"
run --confirm other.lan
check_eq "wrong name: exit 1" 1 "$rc"
check_eq "wrong name creates nothing" 0 "$(made)"
run --confirm AD.HOME.LAN
check_eq "right name: exit 0" 0 "$rc"
check_eq "both groups created" 2 "$(made)"
grep -qx -- '--group-add hn-viewers' "$WORK/mucalls" && grep -qx -- '--group-add hn-app-managers' "$WORK/mucalls" && pass "the two names" || fail "calls: $(cat "$WORK/mucalls")"

echo "-- an existing group is left alone, names follow the settings"
printf 'Domain Admins\tAdministrator\nhn-viewers\tanna\n' > "$WORK/groups"
printf 'team-managers\n' > "$HS_SETTINGS_DIR/webAppManagerGroup"
run --confirm AD.HOME.LAN
check_eq "one created" 1 "$(made)"
grep -qx -- '--group-add team-managers' "$WORK/mucalls" && pass "the setting names the group" || fail "calls: $(cat "$WORK/mucalls")"
printf 'Domain Admins\tAdministrator\nhn-viewers\tanna\nteam-managers\tbob\n' > "$WORK/groups"
run
check_eq "all there: exit 0, nothing asked" 0 "$rc"
check_eq "all there: nothing created" 0 "$(made)"

echo "-- without a domain there is nothing to create"
HS_USERS_BACKEND=local run
check_eq "local: exit 0" 0 "$rc"
check_eq "local: nothing created" 0 "$(made)"
finish
