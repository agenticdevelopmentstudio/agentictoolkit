import { describe, it, expect, vi, afterEach } from 'vitest';
import { composeVercelDeployError, composeVercelBuildLog } from '../src/monitor/fetch-vercel';
import {
  buildLogTail,
  buildLogFull,
  fetchRailwayBuildLogTail,
  fetchRailwayBuildLog,
  RAILWAY_NO_BUILD_TEXT,
} from '../src/monitor/fetch-railway';

afterEach(() => vi.unstubAllGlobals());

// The network-free halves of the deploy-error enrichment: how a Vercel deployment
// detail collapses to one reason line, and how a Railway build log collapses to a
// bounded tail. These are the shaping rules that regress silently, so they're
// tested directly (no fetch mock).
describe('composeVercelDeployError', () => {
  it('prefixes the failing build step onto the error message', () => {
    expect(composeVercelDeployError({ errorMessage: 'Command "next build" exited with 1', errorStep: 'buildStep' }))
      .toBe('[buildStep] Command "next build" exited with 1');
  });

  it('uses the error message alone when no step is named', () => {
    expect(composeVercelDeployError({ errorMessage: 'boom' })).toBe('boom');
  });

  it('falls back to readyStateReason when errorMessage is absent', () => {
    expect(composeVercelDeployError({ readyStateReason: 'deployment blocked' })).toBe('deployment blocked');
  });

  it('returns null when there is no reason at all (empty/whitespace)', () => {
    expect(composeVercelDeployError({ errorMessage: '   ', readyStateReason: '' })).toBeNull();
    expect(composeVercelDeployError({})).toBeNull();
  });
});

describe('buildLogTail', () => {
  it('returns null for no (or all-blank) lines', () => {
    expect(buildLogTail([])).toBeNull();
    expect(buildLogTail([null, undefined, '', '   '])).toBeNull();
  });

  it('drops blank lines and joins the rest with newlines', () => {
    expect(buildLogTail(['step 1', '', 'step 2', null, 'error: failed'])).toBe('step 1\nstep 2\nerror: failed');
  });

  it('keeps only the LAST 40 lines (the failure is at the tail)', () => {
    const lines = Array.from({ length: 100 }, (_, i) => `line ${i}`);
    const out = buildLogTail(lines)!;
    const kept = out.split('\n');
    expect(kept).toHaveLength(40);
    expect(kept[0]).toBe('line 60');
    expect(kept.at(-1)).toBe('line 99');
  });

  it('caps overall length, keeping the END with a leading ellipsis', () => {
    const huge = 'x'.repeat(10_000);
    const out = buildLogTail([huge])!;
    expect(out.length).toBeLessThanOrEqual(4_001); // 4000 chars + the "…" marker
    expect(out.startsWith('…')).toBe(true);
    expect(out.endsWith('x')).toBe(true);
  });
});

// The FULL-log shapers behind GET /deployments/:id/log. Their whole point is the
// opposite of the enrichment shapers above: nothing is dropped, because the cause
// of a build failure is usually far above the last line.
describe('composeVercelBuildLog', () => {
  const ev = (text?: string) => ({ type: 'stdout', payload: text === undefined ? {} : { text } });

  it('joins every event that carries text, in order', () => {
    expect(composeVercelBuildLog([ev('installing'), ev('building'), ev('failed')])).toBe('installing\nbuilding\nfailed');
  });

  it('skips events with no text (deployment-state, metrics)', () => {
    expect(composeVercelBuildLog([ev('one'), ev(), { type: 'deployment-state', payload: null }, ev('two')])).toBe(
      'one\ntwo',
    );
  });

  it('trims each event\'s trailing newline so the join does not double-space', () => {
    expect(composeVercelBuildLog([ev('one\n'), ev('two\n')])).toBe('one\ntwo');
  });

  it('keeps a log far longer than the enrichment tail — nothing is truncated', () => {
    const events = Array.from({ length: 500 }, (_, i) => ev(`line ${i}`));
    const out = composeVercelBuildLog(events)!;
    expect(out.split('\n')).toHaveLength(500);
    expect(out.startsWith('line 0')).toBe(true);
  });

  it('returns null when nothing carried text', () => {
    expect(composeVercelBuildLog([])).toBeNull();
    expect(composeVercelBuildLog([ev(), ev('   ')])).toBeNull();
  });
});

describe('buildLogFull', () => {
  it('keeps every line, unlike the 40-line tail', () => {
    const lines = Array.from({ length: 100 }, (_, i) => `line ${i}`);
    expect(buildLogFull(lines)!.split('\n')).toHaveLength(100);
    expect(buildLogTail(lines)!.split('\n')).toHaveLength(40); // the contrast is the point
  });

  it('drops blank lines and returns null when there are none left', () => {
    expect(buildLogFull(['a', '', null, 'b'])).toBe('a\nb');
    expect(buildLogFull([null, '   '])).toBeNull();
  });
});

describe('fetchRailwayBuildLogTail — GraphQL error handling', () => {
  it('a buildless deployment ("no associated build") gets the PERMANENT placeholder, not a retry', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => Response.json({ errors: [{ message: 'Deployment does not have an associated build' }] })),
    );
    const out = await fetchRailwayBuildLogTail('dep-1', 'tok', new AbortController().signal);
    expect(out).toBe(RAILWAY_NO_BUILD_TEXT); // persists → the id never re-enriches or re-logs
  });

  it('any other GraphQL error stays null (transient — retry next cycle)', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => Response.json({ errors: [{ message: 'Not Authorized' }] })),
    );
    const out = await fetchRailwayBuildLogTail('dep-2', 'tok', new AbortController().signal);
    expect(out).toBeNull();
  });
});

// The tail and the full read now share one GraphQL call, so the full read has to
// answer a buildless deployment and a transient error the same way — otherwise
// the CLI and the details pane would disagree about the same deployment.
describe('fetchRailwayBuildLog — shares the tail\'s error handling', () => {
  it('a buildless deployment gets the same permanent placeholder', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => Response.json({ errors: [{ message: 'Deployment does not have an associated build' }] })),
    );
    expect(await fetchRailwayBuildLog('dep-1', 'tok', new AbortController().signal)).toBe(RAILWAY_NO_BUILD_TEXT);
  });

  it('any other GraphQL error stays null', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => Response.json({ errors: [{ message: 'Not Authorized' }] })));
    expect(await fetchRailwayBuildLog('dep-2', 'tok', new AbortController().signal)).toBeNull();
  });

  it('returns every line the build emitted', async () => {
    const buildLogs = Array.from({ length: 60 }, (_, i) => ({ message: `line ${i}` }));
    vi.stubGlobal('fetch', vi.fn(async () => Response.json({ data: { buildLogs } })));
    const out = await fetchRailwayBuildLog('dep-3', 'tok', new AbortController().signal);
    expect(out!.split('\n')).toHaveLength(60); // the tail would have kept 40
  });
});
