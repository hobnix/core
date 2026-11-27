#!/usr/bin/env bash
# Web interface, share forms: the allowed and refused shapes of the `shares` changes in scripts/web-serve.py (add, perm, rename, delete, purge, restore),
# and the job names of a long share (scripts/lib/job.sh).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! have python3; then skip "python3 missing"; finish; exit 0; fi

echo "-- web share forms"
if out=$(python3 -I "$ROOT/tests/web-forms-shares-test.py" 2>&1); then pass "share form shapes ($(grep -E '^Ran ' <<<"$out"))"; else fail "share form shapes: $(tail -n 25 <<<"$out")"; fi

# issue 1245: the job of a long share must have a unit name and a job id that the web interface accepts (its log and record are read by name)
echo "-- the job of a long share can be followed"
if python3 -c 'import fcntl' 2>/dev/null; then
  mkdir -p "$WORK/bin" "$WORK/jobs" "$WORK/state"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/systemd-run"; chmod +x "$WORK/bin/systemd-run"
  long=$(printf 'a%.0s' $(seq 1 80)).deleted-20261012
  unit=$(PATH="$WORK/bin:$PATH" HS_JOBS_DIR=$WORK/jobs HS_STATE_DIR=$WORK/state HS_JOB_RECORD=python HS_JOB_NOBUMP=1 \
    bash -c '. "$1/lib/job.sh"; hs_job "share-undelete-$2" "hs share $2 undelete" -- true' _ "$SCRIPTS" "$long" 2>/dev/null)
  jid=""; for f in "$WORK"/jobs/*.json; do [ ! -e "$f" ] || jid=$(basename "$f" .json); done
  fits=$(python3 -I - "$ROOT/scripts/web-serve.py" "$unit" "$jid" <<'PY'
import importlib.util, re, sys
spec = importlib.util.spec_from_file_location("web_serve", sys.argv[1])
ws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ws)
print(bool(re.fullmatch(ws.UNIT, sys.argv[2])), bool(re.fullmatch(ws.READS[("jobs", "record")]["args"][0], sys.argv[3])))
PY
)
  check_eq "unit name and job id fit the web patterns ($unit)" "True True" "$fits"
  check_match "the unit still says what it is" '^hs-job-share-undelete-a+-[0-9]{6}$' "$unit"
else
  skip "fcntl is missing: job names not tested here"
fi
finish
