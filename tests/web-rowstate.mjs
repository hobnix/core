// The pending state of a row from job events and job records (web/src/rowstate.js), run with node.
import { fromRecords, applyEvents, isPending, failureOf, jobEventState } from '../web/src/rowstate.js';
import { parseRecord } from '../web/src/jobrecords.js';
let bad = 0;
const check = (n, ok) => { if (!ok) { bad++; console.log('FAIL: ' + n); } };
const J1 = '20261119-100000-app-remove-nextcloud-abcd', J2 = '20261119-110000-app-remove-nextcloud-wxyz';
const rec = (id, state, key, exit = '-', desc = 'hs apps remove nextcloud') => parseRecord([id, 's', desc, state, '-', '-', '-', exit, '-', '-', '-', '-', '-', '-', key]);
const ev = (id, kind, subject, payload) => ({ id, source: 'job', kind, subject, payload });

// the record has the key: parseRecord reads the 15th column, "-" and a missing column are none
check('record key read', rec(J1, 'running', 'apps remove nextcloud').key === 'apps remove nextcloud');
check('record key "-" and no column', rec(J1, 'running', '-').key === null && parseRecord(['i', '-', '-', 'ok']).key === null);

// a job started in a terminal: the record is running with a key; the page has no task of its own
{
  const jobs = fromRecords([rec(J1, 'running', 'apps remove nextcloud')]);
  check('terminal job: row is pending', isPending(jobs, [], 'apps', ['remove', 'nextcloud']));
  check('terminal job: another row is not', !isPending(jobs, [], 'apps', ['remove', 'jellyfin']));
  check('terminal job: area without args matches', isPending(jobs, [], 'apps'));
}
// the event arrives before the next read of the records
{
  const jobs = applyEvents(new Map(), [ev(5, 'running', J1, { key: 'apps remove nextcloud' })], 0);
  check('event alone makes the row pending', isPending(jobs, [], 'apps', ['remove', 'nextcloud']));
  const done = applyEvents(jobs, [ev(6, 'ok', J1, { key: 'apps remove nextcloud' })], 0);
  check('job.ok clears it', !isPending(done, [], 'apps', ['remove', 'nextcloud']));
  const old = applyEvents(fromRecords([rec(J1, 'running', 'apps remove nextcloud')]), [ev(4, 'ok', J1)], 4);
  check('events covered by the records are skipped', isPending(old, [], 'apps', ['remove', 'nextcloud']));
  check('payload as JSON text', jobEventState({ source: 'job', kind: 'running', subject: J1, payload: '{"key":"a b"}' }).key === 'a b');
  check('not a job event', jobEventState({ source: 'disk', kind: 'removed' }) === null && jobEventState({ source: 'job', kind: 'odd' }) === null);
}
// this browser's own task still counts
check('own task counts', isPending(new Map(), [{ key: 'apps remove nextcloud', state: 'running' }], 'apps', ['remove', 'nextcloud']) && !isPending(new Map(), [{ key: 'apps remove nextcloud', state: 'ended' }], 'apps', ['remove', 'nextcloud']));
// a failed fixture job restores the row: not pending, error shown, dismissed by hand, replaced by a later job
{
  const failed = fromRecords([rec(J1, 'failed', 'apps remove nextcloud', '3')]);
  check('failed: row is not pending any more', !isPending(failed, [], 'apps', ['remove', 'nextcloud']));
  const f = failureOf(failed, new Set(), 'apps', ['remove', 'nextcloud']);
  check('failed: the error is shown with the exit', f && f.id === J1 && f.error.code === 'job.failed' && f.error.what === 'hs apps remove nextcloud failed (exit 3)');
  check('failed: other rows show nothing', failureOf(failed, new Set(), 'apps', ['remove', 'jellyfin']) === null);
  check('failed: dismissed by hand', failureOf(failed, new Set([J1]), 'apps', ['remove', 'nextcloud']) === null);
  const again = fromRecords([rec(J1, 'failed', 'apps remove nextcloud', '3'), rec(J2, 'running', 'apps remove nextcloud')]);
  check('a later job replaces the failure and is pending', failureOf(again, new Set(), 'apps', ['remove', 'nextcloud']) === null && isPending(again, [], 'apps', ['remove', 'nextcloud']));
  const viaEvent = applyEvents(fromRecords([rec(J1, 'running', 'apps remove nextcloud')]), [ev(9, 'failed', J1, { exit: 2, key: 'apps remove nextcloud' })], 0);
  check('job.failed event restores the row at once', !isPending(viaEvent, [], 'apps', ['remove', 'nextcloud']) && failureOf(viaEvent, new Set(), 'apps', ['remove', 'nextcloud'])?.error.what.endsWith('(exit 2)'));
  const intr = fromRecords([rec(J1, 'interrupted', 'apps remove nextcloud')]);
  check('interrupted shows its own code', failureOf(intr, new Set(), 'apps', ['remove', 'nextcloud'])?.error.code === 'job.interrupted');
}
// Apps and Marketplace rows: installing, updating, start/stop from a job (also one started in a terminal), and a failed install puts the row back with its error
{
  const K = 'recipes nextcloud run', KI = 'apps install jellyfin';
  const run = fromRecords([rec(J1, 'running', K, '-', 'hs recipes nextcloud run')]);
  check('apps: a recipe run in a terminal makes the row pending', isPending(run, [], 'recipes', ['nextcloud', 'run']) && !isPending(run, [], 'recipes', ['jellyfin', 'run']));
  check('apps: a start job is pending for its instance only', isPending(fromRecords([rec(J1, 'running', 'ct nextcloud start')]), [], 'ct', ['nextcloud', 'start']) && !isPending(fromRecords([rec(J1, 'running', 'ct nextcloud start')]), [], 'ct', ['nextcloud', 'stop']));
  const dead = applyEvents(run, [ev(8, 'failed', J1, { exit: 1, key: K })], 0);
  const f = failureOf(dead, new Set(), 'recipes', ['nextcloud', 'run']);
  check('apps: failed install: not pending, error shown', !isPending(dead, [], 'recipes', ['nextcloud', 'run']) && f && f.error.what === 'hs recipes nextcloud run failed (exit 1)');
  const mk = applyEvents(new Map(), [ev(3, 'running', J2, { key: KI })], 0);
  check('marketplace: install pending from the event, failed shows the error', isPending(mk, [], 'apps', ['install', 'jellyfin'])
    && failureOf(applyEvents(mk, [ev(4, 'failed', J2, { exit: 2, key: KI })], 0), new Set(), 'apps', ['install', 'jellyfin'])?.error.code === 'job.failed');
}
// Instances and Docker rows (web/src/pages/instances/pending.js): start/stop from a terminal job, a failed job puts the row back
{
  const { ctPending, ctFailed, dockerPending, dockerFailed } = await import('../web/src/pages/instances/pending.js');
  const K1 = '20261119-120000-ct-start-dc1-abcd', K2 = '20261119-120100-ct-stop-dc1-efgh', K3 = '20261119-120200-docker-app-pull-web-ijkl';
  const jobs = fromRecords([rec(K1, 'running', 'ct dc1 start', '-', 'hs ct dc1 start')]);
  const pend = (a, g) => isPending(jobs, [], a, g), fail = (a, g) => failureOf(jobs, new Set(), a, g);
  check('ct start from a terminal: Starting', ctPending('dc1', pend) === 'Starting' && ctPending('other', pend) === '');
  const stop = fromRecords([rec(K2, 'running', 'ct dc1 stop --autostart off')]);
  check('ct stop with --autostart off: Stopping', ctPending('dc1', (a, g) => isPending(stop, [], a, g)) === 'Stopping');
  const bad1 = fromRecords([rec(K1, 'failed', 'ct dc1 start', '1', 'hs ct dc1 start')]);
  const pf = (a, g) => failureOf(bad1, new Set(), a, g), pp = (a, g) => isPending(bad1, [], a, g);
  check('failed start: not pending, error shown', ctPending('dc1', pp) === '' && ctFailed('dc1', pf)?.error.what === 'hs ct dc1 start failed (exit 1)' && ctFailed('x', pf) === null);
  const dk = fromRecords([rec(K3, 'running', 'docker-app web pull')]);
  check('docker pull: Pulling', dockerPending('web', (a, g) => isPending(dk, [], a, g)) === 'Pulling');
  const dkf = fromRecords([rec(K3, 'failed', 'docker-app web pull', '2')]);
  check('docker failed pull shows error', dockerFailed('web', (a, g) => failureOf(dkf, new Set(), a, g))?.error.code === 'job.failed');
  void fail;
}
if (bad) process.exit(1);
