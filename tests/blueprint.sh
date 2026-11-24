#!/usr/bin/env bash
# hs blueprint / hs sys blueprint plan|start (scripts/blueprint.sh, blueprint-change.sh, lib/bundle-resolve.sh, lib/pkg_blueprint.py): the plan, the fill-only rule,
# the typed names, the order of the job and its failure rule, the record. Stand-ins for pkg.sh, parts.sh, part-change.sh, rebuild.sh, docker.sh,
# docker-setup.sh, apps-change.sh, apps-list.sh and the job library; nothing real is touched.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
export HS_LANG=en HS_PLAIN=1 HS_CALLER=test HS_PYTHON=python3 PYTHONUTF8=1 HS_BUNDLE_NET=ok HS_LOCKED_MARKER=$WORK/locked
export HS_STATE_DIR=$WORK/state HS_SETTINGS_DIR=$WORK/state/settings HS_MACHINE_FILE=$WORK/machine.toml HS_BLUEPRINT_POLL=0
mkdir -p "$HS_SETTINGS_DIR" "$WORK/jobs"
tab=$'\t'
LOG=$WORK/log; : > "$LOG"
printf 'role = "homeserver"\ntimeZone = "UTC"\n' > "$HS_MACHINE_FILE"

# ── the fixtures: what `hs pkg blueprint show` says (the real reader is tested below with a fake repository) ──
mkdir -p "$WORK/bp"
show_media() {
  printf '%s\n' "repo${tab}official" "version${tab}1.0.0" "tag${tab}v1.0.0" "commit${tab}abc" "title${tab}Media server" "description${tab}x" "roles${tab}homeserver" "added${tab}no" \
    "machine${tab}timeZone${tab}\"Europe/Vienna\"" "machine${tab}gpu${tab}\"nvidia\"" "setting${tab}backupNewShares${tab}true" \
    "part${tab}capabilities${tab}a${tab}-" "part${tab}recipes${tab}r1${tab}ok" "from${tab}r1${tab}official" "needs${tab}r1${tab}docker" "answer${tab}r1${tab}K${tab}V" \
    "part${tab}recipes${tab}r2${tab}ok" "from${tab}r2${tab}official" "needs${tab}r2${tab}-" "part${tab}recipes${tab}r3${tab}later:it asks for a secret (PASS)" "needs${tab}r3${tab}-" "docker${tab}webui${tab}m"
}
show_media > "$WORK/bp/media"
show_media | sed "s/^added${tab}no/added${tab}yes/; s/^repo${tab}official/repo${tab}mine/" > "$WORK/bp/added"
printf '%s\n' "error${tab}Docker is the core capability: use the [docker] table" > "$WORK/bp/bad"
printf 'error\t[settings] x \033[2Jpwned\xc2\x85status ok\xe2\x80\xa8line\n' > "$WORK/bp/hostile"
{ show_media; printf 'setting\tk\tconfirm_name\tx\xc2\x85y\xe2\x80\xa8z\n'; } > "$WORK/bp/hostile2"
show_media | grep -v "^docker${tab}" > "$WORK/bp/nodocker"
show_media | sed "s/^part${tab}recipes${tab}r2${tab}ok/part${tab}recipes${tab}r2${tab}later:it comes from the repository mine you added, so you confirm it yourself/" > "$WORK/bp/addedapp"
show_media | sed "s/^part${tab}capabilities${tab}a${tab}-/part${tab}capabilities${tab}edge-ports${tab}-/" > "$WORK/bp/edgeports"
show_media | sed "s/^roles${tab}homeserver/roles${tab}edge/" > "$WORK/bp/edge"

CAPS=$WORK/caps.tsv
printf '%s\n' "a${tab}caps${tab}1.0.0${tab}-${tab}new${tab}-${tab}feature${tab}A" > "$CAPS"
cat > "$WORK/pkg.sh" <<STUB
#!/usr/bin/env bash
case "\$1" in
  --capabilities) cat "$CAPS" ;;
  --repos) printf 'caps\turl\tsigned\tdefault\nmine\turl\tsigned\tadded\n' ;;
  blueprint)
    case "\$2" in
      show) f="$WORK/bp/\$3"; [ -f "\$f" ] || { printf 'error\tNo blueprint called %s.\n' "\$3"; exit 1; }; cat "\$f"; grep -q '^error' "\$f" && exit 1 || exit 0 ;;
      record) echo "record \$3" >> "$LOG"; echo "[applied.\$3]" > "$WORK/applied.toml" ;;
      list) printf 'media\tofficial\t1.0.0\thomeserver\ta,r1,docker\tnew\tMedia server\n' ;;
    esac ;;
  install) echo "install \$2" >> "$LOG"; [ "\$2" != "\${FAIL_INSTALL:-}" ] ;;
esac
STUB
printf '#!/usr/bin/env bash\ncat "%s"\n' "$WORK/parts.tsv" > "$WORK/parts.sh"
: > "$WORK/parts.tsv"
printf '#!/usr/bin/env bash\necho "enable $3" >> "%s"\nprintf "status\\tdone\\n"\n' "$LOG" > "$WORK/part-change.sh"
printf '#!/usr/bin/env bash\necho rebuild >> "%s"\n[ -z "${FAIL_REBUILD:-}" ]\n' "$LOG" > "$WORK/rebuild.sh"
echo no > "$WORK/docker.on"
cat > "$WORK/docker.sh" <<STUB
#!/usr/bin/env bash
case "\$1" in
  --status) printf 'owned\t%s\n' "\$(cat "$WORK/docker.on")" ;;
  enable) echo "docker enable \$*" >> "$LOG"; [ -z "\${FAIL_DOCKER:-}" ] ;;
esac
STUB
cat > "$WORK/docker-setup.sh" <<STUB
#!/usr/bin/env bash
echo "docker-setup \$*" >> "$LOG"
[ -z "\${REFUSE_DOCKER:-}" ] || { printf 'status\trefused\nreason\tan instance called docker exists\n'; exit 1; }
printf 'status\tok\nheading\tTurn Docker on\nstep\tcreate the container docker\nnote\tthis takes a minute\n'
[ -z "\${CONFIRM_DOCKER:-}" ] || printf 'confirm_name\tdocker\n'
printf 'command\ths docker enable --yes --job\nlong\tyes\n'
STUB
cat > "$WORK/apps-change.sh" <<STUB
#!/usr/bin/env bash
echo "apps \$*" >> "$LOG"
r=\$3
[ "\$1" != plan ] || { printf 'status\tok\n'; [ "\$r" = "\${NOTAG_APP:-}" ] || printf 'command\ths sys apps start install %s --tag v1.0.0\nlong\tyes\n' "\$r"; exit 0; }
if [ "\$r" = "\${REFUSE_APP:-}" ]; then printf 'status\trefused\nreason\tboom\n'; exit 1; fi
printf 'status\tstarted\nunit\ths-job-%s\njob\tJ-%s\n' "\$r" "\$r"
STUB
: > "$WORK/apps.tsv"
printf '#!/usr/bin/env bash\ncat "%s"\n' "$WORK/apps.tsv" > "$WORK/apps-list.sh"
mkdir -p "$WORK/jl"
cat > "$WORK/jl/job.sh" <<STUB
hs_job() { shift 2; "\${@:2}" >/dev/null 2>&1; HS_JOB_LAST_ID=J0; echo hs-job-test; }
hs_job_step() { :; }
hs_job_record() {
  case "\$1" in
    get) id=\$2; if [ "\$id" = "J-\${FAILJOB_APP:-}" ]; then echo '{"state": "failed"}'; else echo '{"state": "ok"}'; fi ;;
    result) echo "\$4" > "$WORK/result.json" ;;
  esac
}
STUB
chmod +x "$WORK"/*.sh
export HS_PKG=$WORK/pkg.sh HS_PARTS=$WORK/parts.sh HS_PART_CHANGE=$WORK/part-change.sh HS_REBUILD=$WORK/rebuild.sh HS_DOCKER_SCRIPT=$WORK/docker.sh
export HS_DOCKER_SETUP=$WORK/docker-setup.sh HS_APPS_CHANGE=$WORK/apps-change.sh HS_APPS_LIST=$WORK/apps-list.sh HS_JOB_LIB=$WORK/jl/job.sh
C="bash $SCRIPTS/blueprint-change.sh"
run() { rc=0; out=$($C "$@" 2>&1 </dev/null) || rc=$?; }
has() { grep -q -- "$1" <<<"$out"; }
reset() { : > "$LOG"; rm -f "$WORK/result.json"; printf 'role = "homeserver"\ntimeZone = "UTC"\n' > "$HS_MACHINE_FILE"; rm -f "$HS_SETTINGS_DIR"/*; echo no > "$WORK/docker.on"; : > "$WORK/apps.tsv"; printf '%s
' "a${tab}caps${tab}1.0.0${tab}-${tab}new${tab}-${tab}feature${tab}A" > "$CAPS"; : > "$WORK/parts.tsv"; }

echo "-- registry"
for r in "blueprint list${tab}blueprint.sh" "blueprint show${tab}blueprint.sh" "blueprint apply${tab}blueprint.sh"; do
  check "user row: $r" grep -qF "user${tab}$r" "$SCRIPTS/lib/registry.tsv"
done
for r in "sys blueprint list${tab}blueprint.sh" "sys blueprint plan <action>${tab}blueprint-change.sh" "sys blueprint start <action>${tab}blueprint-change.sh"; do
  check "sys row: $r" grep -qF "sys${tab}$r" "$SCRIPTS/lib/registry.tsv"
done
check "the preset rows are legacy" grep -qE "^user${tab}preset apply.*legacy:blueprint apply" "$SCRIPTS/lib/registry.tsv"
check "CHANGES allows blueprint apply" grep -qF '"blueprint": [{"fixed"' "$SCRIPTS/web-serve.py"
check "READS has blueprint/list" grep -qF '("blueprint", "list")' "$SCRIPTS/web-serve.py"

echo "-- plan: fill-only"
reset
printf 'timeZone = "UTC"\n' > "$HS_MACHINE_FILE"; printf 'role = "homeserver"\n' >> "$HS_MACHINE_FILE"
printf 'false' > "$HS_SETTINGS_DIR/backupNewShares"
run plan apply media
if [ "$rc" = 0 ] && has "^status${tab}ok" && has "^blueprint${tab}media${tab}official${tab}1.0.0${tab}v1.0.0" \
   && has "^part${tab}1${tab}config${tab}timeZone${tab}kept" && has "^part${tab}2${tab}config${tab}gpu${tab}set" && has "^part${tab}3${tab}config${tab}backupNewShares${tab}kept"; then
  pass "a value that is set is kept, the others are set"; else fail "plan media: $out"; fi
if has "^part${tab}[0-9]*${tab}parts${tab}a${tab}install" && has "^part${tab}[0-9]*${tab}rebuild" && has "^part${tab}[0-9]*${tab}docker${tab}-${tab}enable" \
   && has "^part${tab}[0-9]*${tab}app${tab}r1${tab}install" && has "^part${tab}[0-9]*${tab}app${tab}r3${tab}later" && has "^step${tab}create the container docker" && has "^long${tab}yes"; then
  pass "plan: parts, one rebuild, docker with its plan lines, apps (one later), long"; else fail "plan parts: $out"; fi
check_eq "the plan changes nothing" 'role = "homeserver"|timeZone = "UTC"' "$(sort "$HS_MACHINE_FILE" | paste -sd'|')"
check_eq "no confirm_name for an official blueprint without a docker name" 0 "$(grep -c '^confirm_name' <<<"$out")"

echo "-- plan: refusals"
run plan apply nosuch;  if [ "$rc" = 1 ] && has "No blueprint called"; then pass "unknown blueprint refused"; else fail "nosuch: $out"; fi
run plan apply hostile
check_eq "a hostile message is one status line and one reason line" 2 "$(printf '%s\n' "$out" | wc -l)"
check_eq "and no control, C1 or U+2028 byte is left in it" 0 "$(printf '%s' "$out" | LC_ALL=C grep -c -E $'\xc2[\x80-\x9f]|\xe2\x80[\xa8\xa9]|\x1b' || true)"
run plan apply bad;     if [ "$rc" = 1 ] && has "Docker is the core capability"; then pass "a blueprint with problems is refused with them"; else fail "bad: $out"; fi
run plan apply edge;    if [ "$rc" = 1 ] && has "role"; then pass "a role that does not fit is refused"; else fail "edge: $out"; fi
run plan apply 'A b';   if [ "$rc" = 1 ]; then pass "a bad name is refused"; else fail "bad name: $out"; fi
touch "$WORK/locked"; run plan apply media; if [ "$rc" = 1 ] && has "locked"; then pass "locked storage refused"; else fail "locked: $out"; fi; rm -f "$WORK/locked"
HS_BUNDLE_NET=fail run plan apply media; if [ "$rc" = 1 ] && has "network"; then pass "no network refused"; else fail "net: $out"; fi
REFUSE_DOCKER=1 run plan apply media; if [ "$rc" = 1 ] && has "Docker cannot be turned on: an instance called docker exists"; then pass "a refused docker plan refuses the blueprint"; else fail "docker refused: $out"; fi
run plan apply nodocker
if [ "$rc" = 1 ] && has "r1 needs Docker"; then pass "an app that needs Docker, with Docker off and no [docker] table: refused"; else fail "nodocker: $out"; fi
echo yes > "$WORK/docker.on"; : > "$LOG"
run plan apply nodocker
if [ "$rc" = 0 ]; then pass "the same with Docker on: allowed"; else fail "nodocker, docker on: $out"; fi
run plan apply media
if [ "$rc" = 0 ] && has "^part${tab}[0-9]*${tab}docker${tab}-${tab}kept" && ! has "^step${tab}create the container" && ! grep -q docker-setup "$LOG"; then
  pass "Docker on: part kept, no docker plan asked"; else fail "docker on: $out"; fi
echo no > "$WORK/docker.on"

echo "-- typed names"
run plan apply added;  if [ "$rc" = 0 ] && has "^confirm_name${tab}added"; then pass "an added repository: the blueprint name is typed"; else fail "added: $out"; fi
CONFIRM_DOCKER=1 run plan apply media; if [ "$rc" = 0 ] && has "^confirm_name${tab}docker"; then pass "the docker plan's name becomes the blueprint's confirm_name"; else fail "docker name: $out"; fi
run start apply added; if [ "$rc" = 1 ] && has "Type the name 'added'"; then pass "start without the name is refused"; else fail "start no confirm: $out"; fi
run start apply added --confirm nope; if [ "$rc" = 1 ] && has "not a name this plan asks for"; then pass "a wrong name is refused"; else fail "wrong confirm: $out"; fi
run start apply added --confirm added; if [ "$rc" = 0 ] && has "^status${tab}started" && has "^unit${tab}hs-job-test"; then pass "start with the name starts one job"; else fail "start added: $out"; fi
run start apply media; if [ "$rc" = 0 ] && has "^job${tab}J0"; then pass "start answers unit and job"; else fail "start media: $out"; fi
HS_BUNDLE_NET=fail run start apply media; if [ "$rc" = 1 ] && has "network"; then pass "start without network is refused"; else fail "start net: $out"; fi

echo "-- the job"
reset
run run apply media --tag v1.0.0
order=$(grep -E "^(install|enable|rebuild|docker|apps)" "$LOG" | sed -E 's/ .*//' | uniq | paste -sd'>')
check_eq "order: parts, rebuild, docker, apps" "install>enable>rebuild>docker>apps" "$order"
check_eq "an app is started with the repository and the tag of its own plan (apps-change.sh refuses a start without them)" "apps start install r1 --repo official --tag v1.0.0 --set K=V" "$(grep '^apps start install r1' "$LOG")"
check_eq "r3 needs a person: its app is not started" 0 "$(grep -c "apps start install r3" "$LOG")"
check_eq "docker comes before the first app" "docker" "$(grep -E '^(docker|apps)' "$LOG" | head -1 | sed 's/ .*//')"
check_eq "an app gets its answers as --set" "apps start install r1 --repo official --tag v1.0.0 --set K=V" "$(grep '^apps start install r1' "$LOG")"
check_eq "a set value is not overwritten" '"UTC"' "$(python3 "$SCRIPTS/machine-toml.py" get "$HS_MACHINE_FILE" timeZone --json)"
check_eq "a missing one is set (gpu)" '"nvidia"' "$(python3 "$SCRIPTS/machine-toml.py" get "$HS_MACHINE_FILE" gpu --json)"
check_eq "a missing setting is set" true "$(cat "$HS_SETTINGS_DIR/backupNewShares")"
check "the applied blueprint is recorded" grep -q "^record media" "$LOG"
check "the result names every part" grep -q '"config":"done".*"app:r1":"done".*"app:r3":"later' "$WORK/result.json"
echo yes > "$WORK/docker.on"; : > "$LOG"
printf 'r1\trecipe\trunning\t-\n' > "$WORK/apps.tsv"
printf '%s\n' "a${tab}caps${tab}1.0.0${tab}1.0.0${tab}current${tab}-${tab}feature${tab}A" > "$CAPS"
printf 'a\ton\tpart\tno\tyes\tA\n' > "$WORK/parts.tsv"
run run apply media --tag v1.0.0
check_eq "a second apply: nothing installed, no docker, no rebuild" "" "$(grep -E '^(install|enable|rebuild|docker)' "$LOG" | paste -sd'|')"
check_eq "a second apply: the app that is there is not installed again" "apps start install r2 --repo official --tag v1.0.0" "$(grep '^apps start' "$LOG")"
run run apply media --tag v9
if [ "$rc" = 1 ] && has "read the plan again"; then pass "the job refuses a blueprint that changed since the plan"; else fail "tag: $out"; fi

echo "-- an app of an added repository, edge-ports"
reset
run plan apply addedapp
if [ "$rc" = 0 ] && has "^part${tab}[0-9]*${tab}app${tab}r2${tab}later${tab}.*you added"; then pass "plan: an app of an added repository is later, not install"; else fail "addedapp plan: $out"; fi
run run apply addedapp --tag v1.0.0
check_eq "the job does not start it (apps-change.sh would refuse it without the typed name)" 0 "$(grep -c '^apps start install r2' "$LOG")"
check "and says so in the record" grep -q '"app:r2":"later' "$WORK/result.json"
reset
NOTAG_APP=r1 run run apply media --tag v1.0.0
check "an app whose plan shows no tag is a failed app, not a start without a tag" grep -q '"app:r1":"failed' "$WORK/result.json"
reset
printf 'edge-ports	caps	1.0.0	-	new	-	feature	E
' > "$CAPS"
run plan apply edgeports
if [ "$rc" = 0 ] && has "^warn${tab}edge-ports opens public"; then pass "plan: a warn line when edge-ports is switched on"; else fail "edge-ports plan: $out"; fi
run plan apply media
check_eq "no such warning without edge-ports" 0 "$(grep -c '^warn.*edge-ports' <<<"$out")"
printf 'edge-ports\tcaps\t1.0.0\t-\tnew\t-\tfeature\tE\n' > "$CAPS"
run run apply edgeports --tag v1.0.0
if has "edge-ports opens public"; then pass "the job warns when it switches edge-ports on"; else fail "edge-ports job: $out"; fi

echo "-- failure rule"
reset
FAILJOB_APP=r1 run run apply media --tag v1.0.0
if [ "$rc" = 1 ] && grep -q "install r2" "$LOG" && grep -q '"app:r1":"failed' "$WORK/result.json" && grep -q '"app:r2":"done"' "$WORK/result.json"; then
  pass "a failed app does not stop the next one"; else fail "app failure: $out"; fi
reset
REFUSE_APP=r1 run run apply media --tag v1.0.0
if [ "$rc" = 1 ] && grep -q "install r2" "$LOG" && grep -q '"app:r1":"failed: boom"' "$WORK/result.json"; then pass "a refused app start is a failed app, the next goes on"; else fail "app refused: $out"; fi
reset
FAIL_REBUILD=1 run run apply media --tag v1.0.0
if [ "$rc" = 1 ] && ! grep -q '^apps' "$LOG" && ! grep -q '^docker' "$LOG" && grep -q '"rebuild":"failed' "$WORK/result.json" && grep -q '"docker":"skipped"' "$WORK/result.json" \
   && ! grep -q "^record" "$LOG"; then pass "a failed rebuild stops before docker and apps, nothing is recorded"; else fail "rebuild failure: $out"; fi
reset
FAIL_INSTALL=a run run apply media --tag v1.0.0
if [ "$rc" = 1 ] && ! grep -q '^rebuild' "$LOG" && grep -q '"parts":"failed' "$WORK/result.json" && grep -q '"app:r1":"skipped"' "$WORK/result.json"; then pass "a failed install stops before the rebuild"; else fail "install failure: $out"; fi
reset
FAIL_DOCKER=1 run run apply media --tag v1.0.0
if [ "$rc" = 1 ] && ! grep -q '^apps' "$LOG" && grep -q '"docker":"failed' "$WORK/result.json"; then pass "a failed docker stops before the apps"; else fail "docker failure: $out"; fi

echo "-- hs blueprint (terminal command)"
B="bash $SCRIPTS/blueprint.sh"
reset
out=$($B list 2>&1); check_out "list shows the blueprint" "media.*Media server" echo "$out"
out=$($B --list 2>&1); check_eq "--list is the machine line (7 fields)" 7 "$(awk -F'\t' 'NR == 1 { print NF }' <<<"$out")"
out=$($B apply media --dry-run 2>&1 </dev/null); check_out "a dry run says nothing changed" "Dry run: nothing changed" echo "$out"
check_eq "and starts nothing" "" "$(grep '^record' "$LOG")"
out=$($B apply media 2>&1 </dev/null || true); check_out "without a terminal and without --yes it asks first" "asks first" echo "$out"
out=$($B apply media --yes 2>&1 </dev/null); check_out "--yes starts the job" "Started as a job: hs job follow hs-job-test" echo "$out"
out=$(CONFIRM_DOCKER=1 $B apply media --yes 2>&1 </dev/null || true); check_out "--yes without a terminal cannot type a name" "typed name" echo "$out"

echo "-- the reader (lib/pkg_blueprint.py) with a fake repository"
python3 - "$SCRIPTS" <<'PY' && pass "reader: lines, trust rule, secret answer, later" || fail "reader"
import sys, os
sys.path.insert(0, os.path.join(sys.argv[1], "lib"))
import pkg_blueprint as b
BP = {"name": "bp", "version": "1.0.0", "kind": "blueprint", "requires_core": ">=11", "roles": ["homeserver"],
      "blueprint": {"capabilities": ["storage"], "extensions": ["ext"], "recipes": ["ok", "term", "sec", "foreign"]},
      "docker": {"manager": "webui", "size": "m"}, "machine": {"timeZone": "UTC"}, "settings": {"backupNewShares": "true"},
      "answers": {"ok": {"K": "v"}}}
PKGS = {"ok": ("recipe", {"ask": [{"key": "K"}]}), "term": ("recipe", {"input": "terminal"}),
        "sec": ("recipe", {"ask": [{"key": "PASS", "type": "secret"}]}), "ext": ("extension", {})}
class R:
    def catalog(self):
        c = {"bp": [("official", {"kind": "blueprint"}, "v1.0.0", "c")]}
        for n, (k, _) in PKGS.items():
            c[n] = [("official", {"kind": k}, "v1", "c")]
        c["foreign"] = [("other", {"kind": "recipe"}, "v1", "c")]
        return c
    def all(self): return {"official": {"default": True}}
    def verified_package(self, name, repo=None):
        return ("official", {}, "v1.0.0", "c", BP if name == "bp" else PKGS[name][1])
class P:
    def installed(self): return {"ext": {}}
    def api_level(self): return 99
lines, bad = b.show(R(), P(), "bp")
assert any("foreign" in x and "no repository this blueprint may use" in x for x in bad), bad
assert "part\trecipes\tok\tok" in lines and "answer\tok\tK\tv" in lines
assert "part\trecipes\tterm\tlater:it is set up in a terminal" in lines
assert "part\trecipes\tsec\tlater:it asks for a secret (PASS)" in lines
assert "part\textensions\text\tinstalled" in lines and "docker\twebui\tm" in lines and 'machine\ttimeZone\t"UTC"' in lines
BP["answers"]["sec"] = {"PASS": "x"}
BP["blueprint"]["recipes"] = ["ok", "sec"]
lines, bad = b.show(R(), P(), "bp")
assert any("is a secret" in x for x in bad), bad
rows = b.listing(R(), P())
assert len(rows) == 1 and len(rows[0].split("\t")) == 7 and rows[0].split("\t")[5] in ("new", "applied", "update"), rows
PY

echo "-- hostile texts, the allow-list of keys, an index that says blueprint (lib/pkg_blueprint.py)"
python3 - "$SCRIPTS" "$WORK/bp/realhostile" <<'PY' && pass "hostile fields refused, allow-list, wrong kind refused" || fail "hostile fields"
import sys, os, copy
sys.path.insert(0, os.path.join(sys.argv[1], "lib"))
import pkg_blueprint as b
GOOD = {"name": "bp", "version": "1.0.0", "kind": "blueprint", "requires_core": ">=11", "roles": ["homeserver"], "title": "T", "description": "D",
        "blueprint": {"extensions": ["ext"], "recipes": ["ok"]}, "settings": {"language": "en"}, "answers": {"ok": {"K": "v"}}}
PKGS = {"ok": ("recipe", {"ask": [{"key": "K"}]}), "ext": ("extension", {})}
class R:
    def __init__(self, m, repos=None, kind="blueprint"): self.m, self.repos, self.kind = m, repos or {"official": {"default": True}}, kind
    def catalog(self):
        c = {"bp": [("official", {"kind": self.kind}, "v1.0.0", "c")]}
        for n, (k, _) in PKGS.items(): c[n] = [("official", {"kind": k}, "v1", "c")]
        return c
    def all(self): return self.repos
    def verified_package(self, name, repo=None): return ("official", {}, "v1.0.0", "c", self.m if name == "bp" else PKGS[name][1])
class P:
    def installed(self): return {}
    def api_level(self): return 99
lines, bad = b.show(R(GOOD), P(), "bp")
assert lines and not bad, bad
HOSTILE = "v\nmachine\tpools\t[]\npart\trecipes\tforeign\tok"
def mut(f):
    m = copy.deepcopy(GOOD); f(m); return m
cases = {
    "title": mut(lambda m: m.update(title=HOSTILE)),
    "title_de": mut(lambda m: m.update(title_de="a\rb")),
    "description": mut(lambda m: m.update(description="a\nb")),
    "settings value": mut(lambda m: m["settings"].update(language=HOSTILE)),
    "answers value": mut(lambda m: m["answers"]["ok"].update(K=HOSTILE)),
    "answers key": mut(lambda m: m["answers"]["ok"].update({"K\nx": "v"})),
    "app name": mut(lambda m: m["blueprint"].update(recipes=["ok\n"])),
    "part name": mut(lambda m: m["blueprint"].update(extensions=["ext\nmachine\tx"])),
    "tab in a value": mut(lambda m: m.update(title="a\tb")),
    "DEL": mut(lambda m: m.update(title="a\x7fb")),
}
for what, m in cases.items():
    lines, bad = b.show(R(m), P(), "bp")
    assert lines == [] and bad, (what, lines, bad)
    assert not any("machine\tpools" in x for x in lines), what
long_ = mut(lambda m: m.update(title="x" * 400))
assert b.show(R(long_), P(), "bp")[0] == [], "a long title"
# the writer on its own: with the load check removed, no field can still start a row
orig = b.manifest_problems
b.manifest_problems = lambda m: []
for what in ("title", "settings value", "answers value"):
    lines, bad = b.show(R(cases[what]), P(), "bp")
    assert lines == [] and bad and "control character" in bad[0], (what, lines, bad)
b.manifest_problems = orig
try:
    b._row("a", "b\nc"); raise SystemExit("_row let a newline through")
except ValueError:
    pass
# Unicode line breaks (splitlines() in web-serve.py parse_change breaks on them) and C1 controls
for ch in ("\u0085", " ", " ", "\x80", "\x9f", "\x0b", "\x0c", "\x1c"):
    for field in ("title", "description"):
        lines, bad = b.show(R(mut(lambda m: m.update({field: "a" + ch + "machine\tpools\t[]"}))), P(), "bp")
        assert lines == [] and bad, (repr(ch), field, lines, bad)
    assert b.text_problems(mut(lambda m: m["settings"].update(language="a" + ch + "b"))), repr(ch)
    try:
        b._row("a", "b" + ch + "c"); raise SystemExit("_row let %r through" % ch)
    except ValueError:
        pass
# an allowed key must fit its schema entry (type, pattern, choices): else every later machine-sync check breaks
for table, key, val in (("machine", "siteName", 5), ("machine", "siteName", "Evil Name!"), ("machine", "timeZone", ["a", "b"]),
                        ("machine", "hostName", [1]), ("settings", "icons", "emoji"), ("settings", "loginMessage", "maybe")):
    assert any(key in x for x in b.manifest_problems(mut(lambda m: m.update({table: {key: val}})))), (table, key, val)
for table, key, val in (("machine", "siteName", "home"), ("machine", "timeZone", "Europe/Vienna"), ("settings", "icons", "ascii"), ("settings", "loginMessage", "true")):
    assert not b.manifest_problems(mut(lambda m: m.update({table: {key: val}}))), (table, key, val, b.manifest_problems(mut(lambda m: m.update({table: {key: val}}))))
# hostile KEYS: no message may carry them (a message is printed as a line)
HK = "x status\t\x1b[2J\u2028reason\tpwned"
for m in (mut(lambda m: m["settings"].update({HK: "v"})), mut(lambda m: m["machine"].update({HK: "v"})) if "machine" in GOOD else mut(lambda m: m.update(machine={HK: "v"})),
          mut(lambda m: m.update({HK: "v"})), mut(lambda m: m["answers"]["ok"].update({HK: "v"})), mut(lambda m: m["blueprint"].update({HK: ["a"]})),
          mut(lambda m: m.update(answers={HK: {"K": "v"}}))):
    probs = b.manifest_problems(m)
    assert probs and not any(b.CONTROL.search(x) for x in probs), probs
    lines, bad = b.show(R(m), P(), "bp")
    assert lines == [] and bad and not any(b.CONTROL.search(x) or "pwned" in x.split("?")[0] for x in bad), bad
    assert all(len(x.splitlines()) == 1 for x in bad), bad
# hostName is not settable and has no pattern: never allowed
assert "hostName" not in b.ALLOWED_KEYS
assert any("hostName" in x for x in b.manifest_problems(mut(lambda m: m.update(machine={"hostName": "Evil Name!"}))))
import schema_options
for key in b.ALLOWED_KEYS:
    assert schema_options.specs()[key].get("settable") is not False, key
orig_allowed = b.ALLOWED_KEYS
b.ALLOWED_KEYS = orig_allowed + ("hostName",)
assert any("not settable" in x for x in b.manifest_problems(mut(lambda m: m.update(machine={"hostName": "x"})))), "a key with settable = false"
b.ALLOWED_KEYS = orig_allowed
# the allow-list: nothing security-relevant, whatever the table
for key in ("nodeKeys", "sshKeys", "adminUser", "sshOverIp", "gatewayUnknownHostPublic", "tailscaleAuthKeyFile", "incusDefaultPool", "pools", "role", "capabilities", "firewall", "notAnOption"):
    for table in ("machine", "settings"):
        m = mut(lambda m: m.update({table: {key: "x"}}))
        assert any(key in x for x in b.manifest_problems(m)), (table, key, b.manifest_problems(m))
assert not b.manifest_problems(mut(lambda m: m.update(machine={"timeZone": "UTC"}))), "a plain preference is allowed"
for key in b.ALLOWED_KEYS:
    for bad_word in ("ssh", "node", "admin", "gateway", "tailscale", "pool", "firewall", "key", "user"):
        assert bad_word not in key.lower() or key == "keyMap", key
# the index says blueprint, the package.toml says something else
lines, bad = b.show(R(mut(lambda m: m.update(kind="recipe")), kind="blueprint"), P(), "bp")
assert any("is not a blueprint" in x for x in bad), bad
assert b.listing(R(mut(lambda m: m.update(kind="recipe"))), P()) == [], "listing skips it"
try:
    b.record(R(mut(lambda m: m.update(kind="recipe"))), P(), "bp"); raise SystemExit("record wrote it")
except ValueError:
    pass
# an app of an added repository is later, with its repository named
class R2(R):
    def catalog(self):
        c = R.catalog(self); c["ok"] = [("mine", {"kind": "recipe"}, "v1", "c")]; c["bp"] = [("mine", {"kind": "blueprint"}, "v1.0.0", "c")]; return c
    def verified_package(self, name, repo=None): return (repo or "mine", {}, "v1.0.0", "c", self.m if name == "bp" else PKGS[name][1])
lines, bad = b.show(R2(GOOD, {"official": {"default": True}, "mine": {}}), P(), "bp")
assert any(x.startswith("part\trecipes\tok\tlater:it comes from the repository") for x in lines), lines
assert "from\tok\tmine" in lines, lines
# the real reader on a hostile manifest (a tab in a settings key): the whole show refuses; what it prints is what pkg.sh prints (error lines)
m = mut(lambda m: m["settings"].update({"k\tconfirm_name\tx": "v"}))
lines, bad = b.show(R(m), P(), "bp")
assert lines == [] and bad
open(sys.argv[2], "w", encoding="utf-8").write("\n".join("error\t" + x for x in bad) + "\n")
PY
check_eq "the real reader's refusal of a tab in a key: only error lines, two columns each" "error 2" "$(awk -F'\t' '{ if ($1 != "error" || NF != 2) bad = 1; n++ } END { print (bad ? "bad" : "error"), (n ? 2 : 0) }' "$WORK/bp/realhostile")"
run plan apply realhostile
check_eq "a plan on that hostile manifest is refused: a status line and a reason line, nothing else" "status${tab}refused|reason" "$(printf '%s\n' "$out" | awk -F'\t' '{ printf "%s%s", (NR > 1 ? "|" : ""), ($1 == "status" ? $1 FS $2 : $1) }')"
check_eq "and it is not a plan" 0 "$(grep -c '^part' <<<"$out")"
# defence in depth: a stub that bypasses the reader's checks still cannot add a column or a line to the plan
run plan apply hostile2
check_eq "a tab in a setting key: every part line of the plan has 6 columns" "" "$(grep '^part' <<<"$out" | awk -F'\t' 'NF != 6' | paste -sd'|')"
check_eq "and no line of its own comes out of it" 0 "$(grep -c '^confirm_name' <<<"$out")"
check_eq "C1 and U+2028 in a field are one line with spaces" 1 "$(grep -c 'confirm_name x y z' <<<"$out")"

finish
