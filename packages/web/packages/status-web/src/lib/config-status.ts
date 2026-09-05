// ---------------------------------------------------------------------------
// This board's ONE addition to the shared configuration-status model.
//
// The model itself — `endpointConfigStatus`, `projectStatus`, `partitionPending`,
// `ConfigStatus` — lives in @agentic-toolkit/deploy-platform/engine, the same
// classifier the Hono server runs behind POST /auto-configure. Import it from there;
// a second copy here is how the front page's banner and the Config badges came to
// count different things in the first place.
//
// What is genuinely OURS is that this board has a SECOND way for the operator to say
// "leave this monitor alone": `isActive: false`, the site's master monitoring switch
// (the editor's "Monitoring enabled"). Paused means out of the auto-configure
// conversation entirely — exactly what the per-endpoint opt-out means — so it folds
// into the engine's single `ignoreProjectWarning` flag HERE, at the one place this
// app's rows meet the engine's view of an endpoint. The server folds it identically in
// its own adapter (`autoConfigureOptedOut`, src/routes/auto-configure.ts).
//
// The fold lives at the boundary rather than in the engine because `isActive` means
// nothing to the engine's other consumers; giving the classifier a field per host
// vocabulary is how a shared model stops being shared.
// ---------------------------------------------------------------------------
import {
  endpointConfigStatus as classifyEndpoint,
  type EndpointConfigStatus,
  type EndpointLike as EngineEndpointLike,
} from "@agentic-toolkit/deploy-platform/engine";

/** The endpoint fields this app's wiring logic reads (EndpointView is assignable to this). */
export interface EndpointLike extends EngineEndpointLike {
  // The site's master monitoring switch ("Monitoring enabled"). Explicitly `false` means
  // paused. OPTIONAL and checked against `false` on purpose: a caller that doesn't carry
  // the field (the engine's EndpointLite, a test fixture) must not have `undefined` read
  // as "disabled" and silently lose its warning.
  isActive?: boolean;
}

/**
 * "The operator has told us to leave this monitor alone" — either way of saying it.
 *
 * This is the fold itself, exported so the ONE expression of it serves every place this
 * app hands a row to the engine: the classifier below, and the auto-configure adapter's
 * `EndpointLite` mapping. Named for the server's twin (`autoConfigureOptedOut`,
 * src/routes/auto-configure.ts) so a divergence is visible as two different answers to
 * one question rather than two unrelated helpers.
 */
export function autoConfigureOptedOut(e: Pick<EndpointLike, "ignoreProjectWarning" | "isActive">): boolean {
  return e.ignoreProjectWarning === true || e.isActive === false;
}

/** The endpoint as the engine's classifier sees it — both of this board's opt-outs folded
 *  into the one flag it has. */
function asEngineEndpoint(e: EndpointLike): EngineEndpointLike {
  return { ...e, ignoreProjectWarning: autoConfigureOptedOut(e) };
}

/**
 * One endpoint's configuration status: the engine's classification, asked about an endpoint
 * whose paused-ness has been folded into its opt-out flag.
 *
 * The monitoring switch is read ONLY in the engine's unwired branch, so a paused site that
 * IS wired still reads `configured` — pausing a site does not un-configure it. (Its deploy
 * project likewise stays claimed; see the backend's `listEndpointsForWiring`.)
 */
export function endpointConfigStatus(e: EndpointLike): EndpointConfigStatus {
  return classifyEndpoint(asEngineEndpoint(e));
}

/** True when an endpoint should be wired but isn't (missing platform or project) and the
 *  operator hasn't dismissed it either way. Delegates to the wrapper ABOVE, not to the
 *  engine's own `endpointUnconfigured` — that one would classify the raw row and miss the
 *  paused fold, so the two predicates would disagree about the same endpoint. */
export function endpointUnconfigured(e: EndpointLike): boolean {
  return endpointConfigStatus(e) === "unconfigured";
}
