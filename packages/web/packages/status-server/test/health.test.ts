import { describe, it, expect } from 'vitest';
import { classify } from '../src/monitor/health';

describe('classify', () => {
  const base = { statusCode: 200, responseTimeMs: 100, expectedStatus: 200 };

  it('healthy on fast 2xx', () => {
    expect(classify(base)).toBe('healthy');
  });

  it('degraded when slow', () => {
    expect(classify({ ...base, responseTimeMs: 2500 })).toBe('degraded');
  });

  it('down on 5xx', () => {
    expect(classify({ ...base, statusCode: 503 })).toBe('down');
  });

  it('down when the expected body marker is missing', () => {
    expect(classify({ ...base, bodyMarkerMissing: true })).toBe('down');
  });

  it('down when a health-kind JSON body reports non-ok status', () => {
    expect(
      classify({ ...base, isHealthKind: true, bodyText: '{"status":"degraded"}' }),
    ).toBe('down');
  });

  it('honours a non-2xx expectedStatus match as not-down', () => {
    expect(classify({ ...base, statusCode: 401, expectedStatus: 401 })).toBe('healthy');
  });
});
