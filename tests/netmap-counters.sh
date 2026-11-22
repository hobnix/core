#!/usr/bin/env bash
# hs sys netmap counters: rows id, rx, tx from a fake /sys/class/net, a fake ip and a fake incus. No root.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
if ! have jq; then skip "jq is not installed"; finish; exit 0; fi
export HS_LANG=en HS_PLAIN=1

echo "-- registry row"
check "sys netmap counters row" grep -q "^sys.sys netmap counters.netmap-counters.sh.-." "$SCRIPTS/lib/registry.tsv"

net=$WORK/net
mkdir -p "$net/eno1/statistics" "$net/eno1/device" "$net/br0/brif" "$net/br0/statistics" "$net/br-iot/statistics"
ln -s ../../eno1 "$net/br0/brif/eno1" 2>/dev/null || mkdir -p "$net/br0/brif/eno1"
printf 1000 >"$net/eno1/statistics/rx_bytes"; printf 2000 >"$net/eno1/statistics/tx_bytes"
printf 30 >"$net/br0/statistics/rx_bytes"; printf 40 >"$net/br0/statistics/tx_bytes"
printf 5 >"$net/br-iot/statistics/rx_bytes"          # tx unreadable: the whole row is `-`
printf '#!/bin/sh\necho "default via 10.0.0.1 dev br0"\n' >"$WORK/ip"; chmod +x "$WORK/ip"
cat >"$WORK/incus" <<'EOF'
#!/bin/sh
cat <<'JSON'
[{"name":"web","state":{"network":{"lo":{"counters":{"bytes_received":9,"bytes_sent":9}},"eth0":{"counters":{"bytes_received":100,"bytes_sent":200}},"eth1":{"counters":{"bytes_received":1,"bytes_sent":2}}}}},
 {"name":"off","state":{"network":null}}]
JSON
EOF
chmod +x "$WORK/incus"
export HS_NET_DIR=$net HS_IP=$WORK/ip HS_INCUS=$WORK/incus

out=$(bash "$SCRIPTS/netmap-counters.sh")
check_eq "wan is the physical port under the bridge" "$(printf 'wan\t1000\t2000')" "$(grep '^wan' <<<"$out")"
check_eq "host is the default interface" "$(printf 'host\t30\t40')" "$(grep '^host' <<<"$out")"
check_eq "a bridge with an unreadable counter is -" "$(printf 'bridge:br-iot\t-\t-')" "$(grep '^bridge:br-iot' <<<"$out")"
check_eq "an instance sums its NICs without lo" "$(printf 'instance:web\t101\t202')" "$(grep '^instance:web' <<<"$out")"
check_eq "an instance without network state is -" "$(printf 'instance:off\t-\t-')" "$(grep '^instance:off' <<<"$out")"

echo "-- no incus"
export HS_INCUS=$WORK/none
check_eq "no instance rows without incus" "0" "$(bash "$SCRIPTS/netmap-counters.sh" | grep -c '^instance:')"
finish
