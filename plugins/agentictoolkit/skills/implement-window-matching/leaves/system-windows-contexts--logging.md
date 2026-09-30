<!-- leaf: implement-window-matching/system-windows-contexts--logging · source: window-matching-system-windows-contexts.md -->

# Window Matching System Windows Contexts

## Logging

Subsystem: main bundle identifier (`Loggable.subsystem`) | Category: the type name (`SystemWindowContextStore`, `SystemWindowContextManager`, `SystemWindowContextsModel`)

| Event | Level | Message |
|-------|-------|---------|
| Store created | info | `SystemWindowContextStore initialized at <path>` |
| Context file skipped on load | error | `Skipping context <id>: <error>` |
| Manager load start / end | info | `Loading state from disk` / `Loaded <n> contexts, active: <uuid or none>` |
| Stale IDs cleared | info | `Invalidated <n> stale window ID(s) on load` |
| Context created / deleting / deleted | info | `Created context '<name>' (<id>)` / `Deleting context '<name>' (<n> windows)` / `Deleted context '<name>'` |
| Window added | info | `Added window <id> to '<name>'` |
| Switch | info | `Switching context: '<from>' -> '<to>'` / `Switch complete -> '<to>'` |
| Window dormant / app terminated | info | `Window <id> marked dormant in '<name>'` / `App '<app>' terminated, <n> windows marked dormant` |
| App re-matched / auto-assigned | info | `App '<app>' launched, re-matched <n> dormant windows` / `Auto-assigned <id> to '<name>' (score <n>)` |
| Rules load failed | error | `Failed to load custom heuristic rules: <error>` |
| Persist failed | error | `Failed to persist state: <error>` |
| Model operation failed | error | the same text as `lastError` |
| Default contexts | info / error | `Created <n> default contexts` / `Failed to create default context '<name>': <error>` |
| Reconciliation | info | `No stale windows detected, skipping reconciliation.` / `<n> unmatched windows need assignment.` / `All stale windows auto-matched successfully.` |
| Batch add skip / summary | debug / info | `Skipped window <id> during batch add: <error>` / `Batch-added <n>/<m> windows to context` |
| Hidden apps | debug | `Added '<app>' to hidden apps filter.` / `Removed '<app>' from hidden apps filter.` |
| Observation disabled | debug | `Window observation disabled (test environment).` |

Window-controller failures (move, set frame, focus) and notification authorization results are not logged.
