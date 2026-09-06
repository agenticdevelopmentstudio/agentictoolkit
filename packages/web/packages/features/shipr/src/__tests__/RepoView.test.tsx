import { describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';

import { RepoView } from '../RepoView';
import type { ShiprClient } from '../client';
import type { Group, Ladder, Repo, RepoDetail, Run } from '../types';

// Same reason as the console's own suite: what is under test is the SHAPE of the view, and
// a real EventSource in jsdom is a failure mode with no bearing on that.
vi.mock('../live', () => ({
  watchRun: () => ({ close: vi.fn() }),
  watchWorkspaceRuns: () => ({ close: vi.fn() }),
}));

const repo: Repo = {
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
};

const group: Group = {
  id: 'g1',
  parentId: null,
  name: 'adh',
  path: 'g1',
  depth: 0,
  position: 0,
};

const run: Run = {
  id: 'run1',
  operation: 'status',
  scopeKind: 'group',
  scopeId: 'g1',
  environments: [],
  state: 'succeeded',
  summary: null,
  startedAt: '2026-08-24 16:43:41.000000',
  finishedAt: '2026-08-24 16:43:49.378638',
  createdAt: '2026-08-24 16:43:40.000000',
  updatedAt: '2026-08-24 16:43:49.378638',
};

function stubClient(detail: RepoDetail): ShiprClient {
  return {
    repo: vi.fn().mockResolvedValue(detail),
    runDetail: vi.fn().mockResolvedValue({ steps: [] }),
    events: vi
      .fn()
      .mockResolvedValue({ events: [], nextSeq: 0, state: 'succeeded', done: true }),
  } as unknown as ShiprClient;
}

function detail(
  ladder: Ladder | null,
  over: Partial<RepoDetail> = {},
): RepoDetail {
  return { repo, devRepo: null, group: null, ladder, runs: [], ...over };
}

describe('RepoView — the two ways a ladder can be absent', () => {
  // The bug this exists for: a mirror that has just been registered or seeded has no
  // `repo_states` row, the route answers `ladder: null`, and a view that handed that
  // straight to <Ladder> died on `ladder.rows` and took the whole console down with it.
  // Every repository is in this state on the day it is added, so this is the FIRST thing
  // anyone sees, not an edge case.
  it('says nobody has looked yet, rather than throwing, when the ladder is null', async () => {
    render(<RepoView client={stubClient(detail(null))} repoId="m1" />);
    expect(await screen.findByText(/Never read/)).toBeTruthy();
  });

  // And the other absence keeps its own words: we DID look, and there was no history. A
  // view that said the same thing for both would let an unrefreshed read pass as a fact
  // about the repository.
  it('keeps "we looked and found nothing" distinct from "nobody has looked"', async () => {
    const empty: Ladder = { columns: ['main', 'ship'], rows: [], settled: false };
    render(<RepoView client={stubClient(detail(empty))} repoId="m1" />);
    expect(await screen.findByText(/No history to show/)).toBeTruthy();
    expect(screen.queryByText(/Never read/)).toBeNull();
  });

  it('still names the repository when there is no ladder to draw', async () => {
    render(<RepoView client={stubClient(detail(null))} repoId="m1" />);
    expect(
      await screen.findByRole('heading', { name: 'site-deployment' }),
    ).toBeTruthy();
  });

  // The names underneath — which branch is `ship`, which CI context is watched — are
  // reference material consulted when the ladder shows something surprising, and they sat
  // between the operator and the output the whole rest of the time. They live behind the
  // rail's Settings item now, so the view is the ladder and the output and nothing else.
  it('keeps the reference facts out of the view entirely', async () => {
    render(<RepoView client={stubClient(detail(null))} repoId="m1" />);
    await screen.findByRole('heading', { name: 'site-deployment' });
    expect(screen.queryByText('deploy/ci')).toBeNull();
    expect(screen.queryByText(/Gate context/i)).toBeNull();
    expect(screen.queryByText(/Ship branch/i)).toBeNull();
  });

  // An absence is not output. A repository nothing has been run against used to carry a
  // grey "Nothing has been run against this repository yet." shelf below its ladder — a line
  // of the answer spent saying there is no answer, under every unread repository in a folder
  // stack forty sections long. The ladder above already says "Never read"; saying it twice in
  // two vocabularies is what made the pane look like it was reporting a problem.
  it('draws no output block at all when there is nothing to report', async () => {
    render(<RepoView client={stubClient(detail(null))} repoId="m1" />);
    await screen.findByRole('heading', { name: 'site-deployment' });
    expect(screen.queryByRole('region', { name: 'Latest output' })).toBeNull();
    expect(screen.queryByText(/Nothing has been run/i)).toBeNull();
  });

  // The other half of the same rule, and the reason the one above is not simply "the report
  // was deleted": a run that DID say something is still read where the ladder is.
  it('ends in the report when the last run wrote something', async () => {
    // Scoped to THIS mirror, so the report shows the run's own narration rather than
    // narrowing to the steps of a folder-wide run — of which this repository has none.
    const mine = { ...run, scopeKind: 'deploy_repo' as const, scopeId: 'm1' };
    const client = stubClient(detail(null, { runs: [mine] }));
    (client.events as ReturnType<typeof vi.fn>).mockResolvedValue({
      events: [
        {
          id: 'e1',
          runId: 'run1',
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
    });
    render(<RepoView client={client} repoId="m1" />);
    await screen.findByRole('region', { name: 'Latest output' });
    expect(await screen.findByText(/read 6 branches/)).toBeTruthy();
  });
});

describe('RepoView — when the last run finished', () => {
  it('puts the time on the heading row, not in a sub-line under it', async () => {
    // It is the first fact a stack of these is read for, so it belongs in one scannable
    // column at the right edge rather than after a run's name, where its left edge moves.
    render(<RepoView client={stubClient(detail(null, { runs: [run] }))} repoId="m1" />);
    const stamp = await screen.findByText('2026-08-24 16:43:49.378638');
    const header = stamp.closest('header');
    expect(header).not.toBeNull();
    expect(header!.textContent).toContain('site-deployment');
  });

  it('shows no time at all for a repository nothing has ever been run against', async () => {
    render(<RepoView client={stubClient(detail(null))} repoId="m1" />);
    await screen.findByRole('heading', { name: 'site-deployment' });
    expect(screen.queryByText(/^2026-/)).toBeNull();
  });

  // The report below takes `runs[0]`, so reading the same head for the heading row's time
  // is what makes it the time of the output underneath rather than of some other run.
  it('does not label the output with the run’s operation', async () => {
    // A lone green STATUS used to stand over the log, under a repository whose ladder was
    // directly above it — a label for the thing the reader is already looking at (Mike).
    // Which repository is said by the heading row; what happened is said by the log's own
    // lines and by the dot in the rail.
    render(<RepoView client={stubClient(detail(null, { runs: [run] }))} repoId="m1" />);
    await screen.findByRole('region', { name: 'Latest output' });
    expect(screen.queryByRole('heading', { name: 'status' })).toBeNull();
  });
});

describe('RepoView — its own turn in a batch', () => {
  it('re-reads when the runner arrives and again when it leaves', async () => {
    // A folder-wide run is ONE queue entry, so a section that waited for the entry to finish
    // showed a stale ladder for the whole walk and then caught up with forty others at the
    // end. Each edge of `running` is this section's own turn changing (Mike: "update the
    // status dot before moving onto the next repo") and re-reads THIS section alone.
    const client = stubClient(detail(null, { runs: [run] }));
    const reads = () => (client.repo as ReturnType<typeof vi.fn>).mock.calls.length;
    const { rerender } = render(
      <RepoView client={client} repoId="m1" running={false} />,
    );
    await screen.findByRole('region', { name: 'Latest output' });
    expect(reads()).toBe(1);

    rerender(<RepoView client={client} repoId="m1" running />);
    await waitFor(() => expect(reads()).toBe(2));
    rerender(<RepoView client={client} repoId="m1" running={false} />);
    await waitFor(() => expect(reads()).toBe(3));
  });

  it('sits still while OTHER repositories are being walked', async () => {
    // The counter the pane hands down does not tick per step — that would be one read per
    // section per step. A re-render that changes nothing about this repository reads nothing.
    const client = stubClient(detail(null, { runs: [run] }));
    const reads = () => (client.repo as ReturnType<typeof vi.fn>).mock.calls.length;
    const { rerender } = render(
      <RepoView client={client} repoId="m1" running={false} />,
    );
    await screen.findByRole('region', { name: 'Latest output' });
    rerender(<RepoView client={client} repoId="m1" running={false} />);
    rerender(<RepoView client={client} repoId="m1" running={false} />);
    expect(reads()).toBe(1);
  });
});

describe('RepoView — alone versus one section of a folder', () => {
  it('heads the pane and names its folder when it stands alone', async () => {
    render(<RepoView client={stubClient(detail(null, { group }))} repoId="m1" />);
    expect(
      await screen.findByRole('heading', { level: 2, name: /site-deployment/ }),
    ).toBeTruthy();
    expect(screen.getByText('in adh')).toBeTruthy();
  });

  it('steps down a level and drops the folder inside a folder’s stack', async () => {
    // The pane's own header has just named the folder, and every section under it is in
    // that same folder — so repeating it once per repository says nothing.
    render(
      <RepoView
        client={stubClient(detail(null, { group }))}
        repoId="m1"
        relativePath=""
      />,
    );
    expect(
      await screen.findByRole('heading', { level: 3, name: /site-deployment/ }),
    ).toBeTruthy();
    expect(screen.queryByText('in adh')).toBeNull();
  });

  it('prefixes the sub-folders between the folder and the repository', async () => {
    // Two repositories called `web` in two sub-folders are one word apart, and the word is
    // the sub-folder — so a heading without the path is ambiguous exactly when it matters.
    render(
      <RepoView
        client={stubClient(detail(null))}
        repoId="m1"
        relativePath="marketing/europe"
      />,
    );
    expect(await screen.findByText('marketing/europe/')).toBeTruthy();
  });

  it('draws the LADDER in a folder’s stack too, not a bare log line', async () => {
    // The whole reason this component is shared: a repository used to look like two
    // different facts depending on which row was highlighted — its pipeline in colour in
    // its own pane, and one grey "no output here" in the folder's list.
    const ladder: Ladder = { columns: ['main', 'ship'], rows: [], settled: false };
    render(
      <RepoView client={stubClient(detail(ladder))} repoId="m1" relativePath="" />,
    );
    expect(await screen.findByText(/No history to show/)).toBeTruthy();
  });
});


describe('RepoView — a pressed button clears what it is about', () => {
  // Pressing a control remounts this pane, so the previous answer goes at once — and then
  // the re-read handed the SAME rows straight back, because `repo_states` still held what
  // the last `status` saw. The pane blinked and looked exactly as it had (Mike: "when
  // pressing a button the display should clear"). The ladder is DATED, so the question has
  // an answer: a run created after that read has not spoken for this repository yet.
  const rows: Ladder = {
    columns: ['main', 'ship'],
    rows: [],
    settled: false,
    readAt: '2026-08-24 16:00:00.000000',
  };
  const inFlight: Run = { ...run, state: 'running', createdAt: '2026-08-24 16:30:00.000000' };

  it('hides a ladder older than the run in flight', async () => {
    render(
      <RepoView client={stubClient(detail(rows, { runs: [inFlight] }))} repoId="m1" />,
    );
    // The heading renders either way, so waiting on it means the absence below is measured
    // after the read landed rather than before it.
    await screen.findByRole('heading', { level: 2, name: /site-deployment/ });
    expect(screen.queryByText(/No history to show/)).toBeNull();
    // And NOT the never-read line either: an empty slot, because the report underneath is
    // already saying it is waiting.
    expect(screen.queryByText(/Never read/)).toBeNull();
  });

  it('shows it again the moment the run has read THIS repository', async () => {
    // Per repository, not per run: a status over a folder of forty writes each read as it
    // reaches it, so the sections fill in one at a time behind the walking runner.
    const read: Ladder = { ...rows, readAt: '2026-08-24 16:30:05.000000' };
    render(
      <RepoView client={stubClient(detail(read, { runs: [inFlight] }))} repoId="m1" />,
    );
    expect(await screen.findByText(/No history to show/)).toBeTruthy();
  });

  it('leaves a finished run’s ladder alone however old the read is', async () => {
    // Nothing is coming, so the last thing anyone saw is the best answer there is — and
    // `prepare`/`deploy`, which invalidate a read without writing one, would otherwise
    // clear their sections forever rather than until the run ends.
    render(
      <RepoView client={stubClient(detail(rows, { runs: [run] }))} repoId="m1" />,
    );
    expect(await screen.findByText(/No history to show/)).toBeTruthy();
  });

  it('clears a never-read repository too while a run is in flight', async () => {
    // `NaN >= NaN` is false and the comparison is written as a negation for exactly this:
    // an absent stamp means nothing has been read, and the section must clear.
    render(
      <RepoView client={stubClient(detail(null, { runs: [inFlight] }))} repoId="m1" />,
    );
    await screen.findByRole('heading', { level: 2, name: /site-deployment/ });
    expect(screen.queryByText(/Never read/)).toBeNull();
  });
});
