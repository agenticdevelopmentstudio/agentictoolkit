import { deployEnv, isRealEnvDeployRow } from "../monitor/deploy-view";
import { dropVanishedVercelProjects } from "../monitor/issue-sources";
import type { ConfiguredDeployTargets } from "../monitor/issue-sources";
import { platformCanon } from "../monitor/overview";
import { boardTargetKey } from "./target-key";
import type { DeployFact, RosterEntry } from "./types";

/**
 * WHO OWNS A DEPLOY ROW — the one place that answers it, for the fold AND for every
 * read/write surface outside the fold.
 *
 * There used to be two answers. The fold resolved ownership IDENTITY-first
 * (`providerProjectId ?? projectName`), while the webhook door, the Deployments tab and
 * the live-host stamp each re-asked the question by project NAME
 * (`isConfiguredDeployTarget`, `deployTargetKey`). The moment a project was renamed
 * upstream the two disagreed: the board showed a Problem for `vercel|prj_abc|`, its
 * webhook was discarded before it could be written, the tab showed no rows for it, and
 * its `liveHost` was nulled so the Problem lost the one link that pointed at the thing
 * that was broken.
 *
 * Two granularities live here, and the difference between them is deliberate:
 *
 *  - TARGET (`ownedDeployTarget`, `matchRosterEntry`) — what the fold judges. Railway
 *    keys carry an environment segment, because one Railway project serves many
 *    environments and each is separately monitorable (Requirement A: deactivating one
 *    environment's entry must not silence its sibling's).
 *  - PROJECT (`rosterDeployProjects`, `ownsDeployProject`) — "does any live site monitor
 *    this project at all", environment-free. That is the question the webhook door and
 *    the Deployments tab ask, and it is a property of the PROJECT rather than of one
 *    environment of it — the same distinction the vendored canon already draws between
 *    `deployTargetKey` and `deployProjectKey`. Asking the target question there would
 *    silently drop every Railway row whose environment name is not spelled identically
 *    on the endpoint, which is a narrowing neither surface ever made.
 *
 * Both granularities read the SAME roster and the SAME identity rule (provider id first,
 * project name second, crunchy always owned), so they can differ only where this file
 * says they differ.
 */

/**
 * The identifying columns of a deploy row — all any ownership question needs. A
 * `DeployFact`, a `StaleProdFact`, a raw `deployments` row and a freshly-mapped webhook
 * row (`ProviderDeploy`) all satisfy it. `providerProjectId` is OPTIONAL rather than
 * `string | null` only so the webhook mapper's shape fits without a cast; absent and null
 * mean the same thing here — no id, fall back to the name.
 */
export interface DeployIdentity {
  platform: string | null;
  providerProjectId?: string | null;
  projectName: string;
  environment: string | null;
}

/**
 * The identity a roster entry claims: its provider id when it has one, else its name.
 * Exported because `derive-activity.ts` mints targets for the same entries — two
 * spellings of identity is the defect this whole design removes.
 */
export function entryIdentity(e: RosterEntry): string | null {
  return e.providerProjectId ?? e.projectName;
}

/**
 * Only ACTIVE entries with deploy monitoring ON, and no opt-out, own a deploy target.
 * This is Requirement A for every deploy surface at once: flipping `isActive` or
 * `monitorDeploys` off removes the entry from the roster, so nothing downstream — the
 * fold, the tab, or the webhook door — can claim its rows.
 */
function ownsDeploys(e: RosterEntry): boolean {
  return e.isActive && e.monitorDeploys && !e.ignoreProjectWarning;
}

/**
 * Index the roster twice — by provider id and by project name — so a deploy row can be
 * matched by id when both sides carry one and by name otherwise.
 *
 * Both maps are keyed by `boardTargetKey` — not a hand-rolled `${platform}|${id}`
 * literal — so a Railway entry's key includes its environment. Two roster entries for
 * the SAME Railway project but different environments therefore occupy DISTINCT keys;
 * without this, a name-only key would collapse them, and deactivating one environment's
 * entry would silently leave its Problems owned by the other environment's still-active
 * sibling (Requirement A violated). Vercel/Cloudflare entries are unaffected: their key
 * has no environment segment either way.
 */
export interface RosterIndex {
  byId: Map<string, RosterEntry>;
  byName: Map<string, RosterEntry>;
  /**
   * The Vercel project NAMES a live site still monitors that no longer exist upstream —
   * the SECOND ownership question, and the one every deploy surface used to answer for
   * itself. Name-keyed because the account mirror it is checked against is name-keyed.
   *
   * It belongs on the index rather than beside it because it is the same kind of fact as
   * `byId`/`byName` — "who legitimately owns a deploy row right now" — and because the
   * alternative is what shipped: `routes/reads.ts` computed it for the Deployments tab,
   * `staleProdProblems` computed it again for stale-prod, and `deployProblems` computed
   * it nowhere at all, so the one surface that PAGES ON-CALL was the one that kept
   * re-opening a Problem for a project that had been deleted at Vercel.
   */
  vanishedVercel: ReadonlySet<string>;
}

/**
 * `liveVercelProjects` is REQUIRED, not optional, for the same reason `deployEnv`'s
 * `branch` is: a caller that simply forgot would get the un-narrowed answer silently,
 * which is precisely the defect this parameter exists to close. Pass an empty iterable to
 * mean "I have no account mirror" — `dropVanishedVercelProjects`' first guard reads that
 * as narrow-nothing, deliberately, because an empty read and a wiped account are
 * indistinguishable and silencing the fleet is the worse of the two mistakes.
 */
export function rosterTargets(roster: RosterEntry[], liveVercelProjects: Iterable<string>): RosterIndex {
  const byId = new Map<string, RosterEntry>();
  const byName = new Map<string, RosterEntry>();
  for (const e of roster) {
    if (!ownsDeploys(e)) continue;
    if (e.providerProjectId) {
      const idKey = boardTargetKey(e.platform, e.providerProjectId, e.environment);
      if (idKey) byId.set(idKey, e);
    }
    const nameKey = boardTargetKey(e.platform, e.projectName, e.environment);
    if (nameKey) byName.set(nameKey, e);
  }
  // Built off `rosterDeployProjects` — the PROJECT-granularity answer — because the
  // mirror lists projects, not environments. Only `vanished` is kept; the narrowed set it
  // also returns is the name-keyed ownership answer, which the two maps above already are.
  const projects = rosterDeployProjects(roster);
  const owned: ConfiguredDeployTargets = {
    vercel: projects.get("vercel")?.names ?? new Set<string>(),
    railway: projects.get("railway")?.names ?? new Set<string>(),
    cloudflare: projects.get("cloudflare")?.names ?? new Set<string>(),
  };
  const vanishedVercel = new Set(dropVanishedVercelProjects(owned, new Set(liveVercelProjects)).vanished);
  return { byId, byName, vanishedVercel };
}

/**
 * Find the roster entry that owns a deploy row. Provider id first so a project renamed
 * upstream still resolves to the same entry; name second so a platform we have not
 * adopted ids for still works. THE ENTRY, not the deploy row, then mints the target key
 * — which is what stops the id cutover from spelling one target two ways.
 *
 * Looks up through `boardTargetKey` (same as `rosterTargets`), so the lookup is
 * environment-scoped for Railway exactly as the index is — a deploy for one Railway
 * environment can never match a roster entry that only owns a sibling environment.
 */
export function matchRosterEntry(
  d: DeployIdentity,
  byId: Map<string, RosterEntry>,
  byName: Map<string, RosterEntry>,
): RosterEntry | null {
  if (d.providerProjectId) {
    const idKey = boardTargetKey(d.platform, d.providerProjectId, d.environment);
    if (idKey) {
      const hit = byId.get(idKey);
      if (hit) return hit;
    }
  }
  const nameKey = boardTargetKey(d.platform, d.projectName, d.environment);
  const named = (nameKey ? byName.get(nameKey) : null) ?? null;
  // BOTH sides carry an id and they DISAGREE → different projects that merely share a
  // name, so the name fallback must not adopt this row. The name index is populated for
  // id-carrying entries too (it has to be: a deploy row written before `learnDeployProjectIds`
  // armed the id has only a name to match on), which without this test lets a project
  // renamed upstream keep squatting the old name. Concretely: entry E holds
  // `prj_A` + the stale name `web`; a NEW project is created and named `web`, and its rows
  // carry `prj_B` but reach `byName` before E's own id is learned for them. E would adopt
  // them and the failure would be filed under `vercel|prj_A|` — a Problem attributed to a
  // project that did not build, while the real owner shows nothing.
  //
  // Only a CONFLICT rejects. An entry with no id still answers for a row that has one
  // (that is the pre-adoption path), and a row with no id still matches by name.
  if (named && d.providerProjectId && named.providerProjectId && named.providerProjectId !== d.providerProjectId) {
    return null;
  }
  return named;
}

/**
 * A Crunchy cluster is a deploy row with no site behind it — it has no HTTP host, so no
 * roster entry can ever own one, and it is ALWAYS visible. That was `isConfiguredDeployTarget`'s
 * carve-out (`if (p === "crunchy") return true`) and it is load-bearing in the fold: without
 * it no crunchy Problem is ever derived, and `applyBoardToLedger` would resolve every open
 * crunchy issue on its first sweep — silently retiring the DB alerting the spec keeps.
 */
function isCrunchy(platform: string | null): boolean {
  return platformCanon(platform) === "crunchy";
}

/**
 * Who owns this deploy row, and under what target key — the ONE gate that decides
 * whether a deployment is visible to the BOARD at all. Null means invisible by design:
 * a Vercel PREVIEW row (no live environment), a row whose project has been DELETED at
 * Vercel, a row no live roster entry claims, or a platform/name pair that mints no key.
 *
 * Shared by `deployProblems` and `deriveActivity` on purpose. They used to carry
 * identical copies, and Problems and Activity silently disagreeing about which
 * deployments exist is the failure mode this branch was written to end.
 *
 * Returns the row's `env` for the same reason. TWO different environments are in play and
 * they are NOT interchangeable:
 *
 *  - `d.environment` is the PROVIDER'S TARGET — a promotion channel. Every Vercel project
 *    has its own production target, so `hub-help-testing`'s target is literally
 *    "production". It stays raw on the fact because that is what the preview gate below,
 *    `boardTargetKey`, and the SQL grouping all need.
 *  - `env` is the LOGICAL TIER the project serves, which `deployEnv` reads from the BRANCH
 *    the row was built from — `prepared` builds testing, `staging` staging, `production`
 *    production — falling back to the project name only when the branch says nothing. This
 *    is the one a human reads off a badge.
 *
 * It is derived HERE, at the single gate every board-visible deploy row passes through,
 * rather than left to each producer: the two producers that consumed the raw target
 * instead both shipped a board calling every `-testing`/`-staging` Vercel deploy PROD,
 * while `staleProdProblems` — which did call `deployEnv` — disagreed with them on the same
 * screen. A caller that has a target now has the tier that goes with it.
 *
 * `env` BELONGS TO THE ROW, NOT TO THE TARGET — do not cache it per target. Outside
 * Railway the key's environment segment is blank by construction (`boardTargetKey`), so
 * one target aggregates every board-visible row of a project, while the tier is read from
 * each row's own BRANCH. Normally they agree, because only the project's production branch
 * clears the preview gate above; they diverge exactly when that branch is REPOINTED (the
 * fleet's testing projects moving from `main` to `prepared` is what prompted this code),
 * and then a project's older rows legitimately carry the older tier. That is honest
 * history: an activity row badges the tier its build actually served, and a Problem badges
 * the tier of the row it was judged from. What is NOT safe is assuming one target implies
 * one tier and reusing a cached one across rows.
 */
export function ownedDeployTarget(
  d: DeployFact,
  index: RosterIndex,
): { owner: RosterEntry | null; target: string; env: string } | null {
  // A Vercel row with no environment (or an empty one) is a PREVIEW/branch build. It
  // is not a deployment of any live environment, so a failed preview must never
  // become a "production deploy failed" Problem. Shared with the issue recorder
  // (`issues.ts:370`) and the UI (`deploy-view.ts`) so all three can never disagree
  // about what counts as a real deploy. NOT applied by the project-granularity gate
  // below: a preview build is a real deployment the Deployments tab has always listed.
  if (!isRealEnvDeployRow(d.platform, d.environment)) return null;
  // The project was DELETED at Vercel. Its site is still wired to a target that can never
  // build again, so its last failed build can never be superseded by a success — serving
  // it pins an unclearable Problem on the board, and every provider retry re-opens and
  // re-pages it. The same predicate `routes/reads.ts` applies to the Deployments tab,
  // moved here so Problems, Activity and `monitoredTargets` cannot disagree with it (they
  // did: `hooks.ts` documented this narrowing as the fold's job while the fold had none).
  // Dropping the row from the owned set is the whole fix — an unowned target is absent
  // from `monitoredTargets`, so `applyBoardToLedger` closes any open row SILENTLY, as
  // "unmonitored" rather than as a recovery nobody observed.
  if (platformCanon(d.platform) === "vercel" && index.vanishedVercel.has(d.projectName)) return null;
  const owner = matchRosterEntry(d, index.byId, index.byName);
  if (!owner && !isCrunchy(d.platform)) return null; // no live site owns this target

  // The roster entry mints the key when there is one; a Crunchy row speaks for itself.
  const target = owner
    ? boardTargetKey(owner.platform, entryIdentity(owner), d.environment)
    : boardTargetKey(d.platform, d.projectName, d.environment);
  if (!target) return null;
  return { owner, target, env: deployEnv(d.platform, d.projectName, d.environment, d.branch) };
}

/**
 * The deploy PROJECTS a live site monitors, both spellings of each — provider id and
 * project name — keyed by canonical platform. Environment-free on purpose (see the file
 * header): this answers "does anyone monitor this project", which the webhook door and
 * the Deployments tab ask, and which the SQL pre-filter needs as a set of literals.
 */
export function rosterDeployProjects(
  roster: RosterEntry[],
): Map<string, { ids: Set<string>; names: Set<string> }> {
  const out = new Map<string, { ids: Set<string>; names: Set<string> }>();
  for (const e of roster) {
    if (!ownsDeploys(e)) continue;
    const p = platformCanon(e.platform);
    if (!p) continue;
    let bucket = out.get(p);
    if (!bucket) out.set(p, (bucket = { ids: new Set(), names: new Set() }));
    if (e.providerProjectId) bucket.ids.add(e.providerProjectId);
    if (e.projectName) bucket.names.add(e.projectName);
  }
  return out;
}

/**
 * Does a live site monitor the project this deploy row belongs to? Provider id first,
 * name second — the same order `matchRosterEntry` uses, so a project renamed upstream
 * resolves through its id here exactly as it does in the fold.
 */
export function ownsDeployProject(
  d: DeployIdentity,
  projects: Map<string, { ids: Set<string>; names: Set<string> }>,
): boolean {
  if (isCrunchy(d.platform)) return true;
  const p = platformCanon(d.platform);
  if (!p) return false;
  const bucket = projects.get(p);
  if (!bucket) return false;
  if (d.providerProjectId && bucket.ids.has(d.providerProjectId)) return true;
  return bucket.names.has(d.projectName);
}
