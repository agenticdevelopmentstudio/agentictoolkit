<!-- leaf: implement-window-management/window-activation--test-vectors · source: window-management-window-activation.md -->

# Window Activation

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
