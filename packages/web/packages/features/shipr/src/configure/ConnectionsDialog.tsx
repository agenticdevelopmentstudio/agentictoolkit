'use client';

import * as React from 'react';

import { useWorkspaceDefaultEcosystemId } from '@agentic-toolkit/data/ecosystems';
import { CONNECTIONS_HASH, IntegrationsPane } from '@agentic-toolkit/integrations';
import { StandaloneRailHost } from '@agentic-toolkit/resource';
import { Button } from '@agenticdevelopertoolkit/ui/components/button';
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@agenticdevelopertoolkit/ui/components/dialog';
import { EmptyState } from '@agenticdevelopertoolkit/ui/components/empty-state';

import type { ShiprClient } from '../client';

/**
 * The forge credentials every run goes out over — {@link IntegrationsPane}, scoped to this
 * workspace's own infrastructure ecosystem.
 *
 * A DIALOG OF ITS OWN, and this is the whole reason the file exists. It was a pane inside
 * Configure, opened by a button on the repository list's bar, and in that shape the "Add
 * integration" button could not be drawn AT ALL — which is to say there was no way to
 * connect a GitHub account from this console.
 *
 * OPENED FROM THE TOOLBAR NOW, not from inside Configure. The console mounts it beside
 * Configure rather than under it, and `Integrations` on the far right of the bar is the only
 * way in. Being reachable only from Configure's bar made it look like a setting on the
 * repository list, and it is the opposite of that: the list is per-workspace, these accounts
 * belong to the ecosystem and every workspace on it runs out over them. It is also one modal
 * shallower for it, which is what lets it own the address itself — see `syncConnectionsHash`.
 *
 * `IntegrationsPane` renders only a detail and publishes its list as a rail level, one
 * deeper than whatever is hosting it, and the "+" that adds an integration is that level's.
 * Inside Configure it was published under the repository list — a level that is NOT selected
 * while Connections is showing, because Connections is a sibling of a repository's settings
 * and not a repository. `HierarchicalDetailView` renders levels up to the first UNSELECTED
 * one and slices the rest (`levels.slice(0, frontier + 1)`), so the integrations level, and
 * with it the only add button in the feature, was cut off every single time.
 *
 * Nested one modal deeper it is the rail's FIRST level rather than an orphaned second, which
 * is the same position it holds on the Integrations site. Registering already opens a dialog
 * over this one, and the operator arrives here from that wizard as often as from the bar.
 */

/**
 * The forges a deployment pipeline can actually reach. The whole catalog would offer an
 * operator a Stripe key on a screen about pushing branches.
 *
 * `'railway'` USED TO BE IN THIS LIST AND NAMED NOTHING. The provider catalog has no `railway`
 * entry, and `providerIds` is intersected with the catalog — so the string was silently dropped
 * on every render, in both directions: no Railway row could ever list here, and no Railway offer
 * could ever appear under Add. It looked like support for a forge this console has none of.
 * Deleting it does not remove a capability; it stops advertising one. Railway credentials reach
 * a deploy through the environment today, not through an integration.
 */
const PROVIDERS = ['github-app', 'vercel'] as const;

/**
 * The picker opens on the forges rather than on the alphabet.
 *
 * `'Code'` is a provider SUBTITLE, which is what the catalog uses for the coarse "what kind of
 * service is this" bucket — `github-app` is `Code`, `vercel` is `Deployment`. Typed into the
 * filter box, visible, and clearable: an operator who wants to see everything this dialog offers
 * deletes four characters. The narrowing that is NOT the operator's to undo is `PROVIDERS`
 * above, and it is a different mechanism for that reason.
 */
const ADD_FILTER = 'Code';

/**
 * THE ONE PIECE OF CONSOLE STATE THAT IS IN THE URL, and the reason is that this dialog is
 * the only place in the console an operator can LEAVE THE APP from and come back.
 *
 * Connecting a GitHub App sends the browser to github.com and the provider returns it to
 * `/integrations/oauth-callback`, which navigates on to `returnTo` — the full URL the connect
 * started on, captured by `currentReturnTo()`. Every other modal here is React state and can
 * be, because nothing ever unmounts the page under it. This one has to survive a document
 * that was thrown away and rebuilt, so the only carrier is the address bar.
 *
 * A hash rather than a query parameter: it is a position within this page, it never reaches
 * the server, and it cannot collide with `?workspace=`, which the console reads its tree
 * with and which must survive the round-trip unchanged.
 *
 * Written with `replaceState`, not `pushState`. Opening a dialog is not a navigation, and a
 * Back button that closed a dialog instead of leaving the console would be a worse lie than
 * a URL that is one step behind.
 *
 * The STRING itself is `@agentic-toolkit/integrations`', IMPORTED rather than spelled again
 * here. Both ends of the round-trip need the same fragment — this file puts it in the address,
 * and the callback appends it to the return it has to invent when nothing was stashed on the
 * origin it landed on — and a second spelling would be wrong in exactly one direction, with
 * nothing to catch it.
 */

/** True when the current address names {@link CONNECTIONS_HASH}. Guarded for SSR: this file
 *  is `'use client'`, but a client component still renders once on the server. */
export function connectionsHashPresent(): boolean {
  return typeof window !== 'undefined' && window.location.hash === CONNECTIONS_HASH;
}

/**
 * The fragment this dialog displaced when it opened over one, so closing PUTS IT BACK instead
 * of throwing it away.
 *
 * Module scope rather than React state, for the same reason the fragment is in the URL at all:
 * the thing it describes is the address, of which there is exactly one, and it has to outlive
 * a dialog body that unmounts every time it closes. It does NOT outlive the document, and so
 * is deliberately not consulted on the return leg from a provider — that arrival has
 * `#connections` in the address and nothing else, which is the whole point of putting it there.
 */
let displacedHash: string | null = null;

/** Put the address in agreement with whether Connections is showing, without adding history
 *  entries and without disturbing the path or the query. */
export function syncConnectionsHash(open: boolean): void {
  if (typeof window === 'undefined') return;
  const { pathname, search, hash } = window.location;
  const ours = hash === CONNECTIONS_HASH;
  if (open === ours) return;
  // Opening over SOMEBODY ELSE'S fragment REMEMBERS it and takes the address anyway.
  // Declining instead — which is what this did — was a trade that looked conservative and was
  // not: an operator who arrived by a deep link to an anchor got a Connections dialog whose
  // GitHub round-trip could never reopen it, because the one carrier that survives a document
  // being thrown away and rebuilt is the address, and this branch had refused to write it.
  // Both fragments are kept instead — ours while the dialog is up, theirs again when it closes.
  //
  // The closing direction needs no guard of its own: a foreign hash and `open === false` agree
  // above and return before reaching here, so the only hash ever REPLACED here is ours.
  if (open) displacedHash = hash || null;
  const next = open
    ? `${pathname}${search}${CONNECTIONS_HASH}`
    : `${pathname}${search}${displacedHash ?? ''}`;
  if (!open) displacedHash = null;
  // `null`, NOT `window.history.state`. Next patches `replaceState` and forwards any call
  // whose state carries its `__NA` / `_N` marker straight to the native implementation —
  // which is every entry Next itself stamped, i.e. this one. Handing back the state we just
  // read therefore skips the router's own bookkeeping, so `canonicalUrl` never learns about
  // the fragment and the next render that touches history puts the old address back. Passing
  // `null` is the shape the patch is written for: it copies Next's internal fields across
  // itself (`copyNextJsInternalHistoryState`) and updates the router with the new URL.
  window.history.replaceState(null, '', next);
}

export interface ConnectionsDialogProps {
  open: boolean;
  onClose: () => void;
  /** Read for its workspace slug, which is the same `?workspace=` the console reads its tree
   *  with. Nothing here calls it — the pane owns its own requests. */
  client: ShiprClient;
  /** A connection was added, removed or re-credentialed, so whoever holds a list of them
   *  should read it again. */
  onChanged?: () => void;
}

export function ConnectionsDialog({
  open,
  onClose,
  client,
  onChanged,
}: ConnectionsDialogProps): React.ReactElement {
  /* THE ADDRESS IS THIS DIALOG'S OWN, now that nothing wraps it. Configure used to run this
     effect on the dialog's behalf, because Configure was what the console reopened on the
     return leg and this was a child of it — so the hash had to be written by whoever was
     guaranteed to be mounted. It is opened straight from the toolbar now, so the component
     whose `open` the fragment describes is the one that writes it.

     NOTHING IS WRITTEN UNTIL IT HAS BEEN OPEN ONCE, and that guard is the whole difference
     between this and its old life inside Configure. Configure mounted this only while it was
     itself open; the console mounts it always, closed, beside every other dialog. So on the
     return leg from GitHub the first thing to run was this effect with `open === false`
     against an address that said `#connections` — child effects run before the parent's —
     and it dutifully took the fragment back OUT before the console had read it. The operator
     came back from a successful connect to a bare tree, which is the exact failure the hash
     exists to prevent. A dialog that has never been open has no opinion about the address. */
  const everOpened = React.useRef(false);
  React.useEffect(() => {
    if (open) everOpened.current = true;
    if (everOpened.current) syncConnectionsHash(open);
  }, [open]);
  /* An unmount is not a close, and the address does not know the difference. The console
     tears this whole subtree down when it navigates away, and a `#connections` left behind
     would reopen the dialog on the next load of a URL the operator had already left. */
  React.useEffect(() => () => {
    if (everOpened.current) syncConnectionsHash(false);
  }, []);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent className="flex h-[80vh] max-w-5xl flex-col gap-4">
        <DialogHeader>
          <DialogTitle>Connections</DialogTitle>
        </DialogHeader>
        <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden rounded border border-apt-border">
          {/* Mounted only while open, like Configure's own body: the ecosystem resolution is
              a request and the rail host is a registry, and a dialog stays mounted when it
              closes. */}
          {open ? <ConnectionsBody client={client} onChanged={onChanged} /> : null}
        </div>
        {/* ONE button, and it says Done rather than OK. Every write on this screen has already
            happened — the detail view owns its own Save, and removing an integration confirms
            itself — so there is nothing here for a Cancel to abandon, and offering one would
            promise an undo that does not exist. */}
        <DialogFooter>
          <Button type="button" onClick={onClose}>
            Done
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/**
 * The resolution gate in front of the pane.
 *
 * `isPending` is what separates "still asking" from "asked, and there is no infrastructure
 * ecosystem": mounting the pane on the first would show an empty list that fills in
 * silently, and refusing on it would tell an operator there is nothing set up while the
 * answer was still in flight. The pane's own `ecosystemId` is optional and falls back to
 * `""` inside it, which reads to every route as "no such ecosystem" — so a falsy check
 * inside the pane cannot tell those two apart, and the gate belongs out here.
 *
 * The host is mounted only on the branch that has a pane to put in it. A rail host with no
 * levels is a rail with no columns.
 */
function ConnectionsBody({
  client,
  onChanged,
}: {
  client: ShiprClient;
  onChanged?: () => void;
}): React.ReactElement {
  const { ecosystemId, isPending, isError } = useWorkspaceDefaultEcosystemId(
    client.workspace,
  );

  if (isPending) return <Notice title="Loading…" />;
  if (isError) {
    return (
      <Notice
        title="Couldn't read this workspace's integrations."
        description="Forge credentials are stored against the workspace's infrastructure ecosystem, and this console could not look it up. Nothing is lost — try again, or open Integrations on the hub."
      />
    );
  }
  if (!ecosystemId) {
    return (
      <Notice
        title="This workspace has no infrastructure ecosystem."
        description="Forge credentials are stored against the workspace's infrastructure ecosystem. Until one exists there is nowhere to put them, and every run will fail to reach the forge."
      />
    );
  }
  return (
    <StandaloneRailHost>
      <IntegrationsPane
        ecosystemId={ecosystemId}
        providerIds={PROVIDERS}
        addFilter={ADD_FILTER}
        levelTitle="Connections"
        onChanged={onChanged}
      />
    </StandaloneRailHost>
  );
}

function Notice({
  title,
  description,
}: {
  title: string;
  description?: string;
}): React.ReactElement {
  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-y-auto px-6 py-4">
      <EmptyState title={title} description={description} />
    </div>
  );
}
