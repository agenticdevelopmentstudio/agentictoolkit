import { BEARER, jsonBody, okJson, errors, zodJson, type Paths } from '../shared';
import { autoConfigureBody } from '../../routes/auto-configure';

// ---------------------------------------------------------------------------
// One-shot auto-configuration (src/routes/auto-configure.ts). Behind the app-wide
// requireAuth seam AND a per-route requireAdmin, so it carries the bearer scheme
// plus a 403. Enumerates deploy projects, adds/creates/wires the matchable ones.
// ---------------------------------------------------------------------------

export const autoConfigurePaths: Paths = {
  '/auto-configure': {
    post: {
      tags: ['auto-configure'],
      summary: 'Enumerate deploy projects and add/create/wire the matchable ones',
      security: BEARER,
      requestBody: { ...jsonBody(zodJson(autoConfigureBody)) },
      responses: {
        200: okJson('Counts of what changed', {
          type: 'object',
          required: ['added', 'created', 'wired', 'skipped', 'noDomain'],
          properties: {
            added: { type: 'number' },
            created: { type: 'number' },
            wired: { type: 'number' },
            skipped: { type: 'number' },
            noDomain: { type: 'number' },
          },
        }),
        ...errors(400, 401, 403),
      },
    },
  },
};
