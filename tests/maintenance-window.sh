#!/usr/bin/env bash
# Spin-down rules (docs/Entwicklungsnotizen.md, "Maintenance window"): periodic SMART polling never wakes a disk, and
# the HDD jobs sit inside the 03:00-06:30 window. Greps the sources; needs no root.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# only monitor.sh and disk-health.sh may call smartctl; the collectors go through them
bad=$(cd "$SCRIPTS" && grep -lE '(^|[^a-z_/.-])smartctl +-' state.sh state-db.py deck-status.sh overview-status.sh health-check.sh web-serve.py 2>/dev/null || true)
check_eq "the periodic collectors never call smartctl themselves" "" "$bad"
check "monitor.sh polls with smartctl -n standby" grep -q 'smartctl -n standby' "$SCRIPTS/monitor.sh"
check "disk-health list asks every disk with the standby flag" grep -q 'smart_json "/dev/\$name" standby' "$SCRIPTS/disk-health.sh"
check "smart_json turns on -n standby when asked" grep -q 'flags=(-n standby' "$SCRIPTS/disk-health.sh"

# no timer script lists/walks /bulk (find in cache-mover and sync-shares run inside the window or on the SSD)
bad=$(cd "$SCRIPTS" && grep -nE '\b(du|find|ls) +[^|;]*/bulk' health-check.sh monitor.sh deck-status.sh state.sh 2>/dev/null | grep -v '/mnt/bulk/cache' || true)   # the cache is on the SSD
check_eq "no health/monitor/deck script walks /bulk" "" "$bad"

# HDD jobs: start times between 03:00 and 06:59 (no job at an odd hour)
for pat in 'startAt = "Sat 03:10"' 'startAt = "\*-\*-\* 03:15"' 'interval = "Sun \*-\*-\* 05:00:00"' 'randomizedDelaySec = "0"' 'startAt = "04:00"' 'startAt = "\*-\*-\* 03:05:00"' 'startAt = "\*-\*-\* 03:35:00"'; do
  check "the Nix config (configuration.nix or a capability module) has $pat" grep -qE "$pat" "$ROOT/configuration.nix" "$ROOT"/capabilities/*/module.nix
done

# Every timer and collector: each `startAt` in the Nix files is either an HDD job inside the window (03:00-06:59, or the one documented 06:30 SSD job)
# or on this list of frequent / monthly jobs that do not read the spinning disks. A new timer fails here until someone classifies it
# (docs/Entwicklungsnotizen.md, "Maintenance window").
known='\*:\*:0/10|\*:0/15|\*:7/15|\*:0/2|minutely|hourly|\*-\*-25 08:00'
# *:*:0/10 = deck-status and edge-status (reads state/zpool/df, no smartctl without standby), *:0/15 = health-check, *:7/15 = cache-mover --if-full
# (df on the SSD), *:0/2 = remote-mount (other servers), minutely = state-collect and the AD lookup warm-up, hourly = share snapshots (opt-in),
# 25th 08:00 = backup report (reads the restic report the 04:00 run wrote)
bad=$(grep -rhoE 'startAt = "[^"]*"' "$ROOT/configuration.nix" "$ROOT"/capabilities/*/module.nix | sed 's/startAt = "//; s/"$//'   | grep -vE "^($known)\$" | grep -vE '(^|[ *-])0[3-6]:[0-5][0-9](:00)?$' || true)
check_eq "every startAt is in the window or on the known list of jobs that leave the HDDs alone" "" "$bad"

# the collectors that run all day (hs-state-collect, hs-live via live-collect.py, hs-deck-status, hs-health-check, the live topics they read):
# none of their scripts walks /bulk or /mnt/bulk, and the live topics that name disks go through the standby-aware readers
bad=$(cd "$SCRIPTS" && grep -nE '(du|find|ls) +[^|;]*/(mnt/)?bulk' state.sh state-db.py live-collect.py live.sh live-state.py deck-status.sh health-check.sh monitor.sh 2>/dev/null | grep -v '/mnt/bulk/cache' || true)
check_eq "state collect, live collect, deck and health scripts never walk /bulk" "" "$bad"
bad=$(cd "$SCRIPTS" && grep -lE '(^|[^a-z_/.-])smartctl +-' live-collect.py live.sh live-state.py 2>/dev/null || true)
check_eq "live collect never calls smartctl itself" "" "$bad"
check "hs-state-collect runs state.sh collect (disks via monitor.sh --disks)" grep -q 'state.sh collect' "$ROOT/capabilities/storage/module.nix"
finish
