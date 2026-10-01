---
id: 0ab38622-b4a9-424c-89e2-5d27073680c7
title: Window Discovery
domain: agentictoolkit://cookbook/system/system-windows/window-discovery
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Lists every titled window of regular apps grouped by app, flags windows
  matching a session project, and focuses one.
platforms:
- swift
- macos
tags:
- window-management
- window-matching
depends-on: []
related:
- agentictoolkit://cookbook/system/system-windows/window-explorer-view
references: []
approved-by: ''
approved-date: ''
---

# Window Discovery

## Overview

The window discovery view model (with its two value types, a discovered window and a discovered app) backs the Window Discovery panel. Given a session, it:

- enumerates every window the window-management engine reports — including
  minimized and off-screen windows — and keeps the titled ones owned by regular,
  user-visible applications;
- groups them by owning process into discovered-app values carrying the app's
  localized name and icon;
- flags each window whose title matches the session's project name, using the
  per-app title heuristic from the shared heuristic registry with a raw-title
  fallback (a static matching function);
- sorts apps with a match first, then alphabetically;
- focuses a chosen window through the engine and tells its host when the focus
  succeeded so the panel can close.

It needs only Accessibility permission. When the system window list omits a
title (it does for other apps without Screen Recording permission), the engine
backfills it from the Accessibility API before this model sees it.

Use it when a UI needs a "which window belongs to this session?" chooser. It
is observable; the host binds to its three published properties.

## Behavioral Requirements

### Data shapes

- **discovered-window-shape**: A discovered window MUST be a value with a stable identity (`id`, the system window number, used to focus the window), `title` (a string), `pid` (a process id) and `isMatch` (a boolean), all immutable.
- **discovered-app-shape**: A discovered app MUST be a value with a stable identity (`id`, a process id), `name` (a string), `icon` (an optional image) and `windows` (a list of discovered windows), all immutable.
- **app-has-match**: A discovered app's `hasMatch` MUST be a computed property that is `true` exactly when at least one element of `windows` has `isMatch == true`.
- **published-state**: The model MUST publish three observable properties: `isLoading` (a boolean, initially `true`), `apps` (a list of discovered apps, initially empty) and `accessibilityDenied` (a boolean, initially `false`).
- **session-exposed**: The model MUST expose the `session` it was initialised with as an immutable public property; constructing the model MUST NOT start discovery.

### Discovery

- **discovery-resets-flags**: Discovering windows MUST set `isLoading` to `true` and `accessibilityDenied` to `false` before any other work.
- **discovery-permission-gate**: When Accessibility permission is not granted, discovering windows MUST set `isLoading` to `false` and `accessibilityDenied` to `true` synchronously and return without enumerating windows.
- **denied-keeps-apps**: On the permission-denied path, discovering windows MUST leave `apps` unchanged; it does not clear a previous result.
- **permission-check-no-prompt**: The permission gate MUST only read the trust state; it MUST NOT show the system Accessibility prompt.
- **app-snapshot-on-caller-thread**: Discovering windows MUST snapshot the running applications (process id, localized name, icon) synchronously on the calling thread before dispatching any background work.
- **regular-apps-only**: The snapshot MUST include only applications whose activation policy is regular (user-visible apps); accessory and background-only processes MUST be excluded.
- **unknown-app-name**: An application with no localized name MUST be snapshotted with the name `"Unknown"`.
- **project-name-captured**: Discovering windows MUST read the session's project name once, on the calling thread, and match every window against that captured value.
- **enumeration-off-caller-thread**: Window enumeration and matching MUST run on a background queue at user-initiated priority, not on the calling thread.
- **results-published-on-main**: The grouped result MUST be assigned to `apps`, and `isLoading` set to `false`, on the main queue in a single main-queue block, `apps` first.
- **weak-owner**: The background work MUST hold the model weakly; when the model has been deallocated before the work starts, nothing MUST be enumerated or published.
- **no-cancellation-or-timeout**: Discovery MUST NOT offer cancellation or a timeout; once dispatched, the enumeration runs to completion and publishes.
- **overlapping-discovery-order**: NEEDS REVIEW: Not implemented in source. Two overlapping discovery calls each dispatch independent background work and each publish on completion, so `apps` ends with whichever enumeration finishes last (not the last one started) and `isLoading` turns `false` when the first finishes; the source has no generation token or serialisation. Settling it needs an owner decision on whether the latest call must win.

### Enumeration and grouping

- **all-windows-source**: Enumeration MUST use the engine's full window list, which includes minimized and off-screen windows, excludes desktop elements, and keeps only normal-layer (layer 0) windows.
- **title-backfill-inherited**: Window titles MUST be the engine's titles after its Accessibility backfill; the model performs no title lookup of its own.
- **untitled-windows-dropped**: A window whose title is empty after the engine's backfill MUST be excluded.
- **foreign-pid-dropped**: A window whose owning pid is not among the snapshotted regular apps MUST be excluded.
- **group-by-pid**: Kept windows MUST be grouped into one discovered app per owning pid, with `name` and `icon` taken from that pid's snapshot.
- **window-order-preserved**: Within a discovered app, `windows` MUST keep the order in which the engine reported them.
- **windowless-apps-omitted**: A snapshotted app with no kept window MUST NOT appear in `apps`.
- **duplicate-pid-first-wins**: If the snapshot contains the same pid twice, the first snapshot entry MUST be used for name and icon.
- **match-first-sort**: `apps` MUST be ordered with every app whose `hasMatch` is `true` before every app whose `hasMatch` is `false`.
- **alphabetical-sort**: Within each `hasMatch` group, apps MUST be ordered by `name` ascending using a localized, case-insensitive comparison.

### Matching

- **match-is-pure-static**: Matching a window against a project name MUST be a pure function of a window's info and a project name, with no dependency on model state, so it is testable in isolation.
- **empty-project-never-matches**: When `projectName` is the empty string, matching MUST return `false`.
- **unknown-project-never-matches**: When `projectName` is exactly `"Unknown"` (the sentinel value a session's project name returns for an empty or root working directory), matching MUST return `false`.
- **heuristic-pattern**: Matching MUST look up the heuristic registered for the window's owning app name (case-insensitive lookup) and, when one exists and extracts a pattern from the title, test that pattern.
- **raw-title-fallback**: When no heuristic is registered for the app, or the heuristic extracts no pattern, matching MUST test the raw window title in place of the pattern.
- **pattern-or-title-contains**: Matching MUST return `true` when either the tested pattern or the raw window title contains `projectName` under a localized, case-insensitive substring comparison, and `false` otherwise.

### Activation

- **activation-logs-intent**: Activating a window MUST log an info-level message naming the window title and pid before attempting focus.
- **activation-focuses-by-id**: Activating a window MUST ask the engine to focus the window by its `id`, which raises the window, nudges a horizontally off-screen window back onto the main screen, and activates the owning app.
- **activation-success-callback**: When focus succeeds, activating a window MUST invoke the activation callback exactly once, if it is set.
- **activation-failure-logged**: When focus fails, activating a window MUST log an error-level message with the pid and the error's description.
- **activation-failure-no-callback**: When focus fails, activating a window MUST NOT invoke the activation callback, so the host panel stays open for a retry.
- **activation-error-not-rethrown**: Activating a window MUST NOT throw or return the error; the log entry is the only failure signal.
- **activation-synchronous**: Activating a window MUST run the focus synchronously on the calling thread.
- **stale-window-not-rediscovered**: Activating a window MUST NOT re-run discovery; a window that has closed since discovery fails focus with the engine's window-not-found error and is logged like any other failure.

### Permission prompt

- **settings-request**: Opening Accessibility settings MUST request Accessibility permission, which shows the system Accessibility prompt and opens the Accessibility pane of system settings.
- **settings-no-refresh**: Opening Accessibility settings MUST discard the returned trust state and MUST NOT re-run discovery; the host calls discovery again when it wants a refresh.

### Concurrency

- **unchecked-thread-safety**: The model MUST be usable with no compiler-checked thread isolation; callers are responsible for its thread use.
- **main-thread-caller**: Discovering windows MUST be called on the main thread; its own documentation requires this (app metadata comes from main-thread-only system APIs, and it should be called when the view appears), and it mutates observable state synchronously on the caller's thread.
- **value-types-single-context**: A discovered window and a discovered app MUST NOT be usable across concurrency boundaries (a discovered app holds a platform image), so they are confined to the isolation domain that creates them.

## Appearance

Not applicable — this is a window-enumeration and matching view model, not a visual component.

## States

Not applicable — this is a window-enumeration and matching view model, not a visual component.

## Accessibility

Not applicable — this is a window-enumeration and matching view model, not a visual component.

## Conformance Test Vectors

Vectors 001–005 come from the matching tests; the rest trace to the view model. Enumeration vectors assume a fake engine and fake running-app list.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wdisc-001 | heuristic-pattern, pattern-or-title-contains | Matching with app `"Xcode"`, title `"MyApp — ContentView.swift"`, projectName `"MyApp"` | `true` |
| wdisc-002 | raw-title-fallback, pattern-or-title-contains | app `"SomeEditor"` (no heuristic), title `"Working on MyApp now"`, projectName `"MyApp"` | `true` |
| wdisc-003 | pattern-or-title-contains | app `"Xcode"`, title `"OtherProject — File.swift"`, projectName `"MyApp"` | `false` |
| wdisc-004 | empty-project-never-matches | app `"Xcode"`, title `"MyApp — File.swift"`, projectName `""` | `false` |
| wdisc-005 | unknown-project-never-matches | app `"Xcode"`, title `"MyApp — File.swift"`, projectName `"Unknown"` | `false` |
| wdisc-006 | pattern-or-title-contains | app `"SomeEditor"`, title `"MYAPP notes"`, projectName `"myapp"` | `true` (case-insensitive) |
| wdisc-007 | discovery-permission-gate, denied-keeps-apps | Accessibility not granted; `apps` already holds 2 entries; discover windows | synchronously `isLoading == false`, `accessibilityDenied == true`, `apps` still has the 2 entries, engine never queried |
| wdisc-008 | discovery-resets-flags, results-published-on-main | granted; `accessibilityDenied` previously `true`; discover windows | immediately `isLoading == true`, `accessibilityDenied == false`; later, on main, `apps` set then `isLoading == false` |
| wdisc-009 | untitled-windows-dropped, foreign-pid-dropped, windowless-apps-omitted | regular apps A (pid 10) and B (pid 20); engine windows: pid 10 `"Doc"`, pid 10 `""`, pid 30 `"Other"` | `apps` holds only A with one window `"Doc"`; B and pid 30 absent |
| wdisc-010 | regular-apps-only | an accessory-policy app (pid 40) owns a titled window | pid 40 absent from `apps` |
| wdisc-011 | match-first-sort, alphabetical-sort | apps `"zeta"` (has match), `"Beta"` (no match), `"alpha"` (no match) | order `"zeta"`, `"alpha"`, `"Beta"` |
| wdisc-012 | app-has-match | a discovered app with windows `isMatch` = false, true | `hasMatch == true`; with all false, `hasMatch == false` |
| wdisc-013 | unknown-app-name | regular app with no localized name owns a titled window | its discovered-app `name == "Unknown"` |
| wdisc-014 | window-order-preserved, group-by-pid | engine reports pid 10 windows `"B"` then `"A"` | one discovered app for pid 10 with windows `"B"`, `"A"` in that order |
| wdisc-015 | activation-success-callback | engine focus succeeds; activation callback set | callback invoked exactly once |
| wdisc-016 | activation-failure-logged, activation-failure-no-callback, activation-error-not-rethrown | engine focus fails with window-not-found | error log with the pid and description; callback not invoked; activation returns normally |
| wdisc-017 | settings-request, settings-no-refresh | open Accessibility settings | permission request issued once; `apps`, `isLoading`, `accessibilityDenied` unchanged |
| wdisc-018 | weak-owner | model released after discovery returns but before the background block runs | engine not queried; no publish |
| wdisc-019 | duplicate-pid-first-wins | snapshot lists pid 10 as `"First"` then `"Second"` | the discovered app for pid 10 is named `"First"` |

## Edge Cases

- **Empty project name**: `projectName == ""` — every window gets `isMatch == false`, so no app sorts first and the list is purely alphabetical (MUST).
- **Unknown project**: `projectName == "Unknown"` (session with empty or root working directory) — same as empty: no window matches (MUST). A real project literally named `Unknown` can never match; this is the sentinel's cost.
- **No regular apps or no titled windows**: `apps` becomes an empty array and `isLoading` becomes `false` (MUST); no error or distinct empty state is published.
- **Engine returns nothing**: if the system window list cannot be read the engine returns an empty list, which yields an empty `apps` with no error signal (MUST); the model cannot tell "no windows" from "list unavailable".
- **Titles withheld**: without Screen Recording, titles come from the engine's Accessibility backfill; a window the backfill cannot title stays empty and is dropped (MUST).
- **Permission revoked between snapshot and enumeration**: the gate has already passed; the engine's backfill then yields no titles for other apps, so those windows are dropped and `accessibilityDenied` stays `false` (MUST, as implemented).
- **Denied after a successful run**: `apps` keeps the previous result while `accessibilityDenied` is `true` (MUST); hosts showing the denied state must hide the stale list themselves.
- **Overlapping calls**: repeated discovery calls race; see the open question on overlapping-discovery-order.
- **Model released mid-discovery**: if released before the background block starts, nothing is published (MUST); if released after, the main-queue block holds the model strongly and still publishes (MUST).
- **Window closed before activation**: focus fails with the engine's window-not-found error, which is logged; the activation callback is not called (MUST).
- **App cannot be activated**: focus fails with an activation-failed error; logged; callback not called (MUST).
- **Parked window**: a window moved horizontally off every screen is moved to 80 points right of the main screen's visible-frame left edge (Y unchanged) before being raised (MUST, engine behavior).
- **Equal app names**: two apps with names equal under case-insensitive comparison have no defined relative order; the grouping's iteration order decides (MAY vary between runs).
- **Title containing the project name without heuristic support**: the raw-title fallback still matches substrings, so `"MyAppTests"` matches project `"MyApp"` (MUST); the match is substring-based, not word-based.
- **Concurrent access**: matching reads the shared heuristic registry, which serialises its lookups under a lock, so matching on the background queue is safe while custom rules change (MUST).
- **Offline or disconnected state**: not applicable — the model makes no network calls; all data is local system state.
- **Timeout**: no timeout exists; a slow Accessibility backfill delays the publish with `isLoading` staying `true` (MUST, as implemented).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `session` | session value | required | Supplies the project name (last path component of the working directory, or `"Unknown"`) that windows are matched against. |
| `onWindowActivated` | optional callback | `nil` | Called after a successful focus so the host can close the panel. |
| Heuristic registry | shared singleton | built-in Xcode, Warp, Brave, VS Code, Terminal heuristics plus any registered custom rules | Per-app title-pattern extraction used by matching; not injectable. |
| Window-management engine | private engine instance | created per model | Window enumeration and focus; not injectable. |
| Accessibility permission | system trust state | — | Required for discovery; read via the Accessibility permission's granted state. |

## Deep Linking

Not applicable: the model is driven only by method calls from its host panel (discovering windows, activating a window, opening Accessibility settings) and registers no URL.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded) | `Unknown` | Fallback discovered-app `name` for an application with no localized name; hardcoded English, not localized. |

The `"Unknown"` compared in matching is the sentinel value from the session's project name, not display text. Log messages are English developer diagnostics and are not localized.

## Accessibility Options

Not applicable: the model renders nothing, so Reduce Motion, Increase Contrast and Differentiate Without Color have no effect on it.

## Feature Flags

Not applicable: the source reads no flag; discovery is gated only by Accessibility permission.

## Analytics

Not applicable: the source emits no analytics events; its only output besides published state is the log.

## Privacy

- **Data collected**: the titles, pids and window numbers of every titled window owned by a regular app, plus each app's localized name and icon.
- **Storage**: in memory only, in `apps`; nothing is written to disk.
- **Transmission**: none; no data leaves the device.
- **Retention**: until the next discovery replaces `apps` or the model is released. The activation log line records the chosen window's title as public (unredacted) text in the unified log, where it is retained under the system's log policy.

## Logging

Subsystem: main bundle identifier (`nil` when absent) | Category: the component's role name

| Event | Level | Message |
|-------|-------|---------|
| Activation attempt | info | `WindowDiscovery: activating '<title>' (PID <pid>)` — title marked public |
| Focus failure | error | `WindowDiscovery: focus failed (PID <pid>): <localizedDescription>` — reason marked public |

Discovery itself logs nothing, including the permission-denied path, which is signalled through `accessibilityDenied`.

## Platform Notes

- **SwiftUI**: Source is Swift/AppKit: the view model lives under `AgenticToolkit/macOS/Features/WindowDiscovery`, driven by an AppKit host view through Combine subscriptions to `$isLoading`, `$accessibilityDenied` and `$apps`. A SwiftUI host can bind the same observable model with `@ObservedObject`; a port to Swift 6 style would make it `@MainActor @Observable` and run enumeration in a `Task.detached`, replacing `DispatchQueue` hops and the unchecked thread-safety escape.
- **Compose**: Android has no cross-app window enumeration or focus API; a Kotlin port keeps only the pure parts — matching as a plain function and the grouping/sort over a `List` with `sortedWith(compareByDescending { it.hasMatch }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.name })` — exposed from a `ViewModel` via `StateFlow`, with enumeration running in `viewModelScope.launch(Dispatchers.Default)`.
- **React/Web**: Browsers cannot see other applications' windows; a web port applies only to an Electron-style host (`desktopCapturer.getSources({ types: ['window'] })` gives titles and ids). Matching becomes `title.toLocaleLowerCase().includes(project.toLocaleLowerCase())` and sorting uses `localeCompare` with `sensitivity: 'base'`; state lives in a store or `useState`.
- **AppKit / UIKit**: This is the AppKit source. Enumeration relies on `CGWindowListCopyWindowInfo` with the all-windows option, `NSWorkspace.shared.runningApplications` filtered on `activationPolicy == .regular`, Accessibility (`AXIsProcessTrusted`, AX raise action) for backfill and focus, and `NSRunningApplication.activate()`. UIKit has no equivalent; iOS apps cannot enumerate or focus other apps' windows. The model is a `final class` declared `@unchecked Sendable` with no actor isolation, so the compiler does not check its thread use — callers must call it from the main thread as documented. The discovered-window and discovered-app value types are public structs with no `Sendable` conformance (the discovered-app type holds an `NSImage?`), so the compiler keeps them confined to the isolation domain that creates them. The logging category is the type's own name, `WindowDiscoveryViewModel`.
- **WinUI 3**: Start from a view-model class implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm `ObservableObject` with `[ObservableProperty]`) exposing `IsLoading`, `AccessibilityDenied` and an `ObservableCollection<DiscoveredApp>`. Enumerate with Win32 `EnumWindows` + `IsWindowVisible`/`GetWindowText`/`GetWindowThreadProcessId` via CsWin32 P/Invoke, keeping windows whose owner has a main window (`Process.MainWindowHandle != IntPtr.Zero`) as the "regular app" analogue, and taking icons from `Icon.ExtractAssociatedIcon` on the process path. Run it in `Task.Run` and marshal back with `DispatcherQueue.TryEnqueue`. Focus with `SetForegroundWindow` after `ShowWindow(hwnd, SW_RESTORE)` for minimized windows. Differences: Windows needs no Accessibility permission to read titles, so the denied branch has no direct counterpart (UI Automation is only needed for elevated windows); `SetForegroundWindow` can be refused by the foreground-lock rules and returns `false` rather than throwing, which maps to the failure-logged path. Sort with `StringComparer.CurrentCultureIgnoreCase` and match with `title.Contains(project, StringComparison.CurrentCultureIgnoreCase)`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/WindowDiscovery/WindowDiscoveryViewModel.swift` |

## Design Decisions

**Decision**: Match on the heuristic pattern OR the raw title.
**Rationale**: The source comment says the raw-title check is kept "so existing substring matches still hold". For the built-in Xcode heuristic the pattern is a prefix of the title, so the raw-title test already covers it; the pattern only adds matches when a custom heuristic returns text not present verbatim in the title.
**Approved**: pending

**Decision**: Treat `"Unknown"` and the empty string as "no project".
**Rationale**: A session's project name returns `"Unknown"` for an empty or root working directory; matching it would flag any window whose title contains the word.
**Approved**: pending

**Decision**: Include minimized and off-screen windows.
**Rationale**: The type's doc comment says the panel lists them "so the user can bring any of them back"; the engine's focus moves a parked window back on-screen.
**Approved**: pending

**Decision**: Keep the panel open when focus fails, reporting only via the log.
**Rationale**: The activation doc comment: "on failure it logs and leaves the panel open so the user can retry or pick another window, rather than silently closing as if it worked."
**Approved**: pending

**Decision** (Apple platforms): Snapshot running apps on the calling thread, enumerate windows in the background.
**Rationale**: The source comment names `NSWorkspace`/`NSRunningApplication` as main-thread APIs; the window list and Accessibility backfill can be slow, so they run off the main thread.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [main-thread-freedom](agenticdevelopercookbook://compliance/performance#main-thread-freedom) | passed | Performance |
| [progress-indication](agenticdevelopercookbook://compliance/performance#progress-indication) | passed | Performance |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | failed | Reliability |
| [platform-permissions](agenticdevelopercookbook://compliance/platform-compliance#platform-permissions) | passed | Platform Compliance |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | partial | Privacy and Data |

separation-of-concerns passes because enumeration and focus live in the window-management engine, title parsing in the heuristic registry, permission checks in the Accessibility permission component, and the model only filters, groups, matches and sorts, with matching isolated in a pure static function. unit-test-coverage is partial: the matching tests cover matching (heuristic match, raw-title fallback, non-match, empty and `"Unknown"` projects) but nothing tests grouping, filtering, sorting, the permission gate or activation, and the engine is not injectable. explicit-error-handling is partial: focus failures are caught and logged but not surfaced to the caller, and the ordering of overlapping discoveries is undefined (the open question on overlapping-discovery-order). main-thread-freedom passes because the window list and backfill run on a background queue. progress-indication passes because `isLoading` is published from the start of discovery to the publish. graceful-degradation passes because a missing permission yields `accessibilityDenied` instead of a failure, and withheld titles are backfilled. timeout-handling fails because discovery has no timeout. platform-permissions passes because the model checks trust without prompting and prompts only from the user-initiated settings action. data-minimization passes because only title, pid, window number, name and icon are kept, in memory. no-pii-in-logs is partial because the activation log records the window title, which can contain document or project names, as public.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to system/system-windows/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from `WindowDiscoveryViewModel.swift` and `WindowDiscoveryMatchingTests.swift` |
