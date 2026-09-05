import { shortSha, commitFullMessage } from "./format";
import { mapLimit } from "@agentic-toolkit/deploy-platform/util";
import { toValidDate, type ProviderDeploy } from "./provider-deploy";
import { noteRateLimited, rateLimitedUntil } from "@agentic-toolkit/deploy-platform/cooldown";
import { listWorkerScripts } from "@agentic-toolkit/deploy-platform/providers";

interface WorkerDeploymentMetadata {
  branch?: string | null;
  commit_hash?: string | null;
  commit_message?: string | null;
  [key: string]: unknown;
}

interface WorkerDeployment {
  id: string;
  created_on: string;
  metadata?: WorkerDeploymentMetadata | null;
}

interface WorkersDeploymentsBody {
  success?: boolean;
  result?: {
    deployments?: WorkerDeployment[];
  } | null;
}

export async function fetchCloudflareDeployments(env: {
  CLOUDFLARE_API_TOKEN?: string;
  CLOUDFLARE_ACCOUNT_ID?: string;
  workerScripts?: readonly string[];
  /** Overall poll budget (ms): stop starting new script fetches past this and return a
   *  partial. Defaults to 18s (under sync's 20s `guard`); overridable for tests/tuning. */
  overallBudgetMs?: number;
}): Promise<{ ok: boolean; deploys: ProviderDeploy[] }> {
  if (!env.CLOUDFLARE_API_TOKEN || !env.CLOUDFLARE_ACCOUNT_ID) return { ok: true, deploys: [] };
  if (rateLimitedUntil("cloudflare")) return { ok: false, deploys: [] }; // cooling down after a 429
  const { CLOUDFLARE_API_TOKEN: token, CLOUDFLARE_ACCOUNT_ID: accountId } = env;
  // The overall budget starts BEFORE the script listing — the listing is part of the
  // poll, so its time counts against the deadline (same off-by-a-listing fix as the
  // Railway fetcher: started after it, the worst case ran past sync's 20s `guard`).
  const overallBudgetMs = env.overallBudgetMs ?? 18_000;
  const deadline = Date.now() + overallBudgetMs;
  // Prefer the live account listing (all workers); fall back to the configured set.
  const listController = new AbortController();
  const listTimer = setTimeout(() => listController.abort(), Math.min(6_000, overallBudgetMs));
  const listed = await listWorkerScripts(accountId, token, listController.signal);
  clearTimeout(listTimer);
  const scripts = "scripts" in listed ? listed.scripts : (env.workerScripts ?? []).slice();
  if (scripts.length === 0) {
    // A failed listing with no configured fallback is a BLIND SPOT (we hold a token yet
    // can see nothing), not a healthy empty account — surface ok:false so the
    // platform-health issue fires, matching the Railway fetcher's contract. A genuine
    // `{ scripts: [] }` (authorized, zero workers) stays ok.
    return { ok: !("error" in listed), deploys: [] };
  }
  const deploys: ProviderDeploy[] = [];
  let anyError = false;

  // Once the budget is spent, stop fetching more scripts and RETURN the partial (marked
  // not-fully-ok via `skipped`, so the caller upserts what landed but treats Cloudflare
  // as degraded rather than all-clear). Bounded fan-out, not serial: a serial loop was
  // N scripts × up to 6s, so a many-worker account chronically blew the budget and
  // returned partials every cycle — the same shape Railway fixed with mapLimit.
  let skipped = false;
  const CF_SCRIPT_CONCURRENCY = 5;

  await mapLimit(scripts.slice(), CF_SCRIPT_CONCURRENCY, async (script) => {
    const remaining = deadline - Date.now();
    // `skipped` also stops the remaining queue after a 429 — cooling down means
    // not hammering the rest of the account this cycle either.
    if (remaining <= 0 || skipped) {
      skipped = true;
      return;
    }
    const controller = new AbortController();
    // Never let a per-script fetch run past the overall budget, so the whole poll stays
    // under `guard`'s cap and returns partial instead of being abandoned.
    const timer = setTimeout(() => controller.abort(), Math.min(6_000, remaining));
    try {
      const res = await fetch(
        `https://api.cloudflare.com/client/v4/accounts/${accountId}/workers/scripts/${script}/deployments`,
        {
          headers: { Authorization: `Bearer ${token}` },
          signal: controller.signal,
        },
      );
      if (!res.ok) {
        console.error(`Cloudflare Workers ${script} ${res.status}`);
        anyError = true;
        if (res.status === 429) {
          noteRateLimited("cloudflare", res.headers.get("retry-after"));
          skipped = true;
        }
        return;
      }

      const body = (await res.json()) as WorkersDeploymentsBody;
      const deplList = body.result?.deployments ?? [];
      const slice = deplList.slice(0, 5);

      const rows: ProviderDeploy[] = slice.flatMap((dep) => {
        const meta = dep.metadata ?? null;
        // Boundary validation — same contract as the Vercel/Railway fetchers.
        const createdAt = toValidDate(dep.created_on);
        if (!createdAt) {
          console.error(`Cloudflare deployment ${dep.id} has unparseable created_on ${JSON.stringify(dep.created_on)} — skipping`);
          return [];
        }
        return {
          id: `cf_${dep.id}`,
          platform: "cloudflare-pages", // kept as "cloudflare-pages" — type/glyph/summary maps key on this value
          projectName: script,
          buildPhase: null,
          deployPhase: "deployed" as const, // Workers deployments are live; no failed-build concept
          environment: "production",
          commitHash: typeof meta?.commit_hash === "string" ? shortSha(meta.commit_hash) : null,
          commitMessage: typeof meta?.commit_message === "string" ? commitFullMessage(meta.commit_message) : null,
          branch: typeof meta?.branch === "string" ? meta.branch : null,
          commitRepo: null, // Workers deployment metadata doesn't carry the repo
          url: null,
          createdAt,
        };
      });

      deploys.push(...rows);
    } catch (err) {
      console.error(`Cloudflare Workers fetch ${script}`, err);
      anyError = true;
    } finally {
      clearTimeout(timer);
    }
  });
  // A partial poll (scripts skipped for budget) is not fully ok — but the deploys we DID
  // fetch are still upserted by the caller, so a deploy that was reached lands even when
  // the account has too many Workers to poll within one budget.
  return { ok: !anyError && !skipped, deploys };
}
