// What a row of Shares, Users, Groups, Backup, Vault and Expiry is doing, from rowstate (web/src/rowstate.svelte.js; plain JS so node can test it, tests/web-rowstate.mjs).
// `pending(area, args)` and `failed(area, args)` are the rowstate functions. A job started in a terminal counts too: the answer comes from the job records and events.
const SHARE = (n) => [
  [[n, 'snapshot'], 'Snapshotting'], [[n, 'repair'], 'Repairing'], [[n, 'undelete'], 'Restoring'], [[n, 'purge'], 'Removing'], [[n, 'delete'], 'Deleting'],
  [[n, 'cache', '--to', 'on'], 'Changing'], [[n, 'cache', '--to', 'off'], 'Changing'], [[n, 'auto', '--to', 'on'], 'Changing'], [[n, 'auto', '--to', 'off'], 'Changing'],
];
const USER = (n) => [[[n, 'lock'], 'Locking'], [[n, 'unlock'], 'Unlocking'], [[n, 'user-delete'], 'Deleting']];
const GROUP = (n) => [[[n, 'group-delete'], 'Deleting']];
const BACKUP = [
  [['now'], 'Backing up'], [['verify'], 'Verifying'], [['prune'], 'Freeing space'], [['drill'], 'Testing a restore'], [['offsite-now'], 'Copying off site'],
  [['offsite-off'], 'Stopping the copy'], [['browse', '--to', 'on'], 'Opening'], [['browse', '--to', 'off'], 'Closing'],
];
const VAULT = [[['header-backup'], 'Saving the header'], [['move'], 'Moving secrets'], [['secrets-fix'], 'Fixing permissions'], [['close'], 'Closing']];
const first = (list, area, fn) => { for (const [args, word] of list) { const r = fn(area, args); if (r) return { r, word }; } return null; };
const word = (list, area, pending) => first(list, area, pending)?.word ?? '';
const fail = (list, area, failed) => first(list, area, failed)?.r ?? null;

export const sharePending = (n, pending) => word(SHARE(n), 'shares', pending);
export const shareFailed = (n, failed) => fail(SHARE(n), 'shares', failed);
export const userPending = (n, pending) => word(USER(n), 'users', pending);
export const userFailed = (n, failed) => fail(USER(n), 'users', failed);
export const groupPending = (n, pending) => word(GROUP(n), 'users', pending);
export const groupFailed = (n, failed) => fail(GROUP(n), 'users', failed);
export const backupPending = (pending) => word(BACKUP, 'backup', pending);
export const backupFailed = (failed) => fail(BACKUP, 'backup', failed);
export const vaultFailed = (failed) => fail(VAULT, 'secrets', failed);
export const expiryFailed = (n, failed) => fail([[['remove', n], 'Removing']], 'expiry', failed);
