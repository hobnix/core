// Which running job belongs to which button (web/src/jobkey.js).
import { jobKey, jobMatches } from '../web/src/jobkey.js';

let ok = 0, bad = 0;
const check = (name, cond) => { if (cond) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}`); } };

check('key joins area and args', jobKey('routes', ['apply', '--proxy', 'local']) === 'routes apply --proxy local');
check('key of an area alone', jobKey('ct') === 'ct');
check('same plan matches', jobMatches('routes apply', 'routes', ['apply']));
check('other args do not match', !jobMatches('routes apply', 'routes', ['adopt']));
check('apply is not apply --proxy local', !jobMatches('routes apply --proxy local', 'routes', ['apply']));
check('apply --proxy local matches itself', jobMatches('routes apply --proxy local', 'routes', ['apply', '--proxy', 'local']));
check('a prefix of a word is not a match', !jobMatches('routes applyall', 'routes', ['apply']));
check('area alone matches any job of it', jobMatches('routes import', 'routes'));
check('area alone does not match another area', !jobMatches('ct update-all', 'routes'));
check('area prefix is whole word', !jobMatches('routesx apply', 'routes'));
check('empty key never matches', !jobMatches('', 'routes') && !jobMatches(undefined, 'routes', ['apply']));

// Docker app actions that run as a job (hs_job in scripts/docker-app-change.sh): the button that starts one asks rowstate for exactly its own key (#896).
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
const here = fileURLToPath(new URL(".", import.meta.url));
const sh = readFileSync(here + '../scripts/docker-app-change.sh', 'utf8');
const page = readFileSync(here + '../web/src/pages/Workloads.svelte', 'utf8');
const inJob = [...sh.matchAll(/hs_job "docker-app-(\$action|[a-z]+)-/g)].map((m) => m[1]);
check('start, stop and restart are one job template', inJob.includes('$action'));
for (const a of ['start', 'stop', 'restart', 'pull', 'rebuild', 'recreate', 'delete']) {
  check(`docker-app ${a}: the page asks for its job key`, new RegExp(String.raw`rowstate\.pending\('docker-app', \[(a|sel)\.name, '${a}'`).test(page));
  check(`docker-app ${a}: the key matches its plan`, jobMatches(jobKey('docker-app', ['arr', a]), 'docker-app', ['arr', a]) && !jobMatches(jobKey('docker-app', ['arr', a]), 'docker-app', ['other', a]));
}

console.log(`${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
