<!-- leaf: implement-window-matching/window-discovery--edge-cases · source: window-matching-window-discovery.md -->

# WindowDiscoveryViewModel

**Rules** (cite as `implement-window-matching/window-discovery--edge-cases#<slug>`):

- `empty-project-name` MUST — projectName == "" — every window gets isMatch == false, so no app sorts first and the list is purely alphabetical …
- `unknown-project` MUST — projectName == "Unknown" (session with empty or / cwd) — same as empty: no window matches (MUST). A real project …
- `no-regular-apps-or-no-titled-windows` MUST — apps becomes an empty array and isLoading becomes false (MUST); no error or distinct empty state is published.
- `engine-returns-nothing` MUST — if the system window list cannot be read the engine returns an empty list, which yields an empty apps with no error …
- `titles-withheld` MUST — without Screen Recording, titles come from the engine's Accessibility backfill; a window the backfill cannot title …
- `permission-revoked-between-snapshot-and-enumeration` MUST — the gate has already passed; the engine's backfill then yields no titles for other apps, so those windows are dropped …
- `denied-after-a-successful-run` MUST — apps keeps the previous result while accessibilityDenied is true (MUST); hosts showing the denied state must hide the …
- `model-released-mid-discovery` MUST — if released before the background block starts, nothing is published (MUST); if released after, the main-queue block …
- `window-closed-before-activation` MUST — focus fails with the engine's window-not-found error, which is logged; onWindowActivated is not called (MUST).
- `app-cannot-be-activated` MUST — focus throws activation-failed; logged; callback not called (MUST).
- `parked-window` MUST — a window moved horizontally off every screen is moved to 80 points right of the main screen's visible-frame left edge …
- `equal-app-names` MAY — two apps with names equal under case-insensitive comparison have no defined relative order; the grouping dictionary's …
- `title-containing-the-project-name-without-heuristic-support` MUST — the raw-title fallback still matches substrings, so "MyAppTests" matches project "MyApp" (MUST); the match is …
- `concurrent-access` MUST — matches reads HeuristicRegistry.shared, which serialises its lookups under a lock, so matching on the background queue …
- `timeout` MUST — no timeout exists; a slow Accessibility backfill delays the publish with isLoading staying true (MUST, as implemented).

## Edge Cases

- **Empty project name**: `projectName == ""` — every window gets `isMatch == false`, so no app sorts first and the list is purely alphabetical (MUST).
- **Unknown project**: `projectName == "Unknown"` (session with empty or `/` cwd) — same as empty: no window matches (MUST). A real project literally named `Unknown` can never match; this is the sentinel's cost.
- **No regular apps or no titled windows**: `apps` becomes an empty array and `isLoading` becomes `false` (MUST); no error or distinct empty state is published.
- **Engine returns nothing**: if the system window list cannot be read the engine returns an empty list, which yields an empty `apps` with no error signal (MUST); the model cannot tell "no windows" from "list unavailable".
- **Titles withheld**: without Screen Recording, titles come from the engine's Accessibility backfill; a window the backfill cannot title stays empty and is dropped (MUST).
- **Permission revoked between snapshot and enumeration**: the gate has already passed; the engine's backfill then yields no titles for other apps, so those windows are dropped and `accessibilityDenied` stays `false` (MUST, as implemented).
- **Denied after a successful run**: `apps` keeps the previous result while `accessibilityDenied` is `true` (MUST); hosts showing the denied state must hide the stale list themselves.
- **Overlapping calls**: repeated `discoverWindows()` calls race; see the open question on overlapping-discovery-order.
- **Model released mid-discovery**: if released before the background block starts, nothing is published (MUST); if released after, the main-queue block holds the model strongly and still publishes (MUST).
- **Window closed before activation**: focus fails with the engine's window-not-found error, which is logged; `onWindowActivated` is not called (MUST).
- **App cannot be activated**: focus throws activation-failed; logged; callback not called (MUST).
- **Parked window**: a window moved horizontally off every screen is moved to 80 points right of the main screen's visible-frame left edge (Y unchanged) before being raised (MUST, engine behavior).
- **Equal app names**: two apps with names equal under case-insensitive comparison have no defined relative order; the grouping dictionary's iteration order decides (MAY vary between runs).
- **Title containing the project name without heuristic support**: the raw-title fallback still matches substrings, so `"MyAppTests"` matches project `"MyApp"` (MUST); the match is substring-based, not word-based.
- **Concurrent access**: `matches` reads `HeuristicRegistry.shared`, which serialises its lookups under a lock, so matching on the background queue is safe while custom rules change (MUST).
- **Offline or disconnected state**: not applicable — the model makes no network calls; all data is local system state.
- **Timeout**: no timeout exists; a slow Accessibility backfill delays the publish with `isLoading` staying `true` (MUST, as implemented).
