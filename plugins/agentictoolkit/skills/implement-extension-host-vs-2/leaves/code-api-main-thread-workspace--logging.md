<!-- leaf: implement-extension-host-vs-2/code-api-main-thread-workspace--logging · source: extension-host-vs-code-api-main-thread-workspace.md -->

# MainThreadWorkspace

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `MainThreadWorkspace` (via `Loggable`'s default, derived from the type name)

| Event | Level | Message |
|-------|-------|---------|

`MainThreadWorkspace` conforms to `Loggable` and exposes `logger`, but no member in this file ever calls it: no `readFile`/`writeFile`/`readDirectory`/`stat`/`delete`/`rename`/`createDirectory` failure, no teardown rejection, and no `name`/`workspaceFolders`/`getWorkspaceFolder` resolution writes a log line anywhere in this file (fact, contrasted with `MainThreadCommands`, which logs caller-less callback failures at `error` level; this adaptor has no equivalent caller-less-dispatch concept to log about). Every failure this file produces reaches the extension directly, as a rejected promise or a raised exception, with no separate host-side log entry.
