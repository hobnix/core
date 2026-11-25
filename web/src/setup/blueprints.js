// The "What is this server for?" step. Rows of hs sys blueprint list: name, repo, version, roles (csv), packages (csv, in install order),
// state (new|applied|update|waits), title; - = empty. A blueprint that waits for a newer core cannot be chosen.
const cell = (v) => (v && v !== '-' ? v : '');
export const blueprintRows = (rs) => rs.map((r) => ({
  name: r[0], repo: cell(r[1]), version: cell(r[2]), roles: cell(r[3]).split(',').filter(Boolean),
  packages: cell(r[4]).split(',').filter(Boolean), state: cell(r[5]), title: cell(r[6]) || r[0],
}));

const STATE = { applied: 'Applied already.', update: 'A newer version than the one applied.', waits: 'Needs a newer version of the server software.' };
const textOf = (b) => [
  STATE[b.state],
  b.roles.length ? `For: ${b.roles.join(', ')}.` : '',
  b.packages.length ? `Sets up: ${b.packages.join(', ')}.` : '',
  b.repo ? `Repository: ${b.repo}.` : '',
].filter(Boolean).join(' ');

// the choices of the step: core only first, the blueprints, then single parts. The ids carry a prefix, so a blueprint called core or parts stays apart.
export const setupOptions = (bps) => [
  { id: 'core', label: 'Core only', text: 'Nothing beyond the core. You can add things later.' },
  ...bps.map((b) => ({ id: 'blueprint:' + b.name, label: b.title, text: textOf(b), disabled: b.state === 'waits', reason: STATE.waits })),
  { id: 'parts', label: 'Choose parts', text: 'Pick single optional parts from the signed repositories.' },
];
export const blueprintOf = (bps, id) => bps.find((b) => id === 'blueprint:' + b.name && b.state !== 'waits');
