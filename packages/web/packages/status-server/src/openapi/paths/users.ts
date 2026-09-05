import { BEARER, jsonBody, okJson, okFlag, ref, errors, pathParam, zodJson, type Paths } from '../shared';
import { roleBody } from '../../routes/users';

// ---------------------------------------------------------------------------
// User administration (src/routes/users.ts). Behind the app-wide requireAuth seam
// AND a router-wide requireAdmin, so every op carries the bearer scheme + 403.
// Reuses the StatusUser component defined in the auth module.
// ---------------------------------------------------------------------------

const tag = 'users';

export const usersPaths: Paths = {
  '/users': {
    get: {
      tags: [tag],
      summary: 'List every status account',
      security: BEARER,
      responses: {
        200: okJson('The users', { type: 'array', items: ref('StatusUser') }),
        ...errors(401, 403),
      },
    },
  },
  '/users/{id}': {
    patch: {
      tags: [tag],
      summary: "Change a user's role",
      security: BEARER,
      parameters: [pathParam('id')],
      requestBody: { required: true, ...jsonBody(zodJson(roleBody)) },
      responses: {
        200: okJson('The updated user', ref('StatusUser')),
        ...errors(400, 401, 403, 404, 409),
      },
    },
    delete: {
      tags: [tag],
      summary: 'Delete a user',
      security: BEARER,
      parameters: [pathParam('id')],
      responses: { 200: okFlag, ...errors(401, 403, 404, 409) },
    },
  },
};
