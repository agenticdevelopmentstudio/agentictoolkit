"use client";
import { useCallback, useState } from "react";
import { msg } from "../../lib/err";

/**
 * Shared busy/error guard for the Config editor sections (Groups / Sites /
 * Platforms). `run` flips `busy` for the duration of an async mutation, surfaces
 * any thrown error as `error`, and clears `busy` in a `finally` so a rejection
 * can't leave the toolbar permanently disabled. One source of truth for the
 * save/delete plumbing the three sections used to each re-implement (or omit).
 */
export interface EditorMutations {
  busy: boolean;
  error: string | null;
  setError: (msg: string | null) => void;
  /** Run an async mutation with busy/error handling. */
  run: (fn: () => Promise<void>) => Promise<void>;
}

export function useEditorMutations(): EditorMutations {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const run = useCallback(async (fn: () => Promise<void>): Promise<void> => {
    setBusy(true);
    setError(null);
    try {
      await fn();
    } catch (e) {
      setError(msg(e));
    } finally {
      setBusy(false);
    }
  }, []);

  return { busy, error, setError, run };
}
