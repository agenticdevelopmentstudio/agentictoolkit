import { describe, it, expect } from 'vitest';
import { correlateDeployProjects, type EndpointWiring } from '../src/routes/reads';
import type { EnumeratedProject } from '@agentic-toolkit/deploy-platform/enumerate';

// ---------------------------------------------------------------------------
// `wired` is a CONFIGURATION fact, not a runtime one.
//
// The bug this pins: the correlation used to read the PROBE list
// (`listActiveEndpoints`), so a monitor with monitoring switched off vanished from it
// and its deploy project read "not monitored" — the Auto Configure banner nagged about
// a project that is already set up ("1 project not monitored"), and a run would have
// created a SECOND monitor for a URL that already has one. A paused monitor still
// CLAIMS its project; `listEndpointsForWiring` therefore feeds this every endpoint,
// and pause state stays with the probe list.
// ---------------------------------------------------------------------------

const proj = (over: Partial<EnumeratedProject> = {}): EnumeratedProject => ({
  platform: 'vercel',
  projectName: 'p',
  environment: null,
  domain: 'p.example.com',
  domains: ['p.example.com'],
  gitRepo: null,
  gitBranch: null,
  rootDirectory: null,
  framework: null,
  ...over,
});

const ep = (over: Partial<EndpointWiring> = {}): EndpointWiring => ({
  platform: 'vercel',
  deployProject: 'p',
  environment: 'production',
  url: 'https://p.example.com',
  ...over,
});

/** The single project's flags, for the common one-in-one-out case. */
function only(enumerated: EnumeratedProject[], eps: EndpointWiring[], ignored: { platform: string; projectName: string }[] = []) {
  const rows = correlateDeployProjects(enumerated, eps, ignored);
  expect(rows).toHaveLength(enumerated.length);
  return rows[0]!;
}

describe('correlateDeployProjects — wired', () => {
  it('a project some endpoint names is wired', () => {
    expect(only([proj()], [ep()]).wired).toBe(true);
  });

  it('a project NO endpoint names is not wired', () => {
    expect(only([proj()], [ep({ deployProject: 'other' })]).wired).toBe(false);
  });

  it('an endpoint with no wiring at all claims nothing', () => {
    expect(only([proj()], [ep({ platform: null, deployProject: null })]).wired).toBe(false);
  });

  it('a PAUSED monitor still claims its project — the caller passes every endpoint, active or not', () => {
    // The wiring list carries no `isActive`: that is the point. A paused monitor is
    // indistinguishable here from a running one, so the project can never read
    // "not monitored" merely because its monitor is switched off.
    expect(only([proj()], [ep()]).wired).toBe(true);
  });

  it('keys Railway per ENVIRONMENT — one env wired leaves the others alone', () => {
    const rows = correlateDeployProjects(
      [
        proj({ platform: 'railway', projectName: 'adh-backend', environment: 'scratch1', domain: 'adh-testing-scratch1.up.railway.app', domains: ['adh-testing-scratch1.up.railway.app'] }),
        proj({ platform: 'railway', projectName: 'adh-backend', environment: 'production', domain: 'adh.up.railway.app', domains: ['adh.up.railway.app'] }),
      ],
      [ep({ platform: 'railway', deployProject: 'adh-backend', environment: 'scratch1', url: 'https://adh-testing-scratch1.up.railway.app' })],
      [],
    );
    expect(rows.map((r) => [r.environment, r.wired])).toEqual([
      ['scratch1', true],
      ['production', false],
    ]);
  });

  it('attributes a Railway endpoint by HOST when its stored env says otherwise', () => {
    // The historic shape: a provider host has no env prefix, so the endpoint was tagged
    // "production" by host-parsing while it actually monitors the scratch1 environment.
    const rows = correlateDeployProjects(
      [
        proj({ platform: 'railway', projectName: 'adh-backend', environment: 'scratch1', domain: 'adh-testing-scratch1.up.railway.app', domains: ['adh-testing-scratch1.up.railway.app'] }),
      ],
      [ep({ platform: 'railway', deployProject: 'adh-backend', environment: 'production', url: 'https://adh-testing-scratch1.up.railway.app' })],
      [],
    );
    expect(rows[0]!.wired).toBe(true);
  });

  it('ignores environment for Vercel — the project name carries it', () => {
    expect(only([proj({ projectName: 'site-staging' })], [ep({ deployProject: 'site-staging', environment: 'staging' })]).wired).toBe(true);
    expect(only([proj({ projectName: 'site-staging' })], [ep({ deployProject: 'site-staging', environment: 'production' })]).wired).toBe(true);
  });
});

describe('correlateDeployProjects — ignored', () => {
  it('is project-level: every environment entry of an ignored project reads ignored', () => {
    const rows = correlateDeployProjects(
      [
        proj({ platform: 'railway', projectName: 'infra', environment: 'production' }),
        proj({ platform: 'railway', projectName: 'infra', environment: 'staging' }),
      ],
      [],
      [{ platform: 'railway', projectName: 'infra' }],
    );
    expect(rows.every((r) => r.ignored)).toBe(true);
  });

  it('matches on the CANONICAL platform (cloudflare-pages ≡ cloudflare)', () => {
    expect(only([proj({ platform: 'cloudflare-pages', projectName: 'w' })], [], [{ platform: 'cloudflare', projectName: 'w' }]).ignored).toBe(true);
  });
});
