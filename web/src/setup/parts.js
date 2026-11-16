// The Optional parts step (docs/PLAN-capabilities-repo.md step 14). Rows of hs sys pkg capabilities:
// name, repo, available, installed (- = none), state, requires (a,b or -), type, title.
export const capRows = (rs) => rs.map((r) => ({
  name: r[0], installed: !!r[3] && r[3] !== '-',
  requires: r[5] && r[5] !== '-' ? r[5].split(',') : [],
  title: r[7] && r[7] !== '-' ? r[7] : r[0],
}));
// the argument of the pkg/bundle plan: the ticked packages that are not installed, as one comma list ('' = nothing to do)
export const bundleArg = (caps, picked) => caps.filter((c) => picked[c.name] && !c.installed).map((c) => c.name).join(',');
