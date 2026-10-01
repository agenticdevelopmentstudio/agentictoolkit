---
id: 54413e61-d82d-4526-b496-5daf917ce877
title: Window Activation
domain: agentictoolkit://cookbook/system/system-windows/window-activation
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Diagnostic harness that brings a target terminal window to the front
  via a cascade of activation strategies and logs every step.
platforms:
- swift
- macos
tags:
- window-management
- terminals
- diagnostics
depends-on:
- agentictoolkit://cookbook/system/scripting
related:
- agentictoolkit://cookbook/ui/windows/screen-manager
references: []
approved-by: ''
approved-date: ''
---

# Window Activation

## Overview

Window Activation is a logic package that tries to bring a specific
terminal window (identified by process, project name, working directory and
the `$TERM_PROGRAM` value) to the front, and records a detailed diagnostic log of how it
did so. It is intended for developer and QA use to diagnose why a terminal
window will not come to the front.

The package consists of:

- **a window-activation target** — an app-agnostic value describing the window to activate.
- **the activation-strategy contract** — the interface for one step of the activation cascade.
- Three built-in strategies: **the iTerm TTY strategy**, **the accessibility title-match strategy**, **the bring-terminal-to-front strategy**.
- **the terminal catalog** — the catalog of terminals matched by the `$TERM_PROGRAM` value, made of individual catalog entries.
- **the running-applications provider** / **the real running-applications provider** — a narrow abstraction over the running-application list, injectable for tests.
- **the TTY resolver** (internal) — resolves a PID's controlling TTY by running `ps`.
- **the activation test log** — a thread-safe, append-only, timestamped log mirrored to memory and optionally a file.
- **the activation test harness** — runs the cascade over a list of targets, verifies the frontmost window after each, and returns pass/fail counts.

Use it when an app (for example the Session Watcher list) needs to raise the
terminal window that owns a session and wants a written trace of each attempt.

## Behavioral Requirements

### Window-activation target

- **target-fields**: A window-activation target MUST carry exactly five immutable fields: `identifier` (string, shown in logs), `projectName` (string, used for title matching), `cwd` (string, working directory, used for title matching), `pid` (process ID, used for TTY resolution) and `termProgram` (string, the `$TERM_PROGRAM` value).
- **target-unknown-term-program**: An unknown `$TERM_PROGRAM` MUST be represented as the empty string in `termProgram`, per the field's documentation.
- **target-value-semantics**: A window-activation target MUST be an immutable value type, safe to share across concurrent contexts, comparable for equality, with memberwise equality over all five fields.

### The activation-strategy contract

- **strategy-name**: Every strategy MUST expose a short human-readable name used in log lines.
- **strategy-applies-to**: Every strategy MUST answer whether it applies to a target synchronously with a boolean and no side effects on the log.
- **strategy-activate-signature**: Every strategy MUST implement an activation step that returns `true` when it considers the target's window brought to the front and `false` otherwise, appending its own diagnostics to the supplied log.
- **strategy-sendable**: The activation-strategy contract MUST require every strategy to be safe to share across concurrent contexts.

### The iTerm TTY strategy

- **iterm-name**: The iTerm TTY strategy's name MUST be `iTerm TTY`.
- **iterm-applies**: The strategy MUST apply when `termProgram` equals `iTerm.app` exactly or is the empty string, and MUST NOT apply for any other value.
- **iterm-no-tty**: When the target's PID has no resolvable TTY, the strategy MUST append `  iTerm TTY: pid <pid> has no TTY` and return `false` without running any script.
- **iterm-dev-prefix**: The strategy MUST prefix the resolved TTY with `/dev/` unless it already starts with `/dev/`.
- **iterm-script**: The strategy MUST run one script against iTerm2 that walks every window and every tab, compares the tab's current session `tty` to the `/dev/` path, and on the first match selects that tab, activates iTerm2 and returns `found`; if no tab matches the script MUST return `not_found`.
- **iterm-success**: The strategy MUST return `true` only when the script succeeds and its string result, trimmed of whitespace and newlines, equals `found`.
- **iterm-not-found**: When the script succeeds with any other result (including no string), the strategy MUST append `  iTerm TTY: <devTTY> not found in any iTerm session` and return `false`.
- **iterm-compile-failed**: When the script fails to compile, the strategy MUST append `  iTerm TTY: AppleScript failed to compile` and return `false`.
- **iterm-runtime-failed**: When the script fails at runtime, the strategy MUST append `  iTerm TTY: AppleScript failed: <message> (error <number>)` and return `false`.

### The accessibility title-match strategy

- **ax-name**: The strategy's name MUST be `AX title match`.
- **ax-applies**: The strategy MUST apply whenever `projectName` is not exactly `Unknown` (case-sensitive), including when it is empty.
- **ax-regular-apps-only**: The strategy MUST consider only running applications whose activation policy is regular (visible to the user as a normal running app), skipping accessory and background apps.
- **ax-app-order**: The strategy MUST walk applications in the order the running-applications provider returns them and each application's accessibility windows in the order the accessibility layer returns them, stopping at the first match.
- **ax-skip-unreadable**: The strategy MUST skip an application whose accessibility window list cannot be read, and MUST skip any window whose title is missing or empty.
- **ax-match-rule**: A window MUST match when its title contains, by localized case-insensitive comparison, any one of: `projectName`, the last path component of `cwd`, or the full `cwd`.
- **ax-match-log**: On a match the strategy MUST append `  AX match: "<title>" in <app name>`, using `?` when the application has no localized name.
- **ax-activation-sequence**: On a match the strategy MUST activate the owning application, block the calling thread for 0.15 seconds, perform the raise action on the window through the accessibility layer, and then set the window's main attribute to true, in that order.
- **ax-raise-result**: NEEDS REVIEW: Not implemented in source. The accessibility title-match strategy returns `true` on a title match without checking the results of the application activate call, the raise action or the set-main call, so an accessibility failure is reported as success, contradicting the contract's "Return `true` if the front window now belongs to the target"; whether a failed raise should return `false` needs a decision from the toolkit owner.
- **ax-no-match**: When no window in any regular application matches, the strategy MUST return `false` without appending a log line.
- **ax-injected-apps**: The strategy MUST read the running-application list only through its injected running-applications provider, defaulting to the real provider.

### The bring-terminal-to-front strategy

- **front-name**: The strategy's name MUST be `bring terminal to front`.
- **front-applies**: The strategy MUST apply exactly when the terminal catalog finds a matching entry for the target's `termProgram` in the strategy's catalog.
- **front-catalog-default**: The strategy's catalog MUST default to the full terminal catalog and MUST accept a caller-supplied catalog at construction.
- **front-not-running**: When no catalog entry matches or no running application has the entry's bundle identifier, the strategy MUST return `false` without appending a log line.
- **front-activate-first**: When at least one running instance exists, the strategy MUST activate the first instance returned by the provider and does not select any specific window.
- **front-activate-result**: NEEDS REVIEW: Not implemented in source. The bring-terminal-to-front strategy returns `true` after calling the application activate method without checking its boolean result, so a refused activation is reported as success, contradicting the contract's "Return `true` if the front window now belongs to the target"; whether that result should gate the return value needs a decision from the toolkit owner.

### The terminal catalog

- **catalog-entries**: The terminal catalog MUST contain, in this order: iTerm2 (`com.googlecode.iterm2`, `iTerm.app`), Terminal.app (`com.apple.Terminal`, `Apple_Terminal`), Warp (`dev.warp.Warp-Stable`, `WarpTerminal`) and VS Code (`com.microsoft.VSCode`, `vscode`).
- **catalog-match**: Matching a `termProgram` value against a catalog MUST return the first entry whose `termProgramValues` contains it by exact, case-sensitive string equality, or `nil` when none does.
- **catalog-match-default**: Matching MUST search the full terminal catalog when no catalog is passed.
- **known-terminal-value**: A terminal catalog entry MUST be an immutable value, comparable for equality, with `displayName`, `bundleID` and `termProgramValues` (an array, allowing several `$TERM_PROGRAM` values per terminal).

### The running-applications provider

- **provider-surface**: The running-applications provider MUST expose all running applications (unordered), the running applications for a given bundle identifier, and the frontmost application (optional).
- **provider-real**: The real running-applications provider MUST delegate to the shared workspace's running-application list, the running-application lookup by bundle identifier, and the shared workspace's frontmost application.
- **provider-sendable**: The provider contract MUST require every conformer to be safe to share across concurrent contexts, so strategies holding one stay safe to share too.

### The TTY resolver

- **tty-invalid-pid**: The TTY resolver MUST return `nil` without spawning a process when `pid` is 0 or negative.
- **tty-process**: For a positive PID the resolver MUST run `/bin/ps -p <pid> -o tty=`, discard standard error, block until the process exits, and read all of standard output.
- **tty-result**: The resolver MUST return the output decoded as UTF-8 and trimmed of whitespace and newlines (for example `s001`, with no `/dev/` prefix), or `nil` when the trimmed output is empty or the process fails to launch.
- **tty-internal**: The TTY resolver MUST be internal to the package, not part of its public interface.

### The activation test log

- **log-init-app-support**: Constructing the log with an application-support subdirectory MUST target `<user Application Support>/<subdirectory>/activation-test.log`, creating the subdirectory (with intermediates) if missing.
- **log-init-no-app-support**: When the user Application Support directory cannot be located, that construction path MUST produce an in-memory-only log (the log path is `nil`) rather than crash, per its documentation.
- **log-init-file-url**: Constructing the log with a file URL MUST mirror entries to that URL, or keep them in memory only when the URL is `nil`.
- **log-entry-format**: Appending a message MUST store the entry `[<timestamp>] <message>`, where the timestamp is ISO 8601 internet date-time with fractional seconds captured at the moment the append is called.
- **log-thread-safe-memory**: Reads and writes of the in-memory buffer MUST be serialized on one private queue so appending, clearing and reading the text are safe from any thread.
- **log-text-format**: Reading the log's text MUST return every entry followed by a single newline, concatenated, or the empty string when there are no entries.
- **log-file-create**: On the first append to a file that does not exist, the log MUST create it by writing the entry and a newline atomically.
- **log-file-append-only**: When the file exists, the log MUST append the entry and a newline at the end and MUST NOT truncate existing content; if the file cannot be opened for writing, or the seek or write fails, the line MUST be dropped from the file (it remains in memory), per its documentation.
- **log-file-write-ordering**: NEEDS REVIEW: Not implemented in source. Appending serializes only the in-memory append on its queue and writes to the file outside that queue, so concurrent appends can reach the file in a different order than the buffer and two first appends can both see a missing file and each write it atomically, losing a line, which breaks the declared guarantee that the text and the file are byte-identical; whether file writes must move onto the queue needs a decision from the toolkit owner.
- **log-clear**: Clearing MUST empty the in-memory buffer and, when a file URL exists, overwrite the file with an empty string atomically, ignoring any write error.
- **log-path**: Reading the log path MUST return the file-system path of the log file, or `nil` for an in-memory-only log.
- **log-shared-instance**: One process-wide shared instance MUST be created with the application-support subdirectory `Whippet`.
- **log-sendable**: The activation test log MUST be safe to share across concurrent contexts, relying on its private serial queue for memory-buffer isolation.

### The activation test harness

- **tester-init**: The activation test harness MUST take `targets`, a log, a strategies list (default the built-in cascade) and a running-applications provider (default the real provider).
- **tester-default-cascade**: The built-in cascade MUST be, in order: the iTerm TTY strategy, the accessibility title-match strategy, the bring-terminal-to-front strategy, each with default arguments.
- **tester-threading**: The activation test harness MUST be used single-threaded per its documentation: created on the main thread, with its run-all-tests operation run on a background queue and no concurrent internal access.
- **tester-clear-first**: Running all tests MUST clear the log before writing anything, then append `=== Window Activation Test Harness ===` and `Accessibility: GRANTED` or `Accessibility: DENIED` according to whether the process is trusted for accessibility.
- **tester-permission-abort**: When the process is not trusted for accessibility, running all tests MUST append `ABORT: Accessibility permission required` and return `(passed: 0, failed: 0)` without enumerating or testing any target and without reactivating the host app.
- **tester-header**: When trusted, running all tests MUST append `Targets: <count>`, `Strategies: <names joined by ", ">` and an empty line.
- **tester-inventory**: When trusted, running all tests MUST append a `--- Terminal Window Inventory ---` section iterating the full terminal catalog (not the strategies' catalogs) in catalog order, logging `<displayName>: not running` or `<displayName>: PID=<pid>` for each.
- **tester-inventory-iterm**: For a running iTerm2 (`com.googlecode.iterm2`) the inventory MUST list every window (`  WINDOW id=<id> name=<name>`) and every tab (`    TAB <n>: tty=<tty> name=<name>`, 1-based) through one script, logging `  (no output)` for a nil result, `  (AppleScript compile failed)` for a compile failure, and `  (AppleScript failed: <message>, error <number>)` for a runtime failure.
- **tester-inventory-ax**: For any other running catalog terminal the inventory MUST list each accessibility window as `  AX[<index>]: "<title>"` (0-based, `<no title>` when the title is missing), or `  (no AX windows)` when the window list cannot be read.
- **tester-per-target**: The harness MUST test targets sequentially in the order given, blocking 1.0 second after each target.
- **tester-target-header**: For each target the harness MUST append `--- Test: <projectName> ---` followed by the `identifier`, `cwd`, `pid` and `termProgram` lines.
- **tester-cascade-stop**: The harness MUST run strategies in list order and stop attempting once one returns `true`, logging every later strategy as `  Strategy <name>: skipped (already activated)`.
- **tester-not-applicable**: A strategy that reports it does not apply to the target MUST be logged as `  Strategy <name>: skipped (not applicable)` and not attempted.
- **tester-strategy-result**: Each attempted strategy MUST be logged as `  Strategy <name>: SUCCESS` or `  Strategy <name>: FAILED`.
- **tester-verify-delay**: After the cascade, whether or not any strategy succeeded, the harness MUST block 0.5 seconds and then read the frontmost window title, logging `  After activation: frontmost="<title>"`.
- **tester-frontmost-title**: The frontmost title MUST be the empty string when there is no frontmost app or its focused window or title cannot be read, and MUST be the literal `Sessions` when the frontmost app's bundle identifier equals the host app's own.
- **tester-verify-rule**: A target MUST pass when the frontmost title is non-empty and not exactly `Sessions`, and fail otherwise, logging `  Result: PASS` or `  Result: FAIL`; the verification does not check that the frontmost window belongs to the target.
- **tester-results**: After all targets, running all tests MUST append an empty line and `=== Results: <passed> passed, <failed> failed ===` and return `(passed, failed)`.
- **tester-reactivate-host**: After a completed (non-aborted) run the harness MUST asynchronously, on the main queue, activate the host application ignoring other apps.
- **tester-no-cancellation**: Running all tests MUST run to completion once started; it exposes no cancellation or timeout.

## Appearance

Not applicable — this is a window-activation logic package and diagnostic harness, not a visual component.

## States

Not applicable — this is a window-activation logic package and diagnostic harness, not a visual component.

## Accessibility

Not applicable — this is a window-activation logic package and diagnostic harness, not a visual component.

## Conformance Test Vectors

No test file for this package exists in the repo (only the scripting runner has its own test file); vectors are traced to the source.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| window-activation-001 | catalog-match | Matching `termProgram` "WarpTerminal" against the terminal catalog | Returns the Warp entry with bundle ID `dev.warp.Warp-Stable` |
| window-activation-002 | catalog-match | Matching `termProgram` "iterm.app" against the terminal catalog | Returns `nil` (match is case-sensitive) |
| window-activation-003 | catalog-match, catalog-match-default | Matching `termProgram` "Foo" against a custom catalog of one entry (displayName "Foo", bundleID "x.foo", termProgramValues ["Foo"]) | Returns the custom "Foo" entry |
| window-activation-004 | iterm-applies | Target with `termProgram` `""`, then `iTerm.app`, then `Apple_Terminal`, tested against the iTerm TTY strategy | Applies: `true`, `true`, `false` |
| window-activation-005 | ax-applies | Target with `projectName` `Unknown`, then `unknown`, then `""`, tested against the accessibility title-match strategy | Applies: `false`, `true`, `true` |
| window-activation-006 | front-applies, front-catalog-default | Target with `termProgram` `vscode`; target with `termProgram` `""`, tested against the bring-terminal-to-front strategy | Applies: `true`; then `false` |
| window-activation-007 | front-not-running, ax-injected-apps | Stub provider returning no apps; target `termProgram` `Apple_Terminal`, run through the bring-terminal-to-front strategy | Returns `false`; log unchanged |
| window-activation-008 | ax-no-match | Stub provider returning no apps; target `projectName` `demo`, run through the accessibility title-match strategy | Returns `false`; log unchanged |
| window-activation-009 | tty-invalid-pid, iterm-no-tty | Target with `pid` 0, run through the iTerm TTY strategy | Returns `false`; log gains one entry ending `  iTerm TTY: pid 0 has no TTY` |
| window-activation-010 | log-entry-format, log-text-format | A memory-only log; appending "a" then "b" | Log text equals `[<ts1>] a\n[<ts2>] b\n` with ISO 8601 fractional-second timestamps; log path is `nil` |
| window-activation-011 | log-text-format, log-clear | In-memory log with two entries; clearing it | Log text equals `""` |
| window-activation-012 | log-file-create, log-file-append-only | A file-backed log pointed at a missing file; appending "x" then "y" | File contents equal the log text byte for byte, two lines |
| window-activation-013 | log-clear | File-backed log with entries; clearing it | File exists and is zero bytes |
| window-activation-014 | tester-permission-abort, tester-clear-first | Process not trusted for accessibility; running the harness | Returns `(0, 0)`; log text is exactly the three lines harness header, `Accessibility: DENIED`, `ABORT: Accessibility permission required` |
| window-activation-015 | tester-cascade-stop, tester-strategy-result, tester-not-applicable | Trusted; strategies [S1 applies and returns true, S2 applies, S3 not applicable] | Log shows `Strategy S1: SUCCESS`, `Strategy S2: skipped (already activated)`, `Strategy S3: skipped (already activated)`; S2 and S3 never attempted |
| window-activation-016 | tester-not-applicable, tester-strategy-result | Trusted; strategies [S1 not applicable, S2 applies and returns false] | Log shows `Strategy S1: skipped (not applicable)` then `Strategy S2: FAILED` |
| window-activation-017 | tester-verify-rule, tester-frontmost-title | Trusted; stub provider with no frontmost application | Log shows `After activation: frontmost=""` and `Result: FAIL`; target counted as failed |
| window-activation-018 | tester-results | Trusted; empty target list | Returns `(0, 0)`; log ends with `=== Results: 0 passed, 0 failed ===` |

## Edge Cases

- **Empty target list**: Running the harness MUST still clear the log, run the permission check and inventory, and return `(0, 0)` with `Targets: 0`.
- **Accessibility denied**: The run MUST abort after three log lines and return `(0, 0)`; the host app is not reactivated.
- **Non-positive PID**: The TTY resolver MUST return `nil` without spawning `ps`, so the iTerm TTY strategy logs "has no TTY" and fails.
- **Exited process or no controlling TTY**: `ps` output is empty (it prints `??` for a process without a TTY, which is non-empty and is passed through), so an exited PID MUST yield `nil`; a `??` result MUST produce a `/dev/??` search that is not found.
- **`ps` hangs**: The resolver waits for exit with no timeout; a hung `ps` MUST block the calling thread indefinitely.
- **Scripting call hangs or iTerm2 not running**: The scripting call has no timeout; if iTerm2 is not running, telling it to perform the walk MAY launch it before returning, and a dialog-blocked target app MUST block the calling thread until the automation event times out on its own.
- **Automation permission denied**: A refused automation event MUST surface as a runtime failure with its message and error number in the log, and the strategy returns `false`.
- **Empty `projectName` and `cwd`**: Localized case-insensitive containment of an empty string is false, so an empty `projectName` and empty `cwd` MUST match no window, and the accessibility title-match strategy returns `false`.
- **Root `cwd`**: A `cwd` of `/` has last path component `/`, so any window whose title contains `/` MUST match.
- **Broad title match**: Matching is substring-based across every regular app, so a short `projectName` MUST match the first unrelated window whose title contains it (for example a browser tab).
- **Multiple running instances of one terminal**: The bring-terminal-to-front strategy MUST activate only the first instance the provider returns.
- **`termProgram` of an uncatalogued terminal**: Only the iTerm strategy (if empty) and the accessibility title-match strategy can apply; the bring-terminal-to-front strategy MUST be skipped as not applicable.
- **Verification false positive**: Any non-empty frontmost title other than the host app MUST count as PASS even if it is not the target's window.
- **Host app title literally `Sessions`**: A foreign app whose focused window is titled `Sessions` MUST be counted as FAIL.
- **Application Support unavailable**: Constructing the log MUST fall back to in-memory-only logging.
- **Directory creation fails**: The error is ignored; the file URL is still set and every file write MUST silently fail while memory logging continues.
- **Log file deleted between writes**: The next append MUST recreate the file containing only that line; earlier memory entries are not rewritten.
- **Concurrent appends**: The in-memory buffer MUST stay consistent; file ordering is the open question on log-file-write-ordering.
- **Unbounded growth**: Neither the buffer nor the file has a size cap; both grow until cleared or process exit (the file persists across launches until the next clear).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Harness targets | list of window-activation targets | required | Windows to activate, tested in order |
| Harness log | activation test log | required | Destination for all diagnostics; cleared at the start of each run |
| Harness strategies | list of strategies | the built-in cascade | Activation cascade, run in order |
| Harness running-apps source | running-applications provider | the real provider | Source of running and frontmost apps for inventory and verification |
| Accessibility title-match strategy, running-apps source | running-applications provider | the real provider | Source of apps to scan for matching windows |
| Bring-terminal-to-front strategy, catalog | list of terminal catalog entries | the full terminal catalog | Terminals matched by `termProgram` |
| Bring-terminal-to-front strategy, running-apps source | running-applications provider | the real provider | Source of running instances by bundle ID |
| Log's application-support subdirectory | string | — | Subdirectory of user Application Support holding `activation-test.log` |
| Log's file URL | URL or nil | — | Explicit mirror file, or `nil` for memory only |
| Accessibility trust | system privacy setting | — | Required; without it running the harness aborts |
| Automation permission for iTerm2 | system privacy setting | — | Required for the iTerm strategy and inventory to succeed |

Fixed timings in source: 0.15 s between app activation and window raise, 0.5 s before verification, 1.0 s between targets.

## Deep Linking

Not applicable: the package exposes only programmatic APIs and registers no URL scheme or route.

## Localization

Not applicable: every string the package produces is a hardcoded English diagnostic line written to the activation test log for developers and QA, and none is shown in UI.

## Accessibility Options

Not applicable: the package renders nothing, so Reduce Motion, Increase Contrast and Differentiate Without Color have no effect on it.

## Feature Flags

Not applicable: the source reads no flag or setting; callers opt in by constructing the activation test harness.

## Analytics

Not applicable: the source emits no analytics events; its only output is the local activation test log.

## Privacy

- **Data collected**: Target identifiers, project names, working-directory paths, PIDs, `$TERM_PROGRAM` values, and the titles of accessibility windows in running terminals and in any matched regular app.
- **Storage**: In memory and, for file-backed logs, in plain text at `~/Library/Application Support/<subdirectory>/activation-test.log` (`Whippet` for the shared instance).
- **Transmission**: None; nothing leaves the device.
- **Retention**: The file persists across launches and grows without bound until cleared, which running the harness does at the start of each run.

## Logging

The activation test log is the package's logging mechanism; it does not use the system log (no subsystem or category). File: `activation-test.log` under the configured Application Support subdirectory.

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

Levels are descriptive only; the log has no level field.

## Platform Notes

- **SwiftUI**: No SwiftUI surface. A SwiftUI host would run `runAllTests()` inside `Task.detached` and bind `ActivationTestLog.text` into a view after completion; the package itself stays AppKit and ApplicationServices based.
- **Compose**: Android has no cross-app window activation; a port would limit itself to bringing its own task forward via `ActivityManager.moveTaskToFront` or an `Intent` with `FLAG_ACTIVITY_REORDER_TO_FRONT`. The log maps to a `Mutex`-guarded `MutableList<String>` plus `File.appendText`, with `Dispatchers.IO` for the blocking work.
- **React/Web**: Browsers cannot enumerate or raise other applications' windows; only `window.focus()` on a window the page opened is possible. An Electron port would use `BrowserWindow.focus()` for its own windows and a native module for others; the log maps to `fs.appendFileSync` with `new Date().toISOString()`.
- **AppKit / UIKit**: Source platform. `BuiltInActivationStrategies.swift` and `WindowActivationTester.swift` use `AXUIElementCreateApplication`, `AXUIElementCopyAttributeValue` with `kAXWindowsAttribute` / `kAXTitleAttribute` / `kAXFocusedWindowAttribute`, `AXUIElementPerformAction(kAXRaiseAction)`, `AXIsProcessTrusted`, `NSRunningApplication.activate()` and `NSApp.activate(ignoringOtherApps:)`; `RunningAppsProvider.swift` wraps `NSWorkspace`; `TTYResolver.swift` uses `Process` and `Pipe`; `ActivationTestLog.swift` uses a serial `DispatchQueue`, `ISO8601DateFormatter` and `FileHandle`; AppleScript goes through `AppleScriptRunner` (`NSAppleScript`). UIKit has no equivalent: iOS apps cannot activate other apps' windows. Scripting runs on the caller's thread: `AppleScriptRunner`'s doc comment says `NSAppleScript` requires the main thread on some macOS versions and that background callers should marshal to main if needed; `WindowActivationTester.runAllTests` is documented "Call from a background thread", and both `ITermTTYStrategy.activate` and the tester's iTerm enumeration call `AppleScriptRunner.run` directly on that thread without hopping to main. A port SHOULD run its scripting calls on whatever thread its platform's scripting API requires. `WindowActivationTester` is declared `@unchecked Sendable`; `ActivationTestLog` is a final class also declared `@unchecked Sendable`, relying on its private serial queue for memory-buffer isolation.
- **WinUI 3**: Enumerate top-level windows with Win32 `EnumWindows` plus `GetWindowText` / `GetWindowThreadProcessId` (P/Invoke or CsWin32), or UI Automation (`System.Windows.Automation.AutomationElement.RootElement.FindAll` with `NameProperty`) as the analogue of the AX title walk; raise with `SetForegroundWindow` (subject to foreground-lock rules, often needing `AllowSetForegroundWindow` or an `AttachThreadInput` workaround) and `ShowWindow(SW_RESTORE)`. Running apps come from `System.Diagnostics.Process.GetProcesses()` / `GetProcessesByName`, with `Process.MainWindowHandle` for the bring-to-front strategy; the catalog keys become process names (`WindowsTerminal`, `Code`) since `$TERM_PROGRAM` is rarely set. The iTerm2 TTY strategy has no Windows analogue; a Windows Terminal port would match by title or use `wt.exe` focus-tab commands. Verification reads `GetForegroundWindow` then `GetWindowText`. There is no Accessibility-trust gate, but UIPI blocks raising elevated windows from a non-elevated process. The log maps to a `lock`-guarded `List<string>` plus `File.AppendAllText` under `Windows.Storage.ApplicationData.Current.LocalFolder` (packaged) or `Environment.SpecialFolder.LocalApplicationData`, timestamps from `DateTimeOffset.UtcNow.ToString("o")`; `runAllTests` becomes a `Task.Run` returning `(int Passed, int Failed)`, with `Task.Delay` replacing `Thread.sleep` and `DispatcherQueue.TryEnqueue` replacing the final main-queue hop.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/WindowManager/WindowActivation/` |

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to system/system-windows/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from `ActivationTestLog.swift`, `BuiltInActivationStrategies.swift`, `KnownTerminals.swift`, `RunningAppsProvider.swift`, `TTYResolver.swift`, `WindowActivationStrategy.swift`, `WindowActivationTarget.swift` and `WindowActivationTester.swift` |
