import { jsonBody, okJson, okFlag, ref, errors, queryParam, zodJson, type Paths, type Schemas } from '../shared';
import { signupBody, loginBody } from '../../routes/auth';

// ---------------------------------------------------------------------------
// The auth surface (src/routes/auth.ts + src/auth/github.ts). These are mounted
// PRE-SEAM (before the app-wide requireAuth), so they are public: signup/login
// establish a session, logout clears it, /me reports the current principal (a
// session user, an API-token principal, or nobody). The GitHub OAuth pair only
// redirects (302). No bearer security is documented here.
// ---------------------------------------------------------------------------

const tag = 'auth';

/** A 302 redirect response with a Location header (used by the OAuth pair). */
const redirect = (description: string) => ({
  description,
  headers: { Location: { schema: { type: 'string' }, description: 'Redirect target' } },
});

export const authSchemas: Schemas = {
  // AuthUser (storage/auth-store.ts): the public shape of a status account.
  StatusUser: {
    type: 'object',
    required: ['id', 'email', 'displayName', 'role'],
    properties: {
      id: { type: 'string' },
      email: { type: 'string' },
      displayName: { type: 'string' },
      role: { type: 'string', enum: ['pending', 'viewer', 'admin'] },
    },
  },
};

export const authPaths: Paths = {
  '/auth/signup': {
    post: {
      tags: [tag],
      summary: 'Create a status account (starts pending until an admin promotes it)',
      requestBody: { required: true, ...jsonBody(zodJson(signupBody)) },
      responses: {
        201: okJson('The created user', { type: 'object', required: ['user'], properties: { user: ref('StatusUser') } }),
        ...errors(400, 409),
      },
    },
  },
  '/auth/login': {
    post: {
      tags: [tag],
      summary: 'Exchange email + password for a session cookie',
      requestBody: { required: true, ...jsonBody(zodJson(loginBody)) },
      responses: {
        200: okJson('The signed-in user', { type: 'object', required: ['user'], properties: { user: ref('StatusUser') } }),
        ...errors(400, 401),
      },
    },
  },
  '/auth/logout': {
    post: { tags: [tag], summary: 'Clear the session cookie', responses: { 200: okFlag } },
  },
  '/auth/me': {
    get: {
      tags: [tag],
      summary: 'The current principal: a session user, an API-token principal, or neither',
      responses: {
        200: okJson('The current principal', {
          type: 'object',
          properties: {
            user: { ...ref('StatusUser'), description: 'Present when a session user is signed in' },
            principal: {
              type: 'object',
              description: 'Present when the caller is an API token rather than a session user',
              required: ['kind', 'role', 'name', 'expiresAt'],
              properties: {
                kind: { type: 'string', enum: ['token'] },
                role: { type: 'string', enum: ['admin', 'user'] },
                name: { type: 'string' },
                expiresAt: { type: ['string', 'null'] },
              },
            },
          },
        }),
      },
    },
  },
  '/auth/github/start': {
    get: {
      tags: [tag],
      summary: 'Begin the GitHub OAuth flow (redirects to GitHub)',
      responses: { 302: redirect('Redirect to GitHub authorize'), ...errors(500) },
    },
  },
  '/auth/github/callback': {
    get: {
      tags: [tag],
      summary: 'GitHub OAuth callback — establishes the session then redirects home',
      parameters: [queryParam('code'), queryParam('state')],
      responses: { 302: redirect('Redirect to /home'), ...errors(400, 502) },
    },
  },
};
