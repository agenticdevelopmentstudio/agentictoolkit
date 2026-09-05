import { combinedStatus } from "../monitor/deploy-status";
import { deployEnv } from "../monitor/deploy-view";
import {
  deployIsBad,
  deployIsStuck,
  httpIsBad,
  PLATFORM_UNREACHABLE_POLLS,
  SOURCE_LABEL,
} from "../monitor/issue-sources";
import type { IssueSource } from "../monitor/issue-sources";
import { commitFirstLine } from "../monitor/format";
import { platformCanon } from "../monitor/overview";
import {
  entryIdentity, matchRosterEntry, ownedDeployTarget, rosterTargets, type RosterIndex,
} from "./ownership";
import { boardTargetKey, escapeSegment, unescapeSegment } from "./target-key";
import { ACTIVITY_WINDOW_MS, DEGRADED_CONFIRM_MS } from "./types";
import type {
  BoardFacts, DeployFact, EndpointFact, ErrorFact, Problem, RosterEntry,
} from "./types";

function stuckDetail(status: string, ageMs: number): string {
  return `stuck ${status} · ${Math.round(ageMs / 60_000)}m`;
}

/** The ledger's recorded onset times, keyed by target — shared by every Problem source
 *  so `since` survives restarts consistently rather than each source re-reading the
 *  ledger its own way. */
function onsetMap(facts: BoardFacts): Map<string, number> {
  return new Map(facts.ledger.map((l) => [l.target, l.openedAtMs]));
}

/**
 * A Problem's `since` — THE EARLIER of the two onsets we have, for every Problem source.
 *
 * There are two, and each is wrong on its own:
 *
 *  - The LEDGER's `openedAt` is the moment `applyBoardToLedger` first wrote the row, not
 *    the moment the thing broke. Nothing passes an observed onset to `openIssue`, so the
 *    column takes its `now` default. Preferring it made `since` get WORSE as the system
 *    learned more: an endpoint down since Monday reported Monday from `badSinceMs` on the
 *    first read, then Wednesday forever after the ledger row landed. And any respelling of
 *    a target (Task 12 did exactly that) closes every open row and reopens it under the new
 *    key, so on the first cycle after deploy every open problem would claim to have started
 *    the moment the branch shipped — a three-week wedged deploy rendering as "1m ago".
 *  - The OBSERVED onset (`badSinceMs`, the failed deploy's `createdAtMs`) is the real start
 *    of THIS observation, but it jumps FORWARD across successive failures: a target that
 *    fails again on every deploy would keep resetting to the newest failed build, losing
 *    the continuity the ledger is there to keep.
 *
 * `Math.min` takes the honest one in both directions, and the ledger's value keeps doing
 * the only job it was ever right for.
 *
 * Two rules — platform-unreachable and stale-prod — pass `nowMs` as the observed onset,
 * which looks like a placeholder and is not. Neither fact carries a timestamp for when the
 * condition BEGAN: a platform's `streak` counts consecutive failed polls without recording
 * the first, and a stale-prod fact is a comparison against the current cycle. `nowMs` is
 * the earliest instant either can honestly claim to have observed the condition, so it is
 * the correct value to hand this function, not a fallback. It also makes the `Math.min`
 * behave exactly right: on the FIRST cycle a problem has no ledger row and reads "just
 * now"; on every cycle after, `ledgerOnsetMs` is the older of the two and wins, so the
 * problem ages instead of resetting to now on each pass. Substituting an invented earlier
 * time would be a claim about when the world broke that nothing observed.
 */
function problemSince(ledgerOnsetMs: number | undefined, observedOnsetMs: number): string {
  return new Date(
    ledgerOnsetMs === undefined ? observedOnsetMs : Math.min(ledgerOnsetMs, observedOnsetMs),
  ).toISOString();
}

/** The literal prefix of a platform-health target. Private: read it through the two
 *  functions below, never by hand — that is the whole point of item 4.2. */
const PLATFORM_HEALTH_PREFIX = "platform-health|";

/**
 * The ONE spelling of a platform-health target: TWO segments, no trailing pipe — the
 * spelling already in the `issues` table (`issues.ts:611`). Deliberately not minted by
 * `boardTargetKey()`: a provider is not a deploy target, and giving it a third segment
 * would orphan every live platform-health row for no gain.
 *
 * EXPORTED with its inverse below, because a private minter with hand-rolled readers is
 * the same two-producers shape the minter exists to prevent: `derive-activity`'s
 * `issueKind` and `reads.ts`' `providerHealth` each spelled the prefix themselves, so the
 * spelling could only stay consistent by luck.
 */
export function platformHealthTarget(source: IssueSource): string {
  return `${PLATFORM_HEALTH_PREFIX}${source}`;
}

/**
 * The inverse: the provider a platform-health target names, or `null` if the target is
 * not one. Null is the answer for every deploy and endpoint target, so callers get the
 * "is it one?" test and the "which one?" answer from a single call and cannot drift
 * apart — the two questions were previously asked with two different string literals.
 *
 * Returns the source as written, unvalidated against `IssueSource`: the ledger holds rows
 * minted by older builds, and inventing a filter here would silently drop a live row.
 */
export function parsePlatformHealthTarget(target: string): string | null {
  return target.startsWith(PLATFORM_HEALTH_PREFIX)
    ? target.slice(PLATFORM_HEALTH_PREFIX.length)
    : null;
}

/** One deploy fact, already resolved to the board target that owns it. */
type OwnedDeploy = { owner: RosterEntry | null; target: string; env: string; fact: DeployFact };

/**
 * Does `a` supersede `b` as THE current row for their shared target? Newest wins.
 *
 * The tie-break matters because two rows CAN share a millisecond for one target: they are
 * the two spellings of one project either side of an upstream rename or an id adoption,
 * and 90-day retention keeps both sides in the table. Prefer the row that carries a
 * provider id — that is the row the CURRENT fetcher wrote, so it is the more current
 * spelling of the same project — then the greater `(projectName, environment)` purely to
 * make the order total.
 *
 * Any stable rule would do here; an unstable one would not. `deriveBoard` must return a
 * deep-equal board for the same facts (it is a pure function with a purity test), and
 * `applyBoardToLedger` keys on the target, so a winner that flapped with SQLite's row
 * order would flap the Problem's detail, links and commit on every cycle.
 */
function supersedes(a: DeployFact, b: DeployFact): boolean {
  if (a.createdAtMs !== b.createdAtMs) return a.createdAtMs > b.createdAtMs;
  const aId = a.providerProjectId !== null;
  const bId = b.providerProjectId !== null;
  if (aId !== bId) return aId;
  if (a.projectName !== b.projectName) return a.projectName > b.projectName;
  return (a.environment ?? "") > (b.environment ?? "");
}

/**
 * Collapse deploy facts to ONE PER BOARD TARGET — the authoritative reduction.
 *
 * `readBoardFacts` already grouped by the row's own (platform, projectName, environment),
 * but those columns are not the board's identity: `boardTargetKey` keys on the ROSTER
 * ENTRY's identity (`providerProjectId ?? projectName`), so the same target is reachable
 * by two spellings — a project renamed upstream, or one whose rows predate id adoption.
 * Both spellings survive in `deployments` for the retention window, so SQL hands the fold
 * two facts for one target and, without this, whichever came back last would win: the
 * board would show a failure that a later rebuild already fixed, or hide one behind a
 * stale success, depending on SQLite's row order.
 */
function collapseByTarget(
  facts: readonly DeployFact[],
  index: RosterIndex,
): Map<string, OwnedDeploy> {
  const out = new Map<string, OwnedDeploy>();
  for (const fact of facts) {
    const owned = ownedDeployTarget(fact, index);
    if (!owned) continue;
    const cur = out.get(owned.target);
    if (!cur || supersedes(fact, cur.fact)) out.set(owned.target, { ...owned, fact });
  }
  return out;
}

/**
 * The deploy half of the board. For every deploy target a LIVE roster entry owns, judge
 * that target's current deploy state: failed, or wedged mid-build, is a Problem.
 *
 * TWO facts per target, because a build in flight is not a verdict:
 *   - `facts.deploys` holds the latest CONCLUDED row — the target's standing verdict.
 *   - `facts.inFlightDeploys` holds the latest row still `building`/`queued`.
 *
 * When the in-flight row is NEWER, someone is retrying: the target keeps the verdict of
 * its last concluded row (a build that has not finished has proved nothing), and the
 * in-flight row is judged only for `stuck`. Collapsing both lists into one "latest row"
 * is the regression this replaces — the retry's `BUILDING` row won, the target looked
 * neither failed nor stuck, it dropped out of the Problems list, and `applyBoardToLedger`
 * read that as a RECOVERY and paged on-call while production still served the bad build.
 *
 * The union of the two target sets is iterated, not just the verdicts: a first-ever build
 * that wedges has no concluded row at all, and losing stuck detection for it would be the
 * opposite regression.
 */
export function deployProblems(facts: BoardFacts, nowMs: number, index?: RosterIndex): Problem[] {
  const idx = index ?? rosterTargets(facts.roster, facts.liveVercelProjects);
  const onset = onsetMap(facts);
  const verdicts = collapseByTarget(facts.deploys, idx);
  const inFlight = collapseByTarget(facts.inFlightDeploys, idx);
  const out: Problem[] = [];

  for (const target of new Set([...verdicts.keys(), ...inFlight.keys()])) {
    const verdict = verdicts.get(target);
    const running = inFlight.get(target);
    // A retry is only "current" if it is NEWER than the verdict. An in-flight row older
    // than the concluded one is a corpse the expirer has not swept yet.
    const retrying = running !== undefined && (verdict === undefined || supersedes(running.fact, verdict.fact));

    let judged: OwnedDeploy | undefined;
    let failed = false;
    let stuck = false;

    if (retrying && running) {
      const status = combinedStatus({ buildPhase: running.fact.buildPhase, deployPhase: running.fact.deployPhase });
      // Crunchy needs no exemption here: `crunchyPhases` only ever yields `failed`/`deployed`,
      // so a cluster's status is always a verdict and never reaches this branch.
      stuck = deployIsStuck(status, nowMs - running.fact.createdAtMs);
      if (stuck) judged = running;
    }
    if (!judged && verdict) {
      // Not stuck (or nothing in flight): the standing verdict decides. This is the line
      // that keeps a failure visible across a retry.
      failed = deployIsBad(combinedStatus({ buildPhase: verdict.fact.buildPhase, deployPhase: verdict.fact.deployPhase }));
      if (failed) judged = verdict;
    }
    if (!judged) continue;

    const d = judged.fact;
    const owner = judged.owner;
    // Deleted at Vercel → no Problem, however bad its last build was. Not tested here:
    // `ownedDeployTarget` drops a vanished project's rows before they ever reach the fold,
    // so `verdicts`/`inFlight` cannot hold one. That gate is also the only place the
    // narrowing belongs — Problems, Activity and `monitoredTargets` all reach it through
    // that one call, and the Deployments tab (`routes/reads.ts`'s `keepDeploy`) spells the
    // predicate out itself but off the SAME `index.vanishedVercel`. A second copy here
    // would be a fourth spelling, and disagreeing spellings are how the deploy rules came
    // to have no gate at all while `hooks.ts` documented one.
    const ageMs = nowMs - d.createdAtMs;
    out.push({
      target,
      // The RAW platform, not the canonicalized one: `IssueSource` carries the literal
      // `"cloudflare-pages"`, and `platformCanon` folds that to `"cloudflare"` — which is
      // not a member of the type. The deployments table already records the raw provider
      // string (`schema.ts:61`), and `issues.ts:373` (`source: d.platform as IssueSource`)
      // is the existing convention this reuses rather than re-deriving.
      source: d.platform as IssueSource,
      name: owner?.projectName ?? d.projectName,
      // The LOGICAL TIER `ownedDeployTarget` derived, never `d.environment` — see
      // `staleProdProblems` below, which has always drawn the same distinction.
      environment: judged.env,
      severity: "major",
      state: failed ? "failed" : "stuck",
      statusCode: null,
      detail: failed
        ? commitFirstLine(d.commitMessage)
        : stuckDetail(combinedStatus({ buildPhase: d.buildPhase, deployPhase: d.deployPhase }), ageMs),
      sourceUrl: d.sourceUrl,
      liveUrl: d.liveUrl,
      commitHash: d.commitHash,
      commitMessage: d.commitMessage,
      commitRepo: d.commitRepo,
      // Both off the JUDGED row, not the newest one: when a retry is wedged the branch an
      // operator needs is the wedged build's, and when the verdict stands it is the
      // failure's. `errorText` only ever arrives on the second of those — the sole writer
      // is `enrich-deploy-errors.ts`, which fetches the provider's reason for rows already
      // `buildPhase`/`deployPhase` = failed (fetchers and webhooks never set it,
      // `provider-deploy.ts:28`) — so a stuck row's is null by construction. Read off the
      // judged row anyway rather than special-cased: the field says what the row has, and
      // hardcoding the null here would be a second place to update if enrichment ever
      // learns to explain a wedge.
      branch: d.branch,
      errorText: d.errorText,
      since: problemSince(onset.get(target), d.createdAtMs),
    });
  }
  return out;
}

/**
 * Is this probe a confirmed problem? `down` is unambiguous and counts immediately.
 * `degraded` must persist DEGRADED_CONFIRM_MS first — a single slow response is not an
 * outage. The debounce is measured against the SERVER's persisted `badSince`, so every
 * viewer agrees; on the client it was measured per-tab against each tab's own clock.
 */
function probeConfirmed(e: EndpointFact, nowMs: number): boolean {
  if (!httpIsBad(e.status)) return false;
  if (e.status === "down") return true;
  return e.badSinceMs !== null && nowMs - e.badSinceMs >= DEGRADED_CONFIRM_MS;
}

/**
 * The HTTP/DNS half of the board. An endpoint is judged only while its roster entry is
 * ACTIVE and has HTTP monitoring ON — Requirement A: flipping either switch off removes
 * the Problem, because an unmonitored endpoint has no opinion to contribute.
 */
export function endpointProblems(facts: BoardFacts, nowMs: number): Problem[] {
  const byId = new Map(
    facts.roster.filter((e) => e.isActive && e.monitorHttp).map((e) => [e.endpointId, e]),
  );
  const onset = onsetMap(facts);
  const out: Problem[] = [];

  for (const e of facts.endpoints) {
    const owner = byId.get(e.endpointId);
    if (!owner) continue;
    if (!probeConfirmed(e, nowMs)) continue;

    // The endpoint's BARE id — the spelling the ledger has always held for an endpoint
    // problem (the retired `applyHttpIssues` wrote it, and its rows are still there). Both
    // reads.ts:437 and app.ts:91 separate endpoint problems from the rest by testing
    // `serviceSlugs.has(target)`; a decorated key would orphan every existing row and
    // silently reclassify every endpoint problem as a non-endpoint one.
    const target = e.endpointId;
    const down = e.status === "down";
    out.push({
      target,
      source: e.dnsOk ? "http" : "dns",
      name: owner.label,
      environment: owner.environment,
      severity: down ? "critical" : "minor",
      state: down ? "down" : "degraded",
      statusCode: e.statusCode,
      detail: e.dnsOk ? (e.statusCode ? `HTTP ${e.statusCode}` : "no response") : "DNS did not resolve",
      sourceUrl: null,
      liveUrl: owner.url,
      commitHash: null,
      commitMessage: null,
      commitRepo: null,
      // An HTTP probe knows nothing about a build: no ref, no provider text.
      branch: null,
      errorText: null,
      since: problemSince(onset.get(target), e.badSinceMs ?? e.checkedAtMs),
    });
  }
  return out;
}

/**
 * Provider status pages — a useful click target while a platform is unreachable. Copied
 * verbatim from `issues.ts:571-576` as that recorder is retired in Task 12.
 */
const PLATFORM_STATUS_URL: Partial<Record<IssueSource, string>> = {
  vercel: "https://www.vercel-status.com",
  "cloudflare-pages": "https://www.cloudflarestatus.com",
  railway: "https://status.railway.app",
  crunchy: "https://status.crunchybridge.com",
};

/**
 * What an unreachable provider COSTS, per provider. The deploy platforms all cost the same
 * thing and share the default; GlitchTip does not deploy anything, and copy that told an
 * operator their deploys were unmonitored would name a consequence the status cannot
 * support. What it actually costs is the error feed — and, because `errorProblems` freezes
 * its rows while this is open, the fact that the error rows have stopped updating.
 */
const PLATFORM_UNREACHABLE_COST: Partial<Record<IssueSource, string>> = {
  glitchtip: "application errors can't be monitored — the error rows below are frozen at their last poll",
};

/**
 * A provider API we cannot reach. Debounced by the persisted consecutive-failure streak
 * so a single 429 or timeout never surfaces a Problem. A platform we do not poll at all
 * (no active integration, or no token) is never judged — "not configured" is not "broken".
 *
 * Severity, detail and sourceUrl are carried over verbatim from the retired
 * `applyPlatformIssues`, so a platform row reads exactly as it always has. This
 * is a monitor-side warning, not a customer-facing outage: `minor` is what renders it
 * amber rather than red, so promoting it to `major` here would repaint the board.
 */
export function platformProblems(facts: BoardFacts, nowMs: number): Problem[] {
  const onset = onsetMap(facts);
  const out: Problem[] = [];
  for (const p of facts.platforms) {
    if (!p.configured) continue;
    if (p.ok || p.streak < PLATFORM_UNREACHABLE_POLLS) continue;
    const target = platformHealthTarget(p.source);
    out.push({
      target,
      source: p.source,
      name: SOURCE_LABEL[p.source],
      environment: null,
      severity: "minor",
      state: "unreachable",
      statusCode: null,
      detail: `${SOURCE_LABEL[p.source]} API unreachable — ${PLATFORM_UNREACHABLE_COST[p.source] ?? "deploys for this platform can't be monitored"}`,
      sourceUrl: PLATFORM_STATUS_URL[p.source] ?? null,
      liveUrl: null,
      commitHash: null,
      commitMessage: null,
      commitRepo: null,
      // A provider being unreachable is about the provider, not about any one build.
      branch: null,
      errorText: null,
      since: problemSince(onset.get(target), nowMs),
    });
  }
  return out;
}

/**
 * A Vercel project whose LIVE production deploy is errored or behind its latest build.
 * Distinct from a failed deploy: this judges what is actually serving, not what last
 * built. Suppressed when the same target already has a deploy Problem, so one broken
 * project is one row rather than two.
 *
 * `index.vanishedVercel` narrows this to projects that still exist upstream — the SAME
 * set `ownedDeployTarget` gates deploy rows with, computed once by `rosterTargets`
 * instead of the second copy this function used to keep, so a deleted project cannot be
 * absent from one Vercel rule and present in the other. It refuses to narrow at all on
 * an empty or all-vanished read: a bad token read is indistinguishable from mass
 * deletion, and silencing the whole fleet is worse than leaving the rows up for a human.
 *
 * Environment (and therefore severity/detail) is DERIVED by `deployEnv`, never trusted
 * from `s.environment` — the same call `ownedDeployTarget` makes for a deploy row, so the
 * two halves of the board cannot badge one project two ways. Branch first (here the
 * project's CONFIGURED production branch, from `deploy_project_meta`, because a stale-prod
 * fact judges a project rather than any one build), then the project-name rule. A stale
 * STAGING/TESTING project is a real signal but not a production incident: `major` would
 * misrepresent it, and a detail string that still says "production" would be actively
 * wrong about what's stale.
 */
export function staleProdProblems(
  facts: BoardFacts,
  nowMs: number,
  suppress: ReadonlySet<string>,
  index?: RosterIndex,
): Problem[] {
  const { byId, byName, vanishedVercel } = index ?? rosterTargets(facts.roster, facts.liveVercelProjects);
  const onset = onsetMap(facts);
  const out: Problem[] = [];
  // `vercel_prod_state` is keyed on the project NAME, but the target is minted from the
  // roster entry's IDENTITY — so two stale rows for two names whose roster entries share
  // one `providerProjectId` (the two spellings of a renamed project) mint one target
  // twice. `Board.problems` guarantees one row per target; first wins, which is stable for
  // a given `facts.staleProd` and is all the purity contract needs.
  const seen = new Set<string>();

  for (const s of facts.staleProd) {
    if (vanishedVercel.has(s.projectName)) continue;
    // A `StaleProdFact` already carries the four identifying columns `matchRosterEntry`
    // reads, so it is passed as-is rather than padded out into a synthetic deploy row.
    // This is also the OWNERSHIP half of the test the old `configured.vercel.has(...)`
    // line was doing double duty for — that set was the roster's own project names, so
    // an unowned project failed it here exactly as it fails the lookup below.
    const owner = matchRosterEntry(s, byId, byName);
    if (!owner) continue;
    const target = boardTargetKey(owner.platform, entryIdentity(owner), s.environment);
    if (!target || suppress.has(target) || seen.has(target)) continue;
    seen.add(target);
    // Branch first, exactly as `ownedDeployTarget` does it for a deploy row — here the
    // branch is the project's CONFIGURED production branch, because a stale-prod fact is a
    // verdict about a project rather than about any one build.
    const env = deployEnv("vercel", s.projectName, s.environment, s.branch);
    const severity = env === "production" ? "major" : "minor";
    const detail = env === "production" ? s.detail : (s.detail?.replace(/\bproduction\b/g, env) ?? null);
    out.push({
      target,
      source: "vercel",
      name: owner.projectName ?? s.projectName,
      environment: env,
      severity,
      state: "stale",
      statusCode: null,
      detail,
      sourceUrl: s.sourceUrl,
      liveUrl: s.liveUrl,
      commitHash: null,
      commitMessage: null,
      commitRepo: null,
      // The project's CONFIGURED production branch — the same field `env` above was read
      // from. No provider text: staleness is a verdict we derived, not one Vercel reported.
      branch: s.branch,
      errorText: null,
      since: problemSince(onset.get(target), nowMs),
    });
  }
  return out;
}

/** The literal prefix of an error target. Private, for the same reason
 *  `PLATFORM_HEALTH_PREFIX` is: read it through the pair below. */
const ERRORS_PREFIX = "errors|";

/**
 * The ONE spelling of an error target: `errors|<glitchtip project>`, TWO segments.
 *
 * Namespaced rather than keyed on a site, and the `uniq_open_issue_per_target` partial
 * unique index is why it has to be. The ledger permits exactly one OPEN row per target
 * (`schema.ts:121`), so an error Problem keyed on a site slug would fight that site's own
 * HTTP Problem for the row — one would open, the other would silently fail its insert or
 * overwrite it, and which one won would depend on fold order. Two segments also keeps it
 * clear of `boardTargetKey`'s three-segment deploy keys and of the BARE endpoint uuids,
 * so no existing target can ever collide with one of these.
 *
 * The project segment is ESCAPED with the same pair `boardTargetKey` uses, because the
 * value is not safe by construction: `glitchtip.ts` falls back from the project's `slug`
 * to its free-form `name`, in a file whose own note says the response shape was never
 * verified against a live instance. A raw `|` would mint a target that `parseErrorsTarget`
 * reads back as a different string — so the fold would re-derive a key that never matches
 * the ledger row it just wrote, opening a fresh row every cycle against
 * `uniq_open_issue_per_target` and never being able to close the old one.
 */
export function errorsTarget(project: string): string {
  return `${ERRORS_PREFIX}${escapeSegment(project)}`;
}

/** The inverse: the GlitchTip project an error target names, or null if it is not one. */
export function parseErrorsTarget(target: string): string | null {
  return target.startsWith(ERRORS_PREFIX)
    ? unescapeSegment(target.slice(ERRORS_PREFIX.length))
    : null;
}

/**
 * Error levels that count as a Problem. GlitchTip also groups `warning`, `info` and
 * `debug` issues, and those are diagnostics rather than incidents — surfacing them would
 * put the board permanently red on a healthy fleet, which is the failure mode that makes
 * a status board stop being read.
 *
 * A null level is NOT judged: it means the row predates the field or GlitchTip omitted it,
 * and "we don't know how bad this is" must not read as "bad".
 */
export const ERROR_JUDGED_LEVELS = new Set(["error", "fatal"]);

/**
 * How recently an unresolved error must have FIRED to count.
 *
 * Without it the rule reads GlitchTip's backlog rather than the fleet's health: an issue
 * nobody resolved in the UI stays `is:unresolved` forever, so a bug fixed in March would
 * still be holding the board red today. `lastSeen` is the honest test — the error is only
 * a current problem if it is currently happening. 24h matches ACTIVITY_WINDOW_MS, which is
 * already this board's definition of "recent".
 */
export const ERROR_RECENT_MS = ACTIVITY_WINDOW_MS;

function judgedError(e: ErrorFact, nowMs: number, frozen: boolean): boolean {
  if (!ERROR_JUDGED_LEVELS.has((e.level ?? "").toLowerCase())) return false;
  // While the feed is frozen the recency test is SUSPENDED — see `errorFeedFrozen`. The
  // rows cannot age honestly when nothing is refreshing them, and letting our own blindness
  // expire them would close the problem as `recovered`.
  if (frozen) return true;
  // No lastSeen at all → cannot show it is current, so it is not judged. Erring toward
  // silence here matches the null-level rule above.
  return e.lastSeenMs !== null && nowMs - e.lastSeenMs <= ERROR_RECENT_MS;
}

/**
 * Is the errors feed STALE because we cannot reach GlitchTip — as opposed to quiet?
 *
 * The two are indistinguishable from the `errors` table alone: a failed poll persists
 * nothing (`collect.ts`), so every row's `lastSeen` simply stops advancing. Exactly
 * `ERROR_RECENT_MS` later the recency rule would drop every row, `errorProblems` would
 * return nothing, and `applyBoardToLedger` would close the open row as `recovered` — an
 * all-clear page for errors nobody has been able to observe for a day.
 *
 * `platform_health_state` is what tells them apart. `collectTelemetry` records a
 * `glitchtip` observation on every cycle exactly as the deploy pollers do for theirs, so
 * the same debounced `platformProblems` rule that reports an unreachable Vercel now
 * reports an unreachable GlitchTip — and this reads the raw flag to FREEZE the error rows
 * in their last observed state until the feed comes back. Absent row → not frozen: a
 * deployment that has never recorded an observation must not have its errors pinned.
 */
function errorFeedFrozen(facts: BoardFacts): boolean {
  const gt = facts.platforms.find((p) => p.source === "glitchtip");
  return gt !== undefined && gt.configured && !gt.ok;
}

/**
 * May this GlitchTip project mint a Problem? `null` allowlist → every project.
 *
 * Applied in BOTH `errorProblems` and `monitoredTargets`, from one function, because the
 * two must agree exactly: a project judged by one and not the other either opens a row
 * nothing can close, or closes a live row silently as `unmonitored`.
 */
function allowedProject(facts: BoardFacts, project: string): boolean {
  return facts.errorProjectAllowlist === null || facts.errorProjectAllowlist.includes(project);
}

/**
 * Worst-first: occurrence count descending, ties broken on `issueKey`. Ranks the list ONCE
 * per project, so the headline the row shows and the top-five block in `errorText` are the
 * same order rather than two sorts that could disagree.
 *
 * The tie-break is not cosmetic:
 * `deriveBoard` is pure and has a test that asserts a deep-equal board for the same facts,
 * and `applyBoardToLedger` rewrites the row's detail and sourceUrl every cycle — so a
 * winner that flapped between two equally-frequent issues would rewrite the ledger row and
 * republish the board on every pass, forever.
 */
function byImpact(a: ErrorFact, b: ErrorFact): number {
  if (a.count !== b.count) return b.count - a.count;
  return a.issueKey < b.issueKey ? -1 : a.issueKey > b.issueKey ? 1 : 0;
}

/** Titles run to a full exception message; the row is one line. */
function clip(text: string, max = 120): string {
  return text.length <= max ? text : `${text.slice(0, max - 1)}\u2026`;
}

/**
 * Application errors reported by GlitchTip — the fleet's only signal about code that is
 * broken while its host is perfectly reachable. An HTTP probe cannot see this: the page
 * returns 200 and throws in the browser, or the route succeeds and the background job
 * dies. Everything else on this board watches whether a thing RESPONDS.
 *
 * ONE ROW PER GLITCHTIP PROJECT, not per error group. The fleet has exactly one project
 * today, so per-group rows would mean the board's problem list is however many distinct
 * bugs exist — a list that no longer says "what is wrong with the fleet", which is what
 * the Problems pane is for. The count, the worst title and a link into GlitchTip carry
 * the detail; GlitchTip itself is the right place to work through them.
 *
 * Gated on `errorsConfigured` — see `BoardFacts.errorsConfigured` for why judging frozen
 * rows would pin a Problem open that nothing could close.
 */
export function errorProblems(facts: BoardFacts, nowMs: number): Problem[] {
  if (!facts.errorsConfigured) return [];
  const onset = onsetMap(facts);
  const frozen = errorFeedFrozen(facts);

  const byProject = new Map<string, ErrorFact[]>();
  for (const e of facts.errors) {
    if (!allowedProject(facts, e.project)) continue;
    if (!judgedError(e, nowMs, frozen)) continue;
    const list = byProject.get(e.project);
    if (list) list.push(e);
    else byProject.set(e.project, [e]);
  }

  const out: Problem[] = [];
  for (const [project, list] of byProject) {
    const target = errorsTarget(project);
    const ranked = [...list].sort(byImpact);
    const top = ranked[0]!;
    // A `fatal` is the level GlitchTip reserves for a crash, so it earns the same weight
    // as a stale production deploy. Ordinary `error` rows stay `minor` (amber): the site
    // is serving, and painting the board red for a handled exception is how a board gets
    // ignored. Never `critical` — that is reserved for an endpoint that is actually down.
    const fatal = list.some((e) => (e.level ?? "").toLowerCase() === "fatal");
    // The EARLIEST first-seen among the issues still counted — the honest onset of "this
    // project is erroring", since that run has not stopped. Unlike the platform and
    // stale-prod rules, this fact carries a real observed onset, so `nowMs` is not needed
    // as a stand-in.
    //
    // CLAMPED to the judging window, and that is the whole correctness of it. GlitchTip's
    // `firstSeen` is ALL-TIME: a low-frequency exception first seen in March that is still
    // unresolved would date today's incident to March. `byRecency` sorts oldest-first, so
    // that row would pin itself above a critical outage two minutes old, and `since` would
    // tell every reader the fleet has been degraded for months. Nothing corrects it later
    // either — `firstSeen` is deliberately absent from the upsert's set-list, so the stored
    // value is frozen at whatever the first poll saw. An issue outside the window is not
    // part of the incident we are reporting, by this rule's own definition of the incident.
    const firstSeen = list
      .map((e) => e.firstSeenMs)
      .filter((ms): ms is number => ms !== null);
    const windowStartMs = nowMs - ERROR_RECENT_MS;
    const observedOnsetMs =
      firstSeen.length > 0 ? Math.max(Math.min(...firstSeen), windowStartMs) : nowMs;

    out.push({
      target,
      source: "glitchtip",
      name: project,
      environment: null,
      severity: fatal ? "major" : "minor",
      state: "erroring",
      statusCode: null,
      detail: `${list.length} unresolved error${list.length === 1 ? "" : "s"} \u00b7 ${clip(top.title)}`,
      sourceUrl: top.permalink,
      liveUrl: null,
      commitHash: null,
      commitMessage: null,
      commitRepo: null,
      // GlitchTip's issue summary carries no ref. The individual EVENTS can carry a
      // release, but the grouped issue this fact came from does not, and inventing one
      // from the newest event would attribute a long-running bug to whichever build
      // happened to hit it last.
      branch: null,
      // The provider's own words, which is exactly what the details pane's error block is
      // for — the top few titles, so an operator sees WHAT is failing without leaving the
      // board. Bounded: a project with fifty distinct errors must not paste fifty lines.
      errorText: ranked
        .slice(0, 5)
        .map((e) => `${e.count}\u00d7 ${clip(e.title, 160)}`)
        .join("\n"),
      since: problemSince(onset.get(target), observedOnsetMs),
    });
  }
  return out;
}

/**
 * Every target the board is currently watching, problem or not. The ledger writer needs
 * this to tell a RECOVERED target (still watched, no longer failing → alert) from an
 * UNMONITORED one (no longer watched → close silently). Without it every close looks
 * like a recovery, and a site removed from config pages on-call as if it healed.
 */
export function monitoredTargets(facts: BoardFacts, index?: RosterIndex): string[] {
  const idx = index ?? rosterTargets(facts.roster, facts.liveVercelProjects);
  const out = new Set<string>();

  for (const e of facts.roster) {
    if (!e.isActive) continue;
    if (e.monitorHttp) out.add(e.endpointId);
    if (e.monitorDeploys && !e.ignoreProjectWarning) {
      // The account-mirror gate again, because this loop reaches the roster DIRECTLY and
      // so cannot go through `ownedDeployTarget`. It has to agree with it: a project
      // deleted at Vercel that stayed "watched" here would have its open row closed as a
      // RECOVERY — paging on-call to say a build passed — which is the precise outcome
      // the silent `unmonitored` close exists to prevent.
      if (platformCanon(e.platform) === "vercel" && e.projectName && idx.vanishedVercel.has(e.projectName)) continue;
      const t = boardTargetKey(e.platform, entryIdentity(e), e.environment);
      if (t) out.add(t);
    }
  }
  for (const p of facts.platforms) {
    if (p.configured) out.add(platformHealthTarget(p.source));
  }
  // Error targets, from THREE sources; the second is the one that matters most.
  //
  // The projects currently erroring are the obvious half. The other half is every error
  // target with an OPEN ledger row, because the watch set has to survive the recovery it
  // exists to report: `facts.errors` holds only what is still unresolved upstream, so the
  // moment a project's last error clears it vanishes from that list — and a target missing
  // from `monitoredTargets` closes SILENTLY as `unmonitored` (`issues.ts:322`), the one
  // close that never pages. Fixing the errors would be the single outcome nobody heard
  // about. `facts.ledger` is exactly the open rows (`facts.ts:344`, `resolved_at is null`)
  // and `applyBoardToLedger` runs AFTER this fold, so the row being closed this cycle is
  // still in it — which is what turns the close into a `recovered` alert.
  //
  // Reading the ledger rather than "every project the errors table has ever held" is also
  // what keeps this off a full scan of a table nothing prunes, on a path that runs for
  // /live, /snapshot, /fleet, /badge and every SSE publish. It is the tighter set too: a
  // project that stopped erroring last year stops being watched once its row is closed,
  // instead of being carried forever.
  //
  // Dropped entirely when GlitchTip is unconfigured, so switching it off closes any open
  // error row silently rather than paging a recovery that never happened.
  if (facts.errorsConfigured) {
    for (const e of facts.errors) {
      if (allowedProject(facts, e.project)) out.add(errorsTarget(e.project));
    }
    for (const l of facts.ledger) {
      if (parseErrorsTarget(l.target) !== null) out.add(l.target);
    }
    // The THIRD source, and it is about the Activity feed rather than the ledger.
    // `deriveActivity` drops any issue event whose target is not in this set, and an error
    // target is the only kind whose membership is EPHEMERAL — endpoint, deploy and
    // platform-health targets are re-derived from the roster and config every cycle, so
    // they are present whether or not anything is wrong. Without this, one cycle after an
    // error row closed, its `opened` and `[app errors] resolved` rows would both vanish
    // from Recent Activity and the incident would have no trail. Bounded by the activity
    // window that produced `issueEvents`, and additive only: an event whose row is still
    // open is already covered by the ledger above, so this can open no new close path.
    for (const e of facts.issueEvents) {
      if (parseErrorsTarget(e.target) !== null) out.add(e.target);
    }
  }
  // A Railway deploy target is keyed per ENVIRONMENT, and one roster entry names only
  // its own env — so a target the roster reaches by NAME counts as watched too.
  //
  // Crunchy is watched with no roster entry at all, the same carve-out `deployProblems`
  // makes: a cluster has no HTTP host for a site to own. Omitting it here would make
  // every crunchy close look UNMONITORED, so a cluster that genuinely recovered would
  // never page on-call to say so.
  //
  // BOTH state lists are read: a target whose only rows are still in flight can be judged
  // `stuck` by `deployProblems`, and a Problem on a target this function omits is one the
  // ledger writer closes as unmonitored the instant it is opened.
  //
  // THE SAME CALL `deployProblems` MAKES, not a re-spelling of its rules. This loop used
  // to open-code them: a crunchy row short-circuited to its OWN `d.projectName` key before
  // the owner lookup ran, and the preview gate was missing. The narrow, concrete failure is
  // a crunchy row that a roster entry DOES claim — `deployProblems` mints its target from
  // the OWNER's identity (`crunchy|<providerProjectId>|`), this minted it from the row's
  // name (`crunchy|<projectName>|`), so the Problem opened under one spelling and was
  // closed as "unmonitored" under the other on the very next sweep, silently, with no
  // recovery page. The general point is the one this whole file exists to make: two
  // functions answering "which targets are these deploy rows" is the shape that keeps
  // producing that bug, whatever the day's spelling difference happens to be.
  for (const d of [...facts.deploys, ...facts.inFlightDeploys]) {
    const owned = ownedDeployTarget(d, idx);
    if (owned) out.add(owned.target);
  }
  return [...out].sort();
}
