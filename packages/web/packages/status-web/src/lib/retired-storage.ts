/**
 * One-time cleanup of localStorage keys this app no longer reads.
 *
 * `use-live-snapshot.ts` used to persist the whole activity feed and rehydrate it
 * on mount (`persist` / `hydrateIfNeeded` / `clearActivity` / `STORAGE_KEY`). Those
 * were removed when the board became server-derived, but removing the WRITER does
 * not remove the DATA: every browser that ever loaded the old build still carries a
 * multi-hundred-KB dead blob, and it is the literal artifact of the bug this branch
 * was opened to fix — a phantom `hub-help-testing` problem that lived only in that
 * key, in one tab, and could not be cleared by any server-side fix.
 *
 * Each entry below is a RETIRED key: nothing in the app reads or writes it. Once a
 * release has been out long enough that every live tab has run this purge, the entry
 * (and eventually this module) can be deleted.
 */
const RETIRED_KEYS = [
  // The pre-server-derivation activity feed. Retired by the board rewrite.
  "adh-activity-v1",
] as const;

/**
 * Removes every retired key, and never throws. Safe to call during SSR (no
 * `window`) and in a context where storage is unavailable or denied — Safari
 * private browsing, a blocked third-party frame, a `localStorage`-disabled
 * profile. There is nothing to recover if it fails, and it must never be able to
 * break the board's mount.
 */
export function purgeRetiredStorage(): void {
  if (typeof window === "undefined") return;
  for (const key of RETIRED_KEYS) {
    try {
      window.localStorage.removeItem(key);
    } catch {
      // Storage unavailable/denied — leave the blob and carry on.
    }
  }
}
