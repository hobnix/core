#!/usr/bin/env bash
# hs sys apps plan|start install (scripts/apps-change.sh, docs/PLAN-app-lifecycle.md Q2, step 8a): the plan comes from the verified clone and shows
# the needs and the questions, the job installs exactly the tag of the plan (a different tag is refused), the steps are read needs ask run check done,
# the record ends with a result, --from skips the steps before it. A local git repository with SSH-signed tags stands in for GitHub; stand-ins for
# recipe.sh, the orchestrator, incus, parts and the job library.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have git || { skip "needs git"; finish; exit 0; }
have ssh-keygen || { skip "needs ssh-keygen"; finish; exit 0; }
export HS_LANG=en HS_PLAIN=1 HS_STATE_DIR=$WORK/state HS_JOBS_DIR=$WORK/jobs HS_BUNDLE_NET=ok HS_LOCKED_MARKER=$WORK/locked HS_JOB_RECORD=python
mkdir -p "$HS_STATE_DIR" "$HS_JOBS_DIR"
tab=$'\t'
PKGPY="python3 -I $SCRIPTS/pkg.py"
ssh-keygen -q -t ed25519 -N '' -f "$WORK/good" -C test >/dev/null
printf 'releaser@test namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$WORK/good.pub")" > "$WORK/signers"
R=$WORK/repo; mkdir -p "$R/recipes/multi" "$R/recipes/demo" "$R/recipes/needy" "$R/recipes/docker"; cd "$R"
git init -q . && git config user.email t@t && git config user.name t && git config gpg.format ssh && git config commit.gpgsign false
printf '#!/usr/bin/env bash\n# kind: generic\n# needs: -\n# uses: -\necho demo\n' > recipes/demo/run.sh
printf '#!/usr/bin/env bash\n# kind: generic\n# needs: docker tailscale\n# uses: -\n# phases: fetch configure\necho needy\n' > recipes/needy/run.sh
cat > recipes/demo/package.toml <<'TOML'
name = "demo"
version = "1.0.0"
kind = "recipe"
title = "Demo"
description = "A demo app."
requires_core = ">=1"
audience = "generic"
needs = []
uses = []
input = "form"
script = "run.sh"
[[ask]]
key = "NAME"
label = "Name"
type = "text"
default = "x"
[app]
instances = "one"
[app.health]
check = "container"
[app.routes.web]
port = 8080
[app.uses]
ram_mb = 512
disk_gb = 2
TOML
printf '#!/usr/bin/env bash
# kind: generic
# needs: -
# uses: -
echo multi
' > recipes/multi/run.sh
printf 'name = "multi"
version = "1.0.0"
kind = "recipe"
title = "Multi"
requires_core = ">=1"
audience = "generic"
needs = []
uses = []
input = "none"
script = "run.sh"
[app]
instances = "many"
' > recipes/multi/package.toml
cat > recipes/needy/package.toml <<'TOML'
name = "needy"
version = "1.0.0"
kind = "recipe"
title = "Needy"
requires_core = ">=1"
audience = "generic"
needs = ["docker", "tailscale"]
uses = []
input = "none"
script = "run.sh"
TOML
printf '#!/usr/bin/env bash
# kind: generic
# needs: -
# uses: -
echo docker
' > recipes/docker/run.sh
printf 'name = "docker"
version = "1.0.0"
kind = "recipe"
title = "Docker"
requires_core = ">=1"
audience = "generic"
needs = []
uses = []
input = "none"
script = "run.sh"
' > recipes/docker/package.toml
printf '[package.docker]
version = "1.0.0"
kind = "recipe"
path = "recipes/docker"
requires_core = ">=1"
[package.demo]\nversion = "1.0.0"\nkind = "recipe"\npath = "recipes/demo"\nrequires_core = ">=1"\n[package.multi]\nversion = "1.0.0"\nkind = "recipe"\npath = "recipes/multi"\nrequires_core = ">=1"\n[package.needy]\nversion = "1.0.0"\nkind = "recipe"\npath = "recipes/needy"\nrequires_core = ">=1"\n' > index.toml
mkdir -p recipes/failapp && cp "$ROOT/tests/fixtures/pkgtree/failing/failapp/"* recipes/failapp/
printf '[package.failapp]
version = "1.0.0"
kind = "recipe"
path = "recipes/failapp"
requires_core = ">=1"
' >> index.toml
git add -A && git commit -q -m one && git -c user.signingkey="$WORK/good.pub" tag -s v1.0.0 -m release
cd "$ROOT"
$PKGPY repo add test "$R" --key "$WORK/signers"
$PKGPY fetch test >/dev/null

# stand-ins: incus (docker is not there), parts (tailscale off), recipe, orchestrator, health, job library
LOG=$WORK/log; : > "$LOG"
printf '#!/usr/bin/env bash
case "${1:-} ${2:-}" in "info "*) [ -e "%s/ct-$2" ] && exit 0; [ -s "%s/have_ct" ] && [ "${2:-}" = "$(cat "%s/have_ct")" ] && exit 0; exit 1 ;; "delete -f") rm -f "%s/ct-$3" ;; *) exit 1 ;; esac
' "$WORK" "$WORK" "$WORK" "$WORK" > "$WORK/incus"
chmod +x "$WORK/incus"
printf '#!/usr/bin/env bash\nprintf "tailscale\\toff\\tpart\\tyes\\tyes\\tT\\n"\n' > "$WORK/parts.sh"
printf '#!/usr/bin/env bash\necho "recipe $*" >> "%s"\n' "$LOG" > "$WORK/recipe.sh"
cat > "$WORK/orch.sh" <<STUB
#!/usr/bin/env bash
. "$SCRIPTS/lib/job.sh"
echo "orchestrate \$* base=\${HS_STEP_BASE:-} total=\${HS_STEP_TOTAL:-} prefix=\${HS_STEP_PREFIX:-} ask=\${RECIPE_ASK:-} name=\${RECIPE_NAME:-}" >> "$LOG"
[ -z "\${FAIL_RUN:-}" ] || exit 1
hs_job_step \$((HS_STEP_BASE + 1)) "\$HS_STEP_TOTAL" run:run
STUB
printf '#!/usr/bin/env bash\nprintf "demo\\t%%s\\n" "${HEALTH:-healthy}"\n' > "$WORK/alist.sh"
mkdir -p "$WORK/jl"
cat > "$WORK/jl/job.sh" <<STUB
hs_job() { echo "hs_job \$*" >> "$LOG"; echo "env: \$HS_JOB_ENV" >> "$LOG"; echo hs-job-test; }
hs_job_record() { echo "20260101-000000-demo-abcd"; }
STUB
printf '#!/usr/bin/env bash\necho "enable $3" >> "%s"\nprintf "status\\tdone\\n"\n' "$LOG" > "$WORK/part-change.sh"
printf '#!/usr/bin/env bash\necho rebuild >> "%s"\n' "$LOG" > "$WORK/rebuild.sh"
export HS_INCUS=$WORK/incus HS_PARTS=$WORK/parts.sh HS_RECIPE=$WORK/recipe.sh HS_ORCHESTRATE=$WORK/orch.sh HS_APPS_LIST=$WORK/alist.sh HS_JOB_LIB=$WORK/jl/job.sh
export HS_PART_CHANGE=$WORK/part-change.sh HS_REBUILD=$WORK/rebuild.sh HS_CHECK_WAIT=0
C="bash $SCRIPTS/apps-change.sh"
run() { rc=0; out=$($C "$@" 2>&1 </dev/null) || rc=$?; }
has() { grep -q -- "$1" <<<"$out"; }

echo "-- registry and routes"
for r in "sys apps plan <action>${tab}apps-change.sh" "sys apps start <action>${tab}apps-change.sh"; do
  check "row: $r" grep -qF "sys${tab}$r" "$SCRIPTS/lib/registry.tsv"
done
check "CHANGES has apps" grep -qF '"apps": [{"fixed": [r"^install$"' "$SCRIPTS/web-serve.py"
check "openapi.json has the two rows" grep -q '"/apps/start/{action}"' "$ROOT/docs/api/openapi.json"

echo "-- the plan reads the verified clone and installs nothing"
run plan install demo
if [ "$rc" = 0 ] && has "^status${tab}ok" && has "^tag${tab}v1.0.0" && has "^version${tab}1.0.0" && has "^repo${tab}test" && has "^long${tab}yes"; then pass "plan demo: tag, version, repo, long"; else fail "plan demo: $out"; fi
has "^ask${tab}NAME${tab}Name${tab}text" && pass "the question is in the plan" || fail "ask: $out"
has "^creates${tab}an instance named demo (RAM 512 MB, disk 2 GB)" && pass "what it creates" || fail "creates: $out"
check_eq "the job steps" "read|ask|run|check|done" "$(awk -F'\t' '$1=="jobstep"{print $2}' <<<"$out" | paste -sd'|')"
has "^command${tab}hs sys apps start install demo --tag v1.0.0" && pass "the command carries the tag" || fail "command: $out"
has "^confirm_name${tab}demo" && pass "a package of an added repository asks for the typed name" || fail "confirm_name: $out"
run start install demo --tag v1.0.0; if [ "$rc" = 1 ] && has "type the name (demo)"; then pass "start without the typed name is refused"; else fail "start red: $out"; fi
check "plan installs nothing" test ! -e "$HS_STATE_DIR/packages/current/demo"
run plan install demo --name demo-second
if [ "$rc" = 1 ] && has "runs once on a server"; then pass "a second instance of a one package is refused"; else fail "one: $out"; fi
run plan install demo --name demo;       check_eq "its own name is allowed (a repair)" 0 "$rc"
run plan install multi --name multi-kids
if [ "$rc" = 0 ] && has "an instance named multi-kids"; then pass "a many package gets <recipe>-<word>"; else fail "many: $out"; fi
run plan install multi --name other;     if [ "$rc" = 1 ] && has "is named multi-<word>"; then pass "a name off the pattern is refused"; else fail "pattern: $out"; fi
run plan install multi --name multi-Bad; [ "$rc" = 1 ] && pass "invalid characters are refused" || fail "chars: $out"
echo multi-kids > "$WORK/have_ct"; run plan install multi --name multi-kids; rm -f "$WORK/have_ct"
if [ "$rc" = 1 ] && has "taken already"; then pass "a duplicate instance name is refused"; else fail "dup: $out"; fi
mkdir -p "$WORK/svc"; : > "$WORK/svc/multi-tv.toml"
HS_SERVICES_DIR=$WORK/svc run plan install multi --name multi-tv
if [ "$rc" = 1 ] && has "taken already"; then pass "a name used by a service is refused"; else fail "svc: $out"; fi
run plan install needy
if [ "$rc" = 0 ] && has "^need${tab}docker${tab}missing" && has "^need${tab}tailscale${tab}missing.*${tab}yes\$" && has "^warn${tab}This rebuilds the server"; then pass "plan needy: docker and tailscale are plan lines, the rebuild is said"; else fail "plan needy: $out"; fi
check_eq "needy steps include needs" "read|needs|run|done" "$(awk -F'\t' '$1=="jobstep"{print $2}' <<<"$out" | paste -sd'|')"
HS_BUNDLE_NET=fail run plan install needy;  if [ "$rc" = 1 ] && has "needs the network"; then pass "a rebuild need without network: refused"; else fail "net: $out"; fi
: > "$WORK/locked"; run plan install needy; if [ "$rc" = 1 ] && has "storage is locked"; then pass "locked storage: refused"; else fail "locked: $out"; fi
rm -f "$WORK/locked"
run plan install demo --tag v0.9.0
if [ "$rc" = 1 ] && has "release moved"; then pass "a different tag is refused in the plan"; else fail "tag: $out"; fi
run plan install demo --set BOGUS=1;      if [ "$rc" = 1 ] && has "does not ask 'BOGUS'"; then pass "an answer to no question is refused"; else fail "bogus: $out"; fi
run plan install demo --set 'NAME=a
b';                                        check_eq "a control character is refused" 1 "$rc"
run plan install nosuch;                   check_eq "an unknown package is refused" 1 "$rc"
run plan install 'Bad Name';               check_eq "a bad name is refused" 1 "$rc"
run plan remove demo;                      check_eq "removing an app that is not there is refused" 1 "$rc"
run plan install demo --bogus;             check_eq "an unknown option is refused" 1 "$rc"
run plan install demo --from needs;        if [ "$rc" = 1 ] && has "not a step of demo"; then pass "--from a step the package does not have is refused"; else fail "from needs: $out"; fi
run start install demo --confirm demo;     if [ "$rc" = 1 ] && has "start needs --tag"; then pass "start without --tag is refused"; else fail "no tag: $out"; fi
run plan install demo --from nowhere;      check_eq "a bad --from is refused" 1 "$rc"

echo "-- start"
: > "$LOG"
run start install demo --tag v1.0.0 --set NAME=y --ask --confirm demo
if [ "$rc" = 0 ] && has "^status${tab}started" && has "^unit${tab}hs-job-test" && has "^job${tab}20260101-000000-demo-abcd"; then pass "start: status started, unit and job"; else fail "start: $out"; fi
grep -q "RECIPE_NAME=y" "$LOG" && grep -q "RECIPE_ASK=1" "$LOG" && pass "the answer and --ask reach the job as RECIPE_NAME and RECIPE_ASK" || fail "env: $(cat "$LOG")"
grep -q "run install demo --repo test --tag v1.0.0" "$LOG" && pass "the job runs the tag of the plan" || fail "job args: $(cat "$LOG")"
run start install demo --tag v0.9.0 --confirm demo;      if [ "$rc" = 1 ] && has "release moved"; then pass "start refuses a different tag"; else fail "start tag: $out"; fi
check "start installed nothing itself" test ! -e "$HS_STATE_DIR/packages/current/demo"

echo "-- the job: read ask run check done, then a result"
newjob() { python3 "$SCRIPTS/job-record.py" new --slug app-install-demo --desc "hs apps install demo" --unit u --source cli --initiator t; }
export HS_JOB_ID; HS_JOB_ID=$(newjob)
python3 "$SCRIPTS/job-record.py" run "$HS_JOB_ID"
: > "$LOG"
rc=0; out=$(bash "$SCRIPTS/apps-change.sh" run install demo --repo test --tag v1.0.0 2>&1 </dev/null) || rc=$?
check_eq "a fixture install ends with exit 0" 0 "$rc"
check "the signed copy is in current/" test -f "$HS_STATE_DIR/packages/current/demo/package.toml"
rec=$(python3 "$SCRIPTS/job-record.py" get "$HS_JOB_ID")
check_eq "the last step is done, 5 of 5" "5/5/done" "$(python3 -c 'import json,sys;s=json.loads(sys.argv[1])["step"];print("%s/%s/%s"%(s["n"],s["of"],s["text"]))' "$rec")"
check_eq "the result names the package and the version" "demo 1.0.0 v1.0.0" "$(python3 -c 'import json,sys;r=json.loads(sys.argv[1])["result"];print(r["package"],r["version"],r["tag"])' "$rec")"
check_eq "the result says where to open it" "demo:8080" "$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["result"]["open"])' "$rec")"
grep -q "orchestrate demo base=2 total=5 prefix=run:" "$LOG" && pass "the recipe runs as step 3 of 5 (run:)" || fail "orchestrate: $(cat "$LOG")"
has "demo is healthy" && pass "the health check is a step" || fail "check: $out"

echo "-- a refused tag, a failing recipe, an unhealthy app, --from"
rm -rf "$HS_STATE_DIR/packages/current/demo" "$HS_STATE_DIR/packages/installed.toml"
HS_JOB_ID=$(newjob); python3 "$SCRIPTS/job-record.py" run "$HS_JOB_ID"
rc=0; out=$(bash "$SCRIPTS/apps-change.sh" run install demo --repo test --tag v0.9.0 2>&1 </dev/null) || rc=$?
if [ "$rc" != 0 ] && [ ! -e "$HS_STATE_DIR/packages/current/demo" ]; then pass "the job refuses a tag other than the plan's and installs nothing"; else fail "tag job: rc=$rc $out"; fi
rc=0; out=$(FAIL_RUN=1 bash "$SCRIPTS/apps-change.sh" run install demo --repo test --tag v1.0.0 2>&1 </dev/null) || rc=$?
rec=$(python3 "$SCRIPTS/job-record.py" get "$HS_JOB_ID")
check "a failing recipe fails the job" test "$rc" != 0
check_eq "and no success result is written (a failure result names the step)" "failed/run" "$(python3 -c 'import json,sys;r=json.loads(sys.argv[1]).get("result") or {};print("%s/%s"%(r.get("status"),r.get("failed_step")))' "$rec")"
rc=0; out=$(HEALTH=unhealthy bash "$SCRIPTS/apps-change.sh" run install demo --repo test --tag v1.0.0 2>&1 </dev/null) || rc=$?
if [ "$rc" != 0 ] && grep -q "does not answer" <<<"$out"; then pass "an unhealthy app fails the check step"; else fail "unhealthy: rc=$rc $out"; fi
: > "$LOG"
rc=0; out=$(bash "$SCRIPTS/apps-change.sh" run install demo --repo test --tag v1.0.0 --from check 2>&1 </dev/null) || rc=$?
check_eq "--from check: ok" 0 "$rc"
if ! grep -q orchestrate "$LOG" && grep -q "Step run: done before" <<<"$out"; then pass "--from check does not run the recipe again"; else fail "from: $out $(cat "$LOG")"; fi

echo "-- needs in the job (D5: stop at the first failure, same code as the bundle)"
rm -rf "$HS_STATE_DIR/packages/current/needy"
HS_JOB_ID=$(newjob); python3 "$SCRIPTS/job-record.py" run "$HS_JOB_ID"
: > "$LOG"
rc=0; out=$(bash "$SCRIPTS/apps-change.sh" run install needy --repo test --tag v1.0.0 2>&1 </dev/null) || rc=$?
check_eq "needy installs" 0 "$rc"
check_eq "order: docker (fetched, then its recipe), tailscale on, rebuild, then the recipe in two phases" "recipe docker|enable tailscale|rebuild|orchestrate needy base=2 total=5 prefix=run: ask= name=" "$(sed -E 's/ *$//' "$LOG" | paste -sd'|')"
check "docker was fetched as a need" test -f "$HS_STATE_DIR/packages/current/docker/package.toml"
rec=$(python3 "$SCRIPTS/job-record.py" get "$HS_JOB_ID")
check_eq "the last step counts the phases" "5/5/done" "$(python3 -c 'import json,sys;s=json.loads(sys.argv[1])["step"];print("%s/%s/%s"%(s["n"],s["of"],s["text"]))' "$rec")"
: > "$LOG"; rm -rf "$HS_STATE_DIR/packages/current/needy"
printf '#!/usr/bin/env bash
echo enable >> "%s"
printf "status\trefused\nreason\tno\n"
' "$LOG" > "$WORK/part-change.sh"
rc=0; out=$(bash "$SCRIPTS/apps-change.sh" run install needy --repo test --tag v1.0.0 2>&1 </dev/null) || rc=$?
if [ "$rc" != 0 ] && ! grep -q "rebuild\|orchestrate" "$LOG"; then pass "a need that fails stops the job before the rebuild and the recipe"; else fail "stop: rc=$rc $(cat "$LOG")"; fi

echo "-- the bundle is a caller of the same code, and pkg install --tag"
check "pkg-bundle.sh uses lib/install-steps.sh" grep -q "install-steps.sh" "$SCRIPTS/pkg-bundle.sh"
check "apps-change.sh uses lib/install-steps.sh" grep -q "install-steps.sh" "$SCRIPTS/apps-change.sh"
rm -rf "$HS_STATE_DIR/packages/current/demo"
check "pkg.py install --tag with another tag is refused" bash -c "! $PKGPY install demo --repo test --tag v9.9.9 >/dev/null 2>&1"
check "and installs nothing" test ! -e "$HS_STATE_DIR/packages/current/demo"
check "pkg.py install --tag with the verified tag works" $PKGPY install demo --repo test --tag v1.0.0

echo "-- a failed install names its step, retries from it and removes what it made (step 9, #466)"
export HS_JOB_RATE=0 HS_SCRIPTS=$SCRIPTS HS_SERVICES_DIR=$WORK/services.d
mkdir -p "$HS_SERVICES_DIR"
# an orchestrator stand-in that runs the fixture recipe phase by phase (as recipe-orchestrate.sh does), honouring --from-phase
cat > "$WORK/orch2.sh" <<STUB
#!/usr/bin/env bash
. "$SCRIPTS/lib/job.sh"
name=\$1; shift; ct=\$name; fp=""
while [ \$# -gt 0 ]; do case "\$1" in --name) ct=\$2; shift 2 ;; --from-phase) fp=\$2; shift 2 ;; *) shift ;; esac; done
n=0
for ph in fetch configure; do
  n=\$((n + 1))
  if [ -n "\$fp" ] && [ "\$ph" != "\$fp" ]; then continue; fi
  fp=""
  echo "phase \$ph" >> "$LOG"
  hs_job_step \$((HS_STEP_BASE + n)) "\$HS_STEP_TOTAL" "\${HS_STEP_PREFIX}\$ph"
  [ "\$ph" != fetch ] || touch "$WORK/ct-\$ct"
  [ "\$ph" != configure ] || touch "$HS_SERVICES_DIR/\$ct.toml"
  out=\$(CREATED_APP=\$ct RECIPE_PHASE=\$ph bash "$HS_STATE_DIR/packages/current/\$name/run.sh" 2>&1) || { echo "\$out" >&2; exit 1; }
done
STUB
printf '#!/usr/bin/env bash\nrm -f "%s/$2.toml"\n' "$HS_SERVICES_DIR" > "$WORK/services.sh"
printf '#!/usr/bin/env bash\ncase "$1" in reserved) [ -e "%s/resv" ] && echo 10.0.0.9 ;; clear-ip) rm -f "%s/resv" ;; esac\n' "$WORK" "$WORK" > "$WORK/unifi.sh"
chmod +x "$WORK/orch2.sh" "$WORK/services.sh" "$WORK/unifi.sh"
export HS_ORCHESTRATE=$WORK/orch2.sh HS_SERVICES=$WORK/services.sh HS_UNIFI=$WORK/unifi.sh
touch "$WORK/resv" "$WORK/ct-other"; : > "$HS_SERVICES_DIR/other.toml"
rm -rf "$HS_STATE_DIR/packages/current/failapp"
FJ=$(newjob); python3 "$SCRIPTS/job-record.py" run "$FJ"; export HS_JOB_ID=$FJ
rc=0; out=$(RECIPE_FAIL_AT=configure bash "$SCRIPTS/apps-change.sh" run install failapp --repo test --tag v1.0.0 2>&1 </dev/null) || rc=$?
python3 "$SCRIPTS/job-record.py" finish "$FJ" "$rc"
check "the failing phase fails the job" test "$rc" != 0
rec=$(python3 "$SCRIPTS/job-record.py" get "$FJ")
rf() { python3 -c 'import json,sys;print(json.loads(sys.argv[1])["result"][sys.argv[2]])' "$rec" "$1"; }
check_eq "the record names the failed step" "run:configure" "$(rf failed_step)"
check_eq "and the instance and the tag" "failapp v1.0.0" "$(rf instance) $(rf tag)"
case "$(rf reason)" in ?*) pass "and a reason";; *) fail "no reason";; esac
check_eq "the ledger lists what the run made" "container${tab}failapp${tab}container|reservation${tab}10.0.0.9${tab}aa:bb:cc:dd:ee:09|service${tab}failapp${tab}-" "$(CREATED_APP=failapp bash -c ". $SCRIPTS/lib/created.sh; created_list" | paste -sd'|')"

echo "-- retry: the plan, then the job starts at the failed step"
rc=0; out=$($C plan retry "$FJ" 2>&1 </dev/null) || rc=$?
if [ "$rc" = 0 ] && has "^failed_step${tab}run:configure" && has "^retry_from${tab}run:configure" && has "^tag${tab}v1.0.0" && has "^command${tab}hs sys apps start retry $FJ"; then pass "retry plan: step, tag, command"; else fail "retry plan: $out"; fi
: > "$LOG"; run start retry "$FJ" --confirm failapp
if [ "$rc" = 0 ] && has "^status${tab}started" && grep -q "run install failapp --repo test --tag v1.0.0 --from run:configure" "$LOG"; then pass "retry start: the new job runs from run:configure of the same tag"; else fail "retry start: $out $(cat "$LOG")"; fi
run start retry "$FJ" --bogus;  check_eq "an unknown option is refused" 1 "$rc"
run plan retry 20260101-000000-nosuch-ffff; check_eq "an unknown job is refused" 1 "$rc"
: > "$LOG"; RJ=$(newjob); python3 "$SCRIPTS/job-record.py" run "$RJ"; HS_JOB_ID=$RJ
rc=0; out=$(bash "$SCRIPTS/apps-change.sh" run install failapp --repo test --tag v1.0.0 --from run:configure 2>&1 </dev/null) || rc=$?
check_eq "the retry succeeds" 0 "$rc"
check_eq "only the failed phase runs again" "phase configure" "$(grep '^phase' "$LOG" | paste -sd'|')"

echo "-- cleanup: a plan, the typed name, the data question, nothing the ledger does not list"
: > "$WORK/shared-data-marker"; mkdir -p "$WORK/shared"
CREATED_APP=failapp bash -c ". $SCRIPTS/lib/created.sh; created share media $WORK/shared"
rc=0; out=$($C plan cleanup "$FJ" 2>&1 </dev/null) || rc=$?
if [ "$rc" = 0 ] && has "^confirm_name${tab}failapp" && has "^data${tab}yes" && has "^question${tab}delete_data.*${tab}keep"; then pass "cleanup plan: typed name, the data question (default keep)"; else fail "cleanup plan: $out"; fi
check_eq "the plan lists the ledger in reverse, each line checked" "share|service|reservation|container" "$(awk -F'\t' '$1=="item"{print $2}' <<<"$out" | paste -sd'|')"
has "^item${tab}container${tab}failapp${tab}there${tab}remove" && pass "a line that is still there is a remove" || fail "$out"
run start cleanup "$FJ";                    if [ "$rc" = 1 ] && has "type the name (failapp)"; then pass "cleanup without the typed name is refused"; else fail "no name: $out"; fi
run start cleanup "$FJ" --confirm wrong;    check_eq "a wrong name is refused" 1 "$rc"
run start cleanup "$FJ" --confirm failapp
if [ "$rc" = 0 ] && has "^status${tab}started" && grep -q "apps-recover.sh run cleanup $FJ" "$LOG"; then pass "cleanup start: a background job"; else fail "cleanup start: $out"; fi
rc=0; out=$(bash "$SCRIPTS/apps-recover.sh" run cleanup "$FJ" 2>&1 </dev/null) || rc=$?
check_eq "the clean-up job ends well" 0 "$rc"
if [ ! -e "$WORK/ct-failapp" ]; then pass "the instance is gone"; else fail "the instance is gone: $out"; fi
check "the service description is gone" test ! -e "$HS_SERVICES_DIR/failapp.toml"
check "the reservation is given back" test ! -e "$WORK/resv"
check "the data of the created share is kept by default" test -d "$WORK/shared"
check "the ledger is empty" test ! -e "$(CREATED_APP=failapp bash -c ". $SCRIPTS/lib/created.sh; created_file")"
check "what the ledger did not list is untouched" test -e "$WORK/ct-other" -a -e "$HS_SERVICES_DIR/other.toml"
run plan cleanup "$FJ";                     if [ "$rc" = 1 ] && has "no record of what the run created"; then pass "an app without a ledger is never removed by guesswork"; else fail "no ledger: $out"; fi
python3 "$SCRIPTS/job-record.py" finish "$RJ" 0
CREATED_APP=failapp bash -c ". $SCRIPTS/lib/created.sh; created container failapp container"
run plan cleanup "$FJ";                     if [ "$rc" = 1 ] && has "another run"; then pass "a later good install is not cleaned away"; else fail "later: $out"; fi
run plan cleanup "$RJ";                     if [ "$rc" = 1 ] && has "did not fail"; then pass "a job that did not fail has nothing to clean"; else fail "ok job: $out"; fi
check "recipe-orchestrate.sh knows --from-phase" grep -q -- '--from-phase' "$SCRIPTS/recipe-orchestrate.sh"

echo "-- remove: keep the data (default) or delete it, a typed name, an older app without a ledger (step 11, #466)"
export HS_SHARE_DELETE=$WORK/share-delete.sh
printf '#!/usr/bin/env bash\nmv "%s/keepshare" "%s/keepshare.deleted"\n' "$WORK" "$WORK" > "$HS_SHARE_DELETE"; chmod +x "$HS_SHARE_DELETE"
mkdir -p "$HS_STATE_DIR/packages/current/keepapp"
cat > "$HS_STATE_DIR/packages/current/keepapp/package.toml" <<'TOML'
name = "keepapp"
version = "1.0.0"
kind = "recipe"
[app.remove]
keeps = ["the photo share"]
data = ["/var/lib/keepapp"]
TOML
mkapp() {   # an installed app with a ledger: instance, service description, UniFi address, a share with a file in it
  touch "$WORK/ct-keepapp" "$WORK/resv"; : > "$HS_SERVICES_DIR/keepapp.toml"; mkdir -p "$WORK/keepshare"; echo photo > "$WORK/keepshare/photo.jpg"
  CREATED_APP=keepapp bash -c ". $SCRIPTS/lib/created.sh; created container keepapp container; created reservation 10.0.0.9 aa:bb:cc:dd:ee:09; created service keepapp; created share photos $WORK/keepshare"
}
mkapp
run plan remove keepapp
if [ "$rc" = 0 ] && has "^source${tab}ledger" && has "^keeps${tab}the photo share" && has "^data${tab}yes" && has "^question${tab}delete_data.*${tab}keep" && has "^confirm_name${tab}keepapp"; then pass "remove plan: the ledger, what stays, the data question (default keep), the typed name"; else fail "remove plan: $out"; fi
if has "^item${tab}share${tab}photos${tab}there${tab}keep" && has "^item${tab}container${tab}keepapp${tab}there${tab}remove" && ! has "^confirm_data"; then pass "keep: the share is kept, the instance goes, no second name"; else fail "keep items: $out"; fi
run start remove keepapp;                         if [ "$rc" = 1 ] && has "type the name (keepapp)"; then pass "remove without the typed name is refused"; else fail "no name: $out"; fi
run start remove keepapp --confirm demo;          check_eq "the package name instead of the instance is refused" 1 "$rc"
: > "$LOG"; run start remove keepapp --confirm keepapp
if [ "$rc" = 0 ] && has "^status${tab}started" && grep -q "apps-remove.sh run remove keepapp" "$LOG"; then pass "remove start: a background job"; else fail "remove start: $out $(cat "$LOG")"; fi
rc=0; out=$(bash "$SCRIPTS/apps-remove.sh" run remove keepapp 2>&1 </dev/null) || rc=$?
check_eq "the remove job ends well" 0 "$rc"
check "the instance, the description and the address are gone" test ! -e "$WORK/ct-keepapp" -a ! -e "$HS_SERVICES_DIR/keepapp.toml" -a ! -e "$WORK/resv"
check "keep: the share and the data in it are still there" test -f "$WORK/keepshare/photo.jpg"
check "the ledger is empty, so a later install finds the share as one that was there before" test ! -e "$(CREATED_APP=keepapp bash -c ". $SCRIPTS/lib/created.sh; created_file")"
check "what was not on the list is untouched" test -e "$WORK/ct-other" -a -e "$HS_SERVICES_DIR/other.toml"

mkapp
run plan remove keepapp --delete-data
if [ "$rc" = 0 ] && has "^confirm_name${tab}keepapp" && has "^confirm_data${tab}keepapp" && has "^item${tab}share${tab}photos${tab}there${tab}remove"; then pass "delete plan: the share goes, the name is asked a second time"; else fail "delete plan: $out"; fi
run start remove keepapp --delete-data --confirm keepapp
if [ "$rc" = 1 ] && has "second time"; then pass "deleting the data needs the typed name again"; else fail "delete without name: $out"; fi
run start remove keepapp --delete-data --confirm keepapp --confirm-data wrong; check_eq "a wrong second name is refused" 1 "$rc"
: > "$LOG"; run start remove keepapp --delete-data --confirm keepapp --confirm-data keepapp
if [ "$rc" = 0 ] && grep -q "apps-remove.sh run remove keepapp --delete-data" "$LOG"; then pass "delete start: a background job"; else fail "delete start: $out"; fi
rc=0; out=$(bash "$SCRIPTS/apps-remove.sh" run remove keepapp --delete-data 2>&1 </dev/null) || rc=$?
check_eq "the delete job ends well" 0 "$rc"
check "delete: the share is taken away (its folder kept under the new name)" test ! -e "$WORK/keepshare" -a -f "$WORK/keepshare.deleted/photo.jpg"

touch "$WORK/ct-oldapp"; : > "$HS_SERVICES_DIR/oldapp.toml"; mkdir -p "$WORK/oldshare"
run plan remove oldapp
if [ "$rc" = 0 ] && has "^source${tab}discovered" && has "^item${tab}container${tab}oldapp" && has "^item${tab}service${tab}oldapp" && ! has "^item${tab}share" && ! has "^question"; then pass "an app without a ledger: a read-only discovered list, instance and description only"; else fail "discovered: $out"; fi
check "planning changed nothing" test -e "$WORK/ct-oldapp" -a -e "$HS_SERVICES_DIR/oldapp.toml"
run plan remove oldapp --delete-data;             if [ "$rc" = 1 ] && has "no data to delete"; then pass "nothing is deleted that is on no list"; else fail "discovered delete: $out"; fi
run plan remove nosuchapp;                        if [ "$rc" = 1 ] && has "no app called"; then pass "an unknown instance is refused"; else fail "unknown: $out"; fi
rc=0; out=$(bash "$SCRIPTS/apps-remove.sh" run remove oldapp 2>&1 </dev/null) || rc=$?
check "the discovered instance and description go, the rest stays" test ! -e "$WORK/ct-oldapp" -a ! -e "$HS_SERVICES_DIR/oldapp.toml" -a -d "$WORK/oldshare" -a -e "$WORK/ct-other"

printf '#!/usr/bin/env bash
echo "ARGS: $*"
' > "$WORK/av.sh"; chmod +x "$WORK/av.sh"
rc=0; out=$(HS_APPS_VERSION=$WORK/av.sh bash "$SCRIPTS/apps-change.sh" plan update demo 2>&1 </dev/null) || rc=$?
check_eq "plan update is handed to apps-version.sh" "ARGS: plan update demo" "$out"

finish
