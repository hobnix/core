// Sleep state of a spinning disk for the Disks page: field 13 of `sys monitor disks` (asleep | spinning | -) and, from `sys disk power`,
// since (epoch seconds) and the wakes counted today. Pure functions; no estimate of power per disk.

export const SLEEP_FIELD = 12;   // index of field 13 in a `sys monitor disks` row

// 'asleep' | 'spinning' | '' (an SSD, NVMe or a disk that did not answer: nothing is shown)
export const sleepOf = (row) => {
  const v = (row?.[SLEEP_FIELD] ?? '').trim();
  return v === 'asleep' || v === 'spinning' ? v : '';
};

export const sleepText = (state) => (state === 'asleep' ? 'Asleep' : state === 'spinning' ? 'Spinning' : '');

// StatusDot state: a sleeping disk is the good case (it saves power), a spinning one is neutral
export const sleepDot = (state) => (state === 'asleep' ? 'ok' : 'info');

// `sys disk power` lines -> { disks: { dev: { state, since, wakes } }, power: [{ source, what, watts }] }
export const parsePower = (lines) => {
  const out = { disks: {}, power: [] };
  for (const r of lines ?? []) {
    if (r[0] === 'disk') out.disks[r[1]] = { state: r[2], since: Number(r[3]) || 0, wakes: Number(r[4]) || 0 };
    else if (r[0] === 'power' && r[3] && r[3] !== '-') out.power.push({ source: r[1], what: r[2], watts: Number(r[3]) });
  }
  return out;
};

const SOURCE = { ups: 'UPS', rapl: 'CPU package (RAPL)' };
export const powerText = (p) => `${p.watts} W, ${p.what}, measured by ${SOURCE[p.source] ?? p.source}`;
