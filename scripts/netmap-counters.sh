#!/usr/bin/env bash
# help: byte counters of the network map nodes (wan, host, bridges, instances), one sample
# help.de: Byte-Zähler der Knoten der Netzwerkkarte (WAN, Host, Brücken, Instanzen), eine Messung
# args: -
# hs sys netmap counters: machine-readable, plain, tab separated rows `id  rx_bytes  tx_bytes` (docs/PLAN-network-map.md, part 2). Totals since the
# boot, not rates: the client takes two readings and divides. A source that cannot be read gives `-` in both columns, never an old value.
#   wan            the physical port under the default interface (as `hs sys deck` finds it)
#   host           the default interface itself (br0 or the NIC)
#   bridge:<name>  every br* interface in /sys/class/net
#   instance:<n>   the sum of the NICs of an instance (Incus state.network, without lo); rx = received by the instance; `-` while it has no network state
# Used by the web interface counters stream (one sample per tick for all open pages, only while a page is open). One `incus query`, no per-instance call.
# Test knobs: HS_NET_DIR, HS_IP, HS_INCUS.
set -uo pipefail
netdir=${HS_NET_DIR:-/sys/class/net}

row() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }
# nic_row <id> <iface>: a row with the totals of the interface, `-` when they cannot be read
nic_row() {
  local id=$1 dev=$2 rx tx
  if [ -n "$dev" ] && rx=$(cat "$netdir/$dev/statistics/rx_bytes" 2>/dev/null) && tx=$(cat "$netdir/$dev/statistics/tx_bytes" 2>/dev/null) \
    && [[ $rx =~ ^[0-9]+$ ]] && [[ $tx =~ ^[0-9]+$ ]]; then row "$id" "$rx" "$tx"; else row "$id" - -; fi
}

iface=$(${HS_IP:-ip} route show default 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
port=$iface
if [ -n "$iface" ] && [ -d "$netdir/$iface/brif" ]; then
  for p in "$netdir/$iface"/brif/*; do
    if [ -e "$netdir/${p##*/}/device" ]; then port=${p##*/}; break; fi
  done
fi
nic_row wan "$port"
nic_row host "$iface"
for b in "$netdir"/br*; do
  [ -e "$b" ] || continue
  nic_row "bridge:${b##*/}" "${b##*/}"
done

# Instances: one query for all of them (recursion=2 carries the state).
if out=$(${HS_INCUS:-incus} query "/1.0/instances?recursion=2" 2>/dev/null) && [ -n "$out" ]; then
  jq -r '.[] | (.state.network // null) as $n | [ "instance:" + .name,
      (if $n == null then "-" else ([$n | to_entries[] | select(.key != "lo") | .value.counters.bytes_received // 0] | add // 0 | tostring) end),
      (if $n == null then "-" else ([$n | to_entries[] | select(.key != "lo") | .value.counters.bytes_sent // 0] | add // 0 | tostring) end)
    ] | @tsv' <<<"$out" 2>/dev/null
fi
exit 0
