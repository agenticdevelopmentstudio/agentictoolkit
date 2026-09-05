import { describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { RegisterWizard } from '../toolbar/RegisterWizard';
import type {
  DeclarationResponse,
  ForgeConnection,
  RegisterRequest,
} from '../types';

/**
 * The wizard, driven through its two reads.
 *
 * WHAT IS BEING PINNED HERE is the branch at step 2, because it is the one place the dialog
 * decides something rather than showing something: a repository that declares its mirrors in
 * `.shipr` has nothing left to ask, and one that does not needs two answers with defaults
 * that must match what the server would have computed anyway. Getting that backwards is
 * silent — the wrong screen still submits, and the run creates a repository nobody named.
 */

const CONNECTIONS: ForgeConnection[] = [
  { id: 'c1', label: 'acme app', accountLogin: 'acme' },
  { id: 'c2', label: 'sandbox app', accountLogin: 'sandbox' },
];

const REPOSITORIES = [
  { slug: 'acme/site', defaultBranch: 'trunk', private: true },
  { slug: 'acme/taken', defaultBranch: 'main', private: false },
];

/** The declaration the fallback path gets: a file that named no `[deployments]`. */
const FALLBACK: DeclarationResponse = {
  deployments: null,
  fallbackSlug: 'acme/site-deployment',
};

const DECLARED: DeclarationResponse = {
  deployments: [
    { shard: 'eu', slug: 'acme/site-eu-deployment' },
    { shard: 'us', slug: 'acme/site-us-deployment' },
  ],
  fallbackSlug: 'acme/site-deployment',
};

/** A moment ago, in the shape the wire uses. The exact value never matters to a test — what
 *  matters is that both reads carry one, because the stored list announcing its age is the
 *  whole reason showing a stored list is honest rather than a guess. */
const READ_AT = '2026-09-01T12:00:00.000Z';

function draw(
  declaration: DeclarationResponse,
  over: {
    registeredSlugs?: string[];
    onSubmit?: (b: RegisterRequest) => Promise<void>;
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
    connectionRepositories: vi
      .fn()
      .mockImplementation(async (id: string) => ({
        repositories: granted[id] ?? [],
        readAt: READ_AT,
      })),
    refreshConnectionRepositories: over.refreshError
      ? vi.fn().mockRejectedValue(new Error(over.refreshError))
      : vi.fn().mockImplementation(async (id: string) => ({
          repositories: over.refreshed ?? granted[id] ?? [],
          readAt: READ_AT,
        })),
    connectionDeclaration: vi.fn().mockResolvedValue(declaration),
  };
  const onSubmit = over.onSubmit ?? vi.fn().mockResolvedValue(undefined);
  render(
    <RegisterWizard
      open
      onClose={vi.fn()}
      client={client}
      groups={[]}
      // `in`, not `??`: `undefined` is one of the three states under test — the read that has
      // not landed — so a default that swallows it would test the opposite of what it says.
      connections={'connections' in over ? over.connections : CONNECTIONS}
      connectionsError={over.connectionsError}
      registeredSlugs={over.registeredSlugs}
      onSubmit={onSubmit}
    />,
  );
  return { client, onSubmit };
}

/**
 * Which step is on screen, asked of the buttons rather than of a title.
 *
 * There IS no title any more — the wizard stopped being a modal, so the step heading these
 * assertions used to read went with the dialog chrome. The buttons say the same thing and
 * are what an operator actually navigates by: Back is dead on step 1, and step 3 is the only
 * one that offers Register.
 */
const backButton = () => screen.getByRole('button', { name: 'Back' });

async function toStepTwo(): Promise<void> {
  await userEvent.click(await screen.findByRole('button', { name: /acme\/site\b/ }));
  await userEvent.click(screen.getByRole('button', { name: 'Next' }));
  await waitFor(() => expect(backButton()).not.toBeDisabled());
}

async function toStepThree(): Promise<void> {
  await userEvent.click(screen.getByRole('button', { name: 'Next' }));
  await screen.findByRole('button', { name: 'Register' });
}

describe('RegisterWizard — step 1', () => {
  it('reads every installation’s repositories rather than asking for a slug', async () => {
    const { client } = draw(FALLBACK);
    expect(await screen.findByRole('button', { name: /acme\/site\b/ })).toBeTruthy();
    // BOTH, unprompted. There used to be a dropdown here and the wizard read only whichever
    // installation it happened to open on, so a repository granted to the other one was
    // invisible until the operator guessed which of two identical-looking apps to switch to.
    expect(client.connectionRepositories).toHaveBeenCalledWith('c1');
    expect(client.connectionRepositories).toHaveBeenCalledWith('c2');
  });

  it('never asks which installation to look in', async () => {
    // The dropdown, and the four alternative prose panels that hung under it explaining why it
    // was empty, are what an operator used to meet before their own repositories. They are
    // gone, and this asserts they stay gone.
    draw(FALLBACK);
    await screen.findByRole('button', { name: /acme\/site\b/ });
    expect(screen.queryByLabelText('GitHub App installation')).toBeNull();
  });

  it('merges the installations into one browser', async () => {
    draw(FALLBACK, {
      byConnection: {
        c1: [{ slug: 'acme/site', defaultBranch: 'trunk', private: true }],
        c2: [{ slug: 'sandbox/toys', defaultBranch: 'main', private: false }],
      },
    });
    // Two accounts, one list — and the owner column is what tells them apart, which is a thing
    // an operator can read off the screen rather than a thing they had to know.
    const orgs = await screen.findByRole('list', { name: 'Organizations' });
    expect(within(orgs).getByRole('button', { name: /^acme — / })).toBeTruthy();
    expect(within(orgs).getByRole('button', { name: /^sandbox — / })).toBeTruthy();
  });

  it('derives the installation from the repository that was picked', async () => {
    // The whole reason the dropdown could go: which installation can reach a repository is
    // knowable from the grant it came out of, and is not a thing anybody knows by heart.
    const { client } = draw(FALLBACK, {
      byConnection: {
        c1: [{ slug: 'acme/site', defaultBranch: 'trunk', private: true }],
        c2: [{ slug: 'sandbox/toys', defaultBranch: 'main', private: false }],
      },
    });
    // The owner column is the browser's first half, so the other installation's account is
    // reachable the ordinary way rather than by knowing it is a different installation.
    await userEvent.click(
      await screen.findByRole('button', { name: 'sandbox — 1 repository' }),
    );
    await userEvent.click(
      within(repoList()).getByRole('button', { name: /sandbox\/toys/ }),
    );
    await userEvent.click(screen.getByRole('button', { name: 'Next' }));
    await waitFor(() => expect(backButton()).not.toBeDisabled());
    expect(client.connectionDeclaration).toHaveBeenCalledWith(
      'c2',
      'sandbox/toys',
      'main',
    );
  });

  it('keeps the other installations’ repositories when one read fails', async () => {
    // One account refusing is not every account refusing, and an empty browser is what the
    // operator would otherwise be left holding.
    const client = {
      connectionRepositories: vi.fn().mockImplementation(async (id: string) => {
        if (id === 'c2') throw new Error('installation suspended');
        return { repositories: REPOSITORIES, readAt: READ_AT };
      }),
      refreshConnectionRepositories: vi
        .fn()
        .mockResolvedValue({ repositories: REPOSITORIES, readAt: READ_AT }),
      connectionDeclaration: vi.fn().mockResolvedValue(FALLBACK),
    };
    render(
      <RegisterWizard
        open
        onClose={vi.fn()}
        client={client}
        groups={[]}
        connections={CONNECTIONS}
        onSubmit={vi.fn().mockResolvedValue(undefined)}
      />,
    );
    expect(await screen.findByRole('button', { name: /acme\/site\b/ })).toBeTruthy();
  });

  it('offers an already registered repository disabled rather than omitting it', async () => {
    // "Why isn't it in the list" has no answer on a screen that simply leaves it out, and the
    // answer — it is already here — is the one thing that stops the operator looking.
    draw(FALLBACK, { registeredSlugs: ['acme/taken'] });
    const taken = await screen.findByRole('button', { name: /acme\/taken/ });
    expect(taken).toBeDisabled();
    expect(taken.textContent).toContain('already registered');
    expect(await screen.findByRole('button', { name: /acme\/site\b/ })).not.toBeDisabled();
  });

  it('takes the main branch from the forge’s answer, not from the word "main"', async () => {
    // `acme/site` defaults to `trunk`. Assuming `main` registers the repository against a
    // branch that does not exist, and the first status run is where that turns up.
    const { client } = draw(FALLBACK);
    await toStepTwo();
    expect(client.connectionDeclaration).toHaveBeenCalledWith('c1', 'acme/site', 'trunk');
  });
});

/**
 * ONE empty box, three causes, three sentences.
 *
 * They share a shape — no repositories — and share nothing else, and for a while they shared
 * one sentence too: "No GitHub App installation". That sentence is a guess in two of the three
 * cases and flatly wrong in one, and the wrong one is the expensive one: it sends an operator
 * to GitHub to install an app they have already installed, over a read that simply failed.
 *
 * This used to be four alternative panels stacked under a dropdown. It is one line under the
 * browser now, which is the same information in the place the operator is already looking.
 */
describe('RegisterWizard — why the browser is empty', () => {
  it('says it is still reading while the installations have not landed', async () => {
    draw(FALLBACK, { connections: undefined });
    expect(await screen.findByText(/Reading your repositories/)).toBeTruthy();
  });

  it('says the installations read failed, and why, rather than naming an absence', async () => {
    draw(FALLBACK, { connections: undefined, connectionsError: 'network is down' });
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
    // those apart, because only it asks GitHub out loud. Diagnosing it a second time here
    // would be two places answering one question.
    draw(FALLBACK, { connections: [] });
    expect(
      await screen.findByText(/hasn't been granted any repositories/),
    ).toBeTruthy();
    expect(screen.getByText(/open Integrations and press Test/)).toBeTruthy();
  });

  it('says the repository read failed when the installations were fine', async () => {
    const client = {
      connectionRepositories: vi.fn().mockRejectedValue(new Error('rate limited')),
      refreshConnectionRepositories: vi.fn(),
      connectionDeclaration: vi.fn(),
    };
    render(
      <RegisterWizard
        open
        onClose={vi.fn()}
        client={client}
        groups={[]}
        connections={CONNECTIONS}
        onSubmit={vi.fn().mockResolvedValue(undefined)}
      />,
    );
    expect(await screen.findByText(/rate limited/)).toBeTruthy();
  });
});

describe('RegisterWizard — the stored list', () => {
  it('draws the browser from what was written down, and asks GitHub behind it', async () => {
    const { client } = draw(FALLBACK);
    expect(await screen.findByRole('button', { name: /acme\/site\b/ })).toBeTruthy();
    expect(client.connectionRepositories).toHaveBeenCalledWith('c1');
    expect(client.refreshConnectionRepositories).toHaveBeenCalledWith('c1');
  });

  it('swaps in what the refresh returned', async () => {
    draw(FALLBACK, {
      refreshed: [{ slug: 'acme/newly-granted', defaultBranch: 'main', private: false }],
    });
    expect(
      await screen.findByRole('button', { name: /acme\/newly-granted/ }),
    ).toBeTruthy();
  });

  it('leaves the stored list standing when the refresh fails, with the reason beside it', async () => {
    // A list read an hour ago is a list you can pick from. An empty box is not, and replacing
    // one with the other is the trade the cache exists to stop making.
    draw(FALLBACK, { refreshError: 'installation suspended' });
    expect(await screen.findByText(/installation suspended/)).toBeTruthy();
    expect(screen.getByRole('button', { name: /acme\/site\b/ })).toBeTruthy();
  });
});

describe('RegisterWizard — step 2 with shards declared', () => {
  it('shows the table and offers nothing to choose', async () => {
    // The file already names every mirror. A form that could override it would be two sources
    // of truth for one slug — exactly the drift the CLI refuses.
    draw(DECLARED);
    await toStepTwo();
    expect(screen.getByText('acme/site-eu-deployment')).toBeTruthy();
    expect(screen.getByText('acme/site-us-deployment')).toBeTruthy();
    expect(screen.queryByLabelText('Organization')).toBeNull();
    expect(screen.queryByLabelText('Name')).toBeNull();
  });

  it('carries both shards through to the confirmation, and sends no override', async () => {
    const { onSubmit } = draw(DECLARED);
    await toStepTwo();
    await toStepThree();
    expect(screen.getByText(/create its 2 deployment repositories/)).toBeTruthy();

    await userEvent.click(screen.getByRole('button', { name: 'Register' }));
    expect(onSubmit).toHaveBeenCalledWith({
      slug: 'acme/site',
      connectionId: 'c1',
      mainBranch: 'trunk',
      preparedBranch: 'prepared',
    });
  });
});

describe('RegisterWizard — step 2 on the fallback', () => {
  it('offers org and name, defaulted from the server’s own convention', async () => {
    // Split from `fallbackSlug` rather than re-derived here: a repository registered from this
    // console and one registered from a workstation have to land on the same deployment repo.
    draw(FALLBACK);
    await toStepTwo();
    expect((screen.getByLabelText('Organization') as HTMLSelectElement).value).toBe('acme');
    expect((screen.getByLabelText('Name') as HTMLInputElement).value).toBe(
      'site-deployment',
    );
  });

  it('offers every account an installation was granted, and no other', async () => {
    // An org we hold no connection for would be a menu entry the run refuses.
    draw(FALLBACK);
    await toStepTwo();
    const options = [...(screen.getByLabelText('Organization') as HTMLSelectElement).options];
    expect(options.map((o) => o.value)).toEqual(['acme', 'sandbox']);
  });

  it('sends nothing when the defaults are left alone', async () => {
    // An override equal to the default is a field the request does not need to carry, and one
    // the server would have to reconcile against its own answer.
    const { onSubmit } = draw(FALLBACK);
    await toStepTwo();
    await userEvent.click(screen.getByRole('button', { name: 'Next' }));
    await userEvent.click(await screen.findByRole('button', { name: 'Register' }));
    expect(onSubmit).toHaveBeenCalledWith({
      slug: 'acme/site',
      connectionId: 'c1',
      mainBranch: 'trunk',
      preparedBranch: 'prepared',
    });
  });

  it('sends the override once the operator changes it', async () => {
    const { onSubmit } = draw(FALLBACK);
    await toStepTwo();
    await userEvent.selectOptions(screen.getByLabelText('Organization'), 'sandbox');
    await userEvent.clear(screen.getByLabelText('Name'));
    await userEvent.type(screen.getByLabelText('Name'), 'site-live');
    await userEvent.click(screen.getByRole('button', { name: 'Next' }));

    // The confirmation names what will be created, from the same derivation step 2 showed —
    // so it cannot name a repository the previous screen did not.
    expect(await screen.findByText('sandbox/site-live')).toBeTruthy();
    await userEvent.click(screen.getByRole('button', { name: 'Register' }));
    expect(onSubmit).toHaveBeenCalledWith({
      slug: 'acme/site',
      connectionId: 'c1',
      mainBranch: 'trunk',
      preparedBranch: 'prepared',
      deploymentOwner: 'sandbox',
      deploymentName: 'site-live',
    });
  });

  it('says the declaration was unusable when the server sends a note', async () => {
    // Present and broken is a different fact from absent, and worth one sentence: the operator
    // can go and fix the file.
    draw({ ...FALLBACK, note: 'deployments.eu.repo is not owner/name' });
    await toStepTwo();
    expect(
      screen.getByText(/deployments\.eu\.repo is not owner\/name/),
    ).toBeTruthy();
  });
});

/**
 * The org-and-repo browser.
 *
 * An installation covering several orgs arrived here as ONE flat column sorted by a slug whose
 * first half repeated for pages. What is pinned below is that the owner is now a column of its
 * own, that picking one narrows the other, and that the filter reaches BOTH halves of the slug
 * — a filter that only matched the visible half would silently hide the repository an operator
 * typed the full name of.
 */
const MANY = [
  { slug: 'acme/site', defaultBranch: 'trunk', private: true },
  { slug: 'acme/taken', defaultBranch: 'main', private: false },
  { slug: 'sandbox/site', defaultBranch: 'main', private: false },
  { slug: 'sandbox/toys', defaultBranch: 'main', private: false },
];

/** The repository column, addressed by the label the browser gives it. */
const repoList = () => screen.getByRole('list', { name: 'Repositories' });

describe('RegisterWizard — the org and repo browser', () => {
  it('lists the owners once each, with what each one holds', async () => {
    draw(FALLBACK, { repositories: MANY });
    const orgs = await screen.findByRole('list', { name: 'Organizations' });
    expect(
      within(orgs).getByRole('button', { name: 'acme — 2 repositories' }),
    ).toBeTruthy();
    expect(
      within(orgs).getByRole('button', { name: 'sandbox — 2 repositories' }),
    ).toBeTruthy();
  });

  it('shows one owner’s repositories at a time, and switches on the click', async () => {
    draw(FALLBACK, { repositories: MANY });
    await screen.findByRole('button', { name: 'acme — 2 repositories' });
    // The first owner is open, because a browser that opens on nothing makes the operator
    // click twice to see the list they came for.
    expect(within(repoList()).getByRole('button', { name: /acme\/site\b/ })).toBeTruthy();
    expect(within(repoList()).queryByRole('button', { name: /sandbox\/toys/ })).toBeNull();

    await userEvent.click(screen.getByRole('button', { name: 'sandbox — 2 repositories' }));
    expect(within(repoList()).getByRole('button', { name: /sandbox\/toys/ })).toBeTruthy();
    expect(within(repoList()).queryByRole('button', { name: /acme\/taken/ })).toBeNull();
  });

  it('filters on the whole slug, so the owner half narrows the owners', async () => {
    draw(FALLBACK, { repositories: MANY });
    await screen.findByRole('button', { name: 'acme — 2 repositories' });

    await userEvent.type(screen.getByLabelText('Filter repositories'), 'sandbox');
    // The owner column is derived from what matched, so filtering by owner IS choosing one.
    expect(screen.queryByRole('button', { name: /^acme — / })).toBeNull();
    expect(within(repoList()).getByRole('button', { name: /sandbox\/site/ })).toBeTruthy();
  });

  it('filters on the repository half across every owner at once', async () => {
    // `site` exists under both owners, and the point of one filter over two columns is that
    // this shows both rather than only the one whose column happens to be open.
    draw(FALLBACK, { repositories: MANY });
    await screen.findByRole('button', { name: 'acme — 2 repositories' });

    await userEvent.type(screen.getByLabelText('Filter repositories'), 'site');
    expect(screen.getByRole('button', { name: 'acme — 1 repository' })).toBeTruthy();
    expect(screen.getByRole('button', { name: 'sandbox — 1 repository' })).toBeTruthy();
    expect(within(repoList()).queryByRole('button', { name: /acme\/taken/ })).toBeNull();
  });

  it('says the filter matched nothing rather than drawing an empty frame', async () => {
    draw(FALLBACK, { repositories: MANY });
    await screen.findByRole('button', { name: 'acme — 2 repositories' });

    await userEvent.type(screen.getByLabelText('Filter repositories'), 'nope');
    expect(
      screen.getByText(/No repository this app was granted matches/),
    ).toBeTruthy();
  });

  it('picks a repository from a column that shows only its name', async () => {
    // The owner is a heading in the other column now, so the row's own text is the name alone
    // — but the pick still carries the full slug, which is what the wizard registers.
    const { client } = draw(FALLBACK, { repositories: MANY });
    await screen.findByRole('button', { name: 'acme — 2 repositories' });
    await userEvent.click(
      within(repoList()).getByRole('button', { name: /acme\/site\b/ }),
    );
    await userEvent.click(screen.getByRole('button', { name: 'Next' }));
    await waitFor(() => expect(backButton()).not.toBeDisabled());
    expect(client.connectionDeclaration).toHaveBeenCalledWith('c1', 'acme/site', 'trunk');
  });
});

describe('RegisterWizard — the confirmation', () => {
  it('says out loud that it writes nothing to the source repository', async () => {
    // An earlier draft of this dialog was going to tell the operator it commits a `.shipr`.
    // It does not, and the step that asks for the irreversible click is where that is settled.
    draw(FALLBACK);
    await toStepTwo();
    await userEvent.click(screen.getByRole('button', { name: 'Next' }));
    expect(
      await screen.findByText(/Nothing is written to/),
    ).toBeTruthy();
  });
});
