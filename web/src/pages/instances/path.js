// The address of the page of one instance: /instances/ct/<name>[/<tab>] (D6); Overview has no tab segment. The kind segment `ct` keeps it apart from the other pages
// under /instances (apps, docker, iso, services): an instance may be called "docker". Plain JS so that node can test it.
import { P } from '../../paths.js';
export const instancePath = (name, tab = '') => `${P.instances}/ct/${encodeURIComponent(name)}${!tab || tab === 'overview' ? '' : `/${encodeURIComponent(tab)}`}`;
