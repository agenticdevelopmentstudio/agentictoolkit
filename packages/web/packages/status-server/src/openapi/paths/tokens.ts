import { BEARER, jsonBody, okJson, ref, errors, pathParam, zodJson, type Paths, type Schemas } from '../shared';
import { createSchema } from '../../routes/tokens';

// ---------------------------------------------------------------------------
// API-token management (src/routes/tokens.ts), behind the app-wide requireAuth
// seam. Minting requires a SESSION user (an API token cannot mint another) → 403.
// The raw token value is returned exactly once, on create.
// ---------------------------------------------------------------------------

const tag = 'tokens';

export const tokensSchemas: Schemas = {
  // ApiTokenMeta (storage/token-store.ts) — never includes the secret value.
  ApiTokenMeta: {
    type: 'object',
    required: ['id', 'name', 'role', 'kind', 'prefix', 'createdBy', 'createdAt', 'lastUsedAt', 'expiresAt', 'revokedAt'],
    properties: {
      id: { type: 'string' },
      name: { type: 'string' },
      role: { type: 'string', enum: ['admin', 'user'] },
      kind: { type: 'string', enum: ['minted', 'device'] },
      prefix: { type: 'string' },
      createdBy: { type: 'string' },
      createdAt: { type: 'string' },
      lastUsedAt: { type: ['string', 'null'] },
      expiresAt: { type: ['string', 'null'] },
      revokedAt: { type: ['string', 'null'] },
    },
  },
};

export const tokensPaths: Paths = {
  '/tokens': {
    get: {
      tags: [tag],
      summary: 'List the API tokens the caller can see',
      security: BEARER,
      responses: {
        200: okJson('Token metadata', { type: 'array', items: ref('ApiTokenMeta') }),
        ...errors(401),
      },
    },
    post: {
      tags: [tag],
      summary: 'Mint an API token (returns the raw value once); requires a session user',
      security: BEARER,
      requestBody: { required: true, ...jsonBody(zodJson(createSchema)) },
      responses: {
        201: okJson('The token metadata plus the raw value (shown once)', {
          allOf: [
            ref('ApiTokenMeta'),
            { type: 'object', required: ['token'], properties: { token: { type: 'string' } } },
          ],
        }),
        ...errors(400, 401, 403),
      },
    },
  },
  '/tokens/{id}': {
    delete: {
      tags: [tag],
      summary: 'Revoke an API token',
      security: BEARER,
      parameters: [pathParam('id')],
      responses: { 204: { description: 'Revoked' }, ...errors(401, 403, 404) },
    },
  },
};
