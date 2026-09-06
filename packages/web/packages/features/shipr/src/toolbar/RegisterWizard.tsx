'use client';

import * as React from 'react';

import { Button } from '@agenticdevelopertoolkit/ui/components/button';
import { DialogActions } from '@agenticdevelopertoolkit/ui/components/dialog-actions';
import { ErrorText } from '@agenticdevelopertoolkit/ui/components/error-text';
import { Input } from '@agenticdevelopertoolkit/ui/components/input';
import { List, ListItem } from '@agenticdevelopertoolkit/ui/components/list';
import { Select } from '@agenticdevelopertoolkit/ui/components/select';

import type { ForgeConnection, ForgeRepository, RegisterRequest } from '../types';
import type { ShiprClient } from '../client';
import { useSubmit } from './dialogs';

/**
 * Register: PICK A REPOSITORY. That is the whole screen, and it is one job.
 *
 * It was three steps and seven fields — an installation to choose, a folder, a main branch, a
 * prepared branch, a deployment owner and name, and a confirmation of all of it — asked of an
 * operator whose actual intent was "add this repo". Every one of those questions has a right
 * answer that is derivable here or on the server, and asking anyway is how a two-click job
 * became a form. So they are gone, and each is now answered where it is known:
 *
 * - the **installation** comes off the pick (`grantedBy`) — the repository came out of an
 *   installation's grant, so the one that can reach it is not a question anyone need be asked;
 * - the **main branch** comes off the repository's own `defaultBranch` — a repo whose default
 *   is `master` or `trunk` registered against `main` fails at the first status run;
 * - the **prepared branch** and the **folder** are absent from the request, which is the same
 *   as sending their defaults: the column defaults to `prepared`, and no folder is the root;
 * - the **deployment repository** is the server's `fallbackSlug`, or whatever the source's
 *   committed `.shipr` declares. The file and a form could never disagree if only the file
 *   can speak, so only the file does.
 *
 * NOTHING HERE IS DRAWN BY HAND. The org menu is `Select`, the filter is `Input`, the rows are
 * `List`/`ListItem`, and the two buttons are `DialogActions` — the same vocabulary every other
 * dialog in this console is built from. The two-column owner/repository browser that used to
 * live here reimplemented all four badly.
 *
 * The keyboard is the point of the layout: the filter takes focus on open, a pick moves focus
 * to OK, so Enter commits and Escape cancels without anyone reaching for the mouse. Escape is
 * caught HERE — this is not a modal, it renders inside the Configure dialog's pane, and an
 * uncaught Escape would close that dialog out from under it.
 *
 * What is still deliberately absent is a picker of repositories we hold no token for. GitHub's
 * own installation page is where the GRANT is made, so the empty state points at Integrations
 * rather than at a search box: the filter narrows what was granted, it never reaches past it.
 */

/** `owner/name` → `owner`. The wire guarantees the shape, so this is a split, not a parse. */
function ownerOf(slug: string): string {
  return slug.slice(0, slug.indexOf('/'));
}

function nameOf(slug: string): string {
  return slug.slice(slug.indexOf('/') + 1);
}

export interface RegisterWizardProps {
  open: boolean;
  onClose: () => void;
  /** Only the two reads this screen makes. Narrower than the whole client so a test can drive
   *  it with two functions, and so this file cannot quietly grow a third call. */
  client: Pick<ShiprClient, 'connectionRepositories' | 'refreshConnectionRepositories'>;
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
  /** Leave for the Integrations dialog. Called when the installation granted nothing, which is
   *  a problem only that surface can fix. */
  onManageConnections?: () => void;
  onSubmit: (body: RegisterRequest) => Promise<void>;
}

export function RegisterWizard({
  open,
  onClose,
  client,
  connections,
  connectionsError = null,
  registeredSlugs,
  onManageConnections,
  onSubmit,
}: RegisterWizardProps): React.ReactElement | null {
  /** THE ONE ANSWER THIS SCREEN COLLECTS. Everything the request carries is read off it. */
  const [picked, setPicked] = React.useState<ForgeRepository | null>(null);
  const [owner, setOwner] = React.useState('');
  const [filter, setFilter] = React.useState('');

  /** `null` while the read is out — distinct from `[]`, which is an installation that granted
   *  nothing and is the case with its own empty state. */
  const [repos, setRepos] = React.useState<ForgeRepository[] | null>(null);
  const [listError, setListError] = React.useState<string | null>(null);
  /** Why the list on screen is the STORED one. Set only when a refresh failed on top of a read
   *  that succeeded, which is the one case where there is something to show and a reason it
   *  might be out of date — both facts, and neither is worth suppressing for the other. */
  const [refreshError, setRefreshError] = React.useState<string | null>(null);

  /**
   * Which installation granted each repository, keyed by slug.
   *
   * This is what replaced the installation dropdown. Asking an operator to pick an installation
   * before picking a repository asked them a question about our plumbing in order to answer a
   * question about their code — and got it wrong half the time, because which installation
   * granted a given repository is not a thing anyone knows off the top of their head. Every
   * installation's repositories are read and merged into one list instead, and the pick answers
   * both questions at once: the slug they chose, and the installation that can reach it.
   */
  const [grantedBy, setGrantedBy] = React.useState<ReadonlyMap<string, string>>(
    () => new Map(),
  );

  const filterRef = React.useRef<HTMLInputElement>(null);
  const footerRef = React.useRef<HTMLDivElement>(null);

  const connectionIds = React.useMemo(
    () => (connections ?? []).map((c) => c.id),
    [connections],
  );
  /** The effect's key, rather than the array itself: the host rebuilds `connections` on every
   *  render, and an equal-but-new array would re-read every installation each time. */
  const connectionKey = connectionIds.join(',');
  /** Whether the installations question has been ANSWERED, either way. A failed read is an
   *  answer — it is the one that never arrives otherwise, and an empty box that says "reading…"
   *  for the rest of the session is the exact failure this distinction exists to prevent. */
  const connectionsSettled = connections !== undefined || Boolean(connectionsError);

  // Re-seeded on OPEN, not on mount: the host may keep this mounted while closed, and a second
  // registration must not start on the answers of the first.
  React.useEffect(() => {
    if (!open) return;
    setPicked(null);
    setOwner('');
    setFilter('');
  }, [open]);

  // Every installation's repositories, merged into the one list.
  //
  // TWO CALLS PER INSTALLATION, IN THAT ORDER, because they answer different questions and the
  // operator needs the first answer immediately. The stored list is a database read that cannot
  // fail on GitHub's account, so the list is on screen without waiting on a forge round trip;
  // the refresh replaces it behind them. When a refresh fails the stored list STAYS, with a note
  // beside it — a list read an hour ago is a list you can pick from, and an empty box is not.
  //
  // The installations are read in PARALLEL and republished as each half lands, so one slow
  // account does not hold the others off the screen, and one FAILING account does not take them
  // with it: a failure becomes the empty state's sentence only when nothing at all was read.
  //
  // `stale` discards every half of this when the set of installations changes while reads are
  // still out, and is the whole reason this is not a bare `.then(setRepos)`.
  React.useEffect(() => {
    if (!open || connectionIds.length === 0) {
      // `null` is "still reading" and `[]` is "read, and there are none" — so an unread
      // `connections` must not collapse into the same empty state as an empty one.
      setRepos(connectionsSettled ? [] : null);
      setGrantedBy(new Map());
      return;
    }
    let stale = false;
    setRepos(null);
    setGrantedBy(new Map());
    setListError(null);
    setRefreshError(null);

    const byConnection = new Map<string, ForgeRepository[]>();
    const storedFailures: string[] = [];
    const refreshFailures: string[] = [];

    const publish = () => {
      if (stale) return;
      setRefreshError(refreshFailures.length > 0 ? refreshFailures.join('; ') : null);
      if (byConnection.size === 0) {
        // Nothing has landed. Only once every read has SETTLED is that an empty list rather
        // than a list still arriving.
        if (storedFailures.length === connectionIds.length) {
          setRepos([]);
          setListError(storedFailures.join('; '));
        }
        return;
      }
      // Deduped by slug, because two installations on one account are granted overlapping
      // repositories and the same repository twice is two rows the operator cannot tell apart.
      const seen = new Map<string, ForgeRepository>();
      const from = new Map<string, string>();
      for (const [id, list] of byConnection) {
        for (const repo of list) {
          if (seen.has(repo.slug)) continue;
          seen.set(repo.slug, repo);
          from.set(repo.slug, id);
        }
      }
      setRepos([...seen.values()]);
      setGrantedBy(from);
      setListError(null);
    };

    void Promise.all(
      connectionIds.map(async (id) => {
        try {
          const { repositories } = await client.connectionRepositories(id);
          byConnection.set(id, repositories);
        } catch (e) {
          storedFailures.push((e as Error).message);
          publish();
          return;
        }
        publish();
        try {
          const fresh = await client.refreshConnectionRepositories(id);
          byConnection.set(id, fresh.repositories);
        } catch (e) {
          // Deliberately not clearing the list: what is on screen is a real answer GitHub
          // gave, and replacing it with nothing because we could not ask again is the trade
          // this whole cache exists to stop making.
          refreshFailures.push((e as Error).message);
        }
        publish();
      }),
    );

    return () => {
      stale = true;
    };
    // `connectionKey` stands in for `connectionIds`; see its comment above.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, connectionKey, connectionsSettled, client]);

  const registered = React.useMemo(
    () => new Set(registeredSlugs ?? []),
    [registeredSlugs],
  );

  /** The owners in the menu — DERIVED from the rows, never fetched. Every row carries its
   *  owner, so there is no second call and no state that can disagree with the list it
   *  summarises. */
  const owners = React.useMemo(
    () => [...new Set((repos ?? []).map((r) => ownerOf(r.slug)))].sort(),
    [repos],
  );

  /** The menu's value, resolved rather than stored: the list arrives after the first paint and
   *  can change again under a refresh, so an owner held in state would name one that is no
   *  longer there and show an empty list under a menu that looks answered. */
  const activeOwner = owners.includes(owner) ? owner : (owners[0] ?? '');

  /** That owner's repositories, narrowed by the filter. The filter matches the WHOLE slug, so
   *  the `acme/site` an operator would have typed into the free-text field this replaced still
   *  works, and so does the bare name. */
  const shown = React.useMemo(() => {
    const needle = filter.trim().toLowerCase();
    return (repos ?? [])
      .filter((r) => ownerOf(r.slug) === activeOwner)
      .filter((r) => needle === '' || r.slug.toLowerCase().includes(needle))
      .sort((a, b) => a.slug.localeCompare(b.slug));
  }, [repos, activeOwner, filter]);

  /**
   * ONE empty box, three causes, three sentences.
   *
   * They share a shape — no repositories — and share nothing else, and for a while they shared
   * one sentence too: "No GitHub App installation". That sentence is a guess in two of the
   * three cases and flatly wrong in one, and the wrong one is the expensive one: it sends an
   * operator to GitHub to install an app they have already installed, over a read that simply
   * failed.
   */
  const emptySentence =
    connectionsError != null
      ? `Your integrations could not be read: ${connectionsError}`
      : listError != null
        ? listError
        : "This workspace's GitHub App hasn't been granted any repositories yet — open Integrations and press Test.";

  const body = React.useMemo<RegisterRequest>(
    () => ({
      slug: picked?.slug ?? '',
      // Derived from the pick, never asked for: the run needs an installation that can actually
      // reach this repository, and the list knows which one that is because the repository came
      // out of its grant.
      ...(picked && grantedBy.has(picked.slug)
        ? { connectionId: grantedBy.get(picked.slug)! }
        : {}),
      // The forge's own answer, not `main`.
      ...(picked?.defaultBranch ? { mainBranch: picked.defaultBranch } : {}),
    }),
    [picked, grantedBy],
  );

  const submit = React.useCallback(() => onSubmit(body), [onSubmit, body]);
  const { busy, error, run } = useSubmit(submit, onClose);

  // The filter takes focus when the screen opens — it is the only thing here anyone types into,
  // and landing focus on OK (which is disabled until a pick) or on Cancel would be a keyboard
  // that starts pointed at the exit.
  React.useEffect(() => {
    if (open) filterRef.current?.focus();
  }, [open]);

  // Focus follows the answer, so Enter means OK from here without a reach for the mouse. It has
  // to be an EFFECT and not part of the click handler: OK is natively `disabled` until a repo is
  // picked, and `setPicked` has not re-rendered yet while the handler is still running — so
  // focusing there aims at a disabled button, which the browser silently refuses, leaving focus
  // on the filter. By the time this runs the button is live.
  //
  // The confirm is the LAST button `DialogActions` draws (cancel, then confirm); while `busy` it
  // draws a spinner and no buttons at all, which is exactly when there is nothing to focus.
  React.useEffect(() => {
    if (!picked || busy) return;
    const buttons = footerRef.current?.querySelectorAll('button');
    buttons?.[buttons.length - 1]?.focus();
  }, [picked, busy]);

  const onPick = React.useCallback((repo: ForgeRepository) => setPicked(repo), []);

  // Unmounted rather than hidden while closed, so the host's pane holds the repository list
  // and nothing else. The reset effect above still keys on `open` — a host that keeps this
  // mounted across opens gets the same fresh start a remount gives.
  if (!open) return null;

  return (
    <div
      className="flex min-h-0 min-w-0 flex-1 flex-col gap-3 overflow-hidden"
      onKeyDown={(e) => {
        if (e.key !== 'Escape') return;
        // Escape is CANCEL, and it stops here. This renders inside the Configure dialog's pane
        // rather than in a modal of its own, so an Escape allowed past would close that dialog
        // and take the repository list with it — the operator asked to leave one screen, not two.
        e.preventDefault();
        e.stopPropagation();
        e.nativeEvent.stopImmediatePropagation();
        onClose();
      }}
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          if (picked && !busy) run();
        }}
        className="flex min-h-0 min-w-0 flex-1 flex-col gap-3"
      >
        <Select
          aria-label="Organization"
          value={activeOwner}
          disabled={owners.length === 0}
          onChange={(e) => {
            setOwner(e.target.value);
            setPicked(null);
          }}
        >
          {owners.map((o) => (
            <option key={o} value={o}>
              {o}
            </option>
          ))}
        </Select>

        <Input
          ref={filterRef}
          aria-label="Filter repositories"
          placeholder="Filter repositories"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
        />

        {repos === null ? (
          <p className="min-h-0 flex-1 text-sm text-apt-text-muted">Reading your repositories…</p>
        ) : repos.length === 0 ? (
          <div className="flex min-h-0 flex-1 flex-col items-start gap-2">
            <p className="text-sm text-apt-text-muted">{emptySentence}</p>
            {onManageConnections ? (
              <Button type="button" variant="ghost" onClick={onManageConnections}>
                Integrations
              </Button>
            ) : null}
          </div>
        ) : (
          <List aria-label="Repositories" className="min-h-0 flex-1 overflow-auto">
            {shown.length === 0 ? (
              // In the list's own frame rather than instead of it: an empty bordered box reads
              // as a control that failed to draw.
              <ListItem className="text-sm text-apt-text-muted">
                No repository here matches “{filter}”.
              </ListItem>
            ) : null}
            {shown.map((repo) => {
              const already = registered.has(repo.slug);
              return (
                <ListItem key={repo.slug} className="p-0">
                  <button
                    type="button"
                    disabled={already}
                    // The row SHOWS the name — the owner is the menu above, and repeating it on
                    // every row is what made the old flat column unreadable. It is ADDRESSED by
                    // the whole slug, which is the thing that identifies a repository.
                    aria-label={already ? `${repo.slug} — already registered` : repo.slug}
                    aria-pressed={picked?.slug === repo.slug}
                    onClick={() => onPick(repo)}
                    className={[
                      'flex w-full items-center justify-between gap-3 px-3 py-1.5 text-left text-sm',
                      'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-apt-gold/25',
                      already
                        ? 'cursor-not-allowed text-apt-text-muted'
                        : picked?.slug === repo.slug
                          ? 'bg-apt-gold/15 text-apt-text'
                          : 'text-apt-text hover:bg-apt-border/40',
                    ].join(' ')}
                  >
                    <span className="truncate">{nameOf(repo.slug)}</span>
                    {already ? (
                      <span className="shrink-0 text-xs text-apt-text-muted">Registered</span>
                    ) : null}
                  </button>
                </ListItem>
              );
            })}
          </List>
        )}

        {refreshError ? (
          <p className="text-xs text-apt-text-muted">
            Showing the stored list — {refreshError}
          </p>
        ) : null}

        <ErrorText error={error} />
      </form>

      {/* OUTSIDE the form, deliberately. `DialogActions` draws plain buttons, and a button
          inside a form with no explicit `type` submits it — so OK would run once on its own
          click and once again on the submit it caused. The form still owns Enter: pressing it
          in the filter submits, which is the same run. */}
      <div ref={footerRef} className="shrink-0">
        <DialogActions
          cancelLabel="Cancel"
          onCancel={onClose}
          confirmLabel="OK"
          onConfirm={() => run()}
          confirmDisabled={!picked}
          busy={busy}
          focusOnMount={false}
        />
      </div>
    </div>
  );
}
