// The toast store. `toast({ title, text, href, kind, ttl })` shows one; <Toast /> (mounted once in the shell) draws them.
//   - a job that asks for input: toast({ key: jobKey, kind: 'ask', title: 'Install nextcloud needs an answer', href: '#/jobs/<unit>', linkLabel: 'Open the job' }) - stays until
//     the question is answered (dismissToast(key)) or the user closes it, never times out;
//   - a short result that needs no dialog: toast({ kind: 'ok', title: 'Share created' }) - goes away after `ttl` ms (6 s; 0 = stays).
// A toast with a `key` that is already shown is replaced, not doubled. Closing is by the user or by dismissToast; nothing here reads a server or polls.
export const toasts = $state({ list: [] });
let seq = 0;
const timers = new Map();

export function toast({ key = '', kind = 'info', title = '', text = '', href = '', linkLabel = 'Open', ttl } = {}) {
  const id = key || `t${++seq}`;
  const t = { id, kind, title, text, href, linkLabel };
  const i = toasts.list.findIndex((x) => x.id === id);
  if (i >= 0) toasts.list[i] = t; else toasts.list.push(t);
  clearTimeout(timers.get(id));
  const ms = ttl ?? (kind === 'ask' ? 0 : 6000);
  if (ms > 0) timers.set(id, setTimeout(() => dismissToast(id), ms));
  return id;
}

export function dismissToast(id) {
  clearTimeout(timers.get(id));
  timers.delete(id);
  const i = toasts.list.findIndex((x) => x.id === id);
  if (i >= 0) toasts.list.splice(i, 1);
}
