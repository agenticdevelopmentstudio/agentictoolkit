import { describe, it, expect } from 'vitest';
import { latestDeploysOf } from '../src/monitor/fetch-vercel-projects';

// A project's snapshot must always carry its latest OUTCOME, not merely its latest
// deployment. Vercel's Ignored Build Step cancels a deployment for every site a commit
// didn't touch, so for a low-churn site the newest deployment is almost always a CANCELED
// skip — which is the absence of a verdict, not a verdict. If only that were supplied, the
// last real outcome would age out of the team-wide recent-deployments window and vanish
// from the DB, and the issue recorders (which judge the newest CONCLUSIVE deploy) would
// have nothing to judge: a fixed build could never resolve its issue, a failed one could
// never open. This is the exact shape that pinned the three `projects-*` projects "broken"
// for a day after their build was already fixed.

const dep = (id: string, readyState: string, createdAt: number, readySubstate?: string) => ({
  id,
  readyState,
  readySubstate,
  target: 'production',
  createdAt,
  url: `${id}.vercel.app`,
});

describe('latestDeploysOf', () => {
  it('supplies BOTH the newest deploy and the newest conclusive one when a skip is on top', () => {
    // The real projects-production history: a READY build, then an unrelated commit's skip.
    const out = latestDeploysOf('projects-production', [
      dep('skip', 'CANCELED', 3_000),
      dep('good', 'READY', 2_000, 'PROMOTED'),
      dep('bad', 'ERROR', 1_000),
    ]);

    expect(out.map((d) => d.id)).toEqual(['vc_skip', 'vc_good']);
    expect(out[0]!.buildPhase).toBe('canceled'); // the board still shows the newest deploy
    expect(out[1]!.buildPhase).toBe('built'); // …and the recorders still see the last verdict
    expect(out[1]!.deployPhase).toBe('deployed');
  });

  it('keeps a FAILED build reachable under a stack of skips (a skip never buries a failure)', () => {
    const out = latestDeploysOf('web', [
      dep('skip2', 'CANCELED', 4_000),
      dep('skip1', 'CANCELED', 3_000),
      dep('bad', 'ERROR', 1_000),
    ]);

    expect(out.map((d) => d.id)).toEqual(['vc_skip2', 'vc_bad']);
    expect(out[1]!.buildPhase).toBe('failed');
  });

  it('emits ONE row when the newest deploy is itself conclusive (no duplicate)', () => {
    const out = latestDeploysOf('web', [dep('good', 'READY', 2_000, 'PROMOTED'), dep('bad', 'ERROR', 1_000)]);
    expect(out.map((d) => d.id)).toEqual(['vc_good']);
  });

  it('emits only the skip when a project has never reached a verdict', () => {
    const out = latestDeploysOf('web', [dep('skip', 'CANCELED', 1_000)]);
    expect(out.map((d) => d.id)).toEqual(['vc_skip']);
  });

  it('ignores previews (target=null) and stateless rows, and returns [] when nothing is real', () => {
    const out = latestDeploysOf('web', [
      { id: 'preview', readyState: 'READY', target: null, createdAt: 9_000 },
      { id: 'nostate', target: 'production', createdAt: 8_000 },
    ]);
    expect(out).toEqual([]);
  });
});
