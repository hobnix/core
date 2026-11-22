#!/usr/bin/env bash
# help: the network map graph: the way out, this server, its bridges, the instances and their services, one row per node
# help.de: der Graph der Netzwerkkarte: der Weg nach draußen, dieser Server, seine Brücken, die Instanzen und ihre Dienste, eine Zeile je Knoten
# args: -
# hs sys netmap: machine-readable, plain, tab separated rows `id  kind  parent  label  state  rx_bytes  tx_bytes` (docs/PLAN-network-map.md, part 1;
# the shape web/src/netmap/layout.js reads). An empty field is `-`. A source that cannot be read gives `-`, never an old value. Read only.
#   wan                 the physical port under the default route (as `hs sys deck` finds it); state = operstate of the port
#   gateway             the next hop of the default route (label = its address); its own counters are unknown: `-`
#   host                this server (label = host name, parent gateway); counters of the default interface
#   bridge:<name>       every br* interface in /sys/class/net, parent host
#   instance:<name>     every Incus instance, parent = the bridge of its first NIC (else the default bridge, else host); state = Incus status, lower case
#   service:<name>      every described service (hs services), parent = its instance when the target is one, else host. No address is given: admin
#                       pages (ADMIN_TARGETS) are drawn as nodes, never offered as an address.
# The ids and the counters are the contract with `hs sys netmap counters` (scripts/netmap-counters.sh): the same ids, the same totals.
#   hs sys netmap topology   the same rows with `-` counters: the live-state topic `netmap` reads this, so only a change of the topology is a change.
# Test knobs: HS_NET_DIR, HS_IP, HS_INCUS, HS_HOSTNAME, HS_SERVICES_DIR.
set -uo pipefail
here=$(dirname "$0")
netdir=${HS_NET_DIR:-/sys/class/net}

# clean <text>: no tab or newline inside a field; empty becomes `-`
clean() { local v=${1//$'\t'/ }; v=${v//$'\n'/ }; printf '%s' "${v:--}"; }
# row <id> <kind> <parent> <label> <state> <counters "rx<TAB>tx">; with `topology` the counters are always `-` (the document then changes only with the topology)
topo=0
[ "${1:-}" = topology ] && topo=1
row() {
  local c=${6:-$'-\t-'}
  [ "$topo" = 1 ] && c=$'-\t-'
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(clean "$1")" "$2" "$(clean "$3")" "$(clean "$4")" "$(clean "$5")" "$c"
}
# stats <iface>: "rx<TAB>tx" or "-<TAB>-"
stats() {
  local rx tx
  if [ -n "$1" ] && rx=$(cat "$netdir/$1/statistics/rx_bytes" 2>/dev/null) && tx=$(cat "$netdir/$1/statistics/tx_bytes" 2>/dev/null) \
    && [[ $rx =~ ^[0-9]+$ ]] && [[ $tx =~ ^[0-9]+$ ]]; then printf '%s\t%s' "$rx" "$tx"; else printf -- '-\t-'; fi
}
oper() { local s; if [ -n "$1" ] && s=$(cat "$netdir/$1/operstate" 2>/dev/null) && [ -n "$s" ]; then printf '%s' "$s"; else printf -- '-'; fi; }

route=$(${HS_IP:-ip} route show default 2>/dev/null | head -n 1)
iface=$(awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }' <<<"$route")
gw=$(awk '{ for (i = 1; i < NF; i++) if ($i == "via") { print $(i + 1); exit } }' <<<"$route")
port=$iface
if [ -n "$iface" ] && [ -d "$netdir/$iface/brif" ]; then
  for p in "$netdir/$iface"/brif/*; do
    if [ -e "$netdir/${p##*/}/device" ]; then port=${p##*/}; break; fi
  done
fi

row wan wan - "${port:-wan}" "$(oper "$port")" "$(stats "$port")"
hostparent=wan
if [ -n "$gw" ]; then row gateway gateway wan "$gw" -; hostparent=gateway; fi
row host host "$hostparent" "${HS_HOSTNAME:-$(hostname 2>/dev/null)}" "$(oper "$iface")" "$(stats "$iface")"

bridges=" "
for b in "$netdir"/br*; do
  [ -e "$b" ] || continue
  n=${b##*/}; bridges="$bridges$n "
  row "bridge:$n" bridge host "$n" "$(oper "$n")" "$(stats "$n")"
done
defbr=
case "$bridges" in *" $iface "*) defbr=$iface ;; esac

# Instances: one query for all of them (recursion=2 carries the state and the NIC counters).
instances=" "
if out=$(${HS_INCUS:-incus} query "/1.0/instances?recursion=2" 2>/dev/null) && [ -n "$out" ]; then
  while IFS=$'\t' read -r name status nic rx tx; do
    [ -n "$name" ] || continue
    instances="$instances$name "
    par=host
    case "$bridges" in *" $nic "*) par=bridge:$nic ;; *) [ -n "$defbr" ] && par=bridge:$defbr ;; esac
    row "instance:$name" instance "$par" "$name" "$status" "$rx"$'\t'"$tx"
  done < <(jq -r '.[] | (.state.network // null) as $n | [ .name, ((.status // "") | ascii_downcase),
      ([(.expanded_devices // {}) | to_entries[] | select(.value.type == "nic") | (.value.network // .value.parent // empty)] | first // "-"),
      (if $n == null then "-" else ([$n | to_entries[] | select(.key != "lo") | .value.counters.bytes_received // 0] | add // 0 | tostring) end),
      (if $n == null then "-" else ([$n | to_entries[] | select(.key != "lo") | .value.counters.bytes_sent // 0] | add // 0 | tostring) end)
    ] | @tsv' <<<"$out" 2>/dev/null)
fi

# Services: name, title, target (<instance>:<port> or <host>:<port>); no address and no exposure is passed on.
if svc=$(bash "$here/services.sh" list --plain 2>/dev/null </dev/null); then
  while IFS=$'\t' read -r name title target _; do
    [ -n "$name" ] || continue
    ct=${target%:*}
    case "$instances" in *" $ct "*) par=instance:$ct ;; *) par=host ;; esac
    row "service:$name" service "$par" "${title:-$name}" -
  done <<<"$svc"
fi
exit 0
