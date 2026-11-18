// Pure helpers of Stepper (plain JS so tests/web-stepper.mjs can load them in node).

const STATES = ['done', 'current', 'todo', 'failed'];

// Labels and the current index (0-based) -> steps with a state: done before it, current at it, todo after it.
export const stepsAt = (labels, index) =>
  (labels || []).map((label, i) => ({ label, state: i < index ? 'done' : i === index ? 'current' : 'todo' }));

// One step as the Stepper draws it: a known state (anything else is todo), a label, the 1-based number.
export const normalize = (steps) =>
  (steps || []).map((s, i) => {
    const o = typeof s === 'string' ? { label: s } : s;
    return { ...o, label: o.label ?? '', state: STATES.includes(o.state) ? o.state : 'todo', n: i + 1 };
  });

// A done step may be opened again (back to it) when the page gives a handler; the current, failed and later steps may not.
export const canSelect = (s, hasHandler) => !!hasHandler && s.state === 'done';
