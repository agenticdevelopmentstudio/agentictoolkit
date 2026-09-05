import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import type { Db } from '../src/libsql/client';
import type { Scheduler } from '../src/scheduler';
import { createApp } from '../src/app';
import { buildOpenApiSpec } from '../src/openapi/build';
import { normHonoPath } from '../src/openapi/route-key';
import { PERMANENTLY_UNDOCUMENTED } from './openapi-exclusions';
import { testConfig } from './helpers/config';

// Registration never touches the db/scheduler (only handlers do), so stubs are
// enough to read app.routes and build the spec. A truthy scheduler ensures the
// conditionally-mounted /cron/* routes are present (they're gated on opts.scheduler).
const config = testConfig();
const app = createApp({ db: {} as unknown as Db, scheduler: {} as unknown as Scheduler, config });
const spec = buildOpenApiSpec(app, config.appVersion) as {
  openapi: string;
  components: { securitySchemes: Record<string, { scheme: string }> };
  paths: Record<string, Record<string, unknown>>;
};

describe('OpenAPI spec generation', () => {
  it('is OpenAPI 3.1 with bearer security', () => {
    expect(spec.openapi).toBe('3.1.0');
    expect(spec.components.securitySchemes.bearerAuth.scheme).toBe('bearer');
  });
});

// Drift guard. The documented surface is derived from the REAL app: every route
// createApp() registers must be documented in the spec or permanently excluded
// (test/openapi-exclusions.ts). There is NO backlog fixture — a newly mounted,
// undocumented route fails the suite the moment it is added.
describe('OpenAPI spec stays in sync with the routes', () => {
  const registered = new Set<string>();
  for (const r of app.routes) {
    if (r.method === 'ALL') continue; // .use() middleware, not an operation
    registered.add(`${r.method.toUpperCase()} ${normHonoPath(r.path)}`);
  }
  const documented = new Set<string>();
  for (const [path, item] of Object.entries(spec.paths)) {
    for (const m of Object.keys(item)) {
      if (['get', 'post', 'put', 'patch', 'delete'].includes(m)) {
        documented.add(`${m.toUpperCase()} ${path}`);
      }
    }
  }

  it('documents no phantom routes — every documented op maps to a registered route', () => {
    // Catches a path typo or stale entry in src/openapi/paths/* that documents a
    // route createApp() never registers (which would 404 for every caller).
    const phantom = [...documented].filter((op) => !registered.has(op)).sort();
    expect(
      phantom,
      `OpenAPI documents routes that are not registered by createApp() — fix the path ` +
        `string in src/openapi/build.ts or src/openapi/paths/*:\n  ${phantom.join('\n  ')}`,
    ).toEqual([]);
  });

  it('every registered route is documented or permanently excluded (no backlog)', () => {
    const undocumented = [...registered]
      .filter((op) => !documented.has(op) && !PERMANENTLY_UNDOCUMENTED.has(op))
      .sort();
    expect(
      undocumented,
      `These routes are registered by createApp() but absent from the OpenAPI spec. ` +
        `Document them in a src/openapi/paths/* module (assembled by src/openapi/build.ts). ` +
        `If a route is intentionally never documented, add it to test/openapi-exclusions.ts:\n  ` +
        `${undocumented.join('\n  ')}`,
    ).toEqual([]);
  });

  it('the committed openapi.json matches a fresh build (re-run: pnpm openapi:dump)', () => {
    // The tracked websites/main/openapi.json is what `pnpm openapi:dump` writes;
    // this pins it to the code so it can never silently drift. dump-openapi.ts builds
    // with NO scheduler (createApp({ db, config: testConfig() })), so the committed artifact omits the
    // scheduler-gated /cron/* routes — build it the SAME way here for an apples-to-
    // apples compare. (The drift guard above still covers /cron via the scheduler-
    // stubbed `app`, so cron isn't left unchecked.)
    const dumpSpec = buildOpenApiSpec(createApp({ db: {} as unknown as Db, config }), config.appVersion);
    const committedPath = resolve(dirname(fileURLToPath(import.meta.url)), '../openapi.json');
    const committed = JSON.parse(readFileSync(committedPath, 'utf8')) as { info: Record<string, unknown> };
    // info.version derives from APP_VERSION at build time — normalize it so this
    // structural check doesn't flake when CI injects a version string.
    const pinVersion = (s: { info: Record<string, unknown> }) => ({
      ...s,
      info: { ...s.info, version: '0.0.0' },
    });
    expect(
      pinVersion(committed),
      'websites/main/openapi.json is out of date — re-run: pnpm openapi:dump (and commit).',
    ).toEqual(pinVersion(dumpSpec as { info: Record<string, unknown> }));
  });
});
