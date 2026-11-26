#!/usr/bin/env bash
# hs sys pkg fit (scripts/pkg-fit.sh, #793): what a package states it needs next to this server. The package reads, incus, the pool read, the
# parts list and /proc are stand-ins. And Repos.declared (scripts/pkg_repo.py): the trailing columns of pkg cards, from a manifest nobody trusts.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
have jq || { skip "needs jq"; finish; exit 0; }
export HS_LANG=en HS_PLAIN=1
tab=$'\t'
mkdir -p "$WORK/proc" "$WORK/bin"
# 16 GiB in total, 8 GiB available
printf 'MemTotal: 16777216 kB\nMemFree: 1000 kB\nMemAvailable: 8388608 kB\n' > "$WORK/proc/meminfo"

# name kind repo available installed state core audience title
row() { local IFS=$'\t'; printf '%s\n' "$*"; }
{
  for n in small hungry huge bigdisk silent half gpuapp needsy odd broken lonely; do row "$n" recipe official 1.0.0 - new no generic "$n"; done
  row later recipe official 2.0.0 - waits no generic later
  row there recipe official 1.0.0 1.0.0 current no generic there
  row older recipe official 1.1.0 1.0.0 update no generic older
  row addon extension official 1.0.0 - new no generic addon
  row small recipe family 1.0.0 - new no generic small
} > "$WORK/market"
# name repo category icon verified needs ram_mb disk_gb gpu
{
  row small official - - - - 1024 10 no
  row hungry official - - - - 12000 10 no
  row huge official - - - - 32768 10 no
  row bigdisk official - - - - 1024 500 no
  row silent official - - - docker - - no
  row half official - - - share 512 - no
  row gpuapp official - - - - 512 1 yes
  row needsy official - - - docker,share,tailscale 512 1 no
  row odd official - - - quantum 512 1 no
  row broken official - - - '?' '?' '?' '?'
  row later official - - - - 512 1 no
  row there official - - - - 512 1 no
  row small family - - - - 999999 1 no
} > "$WORK/cards"
cat > "$WORK/pkg.sh" <<STUB
case "\$1" in --market) cat "$WORK/market" ;; --cards) cat "$WORK/cards" ;; esac
STUB
# the pool of the default profile has 100 GiB free of 200 GiB; another pool has room that must not count
cat > "$WORK/pools.sh" <<'STUB'
printf 'other\tzfs\tbulk\t999999999999999\t999999999999999\t/bulk/x\n'
printf 'fastpool\tzfs\tfast\t107374182400\t214748364800\trpool/incus\n'
STUB
cat > "$WORK/parts.sh" <<'STUB'
printf 'tailscale\t%s\n' "${PARTS_TS:-off}"
STUB
echo '{"gpu":{"cards":[],"total":0}}' > "$WORK/gpu-none"
echo '{"gpu":{"cards":[{"driver":"nvidia"}],"total":1}}' > "$WORK/gpu-nvidia"
echo '{"gpu":{"cards":[{"driver":"i915"}],"total":1}}' > "$WORK/gpu-other"
cat > "$WORK/bin/incus" <<STUB
#!/usr/bin/env bash
case "\$*" in
  "query /1.0/profiles/default") echo '{"devices":{"eth0":{"type":"nic"},"root":{"type":"disk","path":"/","pool":"fastpool"}}}' ;;
  "query /1.0/resources") cat "\${GPU_FILE:-$WORK/gpu-none}" ;;
  "list -f csv -c n") printf '%s\n' "\${INSTANCES:-web}" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$WORK/bin/incus"
fit() { HS_PKG=$WORK/pkg.sh HS_CT_POOLS=$WORK/pools.sh HS_PARTS=$WORK/parts.sh HS_INCUS=${HS_INCUS:-$WORK/bin/incus} HS_PROC=${HS_PROC:-$WORK/proc} bash "$SCRIPTS/pkg-fit.sh"; }
out=$(fit); rc=$?
check_eq "the read succeeds" 0 "$rc"
of() { awk -F'\t' -v n="$1" -v r="${2:-official}" '$1 == n && $2 == r' <<<"$out"; }
verdict() { of "$@" | cut -f3 | sort -u | tr '\n' ' ' | sed 's/ $//'; }
line() { of "$1" "${3:-official}" | awk -F'\t' -v c="$2" '$4 == c { print $5 " " $6 " " $7 " " $8 }'; }

check_eq "eight fields on every line" "8" "$(awk -F'\t' '{ print NF }' <<<"$out" | sort -u | tr '\n' ' ' | sed 's/ $//')"
check_eq "no empty field" "0" "$(awk -F'\t' '{ for (i = 1; i <= NF; i++) if ($i == "") n++ } END { print n + 0 }' <<<"$out")"
check_eq "enough of both: fits" "fits" "$(verdict small)"
check_eq "memory: need, available and total in bytes" "ok 1073741824 8589934592 17179869184" "$(line small memory)"
check_eq "disk: the pool of the default profile's root disk" "ok 10737418240 107374182400 214748364800" "$(line small disk)"
check_eq "the same name in another repository is its own package" "no" "$(verdict small family)"
check_eq "more memory than is free now: a note" "note" "$(verdict hungry)"
check_eq "more memory than the server has: no" "no" "$(verdict huge)"
check_eq "and the memory line says it" "no 34359738368 8589934592 17179869184" "$(line huge memory)"
check_eq "more disk than is free: no" "no" "$(verdict bigdisk)"
check_eq "neither memory nor disk stated: never fits" "unstated" "$(verdict silent)"
check_eq "only memory stated: fits" "fits" "$(verdict half)"
check_eq "and the disk line says unstated" "unstated - 107374182400 214748364800" "$(line half disk)"
check_eq "a share is never in the way" "ok share - -" "$(line half share)"
check_eq "no card: the optional graphics card is a note" "note" "$(verdict gpuapp)"
check_eq "gpu line: none" "note - none -" "$(line gpuapp gpu)"
check_eq "no gpu line without the need" "" "$(line small gpu)"
check_eq "docker and tailscale to be set up: a note" "note" "$(verdict needsy)"
check_eq "docker missing" "note docker missing -" "$(line needsy docker)"
check_eq "tailscale off" "note tailscale missing -" "$(line needsy tailscale)"
check_eq "a need this server cannot provide: no" "no" "$(verdict odd)"
check_eq "it names the word" "no quantum - -" "$(line odd need)"
check_eq "an unreadable manifest: unknown, not unstated" "unknown" "$(verdict broken)"
check_eq "no card row at all: unknown" "unknown" "$(verdict lonely)"
check_eq "a release that waits for a newer core: no" "no" "$(verdict later)"
check_eq "core line" "no - - -" "$(line later core)"
check_eq "an installed app has no line" "" "$(of there)$(of older)"
check_eq "an add-on has no line" "" "$(of addon)"

out=$(GPU_FILE=$WORK/gpu-nvidia INSTANCES=docker PARTS_TS=on fit)
check_eq "an NVIDIA card: fits" "fits" "$(verdict gpuapp)"
check_eq "docker and tailscale there: fits" "fits" "$(verdict needsy)"
out=$(GPU_FILE=$WORK/gpu-other fit)
check_eq "another card: a note, never a claim that it works" "note - other -" "$(line gpuapp gpu)"

# nothing of the server can be read: nothing claims to fit
out=$(HS_INCUS=false HS_PROC=$WORK/none fit)
check_eq "no facts: unknown" "unknown" "$(verdict small)"
check_eq "no facts: the memory line" "unknown 1073741824 - -" "$(line small memory)"
check_eq "no facts: no line claims ok for memory or disk" "0" "$(awk -F'\t' '($4 == "memory" || $4 == "disk") && $5 == "ok"' <<<"$out" | grep -c .)"

echo "-- the columns of pkg cards (Repos.declared)"
decl() {
  python3 - "$SCRIPTS" "$1" <<'PY'
import sys, tomllib
sys.path.insert(0, sys.argv[1])
import pkg_repo
print(" ".join(pkg_repo.Repos.declared(tomllib.loads(sys.argv[2]) if sys.argv[2] else {})))
PY
}
check_eq "a full manifest" "docker,share 4096 20 yes" "$(decl $'kind="recipe"\nneeds=["docker","share"]\n[app.uses]\nram_mb=4096\ndisk_gb=20\ngpu=true')"
check_eq "nothing stated" "- - - no" "$(decl 'kind="recipe"')"
check_eq "the recipe header word gpu counts" "- - - yes" "$(decl $'kind="recipe"\nuses=["gpu"]')"
check_eq "zero is not a statement" "- - - no" "$(decl $'kind="recipe"\n[app.uses]\nram_mb=0\ndisk_gb=0')"
check_eq "wrong types cannot be told" "? ? ? no" "$(decl $'kind="recipe"\nneeds=["a\\tb"]\n[app.uses]\nram_mb="lots"\ndisk_gb=-1')"
check_eq "app that is no table" "- - - no" "$(decl $'kind="recipe"\napp="x"')"
check_eq "an unread manifest" "? ? ? ?" "$(decl '')"
finish
