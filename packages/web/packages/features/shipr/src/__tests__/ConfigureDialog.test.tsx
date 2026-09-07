import { describe, expect, it, vi } from 'vitest';
import { act, render, screen, waitFor, within } from '@testing-library/react';
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
  const onRemove = vi.fn((_devRepo: DevRepo) => Promise.resolve());
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
      onRemove={onRemove}
      onSaveSettings={onSaveSettings}
      onImport={onImport}
      {...over}
    />,
  );
  return { onClose, onSaveSettings, onImport, onRemove };
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
  await userEvent.click(await railRow('acme'));
  await userEvent.click(await railRow(name));
}

/**
 * A row IN THE RAIL, rather than the same name spoken elsewhere on the screen.
 *
 * A bare `findByText` was enough while the detail pane held nothing but a hint. It is not any
 * more: the account's own pane names the account it is about and shows a worked example built
 * from the first repository in it — so `site` is on screen twice, and the walk that opens the
 * repository has to say which one it means. `data-htd-row` is the rail's own hook for a row.
 */
function railRow(name: string): Promise<HTMLElement> {
  return waitFor(() => {
    const row = screen
      .getAllByText(name)
      .map((node) => node.closest<HTMLElement>('[data-htd-row]'))
      .find((node): node is HTMLElement => node !== null);
    if (!row) throw new Error(`no rail row named ${name}`);
    return row;
  });
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
 * THE ACCOUNT'S SETTINGS ARE THE ACCOUNT'S TOPIC (Mike: "move the org related settings to org
 * topic list").
 *
 * "The default deployment repo, the default naming scheme, the environments" (Mike) are
 * answers a whole organization gives once, so the subject they belong to is the organization —
 * and every other subject on this screen is asked about the same way: select it in the rail,
 * read its detail pane. These were the exception. They hung off a gear on the REPOSITORY
 * level's title, one level BELOW their own subject, and its single menu entry opened a Dialog
 * on top of this Dialog — so two OK buttons and two Cancels were on screen at once, and the
 * account's settings could not be reached at all until a repository column had been opened.
 *
 * They draw where a repository's settings draw now, one level up, and this dialog's own footer
 * is their Save.
 */
describe("the account's defaults", () => {
  it('draws them in the detail pane when the account itself is selected', async () => {
    const onSaveOrgDefaults = vi.fn(() => Promise.resolve());
    draw([mirror({})], { onSaveOrgDefaults });
    // ONE click, and no menu: selecting the account IS how its settings are asked for.
    await userEvent.click(await screen.findByText('acme'));

    expect(await screen.findByLabelText('Deployment organization')).toBeInTheDocument();
    expect(screen.getByLabelText('Name suffix')).toBeInTheDocument();
  });

  it('has neither the gear nor the second dialog left anywhere', async () => {
    // Both halves of what was removed, pinned separately so neither can come back on its own:
    // the trigger that opened the modal, and the modal it opened.
    draw([mirror({})], { onSaveOrgDefaults: vi.fn(() => Promise.resolve()) });
    await userEvent.click(await screen.findByText('acme'));
    await screen.findByLabelText('Name suffix');

    expect(screen.queryByRole('button', { name: 'acme settings' })).toBeNull();
    expect(screen.queryByText('acme defaults')).toBeNull();
  });

  it('yields the pane to a repository the moment one is chosen', async () => {
    // The two panes share ONE footer OK, which submits whichever form is up — so they must
    // never be up together. A selected row is the more specific subject, and the account's
    // form is what the level above it is about.
    draw([mirror({})], { onSaveOrgDefaults: vi.fn(() => Promise.resolve()) });
    await openRepo();

    await screen.findByRole('checkbox', { name: /testing/i });
    expect(screen.queryByLabelText('Name suffix')).toBeNull();
  });

  it('draws nothing to save when the host wired no save', async () => {
    // A form whose OK cannot write is worse than the hint that sends the operator down a
    // level, so the pane falls back to the hint rather than to a dead form.
    draw([mirror({})]);
    await userEvent.click(await screen.findByText('acme'));
    await screen.findByText('site');
    expect(screen.queryByLabelText('Name suffix')).toBeNull();
  });

  it('will not draw the form before the stored defaults have been read', async () => {
    // THE OVERWRITE THIS GUARDS. The form seeds its draft once, on mount, and an account
    // whose defaults have not arrived seeds identically to one nobody has ever set defaults
    // on. So a pane drawn early would let the footer's OK write the bare convention over a
    // stored row — and re-aim every unprovisioned deployment repository in the account to
    // match it. "Not read yet" is a third state, not a synonym for "none".
    let land: (() => void) | null = null;
    const client = {
      workspace: 'acme',
      orgDefaults: () =>
        new Promise((resolve) => {
          land = () => resolve({ orgDefaults: [] });
        }),
    } as never;
    draw([mirror({})], { client, onSaveOrgDefaults: vi.fn(() => Promise.resolve()) });
    await userEvent.click(await screen.findByText('acme'));
    await screen.findByText('site');
    expect(screen.queryByLabelText('Name suffix')).toBeNull();

    await act(async () => {
      (land as (() => void) | null)?.();
    });
    expect(await screen.findByLabelText('Name suffix')).toBeInTheDocument();
  });
});

/**
 * REMOVE IS ON THE ROW'S OWN PANE TOO (Mike: "add a remove button to the sites details pane").
 *
 * It lived only on the bar above the rail — three columns away from the repository it acts on,
 * and identical in appearance whether or not one was selected. The pane copy sits under the
 * fields that describe that repository, where the operator already is.
 *
 * It is the SAME button, not a second one: the same `toolbarState` answer decides whether it
 * may be pressed, and the same confirmation opens when it is. That is what keeps a second
 * place to press it from becoming a second answer to whether it is allowed.
 */
describe('Remove in the repository pane', () => {
  /** The bar's copy, then the pane's — and, once the question is up, the confirm's. */
  const removes = () => screen.getAllByRole('button', { name: 'Remove' });
  /** The confirmation, once it is up. Thrown-on rather than `null` so `waitFor` retries. */
  const confirm = () =>
    waitFor(() => {
      const found = dialog('Remove repository');
      if (!found) throw new Error('the Remove confirmation is not open');
      return found;
    });

  it('appears with the repository, and only with it', async () => {
    draw([mirror({})]);
    // The bar's, and only the bar's, with nothing chosen.
    expect(removes()).toHaveLength(1);

    await openRepo();
    await screen.findByRole('checkbox', { name: /testing/i });
    expect(removes()).toHaveLength(2);
  });

  it('asks before it unregisters, and names the row in the question', async () => {
    // Mike: "I said I don't want the dangerzone confirmation dialog… but I still want a
    // confirmation dialog when deleting something!" The correction was about the dialog's
    // FORM — no phrase to retype — and never about whether to ask. So the press opens the
    // question and does nothing else, and the question says which row it is about, because
    // this dialog is opened over a list and "the repository" names nothing checkable.
    const { onRemove } = draw([mirror({})]);
    await openRepo();
    await screen.findByRole('checkbox', { name: /testing/i });

    await userEvent.click(removes()[1]!);
    const asked = await confirm();
    expect(within(asked).getByText(/acme\/site/)).toBeTruthy();
    expect(onRemove).not.toHaveBeenCalled();

    await userEvent.click(within(asked).getByRole('button', { name: 'Remove' }));
    await waitFor(() => expect(onRemove).toHaveBeenCalledTimes(1));
    expect(onRemove.mock.calls[0]![0]).toMatchObject({ slug: 'acme/site' });
  });

  it('unregisters nothing when the question is cancelled', async () => {
    // The half of a confirmation that actually does the work. A dialog whose Cancel still
    // removed the row would be worse than no dialog, because it would be believed.
    const { onRemove } = draw([mirror({})]);
    await openRepo();
    await screen.findByRole('checkbox', { name: /testing/i });

    await userEvent.click(removes()[1]!);
    const asked = await confirm();
    await userEvent.click(within(asked).getByRole('button', { name: 'Cancel' }));
    await waitFor(() => expect(dialog('Remove repository')).toBeUndefined());
    expect(onRemove).not.toHaveBeenCalled();
  });

  it('asks the same question from the bar as from the pane', async () => {
    // One verb pressed from two places. A second copy of the confirm is a second chance for
    // the bar and the pane to answer differently.
    const { onRemove } = draw([mirror({})]);
    await openRepo();
    await screen.findByRole('checkbox', { name: /testing/i });

    await userEvent.click(removes()[0]!);
    const asked = await confirm();
    await userEvent.click(within(asked).getByRole('button', { name: 'Remove' }));
    await waitFor(() => expect(onRemove).toHaveBeenCalledTimes(1));
  });

  it('is an ordinary disabled button when the gate refuses', async () => {
    // No `D`, so `toolbarState` refuses unregister. An ordinary button, refused the ordinary
    // way (Mike: "the remove button needs to not look like some weird ui you invented"), with
    // the gate's own sentence on the tooltip rather than in a modal.
    const { onRemove } = draw([mirror({})], { verbs: ['C', 'R', 'U', 'M'] });
    await openRepo();
    await screen.findByRole('checkbox', { name: /testing/i });

    const pane = removes()[1]!;
    expect(pane).toBeDisabled();
    expect(pane).toHaveAttribute('title', 'You cannot unregister repositories here.');

    await userEvent.click(pane);
    expect(onRemove).not.toHaveBeenCalled();
    expect(dialog('Remove repository')).toBeUndefined();
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

/**
 * THE PROVISION PRESS, from the front of the dialog it is pressed in.
 *
 * `useSettle.test.tsx` pins the waiting and `ProvisionButton.test.tsx` pins the button;
 * this pins the thing that was actually reported — that the dialog does not swallow the
 * verdict. The failure used to land in the run queue BEHIND this modal, which stays open,
 * so from in front of it the press did nothing at all.
 */
describe('the Configure dialog — Provision reports back', () => {
  it('holds the press open for the run, then draws what the run said', async () => {
    let fail: (e: Error) => void = () => {};
    const onProvision = vi.fn(
      () =>
        new Promise<void>((_resolve, reject) => {
          fail = reject;
        }),
    );
    draw([mirror({})], { onProvision });
    await openRepo();

    await userEvent.click(await screen.findByRole('button', { name: 'Provision' }));
    expect(onProvision).toHaveBeenCalledWith(DEV_REPO.id);
    // Still out. Nothing has been said yet, because nothing is known yet.
    await waitFor(() =>
      expect(screen.getByRole('button', { name: 'Provisioning…' })).toBeDisabled(),
    );

    const said =
      'POST /orgs/DeploymentRepos/repos — the forge answered 403: Resource not accessible by integration';
    await act(async () => {
      fail(new Error(said));
    });

    // In the dialog, not behind it — which is the whole report. The Configure dialog stays
    // open across the run, so a verdict drawn anywhere else is a verdict nobody can see.
    expect(within(dialog('Configure')).getByText(said)).toBeInTheDocument();
  });
});
