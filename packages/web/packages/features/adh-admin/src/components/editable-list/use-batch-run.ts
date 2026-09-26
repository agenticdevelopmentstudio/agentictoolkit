"use client";

import * as React from "react";
import { useQueryClient, type QueryKey } from "@tanstack/react-query";
import type { ProgressError, ProgressResult } from "@agenticdevelopertoolkit/ui/blocks";

/**
 * Run one action over a SELECTION, one item at a time, halting on the first failure.
 *
 * Every button in an editable list's bar acts on a set of rows, which makes "do this to each of
 * them and tell me how far you got" the shape almost all of them need. It used to exist once, as
 * the transfer-only runner on the users page, and every other bulk action either fired a `map` of
 * mutations and reported nothing or was not offered at all.
 *
 * SEQUENTIAL is not politeness. Each item is its own transaction on the server, so a batch of ten
 * is ten transactions; firing them together keeps "which ones failed" answerable but destroys "how
 * far did it get", and that second number is the one that decides what the operator does next.
 *
 * HALTING is the same argument. The first failure is usually evidence about the REST of the batch
 * rather than about one row — a destination that rejects one email rejects the next, a permissions
 * problem fails identically for everyone behind it — so powering through would be deciding on the
 * operator's behalf that the remaining items should happen anyway. The loop stops, surfaces the
 * error, and waits for Continue or Stop.
 *
 * What already succeeded STAYS. Those transactions committed and cannot be undone from here, and
 * a report that implied otherwise would be the only real lie this hook could tell.
 */

/** One row a run will act on. The label is what the progress list and the halt message show. */
export interface BatchItem {
  id: string;
  label: string;
}

export interface BatchRunState {
  running: boolean;
  /** The run has ended — every item attempted, or the operator pressed Stop. */
  finished: boolean;
  total: number;
  /** Items that succeeded. The progress bar's numerator. */
  done: number;
  currentLabel?: string;
  /** Set while the run is HALTED on a failure, waiting for Continue or Stop. */
  error: ProgressError | null;
  results: ProgressResult[];
}

const IDLE: BatchRunState = {
  running: false,
  finished: false,
  total: 0,
  done: 0,
  error: null,
  results: [],
};

export interface UseBatchRunOptions {
  /**
   * Refetched once the run ends, however it ended.
   *
   * Even a run where every item FAILED leaves the list stale: a failure can be a 409 raised
   * because someone else's change landed first, which is a change this list has not seen either.
   */
  invalidateKey?: QueryKey;
  /** What a successful item reports in the results list. Defaults to "done". */
  successMessage?: string;
  /** What a failure with no message of its own reports. */
  failureMessage?: string;
}

export interface BatchRunController {
  /** Start a run. Resolves when the run ends — after the halt decisions, if there were any. */
  run: (items: BatchItem[], perform: (item: BatchItem) => Promise<unknown>) => Promise<void>;
  continueRun: () => void;
  stop: () => void;
  reset: () => void;
  state: BatchRunState;
}

export function useBatchRun({
  invalidateKey,
  successMessage = "done",
  failureMessage = "Failed",
}: UseBatchRunOptions = {}): BatchRunController {
  const qc = useQueryClient();
  const [state, setState] = React.useState<BatchRunState>(IDLE);
  // Resolves with the operator's choice at a halt. Held in a ref, not state, because the awaiting
  // loop closes over it once and must see the CURRENT resolver, not the one from its own render.
  const decide = React.useRef<((choice: "continue" | "stop") => void) | null>(null);

  // Is a run in flight? A ref, not `state.running`, because `run` closes over its own render and
  // would read a stale `false` from the very state it is about to set.
  const inFlight = React.useRef(false);

  const answer = React.useCallback((choice: "continue" | "stop") => {
    const resolve = decide.current;
    decide.current = null;
    // Clear the error as the loop resumes, so the modal's buttons cannot be pressed twice.
    setState((s) => ({ ...s, error: null }));
    resolve?.(choice);
  }, []);

  const continueRun = React.useCallback(() => answer("continue"), [answer]);
  const stop = React.useCallback(() => answer("stop"), [answer]);
  // Reset RELEASES a halted loop as well as clearing the report. A bare setState left the loop
  // parked on its promise forever, which is not merely untidy: everything after the loop —
  // including the invalidate that refetches the list the run just changed — is downstream of it.
  const reset = React.useCallback(() => {
    answer("stop");
    setState(IDLE);
  }, [answer]);

  // Unmount is the same argument as `reset`, arrived at by a different route: browser Back on a
  // halted run swaps the page out from under the modal and nothing is left to press Continue or
  // Stop. Without this the loop never reaches its `invalidateQueries`, so the shared QueryClient
  // goes on serving pre-run rows for the items that DID succeed, across client-side navigation —
  // a list that quietly disagrees with the database and never refetches to find out.
  React.useEffect(
    () => () => {
      decide.current?.("stop");
      decide.current = null;
    },
    [],
  );

  const run = React.useCallback(
    async (items: BatchItem[], perform: (item: BatchItem) => Promise<unknown>) => {
      // NOTHING TO DO IS NOT A RUN. Every caller's guard is "is the selection empty", which is a
      // different question from "does any selected row need this" — a bar that skips rows already
      // in the target state (and they all should) can reach here with an empty list. Starting
      // anyway opened a blocking progress modal reporting 0 of 0 done, which asks the operator to
      // acknowledge a run that never happened.
      if (items.length === 0) return;
      // A second run over the same controller would share one `decide` ref and one state, so the
      // first loop's halt could be answered by the second's modal. Refused rather than queued:
      // the buttons that start runs are in a bar the operator can press twice.
      if (inFlight.current) return;
      inFlight.current = true;
      setState({ ...IDLE, running: true, total: items.length });
      const results: ProgressResult[] = [];
      let done = 0;

      try {
        for (const item of items) {
          setState((s) => ({ ...s, currentLabel: item.label }));
          try {
            await perform(item);
            done += 1;
            results.push({ id: item.id, label: item.label, status: "ok", message: successMessage });
            setState((s) => ({ ...s, done, results: [...results] }));
          } catch (e) {
            const message = e instanceof Error ? e.message : failureMessage;
            results.push({ id: item.id, label: item.label, status: "failed", message });
            setState((s) => ({
              ...s,
              results: [...results],
              currentLabel: undefined,
              error: { message, itemLabel: item.label },
            }));
            const choice = await new Promise<"continue" | "stop">((resolve) => {
              decide.current = resolve;
            });
            if (choice === "stop") break;
          }
        }

        setState((s) => ({
          ...s,
          running: false,
          finished: true,
          error: null,
          currentLabel: undefined,
        }));
        if (invalidateKey) await qc.invalidateQueries({ queryKey: invalidateKey });
      } finally {
        // In a `finally` because the alternative is a controller that can never run again: an
        // invalidate that rejects, or an unmount that resolved the halt promise out from under the
        // loop, would otherwise leave `inFlight` stuck true for the life of the component.
        inFlight.current = false;
        decide.current = null;
      }
    },
    [qc, invalidateKey, successMessage, failureMessage],
  );

  return { run, continueRun, stop, reset, state };
}
