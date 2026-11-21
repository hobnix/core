// Delay samples (web/src/delaysample.js) leave in batches: one POST /api/live/sample carries up to `max` of them, sent `wait` ms after the first one
// was queued (or when the page closes). The server counts a request, not a sample, against its per-session limit, so a busy stream stays far below it.
/**
 * @param {(samples: {topic: string, ms: number}[]) => void} post
 * @param {{ wait?: number, max?: number, setTimer?: typeof setTimeout, clearTimer?: typeof clearTimeout }} [opt]
 */
export function createBatcher(post, opt = {}) {
  const wait = opt.wait ?? 10000;
  const max = opt.max ?? 20;
  const setT = opt.setTimer ?? setTimeout;
  const clearT = opt.clearTimer ?? clearTimeout;
  /** @type {{topic: string, ms: number}[]} */
  let queue = [];
  let timer = null;
  function flush() {
    if (timer !== null) { clearT(timer); timer = null; }
    while (queue.length) post(queue.splice(0, max));
  }
  return {
    add(topic, ms) {
      queue.push({ topic, ms });
      if (queue.length >= max) flush();
      else if (timer === null) timer = setT(flush, wait);
    },
    flush,
  };
}
