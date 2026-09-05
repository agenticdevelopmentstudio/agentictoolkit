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
 * THE PICK IS AN ORG-AND-REPO BROWSER — owners down the left, that owner's repositories down
 * the right, and a filter over both. It is a browser over WHAT THE INSTALLATION GRANTED and
 * nothing else, which is the distinction that matters: an installation covering four orgs and
 * two hundred repositories arrived here as one flat scrolling column sorted by a slug whose
 * first half repeated for pages, and finding a repository in it meant reading the same owner
 * forty times. Grouping is free — every row already carries its owner — and it turns that
 * column into two short ones.
 *
 * What is still deliberately absent is a picker of repositories we hold no token for. GitHub's
 * own installation page is where the GRANT is made, and offering a repository outside it would
 * put the failure at the first push of a run instead of at the moment of choosing. So the
 * empty state still points at Integrations rather than at a search box: the filter narrows what
 * was granted, it never reaches past it.
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
  client: Pick<
    ShiprClient,
    | 'connectionRepositories'
    | 'refreshConnectionRepositories'
    | 'connectionDeclaration'
  >;
  groups: readonly Group[];
  /** Where the new row is filed. The rail's own folder when the dialog was opened from one. */
  defaultGroupId?: string | null;
  connections?: readonly ForgeConnection[];
  /**
   * Why {@link connections} could not be read, when that is why it is missing.
   *
   * Undefined `connections` means the read has not landed; `[]` means it landed and there is
   * nothing installed; this means it failed. Three situations that share a shape and share
   * nothing else — and the empty box the operator is looking at is the same in all three, so
   * the sentence under it is the only thing that can tell them apart.
   */
  connectionsError?: string | null;
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
  connectionsError = null,
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
  /** Why the list on screen is the STORED one. Set only when a refresh failed on top of a read
   *  that succeeded, which is the one case where there is something to show and a reason it
   *  might be out of date — both facts, and neither is worth suppressing for the other. */
  const [refreshError, setRefreshError] = React.useState<string | null>(null);

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

  // The installation's repositories: what was written down, and then what GitHub says now.
  //
  // TWO CALLS, IN THAT ORDER, because they answer different questions and the operator needs
  // the first answer immediately. The stored list is a database read that cannot fail on
  // GitHub's account, so the browser is on screen without waiting on a forge round trip; the
  // refresh replaces it behind them. When the refresh fails the stored list STAYS, with a note
  // beside it — a list read an hour ago is a list you can pick from, and an empty box is not.
  //
  // The first open after an integration is saved pays for two forge calls, because the stored
  // read had nothing to draw on and went and asked itself. Deciding that from `readAt` would
  // mean comparing the server's clock against the browser's to save one request, which is a
  // worse trade than the request.
  //
  // `stale` discards every half of this when a later connection is chosen while an earlier
  // one is still out, and is the whole reason this is not a bare `.then(setRepos)`.
  React.useEffect(() => {
    if (!open || !connectionId) {
      setRepos(null);
      return;
    }
    let stale = false;
    setRepos(null);
    setListError(null);
    setRefreshError(null);
    void client.connectionRepositories(connectionId).then(
      ({ repositories }) => {
        if (stale) return;
        setRepos(repositories);
        return client.refreshConnectionRepositories(connectionId).then(
          (fresh) => {
            if (!stale) setRepos(fresh.repositories);
          },
          (e: Error) => {
            // Deliberately not `setRepos`: what is on screen is a real answer GitHub gave,
            // and replacing it with nothing because we could not ask again is the trade this
            // whole cache exists to stop making.
            if (!stale) setRefreshError(e.message);
          },
        );
      },
      (e: Error) => {
        // The stored read failed, so there is nothing to leave standing and nothing to
        // refresh. The empty state is all that is left, and it carries the reason.
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
              connectionsError={connectionsError}
              connectionId={connectionId}
              onConnection={setConnectionId}
              repos={repos}
              listError={listError}
              refreshError={refreshError}
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

/**
 * The org-and-repo browser: owners on the left, that owner's repositories on the right.
 *
 * ONE filter drives both columns, and it matches the WHOLE slug rather than the column it is
 * drawn above. `acme` narrows to that owner's repositories, `site` narrows to repositories so
 * named across every owner, and `acme/site` does both — which is the same string an operator
 * would have typed into the free-text field this dialog replaced, so the thing they already
 * know how to type still works. Two filters, one per column, would have made "which box does
 * `acme/site` go in" a question with a wrong answer.
 *
 * The owner column is derived, never fetched: every row already carries its owner, so there is
 * no second call and no state that can disagree with the list it summarises.
 */
function RepoBrowser({
  repos,
  registered,
  slug,
  onPick,
}: {
  repos: readonly ForgeRepository[];
  registered: ReadonlySet<string>;
  slug: string;
  onPick: (repo: ForgeRepository) => void;
}): React.ReactElement {
  const [filter, setFilter] = React.useState('');
  const [ownerPick, setOwnerPick] = React.useState<string | null>(null);

  // A new installation is a new list of owners, and the old pick names nobody in it. Keyed on
  // the array rather than on a connection id, because this component is handed the list and
  // never the thing that produced it.
  React.useEffect(() => {
    setFilter('');
    setOwnerPick(null);
  }, [repos]);

  const needle = filter.trim().toLowerCase();
  const matched = React.useMemo(
    () => (needle ? repos.filter((r) => r.slug.toLowerCase().includes(needle)) : repos),
    [repos, needle],
  );

  /** `owner → its repositories`, in the order the forge listed them, owners sorted. */
  const byOwner = React.useMemo(() => {
    const map = new Map<string, ForgeRepository[]>();
    for (const repo of matched) {
      const owner = ownerOf(repo.slug);
      const bucket = map.get(owner);
      if (bucket) bucket.push(repo);
      else map.set(owner, [repo]);
    }
    return [...map.entries()].sort(([a], [b]) => a.localeCompare(b));
  }, [matched]);

  // The shown owner is DERIVED rather than stored, so a filter that narrows the list past the
  // operator's pick still shows repositories instead of an empty right-hand column. The picked
  // repository's own owner wins when nothing has been clicked, which is what makes reopening
  // the step land where it was left.
  const owners = byOwner.map(([owner]) => owner);
  const owner =
    (ownerPick && owners.includes(ownerPick) ? ownerPick : null) ??
    (slug && owners.includes(ownerOf(slug)) ? ownerOf(slug) : null) ??
    owners[0] ??
    '';
  const shown = byOwner.find(([o]) => o === owner)?.[1] ?? [];

  return (
    <div className="flex flex-col gap-1.5">
      <Input
        aria-label="Filter repositories"
        placeholder="Filter — owner, name, or owner/name"
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
      />
      {byOwner.length === 0 ? (
        <p className="rounded border border-apt-border bg-apt-surface-2 px-3 py-2 text-xs text-apt-text-muted">
          No repository this installation granted matches “{filter.trim()}”.
        </p>
      ) : (
        <div className="grid grid-cols-[minmax(0,11rem)_1fr] overflow-hidden rounded border border-apt-border bg-apt-surface-2">
          <ul
            aria-label="Organizations"
            className="flex max-h-64 flex-col overflow-auto border-r border-apt-border"
          >
            {byOwner.map(([o, list]) => (
              <li key={o}>
                <button
                  type="button"
                  aria-pressed={o === owner}
                  aria-label={`${o} — ${list.length} ${list.length === 1 ? 'repository' : 'repositories'}`}
                  onClick={() => setOwnerPick(o)}
                  className={`flex w-full items-baseline gap-2 px-3 py-1.5 text-left text-xs transition-colors ${
                    o === owner
                      ? 'bg-apt-gold/15 text-apt-text'
                      : 'text-apt-text hover:bg-apt-gold/10'
                  }`}
                >
                  <span className="min-w-0 flex-1 truncate font-mono">{o}</span>
                  <span className="shrink-0 text-apt-text-muted">{list.length}</span>
                </button>
              </li>
            ))}
          </ul>
          <ul aria-label="Repositories" className="flex max-h-64 flex-col overflow-auto">
            {shown.map((repo) => {
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
                    // announced as `acme/siteprivate · trunk`. It names the FULL slug even
                    // though the column shows only the repository half — the owner is a
                    // heading in the other column, which a row read on its own does not carry.
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
                      {nameOf(repo.slug)}
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
        </div>
      )}
    </div>
  );
}

function StepConnection({
  connections,
  connectionsError,
  connectionId,
  onConnection,
  repos,
  listError,
  refreshError,
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
  connectionsError: string | null;
  connectionId: string;
  onConnection: (id: string) => void;
  repos: ForgeRepository[] | null;
  listError: string | null;
  refreshError: string | null;
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
        ) : connectionsError ? (
          // The read FAILED. Its own sentence, because "we could not ask" and "we asked and
          // there are none" prescribe opposite next moves, and the one thing that must never
          // happen here is telling an operator to go install an app they have already
          // installed.
          <Missing
            text={`Your GitHub App installations could not be read: ${connectionsError}`}
            onManageConnections={onManageConnections}
          />
        ) : connections === undefined ? (
          <p className="rounded border border-apt-border bg-apt-surface-2 px-3 py-2 text-xs text-apt-text-muted">
            Reading your GitHub App installations…
          </p>
        ) : (
          // Read, and empty. NOT a hidden picker: an installation is what makes every step
          // after this one possible — the repository list, the deployment repository, the
          // pushes — so its absence is stated where the list would have been rather than
          // discovered at the first run.
          //
          // The second sentence exists because this state has two causes and only one of them
          // is visible from here. Nothing is installed, or the credentials the backend holds
          // are not credentials GitHub accepts — and that second question belongs to the Test
          // button on the integration, which asks GitHub out loud and reports what it says.
          // Answering it a second time here would be two places diagnosing one thing.
          <Missing
            text="This app isn't installed on any account. Install it on GitHub — on your own account or an organization — and its repositories will be listed here. If you have already installed it, open Integrations and press Test: that says what GitHub is refusing."
            onManageConnections={onManageConnections}
          />
        )}
      </div>

      <div className="flex flex-col gap-1.5">
        <Label>Repository</Label>
        {/* Above the list rather than inside it, because it qualifies whichever of the three
            things below is showing — including the empty one, where "granted nothing" and
            "granted nothing as of the last time we could ask" are the same screen otherwise. */}
        {refreshError && repos !== null ? (
          <p className="rounded border border-apt-border bg-apt-surface-2 px-3 py-2 text-xs text-apt-text-muted">
            Showing the last list GitHub gave us — it could not be re-read just now:{' '}
            {refreshError}
          </p>
        ) : null}
        {!connectionId ? (
          // There is no installation to read FROM, so nothing is being read and saying
          // otherwise is the same conflation this whole block exists to undo: the field above
          // has just explained — in one of three different sentences — why there is none, and
          // a spinner underneath it would contradict every one of them and never resolve.
          <p className="rounded border border-apt-border bg-apt-surface-2 px-3 py-2 text-xs text-apt-text-muted">
            Repositories are listed once there is an installation to read them from.
          </p>
        ) : repos === null ? (
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
          <RepoBrowser
            repos={repos}
            registered={registered}
            slug={slug}
            onPick={onPick}
          />
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
