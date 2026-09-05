import { describe, it, expect } from 'vitest';
import { autoConfigureOptedOut, dedupeDetail } from '../src/routes/auto-configure';

// `skippedDetail` is what turned a permanently-stuck project from an opaque count into a
// named reason — but the web dialog only prints the first five lines, so a repeated cause
// crowding out the distinct ones would put the count right back where it was.
describe('dedupeDetail', () => {
  it('collapses an identical project+reason repeated by the endpoint axis', () => {
    // The real shape: `wireMatchingEndpoints` reports one row PER ENDPOINT, so a project
    // whose four endpoints all fail the same way lands the same line four times.
    const rows = Array.from({ length: 4 }, () => ({ project: 'adh-web', reason: '401 Unauthorized' }));
    expect(dedupeDetail(rows)).toEqual([{ project: 'adh-web', reason: '401 Unauthorized' }]);
  });

  it('keeps DIFFERENT reasons for one project, and one reason across different projects', () => {
    // Deduping on the project alone would hide the second failure mode; deduping on the
    // reason alone would hide every project but the first.
    const rows = [
      { project: 'a', reason: 'slug taken' },
      { project: 'a', reason: '401 Unauthorized' },
      { project: 'b', reason: 'slug taken' },
    ];
    expect(dedupeDetail(rows)).toEqual(rows);
  });

  it('keeps first-seen order', () => {
    const rows = [
      { project: 'b', reason: 'r' },
      { project: 'a', reason: 'r' },
      { project: 'b', reason: 'r' },
    ];
    expect(dedupeDetail(rows).map((r) => r.project)).toEqual(['b', 'a']);
  });

  it('is empty for no input', () => {
    expect(dedupeDetail([])).toEqual([]);
  });
});

// The endpoint axis wires any monitor the engine's `endpointUnconfigured` calls undecided.
// `ignoreProjectWarning` used to be dropped on the way into the engine, so BOTH operator
// opt-outs were invisible to it and it re-wired sites it had been told to leave alone.
describe('autoConfigureOptedOut', () => {
  it('an ordinary monitor is fair game', () => {
    expect(autoConfigureOptedOut({ ignoreProjectWarning: false, isActive: true })).toBe(false);
  });

  it('the per-endpoint opt-out ("Automatically Configure" unchecked) opts out', () => {
    expect(autoConfigureOptedOut({ ignoreProjectWarning: true, isActive: true })).toBe(true);
  });

  it('monitoring switched off opts out on its own — a paused site is out of the conversation', () => {
    expect(autoConfigureOptedOut({ ignoreProjectWarning: false, isActive: false })).toBe(true);
  });

  it('either one suffices; neither cancels the other', () => {
    expect(autoConfigureOptedOut({ ignoreProjectWarning: true, isActive: false })).toBe(true);
  });
});
