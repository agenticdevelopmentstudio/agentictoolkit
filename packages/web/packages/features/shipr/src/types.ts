/**
 * The wire.
 *
 * Every shape here is what `backend/src/adh/src/routes/shipr.ts` actually returns, and
 * every tuple is the one the backend validates against — `ENVIRONMENTS` and `OPERATIONS`
 * are `src/shipr/ladder.ts` and `src/shipr/ops/index.ts` respectively. They are declared
 * as runtime tuples rather than bare unions because the toolbar builds its buttons and
 * the deploy dialog builds its checkboxes by MAPPING over them: a second hand-typed list
 * in a `<button>` block is how a UI ends up offering four environments to a backend that
 * accepts three, with no type error anywhere.
 *
 * These are deliberately hand-written rather than pulled from `@agentic-toolkit/adh-api-types`.
 * That package is generated from the OpenAPI document, and the generated names for a
 * hand-written route module are long paths into `components.schemas` that read as noise at
 * every call site. The document is still the contract — `src/openapi/paths/shipr.ts`
 * describes the same shapes — and the drift between the two is caught by the round trip
 * this package's own tests make against a real response fixture.
 */

/** `src/shipr/ladder.ts` — `ENVIRONMENTS`. The rungs above `ship`, outermost first. */
export const ENVIRONMENTS = ['testing', 'staging', 'production'] as const;
export type Environment = (typeof ENVIRONMENTS)[number];

/**
 * `src/shipr/ops/index.ts` — `OPERATIONS`. The five things the toolbar can press, and the
 * same five the terminal script does.
 *
 * `register` is the odd one: the other four name a repository that already exists, and
 * register is how one comes to. It therefore posts to `/shipr/register` with a slug
 * rather than to `/shipr/repos/:id/register`, and there is no such route.
 */
export const OPERATIONS = [
  'status',
  'prepare',
  'deploy',
  'register',
  'unregister',
] as const;
export type Operation = (typeof OPERATIONS)[number];

/** `src/shipr/targets.ts` — `ScopeKind`. What a run was aimed at. */
export const SCOPE_KINDS = ['deploy_repo', 'dev_repo', 'group', 'all'] as const;
export type ScopeKind = (typeof SCOPE_KINDS)[number];

/** `shipr.runs.state`'s CHECK constraint. */
export const RUN_STATES = [
  'queued',
  'running',
  'succeeded',
  'failed',
  'cancelled',
] as const;
export type RunState = (typeof RUN_STATES)[number];

/** The three a run never leaves. Reaching one is what closes the log's stream. */
export const TERMINAL_STATES: readonly RunState[] = [
  'succeeded',
  'failed',
  'cancelled',
];

/** `src/lib/team-access.ts` — `AccessVerb`. `M` is manage (grant it to others). */
export type AccessVerb = 'C' | 'R' | 'U' | 'D' | 'M';

/** Which workspace the tree was read in — a personal one or an organization's. */
export interface Workspace {
  kind: 'customer' | 'organization';
  ownerId: string;
}

/** A folder. Flat rows with a `parentId`, never a nested tree: the rail renders one level
 *  at a time, and a nested shape would have to be flattened again to draw it. */
export interface Group {
  id: string;
  parentId: string | null;
  name: string;
  path: string;
  depth: number;
  position: number;
}

/** The development repository — the one people push to. One of these has one or more
 *  mirrors, which is what a monorepo of separately-deployed directories looks like here. */
export interface DevRepo {
  id: string;
  slug: string;
  /**
   * What the operator calls it, which is not always what the forge calls it.
   *
   * NULL MEANS NO OPINION, and every reader falls back to `slug` — a stored copy of the
   * slug would be indistinguishable from a deliberate choice, and would go stale the
   * moment the repository was renamed. A LABEL AND NOTHING MORE: no branch, no path and
   * no forge call is derived from it.
   */
  displayName: string | null;
  mainBranch: string;
  preparedBranch: string;
  declarationSha: string | null;
  connectionId: string | null;
}

/**
 * THE SHARD A REPOSITORY WITH NO `[deployments]` SECTION GETS.
 *
 * `WHOLE_REPO_SHARD` on the backend (`shipr/ops/bootstrap.ts`), and therefore the value of
 * `shard` on the overwhelming majority of rows there have ever been.
 *
 * IT IS A STRING AND NOT AN ABSENCE, which is the trap: the column is `notNull`, so
 * `!mirror.shard` is false for every mirror in the system and `mirror.shard ?` is true for
 * every one. Two surfaces read it as optional and were wrong in opposite directions — the
 * settings pane drew a chip reading `all` beside every ordinary repository, and the org
 * walk hid its slug recompute behind a condition that could never hold, so re-aiming an
 * organization silently moved nothing. Ask `=== WHOLE_REPO_SHARD`, never truthiness.
 */
export const WHOLE_REPO_SHARD = 'all';

/** A deployment mirror — the repository the pipeline actually pushes branches on. This is
 *  the row a toolbar button acts on, and the row `shard` distinguishes when one dev repo
 *  has several. */
export interface Repo {
  id: string;
  devRepoId: string;
  groupId: string | null;
  slug: string;
  shard: string;
  shipBranch: string;
  ciContext: string;
  /** Environment → the branch it deploys from. An environment ABSENT here is one this
   *  repository does not deploy to, and its ladder column is dropped rather than drawn
   *  empty — an empty column reads as "behind", which is a different fact. */
  envBranches: Partial<Record<Environment, string>>;
  registeredAt: string | null;
  position: number;
}

/** One commit, as git reported it. `when` is RELATIVE (`%ar`) because the question about
 *  an old rung is "how stale", and "3 weeks ago" answers it without arithmetic. */
export interface LadderRow {
  sha: string;
  when: string;
  subject: string;
  /** Which columns are standing on this commit. Order is not significant. */
  marks: string[];
  /** True only on the last row, and only when every branch that exists is on it. */
  settled: boolean;
}

/** The details pane's whole picture: which columns to draw, and the commits to draw them
 *  against, OLDEST FIRST so the list reads the way the pipeline flows. */
export interface Ladder {
  columns: string[];
  rows: LadderRow[];
  settled: boolean;
  /** WHEN `status` LAST SAW THIS. Sent by the route from `repo_states.read_at`, and the
   *  reason the pane can tell a ladder that answers the run in flight from one written
   *  before it — see `RepoView`'s `pending`. Optional because a caller that built a ladder
   *  itself (a test, the terminal port) has no read to date. */
  readAt?: string;
}

/** What the last `status` run saw, and when. A stale ladder is honest about it rather than
 *  hidden: `readAt` is rendered, and the refresh is the `status` button. */
export interface RepoState {
  deployRepoId: string;
  tips: Record<string, string | null>;
  settled: boolean;
  notes: string[];
  readAt: string;
}

/** A row in the tree — a mirror, plus the things the rail and the settings dialog draw
 *  beside it. */
export interface RepoItem extends Repo {
  devRepo: DevRepo | null;
  state: RepoState | null;
}

export interface Run {
  id: string;
  operation: Operation;
  scopeKind: ScopeKind;
  scopeId: string | null;
  environments: Environment[];
  state: RunState;
  summary: unknown;
  startedAt: string | null;
  finishedAt: string | null;
  createdAt: string;
  updatedAt: string;
}

/** One repository's turn inside a run, or one environment's turn inside that. A run over a
 *  group has one step per repository, in sorted order — which is what makes the log
 *  readable as "it is on the fourth of eleven" rather than as one wall of output. */
export interface RunStep {
  id: string;
  runId: string;
  deployRepoId: string | null;
  ordinal: number;
  environment: Environment | null;
  stage: 'advance' | 'arrival' | 'verify' | null;
  state: string;
  detail: unknown;
  startedAt: string | null;
  finishedAt: string | null;
}

/** One line of output. `seq` is the cursor: monotonic per run, and what a reconnecting
 *  stream resumes from, so a dropped connection replays nothing and skips nothing. */
export interface RunEvent {
  id: string;
  runId: string;
  stepId: string | null;
  seq: number;
  stream: 'out' | 'err' | 'meta';
  text: string;
  at: string;
}

/** `GET /shipr/repos` — everything the tree needs in one read. */
export interface TreeResponse {
  workspace: Workspace;
  /**
   * What this caller may do in this workspace.
   *
   * A hint for what to DRAW and nothing else — every route re-derives its own verb
   * server-side, so hiding a button here is a courtesy, not a control. Treat a missing
   * verb as "do not offer", never as "it is safe to offer the rest".
   */
  verbs: AccessVerb[];
  groups: Group[];
  items: RepoItem[];
}

/** `GET /shipr/repos/:id` — the details pane. */
export interface RepoDetail {
  repo: Repo;
  devRepo: DevRepo | null;
  group: Group | null;
  /** NULL when no `status` has ever run against this mirror — which is every mirror the
   *  moment it is registered or seeded. That is a DIFFERENT fact from a ladder with no
   *  rows ("we looked, and there is no history"), so the route answers null rather than
   *  inventing an empty one, and the pane says which of the two it is. */
  ladder: Ladder | null;
  runs: Run[];
}

/** `GET /shipr/runs/:id/events` — a page of log, plus where the next one starts. */
export interface EventPage {
  events: RunEvent[];
  nextSeq: number;
  state: RunState;
  /** True when the run is terminal AND this page did not fill: there is no more to come. */
  done: boolean;
}

/** What `POST /shipr/runs` and the four `/shipr/repos/:id/<operation>` routes answer with.
 *  202, because the run has been QUEUED — the output arrives on the stream. */
export interface RunAccepted {
  runId: string;
}

/** `POST /shipr/register` — the queued run, plus the dev repo row it found or invented. */
export interface RegisterAccepted extends RunAccepted {
  devRepo: DevRepo;
}

/** The body of a `POST /shipr/runs`. `scopeId` is null only for `scopeKind: 'all'`. */
export interface RunRequest {
  operation: Operation;
  scopeKind: ScopeKind;
  scopeId?: string | null;
  /** Required — and non-empty — for `deploy`; ignored by everything else, which is why
   *  the toolbar's other four buttons never ask. */
  environments?: Environment[];
  options?: RunOptions;
}

export interface RunOptions {
  /** Deploy this exact commit rather than the tip. */
  sha?: string;
  shard?: string;
  groupId?: string;
}

/**
 * One credential the caller can reach the forge with — `GET /shipr/connections`.
 *
 * A label and an id, and nothing else, because that is all a chooser needs and everything
 * else on an integration connection is either a secret or a detail of a provider this
 * console does not model. The backend narrows the list to the credentials `register` will
 * actually accept, so an entry here is an answer, not a candidate.
 */
export interface ForgeConnection {
  id: string;
  label: string;
  /**
   * The forge account this installation sits on, or null when the connect flow recorded none.
   *
   * THIS IS THE WIZARD'S ORG CHOOSER, and it needs no call to the forge to build: one
   * installation is one account, so the connections a caller holds ARE the accounts a
   * deployment repository can be created in. An org with no connection is an org the run
   * would fail in, so offering it would be a menu whose entries the next request refuses.
   */
  accountLogin: string | null;
}

/** One repository an installation was granted — `GET /shipr/connections/:id/repositories`. */
export interface ForgeRepository {
  /** `owner/name`. */
  slug: string;
  defaultBranch: string;
  private: boolean;
}

/** One shard of a `.shipr`'s `[deployments]`, as the wizard shows it read-only. */
export interface DeclaredShard {
  /** The key in `[deployments]`. */
  shard: string;
  /** `owner/name` of that shard's mirror. */
  slug: string;
}

/**
 * What a repository's committed `.shipr` says it deploys to —
 * `GET /shipr/connections/:id/declaration`.
 *
 * `deployments: null` IS THE FALLBACK BRANCH, and the wizard reads nothing else to decide:
 * no file, an unparseable one, or one declaring no shards all arrive as null, and all three
 * mean the same thing here — the deployment target is the wizard's to offer. A non-null list
 * means the file already named every mirror, so the wizard shows it and offers nothing.
 */
export interface DeclarationResponse {
  deployments: DeclaredShard[] | null;
  /** The `<name>-deployment` convention applied to the dev repo, computed by the server so
   *  this console and a workstation cannot land on two different deployment repositories. */
  fallbackSlug: string;
  /** Why a declaration that was present could not be used. */
  note?: string;
}

/**
 * What one forge org's repositories are BORN with — `GET /shipr/org-defaults`.
 *
 * Never a description of a mirror that already exists: a default is read when a mirror is
 * first written, so changing one re-aims the NEXT repository and moves nothing already
 * registered. The dialog's Apply is what walks the existing ones, one `PATCH` each.
 */
export interface OrgDefaults {
  id: string;
  /** The forge account login these defaults are for. */
  org: string;
  /** Which org the deployment repositories go in. NULL is "the same org", stored as null
   *  rather than as a copy so an operator who never chose stays distinguishable from one
   *  who chose the org they were already in. */
  deploymentOwner: string | null;
  /** `-deployment`, spelled per-org. Appended to the source repository's name. */
  nameSuffix: string;
  /** The ladder a new mirror starts with. EMPTY means the built-in default (every
   *  environment, named after itself), not a repository that deploys nowhere. */
  envBranches: Partial<Record<Environment, string>>;
  createdAt: string;
  updatedAt: string;
}

/** The body of a `PUT /shipr/org-defaults/:org`. An ABSENT key is left alone rather than
 *  reset, so a request about environments cannot quietly restore the suffix. */
export interface OrgDefaultsPatch {
  deploymentOwner?: string | null;
  nameSuffix?: string;
  envBranches?: Partial<Record<Environment, string>>;
}

/** The body of a `POST /shipr/register`. */
export interface RegisterRequest {
  /** `owner/name` on the forge. */
  slug: string;
  /** Which of the caller's own integration connections to reach the forge with. */
  connectionId?: string;
  groupId?: string;
  mainBranch?: string;
  preparedBranch?: string;
  /** Where the ONE mirror goes when `.shipr` declares no shards. Read only on that
   *  fallback — a declared shard's slug is never overridden, because the file and the form
   *  must not be able to say two different things. */
  deploymentOwner?: string;
  /** That mirror's name, on the same fallback. Overridable independently of the owner,
   *  because changing the org almost always keeps `<name>-deployment`. */
  deploymentName?: string;
  /**
   * Whether to GO AND MAKE IT, or only write down where it goes.
   *
   * `false` writes the rows synchronously, leaves `registeredAt` null and queues no run —
   * so nothing is created on the forge under a name nobody has looked at yet. The operator
   * then sets the org, the name and the environments and presses Provision, which is a
   * plain `register` run against the same `dev_repo`. Defaults to true.
   */
  provision?: boolean;
}

/** `POST /shipr/register` with `provision: false` — 201, and nothing queued. The rows are
 *  written and `registeredAt` is null on every mirror in `mirrors`. */
export interface RegisterConfigured {
  devRepo: DevRepo;
  mirrors: Repo[];
  /** What the run would have journalled — a repository carrying no `.shipr`, a malformed
   *  one, a slug another repository already spoke for. Absent when there is nothing to say. */
  notes?: string[];
}

/**
 * The body of a `PATCH /shipr/repos/:id`. Every key is optional and ABSENT means unchanged.
 *
 * TWO TABLES, ONE ROUTE: `displayName` is the DEV repo's label, addressed through a mirror
 * because a mirror is the only thing this console has an id for. `shard` is absent because
 * it is immutable; `slug` is here but is accepted ONLY while `registeredAt` is null — a
 * repository that is still a plan may be pointed anywhere, and one that has been
 * provisioned answers 409, because re-pointing it would strand its mirror, its ladder and
 * its history on a repository nothing now names.
 */
export interface RepoPatch {
  groupId?: string | null;
  position?: number;
  /** `owner/name` of the DEPLOYMENT repository. 409 once it is provisioned. */
  slug?: string;
  /** The SOURCE repository's label. Null clears it. */
  displayName?: string | null;
  shipBranch?: string;
  ciContext?: string;
  envBranches?: Partial<Record<Environment, string>>;
}
