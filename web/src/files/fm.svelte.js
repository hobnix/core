// The state of the file manager page: the two panes, the selection and the tray, the open dialogs, the running job. One `Fm` per page visit.
// Everything it reads or changes goes through ./api.js; the pure parts (locks, clicks, paths) are in ./selection.js (tested with node).
import * as api from './api.js';
import * as S from './selection.js';
import { track, showTab } from '../ui.svelte.js';
import { pools } from '../pools.svelte.js';

const remember = (k, v) => { try { v === undefined ? sessionStorage.removeItem(k) : sessionStorage.setItem(k, JSON.stringify(v)); } catch { /* private mode */ } };
const recall = (k) => { try { return JSON.parse(sessionStorage.getItem(k) ?? 'null'); } catch { return null; } };
const keep = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* private mode */ } };
const kept = (k) => { try { return JSON.parse(localStorage.getItem(k) ?? 'null'); } catch { return null; } };
const other = (side) => (side === 'L' ? 'R' : 'L');

class Pane {
  loc = $state('');
  path = $state('/');
  rows = $state.raw([]);
  view = $state.raw([]);            // the rows as the table shows them (sorted); set by the table
  next = $state(null);              // cursor of the next page; null = this is all
  status = $state('loading');       // loading | ok | error
  error = $state('');
  busy = $state(false);             // a refresh is under way (the old list stays)
  sel = $state.raw(new Set());
  anchor = '';
  cur = $state('');                 // the keyboard cursor (a name)
  filter = $state('');
  hidden = $state(false);           // show dot files
  seq = 0;
  preselect = '';
}

export class Fm {
  locs = $state.raw([]);
  locsState = $state('loading');    // loading | ok | error
  locsError = $state('');
  locked = $state(false);           // the encrypted storage is locked: `locations` answers without any location
  write = $state(true);             // the runtime setting fileManagerWrite (false = browsing and plans only; the server refuses every start)
  notice = $state('');              // a short message above the panes (the tray rule)
  panes = { L: new Pane(), R: new Pane() };
  active = $state('L');
  tray = $state.raw([]);            // [{ dir, name, type, bytes }], all of trayLoc
  trayLoc = $state('');
  picker = $state(null);            // the side whose location picker is open
  pairs = $state({});               // `${fixedLoc}|${candidate}` -> { ok, reason }
  dialog = $state(null);            // the plan dialog: { op, from, fromLabel, path, names, to, toLabel, toPath, summary }
  info = $state(null);              // { side, name }
  detail = $state({ key: '', stat: null, statErr: '', du: null, duErr: '', duBusy: false });   // what the Info panel read for the item: stat (owner, group, mode) and du (a folder's size)
  keys = $state(false);             // the shortcuts overlay
  patOpen = $state(false);
  pat = $state('');
  drag = $state(null);              // { side, items } while a drag runs
  job = $state(null);               // { unit, op, title, from, to, state, p, result }
  result = $state(false);           // the result dialog of a finished job
  mobile = $state('L');             // the pane the phone shows
  dual = $state(kept('fm:dual') === true);   // the second (right) pane is open; one pane is the start, delete, new folder and rename need no second pane
  timer = 0;
  ticks = 0;

  // open or close the second pane; closing it leaves the left one active
  setDual(on) {
    this.dual = !!on;
    keep('fm:dual', this.dual);
    if (!this.dual) { this.active = 'L'; this.mobile = 'L'; this.picker = null; return; }
    return this.load('R');
  }

  // ── start ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  async init(query = {}) {
    await this.refreshLocs();
    const saved = recall('fm:panes') ?? {};
    const pick = (side, id, path) => {
      const p = this.panes[side];
      p.loc = this.locOf(id) ? id : '';
      p.path = S.cleanPath(path || '/');
    };
    const disks = this.locs.filter((l) => l.kind === 'disk');
    const first = this.locs.find((l) => l.kind === 'pool') ?? this.locs[0];
    pick('L', query.left || saved.L?.loc || disks[0]?.id || first?.id, query.left ? query.path : saved.L?.path);
    pick('R', query.right || saved.R?.loc || S.defaultRight(this.locs, this.panes.L.loc || first?.id), query.right ? query.rpath : saved.R?.path);
    if (!this.panes.L.loc) pick('L', first?.id, '/');
    if (!this.panes.R.loc) pick('R', this.panes.L.loc, '/');
    if (query.right) this.dual = true;   // a link that names the right pane opens it
    if (query.select) this.panes.L.preselect = query.select;
    await Promise.all(this.dual ? [this.load('L'), this.load('R')] : [this.load('L')]);
    const want = this.panes.L.preselect;
    if (want) {
      const r = this.panes.L.rows.find((x) => x.name === want);
      if (r && S.selectable(r, this.ctxOf('L'))) { this.panes.L.sel = new Set([want]); this.panes.L.cur = want; this.panes.L.anchor = want; }
    }
    this.resumeJob();
  }

  destroy() { clearInterval(this.timer); this.timer = 0; }

  async refreshLocs() {
    try {
      const r = await api.locations();
      if (!r.ok) throw new Error(r.reason || 'The server refused to list the locations.');
      this.locs = r.locs;
      this.write = r.write;
      this.locked = r.locked;
      this.locsState = 'ok';
      this.locsError = '';
    } catch (e) {
      this.locsState = this.locs.length ? 'ok' : 'error';
      this.locsError = e.message;
    }
  }

  locOf = (id) => this.locs.find((l) => l.id === id) ?? null;
  label = (id) => this.locOf(id)?.label ?? id;
  // the rules that depend on the location: the top level of the SnapRAID pool is the array itself (the server marks every entry there `array`; this
  // keeps the two in step, so a row is locked even if a flag were missing). The fast pool and shares have no such level.
  ctxOf(side) {
    const p = this.panes[side], l = this.locOf(p.loc);
    const snapName = pools.rows.find((r) => r.kind !== 'zfs')?.name ?? '';
    return { poolRoot: !!l && !!snapName && l.id === `pool:${snapName}` && p.path === '/' };
  }
  lockedNames(side) {
    const ctx = this.ctxOf(side);
    return new Set(this.panes[side].rows.filter((r) => !S.selectable(r, ctx)).map((r) => r.name));
  }
  // the rows after the filter and the hidden-files switch (the table sorts them)
  visible(side) {
    const p = this.panes[side];
    const f = p.filter.trim().toLowerCase();
    return p.rows.filter((r) => (p.hidden || !r.name.startsWith('.')) && (!f || r.name.toLowerCase().includes(f)));
  }
  orderNames(side) {
    const p = this.panes[side];
    const shown = new Set(this.visible(side).map((r) => r.name));
    return (p.view.length ? p.view : this.visible(side)).filter((r) => shown.has(r.name)).map((r) => r.name);
  }

  // ── listing ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  save() { remember('fm:panes', { L: { loc: this.panes.L.loc, path: this.panes.L.path }, R: { loc: this.panes.R.loc, path: this.panes.R.path } }); }

  async load(side, { more = false, silent = false } = {}) {
    const p = this.panes[side];
    if (!p.loc) { p.status = 'error'; p.error = 'No location chosen.'; return; }
    const seq = ++p.seq;
    if (!silent && !more) p.busy = true;
    try {
      const r = await api.ls(p.loc, p.path, more ? (p.next ?? '') : '');
      if (seq !== p.seq) return;
      if (!r.ok) throw new Error(r.reason || 'The server refused to list this folder.');
      p.rows = more ? [...p.rows, ...r.rows] : r.rows;
      p.next = r.next && r.next !== 'end' ? r.next : null;
      p.status = 'ok';
      p.error = '';
      const names = new Set(p.rows.map((x) => x.name));
      if ([...p.sel].some((n) => !names.has(n))) p.sel = new Set([...p.sel].filter((n) => names.has(n)));
      if (p.cur && !names.has(p.cur)) p.cur = '';
    } catch (e) {
      if (seq !== p.seq) return;
      p.status = 'error';       // the last listing stays on screen, greyed
      p.error = e.message;
    } finally {
      if (seq === p.seq) p.busy = false;
    }
  }
  refresh(side) { return side ? this.load(side) : Promise.all(this.dual ? [this.load('L'), this.load('R')] : [this.load('L')]); }

  navigate(side, loc, path = '/') {
    const p = this.panes[side];
    p.loc = loc; p.path = S.cleanPath(path);
    p.rows = []; p.view = []; p.next = null; p.status = 'loading'; p.error = '';
    p.sel = new Set(); p.anchor = ''; p.cur = ''; p.filter = '';
    if (this.info?.side === side) this.info = null;
    this.save();
    return this.load(side);
  }
  goPath(side, path) { return this.navigate(side, this.panes[side].loc, path); }
  up(side) { const p = this.panes[side]; if (p.path !== '/') return this.goPath(side, S.parentPath(p.path)); }
  open(side, name) {
    const p = this.panes[side];
    const r = p.rows.find((x) => x.name === name);
    if (!r || r.type !== 'd' || !S.lockOf(r, this.ctxOf(side)).openable) return;
    return this.goPath(side, S.joinPath(p.path, name));
  }
  // the other pane shows the same place; swap exchanges the two
  same(side) { const o = this.panes[other(side)]; return this.navigate(side, o.loc, o.path); }
  swap() {
    const a = this.panes.L, b = this.panes.R;
    const keep = { loc: a.loc, path: a.path };
    this.navigate('L', b.loc, b.path);
    this.navigate('R', keep.loc, keep.path);
  }
  async pickLocation(side, id) {
    this.picker = null;
    await this.navigate(side, id, '/');
  }

  // ── selection ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  activate(side) { if (!this.dual) side = 'L'; this.active = side; this.mobile = side; }
  rowClick(side, row, e = {}) {
    const p = this.panes[side];
    this.activate(side);
    p.cur = row.name;
    const lock = S.lockOf(row, this.ctxOf(side));
    if (lock.locked) return;
    const st = S.click({ sel: p.sel, anchor: p.anchor, locked: this.lockedNames(side) }, this.orderNames(side), row.name, { ctrl: e.ctrlKey || e.metaKey, shift: e.shiftKey });
    p.sel = st.sel; p.anchor = st.anchor;
  }
  toggleRow(side, row) {
    const p = this.panes[side];
    if (!S.selectable(row, this.ctxOf(side))) return;
    this.activate(side);
    p.cur = row.name;
    p.sel = S.toggle(p.sel, row.name);
    p.anchor = row.name;
  }
  selectAll(side = this.active) { const p = this.panes[side]; p.sel = S.selectAll(this.orderNames(side), this.lockedNames(side), p.sel); }
  invert(side = this.active) { const p = this.panes[side]; p.sel = S.invert(this.orderNames(side), this.lockedNames(side), p.sel); }
  byPattern(remove) { const p = this.panes[this.active]; p.sel = S.byPattern(this.orderNames(this.active), this.lockedNames(this.active), p.sel, this.pat, remove); }
  clear(side = this.active) { const p = this.panes[side]; p.sel = new Set(); p.anchor = ''; }
  clearAll() { this.clear('L'); this.clear('R'); this.tray = []; this.trayLoc = ''; this.notice = ''; }
  move(d) {
    const p = this.panes[this.active];
    p.cur = S.step(this.orderNames(this.active), p.cur, d);
    return p.cur;
  }
  // Space / Insert: toggle the cursor row and go down
  spaceToggle() {
    const p = this.panes[this.active];
    const r = p.rows.find((x) => x.name === p.cur);
    if (r) this.toggleRow(this.active, r);
    this.move(1);
  }

  totalsOf(side) { return S.totals(this.panes[side].rows, this.panes[side].sel); }

  // the tray: collect the selection of the active pane, then go to other places and finish. It holds items of ONE folder of ONE location: the server
  // takes names inside a folder (no slash), a safety rule that stays.
  collect() {
    const p = this.panes[this.active];
    const items = p.rows.filter((r) => p.sel.has(r.name)).map((r) => ({ dir: p.path, name: r.name, type: r.type, bytes: r.bytes }));
    if (!items.length) return;
    if (this.tray.length && (this.trayLoc !== p.loc || this.tray[0].dir !== p.path)) { this.notice = S.TRAY_ONE_FOLDER; return; }
    this.notice = '';
    this.trayLoc = p.loc;
    this.tray = S.addToTray(this.tray, items);
    this.clear(this.active);
  }
  clearTray() { this.tray = []; this.trayLoc = ''; this.notice = ''; }

  // what an operation on `side` works on: { ok, why, loc, path, names, items, n, files, dirs, bytes, unknown }
  source(side = this.active) {
    const p = this.panes[side];
    const items = p.rows.filter((r) => p.sel.has(r.name)).map((r) => ({ dir: p.path, name: r.name, type: r.type, bytes: r.bytes, flags: r.flags }));
    const tray = this.trayLoc === p.loc ? this.tray : [];
    let all = items, why = '';
    if (tray.length) {
      if (items.length && tray[0].dir !== p.path) { all = []; why = S.TRAY_ONE_FOLDER; }   // a selection in another folder than the tray's: not mixed
      else all = S.addToTray(tray, items);
    }
    const { path, names } = S.sourceOf(all);
    const t = { n: all.length, files: all.filter((i) => i.type !== 'd').length, dirs: all.filter((i) => i.type === 'd').length, bytes: all.reduce((a, i) => a + (Number.isFinite(i.bytes) ? i.bytes : 0), 0), unknown: all.filter((i) => i.type === 'd' && !Number.isFinite(i.bytes)).length };
    return { ok: all.length > 0, why, loc: p.loc, path, names, items: all, ...t };
  }

  // '' when the operation may be started now, else the reason (the toolbar button shows it as its tooltip)
  can(op, side = this.active) {
    const a = this.panes[side], b = this.panes[other(side)];
    const src = this.locOf(a.loc), dst = this.locOf(b.loc);
    if (this.locsState !== 'ok' || !src) return 'No location is open';
    const ro = (l) => (l.reason || 'This location is read only');
    if (op === 'mkdir') return src.modifiable ? '' : ro(src);
    const s = this.source(side);
    if (!s.ok) return s.why || 'Select something first';
    if (op === 'rename') {
      if (s.n !== 1) return 'Rename works on one item at a time';
      if (s.items[0].flags?.includes('badname')) return 'This name has odd characters and cannot be renamed here';
      return src.modifiable ? '' : ro(src);
    }
    if (op === 'delete') return src.modifiable ? '' : ro(src);
    if (!this.dual) return 'Open the second pane first: it is the target of a copy or move';
    if (!dst) return 'Open a location in the other pane first';
    if (!dst.writable) return dst.modifiable ? ro(dst) : `${dst.label} is read only: ${ro(dst)}`;
    if (op === 'move' && !src.modifiable) return `${src.label} is read only, so nothing can be moved out of it`;
    return '';
  }

  // open the plan dialog for an operation on the active pane (or the pane a drag came from)
  plan(op, { side = this.active, toPane = other(side), toFolder = '', name = '' } = {}) {
    if (this.can(op, side)) return;
    const a = this.panes[side], b = this.panes[toPane];
    const s = this.source(side);
    const needsTarget = op === 'copy' || op === 'move';
    const toPath = needsTarget ? (toFolder ? S.joinPath(b.path, toFolder) : b.path) : '';
    if (needsTarget && toFolder && S.insideAny(toPath, s.items.map((i) => ({ ...i, dir: s.path })))) return;
    this.dialog = {
      op, side, from: a.loc, fromLabel: this.label(a.loc), path: op === 'mkdir' ? a.path : s.path, names: op === 'mkdir' ? [] : s.names,
      to: needsTarget ? b.loc : '', toLabel: needsTarget ? this.label(b.loc) : '', toPath, toLoc: needsTarget ? this.locOf(b.loc) : null,
      sum: { n: s.n, files: s.files, dirs: s.dirs, bytes: s.bytes, unknown: s.unknown }, name: op === 'rename' ? (s.items[0]?.name ?? '') : name,
      fromLoc: this.locOf(a.loc), arrayMove: op === 'move' && !!this.locOf(a.loc)?.pool && this.locOf(a.loc)?.pool === this.locOf(b.loc)?.pool,
    };
  }

  // ── the Info panel: owner, group and mode come from `stat`; the size of a folder only when asked (it reads the whole folder and can wake disks) ──────────────────
  infoKey(side = this.info?.side, name = this.info?.name) { const p = this.panes[side]; return `${p.loc}|${S.joinPath(p.path, name)}`; }
  openInfo(side, name) {
    this.info = { side, name };
    const key = this.infoKey(side, name);
    this.detail = { key, stat: null, statErr: '', du: null, duErr: '', duBusy: false };
    return this.loadStat(side, name, key);
  }
  async loadStat(side, name, key) {
    const p = this.panes[side];
    try {
      const r = await api.stat(p.loc, S.joinPath(p.path, name));
      if (this.detail.key !== key) return;
      if (r.ok) this.detail.stat = r; else this.detail.statErr = r.reason || 'The server did not answer.';
    } catch (e) { if (this.detail.key === key) this.detail.statErr = e.message; }
  }
  // "Size" next to a folder: open its Info panel and measure it at once
  async sizeOf(side, name) {
    await this.openInfo(side, name);
    return this.measure(side, name);
  }
  // the size of a folder: a background job on the server (kept per folder with its mtime); ask again every 2 s until the number is there
  async measure(side = this.info?.side, name = this.info?.name) {
    if (!this.info || this.detail.duBusy) return;
    const key = this.infoKey(side, name), loc = this.panes[side].loc, path = S.joinPath(this.panes[side].path, name);
    this.detail.duBusy = true; this.detail.duErr = '';
    try {
      for (let i = 0; i < 300; i++) {
        const r = await api.du(loc, path);
        if (this.detail.key !== key) return;
        if (!r.ok) { this.detail.duErr = r.reason || 'The server refused.'; return; }
        if (!r.pending) { this.detail.du = r; return; }
        await new Promise((ok) => setTimeout(ok, 2000));
        if (this.detail.key !== key) return;
      }
      this.detail.duErr = 'Still measuring. Try again later.';
    } catch (e) { if (this.detail.key === key) this.detail.duErr = e.message; }
    finally { if (this.detail.key === key) this.detail.duBusy = false; }
  }

  // ── a typed path: the server decides (ls says why not), the browser never resolves .. or links ───────────────────────────────────────────────────────────────
  async tryPath(side, text) {
    const p = this.panes[side];
    const t = String(text ?? '').trim();
    if (!p.loc) return 'No location chosen.';
    try {
      const r = await api.ls(p.loc, t === '' ? '/' : t, '', 1);
      if (!r.ok) return r.reason || 'The server refused this path.';
    } catch (e) { return e.message; }
    await this.navigate(side, p.loc, S.cleanPath(t === '' ? '/' : t.startsWith('/') ? t : `/${t}`));
    return '';
  }

  // ── drag and drop (desktop): the drop only opens the plan ───────────────────────────────────────────────────────────────────────────────
  dragStart(side, row) {
    const p = this.panes[side];
    if (!S.selectable(row, this.ctxOf(side))) return false;
    if (!p.sel.has(row.name)) { p.sel = new Set([row.name]); p.anchor = row.name; }
    this.active = side;
    this.drag = { side, n: p.sel.size };
    return true;
  }
  dragEnd() { this.drag = null; }
  drop(toPane, folder, shift) {
    const d = this.drag;
    this.drag = null;
    if (!d) return;
    this.plan(shift ? 'move' : 'copy', { side: d.side, toPane, toFolder: folder });
  }

  // ── jobs ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  beginJob(unit, spec, title, opts = {}) {
    const keep = spec.names && spec.names.length <= 2000 ? { spec: { op: spec.op, from: spec.from, path: spec.path, to: spec.to, toPath: spec.toPath, names: [...spec.names] }, opts: { ...opts } } : {};   // what Continue needs (a huge selection is not kept)
    this.job = { unit, op: spec.op, title, from: spec.from, to: spec.to, started: Date.now(), state: 'running', p: null, bad: 0, ...keep };
    remember('fm:job', { unit, op: spec.op, title, from: spec.from, to: spec.to, started: this.job.started, ...keep });
    track(unit, title);
    showTab('tasks');
    this.watch();
    this.afterStart(spec.side);
  }
  afterStart(side) {
    if (side) this.clear(side);
    this.tray = []; this.trayLoc = '';
    this.refresh();
  }
  // a reload of the page does not lose a running job
  resumeJob() {
    const j = recall('fm:job');
    if (!j || this.job) return;
    if (j.paused) { this.job = { ...j, state: 'paused', p: null, bad: 0 }; return; }
    this.job = { ...j, state: 'running', p: null, bad: 0 };
    this.watch();
  }
  watch() {
    clearInterval(this.timer);
    this.ticks = 0;
    this.tick();
    this.timer = setInterval(() => this.tick(), 1500);
  }
  async tick() {
    const j = this.job;
    if (!j || j.state !== 'running') return clearInterval(this.timer);
    try {
      const p = await api.progress(j.unit);
      if (!p.ok) throw new Error(p.reason);
      j.bad = 0;
      j.p = p;
      if (p.result !== 'running') {
        const paused = j.pausing && p.result === 'cancelled';
        j.state = paused ? 'paused' : p.result;
        clearInterval(this.timer);
        if (paused) remember('fm:job', { unit: j.unit, op: j.op, title: j.title, from: j.from, to: j.to, started: j.started, paused: true, spec: j.spec, opts: j.opts });
        else remember('fm:job', undefined);
        await this.refresh();
        if (!paused && (p.skipped.n || p.failed.n || p.result !== 'done')) this.result = true;
        return;
      }
    } catch {
      // the unit is gone (the server restarted, or it ended long ago): after a few misses stop watching
      if (++j.bad >= 4) { j.state = 'gone'; clearInterval(this.timer); remember('fm:job', undefined); }
    }
    if (++this.ticks % 2 === 0) { this.load('L', { silent: true }); if (this.dual) this.load('R', { silent: true }); }   // the lists follow the job
  }
  async cancelJob() {
    const j = this.job;
    if (!j || j.cancelling) return;
    j.cancelling = true;
    try { await api.cancel(j.unit); } catch { j.cancelling = false; }
  }
  // Pause = stop the job and keep its list (no SIGSTOP: a stopped process would hold the pool lock). The job ends cleanly: what was copied stays, nothing
  // unverified was removed. Only copy and move can go on (delete and the rest are instant or ask for a typed confirmation).
  canPause = () => !!this.job && this.job.state === 'running' && (this.job.op === 'copy' || this.job.op === 'move') && !!this.job.spec;
  async pauseJob() {
    const j = this.job;
    if (!j || j.cancelling || j.pausing) return;
    j.pausing = true;
    try { const r = await api.cancel(j.unit); if (!r.ok) j.pausing = false; } catch { j.pausing = false; }
  }
  // Continue = a NEW job over the same selection with `--conflict skip --verify size`: what is at the target already is left alone. For a move the items that
  // already left the source are not asked for again.
  async continueJob() {
    const j = this.job;
    if (!j || j.state !== 'paused' || j.continuing || !j.spec) return;
    j.continuing = true;
    try {
      let names = j.spec.names;
      if (j.op === 'move') {
        const have = new Set();
        let cursor = '';
        for (let i = 0; i < 50; i++) {
          const r = await api.ls(j.spec.from, j.spec.path, cursor, 2000);
          if (!r.ok) { this.notice = r.reason || 'The source cannot be read.'; return; }
          for (const row of r.rows) have.add(row.name);
          if (!r.next || r.next === 'end') break;
          cursor = r.next;
        }
        names = names.filter((n) => have.has(n));
        if (!names.length) { j.state = 'done'; this.notice = 'Nothing is left to move: every item has left the source.'; remember('fm:job', undefined); return; }
      }
      const spec = { ...j.spec, names };
      const opts = { ...j.opts, conflict: 'skip', verify: 'size' };
      const r = await api.start(spec, opts, '');
      if (!r.ok) { this.notice = r.reason || 'The server did not start it.'; return; }
      this.beginJob(r.unit, spec, j.title, opts);
    } catch (e) { this.notice = e.message; }
    finally { if (this.job === j) j.continuing = false; }
  }
  dismissJob() { this.job = null; this.result = false; remember('fm:job', undefined); }
  // the location a running job works in (a pane on it shows "a move is running here")
  jobHere(side) {
    const j = this.job;
    return !!j && j.state === 'running' && (j.from === this.panes[side].loc || j.to === this.panes[side].loc);
  }

  // ── the pair rule in the picker ────────────────────────────────────────────────────────────────────────────────────────────────────────
  // Opens the picker of a pane and asks, for every location, whether it may be the other side of what the other pane shows (greyed with the reason if not)
  async openPicker(side) {
    this.picker = side;
    const fixed = this.panes[other(side)].loc;
    if (!fixed || !this.dual) return;
    await this.refreshLocs();
    await Promise.all(this.locs.map(async (l) => {
      const k = `${fixed}|${l.id}`;
      try { this.pairs[k] = await api.pair(fixed, l.id); } catch { this.pairs[k] = { ok: true, reason: '' }; }
    }));
  }
  pairOf(side, id) {
    if (!this.dual) return { ok: true, reason: '' };
    const fixed = this.panes[other(side)].loc;
    return this.pairs[`${fixed}|${id}`] ?? { ok: true, reason: '' };
  }
}
