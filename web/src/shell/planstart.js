// What the plan dialog asks to be typed and what it sends with Start. Pure functions, no Svelte.
import { offersRebuild } from './effect.js';
import { boundArgs } from './pkgbind.js';

// these start a job that rebuilds the server itself: nothing is saved and waiting, so no "Rebuild now" and the dialog closes
const SELF_REBUILD = ['system', 'blueprint', 'pkg/bundle'];
export const staysForRebuild = (area, steps) => !SELF_REBUILD.includes(area) && offersRebuild(steps);

// the names a person has to type, one field each. Only a blueprint plan may ask for several (confirm_names, one per confirm_name line)
export const typedNames = (area, p) => (area === 'blueprint' && p?.confirm_names?.length ? p.confirm_names : p?.confirm_name ? [p.confirm_name] : []);
export const allTyped = (names, typed) => names.every((n, i) => typed[i] === n);

// the args and the confirm word of the start. What is sent as a name is what was TYPED, never the plan's own word. A blueprint start also
// carries the tag of the plan that was shown (a changed blueprint is refused) and one --confirm for every further name.
export function startRequest(area, args, p, typed) {
  const n = typedNames(area, p).length;
  const confirm = n ? typed[0] ?? '' : '';
  if (area !== 'blueprint') return { args: boundArgs(area, args, p), confirm };     // a package update also carries --tag and --seen
  const more = typed.slice(1, n).flatMap((t) => ['--confirm', t]);
  return { args: [...args, ...(p?.tag ? ['--tag', p.tag] : []), ...more], confirm };
}
