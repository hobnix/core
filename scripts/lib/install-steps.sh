# shellcheck shell=bash
# The three things "install a package" is made of, in ONE place (docs/PLAN-app-lifecycle.md Q2, step 8a): fetch the verified release, switch a
# part on, rebuild. Sourced by scripts/apps-change.sh (hs sys apps start install) and scripts/pkg-bundle.sh (hs sys pkg bundle start); each
# function prints through ui.sh (step, ok) and returns non-zero with a `fail` line when it did not work: the caller stops there.
# Needs lib/ui.sh already sourced. Test knobs: HS_PKG (pkg.sh), HS_PART_CHANGE (part-change.sh), HS_REBUILD (rebuild.sh).
_is_here=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)

inst_fetch() {   # inst_fetch <name> [--repo R] [--tag T]: the signed copy into current/ (T: refused when the newest verified tag is another)
  local n=$1; shift
  step "Install $n"
  bash "${HS_PKG:-$_is_here/pkg.sh}" install "$n" "$@" </dev/null || { fail "Installing $n failed: nothing after it was done."; return 1; }
  ok "$n installed"
}

inst_enable() {   # inst_enable <name>: switch a part on in machine.toml (no rebuild yet)
  local n=$1 out
  step "Switch $n on"
  out=$(bash "${HS_PART_CHANGE:-$_is_here/part-change.sh}" start enable "$n" </dev/null 2>&1) || true
  grep -q $'^status\tdone' <<<"$out" || { fail "Switching $n on failed: $(awk -F'\t' '$1=="reason"{print $2}' <<<"$out")"; return 1; }
  ok "$n is switched on"
}

inst_rebuild() {   # inst_rebuild: hs rebuild
  step "Rebuild"
  bash "${HS_REBUILD:-$_is_here/rebuild.sh}" </dev/null || { fail "The rebuild failed: the parts are switched on in machine.toml; hs rebuild tries again."; return 1; }
  ok "Done"
}
