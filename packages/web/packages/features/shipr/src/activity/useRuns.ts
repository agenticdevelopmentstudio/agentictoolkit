'use client';

import * as React from 'react';

import type { ShiprClient } from '../client';
import { watchWorkspaceRuns, type RunTick } from '../live';
import { TERMINAL_STATES, type Run } from '../types';

/**
 * The workspace's runs, live.
 *
 * Two jobs, and they are the same read: it fills the run picker, and it tells the console
 * when a queued run has FINISHED so the next one in a batch can start. Doing that from the
 * workspace channel rather than from each run's own log means a batch of eleven repositories
 * costs one subscription instead of eleven, and a run somebody else started shows up here
 * too — which is the point of a shared pipeline.
 *
 * A tick carries identity and state, never output. When it names a run this hook has never
 * seen — someone else just started one — the list is re-read rather than reconstructed from
 * the tick, because a tick is deliberately not a whole `Run` and inventing the missing
 * fields would put a row in the picker that says things no server ever said.
 */
export interface Runs {
  /** Newest first — the order `GET /runs` answers in. */
  items: Run[];
  /** True until the first read settles, so a picker can stay quiet rather than flash empty. */
  loading: boolean;
  error: string | null;
  refresh: () => void;
  /** The run's state if it is known here, else null. */
  stateOf: (runId: string) => Run['state'] | null;
}

export function useRuns(client: ShiprClient, limit?: number): Runs {
  const clientRef = React.useRef(client);
  clientRef.current = client;

  // Bump to force a re-read. A counter rather than a callback in a dep array: the effect
  // below owns the fetch, and a caller's `refresh()` is just a request for another turn of it.
  const [nonce, setNonce] = React.useState(0);
  const refresh = React.useCallback(() => setNonce((n) => n + 1), []);

  const workspace = client.workspace;

  // The rows and the workspace they are rows OF, as one value — the same rule `useTree`
  // follows and for the same reason: a run list is per-tenant, and holding the two
  // separately is what would let a workspace change leave the previous one's runs on the
  // screen for as long as the next read takes.
  const [landed, setLanded] = React.useState<{
    workspace: string | undefined;
    items: Run[];
  }>({ workspace, items: [] });
  const [loading, setLoading] = React.useState(true);
  const [error, setError] = React.useState<string | null>(null);

  // The list as the last render left it, for the one reader that must ask a question of it
  // OUTSIDE a state updater — see `apply` below.
  const landedRef = React.useRef(landed);
  landedRef.current = landed;

  React.useEffect(() => {
    let closed = false;
    void (async () => {
      try {
        const page = await clientRef.current.runs(limit);
        if (closed) return;
        setLanded({ workspace, items: page.items });
        setError(null);
      } catch (e) {
        if (!closed) setError((e as Error).message);
      } finally {
        if (!closed) setLoading(false);
      }
    })();
    return () => {
      closed = true;
    };
  }, [nonce, limit, workspace]);

  React.useEffect(() => {
    let closed = false;

    const apply = (tick: RunTick) => {
      if (closed) return;

      // ASKED BEFORE THE WRITE, AND OUTSIDE IT. This used to be a flag the updater below set
      // and this line read afterwards, which a state updater cannot be trusted to have run
      // by then: React only applies one eagerly when the queue is empty and otherwise defers
      // it to render, and StrictMode invokes it twice. What the flag decides is whether a run
      // SOMEBODY ELSE started is re-read — the hook's stated reason for re-reading at all —
      // so getting it wrong is a run that never appears in the picker.
      const seen = landedRef.current;
      const known =
        seen.workspace === workspace && seen.items.some((run) => run.id === tick.id);

      setLanded((prev) => {
        // A tick that arrives after the workspace changed belongs to the stream we are
        // tearing down, not to the list on the screen.
        if (prev.workspace !== workspace) return prev;
        return {
          ...prev,
          items: prev.items.map((run) =>
            run.id === tick.id
              ? // Only what a tick actually asserts. `startedAt`/`finishedAt`/`summary` are
                // not on the wire here, and guessing them from the state ("it says
                // succeeded, so it must have finished now") would put a fabricated
                // timestamp on the screen.
                { ...run, state: tick.state, updatedAt: tick.updatedAt }
              : run,
          ),
        };
      });

      if (!known) refresh();
    };

    const handle = watchWorkspaceRuns({
      workspace,
      onRun: apply,
      onPoll: refresh,
    });
    return () => {
      closed = true;
      handle.close();
    };
  }, [workspace, refresh]);

  // Rows from another workspace read as NO rows — see `useTree`'s guard.
  const items = landed.workspace === workspace ? landed.items : EMPTY_RUNS;

  const stateOf = React.useCallback(
    (runId: string) => items.find((r) => r.id === runId)?.state ?? null,
    [items],
  );

  return { items, loading, error, refresh, stateOf };
}

/** One frozen empty list, so the guard above returns a STABLE value — a fresh `[]` every
 *  render would re-run every memo downstream of it. */
const EMPTY_RUNS: Run[] = [];

/** Has this run stopped? Unknown runs read as NOT finished — a queue that advanced past a
 *  run it has not heard of yet would start two at once. */
export function isFinished(runs: Runs, runId: string): boolean {
  const state = runs.stateOf(runId);
  return state !== null && TERMINAL_STATES.includes(state);
}

/**
 * HOW MANY PAGES OF LOG A POST-MORTEM READS BEFORE IT GIVES UP.
 *
 * A `register` writes tens of lines, so one page is the whole story; the cap is here
 * because the loop advances on a cursor the server hands back, and a server that stopped
 * advancing it would otherwise be read forever by a browser nobody is watching.
 */
const MAX_POST_MORTEM_PAGES = 20;

/**
 * WAIT FOR A RUN TO FINISH, AND THROW WHAT IT SAID IF IT DID NOT.
 *
 * A press that starts a run gets a 202 back in a few milliseconds, and 202 means QUEUED,
 * not done. A button that resolved on it therefore reported success for every run — the
 * ones that went on to fail included — and the failure landed in the run queue, behind
 * whatever modal the operator pressed the button in. From the front of that dialog the
 * button had done nothing at all (Mike: "the provision button did nothing").
 *
 * So the press owns the whole run. This resolves when the run reaches `succeeded`, and
 * REJECTS with the run's own last words otherwise — which is the shape every button in
 * this feature already handles, because they all already catch and draw the rejection of
 * the call that started the run.
 *
 * IT WATCHES THE LIST, IT DOES NOT POLL. `useRuns` is already subscribed to the workspace
 * channel and already re-reads on a tick naming a run it has not seen; a second poller per
 * pressed button would be one more subscription per press for a fact already on screen.
 * The effect below has NO dependency array on purpose: every render of the console is a
 * chance that the state changed, and when nothing is waiting it costs a map lookup.
 */
export function useSettle(
  client: ShiprClient,
  runs: Runs,
): (runId: string) => Promise<void> {
  const clientRef = React.useRef(client);
  clientRef.current = client;
  const runsRef = React.useRef(runs);
  runsRef.current = runs;

  /**
   * The parked waits, by run id — a REJECT beside every resolve.
   *
   * A promise in here is settled by a LATER RENDER of this hook, so it survives only as long
   * as the renders do. Every route by which they stop is a wait nobody will ever settle: the
   * workspace changes and the run stream this reads is torn down; the console unmounts; a
   * second press parks a second wait on the same run id and silently evicts the first. Each
   * one left `await settle(runId)` pending forever, and the press that awaited it is a button
   * inside a modal — it stayed on "Provisioning…" until the page was reloaded, which is the
   * shape of the original "the provision button did nothing" this whole helper exists to fix.
   *
   * So every one of them rejects. A rejection is a verdict the callers already draw; a
   * promise that never settles is the one outcome none of them can say anything about.
   */
  const waiting = React.useRef(
    new Map<
      string,
      { resolve: (state: Run['state']) => void; reject: (reason: Error) => void }
    >(),
  );

  React.useEffect(() => {
    if (waiting.current.size === 0) return;
    // Copied before walking: settling one drops it from the map being iterated.
    for (const [runId, waiter] of [...waiting.current]) {
      const state = runs.stateOf(runId);
      if (state === null || !TERMINAL_STATES.includes(state)) continue;
      waiting.current.delete(runId);
      waiter.resolve(state);
    }
  });

  // THE END OF THE WATCH IS THE END OF EVERY WAIT PARKED AGAINST IT. `useRuns` re-subscribes
  // on a workspace change, and the runs of the old one stop being reported here at all;
  // unmounting runs this same cleanup. Either way the waits below can never be settled, and
  // the operator is owed the reason rather than a spinner.
  const workspace = client.workspace;
  React.useEffect(() => {
    const parked = waiting.current;
    return () => {
      if (parked.size === 0) return;
      const orphaned = [...parked.values()];
      parked.clear();
      for (const waiter of orphaned) {
        waiter.reject(
          new Error(
            'Stopped watching this run before it finished — open it in the activity list to see how it ended.',
          ),
        );
      }
    };
  }, [workspace]);

  return React.useCallback(async (runId: string) => {
    // Asked BEFORE waiting, because a promise parked in the map is only ever settled by a
    // render, and a run that is already terminal may not cause another one.
    const known = runsRef.current.stateOf(runId);
    const state =
      known !== null && TERMINAL_STATES.includes(known)
        ? known
        : await new Promise<Run['state']>((resolve, reject) => {
            // A SECOND WAIT ON THIS RUN DISPLACES THE FIRST — the map is keyed by run id, so
            // it always did; the only question was whether the displaced caller was ever
            // told. It is one press arriving while another is still out, and the press that
            // lost is still a button somebody is watching.
            waiting.current
              .get(runId)
              ?.reject(new Error('Another wait on this run replaced this one.'));
            waiting.current.set(runId, { resolve, reject });
          });
    if (state === 'succeeded') return;
    throw new Error(await verdictText(clientRef.current, runId, state));
  }, []);
}

/** What to put in front of the operator when a run they started did not succeed. */
async function verdictText(
  client: ShiprClient,
  runId: string,
  state: Run['state'],
): Promise<string> {
  if (state === 'cancelled') return 'The run was cancelled before it finished.';
  const said = await lastError(client, runId);
  // The generic sentence points somewhere rather than apologising: a run whose log this
  // read could not fetch is still a run with a log.
  return said ?? 'The run failed. Its log says why — open it in the activity list.';
}

/**
 * The LAST thing a run wrote to `err`.
 *
 * The last and not the first: a failing step's own message is what the runner writes as it
 * gives up, and the lines before it are the ones it wrote on the way there. Reading the
 * log rather than the run's `summary` is what makes the sentence specific — the 403 that
 * started all this named the endpoint and the organisation, and no status field does.
 */
async function lastError(
  client: ShiprClient,
  runId: string,
): Promise<string | null> {
  let after = 0;
  let found: string | null = null;
  for (let page = 0; page < MAX_POST_MORTEM_PAGES; page += 1) {
    const got = await client.events(runId, after).catch(() => null);
    if (!got) break;
    for (const event of got.events) {
      const text = event.stream === 'err' ? event.text.trim() : '';
      if (text) found = text;
    }
    // `nextSeq` not advancing is the one way this loop could spin without the cap.
    if (got.done || got.events.length === 0 || got.nextSeq <= after) break;
    after = got.nextSeq;
  }
  return found;
}
