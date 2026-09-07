'use client';

import * as React from 'react';

import { Button } from '@agenticdevelopertoolkit/ui/components/button';
import { Checkbox } from '@agenticdevelopertoolkit/ui/components/checkbox';
import { DialogActions } from '@agenticdevelopertoolkit/ui/components/dialog-actions';
import { ErrorText } from '@agenticdevelopertoolkit/ui/components/error-text';
import { Input } from '@agenticdevelopertoolkit/ui/components/input';
import { List, ListItem } from '@agenticdevelopertoolkit/ui/components/list';
import { Select } from '@agenticdevelopertoolkit/ui/components/select';

import type { ForgeRepository, RegisterRequest } from '../types';
import type { ForgeCatalogue } from '../forge/useForgeCatalogue';
import { useSubmit } from './dialogs';

/**
 * ADD: TICK THE REPOSITORIES, PRESS OK. One screen, one question, any number of answers.
 *
 * It was three steps and seven fields, then two screens and two — an installation to choose,
 * a folder, a main branch, a prepared branch, a deployment owner and name, a confirmation of
 * all of it — asked of an operator whose actual intent was "add these repos". Every one of
 * those has a right answer that is derivable here, on the server, or LATER, and asking anyway
 * is how a two-click job became a form.
 *
 * THE DEPLOYMENT REPOSITORY IS NOT ASKED HERE ANY MORE, and that is the whole change. It used
 * to be a second screen, because getting it wrong produced
 * `POST /orgs/DeploymentRepos/repos — 403: Resource not accessible by integration` minutes
 * into a run. The fix was a screen that asked before queueing; the better fix is not to queue.
 * Add now WRITES THE CONFIGURATION DOWN AND CREATES NOTHING — `registeredAt` stays null, no
 * run is started, and the org, the name and the environments are set afterwards in the
 * repository's own details pane, where they can be read, corrected, and checked against what
 * the forge actually holds before the operator presses Provision. So the question that needed
 * a screen of its own is now asked on a surface that can also answer it, and Add is one list.
 *
 * That is also what makes MULTIPLE SELECTION possible at all: a per-repository deployment
 * form cannot be filled in for eleven repositories at once, and eleven repositories is the
 * ordinary case when a fleet is first pointed at shipr. Ticking eleven boxes writes eleven
 * rows and touches no forge.
 *
 * THE LIST IS NOT READ HERE EITHER. It comes from {@link ForgeCatalogue}, held at the console
 * so it is prefetched when the site comes up and survives this dialog closing — see that
 * file's header for the three failures the move fixes, one of which was an installation
 * silently missing from this very menu.
 *
 * NOTHING HERE IS DRAWN BY HAND. The org menu is `Select`, the filter is `Input`, the rows are
 * `List`/`ListItem` and `Checkbox`, and the two buttons are `DialogActions` — the same
 * vocabulary every other dialog in this console is built from. The two-column owner/repository
 * browser that used to live here reimplemented all four badly.
 *
 * The keyboard is the point of the layout: the filter takes focus on open and KEEPS it, so
 * filter, tick, filter, tick runs without a reach for the mouse and Enter commits the whole
 * set. Focus does not chase the first tick to OK — it did when there was one answer to give,
 * and with several to give it ate the second. Escape is caught HERE — this is not a modal, it
 * renders inside the Configure dialog's pane, and an uncaught Escape would close that dialog
 * out from under it.
 *
 * What is still deliberately absent is a picker of repositories we hold no token for. GitHub's
 * own installation page is where the GRANT is made, so the empty state points at Integrations
 * rather than at a search box: the filter narrows what was granted, it never reaches past it.
 */

/** `owner/name` → `name`. The wire guarantees the shape, so this is a split, not a parse. */
function nameOf(slug: string): string {
  return slug.slice(slug.indexOf('/') + 1);
}

export interface RegisterWizardProps {
  open: boolean;
  onClose: () => void;
  /**
   * Every account and every repository, read once above this dialog.
   *
   * A prop rather than a hook call, so this screen makes NO request of its own: the whole
   * reason the catalogue exists is that reading it per-opening was the bug.
   */
  catalogue: ForgeCatalogue;
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
  /**
   * ONE CALL FOR THE WHOLE SET, not one per repository.
   *
   * The caller writes them, refreshes once, and reports one failure — a loop out here would
   * refresh the tree eleven times and leave a half-added set behind whichever one threw.
   */
  onSubmit: (bodies: readonly RegisterRequest[]) => Promise<void>;
}

export function RegisterWizard({
  open,
  onClose,
  catalogue,
  registeredSlugs,
  onManageConnections,
  onSubmit,
}: RegisterWizardProps): React.ReactElement | null {
  /** THE ONE ANSWER THIS SCREEN COLLECTS, by slug. A set and not an array: ticking is a
   *  membership question, and the order boxes were ticked in means nothing to the request. */
  const [checked, setChecked] = React.useState<ReadonlySet<string>>(() => new Set());
  /** WHICH ACCOUNT'S REPOSITORIES ARE LISTED, as a CONNECTION ID and not as a login.
   *
   *  An installation is what this screen actually picks between — one installation is one
   *  account — and it is the only identifier every account has: a connection whose forge login
   *  shipr has not read back has `login: null` (see `ForgeOrg.login`), and keying on the login
   *  would have dropped exactly the account this menu promises below to keep in place. Nothing
   *  here composes a slug from it, so nothing here needs the login at all: the requests are
   *  built from the ticked repositories' own slugs. */
  const [accountId, setAccountId] = React.useState('');
  const [filter, setFilter] = React.useState('');

  const filterRef = React.useRef<HTMLInputElement>(null);

  // Re-seeded on OPEN, not on mount: the host may keep this mounted while closed, and a second
  // Add must not start on the answers of the first.
  React.useEffect(() => {
    if (!open) return;
    setChecked(new Set());
    setAccountId('');
    setFilter('');
  }, [open]);

  const registered = React.useMemo(
    () => new Set(registeredSlugs ?? []),
    [registeredSlugs],
  );

  const orgs = catalogue.orgs;

  /** The menu's value, resolved rather than stored: the catalogue arrives after the first
   *  paint and can change again under a refresh, so an account held in state would name one
   *  that is no longer there and show an empty list under a menu that looks answered. */
  const accountIds = React.useMemo(
    () => (orgs ?? []).map((o) => o.connectionId),
    [orgs],
  );
  const activeId = accountIds.includes(accountId) ? accountId : (accountIds[0] ?? '');
  const activeOrg = (orgs ?? []).find((o) => o.connectionId === activeId) ?? null;
  /** What the open account is CALLED, for the sentences below — its login where shipr knows
   *  it, and the connection's own label where it does not. */
  const activeName = activeOrg ? (activeOrg.login ?? activeOrg.label) : '';

  /** That org's repositories, narrowed by the filter. The filter matches the WHOLE slug, so
   *  the `acme/site` an operator would have typed into the free-text field this replaced still
   *  works, and so does the bare name. */
  const shown = React.useMemo(() => {
    const needle = filter.trim().toLowerCase();
    return (activeOrg?.repositories ?? []).filter(
      (r) => needle === '' || r.slug.toLowerCase().includes(needle),
    );
  }, [activeOrg, filter]);

  const toggle = React.useCallback((repo: ForgeRepository, on: boolean) => {
    setChecked((prev) => {
      const next = new Set(prev);
      if (on) next.add(repo.slug);
      else next.delete(repo.slug);
      return next;
    });
  }, []);

  /**
   * The requests, one per ticked repository — built from the catalogue, asked of nobody.
   *
   * `connectionId` is derived from the pick and never asked for: the run needs an installation
   * that can actually reach this repository, and the catalogue knows which one that is because
   * the repository came out of its grant. `mainBranch` is the forge's own `defaultBranch` — a
   * repo whose default is `master` or `trunk` registered against `main` fails at the first
   * status run. Nothing about the DEPLOYMENT repository is sent: this call configures, and the
   * server fills the mirror from the org's defaults, which the details pane then shows.
   */
  const bodies = React.useMemo<RegisterRequest[]>(() => {
    const bySlug = new Map<string, ForgeRepository>();
    for (const org of orgs ?? []) {
      for (const repo of org.repositories) bySlug.set(repo.slug, repo);
    }
    return [...checked].sort().map((slug) => {
      const repo = bySlug.get(slug);
      const connectionId = catalogue.connectionOf(slug);
      return {
        slug,
        ...(connectionId ? { connectionId } : {}),
        ...(repo?.defaultBranch ? { mainBranch: repo.defaultBranch } : {}),
      };
    });
  }, [checked, orgs, catalogue]);

  const submit = React.useCallback(() => onSubmit(bodies), [onSubmit, bodies]);
  const { busy, error, run } = useSubmit(submit, onClose);

  // The filter takes focus when the screen opens — it is the only thing here anyone types into,
  // and landing focus on OK (which is disabled until something is ticked) or on Cancel would be
  // a keyboard that starts pointed at the exit. It KEEPS focus after that: with several answers
  // to give, focus chasing the first one to OK ate the second.
  React.useEffect(() => {
    if (open) filterRef.current?.focus();
  }, [open]);

  /**
   * ONE empty box, four causes, four sentences.
   *
   * They share a shape — no repositories — and share nothing else, and for a while they shared
   * one sentence too: "No GitHub App installation". That sentence is a guess in three of the
   * four cases and flatly wrong in one, and the wrong one is the expensive one: it sends an
   * operator to GitHub to install an app they have already installed, over a read that simply
   * failed.
   */
  const emptySentence =
    catalogue.error != null
      ? `Your integrations could not be read: ${catalogue.error}`
      : activeOrg?.error != null
        ? `${activeName}'s repositories could not be read: ${activeOrg.error}`
        : orgs !== undefined && orgs.length === 0
          ? 'No GitHub App installation is connected yet — open Integrations to add one.'
          : `shipr's GitHub App hasn't been granted any repositories on ${activeName} yet — open Integrations and press Test.`;

  // Unmounted rather than hidden while closed, so the host's pane holds the repository list
  // and nothing else. The reset effect above still keys on `open` — a host that keeps this
  // mounted across opens gets the same fresh start a remount gives.
  if (!open) return null;

  const reading = orgs === undefined || (activeOrg?.loading ?? false);

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
      {/* NOT A FORM, because the Enter this screen owes the operator is not one a form
          reliably gives it. Implicit submission — a form with no submit button in it — fires
          only when exactly one field blocks it, and each row's Checkbox renders a hidden
          `input[type=checkbox]`, so what Enter does here would be decided by how many
          repositories happen to be listed and by which engine is reading the rule. Enter is
          handled where it is pressed instead, in the filter, and there is one path to `run()`
          rather than two that have to agree. */}
      <div className="flex min-h-0 min-w-0 flex-1 flex-col gap-3">
        <Select
          aria-label="Organization"
          value={activeId}
          disabled={accountIds.length === 0}
          onChange={(e) => setAccountId(e.target.value)}
        >
          {/* EVERY account, including one whose read failed — that org keeps its place in the
              menu and says why underneath, which is the difference between an installation
              that is missing and an installation nobody can see is missing.

              AND INCLUDING ONE SHIPR CANNOT NAME, which is why the value is the connection id
              and the text is `login ?? label`. Keyed on the login, an account whose
              `accountLogin` has not been read back would have had no value to carry and would
              have fallen out of the menu — the same disappearance this comment exists to
              forbid, arriving by a different route. */}
          {(orgs ?? []).map((org) => (
            <option key={org.connectionId} value={org.connectionId}>
              {org.login ?? org.label}
            </option>
          ))}
        </Select>

        <Input
          ref={filterRef}
          aria-label="Filter repositories"
          placeholder="Filter repositories"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          onKeyDown={(e: React.KeyboardEvent) => {
            // Enter is OK, and only once something is ticked — the same guard the button
            // carries, because they are the same press.
            if (e.key !== 'Enter') return;
            e.preventDefault();
            if (checked.size === 0 || busy) return;
            run();
          }}
        />

        {reading ? (
          <p className="min-h-0 flex-1 text-sm text-apt-text-muted">Reading your repositories…</p>
        ) : (activeOrg?.repositories.length ?? 0) === 0 ? (
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
              const on = checked.has(repo.slug);
              return (
                <ListItem key={repo.slug} className="p-0">
                  {/* A LABEL, so the whole row toggles: `button` is a labelable element, and
                      the shared Checkbox renders one, so the text is part of the control
                      rather than a second thing to aim at. */}
                  <label
                    // THE NAME GOES ON THE LABEL, and on the box below it, because base-ui
                    // points the box's `aria-labelledby` at this element — and labelledby
                    // outranks the box's own `aria-label`, then swallows it again as part of
                    // this element's text. Named only on the box, the row announced itself as
                    // "acme/site site". Named in both places, whichever the reader resolves
                    // gives the same sentence.
                    aria-label={already ? `${repo.slug} — already registered` : repo.slug}
                    className={[
                      'flex w-full items-center gap-3 px-3 py-1.5 text-left text-sm',
                      already
                        ? 'cursor-not-allowed text-apt-text-muted'
                        : on
                          ? 'cursor-pointer bg-apt-gold/15 text-apt-text'
                          : 'cursor-pointer text-apt-text hover:bg-apt-border/40',
                    ].join(' ')}
                  >
                    <Checkbox
                      // ADDRESSED by the whole slug, which is the thing that identifies a
                      // repository; the row SHOWS the name, because the owner is the menu
                      // above and repeating it on every row is what made the old flat column
                      // unreadable.
                      aria-label={already ? `${repo.slug} — already registered` : repo.slug}
                      checked={on}
                      disabled={already}
                      onCheckedChange={(next: boolean) => toggle(repo, next)}
                    />
                    <span className="truncate">{nameOf(repo.slug)}</span>
                    {already ? (
                      <span className="ml-auto shrink-0 text-xs text-apt-text-muted">
                        Registered
                      </span>
                    ) : null}
                  </label>
                </ListItem>
              );
            })}
          </List>
        )}

        {/* Both are said, and neither suppresses the other: a list read an hour ago is a list
            you can pick from, and the reason it is old is still worth a line. */}
        {activeOrg?.error != null && activeOrg.repositories.length > 0 ? (
          <p className="text-xs text-apt-text-muted">
            Showing the stored list — {activeOrg.error}
          </p>
        ) : null}

        <ErrorText error={error} />
      </div>

      {/* The footer is pinned, and the list above it scrolls. A modal's buttons sit on its
          bottom edge (Mike) — a footer that scrolls away with a long list is a dialog whose
          OK the operator has to go looking for. */}
      <div className="shrink-0">
        {/* OK and Cancel are the whole vocabulary here — a third control (Back, Next, Skip)
            would be the thing this screen was asked twice not to grow. OK writes every ticked
            repository into the configuration and creates nothing; Cancel closes the picker,
            which is also what Escape does. */}
        <DialogActions
          cancelLabel="Cancel"
          onCancel={onClose}
          confirmLabel={checked.size > 1 ? `Add ${checked.size}` : 'OK'}
          onConfirm={run}
          confirmDisabled={checked.size === 0}
          busy={busy}
          focusOnMount={false}
        />
      </div>
    </div>
  );
}
