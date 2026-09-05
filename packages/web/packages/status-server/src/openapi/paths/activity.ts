import { BEARER, okJson, ref, errors, queryParam, type Paths } from '../shared';

// ---------------------------------------------------------------------------
// The activity feed's cold scroll-back path (src/routes/activity.ts), behind the
// app-wide requireAuth seam.
//
//   GET /activity   one cursor-paged page of the feed, older than the given (before,
//                    beforeId) cursor. `GET /board`'s `activity` field still carries the
//                    newest page — this route exists only for scrolling BACK, so it is a
//                    cold path: nothing polls it and no SSE publish touches it. View
//                    tier, same as `GET /board`.
// ---------------------------------------------------------------------------

const tag = 'board';

export const activityPaths: Paths = {
  '/activity': {
    get: {
      tags: [tag],
      summary: "One cursor-paged page of the activity feed, older than the given cursor",
      description:
        'The cursor is the (before, beforeId) PAIR because a deployment\'s build and deploy ' +
        'rows share a timestamp. Both halves are required together — half a cursor is a ' +
        'client bug, and answering it with the newest page would silently restart the ' +
        'scroll at the top, so a lone half 400s. An empty `beforeId` alongside a `before` is ' +
        'still a valid cursor: it is the pagination stall escape the server itself mints ' +
        'when a full page of events shares one millisecond.',
      security: BEARER,
      parameters: [
        queryParam('before'),
        queryParam('beforeId'),
        queryParam('limit'),
      ],
      responses: {
        200: okJson('One page of the activity feed, oldest-first', {
          type: 'object',
          required: ['rows', 'nextCursor'],
          properties: {
            // Same row schema `GET /board`'s `activity` field uses — declared once in
            // board.ts and referenced here, not restated.
            rows: { type: 'array', items: ref('ActivityRow') },
            nextCursor: {
              type: ['object', 'null'],
              required: ['atMs', 'id'],
              properties: {
                atMs: { type: 'number' },
                id: { type: 'string' },
              },
            },
          },
        }),
        ...errors(400, 401),
      },
    },
  },
};
