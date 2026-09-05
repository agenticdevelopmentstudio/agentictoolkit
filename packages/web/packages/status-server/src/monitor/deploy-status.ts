export type DeployStatus = "success" | "failed" | "building" | "queued" | "canceled" | "unknown";

// Two platform-independent lifecycles. `buildPhase = null` → the platform reports
// no build lifecycle (Cloudflare Workers list only already-live deployments).
// `unknown` is TERMINAL: an in-flight phase nothing could re-confirm for the expiry
// window (see expireUnconfirmedDeploys) — the monitor gave up asserting it. Like
// `canceled` it is the ABSENCE of a verdict, never a good or bad one; unlike
// `canceled` it does not claim the provider stopped the work. Fresh provider truth
// (a poll or by-id re-fetch) overwrites it, so a false expiry self-heals.
export type BuildPhase = "queued" | "building" | "built" | "failed" | "canceled" | "unknown";
export type DeployPhase = "none" | "deploying" | "deployed" | "failed" | "unknown";

export interface Phases {
  buildPhase: BuildPhase | null;
  deployPhase: DeployPhase;
}

// THE definition of "still in flight" — the row states that can still change;
// anything else is terminal. Shared by the reconcile candidate query and the
// upsert's webhook regression guard so the two can never drift.
export const IN_FLIGHT_BUILD_PHASES: readonly BuildPhase[] = ["building", "queued"];
export const IN_FLIGHT_DEPLOY_PHASE: DeployPhase = "deploying";

/** The row states that can still change — anything else is terminal. */
export function isInFlight(buildPhase: string | null, deployPhase: string): boolean {
  return (
    IN_FLIGHT_BUILD_PHASES.includes(buildPhase as BuildPhase) ||
    deployPhase === IN_FLIGHT_DEPLOY_PHASE
  );
}

// ---------------------------------------------------------------------------
// The in-flight vocabulary as raw SQL fragments. EVERY SQL caller (the upsert's
// webhook guard, the reconcile's gone-collapse, the expiry sweep) builds its
// predicate from these, so no query can drift from isInFlight() above. The
// interpolated values are the fixed enum literals of this module — never
// caller-supplied strings.
// ---------------------------------------------------------------------------

/** "(build_phase, deploy_phase) is still in flight", over either the stored row
 *  ("") or an upsert's incoming row ("excluded."). */
export function inFlightSql(prefix: "" | "excluded." = ""): string {
  const list = IN_FLIGHT_BUILD_PHASES.map((p) => `'${p}'`).join(", ");
  return `(${prefix}build_phase IN (${list}) OR ${prefix}deploy_phase = '${IN_FLIGHT_DEPLOY_PHASE}')`;
}

/** States a fresh report may ALWAYS overwrite for ONE lifecycle column: that column in
 *  flight (still changing) or `unknown` (the monitor's own gave-up marker, not a provider
 *  verdict). PER-COLUMN on purpose. The webhook regression guard must still protect a real
 *  verdict on ONE lifecycle when the SIBLING lifecycle is unknown/in-flight; a whole-row
 *  predicate (overwritable the moment EITHER lifecycle is unknown) would strip protection
 *  from a settled build/deploy it should keep — regressing e.g. a `built`+`unknown` row's
 *  real `built` back to `building` on a stale webhook. */
export function columnOverwritableSql(col: "build_phase" | "deploy_phase", prefix: "" | "excluded." = ""): string {
  const c = `${prefix}${col}`;
  const inFlight =
    col === "build_phase"
      ? `${c} IN (${IN_FLIGHT_BUILD_PHASES.map((p) => `'${p}'`).join(", ")})`
      : `${c} = '${IN_FLIGHT_DEPLOY_PHASE}'`;
  return `(${inFlight} OR ${c} = 'unknown')`;
}

/**
 * The in-flight BUILD phases in the ORDER a build passes through them. A build enters the
 * queue once and leaves it once, so this is what makes the two comparable: `building` is
 * strictly LATER than `queued`, and nothing walks that back.
 *
 * `deploy_phase` needs no counterpart — `deploying` is its only in-flight value, so it has
 * nothing to be out of order with.
 */
export const IN_FLIGHT_BUILD_ORDER: readonly BuildPhase[] = ["queued", "building"];

/** Every (incoming, stored) pair that would move the build BACKWARDS through
 *  {@link IN_FLIGHT_BUILD_ORDER}, as SQL over an upsert's excluded/stored rows. Derived
 *  from the ordering rather than spelled out, so inserting a phase can't leave a stale
 *  hand-written pair behind. */
function buildPhaseBackwardsSql(): string[] {
  return IN_FLIGHT_BUILD_ORDER.flatMap((earlier, i) =>
    IN_FLIGHT_BUILD_ORDER.slice(i + 1).map(
      (later) => `(excluded.build_phase = '${earlier}' AND build_phase = '${later}')`,
    ),
  );
}

/**
 * "This webhook must KEEP the stored value for this column" — the ingest guard's whole
 * predicate for one lifecycle column, over the stored row and the incoming (`excluded.`) one.
 *
 * Webhooks arrive out of order. They are independent POSTs, and our own ingest answers 503
 * when the ownership check can't read the roster, which asks the provider to redeliver — so
 * "an older event lands after a newer one" is the ordinary case, not an exotic one. TWO
 * distinct ways that goes wrong, and the guard needs both:
 *
 *  1. **A stale event overwriting a VERDICT** — a late in-flight event landing on a row that
 *     already settled. Refused per-column (see {@link columnOverwritableSql}), so a real
 *     verdict on the SIBLING lifecycle keeps its protection when this one is `unknown`.
 *  2. **A stale event overwriting a LATER IN-FLIGHT PHASE** — rule 1 cannot see this one:
 *     both sides are in flight, so there is no verdict to protect. This is reachable only
 *     because `deployment.created` (entered the queue) and `deployment.build-requested`
 *     (left it) BOTH map now; while `build-requested` was being dropped the two events
 *     could not disagree. A redelivered `created` would otherwise drag a site that visibly
 *     started building back to "queued" — the exact transition the board exists to show.
 *
 * A TERMINAL event is exempt from both: it is the provider's current truth, and a
 * re-promotion (`built` → `ROLLING`) is a legitimate move back into flight.
 */
export function webhookKeepsStoredSql(col: "build_phase" | "deploy_phase"): string {
  const staleOverVerdict = `(${inFlightSql("excluded.")} AND NOT ${columnOverwritableSql(col, "")})`;
  const backwards = col === "build_phase" ? buildPhaseBackwardsSql() : [];
  return `(${[staleOverVerdict, ...backwards].join(" OR ")})`;
}

/** CASE-collapse of ONLY the in-flight build lifecycle to `to` — a settled
 *  build keeps its verdict. Evaluates against the row's CURRENT state, so a
 *  concurrent write between a candidate select and this update is never
 *  clobbered. */
export function collapseInFlightBuildSql(to: BuildPhase): string {
  const list = IN_FLIGHT_BUILD_PHASES.map((p) => `'${p}'`).join(", ");
  return `CASE WHEN build_phase IN (${list}) THEN '${to}' ELSE build_phase END`;
}

/** CASE-collapse of ONLY an in-flight deploy lifecycle to `to`. */
export function collapseInFlightDeploySql(to: DeployPhase): string {
  return `CASE WHEN deploy_phase = '${IN_FLIGHT_DEPLOY_PHASE}' THEN '${to}' ELSE deploy_phase END`;
}

/** Vercel: readyState is the BUILD; readySubstate (production only) is the DEPLOY. */
export function vercelPhases(
  readyState: string,
  readySubstate: string | null | undefined,
  target: string | null | undefined,
): Phases {
  const buildPhase: BuildPhase =
    readyState === "READY" ? "built"
    : readyState === "ERROR" ? "failed"
    : readyState === "CANCELED" || readyState === "DELETED" ? "canceled"
    : readyState === "QUEUED" ? "queued"
    : "building"; // BUILDING / INITIALIZING / BLOCKED / unknown
  let deployPhase: DeployPhase = "none";
  if (buildPhase === "built" && target === "production") {
    // STAGED = built but never promoted → no deploy entry yet.
    deployPhase =
      readySubstate === "PROMOTED" ? "deployed"
      : readySubstate === "ROLLING" ? "deploying"
      : "none";
  }
  return { buildPhase, deployPhase };
}

/** Railway reports the build and deploy phases natively in one status enum. */
export function railwayPhases(status: string): Phases {
  switch (status) {
    case "BUILDING":
    case "INITIALIZING":
      return { buildPhase: "building", deployPhase: "none" };
    case "DEPLOYING":
      return { buildPhase: "built", deployPhase: "deploying" };
    case "SUCCESS":
    case "CRASHED": // built+deployed; a runtime crash is a health concern, not a deploy failure
      return { buildPhase: "built", deployPhase: "deployed" };
    case "FAILED": // enum can't separate build-fail from deploy-fail; build is the common case
      return { buildPhase: "failed", deployPhase: "none" };
    case "WAITING":
    case "NEEDSAPPROVAL":
      return { buildPhase: "queued", deployPhase: "none" };
    case "REMOVED":
    case "SKIPPED":
      return { buildPhase: "canceled", deployPhase: "none" };
    default:
      return { buildPhase: "building", deployPhase: "none" };
  }
}

// Crunchy cluster states that mean the cluster is genuinely broken (vs routine maintenance).
// From Crunchy's documented state enum; is_suspended is folded in as the compute-is-off signal.
const CRUNCHY_BAD_STATES = new Set(["failed", "creation_failed", "suspended"]);

/**
 * Crunchy Bridge clusters have no build/deploy CI lifecycle — health is the cluster `state`.
 * Quieter model (owner-chosen): only genuinely-broken states alert. A cluster is `failed`
 * iff it is suspended (is_suspended, or state "suspended") or in a documented problem state
 * (failed / creation_failed). Every other state — `ready` and all routine/transient
 * operations (creating, restarting, resizing→resuming/starting, upgrading, restoring,
 * finalizing, replaying, destroying), plus any unknown/future state — is `deployed`
 * (healthy): routine maintenance must not page, and an unrecognised state is not assumed bad.
 * Both phases are terminal, so `deployIsStuck` never misfires on a cluster's ancient createdAt.
 */
export function crunchyPhases(state: string, isSuspended: boolean): Phases {
  const bad = isSuspended || CRUNCHY_BAD_STATES.has(state);
  return { buildPhase: null, deployPhase: bad ? "failed" : "deployed" };
}

/** Single status for the Details matrix / KPI strip / deploy-issue recorder. */
export function combinedStatus({ buildPhase, deployPhase }: Phases): DeployStatus {
  if (buildPhase === "failed" || deployPhase === "failed") return "failed";
  if (buildPhase === "canceled") return "canceled";
  // Either lifecycle expired unconfirmable → the whole deployment's outcome is
  // unknown (checked before the in-flight fallthroughs so an expired row can
  // never re-read as "building").
  if (buildPhase === "unknown" || deployPhase === "unknown") return "unknown";
  if (deployPhase === "deployed") return "success";
  if (deployPhase === "deploying") return "building";
  if (buildPhase === "built") return "success"; // built, no separate deploy step (non-prod / staged)
  if (buildPhase === "queued") return "queued";
  return "building"; // building, or null/unknown
}
