/**
 * Env-var collection for the debug dialog. Isomorphic (no `'use client'`): the
 * host reads `process.env` on the SERVER and masks secret-named values HERE,
 * before the entries are handed to the client debug console — so a raw secret
 * never crosses to the browser, even though the dialog is dev-only.
 */
export type EnvVarEntry = {
    /** The env var name (e.g. `API_BACKEND_URL`). */
    name: string;
    /** Display value — already masked when `secret` is true. */
    value: string;
    /** Whether the name matched the secret heuristic (so the value is masked). */
    secret: boolean;
};
export declare function isSecretName(name: string): boolean;
/** First 4 chars + a fixed run of dots — enough to recognise, not to reuse. */
export declare function maskValue(value: string): string;
/**
 * Read each named env var via `read`, keep only the ones that are actually SET
 * (non-empty), and mask any whose name looks secret. Returns entries in the
 * given order. Call this on the server (`read = (n) => process.env[n]`) so raw
 * secrets are masked before they reach the client.
 */
export declare function collectEnvVars(names: readonly string[], read: (name: string) => string | undefined): EnvVarEntry[];
/**
 * Read a debug-env response body — `{ entries: EnvVarEntry[] }`, the contract both the
 * hub's `/api/public/debug-env` and the backend's `/api/system/debug-env` answer — or
 * `null` when the body is anything else.
 *
 * A reader, not a cast, because the Environment panel hands the result straight to a React
 * state setter, and a setter CALLS a function argument as an updater. A bare `[]` — what
 * the hub's e2e catch-all answers for every /api/ GET, and what any list-shaped error body
 * would be — has an inherited `entries`: the function `Array.prototype.entries`. The cast
 * read it, the setter ran it with no receiver, and the TypeError, thrown inside React's
 * render, took the whole page (header included) to the app's error boundary; the signed-out
 * Debug Options e2e in the hub's site-menu.spec.ts lost to it whenever the fetch beat the
 * dialog's visibility poll. A row off the contract is refused the same way, since an
 * object-valued `value` would throw in the list's JSX just as surely.
 */
export declare function parseEnvEntries(body: unknown): EnvVarEntry[] | null;
/**
 * The env vars the platform (shared code + hub) reads. Only the `NEXT_PUBLIC_*`
 * ones exist in the browser; the rest are server-only, so a debug view that wants
 * the full picture must read these on the SERVER (see `debugEnvEntries`).
 */
export declare const SITE_ENV_VARS: readonly ["DEPLOYMENT_ENV", "NEXT_PUBLIC_DEPLOYMENT_ENV", "API_BACKEND_URL", "NEXT_PUBLIC_AUTH_API_URL", "NODE_ENV", "DEBUG_MENU", "AI_CHAT", "NEXT_PUBLIC_DEV_FEATURE_FLAGS", "NEXT_PUBLIC_POSTHOG_KEY", "NEXT_PUBLIC_POSTHOG_HOST", "NEXT_PUBLIC_GLITCHTIP_DSN", "NEXT_PUBLIC_TELEMETRY_DEBUG"];
/**
 * The full set of {@link SITE_ENV_VARS} that are set, masked where secret. Reads
 * the real `process.env` — call this ON THE SERVER (a route handler) so both the
 * server-only vars are included and raw secrets are masked before they ship.
 */
export declare function debugEnvEntries(): EnvVarEntry[];
//# sourceMappingURL=env-vars.d.ts.map