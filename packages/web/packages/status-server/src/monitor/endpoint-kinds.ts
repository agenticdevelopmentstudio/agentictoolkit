// The canonical endpoint-kind vocabulary — ONE source for server-side validation
// (the endpoints routes) and the "needs wiring" / auto-wire logic. Kept in step with
// the status site's src/lib/endpoint-kinds.ts so the backend and frontend agree on the
// vocabulary the editor offers.
export const ENDPOINT_KINDS = ['http', 'frontend', 'admin', 'health', 'custom', 'dns'] as const;
export type EndpointKind = (typeof ENDPOINT_KINDS)[number];

// Which of those kinds are deploy-backed is the CLASSIFIER's knowledge, not this list's:
// `endpointNeedsWiring` is what acts on it. Re-exported (never restated) so the auto-wirer
// here and the engine behind POST /auto-configure can't come to disagree about `dns` —
// they used to be three separate literal Sets, here, in the browser, and in the engine.
export { NON_DEPLOY_KINDS } from '@agentic-toolkit/deploy-platform/engine';

export function isEndpointKind(k: string): k is EndpointKind {
  return (ENDPOINT_KINDS as readonly string[]).includes(k);
}
