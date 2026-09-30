<!-- leaf: implement-window-matching/window-discovery · source: window-matching-window-discovery.md -->

**Rules** (cite as `implement-window-matching/window-discovery#<slug>`):

- `discovered-window-shape` MUST
- `discovered-app-shape` MUST
- `app-has-match` MUST
- `published-state` MUST
- `session-exposed` MUST
- `discovery-resets-flags` MUST
- `discovery-permission-gate` MUST
- `denied-keeps-apps` MUST
- `permission-check-no-prompt` MUST
- `app-snapshot-on-caller-thread` MUST
- `regular-apps-only` MUST
- `unknown-app-name` MUST
- `project-name-captured` MUST
- `enumeration-off-caller-thread` MUST
- `results-published-on-main` MUST
- `weak-owner` MUST
- `no-cancellation-or-timeout` MUST
- `all-windows-source` MUST
- `title-backfill-inherited` MUST
- `untitled-windows-dropped` MUST
- `foreign-pid-dropped` MUST
- `group-by-pid` MUST
- `window-order-preserved` MUST
- `windowless-apps-omitted` MUST
- `duplicate-pid-first-wins` MUST
- `match-first-sort` MUST
- `alphabetical-sort` MUST
- `match-is-pure-static` MUST
- `empty-project-never-matches` MUST
- `unknown-project-never-matches` MUST
- `heuristic-pattern` MUST
- `raw-title-fallback` MUST
- `pattern-or-title-contains` MUST
- `activation-logs-intent` MUST
- `activation-focuses-by-id` MUST
- `activation-success-callback` MUST
- `activation-failure-logged` MUST
- `activation-failure-no-callback` MUST
- `activation-error-not-rethrown` MUST
- `activation-synchronous` MUST
- `stale-window-not-rediscovered` MUST
- `settings-request` MUST
- `settings-no-refresh` MUST
- `unchecked-sendable` MUST
- `main-thread-caller` MUST
- `value-types-not-sendable` MUST

# WindowDiscoveryViewModel

## Overview

`WindowDiscoveryViewModel` (in `WindowDiscoveryViewModel.swift`, with its value
types `DiscoveredWindow` and `DiscoveredApp`) backs the macOS Window Discovery
panel. Given a `SessionWatcher.SessionWatcherSession`, it:

- enumerates every window the `SystemWindowManager` engine reports — including
  minimized and off-screen windows — and keeps the titled ones owned by regular
  (Dock-visible) applications;
- groups them by owning process into `DiscoveredApp` values carrying the app's
  localized name and icon;
- flags each window whose title matches the session's `projectName`, using the
  per-app title heuristic from `HeuristicRegistry.shared` with a raw-title
  fallback (the static `matches(window:projectName:)`);
- sorts apps with a match first, then alphabetically;
- focuses a chosen window through the engine and tells its host when the focus
  succeeded so the panel can close.

It needs only Accessibility permission. When the system window list omits a
title (it does for other apps without Screen Recording permission), the engine
backfills it from the Accessibility API before this model sees it.

Use it when a UI needs a "which window belongs to this session?" chooser. It
is an `ObservableObject`; the host binds to its three `@Published` properties.

## Behavioral Requirements

### Data shapes

- **discovered-window-shape**: `DiscoveredWindow` MUST be an `Identifiable` value with `id: CGWindowID` (the system window number, used to focus the window), `title: String`, `pid: pid_t` and `isMatch: Bool`, all immutable.
- **discovered-app-shape**: `DiscoveredApp` MUST be an `Identifiable` value with `id: pid_t`, `name: String`, `icon: NSImage?` and `windows: [DiscoveredWindow]`, all immutable.
- **app-has-match**: `DiscoveredApp.hasMatch` MUST be a computed property that is `true` exactly when at least one element of `windows` has `isMatch == true`.
- **published-state**: The model MUST publish three observable properties: `isLoading: Bool` (initially `true`), `apps: [DiscoveredApp]` (initially empty) and `accessibilityDenied: Bool` (initially `false`).
- **session-exposed**: The model MUST expose the `session` it was initialised with as an immutable public property; `init(session:)` MUST NOT start discovery.

### Discovery (`discoverWindows()`)

- **discovery-resets-flags**: `discoverWindows()` MUST set `isLoading` to `true` and `accessibilityDenied` to `false` before any other work.
- **discovery-permission-gate**: When `SystemAccessibilityPermission.isGranted` is `false`, `discoverWindows()` MUST set `isLoading` to `false` and `accessibilityDenied` to `true` synchronously and return without enumerating windows.
- **denied-keeps-apps**: On the permission-denied path, `discoverWindows()` MUST leave `apps` unchanged; it does not clear a previous result.
- **permission-check-no-prompt**: The permission gate MUST only read the trust state; it MUST NOT show the system Accessibility prompt.
- **app-snapshot-on-caller-thread**: `discoverWindows()` MUST snapshot the running applications (pid, localized name, icon) synchronously on the calling thread before dispatching any background work.
- **regular-apps-only**: The snapshot MUST include only applications whose activation policy is regular (Dock-visible apps); accessory and background-only processes MUST be excluded.
- **unknown-app-name**: An application with no localized name MUST be snapshotted with the name `"Unknown"`.
- **project-name-captured**: `discoverWindows()` MUST read `session.projectName` once, on the calling thread, and match every window against that captured value.
- **enumeration-off-caller-thread**: Window enumeration and matching MUST run on a global background queue at user-initiated quality of service, not on the calling thread.
- **results-published-on-main**: The grouped result MUST be assigned to `apps`, and `isLoading` set to `false`, on the main queue in a single main-queue block, `apps` first.
- **weak-owner**: The background work MUST hold the model weakly; when the model has been deallocated before the work starts, nothing MUST be enumerated or published.
- **no-cancellation-or-timeout**: Discovery MUST NOT offer cancellation or a timeout; once dispatched, the enumeration runs to completion and publishes.
- **overlapping-discovery-order**: NEEDS REVIEW: Not implemented in source. Two overlapping `discoverWindows()` calls each dispatch independent background work and each publish on completion, so `apps` ends with whichever enumeration finishes last (not the last one started) and `isLoading` turns `false` when the first finishes; the source has no generation token or serialisation. Settling it needs an owner decision on whether the latest call must win.

### Enumeration and grouping

- **all-windows-source**: Enumeration MUST use the engine's full window list (`SystemWindowManager.listAllWindows()`), which includes minimized and off-screen windows, excludes desktop elements, and keeps only normal-layer (layer 0) windows.
- **title-backfill-inherited**: Window titles MUST be the engine's titles after its Accessibility backfill; the model performs no title lookup of its own.
- **untitled-windows-dropped**: A window whose title is empty after the engine's backfill MUST be excluded.
- **foreign-pid-dropped**: A window whose owning pid is not among the snapshotted regular apps MUST be excluded.
- **group-by-pid**: Kept windows MUST be grouped into one `DiscoveredApp` per owning pid, with `name` and `icon` taken from that pid's snapshot.
- **window-order-preserved**: Within a `DiscoveredApp`, `windows` MUST keep the order in which the engine reported them.
- **windowless-apps-omitted**: A snapshotted app with no kept window MUST NOT appear in `apps`.
- **duplicate-pid-first-wins**: If the snapshot contains the same pid twice, the first snapshot entry MUST be used for name and icon.
- **match-first-sort**: `apps` MUST be ordered with every app whose `hasMatch` is `true` before every app whose `hasMatch` is `false`.
- **alphabetical-sort**: Within each `hasMatch` group, apps MUST be ordered by `name` ascending using a localized, case-insensitive comparison.

### Matching (`matches(window:projectName:)`)

- **match-is-pure-static**: `matches(window:projectName:)` MUST be a static function of a `SystemWindowInfo` and a project name, with no dependency on model state, so it is testable in isolation (it is internal, visible to `@testable` tests).
- **empty-project-never-matches**: When `projectName` is the empty string, `matches` MUST return `false`.
- **unknown-project-never-matches**: When `projectName` is exactly `"Unknown"` (the sentinel `SessionWatcherSession.projectName` returns for an empty or root working directory), `matches` MUST return `false`.
- **heuristic-pattern**: `matches` MUST look up the heuristic registered in `HeuristicRegistry.shared` for the window's owning app name (case-insensitive lookup) and, when one exists and extracts a pattern from the title, test that pattern.
- **raw-title-fallback**: When no heuristic is registered for the app, or the heuristic extracts no pattern, `matches` MUST test the raw window title in place of the pattern.
- **pattern-or-title-contains**: `matches` MUST return `true` when either the tested pattern or the raw window title contains `projectName` under a localized, case-insensitive substring comparison, and `false` otherwise.

### Activation (`activateWindow(_:)`)

- **activation-logs-intent**: `activateWindow(_:)` MUST log an info-level message naming the window title and pid before attempting focus.
- **activation-focuses-by-id**: `activateWindow(_:)` MUST ask the engine to focus the window by its `id` (`SystemWindowManager.focus(windowID:)`), which raises the window, nudges a horizontally off-screen window back onto the main screen, and activates the owning app.
- **activation-success-callback**: When focus succeeds, `activateWindow(_:)` MUST invoke `onWindowActivated` exactly once, if it is set.
- **activation-failure-logged**: When focus throws, `activateWindow(_:)` MUST log an error-level message with the pid and the error's localized description.
- **activation-failure-no-callback**: When focus throws, `activateWindow(_:)` MUST NOT invoke `onWindowActivated`, so the host panel stays open for a retry.
- **activation-error-not-rethrown**: `activateWindow(_:)` MUST NOT throw or return the error; the log entry is the only failure signal.
- **activation-synchronous**: `activateWindow(_:)` MUST run the focus synchronously on the calling thread.
- **stale-window-not-rediscovered**: `activateWindow(_:)` MUST NOT re-run discovery; a window that has closed since discovery fails focus with the engine's window-not-found error and is logged like any other failure.

### Permission prompt (`openAccessibilitySettings()`)

- **settings-request**: `openAccessibilitySettings()` MUST call `SystemAccessibilityPermission.request()`, which shows the system Accessibility prompt and opens the Accessibility pane of System Settings.
- **settings-no-refresh**: `openAccessibilitySettings()` MUST discard the returned trust state and MUST NOT re-run discovery; the host calls `discoverWindows()` again when it wants a refresh.

### Concurrency

- **unchecked-sendable**: The model MUST be a `final class` declared `@unchecked Sendable` with no actor isolation; the compiler does not check its thread use.
- **main-thread-caller**: `discoverWindows()` MUST be called on the main thread; its own comments require this ("Snapshot app metadata on the main thread (NSWorkspace/NSRunningApplication are main-thread APIs)", "Call from onAppear"), and it mutates `@Published` state synchronously on the caller's thread.
- **value-types-not-sendable**: `DiscoveredWindow` and `DiscoveredApp` MUST be public structs with no `Sendable` conformance (`DiscoveredApp` holds an `NSImage?`), so the compiler keeps them in their isolation domain.

