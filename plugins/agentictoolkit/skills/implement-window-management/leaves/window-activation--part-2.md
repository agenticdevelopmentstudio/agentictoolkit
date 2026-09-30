<!-- leaf: implement-window-management/window-activation--part-2 · source: window-management-window-activation.md -->

# Window Activation — continued (part 2)

**Rules** (cite as `implement-window-management/window-activation--part-2#<slug>`):

- `log-init-app-support` MUST
- `log-init-no-app-support` MUST
- `log-init-file-url` MUST
- `log-entry-format` MUST
- `log-thread-safe-memory` MUST
- `log-text-format` MUST
- `log-file-create` MUST
- `log-file-append-only` MUST
- `log-clear` MUST
- `log-path` MUST
- `log-shared-instance` MUST
- `log-sendable` MUST
- `tester-init` MUST
- `tester-default-cascade` MUST
- `tester-threading` MUST
- `tester-clear-first` MUST
- `tester-permission-abort` MUST
- `tester-header` MUST
- `tester-inventory` MUST
- `tester-inventory-iterm` MUST
- `tester-inventory-ax` MUST
- `tester-per-target` MUST
- `tester-target-header` MUST
- `tester-cascade-stop` MUST
- `tester-not-applicable` MUST
- `tester-strategy-result` MUST
- `tester-verify-delay` MUST
- `tester-frontmost-title` MUST
- `tester-verify-rule` MUST
- `tester-results` MUST
- `tester-reactivate-host` MUST
- `tester-no-cancellation` MUST

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

## Privacy

- **Data collected**: Target identifiers, project names, working-directory paths, PIDs, `$TERM_PROGRAM` values, and the titles of accessibility windows in running terminals and in any matched regular app.
- **Storage**: In memory and, for file-backed logs, in plain text at `~/Library/Application Support/<subdirectory>/activation-test.log` (`Whippet` for `whippetShared`).
- **Transmission**: None; nothing leaves the device.
- **Retention**: The file persists across launches and grows without bound until `clear()`, which `runAllTests()` calls at the start of each run.

