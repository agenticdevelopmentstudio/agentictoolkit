import { describe, it, expect } from 'vitest';
import { computeOverall, publicOverall } from '../src/monitor/overall';

describe('computeOverall (endpoint health rollup)', () => {
  it('no statuses → unknown', () => expect(computeOverall([])).toBe('unknown'));
  it('all healthy → operational', () => expect(computeOverall(['healthy', 'healthy'])).toBe('operational'));
  it('any degraded → degraded', () => expect(computeOverall(['healthy', 'degraded'])).toBe('degraded'));
  it('some down → degraded', () => expect(computeOverall(['healthy', 'down'])).toBe('degraded'));
  it('all down → major_outage', () => expect(computeOverall(['down', 'down'])).toBe('major_outage'));
});

describe('publicOverall (folds non-endpoint problems into the headline)', () => {
  it('healthy endpoints + a non-endpoint problem (e.g. a failed build) → degraded', () => {
    // The bug: a live site serves HTTP 200 while its deploy fails, so the
    // endpoint rollup reads operational — the open deploy issue must drag the
    // public headline down so the landing can't claim "all systems operational".
    expect(publicOverall(['healthy', 'healthy'], true)).toBe('degraded');
  });

  it('healthy endpoints + no other problem → operational (unchanged)', () => {
    expect(publicOverall(['healthy', 'healthy'], false)).toBe('operational');
  });

  it('a non-endpoint problem never manufactures a full outage — degraded, not major_outage', () => {
    expect(publicOverall(['healthy'], true)).toBe('degraded');
  });

  it('an all-endpoints-down major_outage stands even with non-endpoint problems', () => {
    expect(publicOverall(['down', 'down'], true)).toBe('major_outage');
  });

  it('an already-degraded endpoint rollup is unchanged by a non-endpoint problem', () => {
    expect(publicOverall(['healthy', 'down'], true)).toBe('degraded');
  });

  it('an unknown (no-signal) rollup is never lifted to degraded by a problem flag', () => {
    expect(publicOverall([], true)).toBe('unknown');
  });
});
