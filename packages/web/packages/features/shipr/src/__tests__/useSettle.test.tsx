import { act, renderHook, waitFor } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

import { useSettle, type Runs } from '../activity/useRuns';
import type { ShiprClient } from '../client';
import type { EventPage, RunEvent, RunState } from '../types';

/**
 * THE DEFECT THIS FILE IS ABOUT.
 *
 * `POST /shipr/runs` answers 202, and 202 means QUEUED. A Provision button that resolved
 * on it therefore reported success for every run — the ones that went on to fail included
 * — and the failure landed in the run queue behind the modal the operator pressed the
 * button in. From the front of that dialog the button had done nothing at all (Mike: "the
 * provision button did nothing").
 *
 * So the press owns the whole run: `useSettle` resolves on `succeeded` and rejects with
 * the run's own last words otherwise, which is the shape the button already draws.
 */
const RUN = 'run-1';

/** A `Runs` whose only interesting answer is `stateOf` — the one thing `useSettle` reads. */
function runsSaying(state: RunState | null): Runs {
  return {
    items: [],
    loading: false,
    error: null,
    refresh: vi.fn(),
    stateOf: () => state,
  };
}

function event(seq: number, stream: RunEvent['stream'], text: string): RunEvent {
  return {
    id: `e${seq}`,
    runId: RUN,
    stepId: null,
    seq,
    stream,
    text,
    at: '2026-09-01T10:00:00Z',
  };
}

function page(events: RunEvent[], done = true): EventPage {
  return {
    events,
    nextSeq: events.at(-1)?.seq ?? 0,
    state: 'failed',
    done,
  };
}

/** Only `events` is ever called on the client here; the rest of the surface is unused. */
function clientReading(events: ShiprClient['events']): ShiprClient {
  return { events } as unknown as ShiprClient;
}

/** Drive the hook the way the console does: one `Runs` per render, replaced as ticks land. */
function mount(state: RunState | null, client: ShiprClient) {
  return renderHook(({ runs }: { runs: Runs }) => useSettle(client, runs), {
    initialProps: { runs: runsSaying(state) },
  });
}

/** Watch a promise without letting an early rejection reach the runner unhandled. */
function track<T>(promise: Promise<T>): { settled: () => boolean; promise: Promise<T> } {
  let settled = false;
  const watched = promise.then(
    (value) => {
      settled = true;
      return value;
    },
    (error) => {
      settled = true;
      throw error;
    },
  );
  // The caller asserts on `watched`; this second handler only keeps the runner quiet
  // during the deliberate window where nothing is awaiting it yet.
  watched.catch(() => {});
  return { settled: () => settled, promise: watched };
}

describe('useSettle', () => {
  it('does not settle while the run is still going', async () => {
    const events = vi.fn();
    const { result, rerender } = mount('queued', clientReading(events));

    const waited = track(result.current(RUN));
    await act(async () => {
      rerender({ runs: runsSaying('running') });
    });

    expect(waited.settled()).toBe(false);
    // The button is still busy, so nothing has gone looking for a failure to report.
    expect(events).not.toHaveBeenCalled();

    // Left resolved rather than pending, so the test does not end on a live promise.
    await act(async () => {
      rerender({ runs: runsSaying('succeeded') });
    });
    await expect(waited.promise).resolves.toBeUndefined();
  });

  it('resolves when the run reaches succeeded', async () => {
    const events = vi.fn();
    const { result, rerender } = mount('running', clientReading(events));

    const waited = track(result.current(RUN));
    await act(async () => {
      rerender({ runs: runsSaying('succeeded') });
    });

    await expect(waited.promise).resolves.toBeUndefined();
    expect(events).not.toHaveBeenCalled();
  });

  it('rejects with the run’s last error line when it fails', async () => {
    const events = vi.fn().mockResolvedValue(
      page([
        event(1, 'out', 'creating the deployment repository'),
        event(2, 'err', 'POST /orgs/DeploymentRepos/repos — the forge answered 403: Resource not accessible by integration'),
      ]),
    );
    const { result, rerender } = mount('running', clientReading(events));

    const waited = track(result.current(RUN));
    await act(async () => {
      rerender({ runs: runsSaying('failed') });
    });

    // The specific sentence — the endpoint and the organisation — exists only in the log,
    // which is why the post-mortem reads it rather than the run's status.
    await expect(waited.promise).rejects.toThrow(
      'POST /orgs/DeploymentRepos/repos — the forge answered 403: Resource not accessible by integration',
    );
  });

  it('takes the LAST error line, across pages', async () => {
    const events = vi
      .fn()
      .mockResolvedValueOnce(page([event(1, 'err', 'first thing that went wrong')], false))
      .mockResolvedValueOnce(page([event(2, 'err', 'the reason it gave up')], true));
    const { result, rerender } = mount('running', clientReading(events));

    const waited = track(result.current(RUN));
    await act(async () => {
      rerender({ runs: runsSaying('failed') });
    });

    await expect(waited.promise).rejects.toThrow('the reason it gave up');
    await waitFor(() => expect(events).toHaveBeenCalledTimes(2));
    // The second read continues from the cursor the first one handed back.
    expect(events.mock.calls[1]?.[1]).toBe(1);
  });

  it('points at the log when the run failed without writing to err', async () => {
    const events = vi.fn().mockResolvedValue(page([event(1, 'out', 'nothing useful')]));
    const { result, rerender } = mount('running', clientReading(events));

    const waited = track(result.current(RUN));
    await act(async () => {
      rerender({ runs: runsSaying('failed') });
    });

    await expect(waited.promise).rejects.toThrow(
      'The run failed. Its log says why — open it in the activity list.',
    );
  });

  it('says so plainly when the run was cancelled, and reads no log', async () => {
    const events = vi.fn();
    const { result, rerender } = mount('running', clientReading(events));

    const waited = track(result.current(RUN));
    await act(async () => {
      rerender({ runs: runsSaying('cancelled') });
    });

    await expect(waited.promise).rejects.toThrow(
      'The run was cancelled before it finished.',
    );
    expect(events).not.toHaveBeenCalled();
  });

  it('answers a run that is ALREADY terminal, with no further render', async () => {
    // The race the synchronous pre-check exists for: a promise parked in the waiting map
    // is only ever settled by a render, and a finished run may not cause another one.
    const events = vi.fn();
    const { result } = mount('succeeded', clientReading(events));

    await expect(result.current(RUN)).resolves.toBeUndefined();
  });

  it('reports a failure that had already landed before the wait began', async () => {
    const events = vi.fn().mockResolvedValue(page([event(1, 'err', 'it was already broken')]));
    const { result } = mount('failed', clientReading(events));

    await expect(result.current(RUN)).rejects.toThrow('it was already broken');
  });

  it('still reports the failure when the log cannot be read', async () => {
    const events = vi.fn().mockRejectedValue(new Error('offline'));
    const { result } = mount('failed', clientReading(events));

    // A run whose log this read could not fetch is still a run with a log.
    await expect(result.current(RUN)).rejects.toThrow(
      'The run failed. Its log says why — open it in the activity list.',
    );
  });

  it('settles each waiting run on the render that finishes it', async () => {
    // Two presses in one dialog — the batch case. Walking the map while settling it is
    // what the copy in the effect guards, so both must come back.
    const events = vi.fn().mockResolvedValue(page([event(1, 'err', 'that one failed')]));
    const states = new Map<string, RunState>([
      ['a', 'running'],
      ['b', 'running'],
    ]);
    const runsFrom = (): Runs => ({
      items: [],
      loading: false,
      error: null,
      refresh: vi.fn(),
      stateOf: (id: string) => states.get(id) ?? null,
    });
    const { result, rerender } = renderHook(
      ({ runs }: { runs: Runs }) => useSettle(clientReading(events), runs),
      { initialProps: { runs: runsFrom() } },
    );

    const first = track(result.current('a'));
    const second = track(result.current('b'));

    states.set('a', 'succeeded');
    states.set('b', 'failed');
    await act(async () => {
      rerender({ runs: runsFrom() });
    });

    await expect(first.promise).resolves.toBeUndefined();
    await expect(second.promise).rejects.toThrow('that one failed');
  });
});
