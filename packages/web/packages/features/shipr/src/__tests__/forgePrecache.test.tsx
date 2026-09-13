import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, render, screen, waitFor } from '@testing-library/react';

import { ShiprConsole } from '../ShiprConsole';
import type { ShiprClient } from '../client';
import type { ForgeConnection, RepoItem, TreeResponse } from '../types';

/**
 * THE FORGE IS READ BEFORE ANYBODY ASKS FOR IT, and again the moment an integration lands.
 *
 * This is the console end of a defect an operator reported in words worth keeping: "I added 4
 * github integrations, all tested ok, only 2 are showing up in the repo browser — they
 * eventually showed up". Two halves, and both of them are pinned here because neither is
 * visible from inside the hook.
 *
 * The FIRST half is the one the hook's own tests cover from the inside and nothing covered
 * from the outside: the read must start when the CONSOLE mounts, not when the dialog that
 * consumes it opens. The org menu in the repo browser is built from the prefetched catalogue
 * — `ConfigureDialog` takes `catalogue` and makes no request of its own — so an operator who
 * opens Configure ten seconds after the page settled must find it already answered. Put the
 * read behind the dialog and every opening pays a forge round trip per installation, which is
 * exactly what "they eventually showed up" sounds like from the other side of the screen.
 *
 * The SECOND half is why only two of four appeared at all. A GitHub App integration becomes a
 * CONNECTION when the adopt behind Save-or-Test resolves, and that adopt used to tell nobody:
 * the pane's `onChanged` fired before it, so the console re-read the connection list while the
 * new row was still being written and then never asked again. The catalogue keys its reads on
 * WHICH connections exist, so a list that never gained the row never gained the org either.
 * Both are re-read here, on the one seam the pane notifies through.
 *
 * `IntegrationsPane` is stubbed down to that seam. What is under test is the console's
 * reaction to it, and a real pane would put its own reads between the two.
 */

vi.mock('../live', () => ({
  watchRun: () => ({ close: vi.fn() }),
  watchWorkspaceRuns: () => ({ close: vi.fn() }),
}));

vi.mock('@agentic-toolkit/data/ecosystems', () => ({
  useWorkspaceDefaultEcosystemId: () => ({
    ecosystemId: 'eco-1',
    canManage: true,
    isPending: false,
    isFetching: false,
    isError: false,
  }),
}));

/** What the pane was last handed — the notification seam, which is the only part of the pane
 *  this file is about. */
const pane: { onChanged?: () => void } = {};

vi.mock('@agentic-toolkit/integrations', async (importOriginal) => ({
  CONNECTIONS_HASH: (
    await importOriginal<typeof import('@agentic-toolkit/integrations')>()
  ).CONNECTIONS_HASH,
  IntegrationsPane: (props: { onChanged?: () => void }) => {
    pane.onChanged = props.onChanged;
    return <div data-testid="integrations-pane" />;
  },
}));

const repo: RepoItem = {
  id: 'm1',
  devRepoId: 'd1',
  groupId: null,
  slug: 'acme/site-deployment',
  shard: 'all',
  shipBranch: 'ship',
  ciContext: 'deploy/ci',
  envBranches: { testing: 'testing', staging: 'staging', production: 'production' },
  registeredAt: null,
  position: 0,
  devRepo: null,
  state: {
    deployRepoId: 'm1',
    tips: {},
    settled: true,
    notes: [],
    readAt: new Date().toISOString(),
  },
};

const tree: TreeResponse = {
  workspace: { kind: 'customer', ownerId: 'c1' },
  verbs: ['C', 'R', 'U', 'D', 'M'],
  groups: [],
  items: [repo],
};

/** The four the operator added, in the shape the connect flow writes them. */
const CONNECTIONS: ForgeConnection[] = [
  { id: 'c1', label: 'DeploymentRepos', accountLogin: 'DeploymentRepos' },
  { id: 'c2', label: 'fishlampdesign', accountLogin: 'fishlampdesign' },
  { id: 'c3', label: 'agenticdevelopmentstudio', accountLogin: 'agenticdevelopmentstudio' },
  { id: 'c4', label: 'mfullerton', accountLogin: 'mfullerton' },
];

const reads = {
  stored: vi.fn(),
  fresh: vi.fn(),
};

function stubClient(): ShiprClient {
  return {
    workspace: 'acme',
    tree: vi.fn().mockResolvedValue(tree),
    runs: vi.fn().mockResolvedValue({ items: [] }),
    run: vi.fn().mockResolvedValue({ runId: 'run1' }),
    repo: vi.fn().mockResolvedValue({ repo, devRepo: null, group: null, ladder: null, runs: [] }),
    connectionRepositories: (id: string) => {
      reads.stored(id);
      return Promise.resolve({ repositories: [] });
    },
    refreshConnectionRepositories: (id: string) => {
      reads.fresh(id);
      return Promise.resolve({ repositories: [] });
    },
  } as unknown as ShiprClient;
}

/** Which installations the forge was asked about, deduplicated — a generation bump asks about
 *  every one it already knows, so the COUNT says nothing and the set says everything. */
const asked = () => new Set(reads.fresh.mock.calls.map(([id]) => id as string));

beforeEach(() => {
  window.localStorage.clear();
  reads.stored.mockClear();
  reads.fresh.mockClear();
  delete pane.onChanged;
});

afterEach(() => {
  window.history.replaceState(null, '', '/');
});

describe('the forge catalogue is precached', () => {
  it('asks about every installation as the console mounts, with nothing opened', async () => {
    const client = stubClient();
    render(<ShiprConsole client={client} connections={CONNECTIONS} />);

    // Every one of the four, and both halves of each read: what was written down, which is on
    // screen without a round trip, and what the forge says now, which is what makes the menu
    // right rather than merely quick.
    await waitFor(() => expect(asked()).toEqual(new Set(['c1', 'c2', 'c3', 'c4'])));
    expect(new Set(reads.stored.mock.calls.map(([id]) => id))).toEqual(
      new Set(['c1', 'c2', 'c3', 'c4']),
    );
    // And no dialog was opened to make it happen. This is the whole claim: the repo browser
    // finds the orgs already there because the console read them, not because opening it did.
    expect(screen.queryByRole('dialog')).toBeNull();
  });

  it('reads an installation that appears after the load, without being opened either', async () => {
    // The reported shape exactly: two connections at load, four a moment later, because the
    // adopt behind the other two had not resolved when the page read the list. Whatever puts
    // a row in that list, the repositories under it are read on sight.
    const client = stubClient();
    const { rerender } = render(
      <ShiprConsole client={client} connections={CONNECTIONS.slice(0, 2)} />,
    );
    await waitFor(() => expect(asked()).toEqual(new Set(['c1', 'c2'])));

    rerender(<ShiprConsole client={client} connections={CONNECTIONS} />);
    await waitFor(() => expect(asked()).toEqual(new Set(['c1', 'c2', 'c3', 'c4'])));
  });

  it('asks the forge AND the host again when the integrations pane says something changed', async () => {
    // Both, because they answer different questions and an integration can change either. The
    // host owns WHICH connections exist — a new installation is a new row and only a re-read
    // of the list has it. The catalogue owns what is INSIDE each one, and a grant added to an
    // installation that already existed changes no id at all: keyed on which connections
    // exist, the catalogue would go on offering the repositories from before the operator
    // granted the ones they opened that dialog to grant.
    window.history.replaceState(null, '', '/acme?workspace=acme#connections');
    const onConnectionsChanged = vi.fn();
    render(
      <ShiprConsole
        client={stubClient()}
        connections={CONNECTIONS.slice(0, 2)}
        onConnectionsChanged={onConnectionsChanged}
      />,
    );
    await waitFor(() => expect(asked()).toEqual(new Set(['c1', 'c2'])));
    await screen.findByTestId('integrations-pane');

    reads.fresh.mockClear();
    await act(async () => pane.onChanged!());

    await waitFor(() => expect(asked()).toEqual(new Set(['c1', 'c2'])));
    expect(onConnectionsChanged).toHaveBeenCalled();
  });
});
