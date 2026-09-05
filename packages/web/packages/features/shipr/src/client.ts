import type {
  DeclarationResponse,
  EventPage,
  ForgeConnection,
  ForgeRepository,
  Group,
  RegisterAccepted,
  RegisterRequest,
  Repo,
  RepoPatch,
  RepoDetail,
  Run,
  RunAccepted,
  RunRequest,
  RunStep,
  TreeResponse,
} from './types';

/**
 * A `fetch`-shaped call that already carries auth. Supplied by the host site.
 *
 * A fetcher may signal failure either way, and both are handled: return a non-ok
 * `Response` (a bare `fetch`, and what the tests use) or throw (`authedFetch` from
 * `@agentic-toolkit/auth/client`, which is what the site supplies — it throws
 * `AuthHttpError` after its one refresh-and-retry on a 401).
 */
export type Fetcher = (path: string, init?: RequestInit) => Promise<Response>;

/**
 * The backend's standard error envelope is `{ error: { message } }` (`app.ts:403`).
 *
 * Unwrapping it matters more here than on a form: shipr's refusals are the interesting
 * half of the product. "that repository is already registered in this workspace", "folder
 * not found", and above all the unverified-tip refusal are sentences an operator acts on,
 * and handing them the raw JSON instead would bury each one inside a brace.
 */
async function errorMessage(res: Response): Promise<string> {
  const text = await res.text().catch(() => '');
  try {
    const parsed = JSON.parse(text) as { error?: { message?: string } };
    if (typeof parsed?.error?.message === 'string') return parsed.error.message;
  } catch {
    // Not JSON (a proxy's plain-text 502) — the raw text is the best message there is.
  }
  return text || `${res.status} ${res.statusText}`;
}

async function json<T>(res: Response): Promise<T> {
  if (!res.ok) throw new Error(await errorMessage(res));
  return (await res.json()) as T;
}

/** `json`'s void sibling, for the one endpoint that answers 204. Without it a delete that
 *  returned `fetcher`'s promise directly would RESOLVE on a 403 under a bare-`fetch`
 *  fetcher, and a folder that refused to be deleted would vanish from the tree anyway. */
async function ok(res: Response): Promise<void> {
  if (!res.ok) throw new Error(await errorMessage(res));
}

/**
 * The backend mounts the shipr router at `/shipr` (`app.ts`). The `/api` prefix in front
 * of it is the **frontend's** — every fleet site rewrites `/api/:path*` to
 * `${BACKEND_URL}/:path*` in its `next.config.ts`. No backend mount carries `/api`.
 */
export const BASE = '/api/shipr';

/** `shipr.groups` is the one shipr table on GENERIC CRUD (`src/crud/policy.ts`), which is
 *  why folders are created and renamed through a different shape than everything else here
 *  — a bare row in, a bare row out, `PUT` for the update and `204` for the delete. */
const GROUPS = `${BASE}/groups`;

const seg = encodeURIComponent;

/** `?workspace=<slug>`, or nothing at all. Absent means the caller's OWN workspace, which
 *  is a different thing from an empty one: sending `workspace=` would be a slug the
 *  resolver has to reject. */
function query(params: Record<string, string | number | undefined>): string {
  const parts = Object.entries(params)
    .filter(([, v]) => v !== undefined && v !== '')
    .map(([k, v]) => `${k}=${seg(String(v))}`);
  return parts.length ? `?${parts.join('&')}` : '';
}

/**
 * Everything the console can ask the backend for.
 *
 * `workspace` is fixed at construction rather than passed per call: it is the slug in the
 * URL bar, one per screen, and threading it through thirteen signatures would make
 * "forgot the workspace on one call" a defect the type system cannot see — a tree read in
 * the org workspace beside a register that lands in the caller's personal one.
 *
 * Nothing here polls or retries. A run's output arrives on the stream (`./live`), and a
 * failed request throws with the backend's own sentence in it.
 */
export function createShiprClient(fetcher: Fetcher, workspace?: string) {
  const ws = query({ workspace });

  const send = async <T>(path: string, method: string, body?: unknown) =>
    json<T>(
      await fetcher(path, {
        method,
        ...(body === undefined
          ? {}
          : {
              headers: { 'content-type': 'application/json' },
              body: JSON.stringify(body),
            }),
      }),
    );

  return {
    /** The slug this client acts in, so a caller can build a stream URL that agrees with
     *  the reads it is watching. */
    workspace,

    // --- the tree ----------------------------------------------------------

    /** Every folder and every repository the caller reaches, in ONE request — the HTDV
     *  renders levels, not nodes, so a per-folder fetch would be a round trip per click. */
    tree: () => send<TreeResponse>(`${BASE}/repos${ws}`, 'GET'),

    /** The details pane: the repository, its ladder, and its recent runs. */
    repo: (id: string) => send<RepoDetail>(`${BASE}/repos/${seg(id)}`, 'GET'),

    /** Move it, reorder it, or change which branches it ships to. Absent keys are absent —
     *  a drag-and-drop sends `{ groupId, position }` and touches nothing else. */
    updateRepo: (id: string, body: RepoPatch) =>
      send<Repo>(`${BASE}/repos/${seg(id)}`, 'PATCH', body),


    // --- folders -----------------------------------------------------------

    /** A new folder. `parentId` absent (or null) makes a root.
     *
     *  `path` and `depth` are NOT sent and must not be: both are maintained by
     *  `shipr.group_path()`, the trigger migration 0205 installs, which is also what
     *  refuses a cycle and rewrites a subtree when a folder moves. */
    createGroup: (body: { name: string; parentId?: string | null; position?: number }) =>
      send<Group>(`${GROUPS}${ws}`, 'POST', body),

    /** Rename it, move it under a different parent, or reorder it among its siblings.
     *
     *  PUT, not PATCH — generic CRUD's update verb. It still merges: the columns absent
     *  from `body` keep their stored values. */
    updateGroup: (
      id: string,
      body: { name?: string; parentId?: string | null; position?: number },
    ) => send<Group>(`${GROUPS}/${seg(id)}${ws}`, 'PUT', body),

    /** Delete it. 204, no body — hence `ok` rather than `json`. */
    deleteGroup: async (id: string) =>
      ok(await fetcher(`${GROUPS}/${seg(id)}${ws}`, { method: 'DELETE' })),

    // --- the toolbar -------------------------------------------------------

    /**
     * The credentials the caller can register a repository with.
     *
     * NO WORKSPACE on this one, and that is not an omission: `integration_connections` is
     * keyed on the person, not on a workspace, so the answer is the same in every one of
     * them. The backend narrows it to what `register` accepts — a GitHub App installation
     * of the caller's, active — so the register form can offer the list verbatim.
     */
    connections: () =>
      send<{ connections: ForgeConnection[] }>(`${BASE}/connections`, 'GET'),

    /**
     * The repositories one connection was granted — the wizard's first question.
     *
     * No workspace, for `connections`' reason: the answer is a property of the installation.
     *
     * READS WHAT WAS WRITTEN DOWN. The backend answers this from the row the last successful
     * read stored, and reaches GitHub only when there is no row yet — so the picker opens on
     * a list instead of on a spinner, and a slow or unreachable forge shows a stale list
     * rather than an empty one. `readAt` is what stops that being a lie: the wizard says how
     * old the list is, and {@link refreshConnectionRepositories} is how it stops being old.
     */
    connectionRepositories: (id: string) =>
      send<{ repositories: ForgeRepository[]; readAt: string }>(
        `${BASE}/connections/${seg(id)}/repositories`,
        'GET',
      ),

    /**
     * Ask GitHub again, and store what it says.
     *
     * A POST because it writes. Separate from the read for the reason the backend keeps them
     * separate: the read cannot fail in a way worth reporting and this one can — a revoked
     * installation, a suspended app, a forge that is down — and a caller needs to be able to
     * tell "here is the list" from "here is the list, and it is the one from before".
     */
    refreshConnectionRepositories: (id: string) =>
      send<{ repositories: ForgeRepository[]; readAt: string }>(
        `${BASE}/connections/${seg(id)}/repositories/refresh`,
        'POST',
      ),

    /**
     * What a repository's `.shipr` declares — the wizard's second question, and usually the
     * answer that there is no second question to ask.
     *
     * The console READS the file and never writes it. Declaring shards stays an edit an
     * operator makes in a repository and reviews in a diff; a form that could override a
     * declared slug is exactly the drift the CLI refuses when `--org` is passed alongside
     * `--deployment`.
     */
    connectionDeclaration: (id: string, slug: string, branch?: string) =>
      send<DeclarationResponse>(
        `${BASE}/connections/${seg(id)}/declaration${query({ slug, branch })}`,
        'GET',
      ),

    /**
     * Register a repository — the one operation that creates rows rather than moving
     * commits. 202: the provisioning itself is a queued run, and `devRepo` is the row it
     * will provision mirrors for.
     */
    register: (body: RegisterRequest) =>
      send<RegisterAccepted>(`${BASE}/register${ws}`, 'POST', body),

    /**
     * The toolbar, as one call: an operation and a scope.
     *
     * `deploy_repo` is one mirror, `dev_repo` a repository and all its shards, `group` a
     * folder and everything nested under it, `all` the workspace. A run over a folder walks
     * its repositories ONE AT A TIME in the tree's own order.
     */
    run: (body: RunRequest) => send<RunAccepted>(`${BASE}/runs${ws}`, 'POST', body),

    /** The four per-repository buttons. Sugar over `run` — same gate, same queue — for the
     *  common case where the scope is the row the operator has selected. */
    runOnRepo: (
      id: string,
      operation: 'status' | 'prepare' | 'deploy' | 'unregister',
      body: Omit<RunRequest, 'operation' | 'scopeKind' | 'scopeId'> = {},
    ) => send<RunAccepted>(`${BASE}/repos/${seg(id)}/${operation}`, 'POST', body),

    // --- runs --------------------------------------------------------------

    /** The runs the caller may watch, newest first. */
    runs: (limit?: number) =>
      send<{ items: Run[] }>(`${BASE}/runs${query({ workspace, limit })}`, 'GET'),

    /**
     * Stop a run.
     *
     * A STOP, NOT AN UNDO — a folder deploy halted at the fourth of eleven has carried four
     * of them, and the log says which. The backend retires the run's lease rather than
     * messaging the worker, so the stop lands within a heartbeat wherever the run is being
     * held. Idempotent: a run that has already settled comes back unchanged.
     */
    cancelRun: (id: string) =>
      send<{ run: Run }>(`${BASE}/runs/${seg(id)}/cancel`, 'POST'),

    /** One run and its steps, oldest step first — which is the order it walked them. */
    runDetail: (id: string) =>
      send<{ run: Run; steps: RunStep[] }>(`${BASE}/runs/${seg(id)}`, 'GET'),

    /**
     * A page of the run's log.
     *
     * The SAME cursor the stream uses, so the pane can start here and switch to the stream
     * — or fall back to this when EventSource is unavailable — without a second notion of
     * position. Send back the `nextSeq` it answered with.
     */
    events: (id: string, after = 0, limit?: number, repo?: string) =>
      send<EventPage>(
        `${BASE}/runs/${seg(id)}/events${query({ after, limit, repo })}`,
        'GET',
      ),
  };
}

export type ShiprClient = ReturnType<typeof createShiprClient>;
