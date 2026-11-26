// What a row of Apps & VMs (instance or Docker app) is doing, from rowstate (web/src/rowstate.svelte.js; plain JS so node can test it, tests/web-rowstate.mjs).
// `pending(area, args)` and `failed(area, args)` are the rowstate functions. A job started in a terminal counts too: the answer comes from the job records and events.
const CT = (n) => [
  [[n, 'start'], 'Starting'], [[n, 'stop'], 'Stopping'], [[n, 'stop', '--autostart', 'off'], 'Stopping'], [[n, 'restart'], 'Restarting'],
  [[n, 'update'], 'Updating'], [[n, 'snapshot'], 'Snapshotting'], [[n, 'delete'], 'Deleting'],
];
const DOCKER = (n) => [
  [[n, 'start'], 'Starting'], [[n, 'stop'], 'Stopping'], [[n, 'restart'], 'Restarting'], [[n, 'pull'], 'Pulling'], [[n, 'recreate'], 'Applying'],
  [[n, 'rebuild'], 'Rebuilding'], [[n, 'delete'], 'Deleting'], [[n, 'delete', '--delete-data'], 'Deleting'],
];
const first = (list, area, fn) => { for (const [args, word] of list) { const r = fn(area, args); if (r) return { r, word, args }; } return null; };

// 'Starting' | 'Stopping' | ... of an instance (area ct) with a running job, else ''
export const ctPending = (name, pending) => first(CT(name), 'ct', pending)?.word ?? '';
export const dockerPending = (name, pending) => first(DOCKER(name), 'docker-app', pending)?.word ?? '';
// the failure ({ id, error }) of the newest failed job of the instance, or null; only when nothing is pending (a new job replaces it)
export const ctFailed = (name, failed) => first(CT(name), 'ct', failed)?.r ?? null;
export const dockerFailed = (name, failed) => first(DOCKER(name), 'docker-app', failed)?.r ?? null;
