---
id: 54413e61-d82d-4526-b496-5daf917ce877
title: Window Activation
domain: agentictoolkit://recipes/window-management-window-activation
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: macOS diagnostic harness that brings a target terminal window to the front
  via a cascade of activation strategies and logs every step.
platforms:
- swift
- macos
tags:
- window-management
- macos
- terminals
- diagnostics
depends-on:
- agentictoolkit://recipes/foundation-scripting
related:
- agentictoolkit://recipes/window-management-screen-manager
references: []
approved-by: ''
approved-date: ''
---

# Window Activation

## Overview

Window Activation is a macOS logic package that tries to bring a specific
terminal window (identified by process, project name, working directory and
`$TERM_PROGRAM`) to the front, and records a detailed diagnostic log of how it
did so. It is intended for developer and QA use to diagnose why a terminal
window will not come to the front.

The package consists of:

- `WindowActivationTarget` — an app-agnostic value describing the window to activate.
- `WindowActivationStrategy` — the protocol for one step of the activation cascade.
- Three built-in strategies: `ITermTTYStrategy`, `AXTitleMatchStrategy`, `BringTerminalToFrontStrategy`.
- `KnownTerminal` / `KnownTerminals` — the catalog of terminals matched by `$TERM_PROGRAM`.
- `RunningAppsProvider` / `RealRunningAppsProvider` — a narrow abstraction over the running-application list, injectable for tests.
- `TTYResolver` (internal) — resolves a PID's controlling TTY by running `ps`.
- `ActivationTestLog` — a thread-safe, append-only, timestamped log mirrored to memory and optionally a file.
- `WindowActivationTester` — the harness that runs the cascade over a list of targets, verifies the frontmost window after each, and returns pass/fail counts.

Use it when an app (for example the Session Watcher list) needs to raise the
terminal window that owns a session and wants a written trace of each attempt.

## Behavioral Requirements

### WindowActivationTarget

- **target-fields**: `WindowActivationTarget` MUST carry exactly five immutable fields: `identifier` (String, shown in logs), `projectName` (String, used for title matching), `cwd` (String, working directory, used for title matching), `pid` (Int32, POSIX process ID, used for TTY resolution) and `termProgram` (String, the `$TERM_PROGRAM` value).
- **target-unknown-term-program**: An unknown `$TERM_PROGRAM` MUST be represented as the empty string in `termProgram`, per the field's doc comment.
- **target-value-semantics**: `WindowActivationTarget` MUST be a `Sendable`, `Equatable` value type with memberwise equality over all five fields.

### WindowActivationStrategy

- **strategy-name**: Every strategy MUST expose a short human-readable `name` used in log lines.
- **strategy-applies-to**: Every strategy MUST answer `appliesTo(target)` synchronously with a Bool and no side effects on the log.
- **strategy-activate-signature**: Every strategy MUST implement `activate(target, log:)` returning `true` when it considers the target's window brought to the front and `false` otherwise, appending its own diagnostics to the supplied `ActivationTestLog`.
- **strategy-sendable**: The strategy protocol MUST require `Sendable` conformance.

### ITermTTYStrategy

- **iterm-name**: `ITermTTYStrategy.name` MUST be `iTerm TTY`.
- **iterm-applies**: `ITermTTYStrategy` MUST apply when `termProgram` equals `iTerm.app` exactly or is the empty string, and MUST NOT apply for any other value.
- **iterm-no-tty**: When the target's PID has no resolvable TTY, the strategy MUST append `  iTerm TTY: pid <pid> has no TTY` and return `false` without running any script.
- **iterm-dev-prefix**: The strategy MUST prefix the resolved TTY with `/dev/` unless it already starts with `/dev/`.
- **iterm-script**: The strategy MUST run one AppleScript against the application `iTerm2` that walks every window and every tab, compares the tab's current session `tty` to the `/dev/` path, and on the first match selects that tab, activates iTerm2 and returns `found`; if no tab matches the script MUST return `not_found`.
- **iterm-success**: The strategy MUST return `true` only when the script succeeds and its string result, trimmed of whitespace and newlines, equals `found`.
- **iterm-not-found**: When the script succeeds with any other result (including no string), the strategy MUST append `  iTerm TTY: <devTTY> not found in any iTerm session` and return `false`.
- **iterm-compile-failed**: When the script fails to compile, the strategy MUST append `  iTerm TTY: AppleScript failed to compile` and return `false`.
- **iterm-runtime-failed**: When the script fails at runtime, the strategy MUST append `  iTerm TTY: AppleScript failed: <message> (error <number>)` and return `false`.
- **applescript-thread**: AppleScript runs on the caller's thread. `AppleScriptRunner`'s doc comment says `NSAppleScript` requires the main thread on some macOS versions and that background callers should marshal to main if needed; `WindowActivationTester.runAllTests` is documented "Call from a background thread", and both `ITermTTYStrategy.activate` and the tester's iTerm enumeration call `AppleScriptRunner.run` directly on that thread without hopping to main. A port SHOULD run its scripting calls on whatever thread its platform's scripting API requires.

### AXTitleMatchStrategy

- **ax-name**: `AXTitleMatchStrategy.name` MUST be `AX title match`.
- **ax-applies**: `AXTitleMatchStrategy` MUST apply whenever `projectName` is not exactly `Unknown` (case-sensitive), including when it is empty.
- **ax-regular-apps-only**: The strategy MUST consider only running applications whose activation policy is regular (Dock-visible apps), skipping accessory and background apps.
- **ax-app-order**: The strategy MUST walk applications in the order the `RunningAppsProvider` returns them and each application's accessibility windows in the order the accessibility API returns them, stopping at the first match.
- **ax-skip-unreadable**: The strategy MUST skip an application whose accessibility window list cannot be read, and MUST skip any window whose title is missing or empty.
- **ax-match-rule**: A window MUST match when its title contains, by localized case-insensitive comparison, any one of: `projectName`, the last path component of `cwd`, or the full `cwd`.
- **ax-match-log**: On a match the strategy MUST append `  AX match: "<title>" in <app name>`, using `?` when the application has no localized name.
- **ax-activation-sequence**: On a match the strategy MUST activate the owning application, block the calling thread for 0.15 seconds, perform the accessibility raise action on the window, and then set the window's main attribute to true, in that order.
- **ax-raise-result**: NEEDS REVIEW: Not implemented in source. `AXTitleMatchStrategy.activate` returns `true` on a title match without checking the results of the application activate call, the raise action or the set-main call, so an AX failure is reported as success, contradicting the protocol's "Return `true` if the front window now belongs to the target"; whether a failed raise should return `false` needs a decision from the toolkit owner.
- **ax-no-match**: When no window in any regular application matches, the strategy MUST return `false` without appending a log line.
- **ax-injected-apps**: The strategy MUST read the running-application list only through its injected `RunningAppsProvider`, defaulting to `RealRunningAppsProvider`.

### BringTerminalToFrontStrategy

- **front-name**: `BringTerminalToFrontStrategy.name` MUST be `bring terminal to front`.
- **front-applies**: The strategy MUST apply exactly when `KnownTerminals.match(termProgram:in:)` finds a catalog entry for the target's `termProgram` in the strategy's catalog.
- **front-catalog-default**: The strategy's catalog MUST default to `KnownTerminals.all` and MUST accept a caller-supplied catalog at init.
- **front-not-running**: When no catalog entry matches or no running application has the entry's bundle identifier, the strategy MUST return `false` without appending a log line.
- **front-activate-first**: When at least one running instance exists, the strategy MUST activate the first instance returned by the provider and does not select any specific window.
- **front-activate-result**: NEEDS REVIEW: Not implemented in source. `BringTerminalToFrontStrategy.activate` returns `true` after calling the application activate method without checking its Bool result, so a refused activation is reported as success, contradicting the protocol's "Return `true` if the front window now belongs to the target"; whether that result should gate the return value needs a decision from the toolkit owner.

### KnownTerminals

- **catalog-entries**: `KnownTerminals.all` MUST contain, in this order: iTerm2 (`com.googlecode.iterm2`, `iTerm.app`), Terminal.app (`com.apple.Terminal`, `Apple_Terminal`), Warp (`dev.warp.Warp-Stable`, `WarpTerminal`) and VS Code (`com.microsoft.VSCode`, `vscode`).
- **catalog-match**: `KnownTerminals.match(termProgram:in:)` MUST return the first entry in the catalog whose `termProgramValues` contains `termProgram` by exact, case-sensitive string equality, or `nil` when none does.
- **catalog-match-default**: `match` MUST search `KnownTerminals.all` when no catalog is passed.
- **known-terminal-value**: `KnownTerminal` MUST be a `Sendable`, `Equatable` value with `displayName`, `bundleID` and `termProgramValues` (an array, allowing several `$TERM_PROGRAM` values per terminal).

### RunningAppsProvider

- **provider-surface**: `RunningAppsProvider` MUST expose all running applications (unordered), the running applications for a given bundle identifier, and the frontmost application (optional).
- **provider-real**: `RealRunningAppsProvider` MUST delegate to the shared workspace's running-application list, the running-application lookup by bundle identifier, and the shared workspace's frontmost application.
- **provider-sendable**: The provider protocol MUST require `Sendable` conformance so strategies holding one stay `Sendable`.

### TTYResolver

- **tty-invalid-pid**: `TTYResolver.tty(forPID:)` MUST return `nil` without spawning a process when `pid` is 0 or negative.
- **tty-process**: For a positive PID the resolver MUST run `/bin/ps -p <pid> -o tty=`, discard standard error, block until the process exits, and read all of standard output.
- **tty-result**: The resolver MUST return the output decoded as UTF-8 and trimmed of whitespace and newlines (for example `s001`, with no `/dev/` prefix), or `nil` when the trimmed output is empty or the process fails to launch.
- **tty-internal**: `TTYResolver` MUST be internal to the module, not public API.

### ActivationTestLog

- **log-init-app-support**: `init(appSupportSubdirectory:)` MUST target `<user Application Support>/<appSupportSubdirectory>/activation-test.log`, creating the subdirectory (with intermediates) if missing.
- **log-init-no-app-support**: When the user Application Support directory cannot be located, `init(appSupportSubdirectory:)` MUST produce an in-memory-only log (`logPath` is `nil`) rather than crash, per its doc comment.
- **log-init-file-url**: `init(fileURL:)` MUST mirror entries to the given URL, or keep them in memory only when the URL is `nil`.
- **log-entry-format**: `append(message)` MUST store the entry `[<timestamp>] <message>`, where the timestamp is ISO 8601 internet date-time with fractional seconds captured at the moment `append` is called.
- **log-thread-safe-memory**: Reads and writes of the in-memory buffer MUST be serialized on one private serial queue so `append`, `clear` and `text` are safe from any thread.
- **log-text-format**: `text` MUST return every entry followed by a single newline, concatenated, or the empty string when there are no entries.
- **log-file-create**: On the first append to a file that does not exist, the log MUST create it by writing the entry and a newline atomically.
- **log-file-append-only**: When the file exists, the log MUST append the entry and a newline at the end and MUST NOT truncate existing content; if the file cannot be opened for writing, or the seek or write fails, the line MUST be dropped from the file (it remains in memory), per the `appendToFile` doc comment.
- **log-file-write-ordering**: NEEDS REVIEW: Not implemented in source. `ActivationTestLog.append` serializes only the in-memory append on its queue and calls `appendToFile` outside it, so concurrent appends can reach the file in a different order than the buffer and two first appends can both see a missing file and each write it atomically, losing a line, which breaks the declared guarantee that `text` and the file are byte-identical; whether file writes must move onto the queue needs a decision from the toolkit owner.
- **log-clear**: `clear()` MUST empty the in-memory buffer and, when a file URL exists, overwrite the file with an empty string atomically, ignoring any write error.
- **log-path**: `logPath` MUST return the file-system path of the log file, or `nil` for an in-memory-only log.
- **log-shared-instance**: `ActivationTestLog.whippetShared` MUST be one process-wide instance created with `appSupportSubdirectory` `Whippet`.
- **log-sendable**: `ActivationTestLog` MUST be a final class declared `@unchecked Sendable`, relying on its private serial queue for memory-buffer isolation.

### WindowActivationTester

- **tester-init**: `WindowActivationTester` MUST take `targets`, a `log`, a `strategies` list (default `defaultStrategies`) and a `runningApps` provider (default `RealRunningAppsProvider`).
- **tester-default-cascade**: `defaultStrategies` MUST be, in order: `ITermTTYStrategy`, `AXTitleMatchStrategy`, `BringTerminalToFrontStrategy`, each with default arguments.
- **tester-threading**: `WindowActivationTester` MUST be declared `@unchecked Sendable` and its doc comment declares it single-threaded: created on main, `runAllTests` run on a background queue, with no concurrent internal access.
- **tester-clear-first**: `runAllTests()` MUST clear the log before writing anything, then append `=== Window Activation Test Harness ===` and `Accessibility: GRANTED` or `Accessibility: DENIED` according to whether the process is trusted for accessibility.
- **tester-permission-abort**: When the process is not trusted for accessibility, `runAllTests()` MUST append `ABORT: Accessibility permission required` and return `(passed: 0, failed: 0)` without enumerating or testing any target and without reactivating the host app.
- **tester-header**: When trusted, `runAllTests()` MUST append `Targets: <count>`, `Strategies: <names joined by ", ">` and an empty line.
- **tester-inventory**: When trusted, `runAllTests()` MUST append a `--- Terminal Window Inventory ---` section iterating `KnownTerminals.all` (not the strategies' catalogs) in catalog order, logging `<displayName>: not running` or `<displayName>: PID=<pid>` for each.
- **tester-inventory-iterm**: For a running iTerm2 (`com.googlecode.iterm2`) the inventory MUST list every window (`  WINDOW id=<id> name=<name>`) and every tab (`    TAB <n>: tty=<tty> name=<name>`, 1-based) through one AppleScript, logging `  (no output)` for a nil result, `  (AppleScript compile failed)` for a compile failure, and `  (AppleScript failed: <message>, error <number>)` for a runtime failure.
- **tester-inventory-ax**: For any other running catalog terminal the inventory MUST list each accessibility window as `  AX[<index>]: "<title>"` (0-based, `<no title>` when the title is missing), or `  (no AX windows)` when the window list cannot be read.
- **tester-per-target**: The tester MUST test targets sequentially in the order given, blocking 1.0 second after each target.
- **tester-target-header**: For each target the tester MUST append `--- Test: <projectName> ---` followed by the `identifier`, `cwd`, `pid` and `termProgram` lines.
- **tester-cascade-stop**: The tester MUST run strategies in list order and stop attempting once one returns `true`, logging every later strategy as `  Strategy <name>: skipped (already activated)`.
- **tester-not-applicable**: A strategy whose `appliesTo` returns `false` MUST be logged as `  Strategy <name>: skipped (not applicable)` and not attempted.
- **tester-strategy-result**: Each attempted strategy MUST be logged as `  Strategy <name>: SUCCESS` or `  Strategy <name>: FAILED`.
- **tester-verify-delay**: After the cascade, whether or not any strategy succeeded, the tester MUST block 0.5 seconds and then read the frontmost window title, logging `  After activation: frontmost="<title>"`.
- **tester-frontmost-title**: The frontmost title MUST be the empty string when there is no frontmost app or its focused window or title cannot be read, and MUST be the literal `Sessions` when the frontmost app's bundle identifier equals the host app's own.
- **tester-verify-rule**: A target MUST pass when the frontmost title is non-empty and not exactly `Sessions`, and fail otherwise, logging `  Result: PASS` or `  Result: FAIL`; the verification does not check that the frontmost window belongs to the target.
- **tester-results**: After all targets `runAllTests()` MUST append an empty line and `=== Results: <passed> passed, <failed> failed ===` and return `(passed, failed)`.
- **tester-reactivate-host**: After a completed (non-aborted) run the tester MUST asynchronously, on the main queue, activate the host application ignoring other apps.
- **tester-no-cancellation**: `runAllTests()` MUST run to completion once started; it exposes no cancellation or timeout.

## Appearance

Not applicable — this is a macOS window-activation logic package and diagnostic harness, not a visual component.

## States

Not applicable — this is a macOS window-activation logic package and diagnostic harness, not a visual component.

## Accessibility

Not applicable — this is a macOS window-activation logic package and diagnostic harness, not a visual component.

## Conformance Test Vectors

No test file for this package exists in the repo (`AppleScriptRunnerTests.swift` covers only the runner); vectors are traced to the source.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| window-activation-001 | catalog-match | `KnownTerminals.match(termProgram: "WarpTerminal")` | Returns the Warp entry with bundle ID `dev.warp.Warp-Stable` |
| window-activation-002 | catalog-match | `KnownTerminals.match(termProgram: "iterm.app")` | Returns `nil` (match is case-sensitive) |
| window-activation-003 | catalog-match, catalog-match-default | `match(termProgram: "Foo", in: [KnownTerminal(displayName: "Foo", bundleID: "x.foo", termProgramValues: ["Foo"])])` | Returns the custom `Foo` entry |
| window-activation-004 | iterm-applies | Target with `termProgram` `""`, then `iTerm.app`, then `Apple_Terminal` | `ITermTTYStrategy().appliesTo` returns `true`, `true`, `false` |
| window-activation-005 | ax-applies | Target with `projectName` `Unknown`, then `unknown`, then `""` | `AXTitleMatchStrategy().appliesTo` returns `false`, `true`, `true` |
| window-activation-006 | front-applies, front-catalog-default | Target with `termProgram` `vscode`; target with `termProgram` `""` | `BringTerminalToFrontStrategy().appliesTo` returns `true`; returns `false` |
| window-activation-007 | front-not-running, ax-injected-apps | Stub provider returning no apps; target `termProgram` `Apple_Terminal` | `BringTerminalToFrontStrategy(runningApps: stub).activate` returns `false`; log unchanged |
| window-activation-008 | ax-no-match | Stub provider returning no apps; target `projectName` `demo` | `AXTitleMatchStrategy(runningApps: stub).activate` returns `false`; log unchanged |
| window-activation-009 | tty-invalid-pid, iterm-no-tty | Target with `pid` 0 run through `ITermTTYStrategy().activate` | Returns `false`; log gains one entry ending `  iTerm TTY: pid 0 has no TTY` |
| window-activation-010 | log-entry-format, log-text-format | `ActivationTestLog(fileURL: nil)`; `append("a")`; `append("b")` | `text` equals `[<ts1>] a\n[<ts2>] b\n` with ISO 8601 fractional-second timestamps; `logPath` is `nil` |
| window-activation-011 | log-text-format, log-clear | In-memory log with two entries; `clear()` | `text` equals `""` |
| window-activation-012 | log-file-create, log-file-append-only | `ActivationTestLog(fileURL: tmp)` where `tmp` is missing; `append("x")`; `append("y")` | File contents equal `text` byte for byte, two lines |
| window-activation-013 | log-clear | File-backed log with entries; `clear()` | File exists and is zero bytes |
| window-activation-014 | tester-permission-abort, tester-clear-first | Process not trusted for accessibility; `runAllTests()` | Returns `(0, 0)`; `text` is exactly the three lines harness header, `Accessibility: DENIED`, `ABORT: Accessibility permission required` |
| window-activation-015 | tester-cascade-stop, tester-strategy-result, tester-not-applicable | Trusted; strategies `[S1 applies returns true, S2 applies, S3 not applicable]` | Log shows `Strategy S1: SUCCESS`, `Strategy S2: skipped (already activated)`, `Strategy S3: skipped (already activated)`; S2 and S3 `activate` never called |
| window-activation-016 | tester-not-applicable, tester-strategy-result | Trusted; strategies `[S1 not applicable, S2 applies returns false]` | Log shows `Strategy S1: skipped (not applicable)` then `Strategy S2: FAILED` |
| window-activation-017 | tester-verify-rule, tester-frontmost-title | Trusted; stub provider with `frontmostApplication` `nil` | Log shows `After activation: frontmost=""` and `Result: FAIL`; target counted as failed |
| window-activation-018 | tester-results | Trusted; empty `targets` | Returns `(0, 0)`; log ends with `=== Results: 0 passed, 0 failed ===` |

## Edge Cases

- **Empty target list**: `runAllTests()` MUST still clear the log, run the permission check and inventory, and return `(0, 0)` with `Targets: 0`.
- **Accessibility denied**: The run MUST abort after three log lines and return `(0, 0)`; the host app is not reactivated.
- **Non-positive PID**: `TTYResolver` MUST return `nil` without spawning `ps`, so `ITermTTYStrategy` logs "has no TTY" and fails.
- **Exited process or no controlling TTY**: `ps` output is empty (it prints `??` for a process without a TTY, which is non-empty and is passed through), so an exited PID MUST yield `nil`; a `??` result MUST produce a `/dev/??` search that is not found.
- **`ps` hangs**: The resolver waits for exit with no timeout; a hung `ps` MUST block the calling thread indefinitely.
- **AppleScript hangs or iTerm2 not running**: The AppleScript call has no timeout; if iTerm2 is not running, `tell application "iTerm2"` MAY launch it before returning, and a dialog-blocked target app MUST block the calling thread until the Apple Event times out on its own.
- **Automation permission denied**: A refused Apple Event MUST surface as a runtime failure with its message and error number in the log, and the strategy returns `false`.
- **Empty `projectName` and `cwd`**: Localized case-insensitive containment of an empty string is false, so an empty `projectName` and empty `cwd` MUST match no window, and `AXTitleMatchStrategy` returns `false`.
- **Root `cwd`**: A `cwd` of `/` has last path component `/`, so any window whose title contains `/` MUST match.
- **Broad title match**: Matching is substring-based across every regular app, so a short `projectName` MUST match the first unrelated window whose title contains it (for example a browser tab).
- **Multiple running instances of one terminal**: `BringTerminalToFrontStrategy` MUST activate only the first instance the provider returns.
- **`termProgram` of an uncatalogued terminal**: Only the iTerm strategy (if empty) and the AX strategy can apply; `BringTerminalToFrontStrategy` MUST be skipped as not applicable.
- **Verification false positive**: Any non-empty frontmost title other than the host app MUST count as PASS even if it is not the target's window.
- **Host app title literally `Sessions`**: A foreign app whose focused window is titled `Sessions` MUST be counted as FAIL.
- **Application Support unavailable**: `init(appSupportSubdirectory:)` MUST fall back to in-memory-only logging.
- **Directory creation fails**: The error is ignored; the file URL is still set and every file write MUST silently fail while memory logging continues.
- **Log file deleted between writes**: The next append MUST recreate the file containing only that line; earlier memory entries are not rewritten.
- **Concurrent appends**: The in-memory buffer MUST stay consistent; file ordering is the open question on log-file-write-ordering.
- **Unbounded growth**: Neither the buffer nor the file has a size cap; both grow until `clear()` or process exit (the file persists across launches until the next `clear()`).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `WindowActivationTester.targets` | `[WindowActivationTarget]` | required | Windows to activate, tested in order |
| `WindowActivationTester.log` | `ActivationTestLog` | required | Destination for all diagnostics; cleared at the start of each run |
| `WindowActivationTester.strategies` | `[WindowActivationStrategy]` | `defaultStrategies` | Activation cascade, run in order |
| `WindowActivationTester.runningApps` | `RunningAppsProvider` | `RealRunningAppsProvider()` | Source of running and frontmost apps for inventory and verification |
| `AXTitleMatchStrategy.runningApps` | `RunningAppsProvider` | `RealRunningAppsProvider()` | Source of apps to scan for matching windows |
| `BringTerminalToFrontStrategy.catalog` | `[KnownTerminal]` | `KnownTerminals.all` | Terminals matched by `termProgram` |
| `BringTerminalToFrontStrategy.runningApps` | `RunningAppsProvider` | `RealRunningAppsProvider()` | Source of running instances by bundle ID |
| `ActivationTestLog.appSupportSubdirectory` | `String` | — | Subdirectory of user Application Support holding `activation-test.log` |
| `ActivationTestLog.fileURL` | `URL?` | — | Explicit mirror file, or `nil` for memory only |
| Accessibility trust | macOS privacy setting | — | Required; without it `runAllTests()` aborts |
| Automation (Apple Events) permission for iTerm2 | macOS privacy setting | — | Required for the iTerm strategy and inventory to succeed |

Fixed timings in source: 0.15 s between app activation and window raise, 0.5 s before verification, 1.0 s between targets.

## Deep Linking

Not applicable: the package exposes only Swift APIs and registers no URL scheme or route.

## Localization

Not applicable: every string the package produces is a hardcoded English diagnostic line written to `ActivationTestLog` for developers and QA, and none is shown in UI.

## Accessibility Options

Not applicable: the package renders nothing, so Reduce Motion, Increase Contrast and Differentiate Without Color have no effect on it.

## Feature Flags

Not applicable: the source reads no flag or setting; callers opt in by constructing a `WindowActivationTester`.

## Analytics

Not applicable: the source emits no analytics events; its only output is the local `ActivationTestLog`.

## Privacy

- **Data collected**: Target identifiers, project names, working-directory paths, PIDs, `$TERM_PROGRAM` values, and the titles of accessibility windows in running terminals and in any matched regular app.
- **Storage**: In memory and, for file-backed logs, in plain text at `~/Library/Application Support/<subdirectory>/activation-test.log` (`Whippet` for `whippetShared`).
- **Transmission**: None; nothing leaves the device.
- **Retention**: The file persists across launches and grows without bound until `clear()`, which `runAllTests()` calls at the start of each run.

## Logging

`ActivationTestLog` is the package's logging mechanism; it does not use the unified system log (no subsystem or category). File: `activation-test.log` under the configured Application Support subdirectory.

| Event | Level | Message |
|-------|-------|---------|
| Run start | info | `=== Window Activation Test Harness ===` |
| Permission state | info | `Accessibility: GRANTED` or `Accessibility: DENIED` |
| Permission abort | error | `ABORT: Accessibility permission required` |
| Terminal not running | info | `<displayName>: not running` |
| Strategy skipped | debug | `  Strategy <name>: skipped (not applicable)` or `(already activated)` |
| Strategy result | info | `  Strategy <name>: SUCCESS` or `FAILED` |
| iTerm failure | error | `  iTerm TTY: AppleScript failed: <message> (error <number>)` |
| AX match | debug | `  AX match: "<title>" in <app>` |
| Verification | info | `  Result: PASS` or `  Result: FAIL` |
| Run end | info | `=== Results: <passed> passed, <failed> failed ===` |

Levels are descriptive only; `ActivationTestLog` has no level field.

## Platform Notes

- **SwiftUI**: No SwiftUI surface. A SwiftUI host would run `runAllTests()` inside `Task.detached` and bind `ActivationTestLog.text` into a view after completion; the package itself stays AppKit and ApplicationServices based.
- **Compose**: Android has no cross-app window activation; a port would limit itself to bringing its own task forward via `ActivityManager.moveTaskToFront` or an `Intent` with `FLAG_ACTIVITY_REORDER_TO_FRONT`. The log maps to a `Mutex`-guarded `MutableList<String>` plus `File.appendText`, with `Dispatchers.IO` for the blocking work.
- **React/Web**: Browsers cannot enumerate or raise other applications' windows; only `window.focus()` on a window the page opened is possible. An Electron port would use `BrowserWindow.focus()` for its own windows and a native module for others; the log maps to `fs.appendFileSync` with `new Date().toISOString()`.
- **AppKit / UIKit**: Source platform. `BuiltInActivationStrategies.swift` and `WindowActivationTester.swift` use `AXUIElementCreateApplication`, `AXUIElementCopyAttributeValue` with `kAXWindowsAttribute` / `kAXTitleAttribute` / `kAXFocusedWindowAttribute`, `AXUIElementPerformAction(kAXRaiseAction)`, `AXIsProcessTrusted`, `NSRunningApplication.activate()` and `NSApp.activate(ignoringOtherApps:)`; `RunningAppsProvider.swift` wraps `NSWorkspace`; `TTYResolver.swift` uses `Process` and `Pipe`; `ActivationTestLog.swift` uses a serial `DispatchQueue`, `ISO8601DateFormatter` and `FileHandle`; AppleScript goes through `AppleScriptRunner` (`NSAppleScript`). UIKit has no equivalent: iOS apps cannot activate other apps' windows.
- **WinUI 3**: Enumerate top-level windows with Win32 `EnumWindows` plus `GetWindowText` / `GetWindowThreadProcessId` (P/Invoke or CsWin32), or UI Automation (`System.Windows.Automation.AutomationElement.RootElement.FindAll` with `NameProperty`) as the analogue of the AX title walk; raise with `SetForegroundWindow` (subject to foreground-lock rules, often needing `AllowSetForegroundWindow` or an `AttachThreadInput` workaround) and `ShowWindow(SW_RESTORE)`. Running apps come from `System.Diagnostics.Process.GetProcesses()` / `GetProcessesByName`, with `Process.MainWindowHandle` for the bring-to-front strategy; the catalog keys become process names (`WindowsTerminal`, `Code`) since `$TERM_PROGRAM` is rarely set. The iTerm2 TTY strategy has no Windows analogue; a Windows Terminal port would match by title or use `wt.exe` focus-tab commands. Verification reads `GetForegroundWindow` then `GetWindowText`. There is no Accessibility-trust gate, but UIPI blocks raising elevated windows from a non-elevated process. The log maps to a `lock`-guarded `List<string>` plus `File.AppendAllText` under `Windows.Storage.ApplicationData.Current.LocalFolder` (packaged) or `Environment.SpecialFolder.LocalApplicationData`, timestamps from `DateTimeOffset.UtcNow.ToString("o")`; `runAllTests` becomes a `Task.Run` returning `(int Passed, int Failed)`, with `Task.Delay` replacing `Thread.sleep` and `DispatcherQueue.TryEnqueue` replacing the final main-queue hop.

## Design Decisions

**Decision**: Activation is a cascade of pluggable `WindowActivationStrategy` values run in order, stopping at the first success.
**Rationale**: Each terminal needs a different technique (AppleScript TTY lookup for iTerm2, accessibility title match for others, plain app activation as a last resort); the protocol's `appliesTo` gate keeps inapplicable strategies out of the log as FAILED lines, and callers can supply their own list.
**Approved**: pending

**Decision**: Verification after the cascade only checks that some window other than the host app is frontmost with a non-empty title, and the host app is reported under the fixed label `Sessions`.
**Rationale**: The harness was written for the Session Watcher's "Sessions" window; the check detects "focus left our app" rather than "the target is frontmost", which makes PASS a weak signal (see Edge Cases).
**Approved**: pending

**Decision**: Fixed blocking sleeps (0.15 s, 0.5 s, 1.0 s) sequence activation, verification and the next target.
**Rationale**: App activation and window raising complete asynchronously in the window server; the harness is documented to run on a background thread, so blocking sleeps are an accepted diagnostic-only cost.
**Approved**: pending

**Decision**: `ActivationTestLog` never truncates an existing file on append and silently drops a line it cannot write.
**Rationale**: The `appendToFile` doc comment prefers losing one line over risking truncation of the history; memory keeps every entry regardless.
**Approved**: pending

**Decision**: `RunningAppsProvider` abstracts `NSWorkspace` so strategies and the tester can run against a stubbed app list, while the terminal inventory always uses `KnownTerminals.all`.
**Rationale**: Testability of strategies was the goal of the abstraction; the inventory is diagnostic output and was not parameterized by catalog.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | failed | Reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [main-thread-freedom](agenticdevelopercookbook://compliance/performance#main-thread-freedom) | passed | Performance |
| [platform-permissions](agenticdevelopercookbook://compliance/platform-compliance#platform-permissions) | partial | Platform Compliance |
| [data-retention-policy](agenticdevelopercookbook://compliance/privacy-and-data#data-retention-policy) | partial | Privacy and Data |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | partial | Privacy and Data |

separation-of-concerns passes because the target value, each strategy, the terminal catalog, the running-apps abstraction, TTY resolution, logging and the harness each live in their own type. unit-test-coverage fails because no test file exists for any type in the package, despite `RunningAppsProvider` and `ActivationTestLog(fileURL:)` being designed for injection. explicit-error-handling is partial: AppleScript compile and runtime failures and missing TTYs are logged with detail, but two strategies report success without checking the platform call results (the open questions on ax-raise-result and front-activate-result) and file write failures are dropped by design. timeout-handling fails because neither the `ps` subprocess nor the AppleScript calls have a timeout. graceful-degradation passes because a missing Application Support directory falls back to memory-only logging and a denied accessibility permission aborts cleanly with a logged reason. main-thread-freedom passes because `runAllTests()` is documented to run off the main thread and hops to main only for the final host reactivation, though applescript-thread notes that its AppleScript calls stay on that background thread. platform-permissions is partial: accessibility trust is checked and reported before any work, but Automation permission for iTerm2 is not checked up front and only surfaces as a runtime AppleScript error. data-retention-policy is partial because the file is cleared at each run start but otherwise grows without bound and persists across launches. no-pii-in-logs is partial because the log records working-directory paths (which include the user's home directory name) and window titles in plain text on disk.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation from `ActivationTestLog.swift`, `BuiltInActivationStrategies.swift`, `KnownTerminals.swift`, `RunningAppsProvider.swift`, `TTYResolver.swift`, `WindowActivationStrategy.swift`, `WindowActivationTarget.swift` and `WindowActivationTester.swift` |
