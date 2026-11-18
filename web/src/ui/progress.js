// Pure helpers of Progress and StepList (plain JS so tests/web-progress.mjs can load them in node).

// Percent done 0..100, or null when the total is not known (then the bar is indeterminate or shows only the text).
export function pct(done, total) {
  const d = Number(done), t = Number(total);
  if (done === null || done === undefined || !Number.isFinite(d) || !Number.isFinite(t) || t <= 0) return null;
  return Math.max(0, Math.min(100, Math.round((d / t) * 100)));
}

// The state of step i (0-based) of a job at step `current` (0-based): done before it, current at it, todo after it.
// `failed` marks the current step as failed; `finished` marks every step done (a job that ended ok has no current step).
export function stepState(i, current, { failed = false, finished = false } = {}) {
  if (finished) return 'done';
  if (i < current) return 'done';
  if (i === current) return failed ? 'failed' : 'current';
  return 'todo';
}

// Steps from a job record ({ n (1-based), of, text }) when the names are not known: "Step 2 of 4" gives four unnamed steps.
export function stepsFromRecord(step, state = '') {
  if (!step || !Number.isFinite(step.of) || step.of <= 0) return [];
  const cur = Number.isFinite(step.n) ? step.n - 1 : 0;
  return Array.from({ length: step.of }, (_, i) => ({ label: i === cur && step.text ? step.text : '', state: stepState(i, cur, { failed: state === 'failed', finished: state === 'ok' }) }));
}
