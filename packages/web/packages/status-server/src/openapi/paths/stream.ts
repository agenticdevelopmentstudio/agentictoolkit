import { BEARER, okJson, errors, type Paths } from '../shared';

// ---------------------------------------------------------------------------
// The live channel (src/routes/stream.ts), behind the app-wide requireAuth seam.
// /live/stream is a Server-Sent Events feed; /live/check triggers an out-of-band
// probe cycle (503 when this instance has no scheduler, debounced per user).
// ---------------------------------------------------------------------------

const tag = 'stream';

export const streamPaths: Paths = {
  '/live/stream': {
    get: {
      tags: [tag],
      summary: 'Server-Sent Events feed of live snapshots',
      security: BEARER,
      responses: {
        200: {
          description: 'An SSE stream (text/event-stream) of snapshot events',
          content: { 'text/event-stream': { schema: { type: 'string' } } },
        },
        ...errors(401),
      },
    },
  },
  '/live/check': {
    post: {
      tags: [tag],
      summary: 'Trigger an immediate probe cycle (debounced; 503 without a scheduler)',
      security: BEARER,
      responses: {
        200: okJson('Whether a cycle ran (or was debounced)', {
          type: 'object',
          required: ['ok', 'ran'],
          properties: {
            ok: { type: 'boolean' },
            ran: { type: 'boolean' },
            reason: { type: 'string', enum: ['debounced'] },
          },
        }),
        ...errors(401),
        503: okJson('No scheduler on this instance', {
          type: 'object',
          required: ['ok', 'ran', 'reason'],
          properties: {
            ok: { type: 'boolean', enum: [false] },
            ran: { type: 'boolean', enum: [false] },
            reason: { type: 'string', enum: ['no scheduler'] },
          },
        }),
      },
    },
  },
};
