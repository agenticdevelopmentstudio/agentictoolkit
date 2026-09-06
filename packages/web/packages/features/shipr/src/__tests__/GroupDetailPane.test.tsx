import { describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';

import { GroupDetailPane } from '../GroupDetailPane';
import type { ShiprClient } from '../client';
import type { Descendant } from '../tree/levels';
import type { RepoItem, Run } from '../types';

// Same reason as the console's own suite: what is under test is the SHAPE of the pane —
// how many sections, in what order, named how — and a real EventSource in jsdom is a
// failure mode with no bearing on that.
vi.mock('../live', () => ({
  watchRun: () => ({ close: vi.fn() }),
  watchWorkspaceRuns: () => ({ close: vi.fn() }),
}));

function repo(id: string, slug: string, shard = 'all'): RepoItem {
  return {
    id,
    devRepoId: `dev-${id}`,
    groupId: 'a',
    slug,
    shard,
    shipBranch: 'ship',
    ciContext: 'gate',
    envBranches: {},
    registeredAt: null,
    position: 0,
    devRepo: null,
    state: null,
  };
}

/** A finished run, per repository. The pane's sections draw a report only when there IS
 *  output to draw one of — an absence is not output — so a stub with no runs is a stub of a
 *  folder whose sections are all silent, which is a different pane from the one under test. */
function ranOn(id: string): Run {
  return {
    id: `run-${id}`,
    operation: 'status',
    scopeKind: 'deploy_repo',
    scopeId: id,
    environments: [],
    state: 'succeeded',
    summary: null,
    startedAt: '2026-08-24 16:43:41.000000',
    finishedAt: '2026-08-24 16:43:49.378638',
    createdAt: '2026-08-24 16:43:40.000000',
    updatedAt: '2026-08-24 16:43:49.378638',
  };
}

const contents: Descendant[] = [
  { repo: repo('r1', 'acme/one'), relativePath: '' },
  { repo: repo('r2', 'acme/two'), relativePath: 'marketing' },
  { repo: repo('r3', 'acme/three', 'eu'), relativePath: 'marketing/europe' },
];

function stubClient(over: Partial<ShiprClient> = {}): ShiprClient {
  return {
    // Per id, not one canned answer: the pane draws each section from the repository the
    // section is FOR, and a stub that hands every section the same document cannot tell a
    // pane that respects that from one that does not.
    repo: vi.fn((id: string) => {
      const found = contents.find((c) => c.repo.id === id)!.repo;
      return Promise.resolve({
        repo: found,
        devRepo: null,
        group: null,
        ladder: null,
        runs: [ranOn(id)],
      });
    }),
    runDetail: vi.fn().mockResolvedValue({ steps: [] }),
    events: vi.fn().mockResolvedValue({
      events: [
        {
          id: 'e1',
          runId: 'run',
          stepId: null,
          seq: 1,
          stream: 'out',
          text: 'read 6 branches',
          at: '2026-08-24 16:43:49.000000',
        },
      ],
      nextSeq: 1,
      state: 'succeeded',
      done: true,
    }),
    ...over,
  } as unknown as ShiprClient;
}

/** Every section's REPOSITORY heading, top to bottom — which, since the report under it
 *  stopped heading itself with the run's operation, is every level-3 heading in the pane. */
function repoHeadings(): string[] {
  return screen.getAllByRole('heading', { level: 3 }).map((h) => h.textContent ?? '');
}

describe('GroupDetailPane', () => {
  it('draws no title bar of its own — the stack above it already has one', () => {
    // The folder's name and its count used to be drawn at the top of this pane, immediately
    // below the stack's own strip: two title bars stacked, the upper one empty but for the
    // `«` that hides the rail (Mike). They are passed up as `detailTitle` now and drawn IN
    // that strip. What stays here is the accessible name, because "which folder" is still
    // what this region is.
    render(
      <GroupDetailPane client={stubClient()} title="fleet" contents={contents} />,
    );
    expect(screen.queryByRole('heading', { name: 'fleet' })).toBeNull();
    expect(screen.getByLabelText('fleet activity')).toBeTruthy();
  });

  it('draws each section as the SAME view a repository gets on its own', async () => {
    // The bug: a folder used to hang a bare output block under a heading of its own, so a
    // repository whose last run was folder-wide showed one grey "no output here" line here
    // and its whole pipeline in colour one click away. Same component now — which is why a
    // section that has never been read says so, exactly as the pane does.
    render(
      <GroupDetailPane client={stubClient()} title="fleet" contents={contents} />,
    );
    expect(await screen.findAllByText(/Never read/)).toHaveLength(3);
  });

  it('re-reads only the section the runner is inside, not all of them', async () => {
    // A folder-wide run is ONE queue entry, so a pane that re-read every section whenever
    // anything moved was forty reads per step across a batch of forty. Each section watches
    // its own turn instead (Mike: "we need to finish each repo one at a time ... update the
    // status dot before moving onto the next repo"), which is two reads apiece however long
    // the batch runs.
    const client = stubClient();
    const reads = () =>
      (client.repo as ReturnType<typeof vi.fn>).mock.calls.map(([id]) => id);
    const { rerender } = render(
      <GroupDetailPane
        client={client}
        title="fleet"
        contents={contents}
        runningRepoIds={new Set()}
      />,
    );
    await screen.findAllByRole('region', { name: 'Latest output' });
    expect(reads()).toEqual(['r1', 'r2', 'r3']);

    // The runner arrives at the second repository, then leaves it. Both edges are that
    // section's business and nobody else's.
    rerender(
      <GroupDetailPane
        client={client}
        title="fleet"
        contents={contents}
        runningRepoIds={new Set(['r2'])}
      />,
    );
    await waitFor(() => expect(reads()).toEqual(['r1', 'r2', 'r3', 'r2']));
    rerender(
      <GroupDetailPane
        client={client}
        title="fleet"
        contents={contents}
        runningRepoIds={new Set()}
      />,
    );
    await waitFor(() => expect(reads()).toEqual(['r1', 'r2', 'r3', 'r2', 'r2']));
  });

  it('stacks one report per repository — not a summary of them', async () => {
    // A folder is the unit people press Deploy on, so its pane answers "how did the batch
    // go", and the honest answer is every output rather than a chip standing in for them.
    render(
      <GroupDetailPane client={stubClient()} title="fleet" contents={contents} />,
    );
    expect(await screen.findAllByRole('region', { name: 'Latest output' })).toHaveLength(
      3,
    );
  });

  it('keeps rail order, which is the order the backend walks the folder in', async () => {
    // So the fourth section down is the fourth repository the run touched, and scrolling
    // during a batch is watching it move.
    render(
      <GroupDetailPane client={stubClient()} title="fleet" contents={contents} />,
    );
    await screen.findAllByRole('region', { name: 'Latest output' });
    expect(repoHeadings()).toEqual([
      'one',
      'marketing/two',
      'marketing/europe/three',
    ]);
  });

  it('prefixes the sub-folders between the folder and the repository', async () => {
    // Two repositories called `web` in two sub-folders are one word apart, and the word is
    // the sub-folder — so a heading without the path is ambiguous exactly when it matters.
    render(
      <GroupDetailPane client={stubClient()} title="fleet" contents={contents} />,
    );
    expect(await screen.findByText('marketing/europe/')).toBeTruthy();
    // A repository filed directly in the folder gets no prefix at all.
    expect(screen.queryByText('/one')).toBeNull();
  });

  it('asks each repository for its own latest run', async () => {
    const client = stubClient();
    render(
      <GroupDetailPane client={client} title="fleet" contents={contents} />,
    );
    await screen.findAllByRole('region', { name: 'Latest output' });
    expect((client.repo as ReturnType<typeof vi.fn>).mock.calls.map(([id]) => id)).toEqual(
      ['r1', 'r2', 'r3'],
    );
  });

  it('says where to start when the folder is empty, rather than nothing at all', () => {
    render(<GroupDetailPane client={stubClient()} title="fleet" contents={[]} />);
    expect(screen.getByText(/Nothing is filed in this folder yet/)).toBeTruthy();
    expect(screen.queryByRole('region', { name: 'Latest output' })).toBeNull();
  });
});
