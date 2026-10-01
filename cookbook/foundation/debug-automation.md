---
id: a14c4ed2-f380-486b-90da-84a68cbfafc2
title: Debug Automation
domain: agentictoolkit://cookbook/foundation/debug-automation
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'A launch-argument-driven debug switch and the activation/window-presentation
  gates built on it that keep automated test runs and debug launches from stealing
  the desktop from the person at the keyboard.'
platforms:
- swift
- macos
tags:
- debug-automation
- quiet-presentation
- launch-argument
- test-host-detection
depends-on: []
related:
- agentictoolkit://cookbook/ui/windows/single-window-controller
- agentictoolkit://cookbook/ui/containers/floating-chooser-panel
- agentictoolkit://cookbook/ui/settings/settings-window
references:
- packages/apple/AgenticToolkit/CoreMacOS/DebugAutomation/DebugLaunchSwitch.swift (agentictoolkit)
- packages/apple/AgenticToolkit/CoreMacOS/DebugAutomation/NSApplication+QuietActivation.swift (agentictoolkit)
- packages/apple/AgenticToolkit/CoreMacOS/DebugAutomation/NSWindow+TestHostVisibility.swift (agentictoolkit)
- packages/apple/AgenticToolkit/CoreMacOS/DebugAutomation/QuietWindowPresentation.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/CoreUI/DebugLaunchSwitchTests.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/CoreUI/QuietWindowPresentationTests.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Debug Automation

## Overview

Four small units answer one question for the rest of the application: is
this process one that must keep its hands off the desktop? The debug launch
switch is the reusable primitive — a settings-store key that doubles as a
launch-argument name, read only in a debug build. The quiet presentation
gate is the one switch built from it (keyed `"QuietWindowPresentation"`),
OR'd together with a second, independent signal — whether the process is a
test host, detected by checking whether the test framework's marker type is
resolvable in-process. A conditional activation operation and three
window-presentation operations (sink behind desktop, quiet order-front,
quiet make-key-and-order-front) are what the rest of the application calls
instead of unconditional application activation and unconditional window
ordering directly, so a test suite or an automated debug session can drive
real, on-screen, laid-out windows without ever pulling them — or the
application itself — in front of whoever is at the keyboard.

## Behavioral Requirements

- **switch-key-identity**: The debug launch switch MUST store the given key
  string verbatim and unchanged; the key MUST serve both as the
  settings-store key that reading the switch's enabled state looks up and as
  the launch-argument name a caller passes when the process is launched with
  that argument set.
- **switch-immutable-thread-safe**: The debug launch switch MUST be an
  immutable value with its key as its only stored data, so an instance MUST
  be safe to read from any thread concurrently without additional
  synchronization.
- **default-defaults-source**: The switch's enabled state, read with no
  store specified, MUST forward to reading it against the standard/default
  settings store.
- **injectable-defaults-parameter**: Reading the switch's enabled state MUST
  accept its settings-store source as a parameter rather than reading the
  default store internally, so a caller MAY supply an isolated settings
  store instead of the real one.
- **debug-build-reads-argument-domain**: Reading the switch's enabled state,
  when built in a debug configuration, MUST return the stored boolean value
  for its key from the supplied settings store (whose lookup includes the
  process's launch arguments).
- **release-build-always-off**: Reading the switch's enabled state, when
  built in a release configuration, MUST return `false` unconditionally,
  without reading the supplied settings store at all — the switch MUST be
  unreachable in a release build regardless of any launch argument,
  preference, or profile passed to it.
- **quiet-activation-gate**: The conditional activation operation MUST
  return immediately, without performing unconditional application
  activation, when the quiet presentation gate is enabled.
- **loud-activation-behavior**: The conditional activation operation MUST
  perform unconditional application activation when the quiet presentation
  gate is disabled.
- **test-host-detection**: Test-host detection MUST return `true` if and
  only if the test framework's marker type can be resolved in the current
  process, and MUST return `false` otherwise.
- **sink-level-only**: The sink-behind-desktop operation MUST change only
  the window's z-order level, setting it to the desktop's window level, and
  MUST NOT hide the window, close it, or change its visibility or opacity.
- **quiet-order-front**: The quiet order-front operation MUST perform the
  sink-behind-desktop operation before ordering the window to the front
  when the quiet presentation gate is enabled, and MUST perform only the
  front-ordering step when the gate is disabled.
- **quiet-make-key-and-order-front**: The quiet make-key-and-order-front
  operation MUST perform the sink-behind-desktop operation before making the
  window key and ordering it to the front when the quiet presentation gate
  is enabled, and MUST perform only the make-key-and-order-front step when
  the gate is disabled.
- **level-set-before-ordering**: The quiet order-front and quiet
  make-key-and-order-front operations MUST set the window's level before
  performing their ordering step, so the window MUST NOT be visible at the
  normal level even briefly on its way to the sunk level.
- **quiet-operations-run-on-main-thread**: The quiet order-front and quiet
  make-key-and-order-front operations MUST run on the main/UI thread; the
  sink-behind-desktop operation and test-host detection carry no such
  constraint of their own.
- **quiet-presentation-runs-on-main-thread**: The quiet presentation gate
  MUST be confined to the main/UI thread as a whole, so every one of its
  operations — reading its enabled state, resolving the quiet-presentation
  decision, and its underlying switch access — MUST be confined to that
  thread.
- **debug-switch-fixed-key**: The quiet presentation gate's underlying
  switch MUST be constructed with a fixed literal key, `"QuietWindowPresentation"`.
- **defaults-key-alias**: The quiet presentation gate's exposed settings key
  MUST return the underlying switch's key exactly, i.e. the same string
  `"QuietWindowPresentation"`.
- **is-enabled-live-read**: The quiet presentation gate's enabled state MUST
  evaluate the resolve step (test-host detection OR-ed with the underlying
  switch) freshly on every access; it MUST NOT cache or memoize the result.
- **resolve-or-precedence**: Resolving the quiet-presentation decision MUST
  return `true` when the test-host input is `true`, and otherwise MUST
  return the underlying switch's enabled state, read against the supplied
  settings store.
- **test-host-short-circuits-defaults-read**: Because the OR evaluation
  short-circuits, resolving the quiet-presentation decision MUST NOT
  evaluate the underlying switch's enabled state — and therefore MUST NOT
  read the supplied settings store at all — when the test-host input is
  `true`.

## Appearance

Not applicable — this is a set of launch-argument and window-level
primitives, not a visual component.

## States

Not applicable — this is a set of launch-argument and window-level
primitives, not a visual component. The one runtime state these units carry
— whether presentation is currently "quiet" — is a boolean decision covered
above under Behavioral Requirements (`quiet-activation-gate` through
`test-host-short-circuits-defaults-read`), not a visual state.

## Accessibility

Not applicable — this is a set of launch-argument and window-level
primitives, not a visual component. The sink-behind-desktop operation
changes a window's z-order level, never its accessibility role, label, or
announcements.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| foundation-debug-automation-001 | switch-key-identity, release-build-always-off / debug-build-reads-argument-domain | Read the switch's enabled state, keyed by a name never passed as a launch argument, against a settings store with no keys set. | Returns `false`. |
| foundation-debug-automation-002 | debug-build-reads-argument-domain | Read the switch's enabled state, keyed by a name whose value is set to `true` in the settings store, under a debug build. | Returns `true`. |
| foundation-debug-automation-003 | debug-switch-fixed-key, defaults-key-alias | Compare the quiet presentation gate's underlying switch key to its exposed settings key. | Both equal the string `"QuietWindowPresentation"`. |
| foundation-debug-automation-004 | resolve-or-precedence, test-host-short-circuits-defaults-read | Resolve the quiet-presentation decision with the test-host input `true`, against a settings store with the key set to `false`. | Returns `true`, regardless of the stored `false`. |
| foundation-debug-automation-005 | resolve-or-precedence | Resolve the quiet-presentation decision with the test-host input `false`, against a settings store with the key set to `true`. | Returns `true`. |
| foundation-debug-automation-006 | resolve-or-precedence | Resolve the quiet-presentation decision with the test-host input `false`, against an empty settings store. | Returns `false`. |
| foundation-debug-automation-007 | is-enabled-live-read, test-host-detection | Read the quiet presentation gate's enabled state from inside the running automated test process itself. | Returns `true` — the gate reads the live environment (this process is a test host), not merely the resolve step in isolation. |
| foundation-debug-automation-008 | quiet-order-front, quiet-activation-gate (ordering half) | Evaluate whether front-forcing should be suppressed (the negation of the quiet presentation gate) while running under the automated test framework. | Returns `false`, confirming the gate is enabled for the calling process. |
| foundation-debug-automation-009 | sink-level-only, quiet-make-key-and-order-front, level-set-before-ordering | Build a fresh window and perform the quiet make-key-and-order-front operation while the quiet presentation gate is enabled. | The window is visible, is attached to a screen, and its level equals the desktop's window level. |
| foundation-debug-automation-010 | quiet-make-key-and-order-front | Compare the key-window status of a window shown with unconditional make-key-and-order-front against one shown with the quiet make-key-and-order-front operation, both while the gate is enabled. | The two key-window statuses are equal — sinking the level costs no key status a plain call would have given. |

## Edge Cases

- **Null and empty input**: The debug launch switch's constructor takes a
  required, non-optional key and performs no validation; an empty string is
  accepted and stored as the key, and looking up an empty key in the
  settings store is a legal (if useless) lookup that never crashes (MUST,
  see **switch-key-identity**).
- **Boundary values**: The only boundary in this component is the
  compile-time debug/release configuration split itself, exercised by the
  two branches of the enabled-state read (MUST, see
  **debug-build-reads-argument-domain** and **release-build-always-off**);
  there is no numeric range or size to bound.
- **Concurrent access**: The debug launch switch is an immutable value type,
  so concurrent reads of its enabled state from multiple threads require no
  synchronization of their own (MUST, see **switch-immutable-thread-safe**).
  The quiet presentation gate and the two quiet window-presentation
  operations are confined to the main/UI thread by declaration, so access to
  the gate's enabled state, the resolve step, and the quiet
  order-front/quiet make-key-and-order-front operations is serialized (MUST,
  see **quiet-presentation-runs-on-main-thread**,
  **quiet-operations-run-on-main-thread**). The sink-behind-desktop operation
  and test-host detection carry no such constraint of their own; nothing in
  this recipe enforces that either is called on the main thread, though
  every call site in this recipe's own units reaches them only from an
  already-main-thread caller (MUST, see
  **quiet-operations-run-on-main-thread**).
- **Error states**: None of the four units exposes a throwing or failable
  read. The settings-store lookup never throws — it returns `false` for a
  missing or non-boolean key by contract — and the test-framework-detection
  check never throws either. This component has no network, database, or
  file-system dependency whose unavailability it needs to report (MUST —
  there is no error path to define, not an omitted one).
- **Offline or disconnected state**: Not applicable — none of the four units
  makes a network call or models a connectivity state.
- **Colliding switch keys**: The debug launch switch has no built-in
  namespacing or collision guard; two switches constructed with the same key
  string observe the same settings-store/launch-argument slot, since
  equality between two switches is exactly string equality on the key. This
  is the documented contract — the key doubles as both the settings-store
  key and the launch-argument name — not an omitted guard (MUST, see
  **switch-key-identity**).
- **Test-framework linkage outside an actual test run**: Test-host detection
  reports `true` whenever the test framework's marker type is resolvable in
  the current process, per its own stated assumption that the test
  framework links its own runtime library into the runner, so the marker
  type exists in a test run and nowhere else. A host process that happens to
  link the test framework's library for some other reason would also report
  `true`; this is the documented assumption the check relies on, not a
  validation this component performs (MUST, see **test-host-detection**).
- **Live mutation of the launch argument or setting mid-process**: neither
  the switch's enabled-state read nor the gate's enabled state caches its
  result; each re-evaluates its settings-store/test-framework-detection read
  on every call, so a value changed in the supplied settings store between
  two calls MUST be reflected on the very next read (MUST, see
  **is-enabled-live-read**, **injectable-defaults-parameter**).
- **Repeated calls with no intervening state change**: calling the
  sink-behind-desktop, quiet order-front, quiet make-key-and-order-front, or
  conditional activation operation more than once in a row, with the quiet
  presentation gate's enabled state unchanged between calls, MUST leave the
  window or application in the same observable state a single call would
  have produced — each is a single property assignment or a single
  ordering/activation step, not an accumulating counter (MUST, see
  **sink-level-only**, **quiet-order-front**,
  **quiet-make-key-and-order-front**, **loud-activation-behavior**).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Switch key (constructor parameter) | string | none — required at construction | Caller-supplied name shared as both the settings-store key and the launch-argument name, e.g. `"QuietWindowPresentation"` or `"MultipleInstances"`. |
| Launch argument | CLI flag, e.g. `-QuietWindowPresentation YES` | absent | Passed as a launch argument to the process; landed in the settings store's launch-argument-derived layer, which the switch's enabled-state read consults, and which lasts exactly as long as that one process. |
| Settings-store parameter (enabled-state read) | settings store | the standard/default store, via the no-argument read | Injectable so a test can supply an isolated settings store instead of the developer's real preferences. |
| Debug/release build configuration | compiler build configuration | project-configured (debug vs. release) | Gates whether the enabled-state read ever consults the settings store at all; a release build removes the check entirely. |

None of the four units reads a process environment variable or any settings
key of its own beyond the settings-store key described above.

## Deep Linking

Not applicable: none of the four units defines a URL scheme, route, or
navigation destination — this is a process-internal launch-argument and
window-ordering mechanism, not application navigation.

## Localization

Not applicable: none of the four units produces a user-facing string. The
switch's key and the quiet presentation gate's exposed settings key are
internal settings-store/launch-argument identifiers, never displayed to a
user.

## Accessibility Options

Not applicable: the four units present no UI of their own — they change an
already-existing window's z-order level and ordering, or skip application
activation, and respond to no reduced-motion, increased-contrast, or
color-differentiation accessibility setting.

## Feature Flags

Not applicable: this component defines no feature-flag key gating whether
it, itself, is enabled. It is the opposite direction — a launch-argument
primitive (the debug launch switch) that other code, such as the quiet
presentation gate's own `"QuietWindowPresentation"` key (see
Configuration), builds a flag from.

## Analytics

Not applicable: none of the four units calls an analytics or
event-tracking API.

## Privacy

Not applicable: this component reads and writes only a caller-named
Boolean flag under a settings-store key equal to a launch-argument name
(e.g. `"QuietWindowPresentation"`); no user-generated, personal, or
credential data is read, written, or transmitted by any of the four units.

## Logging

Not applicable: none of the four units contains a logging call.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/CoreMacOS/DebugAutomation/{DebugLaunchSwitch,NSApplication+QuietActivation,NSWindow+TestHostVisibility,QuietWindowPresentation}.swift`.
  Nothing here is SwiftUI-specific: `DebugLaunchSwitch` depends only on
  `Foundation`'s `UserDefaults`, and the other three files operate on plain
  `AppKit` `NSApplication`/`NSWindow` instances beneath any SwiftUI
  `WindowGroup`/`Window` scene that hosts them.
- **Compose**: There is no Android/Compose Desktop analogue to a launch
  argument read from an argument domain; the closest equivalent is a
  `BuildConfig.DEBUG`-gated check of an `am start --es` extra or a
  `SharedPreferences` Boolean. `isRunningInTests` would map to detecting
  `androidx.test.platform.app.InstrumentationRegistry` on the classpath.
  There is no per-window desktop-level compositing to sink a window behind
  on Android or Compose Desktop; a Compose Desktop port would instead have
  to withhold `Window`'s focus request / `alwaysOnTop` rather than move it
  behind a desktop-level constant, since AWT/Swing has no
  `CGWindowLevelForKey(.desktopWindow)` equivalent.
- **React/Web**: No analogue exists for either half. A browser page cannot
  read a native launch argument; the nearest equivalent is a
  `process.env.NODE_ENV !== 'production'` gate (build-time, like the
  debug/release split) combined with a URL query parameter or
  `localStorage` flag in place of the argument domain. There is also no
  desktop window level to sink behind — a browser tab does not share
  desktop z-order with other native applications the way a native window
  does, so an E2E harness (Playwright/Cypress) drives the page without the
  app needing to suppress its own foregrounding.
- **AppKit / UIKit**: This recipe is extracted directly from AppKit (the
  source platform). The debug launch switch is `DebugLaunchSwitch`
  (`DebugLaunchSwitch.swift`), a `Sendable`, `Hashable` `struct` with
  `key: String` as its only stored property; enabled-state reads are `isOn`
  / `isOn(defaults:)`, gated by `#if DEBUG` / `#else` compiler branches
  (release builds skip the `UserDefaults` read entirely). The launch
  argument is passed as `open -n -g -a <App> --args -<key> YES`, landing in
  `UserDefaults`'s argument domain, which `isOn(defaults:)` reads via
  `defaults.bool(forKey: key)`. The quiet presentation gate is the
  `@MainActor` enum `QuietWindowPresentation` (`QuietWindowPresentation.swift`):
  `debugSwitch = DebugLaunchSwitch("QuietWindowPresentation")`,
  `defaultsKey`, `isEnabled`, and `resolve(isTestHost:defaults:)`. Test-host
  detection is `NSWindow.isRunningInTests` (`NSWindow+TestHostVisibility.swift`),
  which checks `NSClassFromString("XCTestCase") != nil`. The conditional
  activation operation is `NSApplication.activateUnlessQuiet()`
  (`NSApplication+QuietActivation.swift`), calling
  `activate(ignoringOtherApps: true)` only when disabled. The three window
  operations — sink-behind-desktop, quiet order-front, and quiet
  make-key-and-order-front — are `NSWindow.sinkBehindDesktop()`,
  `orderFrontQuietly()`, and `makeKeyAndOrderFrontQuietly()`
  (`NSWindow+TestHostVisibility.swift`), which wrap `orderFront(nil)` /
  `makeKeyAndOrderFront(nil)` around setting
  `level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))`;
  `sinkBehindDesktop()` never calls `orderOut`, `close`, or touches
  `isVisible`/`alphaValue`. `orderFrontQuietly()` and
  `makeKeyAndOrderFrontQuietly()` are declared `@MainActor`;
  `sinkBehindDesktop()` and `isRunningInTests` carry no actor annotation of
  their own in this source file, though every call site in this recipe's
  own files reaches them only from an already-`@MainActor` caller. UIKit
  (iOS) has no multi-app desktop compositing or unfocused-app foregrounding
  concept in the same sense — an iOS app is always the single foreground
  app when running — so there is no sink-behind-desktop analogue; the
  nearest iOS equivalent of "quiet" automation would be skipping a scene's
  `UIWindowScene` activation request rather than moving a window's z-order.
- **WinUI 3**: Read the launch argument via
  `Environment.GetCommandLineArgs()` (or `AppInstance.GetActivatedEventArgs().Data`
  for a already-running-instance activation), gated by the C# `#if DEBUG`
  preprocessor directive exactly as `isOn(defaults:)` gates on Swift's
  `DEBUG`; store the flag under `ApplicationData.Current.LocalSettings.Values["QuietWindowPresentation"]`
  read only inside that `#if DEBUG` block, mirroring the
  `UserDefaults`-key/launch-argument coupling. Detect a test host by
  checking `AppDomain.CurrentDomain.GetAssemblies()` for
  `Microsoft.VisualStudio.TestPlatform` (or the MSTest/xUnit runner
  assembly) in place of `NSClassFromString("XCTestCase") != nil`. For the
  window-level trick, `AppWindow` exposes no direct
  "desktop window level" constant; the nearest equivalents are
  `AppWindow.MoveInZOrderAtBottom()` or a P/Invoke `SetWindowPos` call with
  `HWND_BOTTOM`, in place of setting `NSWindow.level`. For activation,
  WinUI 3's `AppWindow.Show(activateWindow: Boolean)` takes an explicit
  activate flag directly — a WinUI port can pass `activateWindow: false`
  in one call, rather than needing a separate `NSApplication.activate(ignoringOtherApps:)`
  gate the way `activateUnlessQuiet()` does.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/CoreMacOS/DebugAutomation/` |

## Design Decisions

**Decision**: The debug launch switch is a distinct reusable primitive
rather than an inline settings-store lookup at each use site.
**Rationale** (AppKit implementation): Per the type's own doc comment, a
switch read this way lives only in the launch-argument domain, not a
written preference — so a stale `defaults write` cannot leave a developer
wondering later why the app behaves oddly — and the debug/release check is
evaluated exactly once, in this type, so no call site can forget it
(`DebugLaunchSwitch.swift`).
**Approved**: pending

**Decision**: The sink-behind-desktop operation changes only the window's
`level`, leaving ordering, key status, and visibility to the caller, rather
than hiding the window (`orderOut`, `isVisible = false`) or moving it
off-screen.
**Rationale** (AppKit implementation): A test still has to assert
`isVisible`, the restored frame, `window.screen`, and first-responder
changes — all of which a genuinely hidden or off-screen window would fail —
while a person at the keyboard must not see it "in front of them"; dropping
the level below the desktop gives AppKit a real, laid-out, visible window
and gives the person at the keyboard nothing (`NSWindow+TestHostVisibility.swift`).
**Approved**: pending

**Decision**: The quiet order-front and quiet make-key-and-order-front
operations set the window's level *before* calling
`orderFront`/`makeKeyAndOrderFront`, rather than ordering first and sinking
afterward.
**Rationale** (AppKit implementation): Per the doc comment, this ordering
keeps the window from ever being briefly visible at the normal level on its
way to the sunk level — a flash a person at the keyboard could otherwise
catch.
**Approved**: pending

**Decision**: The quiet presentation gate's enabled state is the OR of two
independent signals — test-host detection and the debug-only switch's
enabled state — rather than a single flag, and the resolve step exists as a
separate function taking both as parameters.
**Rationale**: The doc comment states both are "the same situation twice":
a test host must always stay quiet, with no launch argument required, while
an automated debug session needs the argument because it is not itself a
test-framework process. Exposing the resolve step with both inputs as
parameters makes both branches independently testable — under the test
framework itself, the gate's enabled state would otherwise always
short-circuit to `true` and the debug-only branch could never be exercised
(`QuietWindowPresentation.swift`).
**Approved**: pending

**Decision**: The conditional activation operation generalizes to
application activation the same suppression that window-ordering already
established, as one shared gate rather than a bare unconditional activation
call repeated at each call site.
**Rationale** (AppKit implementation): The doc comment records that eleven
call sites previously called `activate(ignoringOtherApps:)` directly, so
the quiet flag was honored by whichever of them happened to remember it and
ignored by the rest; centralizing the check in one extension method removes
that per-call-site inconsistency (`NSApplication+QuietActivation.swift`).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |

Notes: separation-of-concerns passes because each of the four files owns
exactly one concern — the launch-argument/defaults primitive
(`DebugLaunchSwitch`), the app-activation gate
(`NSApplication+QuietActivation`), the window-level and test-host-detection
primitives (`NSWindow+TestHostVisibility`), and the single combined decision
(`QuietWindowPresentation`) — with `QuietWindowPresentation` composing the
other three rather than any one file duplicating another's logic.
unit-test-coverage passes because `DebugLaunchSwitchTests.swift` and
`QuietWindowPresentationTests.swift` directly exercise both branches of
`isOn(defaults:)`, both branches of `resolve(isTestHost:defaults:)`, the
live `isEnabled` read, and the observable effect of
`makeKeyAndOrderFrontQuietly()` on a real `NSWindow`.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to foundation/. |
