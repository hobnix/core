// The checks of `hs sys docker health` (rows id state fix detail reason): what the Apps & VMs list, the tree and the capability page say when
// Docker is on but something it needs is missing (the share apps, its mount). One place, so a banner and a dimmed tree entry never disagree.
import { P } from '../../paths.js';

// the rows that are not fine: state warn or fail ("off" is a check that does not apply yet)
export function problems(list) {
  return (Array.isArray(list) ? list : [])
    .filter((r) => Array.isArray(r) && r.length >= 5 && (r[1] === 'fail' || r[1] === 'warn'))
    .map((r) => ({ id: r[0], state: r[1], reason: r[4] }));
}

// the tree: a dot on Apps & VMs (the list the Docker apps are in) and the rows that need Docker dimmed (they would only fail) while a check fails;
// { path: { dot, title, dim } }
export function treeMeta(list, children = []) {
  const p = problems(list);
  if (!p.length) return {};
  const title = p.map((x) => x.reason).join(' ');
  const m = { [P.appsGroup]: { dot: p.some((x) => x.state === 'fail') ? 'bad' : 'warn', title } };
  for (const c of children) m[c] = { dim: true, title };
  return m;
}

// the rows of the tree that need Docker (nav.js: capability docker), so a new one is dimmed too without a change here
export function dockerChildren(items) {
  const all = (it) => [...(it.capability === 'docker' && it.path ? [it.path] : []), ...(it.children ?? []).flatMap(all)];
  return (items ?? []).flatMap(all);
}
