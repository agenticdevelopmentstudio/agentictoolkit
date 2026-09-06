import { describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { RegisterWizard } from '../toolbar/RegisterWizard';
import type { ForgeConnection, RegisterRequest } from '../types';

/**
 * Register, as ONE question: which repository?
 *
 * What is pinned here is mostly what the screen NO LONGER ASKS. It was three steps and seven
 * fields — an installation, a folder, a main branch, a prepared branch, a deployment owner and
 * name, and a confirmation of all of it — and every one of those has an answer that is
 * derivable here or on the server. Deleting a question is only safe if the answer it used to
 * collect still reaches the request, so each of the four that still matter is asserted on the
 * body `onSubmit` receives rather than on a control.
 *
 * The keyboard half is pinned for the same reason it exists: this is not a modal, it renders
 * inside the Configure dialog's pane, so an Escape that escaped would close the dialog too.
 */

const CONNECTIONS: ForgeConnection[] = [
  { id: 'c1', label: 'acme app', accountLogin: 'acme' },
  { id: 'c2', label: 'sandbox app', accountLogin: 'sandbox' },
];

const REPOSITORIES = [
  { slug: 'acme/site', defaultBranch: 'trunk', private: true },
  { slug: 'acme/taken', defaultBranch: 'main', private: false },
];

const MANY = [
  { slug: 'acme/site', defaultBranch: 'trunk', private: true },
  { slug: 'acme/taken', defaultBranch: 'main', private: false },
  { slug: 'sandbox/site', defaultBranch: 'main', private: false },
  { slug: 'sandbox/toys', defaultBranch: 'main', private: false },
];

/** A moment ago, in the shape the wire uses. The exact value never matters to a test — what
 *  matters is that both reads carry one, because the stored list announcing its age is the
 *  whole reason showing a stored list is honest rather than a guess. */
const READ_AT = '2026-09-01T12:00:00.000Z';

function draw(
  over: {
    registeredSlugs?: string[];
    onSubmit?: (b: RegisterRequest) => Promise<void>;
    onClose?: () => void;
    repositories?: typeof REPOSITORIES;
    /** What each installation was granted, when a test cares that they differ. Keyed by
     *  connection id; anything unnamed granted nothing. */
    byConnection?: Record<string, typeof REPOSITORIES>;
    /** What the refresh answers, when the test cares. Defaults to the stored list, which is
     *  the ordinary case: nothing changed on GitHub between the two calls. */
    refreshed?: typeof REPOSITORIES;
    /** The refresh REFUSES. The stored list must survive it. */
    refreshError?: string;
    connections?: ForgeConnection[];
    connectionsError?: string;
  } = {},
) {
  // One installation grants the list by default and the other grants nothing, because that is
  // the shape every merge has to survive: an account with repositories beside an account
  // without, both read, neither hiding the other.
  const granted = over.byConnection ?? { c1: over.repositories ?? REPOSITORIES };
  const client = {
    connectionRepositories: vi.fn().mockImplementation(async (id: string) => ({
      repositories: granted[id] ?? [],
      readAt: READ_AT,
    })),
    refreshConnectionRepositories: over.refreshError
      ? vi.fn().mockRejectedValue(new Error(over.refreshError))
      : vi.fn().mockImplementation(async (id: string) => ({
          repositories: over.refreshed ?? granted[id] ?? [],
          readAt: READ_AT,
        })),
  };
  const onSubmit = over.onSubmit ?? vi.fn().mockResolvedValue(undefined);
  const onClose = over.onClose ?? vi.fn();
  render(
    <RegisterWizard
      open
      onClose={onClose}
      client={client}
      // `in`, not `??`: `undefined` is one of the three states under test — the read that has
      // not landed — so a default that swallows it would test the opposite of what it says.
      connections={'connections' in over ? over.connections : CONNECTIONS}
      connectionsError={over.connectionsError}
      registeredSlugs={over.registeredSlugs}
      onSubmit={onSubmit}
    />,
  );
  return { client, onSubmit, onClose };
}

/** The repository list, addressed by the label the screen gives it. */
const repoList = () => screen.getByRole('list', { name: 'Repositories' });
const orgMenu = () => screen.getByLabelText('Organization') as HTMLSelectElement;
const ok = () => screen.getByRole('button', { name: 'OK' });

describe('RegisterWizard — the screen asks one question', () => {
  it('offers OK and Cancel, and nothing else to press through', async () => {
    // Back, Next and Register were three buttons for a job with one decision in it. The whole
    // point of the rewrite is that they are gone.
    draw();
    await screen.findByRole('button', { name: 'acme/site' });
    expect(screen.getByRole('button', { name: 'Cancel' })).toBeTruthy();
    expect(ok()).toBeTruthy();
    for (const gone of ['Back', 'Next', 'Register']) {
      expect(screen.queryByRole('button', { name: gone })).toBeNull();
    }
  });

  it('asks for no folder, no branches and no deployment repository', async () => {
    // Four fields deleted, and each one's answer still reaches the request — see the
    // `onSubmit` assertions below. What is asserted here is only that nobody is asked.
    draw();
    await screen.findByRole('button', { name: 'acme/site' });
    for (const label of ['Folder', 'Main branch', 'Prepared branch', 'Name']) {
      expect(screen.queryByLabelText(label)).toBeNull();
    }
  });

  it('pins OK and Cancel to the bottom, and lets the list have the rest', async () => {
    // A modal's buttons live on its bottom edge. They rode up under a list that was capped at
    // `max-h-72` — 288px of list inside a 1470px pane, with a thousand pixels of nothing under
    // the buttons.
    //
    // jsdom lays nothing out, so what is asserted here is the STRUCTURE that makes the layout
    // possible: the footer is the last thing in the pane (so it sits on the bottom edge), it is
    // outside the form (so OK cannot both click and submit), and the list is told to take the
    // slack rather than to stop at a fixed height. The pixels themselves are checked in a
    // browser — this is the part that would silently regress in an edit.
    draw();
    await screen.findByRole('button', { name: 'acme/site' });

    const footer = document.querySelector('[data-slot="dialog-actions"]')!;
    const form = document.querySelector('form')!;
    expect(form.parentElement!.lastElementChild!.contains(footer)).toBe(true);
    expect(form.contains(footer)).toBe(false);
    expect(form.className).toContain('flex-1');

    const list = repoList();
    expect(list.className).toContain('flex-1');
    expect(list.className).not.toMatch(/max-h-/);
  });

  it('never asks which installation to look in', async () => {
    // The dropdown, and the four alternative prose panels that hung under it explaining why it
    // was empty, are what an operator used to meet before their own repositories.
    draw();
    await screen.findByRole('button', { name: 'acme/site' });
    expect(screen.queryByLabelText('GitHub App installation')).toBeNull();
  });
});

describe('RegisterWizard — reading the repositories', () => {
  it('reads every installation rather than asking for a slug', async () => {
    const { client } = draw();
    expect(await screen.findByRole('button', { name: 'acme/site' })).toBeTruthy();
    // BOTH, unprompted. There used to be a dropdown here and the wizard read only whichever
    // installation it happened to open on, so a repository granted to the other one was
    // invisible until the operator guessed which of two identical-looking apps to switch to.
    expect(client.connectionRepositories).toHaveBeenCalledWith('c1');
    expect(client.connectionRepositories).toHaveBeenCalledWith('c2');
  });

  it('merges the installations into one menu of orgs', async () => {
    draw({
      byConnection: {
        c1: [{ slug: 'acme/site', defaultBranch: 'trunk', private: true }],
        c2: [{ slug: 'sandbox/toys', defaultBranch: 'main', private: false }],
      },
    });
    await screen.findByRole('button', { name: 'acme/site' });
    expect([...orgMenu().options].map((o) => o.value)).toEqual(['acme', 'sandbox']);
  });

  it('draws the list from what was written down, and asks GitHub behind it', async () => {
    const { client } = draw();
    expect(await screen.findByRole('button', { name: 'acme/site' })).toBeTruthy();
    expect(client.connectionRepositories).toHaveBeenCalledWith('c1');
    expect(client.refreshConnectionRepositories).toHaveBeenCalledWith('c1');
  });

  it('swaps in what the refresh returned', async () => {
    draw({
      refreshed: [{ slug: 'acme/newly-granted', defaultBranch: 'main', private: false }],
    });
    expect(await screen.findByRole('button', { name: 'acme/newly-granted' })).toBeTruthy();
  });

  it('leaves the stored list standing when the refresh fails, with the reason beside it', async () => {
    // A list read an hour ago is a list you can pick from. An empty box is not, and replacing
    // one with the other is the trade the cache exists to stop making.
    draw({ refreshError: 'installation suspended' });
    expect(await screen.findByText(/installation suspended/)).toBeTruthy();
    expect(screen.getByRole('button', { name: 'acme/site' })).toBeTruthy();
  });

  it('keeps the other installations’ repositories when one read fails', async () => {
    const client = {
      connectionRepositories: vi.fn().mockImplementation(async (id: string) => {
        if (id === 'c2') throw new Error('installation suspended');
        return { repositories: REPOSITORIES, readAt: READ_AT };
      }),
      refreshConnectionRepositories: vi
        .fn()
        .mockResolvedValue({ repositories: REPOSITORIES, readAt: READ_AT }),
    };
    render(
      <RegisterWizard
        open
        onClose={vi.fn()}
        client={client}
        connections={CONNECTIONS}
        onSubmit={vi.fn().mockResolvedValue(undefined)}
      />,
    );
    expect(await screen.findByRole('button', { name: 'acme/site' })).toBeTruthy();
  });
});

/**
 * ONE empty box, three causes, three sentences.
 *
 * They share a shape — no repositories — and share nothing else, and for a while they shared
 * one sentence too: "No GitHub App installation". That sentence is a guess in two of the three
 * cases and flatly wrong in one, and the wrong one is the expensive one: it sends an operator
 * to GitHub to install an app they have already installed, over a read that simply failed.
 */
describe('RegisterWizard — why the list is empty', () => {
  it('says it is still reading while the installations have not landed', async () => {
    draw({ connections: undefined });
    expect(await screen.findByText(/Reading your repositories/)).toBeTruthy();
  });

  it('says the installations read failed, and why, rather than naming an absence', async () => {
    draw({ connections: undefined, connectionsError: 'network is down' });
    expect(await screen.findByText(/could not be read: network is down/)).toBeTruthy();
    // The one sentence that must NOT appear: it prescribes installing an app that may well
    // already be installed.
    expect(screen.queryByText(/hasn't been granted any repositories/)).toBeNull();
    // And it must SETTLE. A failed read that leaves "reading…" on screen is the state this
    // whole distinction exists to prevent, and it never resolves on its own.
    expect(screen.queryByText(/Reading your repositories/)).toBeNull();
  });

  it('sends a read-and-empty list to the Test button for the second cause', async () => {
    // Nothing installed, or credentials GitHub refuses — and only the Test button can tell
    // those apart, because only it asks GitHub out loud.
    draw({ connections: [] });
    expect(await screen.findByText(/hasn't been granted any repositories/)).toBeTruthy();
    expect(screen.getByText(/open Integrations and press Test/)).toBeTruthy();
  });

  it('says the repository read failed when the installations were fine', async () => {
    const client = {
      connectionRepositories: vi.fn().mockRejectedValue(new Error('rate limited')),
      refreshConnectionRepositories: vi.fn(),
    };
    render(
      <RegisterWizard
        open
        onClose={vi.fn()}
        client={client}
        connections={CONNECTIONS}
        onSubmit={vi.fn().mockResolvedValue(undefined)}
      />,
    );
    expect(await screen.findByText(/rate limited/)).toBeTruthy();
  });
});

describe('RegisterWizard — the org menu and the filter', () => {
  it('shows one owner’s repositories at a time, and switches on the menu', async () => {
    draw({ repositories: MANY });
    // The first owner is open, because a screen that opens on nothing makes the operator
    // choose twice to see the list they came for.
    expect(await screen.findByRole('button', { name: 'acme/site' })).toBeTruthy();
    expect(within(repoList()).queryByRole('button', { name: 'sandbox/toys' })).toBeNull();

    await userEvent.selectOptions(orgMenu(), 'sandbox');
    expect(within(repoList()).getByRole('button', { name: 'sandbox/toys' })).toBeTruthy();
    expect(within(repoList()).queryByRole('button', { name: 'acme/taken' })).toBeNull();
  });

  it('narrows the chosen org’s list as you type', async () => {
    draw({ repositories: MANY });
    await screen.findByRole('button', { name: 'acme/site' });

    await userEvent.type(screen.getByLabelText('Filter repositories'), 'tak');
    expect(within(repoList()).getByRole('button', { name: 'acme/taken' })).toBeTruthy();
    expect(within(repoList()).queryByRole('button', { name: 'acme/site' })).toBeNull();
  });

  it('says the filter matched nothing rather than drawing an empty frame', async () => {
    draw({ repositories: MANY });
    await screen.findByRole('button', { name: 'acme/site' });

    await userEvent.type(screen.getByLabelText('Filter repositories'), 'nope');
    expect(within(repoList()).getByText(/No repository here matches/)).toBeTruthy();
  });

  it('offers an already registered repository disabled rather than omitting it', async () => {
    // "Why isn't it in the list" has no answer on a screen that simply leaves it out, and the
    // answer — it is already here — is the one thing that stops the operator looking.
    draw({ registeredSlugs: ['acme/taken'] });
    const taken = await screen.findByRole('button', { name: /acme\/taken/ });
    expect(taken).toBeDisabled();
    expect(taken.getAttribute('aria-label')).toContain('already registered');
    expect(screen.getByRole('button', { name: 'acme/site' })).not.toBeDisabled();
  });
});

describe('RegisterWizard — what the pick answers', () => {
  it('holds OK until a repository is picked', async () => {
    draw();
    await screen.findByRole('button', { name: 'acme/site' });
    expect(ok()).toBeDisabled();
    await userEvent.click(screen.getByRole('button', { name: 'acme/site' }));
    expect(ok()).not.toBeDisabled();
  });

  it('registers the slug, the installation that granted it, and the forge’s own branch', async () => {
    // THE THREE DELETED QUESTIONS, answered. `acme/site` defaults to `trunk`: assuming `main`
    // registers the repository against a branch that does not exist, and the first status run
    // is where that turns up. The installation is derived from the grant the row came out of,
    // because which one can reach a given repository is not a thing anybody knows by heart.
    // Folder and prepared branch are ABSENT, which is how the server's own defaults apply.
    const { onSubmit } = draw({
      byConnection: {
        c1: [{ slug: 'acme/site', defaultBranch: 'trunk', private: true }],
        c2: [{ slug: 'sandbox/toys', defaultBranch: 'main', private: false }],
      },
    });
    await userEvent.click(await screen.findByRole('button', { name: 'acme/site' }));
    await userEvent.click(ok());
    await waitFor(() =>
      expect(onSubmit).toHaveBeenCalledWith({
        slug: 'acme/site',
        connectionId: 'c1',
        mainBranch: 'trunk',
      }),
    );
  });

  it('takes the installation from the repository, not from the first one read', async () => {
    const { onSubmit } = draw({
      byConnection: {
        c1: [{ slug: 'acme/site', defaultBranch: 'trunk', private: true }],
        c2: [{ slug: 'sandbox/toys', defaultBranch: 'main', private: false }],
      },
    });
    await screen.findByRole('button', { name: 'acme/site' });
    await userEvent.selectOptions(orgMenu(), 'sandbox');
    await userEvent.click(screen.getByRole('button', { name: 'sandbox/toys' }));
    await userEvent.click(ok());
    await waitFor(() =>
      expect(onSubmit).toHaveBeenCalledWith({
        slug: 'sandbox/toys',
        connectionId: 'c2',
        mainBranch: 'main',
      }),
    );
  });
});

/**
 * The keyboard, which is the reason for the layout.
 *
 * Escape is caught HERE. This screen renders inside the Configure dialog's pane rather than in
 * a modal of its own, so an Escape allowed past would close that dialog and take the repository
 * list with it — the operator asked to leave one screen, not two.
 */
describe('RegisterWizard — the keyboard', () => {
  it('submits on Enter once a repository is picked', async () => {
    const user = userEvent.setup();
    const { onSubmit } = draw();
    await user.click(await screen.findByRole('button', { name: 'acme/site' }));
    // Focus is on OK by now — the pick moves it there, which is what makes Enter mean OK.
    expect(document.activeElement).toBe(ok());
    await user.keyboard('{Enter}');
    await waitFor(() => expect(onSubmit).toHaveBeenCalled());
  });

  it('does not submit on Enter with nothing picked', async () => {
    const user = userEvent.setup();
    const { onSubmit } = draw();
    await screen.findByRole('button', { name: 'acme/site' });
    await user.click(screen.getByLabelText('Filter repositories'));
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
          client={{
            connectionRepositories: vi
              .fn()
              .mockResolvedValue({ repositories: REPOSITORIES, readAt: READ_AT }),
            refreshConnectionRepositories: vi
              .fn()
              .mockResolvedValue({ repositories: REPOSITORIES, readAt: READ_AT }),
          }}
          connections={[CONNECTIONS[0]!]}
          onSubmit={vi.fn().mockResolvedValue(undefined)}
        />
      </div>,
    );
    await user.click(await screen.findByRole('button', { name: 'acme/site' }));
    await user.keyboard('{Escape}');
    expect(onClose).toHaveBeenCalled();
    // The host Configure dialog is what would otherwise close underneath.
    expect(outer).not.toHaveBeenCalled();
  });
});
