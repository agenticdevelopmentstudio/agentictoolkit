import { vercelPhases, railwayPhases } from "./deploy-status";
import { shortSha, commitFullMessage } from "./format";
import { toValidDate, type ProviderDeploy } from "./provider-deploy";

// ── Vercel ───────────────────────────────────────────────────────────────────
// Map a Vercel webhook event TYPE to the readyState/substate `vercelPhases` expects
// (the webhook payload carries the project/commit/target but not a raw state field,
// so the event type IS the state). Unmapped types → not a deployment event we ingest.
const VERCEL_STATE: Record<string, { readyState: string; readySubstate: string | null }> = {
  // `created` is the deployment entering the QUEUE, not a build starting. Vercel admits
  // builds only as concurrency slots free, so with a fleet-wide push fanning out to ~48
  // projects against few slots, a created deployment sits QUEUED for minutes to hours.
  // Mapping it to BUILDING claimed work that had not begun, and the board could only be
  // corrected by a poll that happened to still see the row.
  "deployment.created": { readyState: "QUEUED", readySubstate: null },
  // …and THIS is the transition out of the queue — the moment a slot frees and the build
  // actually starts. It was absent from this table, so `mapVercelDeployEvent` returned null
  // and the ingest route dropped it (2xx, `ignored: true`). The account webhook has always
  // been subscribed to it; the only reason queued→building never showed on the board is
  // that the one event announcing it was thrown away here.
  "deployment.build-requested": { readyState: "BUILDING", readySubstate: null },
  "deployment.succeeded": { readyState: "READY", readySubstate: null },
  "deployment.ready": { readyState: "READY", readySubstate: null },
  "deployment.promoted": { readyState: "READY", readySubstate: "PROMOTED" },
  "deployment.error": { readyState: "ERROR", readySubstate: null },
  "deployment.canceled": { readyState: "CANCELED", readySubstate: null },
};

interface VercelEvent {
  type?: string;
  createdAt?: string;
  payload?: {
    target?: string | null;
    /** Vercel sends the project's immutable `prj_…` id alongside the deployment. */
    project?: { id?: string };
    deployment?: {
      id?: string;
      name?: string;
      url?: string;
      meta?: Record<string, string | undefined>;
    };
    links?: { deployment?: string };
  };
}

/** Vercel deploy webhook → a deploy row (same id/shape the poller produces). */
export function mapVercelDeployEvent(event: unknown): ProviderDeploy | null {
  const e = event as VercelEvent;
  const state = VERCEL_STATE[e.type ?? ""];
  if (!state) return null;
  const dep = e.payload?.deployment;
  if (!dep?.id || !dep?.name) return null;
  const target = e.payload?.target ?? null;
  const meta = dep.meta ?? {};
  return {
    id: `vc_${dep.id}`,
    platform: "vercel",
    projectName: dep.name,
    // The identity the board keys on, exactly as the poller records it
    // (`fetch-vercel-projects.ts`) and the Railway mapper below does. Without it a
    // webhook-created row is matchable only by NAME, so a project renamed upstream owns
    // no target until the next full poll overwrites the row. `upsertDeployments`
    // COALESCEs this column, so a null here never erases an id already learned.
    providerProjectId: e.payload?.project?.id ?? null,
    ...vercelPhases(state.readyState, state.readySubstate, target),
    environment: target,
    commitHash: shortSha(meta.githubCommitSha),
    commitMessage: commitFullMessage(meta.githubCommitMessage),
    branch: meta.githubCommitRef ?? null,
    commitRepo:
      meta.githubCommitOrg && meta.githubCommitRepo
        ? `${meta.githubCommitOrg}/${meta.githubCommitRepo}`
        : null,
    url: e.payload?.links?.deployment ?? (dep.url ? `https://${dep.url}` : null),
    // Receipt time when absent OR unparseable — a webhook is often the only
    // witness of a terminal state, so approximate time beats a dropped event
    // (and an Invalid Date must never leave this boundary).
    createdAt: toValidDate(e.createdAt) ?? new Date(),
  };
}

// ── Railway ──────────────────────────────────────────────────────────────────
interface RailwayEvent {
  id?: string;
  status?: string;
  type?: string; // e.g. "Deployment.crashed" — used when `status` is absent
  project?: { id?: string; name?: string };
  environment?: { name?: string };
  commitHash?: unknown;
  commitMessage?: unknown;
  branch?: unknown;
  repo?: unknown;
  timestamp?: string;
}

/** Railway encodes status in a `type` like "Deployment.crashed" — normalize to the
 *  enum `railwayPhases` expects (SUCCESS/FAILED/CRASHED/…). */
function railwayStatusFromType(type: string | undefined): string | undefined {
  if (!type) return undefined;
  const seg = type.split(".").pop();
  return seg ? seg.toUpperCase() : undefined;
}

/** Railway deploy webhook → a deploy row (same id/shape the poller produces). */
export function mapRailwayDeployEvent(event: unknown): ProviderDeploy | null {
  const p = event as RailwayEvent;
  const status = p.status ?? railwayStatusFromType(p.type);
  if (!p.id || !status || !p.project?.name) return null;
  return {
    id: `ry_${p.id}`,
    platform: "railway",
    projectName: p.project.name,
    providerProjectId: p.project?.id ?? null,
    ...railwayPhases(status),
    environment: p.environment?.name ?? null,
    commitHash: typeof p.commitHash === "string" ? shortSha(p.commitHash) : null,
    commitMessage: typeof p.commitMessage === "string" ? commitFullMessage(p.commitMessage) : null,
    branch: typeof p.branch === "string" ? p.branch : null,
    commitRepo: typeof p.repo === "string" && p.repo.includes("/") ? p.repo : null,
    url: p.project?.id ? `https://railway.com/project/${p.project.id}` : null,
    createdAt: toValidDate(p.timestamp) ?? new Date(), // same fallback contract as the Vercel mapper
  };
}
