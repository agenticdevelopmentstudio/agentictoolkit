export type DeployStatus = "success" | "failed" | "building" | "queued" | "canceled" | "unknown";

// Two platform-independent lifecycles. `buildPhase = null` → the platform reports
// no build lifecycle (Cloudflare Workers list only already-live deployments).
// `unknown` is TERMINAL: an in-flight phase the backend could not re-confirm for
// its expiry window, so it stopped asserting it. Like `canceled` it is the
// ABSENCE of a verdict — never good or bad.
export type BuildPhase = "queued" | "building" | "built" | "failed" | "canceled" | "unknown";
export type DeployPhase = "none" | "deploying" | "deployed" | "failed" | "unknown";

export interface Phases {
  buildPhase: BuildPhase | null;
  deployPhase: DeployPhase;
}

// THE in-flight vocabulary — the row states that can still change. A HAND MIRROR of
// the server's deploy-status.ts (there is no shared build between the two packages);
// the values MUST stay identical, which deploy-status-parity.test.ts enforces by
// importing the server module and diffing. Everything that asks "is this still in
// flight?" — the demotion clock, the build-progress cohort — keys off these.
export const IN_FLIGHT_BUILD_PHASES: readonly BuildPhase[] = ["building", "queued"];
export const IN_FLIGHT_DEPLOY_PHASE: DeployPhase = "deploying";

/** The row states that can still change — anything else is terminal. */
export function isInFlight(buildPhase: string | null, deployPhase: string): boolean {
  return (
    IN_FLIGHT_BUILD_PHASES.includes(buildPhase as BuildPhase) ||
    deployPhase === IN_FLIGHT_DEPLOY_PHASE
  );
}

/** The combinedStatus values that assert live progress (a claim with a freshness
 *  deadline), as opposed to a terminal verdict. combinedStatus maps a deploying phase
 *  to "building" and a queued build to "queued", so those two cover every in-flight
 *  DeployStatus. Used to demote a DeploymentDTO whose phase nothing has re-confirmed. */
export const IN_FLIGHT_STATUSES: readonly DeployStatus[] = ["building", "queued"];
export function deployStatusInFlight(status: DeployStatus): boolean {
  return IN_FLIGHT_STATUSES.includes(status);
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
