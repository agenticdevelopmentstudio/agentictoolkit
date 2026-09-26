---
id: a14c4ed2-f380-486b-90da-84a68cbfafc2
title: Foundation Debug Automation
domain: agentictoolkit://cookbook/core-macos/debug-automation
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Four CoreMacOS primitives — a Debug-only launch-argument switch and the
  activation/window-level gates built on it — that keep XCTest hosts and automated
  Debug launches from stealing the desktop.'
platforms:
- swift
- macos
tags:
- debug-automation
- quiet-presentation
- launch-argument
- test-host-detection
- appkit
depends-on: []
related:
- agentictoolkit://cookbook/macos/system-integration/window-manager/windows/single-window-controller
- agentictoolkit://cookbook/macos/ui/panels/floating-chooser-panel-controller
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/settings-window
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

# Foundation Debug Automation

## Overview

The `CoreMacOS/DebugAutomation` folder is four small files that answer one
question for the rest of `AgenticToolkitMacOS`: is this process one that must
keep its hands off the desktop? `DebugLaunchSwitch` is the reusable primitive
— a `UserDefaults` key that doubles as a launch-argument name, read only in a
**Debug** build. `QuietWindowPresentation` is the one switch built from it
(`"QuietWindowPresentation"`), OR'd together with a second, independent
signal — whether the process is an XCTest host, detected by
`NSWindow.isRunningInTests`. `NSApplication.activateUnlessQuiet()` and three
`NSWindow` methods (`sinkBehindDesktop()`, `orderFrontQuietly()`,
`makeKeyAndOrderFrontQuietly()`) are what everything else in the app calls
instead of `NSApplication.activate(ignoringOtherApps:)` and
`NSWindow.orderFront(nil)`/`makeKeyAndOrderFront(nil)` directly, so a test
suite or an automated Debug session can drive real, on-screen, laid-out
windows without ever pulling them — or the app itself — in front of whoever
is at the keyboard.

## Behavioral Requirements

- **switch-key-identity**: `DebugLaunchSwitch.init(_:)` MUST store the given
  `String` in its `key` property verbatim and unchanged; `key` MUST serve
  both as the `UserDefaults` key `isOn(defaults:)` reads and as the
  launch-argument name a caller passes after `--args -<key> YES`
  (`DebugLaunchSwitch.swift`).
- **switch-sendable-hashable-value-type**: `DebugLaunchSwitch` MUST be a
  `struct` conforming to `Sendable` and `Hashable`, with `key` as its only
  stored property, so an instance MUST be safe to read from any thread or
  actor without additional synchronization.
- **default-defaults-source**: `DebugLaunchSwitch.isOn` (the no-argument
  computed property) MUST forward to `isOn(defaults: .standard)`.
- **injectable-defaults-parameter**: `DebugLaunchSwitch.isOn(defaults:)` MUST
  accept its `UserDefaults` source as a parameter rather than reading
  `.standard` internally, so a caller MAY supply an isolated `UserDefaults`
  suite instead of the real one.
- **debug-build-reads-argument-domain**: `isOn(defaults:)`, when compiled
  with the `DEBUG` flag set, MUST return `defaults.bool(forKey: key)`.
- **release-build-always-off**: `isOn(defaults:)`, when compiled without the
  `DEBUG` flag, MUST return `false` unconditionally, without reading the
  `defaults` parameter at all — the switch MUST be unreachable in a Release
  build regardless of any launch argument, preference, or profile passed to
  it.
- **quiet-activation-gate**: `NSApplication.activateUnlessQuiet()` MUST
  return immediately, without calling `activate(ignoringOtherApps:)`, when
  `QuietWindowPresentation.isEnabled` is `true` (`NSApplication+QuietActivation.swift`).
- **loud-activation-behavior**: `activateUnlessQuiet()` MUST call
  `activate(ignoringOtherApps: true)` when `QuietWindowPresentation.isEnabled`
  is `false`.
- **test-host-detection**: `NSWindow.isRunningInTests` MUST return `true` if
  and only if `NSClassFromString("XCTestCase")` resolves to a non-nil class,
  and MUST return `false` otherwise (`NSWindow+TestHostVisibility.swift`).
- **sink-level-only**: `sinkBehindDesktop()` MUST change only the window's
  `level` property, setting it to `NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))`,
  and MUST NOT call `orderOut`, `close`, or change `isVisible`/`alphaValue`.
- **quiet-order-front**: `orderFrontQuietly()` MUST call `sinkBehindDesktop()`
  before calling `orderFront(nil)` when `QuietWindowPresentation.isEnabled`
  is `true`, and MUST call only `orderFront(nil)` when it is `false`.
- **quiet-make-key-and-order-front**: `makeKeyAndOrderFrontQuietly()` MUST
  call `sinkBehindDesktop()` before calling `makeKeyAndOrderFront(nil)` when
  `QuietWindowPresentation.isEnabled` is `true`, and MUST call only
  `makeKeyAndOrderFront(nil)` when it is `false`.
- **level-set-before-ordering**: `orderFrontQuietly()` and
  `makeKeyAndOrderFrontQuietly()` MUST set the window's level before
  performing their ordering call, so the window MUST NOT be visible at the
  normal level even briefly on its way to the sunk level (per the doc comment).
- **quiet-methods-main-actor-isolation**: `orderFrontQuietly()` and
  `makeKeyAndOrderFrontQuietly()` MUST be declared `@MainActor`; `sinkBehindDesktop()` and `isRunningInTests` carry no actor annotation
  in this source file.
- **quiet-presentation-main-actor-isolation**: `QuietWindowPresentation` MUST
  be declared `@MainActor` at the enum level, so every member —
  `debugSwitch`, `defaultsKey`, `isEnabled`, and `resolve(isTestHost:defaults:)`
  — MUST be confined to the main actor (`QuietWindowPresentation.swift`).
- **debug-switch-fixed-key**: `QuietWindowPresentation.debugSwitch` MUST be
  constructed as `DebugLaunchSwitch("QuietWindowPresentation")`, a fixed
  literal key.
- **defaults-key-alias**: `QuietWindowPresentation.defaultsKey` MUST return
  `debugSwitch.key` exactly, i.e. the same string
  `"QuietWindowPresentation"`.
- **is-enabled-live-read**: `QuietWindowPresentation.isEnabled` MUST evaluate
  `resolve(isTestHost: NSWindow.isRunningInTests, defaults: .standard)`
  freshly on every access; it MUST NOT cache or memoize the result.
- **resolve-or-precedence**: `resolve(isTestHost:defaults:)` MUST return
  `true` when `isTestHost` is `true`, and otherwise MUST return
  `debugSwitch.isOn(defaults: defaults)`.
- **test-host-short-circuits-defaults-read**: Because Swift's `||` operator
  short-circuits, `resolve(isTestHost:defaults:)` MUST NOT evaluate
  `debugSwitch.isOn(defaults: defaults)` — and therefore MUST NOT read the
  `defaults` parameter at all — when `isTestHost` is `true`.

## Appearance

Not applicable — this is a set of launch-argument and window-level
primitives, not a visual component.

## States

Not applicable — this is a set of launch-argument and window-level
primitives, not a visual component. The one runtime state these files carry
— whether presentation is currently "quiet" — is a boolean decision covered
above under Behavioral Requirements (`quiet-activation-gate` through
`test-host-short-circuits-defaults-read`), not a visual state.

## Accessibility

Not applicable — this is a set of launch-argument and window-level
primitives, not a visual component. `sinkBehindDesktop()` changes a window's
z-order level, never its accessibility role, label, or announcements.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| foundation-debug-automation-001 | switch-key-identity, release-build-always-off / debug-build-reads-argument-domain | `DebugLaunchSwitch("NeverPassed").isOn(defaults:)` against a scratch `UserDefaults` suite with no keys set (`DebugLaunchSwitchTests.swift`, `testASwitchIsOffUntilItsLaunchArgumentSaysOtherwise`). | Returns `false`. |
| foundation-debug-automation-002 | debug-build-reads-argument-domain | `DebugLaunchSwitch("SomeDebugBehavior").isOn(defaults:)` against a scratch suite with that key set to `true`, under a Debug build. | Returns `true`. |
| foundation-debug-automation-003 | debug-switch-fixed-key, defaults-key-alias | Read `QuietWindowPresentation.debugSwitch.key` and `QuietWindowPresentation.defaultsKey` (`DebugLaunchSwitchTests.swift`, `testTheKeyIsTheArgumentName`). | Both equal the string `"QuietWindowPresentation"`. |
| foundation-debug-automation-004 | resolve-or-precedence, test-host-short-circuits-defaults-read | `QuietWindowPresentation.resolve(isTestHost: true, defaults:)` against a scratch suite with `defaultsKey` set to `false` (`QuietWindowPresentationTests.swift`, `testATestHostIsAlwaysQuietWhateverTheDefaultsSay`). | Returns `true`, regardless of the stored `false`. |
| foundation-debug-automation-005 | resolve-or-precedence | `QuietWindowPresentation.resolve(isTestHost: false, defaults:)` against a scratch suite with `defaultsKey` set to `true` (`testTheLaunchArgumentTurnsQuietPresentationOnOutsideATestHost`). | Returns `true`. |
| foundation-debug-automation-006 | resolve-or-precedence | `QuietWindowPresentation.resolve(isTestHost: false, defaults:)` against an empty scratch suite (`testAnOrdinaryLaunchIsNotQuiet`). | Returns `false`. |
| foundation-debug-automation-007 | is-enabled-live-read, test-host-detection | `QuietWindowPresentation.isEnabled` read from inside the running XCTest process itself (`testTheProcessRunningThisSuiteIsQuiet`). | Returns `true` — `isEnabled` reads the live environment (this process is an XCTest host), not merely `resolve(isTestHost:defaults:)` in isolation. |
| foundation-debug-automation-008 | quiet-order-front, quiet-activation-gate (ordering half) | `SingleWindowController.forcesWindowFront`, evaluated as `!QuietWindowPresentation.isEnabled` while running under XCTest (`testQuietPresentationSuppressesFrontForcing`). | Returns `false`, confirming `isEnabled` is `true` for the calling process. |
| foundation-debug-automation-009 | sink-level-only, quiet-make-key-and-order-front, level-set-before-ordering | Build a fresh `NSWindow` and call `makeKeyAndOrderFrontQuietly()` while `QuietWindowPresentation.isEnabled` is `true` (`testAQuietlyShownWindowIsVisibleButSunkBehindTheDesktop`). | `window.isVisible` is `true`, `window.screen` is non-nil, and `window.level` equals `NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))`. |
| foundation-debug-automation-010 | quiet-make-key-and-order-front | Compare the `isKeyWindow` of a window shown with plain `makeKeyAndOrderFront(nil)` against one shown with `makeKeyAndOrderFrontQuietly()`, both while `isEnabled` is `true` (`testSinkingCostsNoKeyStatusAPlainOrderFrontWouldHaveGiven`). | The two `isKeyWindow` values are equal — sinking the level costs no key status a plain call would have given. |

## Edge Cases

- **Null and empty input**: `DebugLaunchSwitch.init(_:)` takes a
  non-optional `String` and performs no validation; an empty string `""` is
  accepted and stored as `key`, and `UserDefaults.bool(forKey: "")` is a
  legal (if useless) lookup that never crashes (MUST, see
  **switch-key-identity**).
- **Boundary values**: The only boundary in this component is the
  compile-time `DEBUG`/Release split itself, exercised by the two branches
  of `isOn(defaults:)`'s `#if DEBUG` (MUST, see
  **debug-build-reads-argument-domain** and **release-build-always-off**);
  there is no numeric range or size to bound.
- **Concurrent access**: `DebugLaunchSwitch` is an immutable, `Sendable`
  value type, so concurrent reads of `isOn`/`isOn(defaults:)` from multiple
  threads or actors require no synchronization of their own (MUST, see
  **switch-sendable-hashable-value-type**). `QuietWindowPresentation` and
  the two `@MainActor` `NSWindow` methods are confined to the main actor by
  declaration, so the compiler serializes all access to `isEnabled`,
  `resolve(isTestHost:defaults:)`, `orderFrontQuietly()`, and
  `makeKeyAndOrderFrontQuietly()` (MUST, see
  **quiet-presentation-main-actor-isolation**,
  **quiet-methods-main-actor-isolation**). `sinkBehindDesktop()` and
  `isRunningInTests` carry no actor annotation in this source file; nothing
  in `NSWindow+TestHostVisibility.swift` itself enforces that either is
  called on the main thread, though every call site in this recipe's own
  files reaches them only from an already-`@MainActor` caller (MUST, see
  **quiet-methods-main-actor-isolation**).
- **Error states**: None of the four files exposes a `throws` or failable
  API. `UserDefaults.bool(forKey:)` never throws — it returns `false` for a
  missing or non-Boolean key by Foundation's own contract — and
  `NSClassFromString` never throws. This component has no network, database,
  or file-system dependency whose unavailability it needs to report (MUST —
  there is no error path to define, not an omitted one).
- **Offline or disconnected state**: Not applicable — none of the four
  `DebugAutomation` files makes a network call or models a connectivity
  state.
- **Colliding switch keys**: `DebugLaunchSwitch` has no built-in namespacing
  or collision guard; two `DebugLaunchSwitch` values constructed with the
  same key string observe the same `UserDefaults`/launch-argument slot,
  since `Hashable`/`Equatable` conformance is exactly string equality on
  `key`. This is the documented contract — "the `UserDefaults` key, which is
  also the launch-argument name" (`DebugLaunchSwitch.swift`) — not an
  omitted guard (MUST, see **switch-key-identity**).
- **XCTest-framework linkage outside an actual test run**: `isRunningInTests`
  reports `true` whenever the `XCTestCase` class is resolvable in the
  current process, per its own stated assumption that "XCTest links its own
  framework into the runner, so the class exists in a test run and nowhere
  else" (`NSWindow+TestHostVisibility.swift`). A host process that
  happens to link `XCTest.framework` for some other reason would also report
  `true`; this is the documented assumption the check relies on, not a
  validation this file performs (MUST, see **test-host-detection**).
- **Live mutation of the launch argument or default mid-process**: neither
  `isOn(defaults:)` nor `isEnabled` caches its result; each re-evaluates its
  `UserDefaults`/`NSClassFromString` read on every call, so a value changed
  in the supplied `UserDefaults` between two calls MUST be reflected on the
  very next read (MUST, see **is-enabled-live-read**,
  **injectable-defaults-parameter**).
- **Repeated calls with no intervening state change**: calling
  `sinkBehindDesktop()`, `orderFrontQuietly()`,
  `makeKeyAndOrderFrontQuietly()`, or `activateUnlessQuiet()` more than once
  in a row, with `QuietWindowPresentation.isEnabled` unchanged between calls,
  MUST leave the window or app in the same observable state a single call
  would have produced — each is a single property assignment or a single
  AppKit ordering/activation call, not an accumulating counter (MUST, see
  **sink-level-only**, **quiet-order-front**,
  **quiet-make-key-and-order-front**, **loud-activation-behavior**).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `key` (`DebugLaunchSwitch.init(_:)`) | `String` | none — required at construction | Caller-supplied name shared as both the `UserDefaults` key and the launch-argument name, e.g. `"QuietWindowPresentation"` or the doc comment's own example `"MultipleInstances"` (`DebugLaunchSwitch.swift`). |
| Launch argument | CLI flag, e.g. `-QuietWindowPresentation YES` | absent | Passed as `open -n -g -a <App> --args -<key> YES`; written into the process's argument domain, which `isOn(defaults:)` reads through `UserDefaults`, and which lasts exactly as long as that one process. |
| `defaults` (`isOn(defaults:)` parameter) | `UserDefaults` | `.standard`, via the no-argument `isOn` | Injectable so a test can supply an isolated `UserDefaults` suite instead of the developer's real preferences. |
| `DEBUG` compilation flag | compiler build configuration | project-configured (Debug vs. Release) | Gates whether `isOn(defaults:)` ever consults `defaults` at all; a Release build removes the check entirely. |

None of the four files reads a `ProcessInfo.environment` variable or any
settings key of its own beyond the `UserDefaults` key described above.

## Deep Linking

Not applicable: none of the four `DebugAutomation` files defines a URL
scheme, route, or navigation destination — this is a process-internal
launch-argument and window-ordering mechanism, not app navigation.

## Localization

Not applicable: none of the four files produces a user-facing string.
`DebugLaunchSwitch.key` and `QuietWindowPresentation.defaultsKey` are
internal `UserDefaults`/launch-argument identifiers, never displayed to a
user.

## Accessibility Options

Not applicable: the four files present no UI of their own — they change an
already-existing `NSWindow`'s `level` and ordering, or skip `NSApplication`
activation, and respond to no Reduce Motion, Increase Contrast, or
Differentiate Without Color setting.

## Feature Flags

Not applicable: `DebugAutomation` defines no feature-flag key gating whether
it, itself, is enabled. It is the opposite direction — a launch-argument
primitive (`DebugLaunchSwitch`) that other code, such as
`QuietWindowPresentation`'s own `"QuietWindowPresentation"` key (see
Configuration), builds a flag from.

## Analytics

Not applicable: none of the four files calls an analytics or
event-tracking API.

## Privacy

Not applicable: `DebugAutomation` reads and writes only a caller-named
Boolean flag under a `UserDefaults` key equal to a launch-argument name
(e.g. `"QuietWindowPresentation"`); no user-generated, personal, or
credential data is read, written, or transmitted by any of the four files.

## Logging

Not applicable: none of the four files contains a `Logger`, `print`, or
other logging call.

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
  `process.env.NODE_ENV !== 'production'` gate (build-time, like `#if
  DEBUG`) combined with a URL query parameter or `localStorage` flag in
  place of the argument domain. There is also no desktop window level to
  sink behind — a browser tab does not share desktop z-order with other
  native applications the way an `NSWindow` does, so an E2E harness
  (Playwright/Cypress) drives the page without the app needing to suppress
  its own foregrounding.
- **AppKit / UIKit**: This recipe is extracted directly from AppKit (the
  source platform); see Behavioral Requirements above for the concrete API
  surface (`NSApplication`, `NSWindow`, `CGWindowLevelForKey`). UIKit (iOS)
  has no multi-app desktop compositing or unfocused-app foregrounding
  concept in the same sense — an iOS app is always the single foreground
  app when running — so there is no `sinkBehindDesktop()` analogue; the
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

**Decision**: `DebugLaunchSwitch` is a distinct reusable type rather than an
inline `UserDefaults.bool(forKey:)` call at each use site.
**Rationale**: Per the type's own doc comment, a switch read this way lives
only in the launch-argument domain, not a written preference — so a stale
`defaults write` cannot leave a developer wondering later why the app
behaves oddly — and the `#if DEBUG` check is evaluated exactly once, in this
type, so no call site can forget it (`DebugLaunchSwitch.swift`).
**Approved**: pending

**Decision**: `sinkBehindDesktop()` changes only the window's `level`,
leaving ordering, key status, and visibility to the caller, rather than
hiding the window (`orderOut`, `isVisible = false`) or moving it off-screen.
**Rationale**: A test still has to assert `isVisible`, the restored frame,
`window.screen`, and first-responder changes — all of which a genuinely
hidden or off-screen window would fail — while a person at the keyboard
must not see it "in front of them"; dropping the level below the desktop
gives AppKit a real, laid-out, visible window and gives the person at the
keyboard nothing (`NSWindow+TestHostVisibility.swift`).
**Approved**: pending

**Decision**: `orderFrontQuietly()` and `makeKeyAndOrderFrontQuietly()` set
the window's level *before* calling `orderFront`/`makeKeyAndOrderFront`,
rather than ordering first and sinking afterward.
**Rationale**: Per the doc comment, this ordering keeps the window from
ever being briefly visible at the normal level on its way to the sunk
level — a flash a person at the keyboard could otherwise catch.
**Approved**: pending

**Decision**: `QuietWindowPresentation.isEnabled` is the OR of two
independent signals — `NSWindow.isRunningInTests` and the Debug-only
`debugSwitch.isOn` — rather than a single flag, and `resolve(isTestHost:defaults:)`
exists as a separate function taking both as parameters.
**Rationale**: The doc comment states both are "the same situation twice":
a test host must always stay quiet, with no launch argument required, while
an automated Debug session needs the argument because it is not itself an
XCTest process. Exposing `resolve` with both inputs as parameters makes both
branches independently testable — under XCTest, `isEnabled` would otherwise
always short-circuit to `true` and the Debug-only branch could never be
exercised (`QuietWindowPresentation.swift`).
**Approved**: pending

**Decision**: `NSApplication.activateUnlessQuiet()` generalizes to app
activation the same suppression that `SingleWindowController.forcesWindowFront`
already established for window ordering, as one shared gate rather than a
bare `activate(ignoringOtherApps:)` repeated at each call site.
**Rationale**: The doc comment records that eleven call sites previously
called `activate(ignoringOtherApps:)` directly, so the quiet flag was
honored by whichever of them happened to remember it and ignored by the
rest; centralizing the check in one extension method removes that
per-call-site inconsistency (`NSApplication+QuietActivation.swift`).
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
