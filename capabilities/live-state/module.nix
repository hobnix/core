# The capability "live-state" (capabilities/live-state/capability.toml, NOTES.md): the collector hs-live, which keeps the live topics in the state
# database (ADR 0026). No Redis, no socket, no group, no setting. Loaded by capabilities/default.nix while the capability is on: the web interface
# on a homeserver turns it on (configuration.nix), or `live-state` in `capabilities`.
{ config, lib, pkgs, hs, ... }:

{
  # The collector: runs `hs sys <topic>` on an interval and keeps the changed output in state.db (scripts/live-collect.py), plus one heartbeat row.
  # Not tested on hardware yet.
  systemd.services.hs-live = {
    description = "Live state collector (hs sys ... into the state database)";
    wantedBy = [ "multi-user.target" ];
    path = [ "/run/current-system/sw" pkgs.python3 ];
    environment.HS_CALLER = "ui";
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${hs.scripts}/live-collect.py";
      Restart = "always";
      RestartSec = 5;
    };
    onFailure = hs.notifyFailure;
  };
}
