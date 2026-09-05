import { describe, it, expect } from 'vitest';
import { vercelPhases, railwayPhases, combinedStatus, crunchyPhases } from '../src/monitor/deploy-status';

describe('vercelPhases', () => {
  it('maps READY + PROMOTED on production to built+deployed', () => {
    const result = vercelPhases('READY', 'PROMOTED', 'production');
    expect(result.buildPhase).toBe('built');
    expect(result.deployPhase).toBe('deployed');
  });

  it('maps ERROR to failed build with no deploy', () => {
    const result = vercelPhases('ERROR', null, null);
    expect(result.buildPhase).toBe('failed');
    expect(result.deployPhase).toBe('none');
  });

  it('maps READY on non-production (preview) to built+none', () => {
    const result = vercelPhases('READY', null, null);
    expect(result.buildPhase).toBe('built');
    expect(result.deployPhase).toBe('none');
  });

  it('maps CANCELED to canceled+none', () => {
    const result = vercelPhases('CANCELED', null, null);
    expect(result.buildPhase).toBe('canceled');
    expect(result.deployPhase).toBe('none');
  });

  it('maps BUILDING to building+none', () => {
    const result = vercelPhases('BUILDING', null, null);
    expect(result.buildPhase).toBe('building');
    expect(result.deployPhase).toBe('none');
  });

  it('maps QUEUED to queued+none', () => {
    const result = vercelPhases('QUEUED', null, null);
    expect(result.buildPhase).toBe('queued');
    expect(result.deployPhase).toBe('none');
  });

  it('maps READY + ROLLING on production to built+deploying', () => {
    const result = vercelPhases('READY', 'ROLLING', 'production');
    expect(result.buildPhase).toBe('built');
    expect(result.deployPhase).toBe('deploying');
  });
});

describe('railwayPhases', () => {
  it('maps SUCCESS to built+deployed', () => {
    const result = railwayPhases('SUCCESS');
    expect(result.buildPhase).toBe('built');
    expect(result.deployPhase).toBe('deployed');
  });

  it('maps FAILED to failed+none', () => {
    const result = railwayPhases('FAILED');
    expect(result.buildPhase).toBe('failed');
    expect(result.deployPhase).toBe('none');
  });

  it('maps BUILDING to building+none', () => {
    const result = railwayPhases('BUILDING');
    expect(result.buildPhase).toBe('building');
    expect(result.deployPhase).toBe('none');
  });

  it('maps DEPLOYING to built+deploying', () => {
    const result = railwayPhases('DEPLOYING');
    expect(result.buildPhase).toBe('built');
    expect(result.deployPhase).toBe('deploying');
  });

  it('maps REMOVED to canceled+none', () => {
    const result = railwayPhases('REMOVED');
    expect(result.buildPhase).toBe('canceled');
    expect(result.deployPhase).toBe('none');
  });

  it('maps CRASHED to built+deployed (runtime crash is not a deploy failure)', () => {
    const result = railwayPhases('CRASHED');
    expect(result.buildPhase).toBe('built');
    expect(result.deployPhase).toBe('deployed');
  });
});

describe('combinedStatus', () => {
  it('returns "success" when deploy phase is deployed', () => {
    expect(combinedStatus({ buildPhase: 'built', deployPhase: 'deployed' })).toBe('success');
  });

  it('returns "failed" when build phase is failed', () => {
    expect(combinedStatus({ buildPhase: 'failed', deployPhase: 'none' })).toBe('failed');
  });

  it('returns "building" when build phase is building', () => {
    expect(combinedStatus({ buildPhase: 'building', deployPhase: 'none' })).toBe('building');
  });

  it('returns "queued" when build phase is queued', () => {
    expect(combinedStatus({ buildPhase: 'queued', deployPhase: 'none' })).toBe('queued');
  });

  it('returns "canceled" when build phase is canceled', () => {
    expect(combinedStatus({ buildPhase: 'canceled', deployPhase: 'none' })).toBe('canceled');
  });

  it('returns "success" for a built non-prod (staged) deploy with no separate deploy step', () => {
    expect(combinedStatus({ buildPhase: 'built', deployPhase: 'none' })).toBe('success');
  });

  it('returns "building" for in-flight deploy phase', () => {
    expect(combinedStatus({ buildPhase: 'built', deployPhase: 'deploying' })).toBe('building');
  });

  it('returns "unknown" when EITHER lifecycle expired unconfirmable — never re-reads as building', () => {
    expect(combinedStatus({ buildPhase: 'unknown', deployPhase: 'none' })).toBe('unknown');
    expect(combinedStatus({ buildPhase: 'built', deployPhase: 'unknown' })).toBe('unknown');
  });

  it('a failure verdict still wins over an expired other lifecycle', () => {
    expect(combinedStatus({ buildPhase: 'unknown', deployPhase: 'failed' })).toBe('failed');
  });
});

describe('crunchyPhases', () => {
  it('ready + not suspended → deployed', () => {
    expect(crunchyPhases('ready', false)).toEqual({ buildPhase: null, deployPhase: 'deployed' });
  });
  it('suspended flag → failed even when state is ready', () => {
    expect(crunchyPhases('ready', true)).toEqual({ buildPhase: null, deployPhase: 'failed' });
  });
  it('documented problem states → failed', () => {
    for (const s of ['failed', 'creation_failed', 'suspended']) {
      expect(crunchyPhases(s, false)).toEqual({ buildPhase: null, deployPhase: 'failed' });
    }
  });
  it('routine/transient states → deployed (quieter: maintenance is not a problem)', () => {
    for (const s of ['creating', 'restarting', 'resuming', 'starting', 'restoring',
                     'finalizing', 'replaying', 'destroying', 'suspending']) {
      expect(crunchyPhases(s, false)).toEqual({ buildPhase: null, deployPhase: 'deployed' });
    }
  });
  it('unknown / empty state → deployed (unrecognised is not assumed bad)', () => {
    for (const s of ['', 'weird_unknown']) {
      expect(crunchyPhases(s, false)).toEqual({ buildPhase: null, deployPhase: 'deployed' });
    }
  });
});
