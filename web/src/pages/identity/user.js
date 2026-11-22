// The user object (docs/PLAN-navigation.md step 5): its address, which accounts are read-only, and the parse of one row of `hs sys users list`. Plain JS so node can test it.
import { P } from '../../paths.js';

// the page of one user: /identity/users/<name>[/<tab>] (D6); Overview has no tab segment
export const userPath = (name, tab = '') => `${P.users}/${encodeURIComponent(name)}${!tab || tab === 'overview' ? '' : `/${encodeURIComponent(tab)}`}`;

// accounts the domain itself owns: they cannot be locked or deleted here, and the page says so (the read-only marker). `sys users list` carries no field that tells a
// local account from a directory one, so only these names are marked.
export const BUILT_IN_USERS = ['administrator', 'guest', 'krbtgt'];
export const builtInUser = (name) => BUILT_IN_USERS.includes(String(name).toLowerCase());

// one row of `users list`: name, full name, enabled|disabled, groups (comma separated); an empty field is "-"
export function userOf(r) {
  return {
    name: r[0], full: r[1] && r[1] !== '-' ? r[1] : '', enabled: r[2] === 'enabled',
    groups: (r[3] ?? '').split(',').map((g) => g.trim()).filter((g) => g && g !== '-'),
  };
}
export const stateOf = (u) => (u.enabled ? 'active' : 'locked');
