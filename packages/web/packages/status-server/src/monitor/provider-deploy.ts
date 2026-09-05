import { combinedStatus, type BuildPhase, type DeployPhase } from "./deploy-status";
import { deployEnv, isRealEnvDeployRow } from "./deploy-view";
import type { DeploymentDTO } from "./types";

/**
 * One deployment as a provider reports it — the pure in-memory product of the
 * fetchers and the webhook mappers, before any display shaping. Structurally
 * the old deployments-table row minus the storage-only columns (liveHost is
 * stamped from config at serve time; fetchedAt was a storage artifact).
 */
export interface ProviderDeploy {
  id: string; // 'vc_<uid>' | 'cf_<id>' | 'ry_<id>' | 'cr_<id>'
  platform: string; // 'vercel' | 'cloudflare-pages' | 'railway' | 'crunchy'
  projectName: string;
  /**
   * The provider's immutable project id, when the API gives us one. Identity is keyed
   * `providerProjectId ?? projectName`, so a platform we have not adopted ids for keeps
   * working unchanged and adoption is a per-platform change, never a flag day.
   */
  providerProjectId?: string | null;
  buildPhase: BuildPhase | null;
  deployPhase: DeployPhase;
  environment: string | null;
  commitHash: string | null;
  commitMessage: string | null;
  branch: string | null;
  commitRepo: string | null; // "owner/name" — to build a GitHub commit link
  url: string | null;
  // The provider's failure reason for a failed build/deploy, filled in
  // out-of-band by enrich-deploy-errors (fetchers/webhooks leave it undefined;
  // it's read back off the persisted row). Optional so the many ProviderDeploy
  // constructors that never see an error don't each have to spell out `null`.
  errorText?: string | null;
  createdAt: Date;
  // When the PHASES were last confirmed against provider truth: the persisted
  // row's fetched_at, or a webhook's receipt time for live-buffer overlays.
  // Optional because the fetchers construct deploys straight FROM provider truth
  // (their confirmation time is "now", and they are persisted before serving);
  // the DTO mapper falls back to createdAt — the conservative floor that never
  // claims a freshness nothing recorded.
  confirmedAt?: Date;
}

/** Parse a provider/webhook timestamp at the TRUST BOUNDARY: ISO string, epoch
 *  number, or Date in; a real Date out — or null for anything unparseable
 *  (including out-of-range values that construct an Invalid Date). An Invalid
 *  Date let past this point fails the whole deployments upsert (killing the
 *  cycle, repeatedly) or throws out of toISOString() at serialize time. */
export function toValidDate(raw: unknown): Date | null {
  if (raw == null) return null;
  if (typeof raw !== "string" && typeof raw !== "number" && !(raw instanceof Date)) return null;
  const d = raw instanceof Date ? raw : new Date(raw);
  return Number.isFinite(d.getTime()) ? d : null;
}

/** ISO-encode a stored timestamp, fail-soft: a poisoned legacy row pins to epoch
 *  (and logs) instead of throwing — one bad row must not 500 /live for everyone.
 *  New writes can't produce one (toValidDate gates every boundary). */
function isoOf(id: string, d: Date): string {
  if (Number.isFinite(d.getTime())) return d.toISOString();
  console.error(`[provider-deploy] ${id} carries an invalid createdAt — serializing as epoch`);
  return new Date(0).toISOString();
}

/** Shape a provider deploy for the client (same mapping the old /api/deployments
 *  route did from a DB row): derive the combined status, stamp the config-matched
 *  live host, ISO-encode the timestamp. */
export function providerDeployToDTO(d: ProviderDeploy, liveHost: string | null): DeploymentDTO {
  return {
    id: d.id,
    platform: d.platform,
    projectName: d.projectName,
    // `?? null` rather than passed through: `ProviderDeploy.providerProjectId` is OPTIONAL
    // (a platform whose ids we have not adopted omits it entirely), and the wire shape is
    // not — a consumer must be able to tell "this row has no id" from "this build of the
    // DTO predates the field".
    providerProjectId: d.providerProjectId ?? null,
    status: combinedStatus({ buildPhase: d.buildPhase, deployPhase: d.deployPhase }),
    buildPhase: d.buildPhase,
    deployPhase: d.deployPhase,
    environment: d.environment,
    // The tier the client renders, derived once here. Null — not a guess — for a row that
    // is not a deployment of any tier: a Vercel preview reports no environment, but its
    // branch is a feature ref and its project name is the production project's, so both of
    // `deployEnv`'s signals would happily badge it. `deployEnv` has no "don't know" to
    // return, so the gate has to be applied before asking it. Same gate the board applies
    // before a preview can become a Problem (`ownedDeployTarget`).
    tier: isRealEnvDeployRow(d.platform, d.environment)
      ? deployEnv(d.platform, d.projectName, d.environment, d.branch ?? null)
      : null,
    commitHash: d.commitHash,
    commitMessage: d.commitMessage,
    branch: d.branch,
    commitRepo: d.commitRepo,
    url: d.url,
    errorText: d.errorText ?? null,
    liveHost,
    createdAt: isoOf(d.id, d.createdAt),
    phaseConfirmedAt: isoOf(d.id, d.confirmedAt ?? d.createdAt),
  };
}
