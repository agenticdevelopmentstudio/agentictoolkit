<!-- leaf: implement-foundation/debug-automation · source: foundation-debug-automation.md -->

**Rules** (cite as `implement-foundation/debug-automation#<slug>`):

- `switch-key-identity` MUST
- `switch-sendable-hashable-value-type` MUST
- `default-defaults-source` MUST
- `injectable-defaults-parameter` MUST
- `debug-build-reads-argument-domain` MUST
- `release-build-always-off` MUST
- `quiet-activation-gate` MUST
- `loud-activation-behavior` MUST
- `test-host-detection` MUST
- `sink-level-only` MUST
- `quiet-order-front` MUST
- `quiet-make-key-and-order-front` MUST
- `level-set-before-ordering` MUST
- `quiet-methods-main-actor-isolation` MUST
- `quiet-presentation-main-actor-isolation` MUST
- `debug-switch-fixed-key` MUST
- `defaults-key-alias` MUST
- `is-enabled-live-read` MUST
- `resolve-or-precedence` MUST
- `test-host-short-circuits-defaults-read` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `key` (`DebugLaunchSwitch.init(_:)`) | `String` | none — required at construction | Caller-supplied name shared as both the `UserDefaults` key and the launch-argument name, e.g. `"QuietWindowPresentation"` or the doc comment's own example `"MultipleInstances"` (`DebugLaunchSwitch.swift`). |
| Launch argument | CLI flag, e.g. `-QuietWindowPresentation YES` | absent | Passed as `open -n -g -a <App> --args -<key> YES`; written into the process's argument domain, which `isOn(defaults:)` reads through `UserDefaults`, and which lasts exactly as long as that one process. |
| `defaults` (`isOn(defaults:)` parameter) | `UserDefaults` | `.standard`, via the no-argument `isOn` | Injectable so a test can supply an isolated `UserDefaults` suite instead of the developer's real preferences. |
| `DEBUG` compilation flag | compiler build configuration | project-configured (Debug vs. Release) | Gates whether `isOn(defaults:)` ever consults `defaults` at all; a Release build removes the check entirely. |

None of the four files reads a `ProcessInfo.environment` variable or any
settings key of its own beyond the `UserDefaults` key described above.

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

