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
R=$WORK/repo; mkdir -p "$R/recipes/demo" "$R/recipes/needy" "$R/recipes/docker"; cd "$R"
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
[package.demo]\nversion = "1.0.0"\nkind = "recipe"\npath = "recipes/demo"\nrequires_core = ">=1"\n[package.needy]\nversion = "1.0.0"\nkind = "recipe"\npath = "recipes/needy"\nrequires_core = ">=1"\n' > index.toml
git add -A && git commit -q -m one && git -c user.signingkey="$WORK/good.pub" tag -s v1.0.0 -m release
cd "$ROOT"
$PKGPY repo add test "$R" --key "$WORK/signers"
$PKGPY fetch test >/dev/null

# stand-ins: incus (docker is not there), parts (tailscale off), recipe, orchestrator, health, job library
LOG=$WORK/log; : > "$LOG"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/incus"
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
run plan install demo --name second;     check_eq "a container name of its own is allowed" 0 "$rc"
has "an instance named second" && pass "and shows it" || fail "$out"
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
run plan remove demo;                      check_eq "only install exists" 1 "$rc"
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
check_eq "and no result is written" "none" "$(python3 -c 'import json,sys;print(json.loads(sys.argv[1]).get("result") or "none")' "$rec")"
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

finish
