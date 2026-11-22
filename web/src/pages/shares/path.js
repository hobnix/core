// The address of the page of one share: /storage/shares/<name>[/<tab>] (D6); Overview has no tab segment. Plain JS so that node can test it.
import { P } from '../../paths.js';
export const sharePath = (name, tab = '') => `${P.shares}/${encodeURIComponent(name)}${!tab || tab === 'overview' ? '' : `/${encodeURIComponent(tab)}`}`;
