// The lifecycle words of a package (ADR 0027), pure so tests/web-apps.mjs can import it in plain node.
// A row of `hs sys pkg states`: name, kind, stage (available|installed|on|running), flags (comma list, - = none), repo, available, installed, instances, title.
export const STAGES = ['available', 'installed', 'on', 'running'];

export function parseStates(rows) {
  return new Map((rows ?? []).map((r) => [r[0], {
    name: r[0], kind: r[1], stage: r[2], flags: r[3] === '-' ? [] : r[3].split(','),
    instances: !r[7] || r[7] === '-' ? [] : r[7].split(','),
  }]));
}

// What the buttons of a package offer. Install only while it is available, Update with the flag, Remove once it is here;
// Start/Stop belong to the instances of a recipe, Turn off/on to an extension or capability (the secondary button).
export function stageActions(s) {
  if (!s) return {};
  const here = s.stage !== 'available';
  const part = s.kind === 'extension' || s.kind === 'capability';
  return {
    install: s.stage === 'available',
    update: s.flags.includes('update'),
    remove: here,
    turn: part && here ? (s.stage === 'installed' ? 'enable' : 'disable') : '',
    instances: s.kind === 'recipe' && (s.stage === 'on' || s.stage === 'running') ? s.instances : [],
  };
}
