<!-- leaf: implement-window-management/window-activation--edge-cases · source: window-management-window-activation.md -->

# Window Activation

**Rules** (cite as `implement-window-management/window-activation--edge-cases#<slug>`):

- `empty-target-list` MUST — runAllTests() MUST still clear the log, run the permission check and inventory, and return (0, 0) with Targets: 0.
- `accessibility-denied` MUST — The run MUST abort after three log lines and return (0, 0); the host app is not reactivated.
- `non-positive-pid` MUST — TTYResolver MUST return nil without spawning ps, so ITermTTYStrategy logs "has no TTY" and fails.
- `exited-process-or-no-controlling-tty` MUST — ps output is empty (it prints ?? for a process without a TTY, which is non-empty and is passed through), so an exited …
- `ps-hangs` MUST — The resolver waits for exit with no timeout; a hung ps MUST block the calling thread indefinitely.
- `applescript-hangs-or-iterm2-not-running` MUST — The AppleScript call has no timeout; if iTerm2 is not running, tell application "iTerm2" MAY launch it before …
- `automation-permission-denied` MUST — A refused Apple Event MUST surface as a runtime failure with its message and error number in the log, and the strategy …
- `empty-projectname-and-cwd` MUST — Localized case-insensitive containment of an empty string is false, so an empty projectName and empty cwd MUST match no …
- `root-cwd` MUST — A cwd of / has last path component /, so any window whose title contains / MUST match.
- `broad-title-match` MUST — Matching is substring-based across every regular app, so a short projectName MUST match the first unrelated window …
- `multiple-running-instances-of-one-terminal` MUST — BringTerminalToFrontStrategy MUST activate only the first instance the provider returns.
- `termprogram-of-an-uncatalogued-terminal` MUST — Only the iTerm strategy (if empty) and the AX strategy can apply; BringTerminalToFrontStrategy MUST be skipped as not …
- `verification-false-positive` MUST — Any non-empty frontmost title other than the host app MUST count as PASS even if it is not the target's window.
- `host-app-title-literally-sessions` MUST — A foreign app whose focused window is titled Sessions MUST be counted as FAIL.
- `application-support-unavailable` MUST — init(appSupportSubdirectory:) MUST fall back to in-memory-only logging.
- `directory-creation-fails` MUST — The error is ignored; the file URL is still set and every file write MUST silently fail while memory logging continues.
- `log-file-deleted-between-writes` MUST — The next append MUST recreate the file containing only that line; earlier memory entries are not rewritten.
- `concurrent-appends` MUST — The in-memory buffer MUST stay consistent; file ordering is the open question on log-file-write-ordering.

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
