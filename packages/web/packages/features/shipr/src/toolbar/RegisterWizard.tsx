'use client';

import * as React from 'react';

import { Button } from '@agenticdevelopertoolkit/ui/components/button';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@agenticdevelopertoolkit/ui/components/dialog';
import { ErrorText } from '@agenticdevelopertoolkit/ui/components/error-text';
import { Input } from '@agenticdevelopertoolkit/ui/components/input';
import { Label } from '@agenticdevelopertoolkit/ui/components/label';
import { Select } from '@agenticdevelopertoolkit/ui/components/select';

import { flattenGroups } from '../tree/levels';
import type {
  DeclarationResponse,
  ForgeConnection,
  ForgeRepository,
  Group,
  RegisterRequest,
} from '../types';
import type { ShiprClient } from '../client';
import { useSubmit } from './dialogs';

/**
 * Register, as three questions instead of a text field.
 *
 * THE FORM IT REPLACED ASKED FOR `owner/name` AS FREE TEXT, validated by a regex that can only
 * tell a slug from a not-slug. Every other way of getting it wrong was silent until a run: a
 * typo that happens to name a real repository the installation was never granted resolves,
 * registers, and fails minutes later at the first push, in a log, under a repository name that
 * is not the one anybody meant. So the operator no longer types the repository — they pick it
 * out of what an installation actually granted, which is the only list whose every entry is
 * reachable.
 *
 * THERE IS NO ORG-AND-REPO BROWSER HERE, and building one would be a mistake rather than an
 * omission: GitHub's own installation page is that browser, it is where the grant is made, and
 * a picker of ours could only ever offer repositories we hold no token for. When the list is
 * missing what the operator wants, the answer is to grant it there — so the empty state points
 * at Integrations rather than at a search box.
 *
 * WHAT IT IS ABOUT TO DO, in the words the confirm step uses: read the repository's committed
 * `.shipr` on its main branch; find or create the deployment repository, always private; seed
 * its `main`; cut and protect `ship` and one branch per environment with the gate's check; set
 * both repositories squash-only and record the registration. It writes NOTHING to the source
 * repository — an earlier draft of this dialog was going to tell the operator it commits a
 * `.shipr`, and it does not.
 */

type Step = 1 | 2 | 3;

/** `owner/name` → `owner`. The wire guarantees the shape (`fallbackSlug` is built by the same
 *  server code the run uses), so this is a split rather than a parse. */
function ownerOf(slug: string): string {
  return slug.slice(0, slug.indexOf('/'));
}

function nameOf(slug: string): string {
  return slug.slice(slug.indexOf('/') + 1);
}

export interface RegisterWizardProps {
  open: boolean;
  onClose: () => void;
  /** Only the two reads the wizard makes. Narrower than the whole client so a test can drive it
   *  with two functions, and so this file cannot quietly grow a third call. */
  client: Pick<ShiprClient, 'connectionRepositories' | 'connectionDeclaration'>;
  groups: readonly Group[];
  /** Where the new row is filed. The rail's own folder when the dialog was opened from one. */
  defaultGroupId?: string | null;
  connections?: readonly ForgeConnection[];
  /**
   * Dev repo slugs this workspace already has.
   *
   * Their rows are DISABLED rather than hidden: "why isn't it in the list" is a question with
   * no answer on a screen that simply omits them, and the answer — it is already here — is the
   * one thing the operator needs to stop looking.
   */
  registeredSlugs?: readonly string[];
  /** Leave for the Integrations dialog. Called when the installation granted nothing, which is a
   *  problem only that surface can fix. */
  onManageConnections?: () => void;
  onSubmit: (body: RegisterRequest) => Promise<void>;
}

export function RegisterWizard({
  open,
  onClose,
  client,
  groups,
  defaultGroupId = null,
  connections,
  registeredSlugs,
  onManageConnections,
  onSubmit,
}: RegisterWizardProps): React.ReactElement {
  const [step, setStep] = React.useState<Step>(1);
  const [connectionId, setConnectionId] = React.useState('');
  const [slug, setSlug] = React.useState('');
  const [groupId, setGroupId] = React.useState(defaultGroupId ?? '');
  const [mainBranch, setMainBranch] = React.useState('main');
  const [preparedBranch, setPreparedBranch] = React.useState('prepared');
  const [owner, setOwner] = React.useState('');
  const [name, setName] = React.useState('');

  /** `null` while the read is out — distinct from `[]`, which is an installation that granted
   *  nothing and is the case with its own empty state. */
  const [repos, setRepos] = React.useState<ForgeRepository[] | null>(null);
  const [listError, setListError] = React.useState<string | null>(null);

  const [decl, setDecl] = React.useState<DeclarationResponse | null>(null);
  const [reading, setReading] = React.useState(false);
  const [readError, setReadError] = React.useState<string | null>(null);

  const firstConnectionId = connections?.[0]?.id ?? '';

  // Re-seeded on OPEN, not on mount: a dialog stays mounted while closed, and a second
  // registration must not start on the answers of the first.
  React.useEffect(() => {
    if (!open) return;
    setStep(1);
    setConnectionId(firstConnectionId);
    setSlug('');
    setGroupId(defaultGroupId ?? '');
    setMainBranch('main');
    setPreparedBranch('prepared');
    setOwner('');
    setName('');
    setDecl(null);
    setReadError(null);
  }, [open, firstConnectionId, defaultGroupId]);

  // The installation's repositories. Re-read per connection, and discarded when a later
  // connection is chosen while this one is still out — `stale` is the whole reason this is not
  // a bare `.then(setRepos)`.
  React.useEffect(() => {
    if (!open || !connectionId) {
      setRepos(null);
      return;
    }
    let stale = false;
    setRepos(null);
    setListError(null);
    void client.connectionRepositories(connectionId).then(
      ({ repositories }) => {
        if (!stale) setRepos(repositories);
      },
      (e: Error) => {
        if (stale) return;
        setRepos([]);
        setListError(e.message);
      },
    );
    return () => {
      stale = true;
    };
  }, [open, connectionId, client]);

  const registered = React.useMemo(
    () => new Set(registeredSlugs ?? []),
    [registeredSlugs],
  );

  /**
   * The accounts a deployment repository may be created in.
   *
   * The connections' own `accountLogin`s, plus the source repository's own org — which is the
   * default, and which is reachable by definition: the installation that granted us the source
   * is installed there. No forge call is needed for any of it, and adding an org we hold no
   * connection for would be a menu entry the run refuses.
   */
  const orgs = React.useMemo(() => {
    const set = new Set<string>();
    for (const c of connections ?? []) if (c.accountLogin) set.add(c.accountLogin);
    if (slug) set.add(ownerOf(slug));
    return [...set].sort();
  }, [connections, slug]);

  /** The file already named every mirror — see `DeclarationResponse`. */
  const declared = decl?.deployments ?? null;

  const onPickRepo = React.useCallback((repo: ForgeRepository) => {
    setSlug(repo.slug);
    // The forge's own answer, not `main`: a repository whose default branch is `master` or
    // `trunk` is otherwise registered against a branch that does not exist, and the first
    // status run is where that turns up.
    setMainBranch(repo.defaultBranch);
    setDecl(null);
    setReadError(null);
  }, []);

  /** Step 1 → 2. The declaration is read HERE rather than on the pick, because it is what step
   *  2 is: with shards declared the step has nothing to ask, and without them it has two
   *  fields whose defaults come out of the same response. */
  const onNext = React.useCallback(() => {
    if (!connectionId || !slug) return;
    setReading(true);
    setReadError(null);
    void client.connectionDeclaration(connectionId, slug, mainBranch).then(
      (response) => {
        setReading(false);
        setDecl(response);
        setOwner(ownerOf(response.fallbackSlug));
        setName(nameOf(response.fallbackSlug));
        setStep(2);
      },
      (e: Error) => {
        setReading(false);
        setReadError(e.message);
      },
    );
  }, [client, connectionId, slug, mainBranch]);

  const body = React.useMemo<RegisterRequest>(() => {
    const fallbackSlug = decl?.fallbackSlug ?? '';
    return {
      slug,
      ...(connectionId ? { connectionId } : {}),
      ...(groupId ? { groupId } : {}),
      ...(mainBranch ? { mainBranch } : {}),
      ...(preparedBranch ? { preparedBranch } : {}),
      // Sent only on the fallback branch, and only when they actually differ from what the
      // server would compute anyway — a declared shard's slug is never overridable, and an
      // override equal to the default is a field the request does not need to carry.
      ...(declared === null && owner && owner !== ownerOf(fallbackSlug)
        ? { deploymentOwner: owner }
        : {}),
      ...(declared === null && name && name !== nameOf(fallbackSlug)
        ? { deploymentName: name }
        : {}),
    };
  }, [slug, connectionId, groupId, mainBranch, preparedBranch, declared, owner, name, decl]);

  const submit = React.useCallback(() => onSubmit(body), [onSubmit, body]);
  const { busy, error, run } = useSubmit(submit, onClose);

  /** What step 3 says will be created, and what step 2 showed. One derivation, so the confirm
   *  cannot name a repository the previous screen did not. */
  const targets = React.useMemo<{ shard: string; slug: string }[]>(() => {
    if (declared) return [...declared];
    return owner && name ? [{ shard: 'all', slug: `${owner}/${name}` }] : [];
  }, [declared, owner, name]);

  const canNext = Boolean(connectionId && slug) && !reading;
  const canRegister = targets.length > 0 && !busy;

  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>
            Register a repository
            <span className="pl-2 text-sm font-normal text-apt-text-muted">
              step {step} of 3
            </span>
          </DialogTitle>
        </DialogHeader>

        <form
          onSubmit={(e) => {
            e.preventDefault();
            if (step === 3) {
              if (canRegister) run();
            } else if (canNext) {
              step === 1 ? onNext() : setStep(3);
            }
          }}
          className="flex min-w-0 flex-col gap-3"
        >
          {step === 1 ? (
            <StepConnection
              connections={connections}
              connectionId={connectionId}
              onConnection={setConnectionId}
              repos={repos}
              listError={listError}
              registered={registered}
              slug={slug}
              onPick={onPickRepo}
              onManageConnections={onManageConnections}
              groups={groups}
              groupId={groupId}
              onGroup={setGroupId}
              mainBranch={mainBranch}
              onMainBranch={setMainBranch}
              preparedBranch={preparedBranch}
              onPreparedBranch={setPreparedBranch}
            />
          ) : step === 2 ? (
            <StepTarget
              slug={slug}
              declared={declared}
              note={decl?.note}
              orgs={orgs}
              owner={owner}
              onOwner={setOwner}
              name={name}
              onName={setName}
            />
          ) : (
            <StepConfirm slug={slug} mainBranch={mainBranch} targets={targets} />
          )}

          <ErrorText error={error ?? readError ?? null} />

          <div className="flex items-center justify-between gap-3 pt-1">
            <Button
              type="button"
              variant="ghost"
              disabled={step === 1 || busy}
              onClick={() => setStep((s) => (s === 3 ? 2 : 1))}
            >
              Back
            </Button>
            <div className="flex items-center gap-3">
              <Button type="button" variant="ghost" onClick={onClose}>
                Cancel
              </Button>
              {step === 3 ? (
                <Button type="submit" disabled={!canRegister}>
                  {busy ? 'Registering…' : 'Register'}
                </Button>
              ) : (
                <Button type="submit" disabled={!canNext}>
                  {reading ? 'Reading .shipr…' : 'Next'}
                </Button>
              )}
            </div>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

// ── step 1 ────────────────────────────────────────────────────────────────────

function StepConnection({
  connections,
  connectionId,
  onConnection,
  repos,
  listError,
  registered,
  slug,
  onPick,
  onManageConnections,
  groups,
  groupId,
  onGroup,
  mainBranch,
  onMainBranch,
  preparedBranch,
  onPreparedBranch,
}: {
  connections?: readonly ForgeConnection[];
  connectionId: string;
  onConnection: (id: string) => void;
  repos: ForgeRepository[] | null;
  listError: string | null;
  registered: ReadonlySet<string>;
  slug: string;
  onPick: (repo: ForgeRepository) => void;
  onManageConnections?: () => void;
  groups: readonly Group[];
  groupId: string;
  onGroup: (id: string) => void;
  mainBranch: string;
  onMainBranch: (v: string) => void;
  preparedBranch: string;
  onPreparedBranch: (v: string) => void;
}): React.ReactElement {
  return (
    <>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="shipr-register-connection">GitHub App installation</Label>
        {connections && connections.length > 0 ? (
          <Select
            id="shipr-register-connection"
            value={connectionId}
            onChange={(e) => onConnection(e.target.value)}
          >
            {connections.map((c) => (
              <option key={c.id} value={c.id}>
                {c.accountLogin ? `${c.accountLogin} — ${c.label}` : c.label}
              </option>
            ))}
          </Select>
        ) : (
          // NOT a hidden picker. An installation is what makes every step after this one
          // possible — the repository list, the deployment repository, the pushes — so its
          // absence is stated where the list would have been rather than discovered at the
          // first run.
          <Missing
            text="No GitHub App installation. Install the app on the account that holds the repository, and its repositories will be listed here."
            onManageConnections={onManageConnections}
          />
        )}
      </div>

      <div className="flex flex-col gap-1.5">
        <Label>Repository</Label>
        {repos === null ? (
          <p className="rounded border border-apt-border bg-apt-surface-2 px-3 py-2 text-xs text-apt-text-muted">
            Reading what this installation was granted…
          </p>
        ) : repos.length === 0 ? (
          <Missing
            text={
              listError ??
              'This installation was granted no repositories. Grant it the repository on GitHub and it will appear here.'
            }
            onManageConnections={onManageConnections}
          />
        ) : (
          <ul className="flex max-h-64 flex-col overflow-auto rounded border border-apt-border bg-apt-surface-2">
            {repos.map((repo) => {
              const taken = registered.has(repo.slug);
              return (
                <li key={repo.slug}>
                  {/* Disabled, not omitted — see `registeredSlugs`. */}
                  <button
                    type="button"
                    disabled={taken}
                    aria-pressed={repo.slug === slug}
                    // SPELLED OUT, because the row's own text runs together when it is read
                    // rather than seen: two adjacent spans with no space between them are
                    // announced as `acme/siteprivate · trunk`. The slug is the whole point of
                    // the row, so it gets to be the name, and the tail is said in words.
                    aria-label={
                      taken
                        ? `${repo.slug} — already registered`
                        : repo.private
                          ? `${repo.slug} — private, default branch ${repo.defaultBranch}`
                          : `${repo.slug} — default branch ${repo.defaultBranch}`
                    }
                    onClick={() => onPick(repo)}
                    className={`flex w-full items-baseline gap-2 px-3 py-1.5 text-left text-xs transition-colors ${
                      taken
                        ? 'cursor-not-allowed text-apt-text-muted opacity-60'
                        : repo.slug === slug
                          ? 'bg-apt-gold/15 text-apt-text'
                          : 'text-apt-text hover:bg-apt-gold/10'
                    }`}
                  >
                    <span className="min-w-0 flex-1 truncate font-mono">
                      {repo.slug}
                    </span>
                    <span className="shrink-0 text-apt-text-muted">
                      {taken
                        ? 'already registered'
                        : repo.private
                          ? `private · ${repo.defaultBranch}`
                          : repo.defaultBranch}
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </div>

      <div className="flex flex-col gap-1.5">
        <Label htmlFor="shipr-register-group">Folder</Label>
        <Select
          id="shipr-register-group"
          value={groupId}
          onChange={(e) => onGroup(e.target.value)}
        >
          <option value="">(top level)</option>
          {flattenGroups(groups).map((g) => (
            <option key={g.id} value={g.id}>
              {'  '.repeat(g.depth)}
              {g.name}
            </option>
          ))}
        </Select>
      </div>

      {/* Prefilled from the repository's own default branch, and editable because `prepared`
          has no forge answer to read and neither branch can be changed afterwards — a
          registration is the only moment either is settable. */}
      <div className="flex gap-2">
        <div className="flex min-w-0 flex-1 flex-col gap-1.5">
          <Label htmlFor="shipr-register-main">Main branch</Label>
          <Input
            id="shipr-register-main"
            value={mainBranch}
            onChange={(e) => onMainBranch(e.target.value)}
            placeholder="main"
          />
        </div>
        <div className="flex min-w-0 flex-1 flex-col gap-1.5">
          <Label htmlFor="shipr-register-prepared">Prepared branch</Label>
          <Input
            id="shipr-register-prepared"
            value={preparedBranch}
            onChange={(e) => onPreparedBranch(e.target.value)}
            placeholder="prepared"
          />
        </div>
      </div>
    </>
  );
}

/** The one empty state both halves of step 1 use: a sentence, and the only surface that can
 *  act on it. */
function Missing({
  text,
  onManageConnections,
}: {
  text: string;
  onManageConnections?: () => void;
}): React.ReactElement {
  return (
    <div className="flex flex-col items-start gap-2 rounded border border-apt-border bg-apt-surface-2 px-3 py-2">
      <p className="text-xs text-apt-text-muted">{text}</p>
      {/* The button is labelled for where it GOES, not for what the prop is called. The
          destination is the dialog the toolbar's Integrations button opens, and a button that
          said "Connections" would land the operator on a title they had not asked for. */}
      {onManageConnections ? (
        <Button type="button" size="sm" variant="ghost" onClick={onManageConnections}>
          Integrations
        </Button>
      ) : null}
    </div>
  );
}

// ── step 2 ────────────────────────────────────────────────────────────────────

function StepTarget({
  slug,
  declared,
  note,
  orgs,
  owner,
  onOwner,
  name,
  onName,
}: {
  slug: string;
  declared: readonly { shard: string; slug: string }[] | null;
  note?: string;
  orgs: readonly string[];
  owner: string;
  onOwner: (v: string) => void;
  name: string;
  onName: (v: string) => void;
}): React.ReactElement {
  if (declared) {
    return (
      <>
        {/* NOTHING TO CHOOSE HERE, and that is the point. The file already names every mirror,
            and a form that could override it would be two sources of truth for one slug —
            exactly the drift the CLI refuses when `--org` is passed beside `--deployment`. */}
        <p className="text-xs text-apt-text-muted">
          <span className="font-mono">{slug}</span> declares its deployment
          repositories in its committed <span className="font-mono">.shipr</span>, so
          they are read from the file rather than chosen here.
        </p>
        <dl className="flex flex-col gap-1 rounded border border-apt-border bg-apt-surface-2 px-3 py-2">
          {declared.map((d) => (
            <div key={d.shard} className="flex gap-2 text-xs">
              <dt className="w-28 shrink-0 text-apt-text-muted">{d.shard}</dt>
              <dd className="min-w-0 break-all font-mono text-apt-text">{d.slug}</dd>
            </div>
          ))}
        </dl>
      </>
    );
  }

  return (
    <>
      <p className="text-xs text-apt-text-muted">
        {note ? (
          <>
            {/* The declaration was THERE and unusable, which is a different fact from its
                absence and worth one sentence: the operator can go and fix the file. */}
            <span className="font-mono">{slug}</span>&apos;s{' '}
            <span className="font-mono">.shipr</span> could not be used — {note}. One
            deployment repository will be created instead.
          </>
        ) : (
          <>
            <span className="font-mono">{slug}</span> declares no{' '}
            <span className="font-mono">[deployments]</span>, so one deployment
            repository is created for the whole repository.
          </>
        )}
      </p>

      <div className="flex gap-2">
        <div className="flex min-w-0 flex-1 flex-col gap-1.5">
          <Label htmlFor="shipr-register-owner">Organization</Label>
          {/* The accounts the caller actually holds an installation for — see `orgs`. */}
          <Select
            id="shipr-register-owner"
            value={owner}
            onChange={(e) => onOwner(e.target.value)}
          >
            {orgs.map((o) => (
              <option key={o} value={o}>
                {o}
              </option>
            ))}
          </Select>
        </div>
        <div className="flex min-w-0 flex-1 flex-col gap-1.5">
          <Label htmlFor="shipr-register-name">Name</Label>
          <Input
            id="shipr-register-name"
            value={name}
            onChange={(e) => onName(e.target.value)}
            placeholder="site-deployment"
          />
        </div>
      </div>
    </>
  );
}

// ── step 3 ────────────────────────────────────────────────────────────────────

function StepConfirm({
  slug,
  mainBranch,
  targets,
}: {
  slug: string;
  mainBranch: string;
  targets: readonly { shard: string; slug: string }[];
}): React.ReactElement {
  return (
    <>
      <p className="text-sm text-apt-text">
        Register <span className="font-mono">{slug}</span> and{' '}
        {targets.length === 1
          ? 'create its deployment repository'
          : `create its ${targets.length} deployment repositories`}
        , private, if they do not already exist:
      </p>
      <ul className="flex flex-col gap-1 rounded border border-apt-border bg-apt-surface-2 px-3 py-2">
        {targets.map((t) => (
          <li key={t.shard} className="flex gap-2 text-xs">
            <span className="w-28 shrink-0 text-apt-text-muted">{t.shard}</span>
            <span className="min-w-0 break-all font-mono text-apt-text">{t.slug}</span>
          </li>
        ))}
      </ul>
      {/* The five steps, in the order the run does them. Written out because every one of them
          touches a repository the operator owns, and because the one thing it does NOT do —
          write to the source repository — is worth being able to read. */}
      <ol className="flex list-decimal flex-col gap-1 pl-5 text-xs text-apt-text-muted">
        <li>
          Read <span className="font-mono">.shipr</span> from{' '}
          <span className="font-mono">{slug}</span> on{' '}
          <span className="font-mono">{mainBranch}</span>.
        </li>
        <li>Find or create each deployment repository, always private.</li>
        <li>
          Seed each mirror&apos;s <span className="font-mono">main</span> from{' '}
          <span className="font-mono">
            {slug}:{mainBranch}
          </span>
          .
        </li>
        <li>
          Cut and protect <span className="font-mono">ship</span> and one branch per
          environment, with the gate&apos;s status check.{' '}
          <span className="font-mono">main</span> is left unprotected.
        </li>
        <li>
          Set both repositories squash-only, link platform connections, and record the
          registration.
        </li>
      </ol>
      <p className="text-xs text-apt-text-muted">
        Nothing is written to <span className="font-mono">{slug}</span> — no commit, no{' '}
        <span className="font-mono">.shipr</span>, no branch.
      </p>
    </>
  );
}
