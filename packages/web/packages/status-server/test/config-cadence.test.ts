import { describe, it, expect, afterEach } from 'vitest';
import { deploySyncIntervalMs, envConfig } from '../src/config';

afterEach(() => {
  delete process.env.DEPLOY_SYNC_SECONDS;
});

const MIN = 60_000;

describe('deploySyncIntervalMs', () => {
  it('defaults to a 5-minute floor at the default probe interval', () => {
    expect(deploySyncIntervalMs(envConfig(process.env), MIN)).toBe(300_000); // max(5min, 5×60s) = 5min
  });

  it('scales to 5× the probe interval when that exceeds the 5-minute floor', () => {
    expect(deploySyncIntervalMs(envConfig(process.env), 120_000)).toBe(600_000); // 5×120s = 10min > floor
  });

  it('honors a positive DEPLOY_SYNC_SECONDS override', () => {
    process.env.DEPLOY_SYNC_SECONDS = '90';
    expect(deploySyncIntervalMs(envConfig(process.env), MIN)).toBe(90_000);
  });

  it('ignores a blank/zero/non-numeric override and falls back to the default', () => {
    for (const bad of ['', '0', '-5', 'abc']) {
      process.env.DEPLOY_SYNC_SECONDS = bad;
      expect(deploySyncIntervalMs(envConfig(process.env), MIN)).toBe(300_000);
    }
  });
});
