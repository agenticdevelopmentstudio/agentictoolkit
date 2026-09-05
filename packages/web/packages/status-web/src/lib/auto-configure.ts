// ---------------------------------------------------------------------------
// The browser's side of "Auto Configure": an ADAPTER onto the shared engine, plus the
// two detail blocks only this UI renders.
//
// The matching itself is @agentic-toolkit/deploy-platform/engine's — the SAME code the
// Hono server runs behind POST /auto-configure. This app used to carry a hand-written
// copy of the planner, the classifier and the runner, which is one piece of knowledge in
// two places with nothing checking they agree: the browser and the server could
// canonicalize a host differently and file the same project under different sites
// depending on which button the operator pressed.
//
// MATCH-ONLY, and that is a property of the CALL, not of a private runner: `runMatch`
// never passes the engine's `create`, so an unmonitored project is left for the operator
// and these per-platform "Match" / "Match all" buttons can't graft a phantom site.
// CREATION stays on the SERVER — the global "Auto Configure" review flow POSTs, and site
// creation there sees every site in one transaction-scoped snapshot, so it can file a new
// site under the group that already owns its domain family and disambiguate a taken slug.
// Neither is answerable from a browser.
// ---------------------------------------------------------------------------
import * as defaultApi from "../api/monitored-sites";
import type { EndpointView, SiteView } from "../api/monitored-sites";
import { autoConfigureOptedOut } from "./config-status";
import {
  runAutoConfigure,
  type EndpointLite,
  type PlanOpts,
  type ProjectLite,
  type SkippedAdd,
  type StatusAddApi,
} from "@agentic-toolkit/deploy-platform/engine";

/** The monitored-sites client, as the engine's I/O port. The engine is pure
 *  I/O-injection: it names the calls it makes and the caller supplies them, so this is the
 *  browser's counterpart to the server's `statusAdapter` (direct config-store calls).
 *
 *  The create methods are wired even though `runMatch` never reaches them — they exist on
 *  the client, and an adapter that threw for half its port would be a trap for the next
 *  caller. What keeps this match-only is the absent `create` option, not a crippled API. */
export function statusApi(api: typeof defaultApi = defaultApi): StatusAddApi {
  // The probe/monitoring fields are this board's and mean nothing to the planner, so they
  // stop here — all but the opt-out, which the engine's own `endpointUnconfigured` reads.
  // It carries the FOLD of both of this board's ways to say "leave this alone", the same
  // one the server's adapter carries; dropping it is what had the endpoint axis wire every
  // opted-out monitor anyway.
  const toLite = (e: EndpointView): EndpointLite => ({
    id: e.id,
    siteId: e.siteId,
    url: e.url,
    kind: e.kind,
    environment: e.environment,
    platform: e.platform,
    deployProject: e.deployProject,
    ignoreProjectWarning: autoConfigureOptedOut(e),
  });
  const toSiteLite = (s: SiteView): { id: string; slug: string; groupId: string } => ({ id: s.id, slug: s.slug, groupId: s.groupId });
  return {
    listAllEndpoints: async () => (await api.listAllEndpoints()).map(toLite),
    listSites: async () => (await api.listSites()).map(toSiteLite),
    updateEndpoint: (id, body) => api.updateEndpoint(id, body as Parameters<typeof api.updateEndpoint>[1]),
    createSite: async (body) => ({ id: (await api.createSite({ name: body.name, slug: body.slug, groupId: body.groupId })).id }),
    createEndpoint: async (siteId, body) => toLite(await api.createEndpoint(siteId, body as Parameters<typeof api.createEndpoint>[1])),
    deleteSite: (id) => api.deleteSite(id),
  };
}

/** A project that succeeded, with something the operator has to be told (the run's `notes`,
 *  and the same shape the server's POST /auto-configure response carries). */
export interface NotedAdd {
  project: string;
  note: string;
}

/** A match run as this UI displays it: a COUNT of what was matched, and the leftovers/notes
 *  named by project. The engine returns the projects themselves (it is generic over the
 *  project type, and its other caller reports per-project detail); flattening to names is
 *  what the dialogs and inline error lines render. */
export interface MatchRun {
  /** Existing endpoints wired to their project (this axis never creates). */
  added: number;
  /** Projects that couldn't be matched (no site yet, conflict, or error) with a reason. */
  skipped: SkippedAdd[];
  /** Projects that WERE matched, with something the operator has to be told — today, a
   *  monitor taken over from a project the platform no longer has. Rewriting wiring they
   *  can still see on the board is a change we owe them an explanation for. */
  notes: NotedAdd[];
}

/**
 * Match every project in `addable` to the EXISTING site that monitors its domain, wiring
 * that endpoint's platform + deployProject. The engine sequences the batch (each match sees
 * the previous one's wiring, so a project's staging and prod variants resolve against the
 * same site) and is resilient — one project failing lands in `skipped`, never fatal.
 *
 * No `create`: the engine's `created` list is empty by construction here, so `added` is the
 * whole of what this run changed.
 */
export async function runMatch(
  addable: ProjectLite[],
  opts: { api?: StatusAddApi; liveProjects?: PlanOpts["liveProjects"]; onProgress?: (done: number, total: number) => void } = {},
): Promise<MatchRun> {
  const { added, skipped, notes } = await runAutoConfigure(addable, {
    api: opts.api ?? statusApi(),
    liveProjects: opts.liveProjects,
    onProgress: opts.onProgress,
  });
  return {
    added: added.length,
    skipped: skipped.map((s) => ({ project: s.project.projectName, reason: s.reason })),
    notes: notes.map((n) => ({ project: n.project.projectName, note: n.note })),
  };
}

/** How many "project: reason" lines a detail block names before it summarizes the rest. */
export const SKIP_DETAIL_LINES = 5;

/** One `header` + at most {@link SKIP_DETAIL_LINES} "• project: why" lines, with the rest
 *  counted — the shared shape of every per-project block appended to the run summary, so a
 *  second block can't drift into a different one. Empty input → empty string (no header). */
function detailBlock(header: string, rows: { project: string; why: string }[]): string {
  if (!rows.length) return "";
  const shown = rows.slice(0, SKIP_DETAIL_LINES).map((r) => `• ${r.project}: ${r.why}`);
  const rest = rows.length - shown.length;
  return `\n\n${header}\n${shown.join("\n")}${rest > 0 ? `\n…and ${rest} more` : ""}`;
}

/**
 * The per-project WHY behind a run's leftovers, as a block appended to the engine's
 * `summarizeAutoConfigure` sentence. Names at most {@link SKIP_DETAIL_LINES} projects and
 * counts the rest, so the dialog can't become a log dump.
 *
 * Kept out of `summarizeAutoConfigure` because that function is the shared core summary of
 * what the engine DID; this is the diagnostic beside it. It exists because the counts alone
 * can't tell a benign "nothing to do here" apart from a run that fails identically every
 * time (a name collision, a conflicting wiring) — which is exactly how a permanently stuck
 * project stayed invisible behind a bare `skipped: 1`.
 */
export function skipDetail(rows: SkippedAdd[] | undefined): string {
  return detailBlock("Left alone:", (rows ?? []).map((r) => ({ project: r.project, why: r.reason })));
}

/**
 * The per-project block for work that SUCCEEDED with a caveat — a new site filed under the
 * group that already owns its domain family rather than the one the operator selected, or a
 * monitor taken over from a project the platform no longer has. Separate from
 * {@link skipDetail} because these projects WERE configured; the operator just needs to know
 * what we decided on their behalf, since silence reads as "exactly as you asked".
 *
 * The header is deliberately neutral ("Also:") and every line self-describing: two different
 * caveats now share this block, and a header naming only one of them ("Filed elsewhere:")
 * mislabels the other — a wrong explanation is worse than none.
 */
export function noteDetail(rows: NotedAdd[] | undefined): string {
  return detailBlock("Also:", (rows ?? []).map((r) => ({ project: r.project, why: r.note })));
}
