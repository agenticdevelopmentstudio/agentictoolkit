import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import * as React from 'react';

import { useStackLevel } from '@agentic-toolkit/resource';

import { SHIPR_DIALOG_SURFACE } from '../dialogSurface';

/**
 * The Connections dialog — the forge accounts every run goes out over, opened from
 * Integrations on the far right of the toolbar.
 *
 * TWO things are pinned here, and both were reported as defects against a build that had
 * neither. The first is the POSITION the integrations pane is mounted in: the pane publishes
 * its list as a rail level one deeper than its host, and the "+" that adds an integration
 * belongs to that level. Inside Configure it was published under a repository list that was
 * not selected, and `HierarchicalDetailView` renders levels only as far as the first
 * unselected one — so the level carrying the only add button in the feature was sliced off
 * every single time, which is to say there was no way to connect a GitHub account at all.
 *
 * The second is the ADDRESS. This is the one dialog in the console an operator can leave the
 * app from, so it is the one whose open-ness lives in the URL. Neither fact is visible to a
 * type checker, and no other test in this package ever leaves the page.
 *
 * `IntegrationsPane` is stood in for, because what is being pinned is not the pane. The stub
 * publishes a rail level with an `onNew` exactly as the real one does, through the real
 * `useStackLevel` and the real rail host, so the button it asks for is drawn by the real
 * machinery or not at all.
 */

/** The resolution the dialog is handed. Reset before every test to the resolved answer; the
 *  failure cases below overwrite it. */
const RESOLVED = {
  ecosystemId: 'eco-1' as string | undefined,
  canManage: true,
  isPending: false,
  isFetching: false,
  isError: false,
  isLoadingError: false,
};
const resolution = vi.hoisted(() => ({ current: {} as Record<string, unknown> }));
beforeEach(() => {
  resolution.current = { ...RESOLVED };
});

vi.mock('@agentic-toolkit/data/ecosystems', () => ({
  useWorkspaceDefaultEcosystemId: () => resolution.current,
}));

// `CONNECTIONS_HASH` is taken from the REAL module rather than spelled again here. It is the
// one string both ends of the OAuth round-trip have to agree on, and a fixture that declared
// its own would keep passing through exactly the divergence that breaks the return leg.
/** What the dialog handed the pane on its last render — the narrowing props are the dialog's
 *  own decisions, and the stub is the only place they are observable. */
const paneProps: { providerIds?: readonly string[]; workspaceSlug?: string } & {
  [k: string]: unknown;
} = {};

vi.mock('@agentic-toolkit/integrations', async (importOriginal) => ({
  CONNECTIONS_HASH: (
    await importOriginal<typeof import('@agentic-toolkit/integrations')>()
  ).CONNECTIONS_HASH,
  IntegrationsPane: (props: {
    levelTitle?: string;
    providerIds?: readonly string[];
    workspaceSlug?: string;
  }) => {
    const { levelTitle, providerIds, workspaceSlug } = props;
    // The WHOLE prop object, so `'addFilter' in paneProps` can be asked below. Recording only
    // the props this stub names would answer "absent" for a prop the dialog still passes.
    Object.assign(paneProps, props);
    paneProps.providerIds = providerIds;
    paneProps.workspaceSlug = workspaceSlug;
    useStackLevel({
      id: 'integrations-list',
      title: levelTitle ?? 'Integrations',
      items: [],
      selectedId: null,
      onSelect: () => {},
      onClear: () => {},
      newLabel: 'Add integration',
      onNew: () => {},
    });
    return <div>integrations detail</div>;
  },
}));

const { ConnectionsDialog } = await import('../configure/ConnectionsDialog');

const PROPS = {
  onClose: () => {},
  client: { workspace: 'acme' } as never,
};

function draw() {
  const onClose = vi.fn();
  render(<ConnectionsDialog {...PROPS} open onClose={onClose} />);
  return { onClose };
}

/** The dialog with this title, of however many are open. */
const dialog = (title: string) =>
  screen
    .queryAllByRole('dialog')
    .find((d) => within(d).queryByText(title, { selector: '[data-slot="dialog-title"]' }));

describe('the Connections dialog frame', () => {
  it('draws the add button, because the pane is the first level of its own rail', async () => {
    draw();
    // The whole reason this is a dialog rather than a pane inside Configure: the integrations
    // level is the FIRST level of this dialog's own rail rather than an orphan under an
    // unselected repository list, so the "+" it publishes is inside the rendered frontier.
    expect(
      await screen.findByRole('button', { name: 'Add integration' }),
    ).toBeInTheDocument();
  });

  it('offers OK and nothing to cancel', async () => {
    // OK, not Done: it is the word every dialog in this console dismisses on, and a footer
    // that varies by dialog makes an operator read it to find the button that closes. There is
    // no Cancel because every write on this screen has already happened — the detail view owns
    // its own Save, and removing an integration confirms itself — so one would promise an undo
    // that does not exist.
    const { onClose } = draw();
    await userEvent.click(await screen.findByRole('button', { name: 'OK' }));
    expect(onClose).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('button', { name: 'Cancel' })).toBeNull();
  });

  it('offers only the forges it actually has, and pre-narrows nothing', async () => {
    draw();
    await screen.findByRole('button', { name: 'Add integration' });
    // `'railway'` was in this list and named NOTHING: the catalog has no railway entry, and
    // `providerIds` is intersected with the catalog, so the string was dropped on every render
    // in both directions — no row could list, no offer could appear. It read as support for a
    // forge this console has none of. Railway credentials reach a deploy through the
    // environment, not through an integration.
    expect(paneProps.providerIds).toEqual(['github-app', 'vercel']);
    // And NO starting filter — the prop is gone from the pane entirely. It used to be
    // `'Code'`, the catalog subtitle `github-app` carries and `vercel` does not, so the picker
    // for a two-forge dialog opened showing one of them with the other behind four characters
    // the operator had to notice and delete.
    expect('addFilter' in paneProps).toBe(false);
    // The workspace the bar's Transfer reads its destinations from. Without it the pane draws
    // no Transfer button at all, which is the right answer for a host that has no workspace and
    // the wrong one for this dialog, which has had the slug all along.
    expect(paneProps.workspaceSlug).toBe(PROPS.client.workspace);
    // And this dialog's own button floor. The pane's confirms and its picker render into a
    // PORTAL, so nothing this surface sets reaches them by inheritance — without the prop
    // they would be the one step in the flow with smaller buttons.
    expect(paneProps.dialogSurfaceClassName).toBe(SHIPR_DIALOG_SURFACE);
  });

  it('does not draw the pane while it is closed', () => {
    // The ecosystem resolution is a request and the rail host is a registry; a dialog stays
    // mounted when it closes, so the body is what has to go.
    render(<ConnectionsDialog {...PROPS} open={false} />);
    expect(screen.queryByText('integrations detail')).toBeNull();
    expect(dialog('Integrations')).toBeUndefined();
  });
});

// react-query's `isError` is also true when a background re-read fails behind an ecosystem
// already resolved. Gating on it swapped a working pane for "couldn't read" over a hiccup.
describe('a failed ecosystem resolution', () => {
  it('keeps the pane when a re-read fails behind the resolved ecosystem', async () => {
    resolution.current = { ...RESOLVED, isError: true, isLoadingError: false };
    draw();
    expect(await screen.findByText('integrations detail')).toBeInTheDocument();
    expect(screen.queryByText("Couldn't read this workspace's integrations.")).toBeNull();
  });

  it('says so when the first read failed with no answer', async () => {
    resolution.current = {
      ...RESOLVED,
      ecosystemId: undefined,
      isError: true,
      isLoadingError: true,
    };
    draw();
    expect(
      await screen.findByText("Couldn't read this workspace's integrations."),
    ).toBeInTheDocument();
    expect(screen.queryByText('integrations detail')).toBeNull();
  });
});

/**
 * Connections is the one modal in this console whose open-ness is in the URL, and the reason
 * is that it is the one an operator can LEAVE THE APP from. Connecting a GitHub App sends the
 * browser to github.com; `/integrations/oauth-callback` returns it to the URL the connect
 * started on. Every other dialog here is React state and can be, because nothing ever unmounts
 * the page beneath it — this one has to survive a document that was thrown away and rebuilt.
 *
 * Without the hash the operator came back to a bare tree with every dialog closed and their
 * new connection nowhere in sight, which reads as the connect having failed.
 */
describe('Connections is the one dialog the address bar knows about', () => {
  const at = (url: string) => window.history.replaceState(null, '', url);

  beforeEach(() => at('/acme/repos?workspace=acme'));
  afterEach(() => at('/'));

  it('writes the hash when it opens, leaving the path and query alone', async () => {
    draw();
    await waitFor(() => expect(window.location.hash).toBe('#connections'));
    // `?workspace=` is what the console reads its tree with, so a round-trip that dropped it
    // would come back to someone else's workspace — or to none.
    expect(window.location.pathname).toBe('/acme/repos');
    expect(window.location.search).toBe('?workspace=acme');
  });

  it('takes the hash back out when it closes', async () => {
    const { rerender } = render(<ConnectionsDialog {...PROPS} open />);
    await waitFor(() => expect(window.location.hash).toBe('#connections'));
    rerender(<ConnectionsDialog {...PROPS} open={false} />);
    await waitFor(() => expect(window.location.hash).toBe(''));
    expect(window.location.pathname).toBe('/acme/repos');
  });

  it('takes the hash back out when it is unmounted rather than closed', async () => {
    // The console tears this whole subtree down when it navigates away, and an unmount is not
    // a close — the effect that watches `open` never sees the change. A stale `#connections`
    // would reopen the dialog on the next load of a URL the operator had already left.
    const { unmount } = render(<ConnectionsDialog {...PROPS} open />);
    await waitFor(() => expect(window.location.hash).toBe('#connections'));
    unmount();
    await waitFor(() => expect(window.location.hash).toBe(''));
  });

  it("takes somebody else's fragment, and gives it back when it closes", async () => {
    // A fragment names a position within the page — an anchor a deep link aimed at, a scroll
    // target a shared URL carried — and this dialog wants the same slot. DECLINING to open
    // over one, which is what this did, looked like the conservative reading and was not: an
    // operator who arrived by a deep link got a Connections dialog whose GitHub round-trip
    // could never reopen it, because the address is the only carrier that survives the
    // document being thrown away and the branch that writes it had refused to run. So the
    // fragment is displaced and remembered rather than either overwritten or deferred to.
    at('/acme/repos?workspace=acme#pricing');
    const { rerender } = render(<ConnectionsDialog {...PROPS} open />);
    await waitFor(() => expect(window.location.hash).toBe('#connections'));
    // The path and query are untouched either way — `?workspace=` is what the tree is read
    // with, and only the fragment was ever this function's to claim.
    expect(window.location.search).toBe('?workspace=acme');

    rerender(<ConnectionsDialog {...PROPS} open={false} />);
    // Restored, not cleared: the deep link the operator followed is still where they left it.
    await waitFor(() => expect(window.location.hash).toBe('#pricing'));
  });

  it('hands Next a null history state, not the entry Next itself stamped', async () => {
    // Next patches `replaceState` and forwards any call whose state carries its `__NA` / `_N`
    // marker — which is every entry Next wrote, i.e. the one we would be reading back —
    // straight to the native implementation, skipping the router's own bookkeeping. The
    // fragment then never reaches `canonicalUrl`, and the next render that touches history
    // puts the old address back. `null` is the shape the patch is written for: it copies
    // Next's internal fields across itself and updates the router with the new URL.
    const spy = vi.spyOn(window.history, 'replaceState');
    try {
      draw();
      await waitFor(() => expect(window.location.hash).toBe('#connections'));
      const wroteTheHash = spy.mock.calls.find(([, , url]) =>
        String(url).endsWith('#connections'),
      );
      expect(wroteTheHash).toBeTruthy();
      expect(wroteTheHash![0]).toBeNull();
    } finally {
      spy.mockRestore();
    }
  });
});
