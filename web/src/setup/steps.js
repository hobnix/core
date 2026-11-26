// The first-run wizard (docs/PLAN-first-run-wizard.md step 5). Steps are data; the page maps an id to its component.
// A step whose component is not built yet is a SLOT: it stays here so its place in the order is fixed, and active() leaves it out.
export const FIRST_RUN_STEPS = [
  { id: 'account', question: 'Your administrator account', help: 'Signed in with the password you just set. The server name and the language of this interface.', primary: 'Next' },
  { id: 'network', slot: '#179', question: 'Network', help: '', primary: 'Next' },   // SLOT: Network step, built in #179 (web/src/setup/NetworkStep.svelte)
  { id: 'storage', question: 'Storage', help: 'The disks this server found. Import a pool that is on them, or make one from empty disks. Nothing changes until you confirm a plan.', primary: 'Next' },
  { id: 'blueprint', question: 'What is this server for?', help: 'Only the core, a blueprint (a ready-made choice that fills in what is not set yet and never overwrites a value) or single parts. Nothing changes until you confirm a plan.', primary: 'Next' },
  { id: 'done', question: 'Done', help: 'What is still open stays on the Setup page.', primary: 'Finish' },
];
export const active = (steps, built) => steps.filter((s) => built.includes(s.id));
export const clampIndex = (i, n) => Math.max(0, Math.min(i, n - 1));
