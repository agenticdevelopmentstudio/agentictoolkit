import { describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import * as React from 'react';

import { useStackLevel } from '@agentic-toolkit/resource';

import type { DevRepo, Environment, RepoItem } from '../types';

/**
 * The Configure dialog's FRAME — the three things that are true of it before any of its
 * contents are: where the bar is, what the footer's two buttons commit, and that the forge
 * accounts are NOT in here.
 *
 * All three were reported as defects against a build that had none of them, and two of the
 * three are invisible to a type checker and to every other test in this package: a bar hung
 * inside the rail still renders, and a modal with no footer still closes. The only way either
 * fails loudly is a test that asks the DOM where things ended up.
 *
 * `IntegrationsPane` is stood in for because this file is about the frame, not the pane; what
 * the dialog it now lives in has to get right is pinned in `ConnectionsDialog.test.tsx`.
 */

vi.mock('@agentic-toolkit/data/ecosystems', () => ({
  useWorkspaceDefaultEcosystemId: () => ({
    ecosystemId: 'eco-1',
    canManage: true,
    isPending: false,
    isFetching: false,
    isError: false,
  }),
}));

// `IntegrationsPane` is stubbed — it is the whole integrations feature, and this file is about
// the frame around it — but `CONNECTIONS_HASH` is taken from the REAL module rather than spelled
// again here. It is the one string both ends of the OAuth round-trip have to agree on, and a
// fixture that declares its own would keep passing through exactly the divergence that breaks
// the return leg.
vi.mock('@agentic-toolkit/integrations', async (importOriginal) => ({
  CONNECTIONS_HASH: (
    await importOriginal<typeof import('@agentic-toolkit/integrations')>()
  ).CONNECTIONS_HASH,
  IntegrationsPane: ({ levelTitle }: { levelTitle?: string }) => {
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

const { ConfigureDialog } = await import('../configure/ConfigureDialog');

const DEV_REPO: DevRepo = {
  id: 'd1',
  slug: 'acme/site',
  mainBranch: 'main',
  preparedBranch: 'prepared',
  declarationSha: null,
  connectionId: 'c1',
};

function mirror(envBranches: Partial<Record<Environment, string>>): RepoItem {
  return {
    id: 'm1',
    devRepoId: DEV_REPO.id,
    groupId: null,
    slug: 'acme/site-deployment',
    shard: 'all',
    shipBranch: 'ship',
    ciContext: 'gate',
    envBranches,
    registeredAt: null,
    position: 0,
    devRepo: DEV_REPO,
    state: null,
  };
}

function draw(items: RepoItem[] = []) {
  const onClose = vi.fn();
  const onSaveSettings = vi.fn(() => Promise.resolve());
  const onImport = vi.fn(() => Promise.resolve());
  render(
    <ConfigureDialog
      open
      onClose={onClose}
      client={{ workspace: 'acme' } as never}
      groups={[]}
      items={items}
      verbs={['C', 'R', 'U', 'D', 'M']}
      onRegister={() => Promise.resolve()}
      onRemove={() => Promise.resolve()}
      onSaveSettings={onSaveSettings}
      onImport={onImport}
    />,
  );
  return { onClose, onSaveSettings, onImport };
}

/** The dialog with this title, of however many are open. */
const dialog = (title: string) =>
  screen
    .getAllByRole('dialog')
    .find((d) => within(d).queryByText(title, { selector: '[data-slot="dialog-title"]' }))!;

describe('the Configure dialog frame', () => {
  it('draws the bar above the rail, not inside its list', async () => {
    draw([mirror({})]);
    const add = await screen.findByRole('button', { name: 'Add' });
    // Measured against the breadcrumb, which is the FIRST thing the view draws: a bar hung
    // off the level as its `headerSlot` lands inside the list column, which is below it.
    // Anything that renders after the breadcrumb is inside the rail, not above it.
    const [breadcrumb] = screen.getAllByText('Repositories');
    expect(
      add.compareDocumentPosition(breadcrumb!) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
  });

  it('closes on Cancel without writing the boxes that were ticked', async () => {
    const { onClose, onSaveSettings } = draw([mirror({})]);
    await userEvent.click(await screen.findByText('acme/site'));
    await userEvent.click(await screen.findByRole('checkbox', { name: /testing/i }));
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(onSaveSettings).not.toHaveBeenCalled();
    expect(onClose).toHaveBeenCalled();
  });

  it('writes the boxes and closes on OK', async () => {
    const { onClose, onSaveSettings } = draw([mirror({ testing: 'release/next' })]);
    await userEvent.click(await screen.findByText('acme/site'));
    await userEvent.click(await screen.findByRole('checkbox', { name: /staging/i }));
    await userEvent.click(screen.getByRole('button', { name: 'OK' }));
    await waitFor(() => expect(onSaveSettings).toHaveBeenCalled());
    expect(onSaveSettings.mock.calls[0]![0]).toEqual([
      { repoId: 'm1', envBranches: { testing: 'release/next', staging: 'staging' } },
    ]);
    await waitFor(() => expect(onClose).toHaveBeenCalled());
  });

  it('leaves the repository settings one Save, not two', async () => {
    // The footer's OK IS the Save. An inline one beside it would be a second control writing
    // the same patch, and a second answer to "did that go through".
    draw([mirror({})]);
    await userEvent.click(await screen.findByText('acme/site'));
    await screen.findByRole('checkbox', { name: /testing/i });
    expect(screen.queryByRole('button', { name: /^Save/ })).toBeNull();
  });

  it('does not hold the forge accounts at all — they are a door of their own', async () => {
    // Integrations left this dialog. It was a button on the repository list's bar, two clicks
    // in and filed under the rows that depend on it, which made credentials owned by the
    // ECOSYSTEM read as a per-repository setting. It is on the toolbar now, and this dialog
    // has no way in — see `ConnectionsDialog.test.tsx` for what it opens.
    draw([mirror({})]);
    await screen.findByText('acme/site');
    expect(screen.queryByRole('button', { name: 'Connections' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Integrations' })).toBeNull();
  });
});

describe('the fleet as a file', () => {
  /**
   * A refused bar button SAYS SO WHEN PRESSED. It is `aria-disabled`, never natively
   * `disabled`: Chrome dispatches no hover over a disabled button and shows no `title`
   * tooltip for one, so the old contract — the reason on `title` — could only be read by
   * someone who already knew what it said. "The import button does nothing" (Mike) was
   * exactly that, on the sibling control.
   */
  it('says why when a refused bar button is pressed', async () => {
    const user = userEvent.setup();
    draw();
    const button = screen.getByRole('button', { name: 'Export' });
    expect(button).toHaveAttribute('aria-disabled', 'true');
    // Not `disabled` — that is what swallowed the press and the explanation with it.
    expect(button).not.toBeDisabled();

    await user.click(button);
    expect(await screen.findByText('Nothing is registered yet.')).toBeInTheDocument();
  });

  it('writes a file of the rows on the screen', async () => {
    // Every part of the export is stubbed except the one thing worth pinning here: that the
    // button reaches the file at all. What goes IN the file is `buildDocument`'s, and is
    // pinned against the CLI's own output in exchange.test.ts.
    const createObjectURL = vi.fn(() => 'blob:configure');
    const revokeObjectURL = vi.fn();
    Object.assign(URL, { createObjectURL, revokeObjectURL });
    const click = vi
      .spyOn(HTMLAnchorElement.prototype, 'click')
      .mockImplementation(() => {});

    draw([mirror({})]);
    await userEvent.click(screen.getByRole('button', { name: 'Export' }));

    expect(click).toHaveBeenCalled();
    expect(createObjectURL).toHaveBeenCalled();
    click.mockRestore();
  });

  it('opens the import dialog rather than importing anything on the press', async () => {
    const { onImport } = draw([mirror({})]);
    await userEvent.click(screen.getByRole('button', { name: 'Import' }));
    expect(await waitFor(() => dialog('Import configuration'))).toBeTruthy();
    // The bar button opens a plan; it never applies one.
    expect(onImport).not.toHaveBeenCalled();
  });
});
