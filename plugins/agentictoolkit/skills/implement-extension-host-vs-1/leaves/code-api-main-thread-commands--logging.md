<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-commands--logging · source: extension-host-vs-code-api-main-thread-commands.md -->

# MainThreadCommands

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `MainThreadCommands` (via `Loggable`'s default, derived from the type name)

| Event | Level | Message |
|-------|-------|---------|
| A registered callback's returned thenable rejects, and no `executeCommand` caller is awaiting it | error | `Extension command '<commandID>' rejected: <reason.toString() or "<unprintable>">` |
| A registered callback throws, and no `executeCommand` caller is awaiting it | error | `Extension command '<commandID>' threw: <exception.toString() or "<unprintable>">` |
| A registered callback could not be dispatched at all (its context has no usable trampoline) | error | `Extension command '<commandID>' could not be dispatched: its context has no usable command dispatch trampoline` |

No other event in this file is logged: `registerCommand`'s three refusals (missing id, missing callback, non-function callback, duplicate id, unreachable context) and `executeCommand`'s rejections are all surfaced directly to the extension as raised or rejected errors instead of being logged, per the corresponding Behavioral Requirements above. The "could not be dispatched" line is the one report logged unconditionally, per **invoke-logs-dispatch-unavailable-unconditionally**, whether or not an `executeCommand` caller is also told through its own rejected promise.
