# Loads capabilities/<name>/module.nix for every capability that is switched on (docs/PLAN-modular-core.md step 3).
# A folder without a module.nix, or a capability that is off, adds nothing. options.nix (the options capabilities share) is
# always loaded. Called from configuration.nix.
#
# Capability packages (docs/PLAN-capabilities-repo.md, Q3): `hs pkg install` copies a package with a Nix module to
# <checkout>/vendor/capabilities/<name>/ and writes vendor/capabilities.lock (sha256 of every *.nix file). An enabled name that is not a
# folder of the core but is in the lock is loaded from there, after the hashes are checked: a changed, missing or extra .nix file stops the
# evaluation with the package name. Without vendor/ nothing here changes (the store path of the system stays equal).
{ lib, enabled }:
let
  names = lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./.));
  moduleOf = name: ./. + "/${name}/module.nix";

  vendorDir = ../vendor/capabilities;
  lockFile = ../vendor/capabilities.lock;
  lock = if builtins.pathExists lockFile then builtins.fromTOML (builtins.readFile lockFile) else { };
  vendoredNames = lib.filter (n: enabled n && !(builtins.elem n names)) (lib.attrNames lock);

  # the module of a vendored package, once its folder is what the lock says
  vendoredModule = n:
    let
      dir = vendorDir + "/${n}";
      want = lock.${n}.nix or { };
      have =
        if builtins.pathExists dir then
          lib.attrNames (lib.filterAttrs (f: t: t == "regular" && lib.hasSuffix ".nix" f) (builtins.readDir dir))
        else
          [ ];
      differs = lib.filter (f: !(want ? ${f}) || builtins.hashFile "sha256" (dir + "/${f}") != want.${f}) have;
      missing = lib.filter (f: !(builtins.elem f have)) (lib.attrNames want);
      bad = differs ++ missing;
    in
    if !(builtins.pathExists dir) then
      throw "capability package ${n}: vendor/capabilities/${n} is missing; run: hs pkg install ${n}"
    else if bad != [ ] then
      throw "capability package ${n}: ${lib.concatStringsSep ", " bad} does not match vendor/capabilities.lock; run: hs pkg install ${n}"
    else
      dir + "/module.nix";
in
[ ./options.nix ]
++ lib.concatMap (name: lib.optional (enabled name && builtins.pathExists (moduleOf name)) (moduleOf name)) names
++ map vendoredModule vendoredNames
