<!-- leaf: implement-window-matching/core-mac-os-system-windows--part-3 · source: window-matching-core-mac-os-system-windows.md -->

# SystemWindows Engine — continued (part 3)

**Rules** (cite as `implement-window-matching/core-mac-os-system-windows--part-3#<slug>`):

- `observer-start-idempotent` MUST
- `observer-start-snapshot` MUST
- `observer-start-apps` MUST
- `observer-ax-subscriptions` MUST
- `observer-one-per-pid` MUST
- `observer-create-failure` MUST
- `observer-stop` MUST
- `observer-deinit` MUST
- `observer-refresh` MUST
- `observer-delegate-weak` MUST
- `app-launched` MUST
- `app-launched-policy` MUST
- `app-terminated` MUST
- `window-created-baseline` MUST
- `window-created-report` MUST
- `window-destroyed` MUST
- `title-changed-match` MUST
- `title-changed-drop` MUST
- `focused-window-changed` MUST
- `observer-main-confinement` MUST
- `manager-non-sendable` MAY
- `helpers-stateless` MUST
- `no-timeouts` MUST
- `side-effects` MUST
- `no-persistence` MUST

### Observer lifecycle

- **observer-start-idempotent**: `startObserving()` MUST do nothing when already observing.
- **observer-start-snapshot**: `startObserving()` MUST snapshot known window ids per PID from `listAllWindows()` before subscribing.
- **observer-start-apps**: `startObserving()` MUST create one AX observer per running app that has a non-empty localized name and a regular activation policy.
- **observer-ax-subscriptions**: Each app observer MUST subscribe to window-created and focused-window-changed on the app element, and to element-destroyed and title-changed on each of the app's existing AX windows.
- **observer-one-per-pid**: The observer MUST NOT create a second AX observer for a PID that already has one.
- **observer-create-failure**: When AX observer creation fails for an app, the observer MUST skip that app silently.
- **observer-registration-errors**: NEEDS REVIEW: Not implemented in source. Every AX notification registration ignores its result code, so an app whose registrations fail (for example with Accessibility trust missing) is counted as monitored yet never reports window events; evidence needed is which registration errors the owner wants logged or surfaced.
- **observer-stop**: `stopObserving()` MUST do nothing when not observing; otherwise it MUST remove both workspace observers, remove every AX observer's run-loop source, clear all AX observers and clear the known-window snapshot.
- **observer-deinit**: Deallocating the observer MUST stop observation.
- **observer-refresh**: `refreshKnownWindows()` MUST replace the whole known-window snapshot with the ids from `listAllWindows()`, grouped by PID.
- **observer-delegate-weak**: The delegate MUST be held weakly; events with no delegate are dropped.

### Observer events

- **app-launched**: On an app launch with a non-nil localized name, the observer MUST, 1.0 second later and only if still observing, create an AX observer for the PID, refresh the snapshot, then call `appLaunched(appName:pid:)`.
- **app-launched-policy**: The launch path MUST NOT filter by activation policy or empty name, unlike `startObserving()`.
- **app-terminated**: On an app termination with a non-nil localized name, the observer MUST remove that PID's AX observer and snapshot entry, then call `appTerminated(appName:pid:)` synchronously.
- **window-created-baseline**: On a window-created notification the observer MUST subscribe the new window to destroyed and title-changed notifications and capture the baseline id set at once: the owning PID's known ids when the PID is readable, otherwise all known ids.
- **window-created-report**: 0.5 second later, only if still observing, the observer MUST list all windows, scope them to the PID when known, refresh the snapshot, and call `windowCreated(window:)` for each scoped window whose id is not in the baseline, in list order.
- **window-destroyed**: On an element-destroyed notification the observer MUST synchronously list all windows, refresh the snapshot, and call `windowDestroyed(windowID:)` for every previously known id no longer listed, across all apps.
- **title-changed-match**: On a title-changed notification the observer MUST read the element's title, position and size, and report `windowTitleChanged(windowID:newTitle:)` for the first listed window, scoped to the element's PID when readable, whose origin and size each lie within 2 points of the element's.
- **title-changed-drop**: When the title, position or size is unreadable, or no window matches, the title change MUST be dropped without a delegate call.
- **focused-window-changed**: On a focused-window-changed notification the observer MUST read the app's focused window and subscribe it to destroyed and title-changed notifications, relying on AX deduplication of repeated registrations.

### Concurrency

- **observer-main-confinement**: `SystemWindowObserver` MUST be used only on the main thread: it is declared `@unchecked Sendable` on the documented invariant that AX sources run on the main run loop, workspace observers use the main queue and delayed work hops through the main queue; callers of `startObserving()`, `stopObserving()` and `refreshKnownWindows()` MUST honor it.
- **manager-non-sendable**: `SystemWindowManager` is a public non-`Sendable` final class with no stored state, so the compiler keeps each instance in its isolation domain; list operations MAY run off the main thread, as `backfillTitles` documents.
- **helpers-stateless**: `SystemWindowAXHelper` and `SystemAccessibilityPermission` MUST hold no state; every call is independent.
- **no-timeouts**: Every operation MUST run synchronously with no AX messaging timeout of its own, no cancellation and no retry, so a call is bounded only by the system's default AX timeout.

### Side effects

- **side-effects**: Control operations MUST change only the targeted window's position, size, z-order and the owning app's activation; list operations and permission reads MUST have no side effect on other apps.
- **no-persistence**: The engine MUST NOT persist anything; the observer's snapshot lives only in memory.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `SystemWindowManager.init()` | — | — | No parameters; the manager is stateless. |
| `SystemWindowManager.excludedApps` | `Set<String>` (static let) | six system process names | Owner names dropped from enumeration. |
| `SystemWindowObserver.init(windowManager:)` | `SystemWindowControlling` | required | Window source used for snapshots and diffs; a mock can be injected. |
| `SystemWindowObserver.delegate` | `SystemWindowObserverDelegate?` (weak) | nil | Receives lifecycle events. |
| `SystemWindowAXHelper.axElement(for:windowInfo:)` `windowInfo` | `SystemWindowInfo?` | nil | Pre-fetched info; nil triggers a fresh window-list lookup. |
| Geometry tolerance | `CGFloat` (constant) | strictly less than 2 points | Position and size match tolerance for matching, backfill and title changes. |
| Match weights | `Int` (constants) | title 10, position 5, size 3, both-empty title 1 | `bestMatch` scoring. |
| Unpark x offset | `CGFloat` (constant) | 80 | Points right of the main screen's visible minX. |
| Launch delay | seconds (constant) | 1.0 | Wait before subscribing to a newly launched app. |
| Window-created delay | seconds (constant) | 0.5 | Wait before diffing for a new window. |

## Localization

`SystemWindowControlError.description` returns hardcoded English strings with no localization; the `accessibilityNotAvailable` text addresses the user.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none) | `No window found with CGWindowID <windowID>` | `windowNotFound` |
| (none) | `Accessibility not available for <app> (PID <pid>). Grant Accessibility permission in System Settings.` | `accessibilityNotAvailable` |
| (none) | `Failed to set <attribute>: AXError code <axError>` | `attributeSetFailed` |
| (none) | `Failed to activate <app> (PID <pid>)` | `activationFailed` |

## Privacy

- **Data collected**: Other apps' names, PIDs, window ids, titles (which often name documents, pages or paths), frames, displays and on-screen state.
- **Storage**: In memory only; the observer keeps window ids per PID, and nothing is written to disk.
- **Transmission**: None; data goes to the caller and the delegate. Log lines go to the unified log.
- **Retention**: For the life of the returned values and, for the observer snapshot, until the next refresh or `stopObserving()`.

