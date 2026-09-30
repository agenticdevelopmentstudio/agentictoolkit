<!-- leaf: implement-foundation/debug-automation--part-2 · source: foundation-debug-automation.md -->

# Foundation Debug Automation — continued (part 2)

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
