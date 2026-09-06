import { describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { RegisterWizard } from '../toolbar/RegisterWizard';
import type { ForgeCatalogue, ForgeOrg } from '../forge/useForgeCatalogue';
import type { ForgeRepository, RegisterRequest } from '../types';

/**
 * Add, as ONE question with any number of answers: which repositories?
 *
 * Most of what is pinned here is what this screen NO LONGER ASKS. It was three steps and
 * seven fields, then two screens and two — an installation, a folder, a main branch, a
 * prepared branch, a deployment owner, a deployment name, a confirmation of all of it — and
 * every one of those has an answer that is derivable here, on the server, or LATER. Deleting
 * a question is only safe if the answer it used to collect still reaches the request, so each
 * one that still matters is asserted on the bodies `onSubmit` receives rather than on a
 * control.
 *
 * THE DEPLOYMENT REPOSITORY IS NOT ASKED HERE AT ALL any more, and that is the change these
 * tests are mostly about. It was a second screen, because getting it wrong produced
 * `POST /orgs/DeploymentRepos/repos — 403: Resource not accessible by integration` minutes
 * into a run; it is now not asked because nothing is queued — Add writes the configuration
 * and creates nothing, and the org, the name and the environments are set afterwards in the
 * repository's own details pane, which can also check them against the forge. A screen that
 * makes nothing has nothing to confirm, which is what makes MULTIPLE SELECTION possible: a
 * per-repository deployment form cannot be filled in for eleven repositories at once, and
 * eleven is the ordinary case when a fleet is first pointed at shipr.
 *
 * THE LIST IS NOT READ HERE EITHER — it arrives as a {@link ForgeCatalogue} prop, so every
 * fixture below is a plain object and the screen makes no request in any test. What the read
 * itself has to get right (stored-then-refresh, a failed installation keeping its place) is
 * pinned in `useForgeCatalogue.test.tsx`, where the read now lives.
 *
 * The keyboard half is pinned for the same reason it exists: this is not a modal, it renders
 * inside the Configure dialog's pane, so an Escape that escaped would close the dialog too.
 */

const ACME: ForgeRepository[] = [
  { slug: 'acme/site', defaultBranch: 'trunk', private: true },
  { slug: 'acme/taken', defaultBranch: 'main', private: false },
];

const SANDBOX: ForgeRepository[] = [
  { slug: 'sandbox/site', defaultBranch: 'main', private: false },
  { slug: 'sandbox/toys', defaultBranch: 'main', private: false },
];

function org(over: Partial<ForgeOrg> & Pick<ForgeOrg, 'login'>): ForgeOrg {
  return {
    connectionId: `c-${over.login}`,
    repositories: [],
    error: null,
    loading: false,
    ...over,
  };
}

/**
 * A catalogue, built by hand.
 *
 * `connectionOf` is DERIVED from the orgs rather than accepted as a fixture, because that is
 * what the real one does and because the whole point of the field is that the installation
 * follows the repository — a hard-coded map would pass just as happily against a wizard that
 * sent the first connection every time.
 */
function catalogueOf(
  orgs: readonly ForgeOrg[] | undefined,
  over: Partial<ForgeCatalogue> = {},
): ForgeCatalogue {
  return {
    orgs,
    error: null,
    loading: orgs === undefined,
    connectionOf: (slug) =>
      (orgs ?? []).find((o) => o.repositories.some((r) => r.slug === slug))?.connectionId,
    installedOn: (login) => (orgs ?? []).some((o) => o.login === login),
    refresh: () => {},
    ...over,
  };
}

const BOTH = catalogueOf([
  org({ login: 'acme', repositories: ACME }),
  org({ login: 'sandbox', repositories: SANDBOX }),
]);

function draw(
  over: {
    catalogue?: ForgeCatalogue;
    registeredSlugs?: string[];
    onSubmit?: (bodies: readonly RegisterRequest[]) => Promise<void>;
    onClose?: () => void;
    onManageConnections?: () => void;
  } = {},
) {
  const onSubmit = vi
    .fn<(bodies: readonly RegisterRequest[]) => Promise<void>>()
    .mockImplementation(over.onSubmit ?? (() => Promise.resolve()));
  const onClose = over.onClose ?? vi.fn();
  const view = render(
    <RegisterWizard
      open
      onClose={onClose}
      catalogue={over.catalogue ?? BOTH}
      registeredSlugs={over.registeredSlugs}
      onManageConnections={over.onManageConnections}
      onSubmit={onSubmit}
    />,
  );
  return { onSubmit, onClose, view };
}

/** The repository list, addressed by the label the screen gives it. */
const repoList = () => screen.getByRole('list', { name: 'Repositories' });
const orgMenu = () => screen.getByLabelText('Organization') as HTMLSelectElement;
const filter = () => screen.getByLabelText('Filter repositories');
const ok = () => screen.getByRole('button', { name: 'OK' });
/** The confirm button whatever it is called — it counts the ticks once there is more than
 *  one, so a test that ticks two cannot address it as "OK". */
const confirm = () => screen.getByRole('button', { name: /^(OK|Add \d+)$/ });
/** A row's checkbox, by the slug it is addressed with. */
const box = (slug: string) => screen.getByRole('checkbox', { name: slug });

describe('RegisterWizard — the screen asks one question', () => {
  it('offers OK and Cancel, and nothing else to press through', () => {
    // Back, Next and Register were three buttons for a job with one decision in it.
    draw();
    expect(screen.getByRole('button', { name: 'Cancel' })).toBeTruthy();
    expect(ok()).toBeTruthy();
    for (const gone of ['Back', 'Next', 'Register']) {
      expect(screen.queryByRole('button', { name: gone })).toBeNull();
    }
  });

  it('asks for no folder and no branches, here or anywhere', () => {
    // Three fields deleted for good, and each one's answer still reaches the request — see
    // the `onSubmit` assertions below. What is asserted here is only that nobody is asked.
    draw();
    for (const label of ['Folder', 'Main branch', 'Prepared branch']) {
      expect(screen.queryByLabelText(label)).toBeNull();
    }
  });

  it('never asks which installation to look in', () => {
    // The dropdown, and the four alternative prose panels that hung under it explaining why
    // it was empty, are what an operator used to meet before their own repositories.
    draw();
    expect(screen.queryByLabelText('GitHub App installation')).toBeNull();
  });

  it('does not ask where the mirror goes, on this screen or a second one', async () => {
    // THE WHOLE POINT OF CONFIGURING FIRST. Add writes rows and creates nothing, so there is
    // nothing here to get wrong in somebody else's organization — the question moves to the
    // details pane, where the answer can be checked against the forge before Provision.
    const { onSubmit } = draw();
    await userEvent.click(box('acme/site'));
    await userEvent.click(ok());
    await waitFor(() => expect(onSubmit).toHaveBeenCalled());

    expect(screen.queryByLabelText('Deployment repository')).toBeNull();
    expect(screen.queryByLabelText('Deployment organization')).toBeNull();
    // And nothing about it reaches the request either: an absent key is what lets the org's
    // stored defaults decide, which is a decision this screen must not pre-empt.
    expect(onSubmit.mock.calls[0]![0][0]).not.toHaveProperty('deploymentOwner');
    expect(onSubmit.mock.calls[0]![0][0]).not.toHaveProperty('deploymentName');
  });

  it('reads nothing — the catalogue is a prop, and the screen makes no request', () => {
    // Structural, and deliberately so: there is no client to make one with. Re-reading per
    // opening is the bug the catalogue exists to fix, and a `client` prop creeping back is
    // how it would return.
    draw();
    expect(screen.queryByText(/Reading your repositories/)).toBeNull();
    expect(Object.keys(BOTH)).not.toContain('client');
  });

  it('pins OK and Cancel to the bottom, and lets the list have the rest', () => {
    // A modal's buttons live on its bottom edge. They rode up under a list capped at
    // `max-h-72` — 288px of list inside a 1470px pane, with a thousand pixels of nothing
    // under the buttons.
    //
    // jsdom lays nothing out, so what is asserted here is the STRUCTURE that makes the
    // layout possible: the footer is the last thing in the pane and does not sit inside the
    // scrolling half, and the list takes the slack rather than stopping at a fixed height.
    draw();
    const footer = document.querySelector('[data-slot="dialog-actions"]')!;
    const list = repoList();
    // The pane is [the part that scrolls, the part that does not]; the footer is the second.
    const pane = footer.parentElement!.parentElement!;
    expect(pane.lastElementChild!.contains(footer)).toBe(true);
    expect(pane.firstElementChild!.contains(list)).toBe(true);
    expect(pane.firstElementChild!.contains(footer)).toBe(false);
    expect((pane.firstElementChild as HTMLElement).className).toContain('flex-1');

    expect(list.className).toContain('flex-1');
    expect(list.className).not.toMatch(/max-h-/);
  });
});

describe('RegisterWizard — the org menu and the filter', () => {
  it('shows one owner’s repositories at a time, and switches on the menu', async () => {
    draw();
    // The first owner is open, because a screen that opens on nothing makes the operator
    // choose twice to see the list they came for.
    expect(within(repoList()).getByRole('checkbox', { name: 'acme/site' })).toBeTruthy();
    expect(within(repoList()).queryByRole('checkbox', { name: 'sandbox/toys' })).toBeNull();

    await userEvent.selectOptions(orgMenu(), 'sandbox');
    expect(within(repoList()).getByRole('checkbox', { name: 'sandbox/toys' })).toBeTruthy();
    expect(within(repoList()).queryByRole('checkbox', { name: 'acme/taken' })).toBeNull();
  });

  it('keeps every account in the menu, including one whose read failed', () => {
    // An installation that answered with an error contributes no rows, and a menu derived
    // from rows would therefore not name it: four accounts connected, three on screen, and
    // nothing anywhere saying which one was missing or why.
    draw({
      catalogue: catalogueOf([
        org({ login: 'acme', repositories: ACME }),
        org({ login: 'sandbox', error: 'installation suspended' }),
      ]),
    });
    expect([...orgMenu().options].map((o) => o.value)).toEqual(['acme', 'sandbox']);
  });

  it('names the repository without its owner, which the column already is', () => {
    // `acme/site` said eleven times down a 240px column is the owner eleven times and the
    // name once. The checkbox is still ADDRESSED by the slug, because that is what
    // identifies a repository.
    draw();
    expect(within(repoList()).getByText('site')).toBeTruthy();
    expect(within(repoList()).queryByText('acme/site')).toBeNull();
  });

  it('narrows the chosen org’s list as you type', async () => {
    draw();
    await userEvent.type(filter(), 'tak');
    expect(within(repoList()).getByRole('checkbox', { name: 'acme/taken' })).toBeTruthy();
    expect(within(repoList()).queryByRole('checkbox', { name: 'acme/site' })).toBeNull();
  });

  it('matches the whole slug, so the owner still filters', async () => {
    draw();
    await userEvent.selectOptions(orgMenu(), 'sandbox');
    await userEvent.type(filter(), 'sandbox/toys');
    expect(within(repoList()).getByRole('checkbox', { name: 'sandbox/toys' })).toBeTruthy();
  });

  it('says the filter matched nothing rather than drawing an empty frame', async () => {
    draw();
    await userEvent.type(filter(), 'nope');
    expect(within(repoList()).getByText(/No repository here matches/)).toBeTruthy();
  });

  it('offers an already registered repository disabled rather than omitting it', () => {
    // "Why isn't it in the list" has no answer on a screen that simply leaves it out, and the
    // answer — it is already here — is the one thing that stops the operator looking.
    draw({ registeredSlugs: ['acme/taken'] });
    const taken = screen.getByRole('checkbox', { name: /acme\/taken/ });
    // `aria-disabled`, not `disabled`: the shared Checkbox is a `span` carrying the role, so
    // there is no native control to refuse the click and the attribute is the whole refusal.
    expect(taken.getAttribute('aria-disabled')).toBe('true');
    expect(taken.getAttribute('aria-label')).toContain('already registered');
    expect(box('acme/site').getAttribute('aria-disabled')).not.toBe('true');
  });
});

/**
 * ONE empty box, four causes, four sentences.
 *
 * They share a shape — no repositories — and share nothing else, and for a while they shared
 * one sentence too: "No GitHub App installation". That sentence is a guess in three of the
 * four cases and flatly wrong in one, and the wrong one is the expensive one: it sends an
 * operator to GitHub to install an app they have already installed, over a read that simply
 * failed.
 */
describe('RegisterWizard — why the list is empty', () => {
  it('says it is still reading while the installations have not landed', () => {
    draw({ catalogue: catalogueOf(undefined) });
    expect(screen.getByText(/Reading your repositories/)).toBeTruthy();
  });

  it('says the installations read failed, and why, rather than naming an absence', () => {
    draw({ catalogue: catalogueOf([], { error: 'network is down' }) });
    expect(screen.getByText(/could not be read: network is down/)).toBeTruthy();
    // The one sentence that must NOT appear: it prescribes installing an app that may well
    // already be installed.
    expect(screen.queryByText(/hasn't been granted any repositories/)).toBeNull();
    // And it must SETTLE. A failed read that leaves "reading…" on screen is the state this
    // whole distinction exists to prevent, and it never resolves on its own.
    expect(screen.queryByText(/Reading your repositories/)).toBeNull();
  });

  it('says which account’s read failed when the others were fine', async () => {
    draw({
      catalogue: catalogueOf([
        org({ login: 'acme', repositories: ACME }),
        org({ login: 'sandbox', error: 'installation suspended' }),
      ]),
    });
    await userEvent.selectOptions(orgMenu(), 'sandbox');
    expect(screen.getByText(/sandbox's repositories could not be read/)).toBeTruthy();
    expect(screen.getByText(/installation suspended/)).toBeTruthy();
  });

  it('sends a read-and-empty account to the Test button', () => {
    // Nothing granted, or credentials GitHub refuses — and only the Test button can tell
    // those apart, because only it asks GitHub out loud.
    draw({ catalogue: catalogueOf([org({ login: 'acme' })]) });
    expect(screen.getByText(/hasn't been granted any repositories/)).toBeTruthy();
    expect(screen.getByText(/open Integrations and press Test/)).toBeTruthy();
  });

  it('sends an account-less workspace to Integrations to connect one', async () => {
    const onManageConnections = vi.fn();
    draw({ catalogue: catalogueOf([]), onManageConnections });
    expect(screen.getByText(/No GitHub App installation is connected yet/)).toBeTruthy();
    await userEvent.click(screen.getByRole('button', { name: 'Integrations' }));
    expect(onManageConnections).toHaveBeenCalled();
  });

  it('shows a stored list under its reason rather than replacing it with the reason', () => {
    // A list read an hour ago is a list you can pick from. An empty box is not, and swapping
    // one for the other is the trade the cache exists to stop making.
    draw({
      catalogue: catalogueOf([
        org({ login: 'acme', repositories: ACME, error: 'installation suspended' }),
      ]),
    });
    expect(screen.getByText(/Showing the stored list/)).toBeTruthy();
    expect(box('acme/site')).toBeTruthy();
  });
});

describe('RegisterWizard — what the ticks answer', () => {
  it('holds OK until a repository is ticked', async () => {
    draw();
    expect(ok()).toBeDisabled();
    await userEvent.click(box('acme/site'));
    expect(confirm()).not.toBeDisabled();
  });

  it('registers the slug, the installation that granted it, and the forge’s own branch', async () => {
    // THE THREE DELETED QUESTIONS, answered. `acme/site` defaults to `trunk`: assuming `main`
    // registers the repository against a branch that does not exist, and the first status run
    // is where that turns up. The installation is derived from the grant the row came out of,
    // because which one can reach a given repository is not a thing anybody knows by heart.
    // Folder and prepared branch are ABSENT, which is how the server's own defaults apply.
    const { onSubmit } = draw();
    await userEvent.click(box('acme/site'));
    await userEvent.click(ok());
    await waitFor(() =>
      expect(onSubmit).toHaveBeenCalledWith([
        { slug: 'acme/site', connectionId: 'c-acme', mainBranch: 'trunk' },
      ]),
    );
  });

  it('takes the installation from the repository, not from the first one read', async () => {
    const { onSubmit } = draw();
    await userEvent.selectOptions(orgMenu(), 'sandbox');
    await userEvent.click(box('sandbox/toys'));
    await userEvent.click(ok());
    await waitFor(() =>
      expect(onSubmit).toHaveBeenCalledWith([
        { slug: 'sandbox/toys', connectionId: 'c-sandbox', mainBranch: 'main' },
      ]),
    );
  });

  it('adds every ticked repository in ONE call, across accounts', async () => {
    // Eleven repositories is the ordinary case when a fleet is first pointed at shipr, and a
    // loop out here would refresh the tree eleven times and leave a half-added set behind
    // whichever one threw.
    const { onSubmit } = draw();
    await userEvent.click(box('acme/site'));
    await userEvent.click(box('acme/taken'));
    // The ticks SURVIVE the menu — switching accounts is narrowing the list, not starting
    // over, and a set that reset would silently drop the first half of a two-account add.
    await userEvent.selectOptions(orgMenu(), 'sandbox');
    await userEvent.click(box('sandbox/toys'));

    await userEvent.click(confirm());
    await waitFor(() => expect(onSubmit).toHaveBeenCalledTimes(1));
    expect(onSubmit.mock.calls[0]![0]).toEqual([
      { slug: 'acme/site', connectionId: 'c-acme', mainBranch: 'trunk' },
      { slug: 'acme/taken', connectionId: 'c-acme', mainBranch: 'main' },
      { slug: 'sandbox/toys', connectionId: 'c-sandbox', mainBranch: 'main' },
    ]);
  });

  it('counts the ticks on the button, so the press says what it is about to do', async () => {
    draw();
    await userEvent.click(box('acme/site'));
    expect(screen.getByRole('button', { name: 'OK' })).toBeTruthy();
    await userEvent.click(box('acme/taken'));
    expect(screen.getByRole('button', { name: 'Add 2' })).toBeTruthy();
  });

  it('un-ticks, and stands down again when the last box is cleared', async () => {
    draw();
    await userEvent.click(box('acme/site'));
    await userEvent.click(box('acme/site'));
    expect(ok()).toBeDisabled();
  });

  it('starts fresh on the next opening rather than on the last add’s answers', async () => {
    // The host may keep this mounted while closed, so the reset keys on `open` rather than on
    // a remount.
    const { view } = draw();
    await userEvent.click(box('acme/site'));
    await userEvent.type(filter(), 'site');

    view.rerender(
      <RegisterWizard open={false} onClose={() => {}} catalogue={BOTH} onSubmit={vi.fn()} />,
    );
    view.rerender(
      <RegisterWizard open onClose={() => {}} catalogue={BOTH} onSubmit={vi.fn()} />,
    );

    expect((filter() as HTMLInputElement).value).toBe('');
    expect(box('acme/site')).not.toBeChecked();
    expect(ok()).toBeDisabled();
  });
});

/**
 * The keyboard, which is the reason for the layout.
 *
 * Escape is caught HERE. This screen renders inside the Configure dialog's pane rather than
 * in a modal of its own, so an Escape allowed past would close that dialog and take the
 * repository list with it — the operator asked to leave one screen, not two.
 */
describe('RegisterWizard — the keyboard', () => {
  it('opens with the filter focused, and does not chase a tick to OK', async () => {
    const user = userEvent.setup();
    draw();
    expect(document.activeElement).toBe(filter());
    await user.click(box('acme/site'));
    // With several answers to give, focus jumping to OK on the first one ate the second.
    expect(document.activeElement).not.toBe(confirm());
  });

  it('submits on Enter once something is ticked', async () => {
    const user = userEvent.setup();
    const { onSubmit } = draw();
    await user.click(box('acme/site'));
    await user.click(filter());
    await user.keyboard('{Enter}');
    await waitFor(() => expect(onSubmit).toHaveBeenCalledTimes(1));
  });

  it('does not submit on Enter with nothing ticked', async () => {
    const user = userEvent.setup();
    const { onSubmit } = draw();
    await user.click(filter());
    await user.keyboard('{Enter}');
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it('cancels on Escape, and lets nothing above it hear the press', async () => {
    const user = userEvent.setup();
    const outer = vi.fn();
    const onClose = vi.fn();
    render(
      <div onKeyDown={outer}>
        <RegisterWizard
          open
          onClose={onClose}
          catalogue={BOTH}
          onSubmit={vi.fn().mockResolvedValue(undefined)}
        />
      </div>,
    );
    await user.click(screen.getByRole('checkbox', { name: 'acme/site' }));
    await user.keyboard('{Escape}');
    expect(onClose).toHaveBeenCalled();
    // The host Configure dialog is what would otherwise close underneath.
    expect(outer).not.toHaveBeenCalled();
  });

  it('says why the add failed, and stays open on the answers that were given', async () => {
    const onSubmit = vi.fn().mockRejectedValue(new Error('workspace is read-only'));
    const onClose = vi.fn();
    draw({ onSubmit, onClose });
    await userEvent.click(box('acme/site'));
    await userEvent.click(ok());
    expect(await screen.findByText(/workspace is read-only/)).toBeTruthy();
    expect(onClose).not.toHaveBeenCalled();
    expect(box('acme/site')).toBeChecked();
  });
});
