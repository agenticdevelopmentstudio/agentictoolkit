import { describe, it, expect } from 'vitest';
import { evaluateProdStaleness } from '../src/monitor/fetch-vercel-projects';

// The staleness check answers "is production frozen on a broken/old build while newer
// builds pile up unpromoted". It reads Vercel's `targets.production` as "what is live".
//
// That premise breaks on a CANCELED deployment. Vercel's Ignored Build Step cancels a
// deployment for every site a commit didn't touch, and `targets.production` then points at
// that SKIP — a deployment that never served a byte. Judging it disarms BOTH signals at
// once: `errored` is false (a skip is not an ERROR) and the skip's timestamp is newer than
// any READY build, so `behind` is false too. The detector silently reports healthy.
// (Verified against the live API: all three projects-* had targets.production = CANCELED.)
//
// Reconstructing under a skip needs TWO different answers, not one:
//   errored → the last CONCLUSIVE attempt on production;
//   behind  → what is actually SERVING, i.e. the newest PROMOTED deployment. (Resolving
//             this to the newest conclusive instead would compare an unpromoted build to
//             itself and always report healthy — killing the signal.)

const dep = (
  readyState: string,
  createdAt: number,
  opts: { promoted?: boolean; target?: string | null } = {},
) => ({
  id: `d${createdAt}`,
  readyState,
  readySubstate: opts.promoted ? 'PROMOTED' : null,
  target: opts.target === undefined ? 'production' : opts.target,
  createdAt,
});

describe('evaluateProdStaleness', () => {
  it('sees an ERRORED attempt hidden under a canceled skip', () => {
    const skip = dep('CANCELED', 3_000);
    const r = evaluateProdStaleness(skip, [skip, dep('ERROR', 2_000), dep('READY', 1_000, { promoted: true })]);
    expect(r.errored).toBe(true); // the last REAL build errored — production never moved
    expect(r.stale).toBe(true);
  });

  it('sees a newer READY build left unpromoted under a canceled skip', () => {
    // Serving = READY@1000 (PROMOTED). READY@2000 built fine but was never promoted, so
    // production is behind. The skip@3000 on top would out-date it and mask the lag.
    const skip = dep('CANCELED', 3_000);
    const r = evaluateProdStaleness(skip, [skip, dep('READY', 2_000), dep('READY', 1_000, { promoted: true })]);
    expect(r.behind).toBe(true);
    expect(r.liveCreated).toBe(1_000); // measured against what is SERVING, not the skip
    expect(r.stale).toBe(true);
  });

  it('reports healthy when the promoted build IS the newest READY one', () => {
    // The real projects-* shape today: b020e5c9 READY+PROMOTED, then eb3ae595's skip on top.
    const skip = dep('CANCELED', 3_000);
    const r = evaluateProdStaleness(skip, [skip, dep('READY', 2_000, { promoted: true })]);
    expect(r.stale).toBe(false);
    expect(r.liveCreated).toBe(2_000); // the skip never served — the promoted build is live
  });

  it('still judges a conclusive live deployment directly (pre-skip behaviour, untouched)', () => {
    const errored = dep('ERROR', 2_000);
    expect(evaluateProdStaleness(errored, [errored, dep('READY', 1_000, { promoted: true })]).errored).toBe(true);

    const ready = dep('READY', 2_000, { promoted: true });
    expect(evaluateProdStaleness(ready, [ready]).stale).toBe(false);

    // `behind` still fires the classic way: production pinned to an older promoted build
    // while a newer READY one sits unpromoted, no skip involved.
    const promoted = dep('READY', 1_000, { promoted: true });
    expect(evaluateProdStaleness(promoted, [dep('READY', 2_000), promoted]).behind).toBe(true);
  });

  it('cannot judge a project with no conclusive production deploy at all — not stale', () => {
    const skip = dep('CANCELED', 3_000);
    const r = evaluateProdStaleness(skip, [skip]);
    expect(r.stale).toBe(false);
  });

  it('ignores previews (target != production) when reconstructing the live deploy', () => {
    const skip = dep('CANCELED', 3_000);
    const r = evaluateProdStaleness(skip, [
      skip,
      dep('ERROR', 2_500, { target: null }), // an errored PREVIEW is not production
      dep('READY', 2_000, { promoted: true }),
    ]);
    expect(r.errored).toBe(false);
    expect(r.stale).toBe(false);
  });
});
