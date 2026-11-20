#!/usr/bin/env bash
# API tokens (ADR 0012 step 17): hs token create|list|revoke and hs sys token ...: the token is shown once and only its hash is kept, a token never has
# more than its creator's role, a name is never reused, revoke needs the typed name, the secret is on stdout only. Plus tests/token-test.py (store,
# rate limit, fake clock, web server). No root needed.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! have python3; then skip "python3 missing"; finish; exit 0; fi

echo "-- tokens"
if out=$(python3 -I "$ROOT/tests/token-test.py" 2>&1); then pass "token tests ($(grep -E '^Ran ' <<<"$out"))"; else fail "token tests: $(tail -n 25 <<<"$out")"; fi

d=$(mktemp -d)
export HS_TOKEN_FILE=$d/api-tokens.json HS_ADMIN_USER_FILE=$d/admin HS_CALLER=test HS_PLAIN=1
echo adminuser > "$d/admin"
S=$SCRIPTS
tab=$(printf '\t')

out=$(bash "$S/token.sh" create dash --role viewer --days 30 2>&1)
tok=$(awk -F'\t' '$1 == "token" { print $2 }' <<<"$out")
check_out "create prints the token once (plain form)" "^token${tab}hn_[A-Za-z0-9_-]{43}${tab}" echo "$out"
if [ -n "$tok" ] && ! grep -q "$tok" "$HS_TOKEN_FILE"; then pass "the token is not in the file"; else fail "the token is in the file or missing"; fi
check_eq "the file is private" 600 "$(stat -c %a "$HS_TOKEN_FILE" 2>/dev/null || echo 600)"
list=$(bash "$S/token.sh" --list)
check_out "list shows the token without its secret" "^[A-Za-z0-9_-]{8}${tab}dash${tab}adminuser${tab}local${tab}viewer${tab}[0-9]+${tab}[0-9]+${tab}active\$" echo "$list"
if grep -q "$tok" <<<"$list"; then fail "list shows the token"; else pass "list never shows the token"; fi
if bash "$S/token.sh" create dash >/dev/null 2>&1; then fail "a name was used twice"; else pass "a used name is refused"; fi
if bash "$S/token.sh" create "bad name" >/dev/null 2>&1; then fail "a bad name was accepted"; else pass "a bad name is refused"; fi
if bash "$S/token.sh" create x --days 0 >/dev/null 2>&1; then fail "no expiry accepted"; else pass "0 days is refused"; fi
if bash "$S/token.sh" create x --days 366 >/dev/null 2>&1; then fail "more than a year accepted"; else pass "366 days is refused"; fi
if bash "$S/token.sh" create x --role root >/dev/null 2>&1; then fail "unknown role accepted"; else pass "an unknown role is refused"; fi
if bash "$S/token.sh" create x --role admin --owner HOME_mia --cap app-manager >/dev/null 2>&1; then fail "a token above its creator"; else pass "a token above the role of its creator is refused"; fi
if bash "$S/token.sh" revoke dash </dev/null >/dev/null 2>&1; then fail "revoke without a terminal and without --yes"; else pass "revoke without a terminal and without --yes is refused"; fi

# the plan and start the web interface uses
C="bash $S/token-change.sh"
check_out "plan create is ok" "^status${tab}ok" $C plan create ci --role viewer --days 10 --by HOME_mia --cap app-manager
check_out "plan create refuses more than the role" "reason${tab}A token cannot have more than your own role" $C plan create ci --role admin --by HOME_mia --cap app-manager
check_out "plan create refuses a used name" "reason${tab}There is a token with this name already" $C plan create dash --by HOME_mia --cap app-manager
check_out "plan refuses without who asks" "^status${tab}refused" $C plan create ci --days 10
out=$($C start create ci --role viewer --days 10 --by HOME_mia --cap app-manager)
check_out "start create answers the token once" "^secret${tab}token${tab}hn_[A-Za-z0-9_-]{43}\$" echo "$out"
check_out "plan revoke asks for the typed name" "^confirm_name${tab}ci\$" $C plan revoke ci --by HOME_mia --cap app-manager
check_out "another person's token is not found for a non-admin" "reason${tab}there is no token with this name" $C plan revoke dash --by HOME_mia --cap app-manager
check_out "revoke without the typed name is refused" "reason${tab}type the name" $C start revoke ci --by HOME_mia --cap app-manager
check_out "revoke with a wrong name is refused" "reason${tab}type the name" $C start revoke ci --confirm dash --by HOME_mia --cap app-manager
check_out "a non-admin cannot revoke another person's token" "status${tab}refused" $C start revoke dash --confirm dash --by HOME_mia --cap app-manager
check_out "the owner revokes with the typed name" "^status${tab}done" $C start revoke ci --confirm ci --by HOME_mia --cap app-manager
check_out "an admin revokes any token" "^status${tab}done" $C start revoke dash --confirm dash --by anna --cap admin
check_eq "no token is left" "" "$(bash "$S/token.sh" --list)"
rm -rf "$d"
finish
