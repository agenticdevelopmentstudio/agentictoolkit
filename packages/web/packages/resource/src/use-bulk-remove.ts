"use client";

import { useCallback, useState } from "react";

export interface BulkRemove<T> {
  /** The rows the confirm is about — `null` while it is closed. */
  targets: T[] | null;
  /** Why the last attempt did not remove everything; shown inside the still-open confirm. */
  error: string | null;
  pending: boolean;
  /** The bar's Delete: open the confirm for these rows. */
  open: (rows: T[]) => void;
  /** The confirm's destructive button. */
  confirm: () => void;
  /** The confirm's Cancel. */
  cancel: () => void;
}

/**
 * The state behind a `ListBarActions` Delete: the ticked rows it was pressed for, the confirm that
 * names them, and a removal that is honest about a PARTIAL failure.
 *
 * One hook because five settings lists (tokens, contacts, passkeys, social links, addresses) each
 * carried their own copy, and every copy made the same mistake: `Promise.all` over the targets.
 * Tick A and B, A's DELETE lands and B's fails — `all` rejects, the confirm stays open still
 * naming A, and the retry re-sends DELETE for a row that is gone, which 404s, which rejects again:
 * a confirm that can never succeed until Cancel. So:
 *
 *   • `allSettled`, not `all` — the first rejection must not abandon the rest, which are already
 *     in flight and will land whether or not anyone listens (and `pending` must not clear while
 *     they are still running);
 *   • after a partial failure the confirm narrows to exactly the rows that failed, so it names
 *     only what is still there and a second press retries only those;
 *   • `onSettled` runs EITHER way, because either way something may have changed on the server.
 */
export function useBulkRemove<T>({
  getId,
  remove,
  onSettled,
  onDone,
  errorMessage,
}: {
  getId: (row: T) => string;
  remove: (id: string) => Promise<unknown>;
  /** Re-read the list — after every attempt, whole or partial. */
  onSettled: () => void;
  /** Everything went: clear the selection, say so. */
  onDone?: () => void;
  /** One failure's message, in the caller's own words for this kind of row. */
  errorMessage: (err: unknown) => string;
}): BulkRemove<T> {
  const [targets, setTargets] = useState<T[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  const open = useCallback((rows: T[]) => {
    setError(null);
    setTargets(rows);
  }, []);

  const cancel = useCallback(() => {
    if (pending) return;
    setTargets(null);
    setError(null);
  }, [pending]);

  const confirm = useCallback(() => {
    if (!targets || pending) return;
    const rows = targets;
    setError(null);
    setPending(true);
    void (async () => {
      const results = await Promise.allSettled(rows.map((row) => remove(getId(row))));
      const failed = rows.filter((_, i) => results[i]?.status === "rejected");
      setPending(false);
      onSettled();
      if (failed.length === 0) {
        setTargets(null);
        onDone?.();
        return;
      }
      const first = results.find((r) => r.status === "rejected") as PromiseRejectedResult;
      const why = errorMessage(first.reason);
      setTargets(failed);
      setError(
        rows.length > 1 ? `${failed.length} of ${rows.length} could not be removed: ${why}` : why,
      );
    })();
  }, [targets, pending, remove, getId, onSettled, onDone, errorMessage]);

  return { targets, error, pending, open, confirm, cancel };
}
