import { BEARER, okJson, ref, errors, type Paths, type Schemas } from '../shared';

// ---------------------------------------------------------------------------
// The fleet view (src/routes/fleet.ts), behind the app-wide requireAuth seam.
// Returns this monitor's own compact snapshot plus the latest stored snapshot per
// peer, each annotated with freshness (FleetMember in src/peers/fleet.ts).
// ---------------------------------------------------------------------------

export const fleetSchemas: Schemas = {
  FleetMember: {
    type: 'object',
    required: ['self', 'label', 'baseUrl', 'overall', 'reachable', 'fetchedAt', 'payload'],
    properties: {
      self: { type: 'boolean' },
      label: { type: 'string' },
      baseUrl: { type: ['string', 'null'] },
      overall: { type: ['string', 'null'] },
      reachable: { type: 'boolean' },
      fetchedAt: { type: 'string' },
      // The peer's (or self's) compact snapshot body — opaque here (CompactSnapshot).
      payload: {},
    },
  },
};

export const fleetPaths: Paths = {
  '/fleet': {
    get: {
      tags: ['fleet'],
      summary: 'This monitor plus every peer, each with its latest snapshot + freshness',
      security: BEARER,
      responses: {
        200: okJson('The fleet members', { type: 'array', items: ref('FleetMember') }),
        ...errors(401),
      },
    },
  },
};
