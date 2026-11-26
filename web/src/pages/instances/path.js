// The address of the page of one instance: /apps/instance/<name>[/<tab>] (D6); Overview has no tab segment. The kind segment keeps it apart from a Docker app of the
// same name (/apps/docker-app/<name>) and from the other pages under /apps. Plain JS so that node can test it.
import { P } from '../../paths.js';
export const instancePath = (name, tab = '') => `${P.appsGroup}/instance/${encodeURIComponent(name)}${!tab || tab === 'overview' ? '' : `/${encodeURIComponent(tab)}`}`;
