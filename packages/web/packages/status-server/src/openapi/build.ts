/* eslint-disable @typescript-eslint/no-explicit-any --
 * An OpenAPI document is an open-ended JSON structure; assembling the doc by merging
 * hand-written path/schema fragments with the auto-generated one needs `any`. No
 * client input flows through here — every fragment is a static, trusted document
 * piece derived from the route zod schemas. */
import type { OpenAPIHono } from '@hono/zod-openapi';
import { type Paths, type Schemas } from './shared';
// Hand-written path modules — one per plain-Hono route file. Each exports a
// `<name>Paths` (path → operation map) and, where it introduces named response
// shapes, a `<name>Schemas` (component schemas). The drift guard
// (test/openapi.test.ts) fails if any mounted route is missing from these, so this
// list IS the documented surface for every route that isn't a native `.openapi()`
// one. (GET /health, GET /version, GET /public/status-summary and the two /cron/*
// routes are `.openapi()`-registered, so getOpenAPI31Document documents them for us.)
import { readsPaths, readsSchemas } from './paths/reads';
import { boardPaths, boardSchemas } from './paths/board';
import { activityPaths } from './paths/activity';
import { configPaths, configSchemas } from './paths/config';
import { telemetryPaths, telemetrySchemas } from './paths/telemetry';
import { fleetPaths, fleetSchemas } from './paths/fleet';
import { usersPaths } from './paths/users';
import { authPaths, authSchemas } from './paths/auth';
import { tokensPaths, tokensSchemas } from './paths/tokens';
import { devicePaths } from './paths/device';
import { streamPaths } from './paths/stream';
import { badgePaths } from './paths/badge';
import { autoConfigurePaths } from './paths/autoConfigure';
import { hooksPaths } from './paths/hooks';

// Each route file is registered ONCE as a {paths, schemas} pair, so a new module is
// a single array entry and its paths + component schemas can't drift out of lockstep.
const MODULES: { paths: Paths; schemas?: Schemas }[] = [
  { paths: readsPaths, schemas: readsSchemas },
  { paths: boardPaths, schemas: boardSchemas },
  { paths: activityPaths },
  { paths: configPaths, schemas: configSchemas },
  { paths: telemetryPaths, schemas: telemetrySchemas },
  { paths: fleetPaths, schemas: fleetSchemas },
  { paths: usersPaths },
  { paths: authPaths, schemas: authSchemas },
  { paths: tokensPaths, schemas: tokensSchemas },
  { paths: devicePaths },
  { paths: streamPaths },
  { paths: badgePaths },
  { paths: autoConfigurePaths },
  { paths: hooksPaths },
];
const HAND_WRITTEN_PATHS: Paths = Object.assign({}, ...MODULES.map((m) => m.paths));
const HAND_WRITTEN_SCHEMAS: Schemas = Object.assign({}, ...MODULES.map((m) => m.schemas ?? {}));

// The standard error envelope every documented 4xx/5xx references (shared.errorResponse
// points at `#/components/schemas/Error`). Shape mirrors the app's error handler.
const COMPONENT_SCHEMAS: Record<string, any> = {
  Error: {
    type: 'object',
    properties: {
      error: {
        type: 'object',
        properties: {
          message: { type: 'string' },
          code: { type: 'string' },
        },
      },
    },
  },
};

/**
 * Build the full OpenAPI 3.1 document. The version/info + the native `.openapi()`
 * routes (health, version, public status summary, and the merged /cron/* pair) come
 * from getOpenAPI31Document; every plain-Hono route is documented by the hand-written
 * modules above and merged in. The auto-generated entries WIN on any path/schema key
 * collision (they are the source of truth for the routes they cover).
 */
export function buildOpenApiSpec(app: OpenAPIHono<any>, version: string): unknown {
  const doc: any = app.getOpenAPI31Document({
    openapi: '3.1.0',
    info: { title: 'status-backend', version },
  });

  doc.paths = { ...HAND_WRITTEN_PATHS, ...doc.paths };

  doc.components = doc.components ?? {};
  doc.components.schemas = { ...COMPONENT_SCHEMAS, ...HAND_WRITTEN_SCHEMAS, ...doc.components.schemas };
  doc.components.securitySchemes = {
    ...doc.components.securitySchemes,
    bearerAuth: { type: 'http', scheme: 'bearer' },
  };

  return doc;
}
