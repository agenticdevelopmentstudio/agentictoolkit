import { describe, it, expect } from 'vitest';
import { envConfig } from '../src/config/env';

describe('envConfig crosses the monitor-worker boundary', () => {
  // The host hands the SAME config object to the worker as workerData, which is a
  // structured clone: a method on the config throws DataCloneError at the first
  // cycle, in the container, where no type-check can see it. Keep it plain data.
  it('survives structuredClone with every field, and resolves an integration-named secret', () => {
    const config = envConfig({
      DATABASE_URL: 'file:/tmp/x.db',
      NODE_ENV: 'test',
      STATUS_TEST_VERCEL_TOKEN: 'tok_from_an_integration_row',
    });
    const cloned = structuredClone(config);
    expect(cloned.secrets.STATUS_TEST_VERCEL_TOKEN).toBe('tok_from_an_integration_row');
    expect(cloned.credentials).toEqual(config.credentials);
    expect(Object.keys(cloned).sort()).toEqual(Object.keys(config).sort());
    for (const [key, value] of Object.entries(config)) {
      expect(typeof value, `StatusConfig.${key} must be data, not a function`).not.toBe('function');
    }
  });
});
