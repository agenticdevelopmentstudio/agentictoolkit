import { describe, it, expect, afterEach, vi } from 'vitest';
import { envConfig } from '../src/config/env';
import { STATUS_CREDENTIAL_NAMES } from '../src/config/port';

afterEach(() => {
  vi.unstubAllEnvs();
});

describe('envConfig', () => {
  describe('production escape-hatch guard (SEC-M5)', () => {
    it('throws when AUTH_DISABLED=1 in production', () => {
      vi.stubEnv('NODE_ENV', 'production');
      vi.stubEnv('AUTH_DISABLED', '1');
      expect(() => envConfig(process.env)).toThrow(/AUTH_DISABLED/);
    });

    it('throws when COOKIE_INSECURE=1 in production', () => {
      vi.stubEnv('NODE_ENV', 'production');
      vi.stubEnv('COOKIE_INSECURE', '1');
      expect(() => envConfig(process.env)).toThrow(/COOKIE_INSECURE/);
    });

    it('allows either escape hatch outside production', () => {
      vi.stubEnv('NODE_ENV', 'test');
      vi.stubEnv('AUTH_DISABLED', '1');
      vi.stubEnv('COOKIE_INSECURE', '1');
      expect(() => envConfig(process.env)).not.toThrow();
    });
  });

  describe('credentials', () => {
    it('maps every STATUS_CREDENTIAL_NAMES entry from its like-named env var', () => {
      for (const name of STATUS_CREDENTIAL_NAMES) vi.stubEnv(name, `value-for-${name}`);
      const { credentials } = envConfig(process.env);
      for (const name of STATUS_CREDENTIAL_NAMES) {
        expect(credentials[name]).toBe(`value-for-${name}`);
      }
    });

    it('leaves an unset credential undefined rather than defaulting it', () => {
      for (const name of STATUS_CREDENTIAL_NAMES) vi.stubEnv(name, undefined);
      const { credentials } = envConfig(process.env);
      for (const name of STATUS_CREDENTIAL_NAMES) {
        expect(credentials[name]).toBeUndefined();
      }
    });
  });

  describe('deploySyncSeconds', () => {
    it('rejects zero and negative overrides, deferring to the derived cadence', () => {
      for (const bad of ['0', '-5']) {
        vi.stubEnv('DEPLOY_SYNC_SECONDS', bad);
        expect(envConfig(process.env).deploySyncSeconds).toBeNull();
      }
    });

    it('accepts a positive override', () => {
      vi.stubEnv('DEPLOY_SYNC_SECONDS', '900');
      expect(envConfig(process.env).deploySyncSeconds).toBe(900);
    });

    it('is null when unset', () => {
      vi.stubEnv('DEPLOY_SYNC_SECONDS', undefined);
      expect(envConfig(process.env).deploySyncSeconds).toBeNull();
    });
  });

  describe('glitchtipProjects', () => {
    it('is null when GLITCHTIP_PROJECTS is unset — meaning every project the org returns', () => {
      vi.stubEnv('GLITCHTIP_PROJECTS', undefined);
      expect(envConfig(process.env).glitchtipProjects).toBeNull();
    });

    it('is null for a mistaken all-comma value rather than an empty allowlist', () => {
      vi.stubEnv('GLITCHTIP_PROJECTS', ',,');
      expect(envConfig(process.env).glitchtipProjects).toBeNull();
    });

    it('splits a comma-separated value into a trimmed allowlist', () => {
      vi.stubEnv('GLITCHTIP_PROJECTS', 'proj-a, proj-b');
      expect(envConfig(process.env).glitchtipProjects).toEqual(['proj-a', 'proj-b']);
    });
  });

  describe('monitorLabel', () => {
    it('is left alone in production', () => {
      vi.stubEnv('MONITOR_LABEL', 'adh-status');
      vi.stubEnv('RAILWAY_ENVIRONMENT_NAME', 'production');
      expect(envConfig(process.env).monitorLabel).toBe('adh-status');
    });

    it('is left alone with no RAILWAY_ENVIRONMENT_NAME', () => {
      vi.stubEnv('MONITOR_LABEL', 'adh-status');
      vi.stubEnv('RAILWAY_ENVIRONMENT_NAME', undefined);
      expect(envConfig(process.env).monitorLabel).toBe('adh-status');
    });

    it('qualifies the label with a non-production RAILWAY_ENVIRONMENT_NAME', () => {
      vi.stubEnv('MONITOR_LABEL', 'adh-status');
      vi.stubEnv('RAILWAY_ENVIRONMENT_NAME', 'testing');
      expect(envConfig(process.env).monitorLabel).toBe('adh-status (testing)');
    });

    it('does not double-qualify a label that already names its environment', () => {
      vi.stubEnv('MONITOR_LABEL', 'adh-status-testing');
      vi.stubEnv('RAILWAY_ENVIRONMENT_NAME', 'testing');
      expect(envConfig(process.env).monitorLabel).toBe('adh-status-testing');
    });
  });
});
