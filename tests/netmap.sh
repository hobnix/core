#!/usr/bin/env bash
# hs sys netmap (scripts/netmap.sh, #872): the graph rows from a fake /sys/class/net, a fake ip, a fake incus and a fake services dir. No root.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! have jq; then skip "jq is not installed"; finish; exit 0; fi
if ! have python3; then skip "python3 is not installed"; finish; exit 0; fi
export HS_LANG=en HS_PLAIN=1

echo "-- registry rows"
check "sys netmap row" grep -q "^sys.sys netmap.netmap.sh.-." "$SCRIPTS/lib/registry.tsv"
check "sys netmap topology row" grep -q "^sys.sys netmap topology.netmap.sh.topology." "$SCRIPTS/lib/registry.tsv"
check "the netmap topic reads the topology" grep -q "^netmap.netmap topology." "$SCRIPTS/lib/live-topics.tsv"

net=$WORK/net
mkdir -p "$net/eno1/statistics" "$net/eno1/device" "$net/br0/brif" "$net/br0/statistics" "$net/br-iot/statistics"
mkdir -p "$net/br0/brif/eno1"
printf 1000 >"$net/eno1/statistics/rx_bytes"; printf 2000 >"$net/eno1/statistics/tx_bytes"; printf up >"$net/eno1/operstate"
printf 30 >"$net/br0/statistics/rx_bytes"; printf 40 >"$net/br0/statistics/tx_bytes"; printf up >"$net/br0/operstate"
printf 5 >"$net/br-iot/statistics/rx_bytes"          # tx unreadable: the counters are `-`
printf '#!/bin/sh\necho "default via 10.0.0.1 dev br0 proto dhcp"\n' >"$WORK/ip"; chmod +x "$WORK/ip"
cat >"$WORK/incus" <<'EOF'
#!/bin/sh
cat <<'JSON'
[{"name":"web","status":"Running","expanded_devices":{"eth0":{"type":"nic","network":"br-iot"}},"state":{"network":{"lo":{"counters":{"bytes_received":9,"bytes_sent":9}},"eth0":{"counters":{"bytes_received":100,"bytes_sent":200}},"eth1":{"counters":{"bytes_received":1,"bytes_sent":2}}}}},
 {"name":"off","status":"Stopped","expanded_devices":{"eth0":{"type":"nic","parent":"nowhere"}},"state":{"network":null}}]
JSON
EOF
chmod +x "$WORK/incus"
sd=$WORK/services.d; mkdir -p "$sd"
printf 'name = "web"\ntitle = "Web site"\ncontainer = "web"\nport = 80\n' >"$sd/web.toml"
printf 'name = "nas"\ntitle = "NAS"\nhost = "10.0.0.9"\nport = 5000\n' >"$sd/nas.toml"
export HS_NET_DIR=$net HS_IP=$WORK/ip HS_INCUS=$WORK/incus HS_HOSTNAME=srv HS_SERVICES_DIR=$sd HS_STATE_DIR=$WORK/state

out=$(bash "$SCRIPTS/netmap.sh")
g() { grep "^$1"$'\t' <<<"$out"; }
t() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$@"; }
check_eq "wan is the physical port under the bridge" "$(t wan wan - eno1 up 1000 2000)" "$(g wan)"
check_eq "gateway is the next hop, no counters" "$(t gateway gateway wan 10.0.0.1 - - -)" "$(g gateway)"
check_eq "host hangs under the gateway" "$(t host host gateway srv up 30 40)" "$(g host)"
check_eq "a bridge with an unreadable counter is -" "$(t bridge:br-iot bridge host br-iot - - -)" "$(g bridge:br-iot)"
check_eq "an instance sits under the bridge of its NIC" "$(t instance:web instance bridge:br-iot web running 101 202)" "$(g instance:web)"
check_eq "an instance on an unknown bridge falls back to the default bridge" "$(t instance:off instance bridge:br0 off stopped - -)" "$(g instance:off)"
check_eq "a service sits under its instance" "$(t service:web service instance:web 'Web site' - - -)" "$(g service:web)"
check_eq "a service on another host sits under the host" "$(t service:nas service host NAS - - -)" "$(g service:nas)"
check_eq "every row has 7 fields" "0" "$(awk -F'\t' 'NF != 7' <<<"$out" | wc -l | tr -d ' ')"
check_eq "no empty field" "0" "$(awk -F'\t' '{ for (i = 1; i <= NF; i++) if ($i == "") n++ } END { print n + 0 }' <<<"$out")"

echo "-- the ids are the ones of the counters stream"
cids=$(bash "$SCRIPTS/netmap-counters.sh" | cut -f1 | sort)
gids=$(cut -f1 <<<"$out" | grep -E '^(wan|host|bridge:|instance:)' | sort)
check_eq "counter ids are graph ids" "$cids" "$gids"
check_eq "the counters are the same" "$(bash "$SCRIPTS/netmap-counters.sh" | sort)" "$(grep -E '^(wan|host|bridge:|instance:)' <<<"$out" | cut -f1,6,7 | sort)"

echo "-- topology: no counters"
top=$(bash "$SCRIPTS/netmap.sh" topology)
check_eq "same ids" "$(cut -f1 <<<"$out")" "$(cut -f1 <<<"$top")"
check_eq "counters are -" "0" "$(awk -F'\t' '$6 != "-" || $7 != "-"' <<<"$top" | wc -l | tr -d ' ')"

echo "-- no incus, no default route"
export HS_INCUS=$WORK/none
printf '#!/bin/sh\nexit 0\n' >"$WORK/ip2"; chmod +x "$WORK/ip2"; export HS_IP=$WORK/ip2
o2=$(bash "$SCRIPTS/netmap.sh")
check_eq "no instance rows without incus" "0" "$(grep -c '^instance:' <<<"$o2")"
check_eq "no gateway without a default route, the host hangs under wan" "$(t host host wan srv - - -)" "$(grep '^host'$'\t' <<<"$o2")"
finish
