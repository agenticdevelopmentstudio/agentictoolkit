import { crunchyPhases } from "./deploy-status";
import { toValidDate, type ProviderDeploy } from "./provider-deploy";
import { noteRateLimited, rateLimitedUntil } from "@agentic-toolkit/deploy-platform/cooldown";

interface CrunchyCluster {
  id: string;
  name: string;
  state: string;
  is_suspended?: boolean;
  environment?: string | null;
  created_at?: string | null;
}

interface ClustersBody {
  clusters?: CrunchyCluster[];
}

/**
 * List every cluster in the team (testing/staging/prod + any future cluster or replica)
 * and map each to a deploy row whose phase IS its health (see crunchyPhases). Poll-only,
 * mirroring fetch-cloudflare: missing token → dormant; any failure → ok:false so the
 * platform-health path opens a "can't reach Crunchy" blind-spot issue. The raw cbkey_ key
 * is a direct Bearer token (no exchange).
 */
export async function fetchCrunchyClusters(env: {
  CRUNCHY_API_TOKEN?: string;
}): Promise<{ ok: boolean; deploys: ProviderDeploy[] }> {
  if (!env.CRUNCHY_API_TOKEN) return { ok: true, deploys: [] };
  if (rateLimitedUntil("crunchy")) return { ok: false, deploys: [] }; // cooling down after a 429
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 6_000);
  try {
    const res = await fetch("https://api.crunchybridge.com/clusters", {
      headers: { Authorization: `Bearer ${env.CRUNCHY_API_TOKEN}` },
      signal: controller.signal,
    });
    if (!res.ok) {
      if (res.status === 429) noteRateLimited("crunchy", res.headers.get("retry-after"));
      console.error(`Crunchy /clusters ${res.status}`);
      return { ok: false, deploys: [] };
    }
    const body = (await res.json()) as ClustersBody;
    const deploys: ProviderDeploy[] = (body.clusters ?? []).map((c) => ({
      id: `cr_${c.id}`,
      platform: "crunchy",
      projectName: c.name,
      ...crunchyPhases(c.state, Boolean(c.is_suspended)),
      environment: c.environment ?? "production",
      commitHash: null,
      commitMessage: null,
      branch: null,
      commitRepo: null,
      url: null,
      createdAt: toValidDate(c.created_at) ?? new Date(), // fall back to poll time, never Invalid Date
    }));
    return { ok: true, deploys };
  } catch (err) {
    console.error("Crunchy /clusters fetch", err);
    return { ok: false, deploys: [] };
  } finally {
    clearTimeout(timer);
  }
}
