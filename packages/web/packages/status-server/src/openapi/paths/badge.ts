import { BEARER, errors, type Paths } from '../shared';

// ---------------------------------------------------------------------------
// The status badge (src/routes/badge.ts), behind the app-wide requireAuth seam.
// Returns an SVG shields-style badge; falls back to an "unknown" badge on error.
// ---------------------------------------------------------------------------

export const badgePaths: Paths = {
  '/status/badge.svg': {
    get: {
      tags: ['badge'],
      summary: 'An SVG status badge for the overall portfolio',
      security: BEARER,
      responses: {
        200: {
          description: 'The badge as an SVG image',
          content: { 'image/svg+xml': { schema: { type: 'string' } } },
        },
        ...errors(401),
      },
    },
  },
};
