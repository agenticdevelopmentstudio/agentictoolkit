// The canonical endpoint-kind vocabulary — ONE source for the editor dropdown
// (api/monitored-sites re-exports this), server-side validation (the endpoints
// routes), and the "needs wiring" warning logic (config-status).
export const ENDPOINT_KINDS = ["http", "frontend", "admin", "health", "custom", "dns"] as const;
export type EndpointKind = (typeof ENDPOINT_KINDS)[number];

// Which of those kinds are deploy-backed is the CLASSIFIER's knowledge, not this list's:
// `endpointNeedsWiring` is what acts on it. Re-exported (never restated) so this app's
// warning badge and the engine's classification can't come to disagree about `dns` —
// they used to be three separate literal Sets, here, on the Hono server, and in the engine.
export { NON_DEPLOY_KINDS } from "@agentic-toolkit/deploy-platform/engine";

export function isEndpointKind(k: string): k is EndpointKind {
  return (ENDPOINT_KINDS as readonly string[]).includes(k);
}
