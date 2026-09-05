"use client";
import { createContext, useCallback, useContext, useMemo, useRef, useState, type ReactElement, type ReactNode } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { type DeployProject, fetchUnconfigured } from "../hooks/use-deploy-projects";
import { summarizeAutoConfigure } from "@agentic-toolkit/deploy-platform/engine";
import { skipDetail, noteDetail } from "../lib/auto-configure";
import { listGroups } from "../api/monitored-sites";
import { projectKeyOf, uniqueByProject } from "../lib/project-key";
import { plural } from "../lib/format";
import { msg } from "../lib/err";
import { StatusAlert } from "./StatusAlert";
import { AutoConfigureReview, type ReviewProject } from "./AutoConfigureReview";
import { invalidateConfigQueries } from "../hooks/use-config-status";

interface AutoConfigureContext {
  run: () => Promise<void>;
  busy: boolean;
  /** Batch progress. Always null now the engine runs server-side in ONE request (a single
   *  POST has no incremental frames) — kept in the shape so the button/modal render "…". */
  progress: { done: number; total: number } | null;
}

const Ctx = createContext<AutoConfigureContext | null>(null);

interface ReviewState {
  pending: DeployProject[];
  groups: { id: string; name: string }[];
}

/** The server's POST /auto-configure run summary — the counts the display message is built
 *  from (shape matches core `AutoConfigureSummary`). */
interface AutoConfigureRunResult {
  added: number;
  created: number;
  wired: number;
  skipped: number;
  noDomain: number;
  /** true → Vercel IS configured, but the server could not verify its project list this run
   *  (a truncated page walk, an API failure), so it deliberately contributed NO Vercel
   *  suggestions rather than offering projects from a table it can't vouch for.
   *  Surfaced because "nothing to match" and "we didn't look" must not read the same.
   *  FALSE when no Vercel token is configured at all — that is a steady state, not news. */
  vercelUnverified?: boolean;
  /** How many projects that skip cost. Without it the caveat lands next to a row of zeroes
   *  that reads as "nothing to do". */
  vercelSkipped?: number;
  /** WHY each leftover was left. The counts alone can't tell a benign "nothing to do here"
   *  apart from a run that fails identically every time (a name collision, a conflicting
   *  wiring) — which is exactly how a permanently stuck project stayed invisible. */
  skippedDetail?: { project: string; reason: string }[];
  /** Projects that WERE configured, but not the way asked — today, a new site filed under
   *  the group that already owns its domain family rather than the selected one. Rendered
   *  because an override nobody is told about reads as "it went where you said". */
  notes?: { project: string; note: string }[];
}

async function postAutoConfigure(body: {
  ignore: { platform: string; projectName: string }[];
  create: { groupId: string; forceGroup?: boolean } | null;
}): Promise<AutoConfigureRunResult> {
  const r = await fetch("/api/auto-configure", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`auto-configure ${r.status}`);
  return r.json() as Promise<AutoConfigureRunResult>;
}

/**
 * Owns the "Auto Configure" action + its review modal + result dialog at a stable
 * point in the tree, so they survive the TRIGGER unmounting (configuring drops the
 * banner's count to 0 and unmounts it). Both "Auto Configure" buttons share this.
 *
 * The flow: fetch the server's unconfigured partition. If any project is UNMONITORED,
 * open the review modal so the operator can ignore the ones they don't want (e.g. the
 * many Railway infra projects) before the rest are configured. Applying POSTs the chosen
 * ignores + create-group to the server, which runs the WHOLE engine in one request —
 * match each kept project to the site that monitors its domain, CREATE a site for one no
 * site monitors yet (in the chosen group), and wire any straggler endpoint whose host is
 * one of a project's domains. When nothing is unmonitored, it skips the modal and just
 * asks the server to wire stragglers.
 */
export function AutoConfigureProvider({ children }: { children: ReactNode }): ReactElement {
  const queryClient = useQueryClient();
  const [message, setMessage] = useState<string | null>(null);
  const [review, setReview] = useState<ReviewState | null>(null);
  const [busy, setBusy] = useState(false);
  // A ref guard (not `busy`) so two activations in the same tick — keyboard repeat,
  // double-tap — can't both pass before React commits state.
  const running = useRef(false);

  // The shared I/O: POST the operator's ignore/create intent to the server (which ignores
  // the checked projects, matches + creates + wires stragglers), invalidate, and return the
  // summary message. Callers own busy/message so this stays a pure worker.
  const configure = useCallback(
    async (pending: DeployProject[], ignoreKeys: Set<string>, newSiteGroupId: string, forceGroup = false): Promise<string> => {
      // Ignore is project-level, so collapse the per-env entries to one row per project
      // before sending (otherwise a 3-env Railway project writes the same ignore ×3).
      const ignore = uniqueByProject(pending.filter((p) => ignoreKeys.has(projectKeyOf(p)))).map((p) => ({
        platform: p.platform,
        projectName: p.projectName,
      }));
      const result = await postAutoConfigure({ ignore, create: newSiteGroupId ? { groupId: newSiteGroupId, forceGroup } : null });
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["deploy-projects"] }),
        invalidateConfigQueries(queryClient),
        // The /api/live snapshot carries the self-check + "no endpoints configured"
        // state; refresh it too so the Monitored-sites panel reflects the new monitors
        // immediately instead of after the next ~30s poll.
        queryClient.invalidateQueries({ queryKey: ["live"] }),
      ]);
      // Appended here rather than inside `summarizeAutoConfigure`: that function is the
      // shared core summary of what the engine DID, and this is a caveat about what the
      // server declined to look at.
      // Name the SIZE of what was skipped: the counts above are all 0 on a skipped run, and
      // "0 added, 0 created" beside a bare caveat reads as "there was nothing to do".
      const skippedVercel = result.vercelUnverified
        ? ` Vercel was skipped — its project list couldn't be verified, so ${plural(result.vercelSkipped ?? 0, "Vercel project")} went unexamined this run.`
        : "";
      return summarizeAutoConfigure(result) + skippedVercel + noteDetail(result.notes) + skipDetail(result.skippedDetail);
    },
    [queryClient],
  );

  const run = useCallback(async (): Promise<void> => {
    if (running.current || review) return;
    running.current = true;
    setBusy(true);
    try {
      // A user clicked Auto Configure — ask the providers NOW (bypass the 30s enumeration
      // cache). The badges' 60s loop stays cache-served (fetchUnconfigured() without fresh).
      const { pending } = await fetchUnconfigured({ fresh: true });
      if (pending.length === 0) {
        // Nothing new to review — still ask the server to wire any straggler endpoints
        // (no ignores, no creation).
        setMessage(await configure([], new Set<string>(), ""));
        return;
      }
      const groups = (await listGroups()).map((g) => ({ id: g.id, name: g.name }));
      // Hand off to the modal; the work runs when the operator applies.
      setReview({ pending, groups });
    } catch (err) {
      setMessage(`Auto-configure failed: ${msg(err)}`);
    } finally {
      running.current = false;
      setBusy(false);
    }
  }, [review, configure]);

  const applyReview = useCallback(
    async (ignoreKeys: Set<string>, newSiteGroupId: string, forceGroup: boolean): Promise<void> => {
      if (!review || running.current) return;
      running.current = true;
      setBusy(true);
      try {
        const summary = await configure(review.pending, ignoreKeys, newSiteGroupId, forceGroup);
        setReview(null);
        setMessage(summary);
      } catch (err) {
        setReview(null);
        setMessage(`Auto-configure failed: ${msg(err)}`);
      } finally {
        running.current = false;
        setBusy(false);
      }
    },
    [review, configure],
  );

  const value = useMemo<AutoConfigureContext>(() => ({ run, busy, progress: null }), [run, busy]);

  return (
    <Ctx.Provider value={value}>
      {children}
      {review && (
        <AutoConfigureReview
          projects={uniqueByProject(review.pending).map((p): ReviewProject => ({ platform: p.platform, projectName: p.projectName, domain: p.domain }))}
          groups={review.groups}
          busy={busy}
          progress={null}
          onApply={(ignoreKeys, groupId, forceGroup) => void applyReview(ignoreKeys, groupId, forceGroup)}
          onCancel={() => {
            if (!busy) setReview(null);
          }}
        />
      )}
      <StatusAlert message={message} onClose={() => setMessage(null)} />
    </Ctx.Provider>
  );
}

/** Access the shared Auto Configure action. Must be rendered under an AutoConfigureProvider. */
export function useAutoConfigure(): AutoConfigureContext {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error("useAutoConfigure must be used within an AutoConfigureProvider");
  return ctx;
}
