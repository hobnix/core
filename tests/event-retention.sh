#!/usr/bin/env bash
# Event retention classes (hobnix/server#927): ephemeral, audit and metric, the pruning by class in scripts/state-db.py, the rollup upsert
# by (month, user, kind), the migration rule for a declaration without retention, and 5 years of fake data that stays small.
# No root, python3 only.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
command -v python3 >/dev/null || { echo "python3 missing: skipped"; exit 0; }
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }
export HS_PLAIN=1 HS_LANG=en HS_CALLER=test
mkdir -p "$WORK/state" "$WORK/pe"
export HS_STATE_DIR=$(wp "$WORK/state") HS_PKG_EVENTS_DIR=$(wp "$WORK/pe") HS_STATE_DB=$(wp "$WORK/state/state.db")
tab=$'\t'

echo "-- the declaration file"
printf 'pkg.rapp.tick\tinfo\t-\tTick\t-\ta tick\t-\t-\t-\t-\tmetric\n' > "$WORK/pe/rapp.tsv"
printf 'pkg.rapp.old\tinfo\t-\tOld\t-\tno retention column\t-\t-\t-\t-\n' >> "$WORK/pe/rapp.tsv"
printf 'pkg.rapp.bad\tinfo\t-\tBad\t-\tunknown class\t-\t-\t-\t-\tforever\n' >> "$WORK/pe/rapp.tsv"
got=$(python3 -I -c '
import importlib.util, sys
s = importlib.util.spec_from_file_location("pkg_events", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(" ".join("%s=%s" % (r["kind"], r["retention"]) for r in m.read_file(sys.argv[2], "rapp")))
print(m.retention_of("pkg.nosuch.x"))' "$SCRIPTS/lib/pkg_events.py" "$(wp "$WORK/pe/rapp.tsv")" | tr -d '\r')
check_eq "a row without the column is audit, an unknown class is dropped" "pkg.rapp.tick=metric pkg.rapp.old=audit
audit" "$got"
check_eq "the media copy in the core is read as audit" "audit" "$(python3 -I -c '
import importlib.util, sys
s = importlib.util.spec_from_file_location("pkg_events", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(m.retention_of("pkg.sabnzbd.added"))' "$SCRIPTS/lib/pkg_events.py")"

echo "-- a declaration without retention"
got=$(python3 -I -c '
import importlib.util, sys
s = importlib.util.spec_from_file_location("pkg_events", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
e = {"kind": "x", "level": "info", "label": "B", "meaning": "m"}
print(len(m.manifest_problems("p", [e])), len(m.manifest_problems("p", [dict(e, retention="forever")])), m.rows("p", [e])[0][-1])' "$SCRIPTS/lib/pkg_events.py" | tr -d '\r')
check_eq "a manifest event without retention validates and reads as audit, a bad class does not" "0 1 audit" "$got"

echo "-- five years of fake data"
printf 'pkg.rapp.tick\tinfo\t-\tTick\t-\ta tick\t-\t-\t-\t-\tmetric\n' > "$WORK/pe/rapp.tsv"
printf 'pkg.rapp.flash\tinfo\t-\tFlash\t-\ta flash\t-\t-\t-\t-\tephemeral\n' >> "$WORK/pe/rapp.tsv"
printf 'pkg.rapp.login\tinfo\t-\tLogin\t-\ta login\t-\t-\t-\t-\taudit\n' >> "$WORK/pe/rapp.tsv"
out=$(HS_EVENT_KEEP=1000000 HS_EVENT_DAYS=3650 python3 -I -c '
import importlib.util, os, sys
s = importlib.util.spec_from_file_location("sd", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
c = m.open_rw()
t0 = 1577836800                                    # 2020-01-01 UTC
days = 5 * 365
for d in range(days):
    t = t0 + d * 86400
    with c:
        for u in ("anna", "ben"):
            for i in range(24):                    # a tick per hour and user: the raw rate an extension would store
                m.event(c, t + i * 3600, "rapp.tick", u, "", "pkg")
                m.rollup_add(c, t + i * 3600, u, "tick", 1, 5)
        m.event(c, t, "rapp.flash", "x", "", "pkg")
        m.event(c, t, "rapp.login", "anna", "", "pkg")
        m.event(c, t, "rapp.undeclared", "x", "", "pkg")
        m.trim_events(c, t + 86399)
q = lambda sql: c.execute(sql).fetchone()[0]
last = t0 + (days - 1) * 86400
print(q("SELECT count(*) FROM events WHERE kind=\"rapp.flash\""), q("SELECT max(time) - min(time) FROM events WHERE kind=\"rapp.flash\"") // 86400)
print(q("SELECT count(*) FROM events WHERE kind=\"rapp.tick\""), q("SELECT count(*) FROM events WHERE kind=\"rapp.login\""))
print(q("SELECT count(*) FROM events WHERE kind=\"rapp.undeclared\""))
print(q("SELECT count(*) FROM rollups"), q("SELECT sum(n) FROM rollups"), q("SELECT sum(sum) FROM rollups"))
print(q("SELECT n FROM rollups WHERE month=\"2020-02\" AND user=\"ben\" AND kind=\"tick\""))
c.commit(); c.execute("VACUUM")
print(os.path.getsize(sys.argv[2]) < 1000000)
r = sys.argv[2] + ".rollups"
c.execute("ATTACH ? AS r", (r,)); c.execute("CREATE TABLE r.rollups AS SELECT * FROM main.rollups"); c.commit()
print(os.path.getsize(r) < 50000)
' "$SCRIPTS/state-db.py" "$HS_STATE_DB")
check_eq "ephemeral: one week left" "7 6" "$(sed -n 1p <<<"$out")"
check_eq "metric: about a month of raw ticks, audit: the whole window" "1680 1825" "$(sed -n 2p <<<"$out")"
check_eq "an undeclared kind follows the general limit only" "1825" "$(sed -n 3p <<<"$out")"
check_eq "rollups: 60 months x 2 users, no tick lost" "120 87600 438000" "$(sed -n 4p <<<"$out")"
check_eq "a month row adds up (Feb 2020: 29 days x 24)" "696" "$(sed -n 5p <<<"$out")"
check_eq "5 years stay under a megabyte" "True" "$(sed -n 6p <<<"$out" | tr -d '')"
check_eq "the rollup table alone is under 50 KB" "True" "$(sed -n 7p <<<"$out" | tr -d '')"

echo "-- the command line"
rm -f "$HS_STATE_DB"
S="bash $SCRIPTS/state.sh"
$S rollup-add tick anna --time 1580515200 --n 3 --sum 10
$S rollup-add tick anna --time 1580600000 --n 2
check_eq "two adds in one month are one row" "2020-02${tab}anna${tab}tick${tab}5${tab}10" "$($S rollups tick anna)"
check "a bad kind is refused" bash -c "! $S rollup-add 'bad kind' anna"
finish
