export interface Scheduler {
  start(): void;
  stop(): void;
  /** Run a cycle now, out of band, AWAITING its completion (the cron route).
   *  Returns false if a cycle was already in flight — this call coalesced into
   *  it and did NOT start a fresh one. Re-anchors the periodic grid so the next
   *  automatic tick is a full interval after this run (keeping
   *  {@link nextCycleAt} truthful). */
  runNow(): Promise<boolean>;
  /** Start a cycle now WITHOUT waiting for it (the interactive "check now" — a
   *  manual full sync can run minutes, and its result reaches clients via SSE,
   *  so nothing should hold an HTTP response open for it). Returns false when a
   *  cycle was already in flight (coalesced). Re-anchors the grid immediately. */
  runNowDetached(): boolean;
  lastCycleAt(): Date | null;
  /** When the next periodic tick will actually fire, computed off the interval
   *  GRID ANCHOR (when start()/runNow last (re)armed the timer) — NOT off
   *  lastCycleAt, so an out-of-band runNow or a failed/slow cycle can't desync the
   *  client's "next check" countdown. Null while stopped. */
  nextCycleAt(): Date | null;
  /** True when the loop has not COMPLETED a cycle within the staleness window (a
   *  few intervals). The readiness signal `/health` exposes so a wedged or
   *  repeatedly-failing loop is visible instead of masquerading as green — the gap
   *  that let the deployed monitor sit on ~32h-stale data behind a 200 healthcheck. */
  cycleStale(): boolean;
}

/** A single-flight interval runner: never starts a new cycle while one is in
 *  flight, never crashes the loop (each cycle is try/caught), and — via a per-cycle
 *  watchdog — never lets one hung cycle freeze the loop. Without the watchdog a
 *  single un-timed-out await inside the cycle strands `inFlight` true forever, so
 *  every later tick no-ops while the process stays up serving stale data — exactly
 *  the failure that left the deployed monitor frozen on ~32h-old checks. */
export function createScheduler(opts: {
  /** One cycle. `manual` is true for an out-of-band {@link Scheduler.runNow} ("check
   *  now") and false for the periodic/boot ticks — the cadence-decoupled cycle uses it to
   *  force a full deploy sync on a user-triggered check while the timer ticks stay cheap. */
  cycle: (ctx: { manual: boolean }) => Promise<void>;
  intervalMs: number;
  /** Hard cap on a single cycle. A cycle still running past this is presumed hung
   *  on an un-timed-out await; the watchdog releases the single-flight lock so the
   *  next tick can run, instead of the loop wedging forever on it. The abandoned
   *  cycle is left to settle on its own and does NOT advance {@link Scheduler.lastCycleAt}.
   *  Defaults to 3× the interval, floored at 2min. */
  cycleTimeoutMs?: number;
  /** How long WITHOUT a completed cycle before {@link Scheduler.cycleStale} trips.
   *  Defaults to 5× the interval, floored at 5min. */
  staleAfterMs?: number;
}): Scheduler {
  const cycleTimeoutMs = opts.cycleTimeoutMs ?? Math.max(opts.intervalMs * 3, 120_000);
  const staleAfterMs = opts.staleAfterMs ?? Math.max(opts.intervalMs * 5, 300_000);
  let timer: ReturnType<typeof setInterval> | null = null;
  let inFlight = false;
  let last: Date | null = null;
  let anchor: number | null = null; // ms — when the current interval grid started
  let startedAt: number | null = null; // ms — when the loop was first armed (staleness ref before the first completed cycle)
  let cycleSeq = 0; // identifies the in-flight cycle so a watchdog release and a
  //                   late settle of that SAME cycle can't free a newer cycle's lock.

  /** Run one cycle. Returns false if skipped because one was already running. */
  async function tick(manual = false): Promise<boolean> {
    if (inFlight) return false;
    inFlight = true;
    const seq = ++cycleSeq;
    // Only release the lock if WE still own it: a cycle the watchdog abandoned may
    // settle after a newer cycle has taken over, and its finally must not free that one.
    const release = (): void => {
      if (cycleSeq === seq) inFlight = false;
    };
    const watchdog = setTimeout(() => {
      console.error(`cycle exceeded ${cycleTimeoutMs}ms — abandoning it and releasing the scheduler (self-heal)`);
      release();
    }, cycleTimeoutMs);
    try {
      await opts.cycle({ manual });
      last = new Date();
    } catch (err) {
      console.error('cycle failed:', err);
    } finally {
      clearTimeout(watchdog);
      release();
    }
    return true;
  }

  function arm(): void {
    anchor = Date.now();
    timer = setInterval(() => void tick(), opts.intervalMs);
  }

  return {
    start() {
      if (timer) return;
      startedAt = Date.now();
      void tick(); // run once immediately on boot
      arm();
    },
    stop() {
      if (timer) clearInterval(timer);
      timer = null;
      anchor = null;
      startedAt = null;
    },
    async runNow() {
      const ran = await tick(true);
      // Re-anchor the grid so the next automatic tick is a full interval from now,
      // rather than firing again moments after this manual run.
      if (timer) {
        clearInterval(timer);
        arm();
      }
      return ran;
    },
    runNowDetached() {
      // `inFlight` flips inside tick's first synchronous slice, so this
      // check-then-start pair cannot interleave with another caller.
      if (inFlight) return false;
      void tick(true); // errors are contained inside tick (try/catch); nothing rejects
      if (timer) {
        clearInterval(timer);
        arm();
      }
      return true;
    },
    lastCycleAt: () => last,
    nextCycleAt: () => {
      if (!timer || anchor == null) return null;
      const elapsed = Date.now() - anchor;
      const n = Math.floor(elapsed / opts.intervalMs) + 1; // next firing on the grid
      return new Date(anchor + n * opts.intervalMs);
    },
    cycleStale: () => {
      if (!timer || startedAt == null) return false; // stopped / never started → nothing to judge
      // Measure from the last COMPLETED cycle; before the first one lands, from boot
      // (so a loop that never completes a cycle still trips after the window).
      const ref = last ? last.getTime() : startedAt;
      return Date.now() - ref > staleAfterMs;
    },
  };
}
