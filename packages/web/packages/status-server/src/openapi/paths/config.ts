import { BEARER, jsonBody, okJson, okFlag, ref, errors, pathParam, zodJson, type Paths, type Schemas } from '../shared';
import {
  siteGroupInsert, siteGroupPatch,
  monitoredSiteInsert, monitoredSitePatch,
  monitoredEndpointInsert, monitoredEndpointPatch,
  deployIntegrationInsert, deployIntegrationPatch,
  ignoredProjectInsert,
  peerInsert, peerPatch,
} from '../../routes/config';

// ---------------------------------------------------------------------------
// The admin configuration CRUD (src/routes/config.ts), mounted at /config and
// gated by a router-wide requireAdmin behind the app-wide requireAuth seam — so
// every op carries the bearer scheme + 401 + 403. Request bodies REUSE the route's
// own drizzle-zod insert/patch schemas (exported from config.ts). Each persisted
// row's response shape is the insert schema plus the server-managed columns.
// ---------------------------------------------------------------------------

const tag = 'config';

/** A persisted row = the insert fields plus the server-managed id/timestamps. The
 *  insert JSON is the SAME schema the handler validates writes against; here we add
 *  the columns `.omit()` dropped. `updatedAt:false` for the append-only ignored list. */
const rowSchema = (insertJson: unknown, updatedAt = true) => ({
  allOf: [
    insertJson,
    {
      type: 'object',
      required: updatedAt ? ['id', 'createdAt', 'updatedAt'] : ['id', 'createdAt'],
      properties: {
        id: { type: 'string' },
        createdAt: { type: 'string' },
        ...(updatedAt ? { updatedAt: { type: 'string' } } : {}),
      },
    },
  ],
});

export const configSchemas: Schemas = {
  SiteGroupRow: rowSchema(zodJson(siteGroupInsert)),
  MonitoredSiteRow: rowSchema(zodJson(monitoredSiteInsert)),
  MonitoredEndpointRow: rowSchema(zodJson(monitoredEndpointInsert)),
  DeployIntegrationRow: rowSchema(zodJson(deployIntegrationInsert)),
  IgnoredProjectRow: rowSchema(zodJson(ignoredProjectInsert), false),
  // The PEER_TOKEN secret is accepted on write (the POST/PATCH bodies keep it) but
  // never returned, so the response row schema omits it — the doc must not advertise
  // a field the redacted responses never carry. What every response DOES carry in its
  // place is `hasToken`: whether a token is set, which is all a reader may learn.
  PeerRow: {
    allOf: [
      ...rowSchema(zodJson(peerInsert.omit({ token: true }))).allOf,
      { type: 'object', required: ['hasToken'], properties: { hasToken: { type: 'boolean' } } },
    ],
  },
};

/** A CRUD collection: GET list, POST create (201). `createErrors` adds any further
 *  failure the create can answer with beyond the universal 400/401/403 (peers, whose
 *  base URL is uniquely indexed, answer a duplicate with 409). */
const listCreate = (rowRef: string, createBody: unknown, summary: string, ...createErrors: number[]) => ({
  get: {
    tags: [tag], summary: `List ${summary}`, security: BEARER,
    responses: { 200: okJson('The rows', { type: 'array', items: ref(rowRef) }), ...errors(401, 403) },
  },
  post: {
    tags: [tag], summary: `Create a ${summary} row`, security: BEARER,
    requestBody: { required: true, ...jsonBody(createBody) },
    responses: { 201: okJson('The created row', ref(rowRef)), ...errors(400, 401, 403, ...createErrors) },
  },
});

/** A CRUD item: PATCH update, DELETE ({ ok: true }). `patchErrors` mirrors
 *  `listCreate`'s `createErrors`: only the peers routes map a duplicate to 409, so only
 *  they declare it — advertising it everywhere would have generated clients writing
 *  duplicate-handling for resources that can never answer with one. */
const patchDelete = (rowRef: string, patchBody: unknown, summary: string, ...patchErrors: number[]) => ({
  patch: {
    tags: [tag], summary: `Update a ${summary} row`, security: BEARER, parameters: [pathParam('id')],
    requestBody: { required: true, ...jsonBody(patchBody) },
    responses: { 200: okJson('The updated row', ref(rowRef)), ...errors(400, 401, 403, 404, ...patchErrors) },
  },
  delete: {
    tags: [tag], summary: `Delete a ${summary} row`, security: BEARER, parameters: [pathParam('id')],
    responses: { 200: okFlag, ...errors(401, 403, 404) },
  },
});

export const configPaths: Paths = {
  '/config/site-groups': listCreate('SiteGroupRow', zodJson(siteGroupInsert), 'site group'),
  '/config/site-groups/{id}': patchDelete('SiteGroupRow', zodJson(siteGroupPatch), 'site group'),

  '/config/sites': listCreate('MonitoredSiteRow', zodJson(monitoredSiteInsert), 'monitored site'),
  '/config/sites/{id}': patchDelete('MonitoredSiteRow', zodJson(monitoredSitePatch), 'monitored site'),

  '/config/endpoints': listCreate('MonitoredEndpointRow', zodJson(monitoredEndpointInsert), 'monitored endpoint'),
  '/config/endpoints/{id}': {
    ...patchDelete('MonitoredEndpointRow', zodJson(monitoredEndpointPatch), 'monitored endpoint'),
    // DELETE retires the endpoint (and its now-empty site) atomically; the result
    // reports what was actually removed.
    delete: {
      tags: [tag], summary: 'Retire an endpoint (deletes its site if that leaves it empty)',
      security: BEARER, parameters: [pathParam('id')],
      responses: {
        200: okJson('What was retired', {
          type: 'object',
          required: ['ok', 'endpointDeleted', 'siteDeleted'],
          properties: {
            ok: { type: 'boolean' },
            endpointDeleted: { type: 'boolean' },
            siteDeleted: { type: 'boolean' },
          },
        }),
        ...errors(401, 403, 404),
      },
    },
  },

  '/config/integrations': listCreate('DeployIntegrationRow', zodJson(deployIntegrationInsert), 'deploy integration'),
  '/config/integrations/{id}': patchDelete('DeployIntegrationRow', zodJson(deployIntegrationPatch), 'deploy integration'),

  '/config/ignored-projects': {
    get: {
      tags: [tag], summary: 'List ignored deploy projects', security: BEARER,
      responses: { 200: okJson('The rows', { type: 'array', items: ref('IgnoredProjectRow') }), ...errors(401, 403) },
    },
    post: {
      tags: [tag], summary: 'Ignore a deploy project', security: BEARER,
      requestBody: { required: true, ...jsonBody(zodJson(ignoredProjectInsert)) },
      responses: { 201: okFlag, ...errors(400, 401, 403) },
    },
  },
  '/config/ignored-projects/{id}': {
    delete: {
      tags: [tag], summary: 'Un-ignore a deploy project', security: BEARER, parameters: [pathParam('id')],
      responses: { 200: okFlag, ...errors(401, 403, 404) },
    },
  },

  '/config/peers': listCreate('PeerRow', zodJson(peerInsert), 'fleet peer', 409),
  '/config/peers/{id}': patchDelete('PeerRow', zodJson(peerPatch), 'fleet peer', 409),

  '/config/seed': {
    post: {
      tags: [tag], summary: 'Seed the default groups/sites/endpoints/integrations', security: BEARER,
      responses: {
        200: okJson('Counts of what was seeded', {
          type: 'object',
          required: ['ok', 'groups', 'sites', 'endpoints', 'integrations'],
          properties: {
            ok: { type: 'boolean' },
            groups: { type: 'number' },
            sites: { type: 'number' },
            endpoints: { type: 'number' },
            integrations: { type: 'number' },
          },
        }),
        ...errors(401, 403),
      },
    },
  },
};
