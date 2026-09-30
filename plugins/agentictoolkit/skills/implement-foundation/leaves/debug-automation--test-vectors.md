<!-- leaf: implement-foundation/debug-automation--test-vectors · source: foundation-debug-automation.md -->

# Foundation Debug Automation

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
