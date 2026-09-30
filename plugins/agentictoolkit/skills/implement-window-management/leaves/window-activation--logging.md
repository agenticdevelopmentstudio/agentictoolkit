<!-- leaf: implement-window-management/window-activation--logging · source: window-management-window-activation.md -->

# Window Activation

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
