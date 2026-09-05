import { jsonBody, okJson, errors, queryParam, type Paths } from '../shared';

// ---------------------------------------------------------------------------
// Provider deploy webhooks (src/routes/hooks.ts). Mounted PRE-SEAM: they are NOT
// behind the app's view/admin token — each authenticates the PROVIDER instead (a
// Vercel signature over the raw body, or Railway's shared secret via ?token= /
// x-webhook-secret). So no bearer scheme; a 401 is a provider-auth failure and a
// 503 means the webhook secret is unconfigured. The body is the provider's own
// event payload (opaque here), always answered 2xx once authenticated so the
// provider never retry-storms.
// ---------------------------------------------------------------------------

const tag = 'hooks';

const okIgnored = okJson('Accepted (possibly ignored — always 2xx to avoid retry storms)', {
  type: 'object',
  required: ['ok'],
  properties: {
    ok: { type: 'boolean' },
    id: { type: 'string' },
    ignored: {},
  },
});

const providerBody = { ...jsonBody({ type: 'object', additionalProperties: true }) };

export const hooksPaths: Paths = {
  '/hooks/vercel': {
    post: {
      tags: [tag],
      summary: 'Vercel deploy webhook (authenticated by the Vercel signature)',
      requestBody: providerBody,
      responses: { 200: okIgnored, ...errors(401, 503) },
    },
  },
  '/hooks/railway': {
    post: {
      tags: [tag],
      summary: 'Railway deploy webhook (authenticated by a shared secret)',
      parameters: [queryParam('token')],
      requestBody: providerBody,
      responses: { 200: okIgnored, ...errors(401, 503) },
    },
  },
};
