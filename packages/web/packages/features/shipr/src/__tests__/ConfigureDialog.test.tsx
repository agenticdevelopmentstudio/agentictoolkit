import { describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import * as React from 'react';

import { useStackLevel } from '@agentic-toolkit/resource';

import type { AccessVerb, DevRepo, Environment, RepoItem } from '../types';
import type { ForgeCatalogue } from '../forge/useForgeCatalogue';
import type { RepoSettingsPatch } from '../settings/SettingsDialog';

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
  displayName: null,
  mainBranch: 'main',
  preparedBranch: 'prepared',
  declarationSha: null,
  connectionId: 'c1',
};

/**
 * The forge, already read.
 *
 * It is a PROP here rather than something this dialog fetches, and that is the whole point of
 * the shape: the console reads the accounts once when it comes up, so every opening of this
 * dialog — and the Add picker inside it — draws from a list that is already on hand. A test
 * that stubbed a client method instead would be testing a read this screen no longer does.
 */
function catalogueOf(over: Partial<ForgeCatalogue> = {}): ForgeCatalogue {
  return {
    orgs: [
      {
        login: 'acme',
        connectionId: 'c1',
        repositories: [{ slug: 'acme/site', defaultBranch: 'main', private: false }],
        error: null,
        loading: false,
      },
    ],
    error: null,
    loading: false,
    connectionOf: (slug: string) => (slug.startsWith('acme/') ? 'c1' : undefined),
    installedOn: (login: string) => login === 'acme',
    refresh: () => {},
    ...over,
  };
}

/** The client this dialog still touches. Only `orgDefaults` is read — the gear menu's stored
 *  answer — and it is stubbed empty because none of these tests is about what is in it. */
const CLIENT = {
  workspace: 'acme',
  orgDefaults: () => Promise.resolve({ orgDefaults: [] }),
} as never;

function mirror(
  envBranches: Partial<Record<Environment, string>>,
  over: Partial<RepoItem> = {},
): RepoItem {
  return {
    id: 'm1',
    devRepoId: DEV_REPO.id,
    groupId: null,
    slug: 'acme/site-deployment',
    shard: 'all',
    shipBranch: 'ship',
    ciContext: 'gate',
    envBranches,
    // ADDED, NOT MADE — what Add now leaves behind, and the default here because it is the
    // state every row passes through. A row that has been provisioned says so with a date.
    registeredAt: null,
    position: 0,
    devRepo: DEV_REPO,
    state: null,
    ...over,
  };
}

/** A second source repository, in an account of its own, so the root level has two rows. */
const OTHER_REPO: DevRepo = {
  ...DEV_REPO,
  id: 'd2',
  slug: 'sandbox/toys',
  connectionId: 'c2',
};

function otherMirror(over: Partial<RepoItem> = {}): RepoItem {
  return {
    ...mirror({}),
    id: 'm2',
    devRepoId: OTHER_REPO.id,
    slug: 'sandbox/toys-deployment',
    devRepo: OTHER_REPO,
    registeredAt: '2026-09-01T00:00:00.000Z',
    ...over,
  };
}

function draw(items: RepoItem[] = [], over: Partial<React.ComponentProps<typeof ConfigureDialog>> = {}) {
  const onClose = vi.fn();
  // Typed rather than bare, so `mock.calls[0][0]` below is the patch list and not an
  // out-of-range index into an empty tuple.
  const onSaveSettings = vi.fn((_patches: RepoSettingsPatch[]) => Promise.resolve());
  const onImport = vi.fn(() => Promise.resolve());
  render(
    <ConfigureDialog
      open
      onClose={onClose}
      client={CLIENT}
      catalogue={catalogueOf()}
      groups={[]}
      items={items}
      verbs={['C', 'R', 'U', 'D', 'M']}
      onRegister={() => Promise.resolve()}
      onRemove={() => Promise.resolve()}
      onSaveSettings={onSaveSettings}
      onImport={onImport}
      {...over}
    />,
  );
  return { onClose, onSaveSettings, onImport };
}

/**
 * Open a repository — TWO clicks, because the root level is the accounts.
 *
 * The rail's first column is the organizations the fleet is registered from and the second is
 * that account's repositories, so nothing about a repository is reachable without saying which
 * account it is in. Named here rather than spelled out per test so that the shape of the walk
 * is stated once.
 */
async function openRepo(name = 'site') {
  await userEvent.click(await screen.findByText('acme'));
  await userEvent.click(await screen.findByText(name));
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
    const [breadcrumb] = screen.getAllByText('Organizations');
    expect(
      add.compareDocumentPosition(breadcrumb!) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
  });

  it('closes on Cancel without writing the boxes that were ticked', async () => {
    const { onClose, onSaveSettings } = draw([mirror({})]);
    await openRepo();
    await userEvent.click(await screen.findByRole('checkbox', { name: /testing/i }));
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(onSaveSettings).not.toHaveBeenCalled();
    expect(onClose).toHaveBeenCalled();
  });

  it('writes the boxes and closes on OK', async () => {
    const { onClose, onSaveSettings } = draw([mirror({ testing: 'release/next' })]);
    await openRepo();
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
    await openRepo();
    await screen.findByRole('checkbox', { name: /testing/i });
    expect(screen.queryByRole('button', { name: /^Save/ })).toBeNull();
  });

  it('does not hold the forge accounts at all — they are a door of their own', async () => {
    // Integrations left this dialog. It was a button on the repository list's bar, two clicks
    // in and filed under the rows that depend on it, which made credentials owned by the
    // ECOSYSTEM read as a per-repository setting. It is on the toolbar now, and this dialog
    // has no way in — see `ConnectionsDialog.test.tsx` for what it opens.
    draw([mirror({})]);
    await screen.findByText('acme');
    expect(screen.queryByRole('button', { name: 'Connections' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Integrations' })).toBeNull();
  });
});

/**
 * ACCOUNT, THEN REPOSITORY — and a mark on anything that was added but never made.
 *
 * The rail used to be one flat list of `owner/name` rows, which is the shape that produced
 * `POST /orgs/DeploymentRepos/repos — 403`: the account a repository lives in was a prefix on
 * a label rather than a thing on the screen, so nothing ever asked which one. It is a level of
 * its own now, and the column under it says `site` rather than `acme/site` because that column
 * IS `acme` — the same name twice is the flat list wearing a breadcrumb.
 *
 * The mark is the other half. Add writes a row and stops (see the note at the top of
 * `ConfigureDialog`), so "configured" and "provisioned" are now different states, and a screen
 * that cannot tell them apart is a screen that lets an operator wait forever for a deployment
 * repository nobody ever asked the forge to create.
 */
describe('the repository rail', () => {
  it('opens on the accounts, and names each repository without repeating its account', async () => {
    draw([mirror({}), otherMirror()]);

    // The ROOT level is the accounts. Not a filter over one list — a level, so a fleet spread
    // across four organizations is four folders rather than four prefixes.
    const acme = await screen.findByText('acme');
    expect(screen.getByText('sandbox')).toBeInTheDocument();
    // And no repository is on it: `site` is behind `acme`, not beside it.
    expect(screen.queryByText('site')).toBeNull();

    await userEvent.click(acme);

    expect(await screen.findByText('site')).toBeInTheDocument();
    // WITHOUT THE ACCOUNT IN IT — the column is already `acme`.
    expect(screen.queryByText('acme/site')).toBeNull();
    // The other account's repository is not in this column; it is behind `sandbox`.
    expect(screen.queryByText('toys')).toBeNull();
  });

  it('marks what was added but never made, on the row AND on the account above it', async () => {
    // `data-blocked` is the rail's own hook for exactly this — the mark itself is an amber dot
    // and a screen-reader-only "needs attention", so neither half is a thing to assert against
    // directly.
    draw([mirror({}), otherMirror()]);
    await screen.findByText('acme');

    // One account holds something unmade and the other does not, and the difference shows on
    // the FOLDER: a warning visible only to whoever already opened the right one is not one.
    const blockedOrgs = [...document.querySelectorAll('[data-blocked="true"]')];
    expect(blockedOrgs).toHaveLength(1);
    expect(blockedOrgs[0]!.textContent).toContain('acme');

    await userEvent.click(screen.getByText('acme'));
    await screen.findByText('site');

    // ...and on the repository itself, which is the row Provision is pressed from.
    const marked = [...document.querySelectorAll('[data-blocked="true"]')].map(
      (el) => el.textContent,
    );
    expect(marked.some((t) => t?.includes('site'))).toBe(true);
  });

  it('marks nothing when every deployment repository has been made', async () => {
    draw([otherMirror()]);
    await screen.findByText('sandbox');
    expect(document.querySelectorAll('[data-blocked="true"]')).toHaveLength(0);
  });
});

/**
 * THE GEAR IS THE ACCOUNT'S, NOT THE REPOSITORY'S.
 *
 * "The default deployment repo, the default naming scheme, the environments" (Mike) are
 * answers a whole organization gives once, and hanging them off the repository level's title —
 * which names that organization — is what keeps them from being asked again per repository. It
 * is drawn only when the host wired a save, because a menu whose one entry cannot write is
 * worse than no menu at all.
 */
describe("the account's defaults", () => {
  it('offers Settings from the gear on the account column', async () => {
    const onSaveOrgDefaults = vi.fn(() => Promise.resolve());
    draw([mirror({})], { onSaveOrgDefaults });
    await userEvent.click(await screen.findByText('acme'));

    await userEvent.click(await screen.findByRole('button', { name: 'acme settings' }));
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Settings' }));

    expect(await waitFor(() => dialog('acme defaults'))).toBeTruthy();
  });

  it('draws no gear at all when nothing can be saved', async () => {
    draw([mirror({})]);
    await userEvent.click(await screen.findByText('acme'));
    await screen.findByText('site');
    expect(screen.queryByRole('button', { name: 'acme settings' })).toBeNull();
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

/**
 * THE VERBS LAND AFTER THE FIRST PAINT, AND A PRESS IN THAT WINDOW IS NOT A REFUSAL.
 *
 * The console paints its toolbar before the tree read returns, so Configure and then Add are
 * both pressable while nothing yet knows what this operator may do. Pressing Add there raised
 * "Not available / Still reading what you may do in this workspace." over the dialog — a modal
 * answering no to a question that had not been asked, and that would have answered yes a
 * moment later.
 *
 * Both halves are pinned here, because the cheap fix for the first breaks the second:
 * dropping the press silently is the swallowed click `BarButton` exists to prevent, and
 * treating every unlanded read as permission would hand a viewer the wizard.
 */
describe('a bar button pressed before the verbs have been read', () => {
  function drawWithVerbs(verbs: readonly AccessVerb[] | undefined) {
    const props = (v: readonly AccessVerb[] | undefined): React.ReactElement => (
      <ConfigureDialog
        open
        onClose={() => {}}
        client={CLIENT}
        catalogue={catalogueOf()}
        groups={[]}
        items={[]}
        verbs={v}
        onRegister={() => Promise.resolve()}
        onRemove={() => Promise.resolve()}
        onSaveSettings={() => Promise.resolve()}
        onImport={() => Promise.resolve()}
      />
    );
    const { rerender } = render(props(verbs));
    return { land: (v: readonly AccessVerb[]) => rerender(props(v)) };
  }

  it('says nothing yet, then opens the wizard when the read grants it', async () => {
    const user = userEvent.setup();
    const { land } = drawWithVerbs(undefined);

    await user.click(screen.getByRole('button', { name: 'Add' }));
    // The press is held, not answered: no verdict has been reached, so there is nothing
    // truthful to put on screen.
    expect(screen.queryByText('Not available')).toBeNull();
    expect(
      screen.queryByText('Still reading what you may do in this workspace.'),
    ).toBeNull();

    land(['C', 'R', 'U', 'D', 'M']);

    // And the press is not lost either — the operator gets the wizard they asked for, without
    // having to notice the button went live and press it a second time.
    expect(await screen.findByLabelText('Filter repositories')).toBeInTheDocument();
  });

  it('becomes the real refusal when the read grants nothing', async () => {
    const user = userEvent.setup();
    const { land } = drawWithVerbs(undefined);

    await user.click(screen.getByRole('button', { name: 'Add' }));
    land([]);

    // A workspace that answered "nothing" IS a refusal, and it is spoken with the sentence
    // that names the permission rather than the one about waiting.
    expect(
      await screen.findByText('You cannot register repositories here.'),
    ).toBeInTheDocument();
    expect(screen.queryByLabelText('Filter repositories')).toBeNull();
  });
});
