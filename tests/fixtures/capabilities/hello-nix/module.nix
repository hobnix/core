# Fixture: the smallest module that changes the system, so the matrix can see that it was loaded from vendor/ (a pure evaluation).
{ config, lib, pkgs, hs, ... }:
{
  environment.etc."hs/hello-nix".text = "hello\n";
}
