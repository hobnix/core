#!/usr/bin/env bash
# Job steps (#389): a long job reports "step n of m" to its record. The record writer is a stand-in that logs every call
# (job.sh uses $HOBNIX_BIN job-record when it answers --probe). Checks the step() heading of ui.sh inside a job (what update,
# rebuild and gc use), the explicit steps of hs ct update-all, real jobs of hs backup (verify, drill, share restore: a fake restic), the step count of pool changes and that nothing is reported outside a job. No root, no systemd.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok:   $1"; else echo "FAIL: $1 (got: $3 | want: $2)"; fail=1; fi; }

cat > "$T/hobnix" <<'FAKE'
#!/usr/bin/env bash
[ "$1" = job-record ] || exit 1
shift
[ "$1" != --probe ] || exit 0
[ "$1" != step ] || echo "$*" >> "$(dirname "$0")/steps.log"
FAKE
chmod +x "$T/hobnix"
export HOBNIX_BIN=$T/hobnix HS_LANG=en HS_PLAIN=1 HS_STATE_DIR=$T/state

# 1. step() inside a job reports n of m with its heading, and only when the script declared `steps N`
HS_JOB_ID=j1 bash -c ". '$here/scripts/lib/ui.sh'; steps 3; step 'Update'; step 'Check'; step 'Rebuild'" >/dev/null 2>&1
check "steps 3 in a job: the sequence is in the record" "step j1 1 3 Update|step j1 2 3 Check|step j1 3 3 Rebuild" "$(paste -sd'|' "$T/steps.log")"
rm -f "$T/steps.log"
bash -c ". '$here/scripts/lib/ui.sh'; steps 2; step A; step B" >/dev/null 2>&1
check "outside a job nothing is reported" "none" "$([ -s "$T/steps.log" ] && echo some || echo none)"
HS_JOB_ID=j1 bash -c ". '$here/scripts/lib/ui.sh'; step A" >/dev/null 2>&1
check "a heading without a declared count reports nothing" "none" "$([ -s "$T/steps.log" ] && echo some || echo none)"

# 2. hs ct update-all: one step per container
B=$T/fake; mkdir -p "$B"
cat > "$B/incus" <<'FAKE'
#!/usr/bin/env bash
case "$1 $2" in "list -f") printf 'web,RUNNING,CONTAINER\ndb,RUNNING,CONTAINER\n' ;; esac
exit 0
FAKE
printf '#!/usr/bin/env bash\nexit 0\n' > "$B/manage-ct.sh"
chmod +x "$B/incus" "$B/manage-ct.sh"
HS_JOB_ID=j2 HS_CALLER=job HS_INCUS=$B/incus HS_MANAGE_CT=$B/manage-ct.sh bash "$here/scripts/ct-update-all.sh" >/dev/null 2>&1
check "ct update-all: a step per container" "step j2 1 2 Updating container web|step j2 2 2 Updating container db" "$(grep ' Updating container ' "$T/steps.log" | paste -sd'|')"

# 3. hs backup verify and drill as real jobs: the steps of the script itself (a fake restic, no disk, no root)
BK=$T/bk; mkdir -p "$BK/bin" "$BK/mnt/restic" "$BK/state"
echo x > "$BK/mnt/restic/config"; echo pw > "$BK/state/restic-password"
cat > "$BK/bin/restic" <<'FAKE'
#!/usr/bin/env bash
[ "$1" = -r ] && shift 2; [ "$1" = --password-file ] && shift 2
cmd=$1; shift
case "$cmd" in
  ls) printf '{"type":"file","path":"%s","size":3}
' "$FAKE_FILE" ;;
  restore) target=""; while [ $# -gt 0 ]; do case "$1" in --target) target=$2; shift 2 ;; *) shift ;; esac; done
           mkdir -p "$target$(dirname "$FAKE_FILE")"; echo abc > "$target$FAKE_FILE" ;;
esac
exit 0
FAKE
chmod +x "$BK/bin/restic"
bkjob() { HS_JOB_ID=$1 HS_CALLER=job PATH="$BK/bin:$PATH" FAKE_FILE=/srv/f1 HS_STATE_DIR=$BK/state HS_BACKUP_NO_MOUNT=1 HS_BACKUP_MOUNT=$BK/mnt HS_BACKUP_CACHE=$BK/cache HS_RUN_DIR=$BK/run   bash "$here/scripts/backup.sh" "${@:2}" >/dev/null 2>&1; }
rm -f "$T/steps.log"
bkjob j3 verify
check "backup verify: two steps in the record" "step j3 1 2 Opening the backup repository|step j3 2 2 Reading a tenth of the stored data" "$(grep '^step j3 ' "$T/steps.log" | paste -sd'|')"
rm -f "$T/steps.log"
bkjob j4 drill 1
check "backup drill: choose, restore, compare" "step j4 1 3 Choosing files from the newest backup|step j4 2 3 Restoring the files into a temporary folder|step j4 3 3 Restore drill: 1 file(s)" "$(grep '^step j4 ' "$T/steps.log" | paste -sd'|')"
rm -f "$T/steps.log"; mkdir -p "$BK/to"
bkjob j5 restore latest /srv/f1 --to "$BK/to"
check "share restore: prepare, restore" "step j5 1 2 Preparing the target|step j5 2 2 Restoring /srv/f1" "$(grep '^step j5 ' "$T/steps.log" | paste -sd'|')"

# 4. pool changes: the plan heading is step 1, pplan_steps declares the real steps after it (manage-pool.sh, the line itself is used)
rm -f "$T/steps.log"
HS_JOB_ID=j6 bash -c ". '$here/scripts/lib/ui.sh'; $(grep '^pplan_steps()' "$here/scripts/manage-pool.sh"); steps 1; step 'Plan: replace a disk'; pplan_steps 3; step 'Taking the old disk out of the array'; step 'Formatting the new disk'; step 'Restoring the disk from the parity'" >/dev/null 2>&1
check "pool change: plan heading, then each real step" "step j6 1 1 Plan: replace a disk|step j6 2 4 Taking the old disk out of the array|step j6 3 4 Formatting the new disk|step j6 4 4 Restoring the disk from the parity" "$(grep '^step j6 ' "$T/steps.log" | paste -sd'|')"
exit $fail
