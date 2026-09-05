import { BEARER, jsonBody, okJson, errors, queryParam, zodJson, type Paths } from '../shared';
import { requestSchema, tokenSchema, userCodeSchema } from '../../routes/device';

// ---------------------------------------------------------------------------
// OAuth 2.0 Device Authorization flow (src/routes/device.ts). The two /auth/device
// endpoints (request + poll) are PUBLIC (pre-seam) — a CLI with no session hits
// them. The pending/approve/deny trio is POST-SEAM: a signed-in user approves a
// pending device from their browser, so those carry the bearer scheme.
// ---------------------------------------------------------------------------

const tag = 'device';

export const devicePaths: Paths = {
  '/auth/device': {
    post: {
      tags: [tag],
      summary: 'Start a device authorization: issue a device_code + user_code pair',
      requestBody: { ...jsonBody(zodJson(requestSchema)) },
      responses: {
        201: okJson('The device + user codes and polling parameters', {
          type: 'object',
          required: ['device_code', 'user_code', 'verification_uri', 'interval', 'expires_in'],
          properties: {
            device_code: { type: 'string' },
            user_code: { type: 'string' },
            verification_uri: { type: 'string' },
            interval: { type: 'number' },
            expires_in: { type: 'number' },
          },
        }),
      },
    },
  },
  '/auth/device/token': {
    post: {
      tags: [tag],
      summary: 'Poll for the device token — pending/slow_down/denied/expired, or the granted token',
      requestBody: { required: true, ...jsonBody(zodJson(tokenSchema)) },
      responses: {
        200: okJson('A pending/error status, or the granted token', {
          type: 'object',
          properties: {
            error: { type: 'string', enum: ['authorization_pending', 'slow_down', 'denied', 'expired'] },
            token: { type: 'string' },
            role: { type: 'string', enum: ['admin', 'user'] },
            expires_at: { type: ['string', 'null'] },
          },
        }),
      },
    },
  },
  '/auth/device/pending': {
    get: {
      tags: [tag],
      summary: 'Look up a pending device authorization by its user_code',
      security: BEARER,
      parameters: [queryParam('user_code', true)],
      responses: {
        200: okJson('The pending device request', {
          type: 'object',
          required: ['label', 'status', 'createdAt', 'expiresAt'],
          properties: {
            label: { type: ['string', 'null'] },
            status: { type: 'string' },
            createdAt: { type: 'string' },
            expiresAt: { type: 'string' },
          },
        }),
        ...errors(400, 401, 404),
      },
    },
  },
  '/auth/device/approve': {
    post: {
      tags: [tag],
      summary: 'Approve a pending device authorization',
      security: BEARER,
      requestBody: { required: true, ...jsonBody(zodJson(userCodeSchema)) },
      responses: {
        200: okJson('Approved', {
          type: 'object',
          required: ['status'],
          properties: { status: { type: 'string', enum: ['approved'] } },
        }),
        ...errors(400, 401, 403, 404, 409),
      },
    },
  },
  '/auth/device/deny': {
    post: {
      tags: [tag],
      summary: 'Deny a pending device authorization',
      security: BEARER,
      requestBody: { required: true, ...jsonBody(zodJson(userCodeSchema)) },
      responses: {
        200: okJson('Denied', {
          type: 'object',
          required: ['status'],
          properties: { status: { type: 'string', enum: ['denied'] } },
        }),
        ...errors(400, 401, 403, 404, 409),
      },
    },
  },
};
