<!-- leaf: implement-window-management/window-activation · source: window-management-window-activation.md -->

**Rules** (cite as `implement-window-management/window-activation#<slug>`):

- `target-fields` MUST
- `target-unknown-term-program` MUST
- `target-value-semantics` MUST
- `strategy-name` MUST
- `strategy-applies-to` MUST
- `strategy-activate-signature` MUST
- `strategy-sendable` MUST
- `iterm-name` MUST
- `iterm-applies` MUST
- `iterm-no-tty` MUST
- `iterm-dev-prefix` MUST
- `iterm-script` MUST
- `iterm-success` MUST
- `iterm-not-found` MUST
- `iterm-compile-failed` MUST
- `iterm-runtime-failed` MUST
- `applescript-thread` SHOULD
- `ax-name` MUST
- `ax-applies` MUST
- `ax-regular-apps-only` MUST
- `ax-app-order` MUST
- `ax-skip-unreadable` MUST
- `ax-match-rule` MUST
- `ax-match-log` MUST
- `ax-activation-sequence` MUST
- `ax-no-match` MUST
- `ax-injected-apps` MUST
- `front-name` MUST
- `front-applies` MUST
- `front-catalog-default` MUST
- `front-not-running` MUST
- `front-activate-first` MUST
- `catalog-entries` MUST
- `catalog-match` MUST
- `catalog-match-default` MUST
- `known-terminal-value` MUST
- `provider-surface` MUST
- `provider-real` MUST
- `provider-sendable` MUST
- `tty-invalid-pid` MUST
- `tty-process` MUST
- `tty-result` MUST
- `tty-internal` MUST

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

