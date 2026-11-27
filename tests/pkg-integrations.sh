#!/usr/bin/env bash
# {host} in the api_url of [integrations.<name>] (hobnix/core#1322): the core fills it with the address Incus reports for the own network
# interface of the instance that the service record names. It decides where an API key is sent, so every doubt must give "-". A fake incus
# (HS_INCUS) prints fixed `incus list --format json` output and records its calls; lib/pkg_integrations.py rows() reads it. No root.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

cat > "$WORK/fixtures.py" <<'PY'
import json, os, sys

def a(address, family="inet", scope="global"):
    return {"address": address, "family": family, "scope": scope, "netmask": "24"}

def net(mac, *addresses):
    return {"hwaddr": mac, "addresses": list(addresses), "type": "broadcast", "state": "up"}

def inst(name, devices, network, status="Running", macs=None):
    return {"name": name, "status": status, "expanded_devices": devices,
            "expanded_config": {"volatile.%s.hwaddr" % k: v for k, v in (macs or {}).items()},
            "state": {"network": network}}

NIC = {"type": "nic", "nictype": "bridged", "parent": "br0", "name": "eth0"}
ROOT = {"type": "disk", "path": "/", "pool": "default"}
M0, M1, MX = "00:16:3e:00:00:01", "00:16:3e:00:00:02", "02:42:aa:bb:cc:dd"
LO = {"hwaddr": "", "addresses": [a("127.0.0.1", scope="local")], "type": "loopback"}
LL = a("fe80::216:3eff:fe00:1", "inet6", "link")
own = {"lo": LO, "eth0": net(M0, a("192.168.1.20"), a("2001:db8::20", "inet6"), LL)}
one = {"eth0": NIC, "root": ROOT}

def only(network, devices=one, macs={"eth0": M0}, **kw):
    return [inst("jellyfin", devices, network, macs=macs, **kw)]

# the docker instance: the Docker bridges come first in the listing, one of them even with the MAC of the NIC
bridges = {"br-0a1b2c3d4e5f": net(MX, a("172.18.0.1")), "br-ffff00001111": net("02:42:00:00:00:02", a("172.19.0.1")),
           "br-same": net(M0, a("172.20.0.1")), "docker0": net("02:42:00:00:00:03", a("172.17.0.1")),
           "veth9a8b7c": net("02:42:00:00:00:04"), "cni0": net(MX, a("10.88.0.1")), "lo": LO, "eth0": net(M0, a("192.168.1.30"))}
two = {"eth0": NIC, "link": {"type": "nic", "network": "hs-internal", "name": "eth1"}, "root": ROOT}
twonet = {"eth1": net(M1, a("10.99.0.2")), "eth0": net(M0, a("192.168.1.20"))}

F = {
    "own": only(own),
    "docker": only(bridges),
    "only-bridges": only({k: v for k, v in bridges.items() if k != "eth0"}),
    "two": only(twonet, two, {"eth0": M0, "link": M1}),
    "two-no-eth0": only(twonet, {"a": NIC, "b": two["link"]}, {"a": M0, "b": M1}),
    "two-eth0-down": only({"eth1": twonet["eth1"], "eth0": net(M0)}, two, {"eth0": M0, "link": M1}),
    "vm": only({"enp5s0": net(M0.upper(), a("192.168.1.40"))}),
    "device-hwaddr": only(own, {"nic1": dict(NIC, hwaddr=M0)}, {}),
    "no-mac": only(own, macs={}),
    "no-nic": only(own, {"root": ROOT}),
    "other-mac": only({"eth0": net(MX, a("192.168.1.20"))}),
    "same-mac-twice": only({"eth0": net(M0, a("192.168.1.20")), "eth0.5": net(M0, a("192.168.5.20"))}),
    "two-addresses": only({"eth0": net(M0, a("192.168.1.20"), a("192.168.1.21"))}),
    "no-address": only({"eth0": net(M0, LL)}),
    "v6-only": only({"eth0": net(M0, a("2001:db8::20", "inet6"), LL)}),
    "two-v6": only({"eth0": net(M0, a("2001:db8::20", "inet6"), a("fd00::20", "inet6"))}),
    "junk-address": only({"eth0": net(M0, a("evil.example.org"), a("192.168.1.20/24"), a("fd00::1%eth0", "inet6"))}),
    "special-address": only({"eth0": net(M0, a("127.0.0.1"), a("0.0.0.0"), a("169.254.1.1"), a("224.0.0.1"), a("::1", "inet6"))}),
    "stopped": only(own, status="Stopped"),
    "no-state": [dict(only(own)[0], state=None)],
    "missing": [inst("radarr", one, own, macs={"eth0": M0})],
    "wrong-shape": [None, "x", {"name": "jellyfin", "status": "Running", "expanded_devices": [], "state": {"network": []}}],
}
for k, v in F.items():
    with open(os.path.join(sys.argv[1], k + ".json"), "w") as fh:
        json.dump(v, fh)
with open(os.path.join(sys.argv[1], "not-json.json"), "w") as fh:
    fh.write("Error: not authorized\n")
with open(os.path.join(sys.argv[1], "object.json"), "w") as fh:
    fh.write('{"name": "jellyfin"}\n')
PY
mkdir -p "$WORK/fx" "$WORK/services.d"
python3 -I "$WORK/fixtures.py" "$WORK/fx"

cat > "$WORK/incus" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_CALLS"
case "$FAKE_FIXTURE" in
  hang) exec sleep 30 ;;
  fails) cat "$FAKE_DIR/own.json"; exit 1 ;;
esac
cat "$FAKE_DIR/$FAKE_FIXTURE.json"
SH
chmod +x "$WORK/incus"
export HS_INCUS=$WORK/incus HS_INCUS_TIMEOUT=2 FAKE_CALLS=$WORK/calls FAKE_DIR=$WORK/fx

cat > "$WORK/rows.py" <<'PY'
# rows.py <lib> <services dir> <package=api_url>...: "api_url ..." of the rows on one line, then " !" and the unresolved ones
import importlib.util, sys
s = importlib.util.spec_from_file_location("p", sys.argv[1] + "/pkg_integrations.py"); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
ms, on = [], set()
for arg in sys.argv[3:]:
    name, url = arg.split("=", 1)
    ms.append(("", {"name": name, "kind": "recipe", "integrations": {"media": {"api_url": url}}})); on.add(name)
miss = []
print(" ".join(r[3] for r in m.rows(ms, on, None, sys.argv[2], miss)) + (" !" + ",".join(miss) if miss else ""))
PY
rec() {   # rec <package> <toml line>...: its service record
  local n=$1; shift; printf '%s\n' "$@" > "$WORK/services.d/$n.toml"
}
ALL=$WORK/all-rows
run() {   # run <fixture> [package=url]...: the rows, with the calls of this run alone in $FAKE_CALLS
  local fx=$1 out; shift
  [ $# -gt 0 ] || set -- 'jellyfin=http://{host}:{port}'
  : > "$FAKE_CALLS"
  out=$(FAKE_FIXTURE=$fx python3 -I "$WORK/rows.py" "$SCRIPTS/lib" "$WORK/services.d" "$@")
  printf '%s\n' "${out%% !*}" >> "$ALL"
  printf '%s' "$out"
}
calls() { wc -l < "$FAKE_CALLS" | tr -d ' '; }
no='- !jellyfin/media'
rec jellyfin 'name = "jellyfin"' 'container = "jellyfin"' 'port = 8096'

echo "-- the address of the instance's own interface"
check_eq "own instance: IPv4 of its NIC" "http://192.168.1.20:8096" "$(run own)"
check_eq "one Incus query, nothing but the list" "list --format json" "$(cat "$FAKE_CALLS")"
rec jellyfin 'name = "jellyfin"' 'container = "jellyfin"' 'port = 8080'
check_eq "docker instance with many bridges: the NIC, never a bridge" "http://192.168.1.30:8080" "$(run docker)"
check_eq "only bridges have an address: unresolved" "$no" "$(run only-bridges)"
rec jellyfin 'name = "jellyfin"' 'container = "jellyfin"' 'port = 8096'
check_eq "two NICs: the device eth0 of the core's profiles" "http://192.168.1.20:8096" "$(run two)"
check_eq "two NICs, none is the device eth0: unresolved" "$no" "$(run two-no-eth0)"
check_eq "two NICs, eth0 without an address: the other is not taken" "$no" "$(run two-eth0-down)"
check_eq "a VM (enp5s0) is found by the MAC of its device" "http://192.168.1.40:8096" "$(run vm)"
check_eq "a MAC set on the device itself" "http://192.168.1.20:8096" "$(run device-hwaddr)"
check_eq "only IPv6: in brackets" "http://[2001:db8::20]:8096" "$(run v6-only)"
check_eq "an address without a port in the URL" "http://192.168.1.20/api" "$(run own 'jellyfin=http://{host}/api')"

echo "-- every doubt is unresolved"
for fx in no-mac no-nic other-mac same-mac-twice two-addresses two-v6 no-address junk-address special-address stopped no-state missing wrong-shape \
          not-json object fails; do
  check_eq "$fx: -" "$no" "$(run "$fx")"
done
start=$SECONDS
check_eq "Incus hangs: -" "$no" "$(HS_INCUS_TIMEOUT=1 run hang)"
check "the timeout ends the wait" test $((SECONDS - start)) -lt 15
check_eq "no incus program: -" "$no" "$(HS_INCUS=$WORK/no-such-incus run own)"

echo "-- the service record"
for bad in '--all-projects' '-f' 'remote:jellyfin' 'remote:' '../jellyfin' 'a/b' 'jelly fin' 'jellyfin?recursion=1' '1jellyfin' 'jellyfin-' \
           'jellyfin\n' "$(printf 'a%.0s' $(seq 1 64))"; do
  rec jellyfin 'name = "jellyfin"' "container = \"$bad\"" 'port = 8096'
  check_eq "bad container name '${bad:0:30}': -, Incus is not asked" "$no 0" "$(run own) $(calls)"
done
rec jellyfin 'name = "jellyfin"' 'container = 7' 'port = 8096'
check_eq "a container that is not text: -" "$no 0" "$(run own) $(calls)"
rec jellyfin 'name = "jellyfin"' 'host = "192.168.1.99"' 'port = 8096'
check_eq "a record with a host and no container: -, its text is not used" "$no 0" "$(run own) $(calls)"
rec jellyfin 'name = "jellyfin"' 'container = "jellyfin"'
check_eq "no port: -, Incus is not asked" "$no 0" "$(run own) $(calls)"
rm "$WORK/services.d/jellyfin.toml"
check_eq "no record: -, Incus is not asked" "$no 0" "$(run own) $(calls)"
printf 'name = "\xff"\n' > "$WORK/services.d/jellyfin.toml"
check_eq "a record that is not UTF-8: -" "$no" "$(run own)"

echo "-- URLs"
rec jellyfin 'name = "jellyfin"' 'container = "jellyfin"' 'port = 8096'
check_eq "without {host}: unchanged, Incus is not asked" "http://fixed.example.org:8096/x 0" "$(run own 'jellyfin=http://fixed.example.org:{port}/x') $(calls)"
check_eq "a fixed URL stays as it is" "http://10.0.0.1:7878 0" "$(run own 'jellyfin=http://10.0.0.1:7878') $(calls)"
for u in 'http://{host}.example.org:{port}' 'http://x{host}:{port}' 'http://{host}-x' 'http://example.org/{host}' 'http://{host}:{port}/?u={host}'; do
  check_eq "{host} that is not the whole host, or twice: - ($u)" "$no 0" "$(run own "jellyfin=$u") $(calls)"
done
rec radarr 'name = "radarr"' 'container = "jellyfin"' 'port = 7878'
rec sonarr 'name = "sonarr"' 'container = "gone"' 'port = 8989'
check_eq "several rows that need {host}: one Incus query" "http://192.168.1.20:8096 http://192.168.1.20:7878 - !sonarr/media 1" \
  "$(run own 'jellyfin=http://{host}:{port}' 'radarr=http://{host}:{port}' 'sonarr=http://{host}:{port}') $(calls)"
check_eq "a failing query is not repeated for the next row" "- - !jellyfin/media,radarr/media 1" \
  "$(run fails 'jellyfin=http://{host}:{port}' 'radarr=http://{host}:{port}') $(calls)"

check "no row of any run above holds {host}" bash -c '[ "$(wc -l < "$1")" -gt 30 ] && ! grep -qF "{host}" "$1"' _ "$ALL"

finish
