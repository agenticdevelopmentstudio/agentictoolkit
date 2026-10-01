---
id: 5141968f-3922-47f2-a31f-ba953b92a048
title: VS Code Commands Bridge
domain: agentictoolkit://cookbook/workspace/extensions/vscode-api/commands/main-thread-commands
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The extension host's vscode.commands adaptor — registerCommand, executeCommand
  and getCommands — dispatching every command into the app's own CommandRegistry,
  the same table the app's menus and command palette already share, rather than a
  second extension-private one.
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- commands
- disposable
depends-on: []
related:
- agentictoolkit://cookbook/workspace/extensions/host/extension-event
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadCommands.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/AppShell/AppCommand.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/VSCodeAPI.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/MainThreadCommandsTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ''
approved-date: ''
---

# VS Code Commands Bridge

## Overview

This adaptor is the extension host's `vscode.commands` namespace:
`registerCommand`, `executeCommand` and `getCommands`. All three terminate
in the app's own command registry — the same table the app's menus and
command palette dispatch through — rather than in a second,
extension-private command table. The adaptor MUST run confined to a
single, serialized execution context (matching the command registry and
the extension host, since the callback values it holds are not safe to
share across concurrent contexts, and every member below is invoked on
the thread that made the call, which for this host is always that
confined context), and is meant as **one instance per extension**,
mirroring the extension host itself: nothing in the type enforces that,
but every ownership rule below — most importantly the duplicate-
registration check — is answerable only if it holds, because it is what
makes "an id *this adaptor* already owns" a question this type can see.
The ownership record maps an id to its registered callback and the
registration token that names that specific registration — never a
second dispatch table; dispatch always goes through the shared registry.
Tearing the adaptor down walks that record to unregister everything this
adaptor is responsible for. There is deliberately no automatic net for
that teardown: nothing calls it today because nothing instantiates the
extension host in production yet, so the requirement to call it lives
only in documentation until a coordinator task wires it in.

## Behavioral Requirements

- **thread-confined-access**: The adaptor MUST be confined to a single,
  serialized execution context; every stored value read or write and every
  method body MUST execute on that same confined context.
- **one-registry-per-adaptor-no-default**: Constructing the adaptor MUST
  take the shared command registry as a required parameter with no default
  value, so a caller cannot receive a private registry silently and have
  every extension command vanish from the app's own command palette.
- **ownership-record-not-a-dispatch-table**: The ownership record MUST
  record only the ids this specific adaptor instance has registered (each
  entry holding the registered callback and the registration token for
  that registration); dispatch MUST always go through the shared
  registry, never through the ownership record directly.
- **register-raises-on-torn-down-adaptor**: Registering a command MUST be
  built with the raised-exception teardown response, so a call after the
  adaptor's owner has been deallocated raises an exception rather than
  resolving or answering "undefined."
- **register-requires-string-command-id**: Handling a register-command
  call MUST raise `"registerCommand requires a string command id."` and
  return without registering anything when the first argument is missing
  or is not a string.
- **register-requires-callback-argument**: Handling a register-command
  call MUST raise `"registerCommand requires a callback function."` and
  return without registering anything when no second argument was
  supplied.
- **register-requires-function-callback**: Handling a register-command
  call MUST test the second argument against the calling context's own
  function type, and when that test fails (including when that type check
  is unavailable) MUST raise `"registerCommand's callback must be a
  function."` and return without registering anything.
- **register-rejects-duplicate-within-adaptor**: Handling a
  register-command call MUST raise `"command '<id>' already exists"` and
  return without registering anything when the ownership record already
  holds an entry for that id; a duplicate the app or a different
  extension's adaptor instance owns is out of scope for this check and
  MUST fall through to the shared registry's own replace-and-warn (or
  built-in-refusal) behavior instead.
- **register-requires-dispatchable-context**: Handling a register-command
  call MUST raise the shared dispatch-unavailable message and return
  without registering anything when the active context cannot dispatch,
  refusing before a disposable is ever handed back for a command that
  could never be invoked.
- **register-normalizes-nullish-this-arg**: Handling a register-command
  call MUST treat a third argument that is absent, "undefined," or "null"
  as "no receiver" (binding nothing), and MUST bind any other third-
  argument value (including a falsy value such as `false` or `0`) as the
  receiver unchanged.
- **register-marks-registration-extension-contributed**: Handling a
  register-command call MUST mark every command it registers as
  extension-contributed, so the shared registry's built-in-versus-
  extension collision refusal applies to it.
- **register-uses-the-command-id-as-its-title**: Handling a
  register-command call MUST construct the registered command with its
  title equal to the raw id, giving the command palette no separate
  human-readable title or category for an extension-registered command.
- **register-returns-a-disposable-that-unregisters-this-registration**: On
  success, handling a register-command call MUST return a disposable
  whose dispose operation removes exactly the registration just made and
  no other.
- **register-records-ownership-before-returning**: Handling a
  register-command call MUST store the callback and token in the
  ownership record before constructing and returning the disposable.
- **dispatch-consumes-the-caller-flag-exactly-once**: The dispatch a
  registered command runs through MUST consume the caller flag exactly
  once per dispatch, before invoking the callback, reading and resetting
  the flag to false in the same step.
- **dispatch-has-caller-is-static-not-instance**: The caller flag MUST be
  shared across every adaptor instance, not held per instance, because the
  flag describes one dispatch (whether an awaiting extension caller is
  waiting on it) rather than a fact about which adaptor instance is
  running it — an extension awaiting a command a *different* extension's
  adaptor registered must still be recognized as a caller by that other
  adaptor's dispatch.
- **dispatch-has-caller-restored-after-a-caller-dispatch**: Marking a
  dispatch as having a caller MUST save the previous value of the caller
  flag, set it to true, run the dispatch, and restore the previous value
  afterward regardless of outcome — so a nested execute-command call made
  from inside a command callback that itself has no caller is not left
  permanently marked as having one.
- **invoke-returns-the-callback-value-on-success**: Invoking a registered
  callback MUST, when the call answers with a returned value, return that
  value unchanged.
- **invoke-observes-async-rejection-only-when-caller-less**: Invoking a
  registered callback MUST attach a rejection observer to a returned
  thenable value only when there is no caller; when there is a caller, it
  MUST attach nothing, leaving the extension's own await/catch as the sole
  observer of that rejection.
- **invoke-logs-a-caller-less-async-rejection**: The rejection handler
  attached when there is no caller MUST log, at error level, the command
  id and the rejection reason's string form (or a placeholder when that
  string form is unavailable).
- **invoke-returns-callback-failure-on-throw**: Invoking a registered
  callback MUST, when the call answers with a thrown value, return a
  callback-failure result wrapping it, and MUST NOT let the exception
  propagate as a host error or reach the host's own pending-exception
  state.
- **invoke-logs-a-caller-less-throw**: Invoking a registered callback MUST
  log, at error level, the command id and the thrown value's string form
  (or a placeholder) only when there is no caller; when there is a caller
  it MUST NOT log, leaving the rejection this throw becomes (via
  execute-command) as the extension's own responsibility.
- **invoke-returns-dispatch-unavailable-never-nil**: Invoking a registered
  callback MUST, when the call answers "unavailable," return a
  dispatch-unavailable result and MUST NOT answer nothing, because
  answering nothing here would resolve an execute-command promise with
  "undefined," which is what a void command that ran successfully also
  answers.
- **invoke-logs-dispatch-unavailable-unconditionally**: Invoking a
  registered callback MUST log, at error level, the command id whenever
  the call answers "unavailable," regardless of whether there is a caller,
  because that case is a host fault rather than an extension's, so an
  operator must be able to find it in the log even when the extension
  awaited nothing.
- **execute-rejects-on-torn-down-adaptor**: Executing a command MUST be
  built with the rejected-promise teardown response, so a call after the
  adaptor's owner has been deallocated rejects the returned promise rather
  than raising synchronously or answering "undefined."
- **execute-requires-string-command-id**: Handling an execute-command call
  MUST answer a promise rejected with `"executeCommand requires a string
  command id."` when the first argument is missing or is not a string.
- **execute-forwards-remaining-arguments-untouched**: Handling an
  execute-command call MUST pass every argument after the command id, as
  the same values the caller supplied and with no conversion, to the
  shared registry's execute operation.
- **execute-marks-its-dispatch-as-having-a-caller**: Handling an
  execute-command call MUST wrap its call to the shared registry's execute
  operation in the caller-marking helper, marking that one dispatch as
  having a caller for the invoke operation to read.
- **execute-rejects-on-dispatch-unavailable**: Handling an execute-command
  call MUST answer a promise rejected with the shared dispatch-unavailable
  message when the registry's execute operation answers "unavailable,"
  and MUST NOT resolve with "undefined" in that case.
- **execute-rejects-with-the-extensions-own-exception**: Handling an
  execute-command call MUST answer a promise rejected with the
  callback-failure's own reason, unchanged, when the registry's execute
  operation answers a callback failure, preserving the extension's own
  error subclass and stack rather than paraphrasing it.
- **execute-settles-a-thenable-result**: Handling an execute-command call
  MUST settle its returned promise with the script value the registry's
  execute operation answers, so an async command callback's own promise
  (or a plain returned value) settles the extension's await with the
  value the command actually produced.
- **execute-resolves-a-native-result**: Handling an execute-command call
  MUST resolve its returned promise with the result, when the registry's
  execute operation answers any value that is neither "unavailable," a
  callback failure, nor a script value (an app-registered command's
  native return value, bridged into the script engine).
- **execute-translates-registry-errors-verbatim**: Handling an
  execute-command call MUST answer a promise rejected with the registry
  error's own wording (`"No command is registered with id '<id>'"` for an
  unknown command, `"Command '<id>' is registered but currently
  disabled"` for a disabled command) rather than paraphrasing it, when the
  registry's execute operation throws one of those two named errors.
- **execute-rejects-on-any-other-thrown-error**: Handling an
  execute-command call MUST answer a promise rejected with that error's
  own description, for any error the registry's execute operation throws
  that is not one of those two named errors.
- **get-commands-rejects-on-torn-down-adaptor**: Getting the list of
  commands MUST be built with the rejected-promise teardown response.
- **get-commands-defaults-to-including-every-id**: Handling a
  get-commands call MUST treat a first argument that is absent,
  "undefined," false, or any other falsy value as "do not filter,"
  answering with every id the shared registry knows.
- **get-commands-filters-underscore-prefixed-ids-on-true**: Handling a
  get-commands call MUST, when the first argument's boolean value is
  true, exclude every id that starts with an underscore from the result.
- **get-commands-never-rejects-for-its-own-reason**: Handling a
  get-commands call MUST always resolve its returned promise and MUST NOT
  reject it for its own reasons, because reading the registry's known
  commands cannot fail; the only rejection this member can produce is the
  teardown rejection from **get-commands-rejects-on-torn-down-adaptor**.
- **get-commands-preserves-registration-order**: Handling a get-commands
  call MUST answer the ids in the registry's own order, without
  re-sorting them.
- **dispose-unregisters-every-owned-command**: Tearing the adaptor down
  MUST unregister every entry currently in the ownership record, and MUST
  leave the ownership record empty when it returns.
- **unregister-is-guarded-by-both-ownership-and-token**: Unregistering an
  id and token MUST remove the registration named by both from the
  ownership record and the shared registry only when the ownership record
  holds an entry for that id whose stored token equals the given token;
  when either check fails it MUST do nothing.
- **disposable-is-idempotent**: The disposable returned when registering a
  command MUST unregister its registration on its first dispose call and
  MUST do nothing on every subsequent dispose call on the same disposable,
  per the underlying disposable-building operation's own single-call
  guarantee.
- **disposable-captures-a-fixed-token**: The token a disposable
  unregisters MUST be the one captured for it at the time the disposable
  was built, not re-read from the ownership record at dispose time, so a
  disposable minted before a dispose-and-re-register cycle finds its
  captured token no longer matches the live registration and becomes a
  no-op rather than unregistering the adaptor's own fresh registration of
  the same id.
- **teardown-does-not-capture-self**: The dispatch a registered command
  runs through MUST capture no reference to the adaptor instance, reading
  only shared state and the receiver/callback values captured at
  registration time, so the adaptor is not kept alive by the registry's
  own retain graph.
- **logging-conformance**: The adaptor MUST participate in the host's
  logging convention, exposing a logger built from its own name.

## Appearance

Not applicable — this is the extension host's `vscode.commands` adaptor, not a visual component.

## States

Not applicable — this is the extension host's `vscode.commands` adaptor, not a visual component. Its only lifecycle-shaped behavior is the registered-versus-disposed status of each command id it owns, which is captured under Behavioral Requirements (`disposable-is-idempotent`, `dispose-unregisters-every-owned-command`) rather than as a visual-state table.

## Accessibility

Not applicable — this is the extension host's `vscode.commands` adaptor, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| main-thread-commands-001 | register-requires-function-callback | `registerCommand('test.cmd', {})` — second argument is a plain object, not a function | Raises `"registerCommand's callback must be a function."`; no registration is added |
| main-thread-commands-002 | register-rejects-duplicate-within-adaptor | `registerCommand('test.cmd', cb1)` then `registerCommand('test.cmd', cb2)` on the same adaptor instance | The second call raises `"command 'test.cmd' already exists"`; the first registration (dispatching to `cb1`) is left in place and still reachable through `executeCommand` |
| main-thread-commands-003 | execute-forwards-remaining-arguments-untouched, execute-resolves-a-native-result | `executeCommand('test.cmd', 1, 2, 3)` against a command registered whose implementation echoes its arguments | The promise resolves with the same argument values the command received, delivered in order |
| main-thread-commands-004 | execute-translates-registry-errors-verbatim | `executeCommand('no.such.command')` where no command is registered under that id | The promise rejects with an error whose message is `"No command is registered with id 'no.such.command'"` |
| main-thread-commands-005 | execute-translates-registry-errors-verbatim | `executeCommand('test.cmd')` where `test.cmd` is registered but currently disabled | The promise rejects with an error whose message is `"Command 'test.cmd' is registered but currently disabled"` |
| main-thread-commands-006 | dispose-unregisters-every-owned-command, disposable-is-idempotent | Register two commands from one adaptor, tear the adaptor down, then tear it down again | After the first teardown, both ids are gone from the registry's known commands and `executeCommand` on either id rejects as unknown; the second teardown changes nothing further |
| main-thread-commands-007 | execute-rejects-with-the-extensions-own-exception, invoke-logs-a-caller-less-throw | `executeCommand('test.cmd')` where `test.cmd`'s registered callback throws | The promise rejects with the callback's own thrown value (same error subclass, same message), and the throw never reaches the host's own pending-exception bookkeeping |
| main-thread-commands-008 | invoke-logs-a-caller-less-throw, invoke-returns-callback-failure-on-throw | Invoking `test.cmd` directly through the shared registry (a palette-style dispatch with no execute-command caller), where its callback throws | The throw is logged and swallowed — the dispatch returns normally, the extension host stays usable, and no exception reaches the caller |
| main-thread-commands-009 | get-commands-filters-underscore-prefixed-ids-on-true, get-commands-defaults-to-including-every-id | Register a command whose id starts with `"_"` alongside an ordinary one, then call `getCommands(true)` and separately `getCommands()` | `getCommands(true)` resolves with a list excluding the underscore-prefixed id; `getCommands()` (no argument) resolves with a list that includes it |
| main-thread-commands-010 | unregister-is-guarded-by-both-ownership-and-token, disposable-captures-a-fixed-token | Register `'test.cmd'`, keep its disposable, tear the whole adaptor down, let a different registrant register `'test.cmd'` again, then dispose the kept disposable | The kept disposable's late dispose call is a no-op — the newer registration under `'test.cmd'` survives untouched |
| main-thread-commands-011 | execute-rejects-on-torn-down-adaptor, register-raises-on-torn-down-adaptor, get-commands-rejects-on-torn-down-adaptor | Deallocate the adaptor's owner, then call the previously captured `registerCommand`, `executeCommand`, and `getCommands` block values | `registerCommand` raises synchronously; `executeCommand` and `getCommands` each reject their returned promise; none of the three answers `undefined` as if it had succeeded |

## Edge Cases

- **Null/empty input**: `registerCommand()` called with zero arguments MUST fail the string-command-id guard (since the first argument is missing) and MUST raise the same message as a non-string first argument, per **register-requires-string-command-id** (MUST).
- **Null/empty input**: `registerCommand('id')` called with only one argument MUST fail the callback-argument guard and MUST raise `"registerCommand requires a callback function."`, per **register-requires-callback-argument** (MUST).
- **Null/empty input**: `getCommands()` called with zero arguments MUST be treated identically to `getCommands(false)` — the first argument's boolean value is absent, and the "do not filter" default applies — per **get-commands-defaults-to-including-every-id** (MUST).
- **Boundary values**: a command id equal to the empty string is a valid string and reaches the duplicate check and the shared registry's registration exactly as any other id would; nothing in this file rejects it (MUST, per **register-requires-string-command-id**, which checks only that the value is a string).
- **Concurrent access**: the adaptor is confined to a single execution context with no additional locking; the ownership record and the shared caller flag are read and mutated only on that confined context, so there is no data race to define behavior for (MUST).
- **Concurrent access**: `executeCommand` invoked reentrantly from inside a command callback that is itself running under an outer `executeCommand` dispatch MUST see the inner dispatch's own caller-marking set the caller flag to true for the inner call and restore the outer call's prior value afterward, per **dispatch-has-caller-restored-after-a-caller-dispatch** (MUST).
- **Error states**: a registered callback that throws MUST become a callback-failure result rather than a host error or a value, per **invoke-returns-callback-failure-on-throw**; whether it is also logged depends on whether there is a caller, per **invoke-logs-a-caller-less-throw** (MUST).
- **Error states**: a context whose command dispatch trampoline cannot be installed MUST cause `registerCommand` to raise before any disposable is returned, and MUST cause `executeCommand` to reject rather than resolve with `undefined`, per **register-requires-dispatchable-context** and **execute-rejects-on-dispatch-unavailable** (MUST).
- **Cancellation or timeout**: not applicable to any of the three members — dispatch through the shared registry is synchronous on the confined context; the only asynchronous element is a command callback's own async return value, which `executeCommand` hands back unresolved by settling its promise with it rather than awaiting or imposing a timeout on it (fact, per **execute-settles-a-thenable-result**).
- **Missing or unreachable resource**: `executeCommand` on an id nothing has registered MUST reject with the unknown-command error's own message, `"No command is registered with id '<id>'"`, per **execute-translates-registry-errors-verbatim** (MUST).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `registry` | a command registry | none (required, no default) | The shared registry every `registerCommand`, `executeCommand` and `getCommands` call dispatches through; supplied by whoever constructs this adaptor for one extension host instance. |

## Deep Linking

Not applicable: this adaptor defines no URL, route, or navigable destination — it dispatches extension-originated command calls into an in-process registry, with no navigation surface of its own.

## Localization

This adaptor raises or rejects with hardcoded English string literals; none carries a localization key or catalog entry. Every raised or rejected message reaches the extension as a thrown or rejected error, so an extension author sees the literal English text regardless of locale. The two log-only messages the invoke operation produces (a caller-less rejection or throw) reach only the host's own log, never the extension. The registry's two error messages are not literals in this adaptor, but handling an execute-command call passes them through to the extension verbatim, so they are user-facing text this component is responsible for surfacing.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `registerCommand requires a string command id.` | Raised when `registerCommand`'s first argument is missing or not a string. |
| (none — literal only) | `registerCommand requires a callback function.` | Raised when `registerCommand`'s second argument is missing. |
| (none — literal only) | `registerCommand's callback must be a function.` | Raised when `registerCommand`'s second argument fails the function-type check. |
| (none — literal only) | `command '<id>' already exists` | Raised when this adaptor already owns `<id>`. |
| (none — literal only) | `executeCommand requires a string command id.` | Rejected when `executeCommand`'s first argument is missing or not a string. |
| (none — literal only) | `The extension host could not install its command dispatch trampoline in JavaScript context '<context name>', so extension command callbacks cannot be invoked in it.` | Raised by `registerCommand` or rejected by `executeCommand` when dispatch is unavailable. |
| (none — literal only, from the registry's own error description) | `No command is registered with id '<id>'` | Rejected by `executeCommand` when the registry's execute operation throws its unknown-command error. |
| (none — literal only, from the registry's own error description) | `Command '<id>' is registered but currently disabled` | Rejected by `executeCommand` when the registry's execute operation throws its disabled-command error. |

## Accessibility Options

Not applicable: this adaptor renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; `registerCommand`, `executeCommand` and `getCommands` are always available once this adaptor is constructed.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind; its only telemetry-adjacent calls are the diagnostic log lines covered under Logging, which are not analytics events.

## Privacy

- **Data collected**: this adaptor collects no data of its own; the ownership record holds, for the lifetime of each registration, the extension-supplied callback (and, indirectly through it, everything the extension's own module graph captured). Arguments and results that pass through `executeCommand` are the caller's own values, forwarded untouched — never copied, stored, or inspected beyond the type checks the Behavioral Requirements describe.
- **Storage**: this adaptor performs no storage of its own; the ownership record is in-memory only and exists for the adaptor's lifetime. The shared registry's own bookkeeping is likewise in-memory, out of this component's scope.
- **Transmission**: nothing here leaves the process; every call is an in-process round trip between the host and the script engine the same process owns.
- **Retention**: a registered callback (and the context it keeps alive) is retained in the ownership record until its disposable is disposed, until the adaptor is torn down, or until the shared registry replaces it under the same id — per **disposable-is-idempotent** and **dispose-unregisters-every-owned-command**.

## Logging

Subsystem: the host's own logging subsystem | Category: this adaptor's own category

| Event | Level | Message |
|-------|-------|---------|
| A registered callback's returned thenable rejects, and no `executeCommand` caller is awaiting it | error | `Extension command '<commandID>' rejected: <reason.toString() or "<unprintable>">` |
| A registered callback throws, and no `executeCommand` caller is awaiting it | error | `Extension command '<commandID>' threw: <exception.toString() or "<unprintable>">` |
| A registered callback could not be dispatched at all (its context has no usable trampoline) | error | `Extension command '<commandID>' could not be dispatched: its context has no usable command dispatch trampoline` |

No other event in this file is logged: `registerCommand`'s refusals (missing id, missing callback, non-function callback, duplicate id, unreachable context) and `executeCommand`'s rejections are all surfaced directly to the extension as raised or rejected errors instead of being logged, per the corresponding Behavioral Requirements above. The "could not be dispatched" line is the one report logged unconditionally, per **invoke-logs-dispatch-unavailable-unconditionally**, whether or not an `executeCommand` caller is also told through its own rejected promise.

## Platform Notes

- **SwiftUI**: not applicable to this file — `MainThreadCommands.swift` imports only `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing in this component renders a view.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadCommands.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is `@MainActor`-isolated per its class declaration (satisfying "thread-confined access" above because `JSValue` is not `Sendable` and JavaScriptCore always calls an installed block on the thread that made the call), and the `CommandRegistry` it wraps (`AppCommand.swift`) is likewise `@MainActor` and macOS-only in this codebase today. The "caller flag" of **dispatch-has-caller-is-static-not-instance** is `dispatchHasCaller`, a `static` property of `MainThreadCommands`. The ownership record is `ownedCallbacks`, mapping a command id to its registered `JSValue` callback and its `CommandRegistration` token. "Callback failure" and "dispatch unavailable" are the private `CallbackFailure` and `DispatchUnavailable` wrapper values `invoke` returns through `AppCommand.run`'s `([Any]) -> Any?` signature.
- **Compose**: model this adaptor as a Kotlin `class MainThreadCommands(private val registry: CommandRegistry)` confined to the main dispatcher, with the ownership record as a plain `MutableMap` guarded by that confinement (no `Mutex` needed, matching the source's own single-actor argument). The extension callback becomes whatever function-reference type the host's own JavaScript engine binding (a J2V8 or Rhino function reference, say) exposes, and the caller flag becomes a top-level (or companion-object) `var`, matching its shared-not-per-instance requirement.
- **React/Web**: this component's own upstream is VS Code's real `MainThreadCommands` (`mainThreadCommands.ts`), already TypeScript, so a web port is closer to restoring the original than translating it: a class wrapping a `CommandsRegistry`-equivalent map, with `registerCommand` returning a disposable-shaped object and `executeCommand` returning a native `Promise` rather than the settled-synchronously thenable this host constructs by hand.
- **WinUI 3**: model this adaptor as a class whose every member runs on a captured `DispatcherQueue` (the confined-execution-context equivalent — WinUI 3 has no compiler-enforced actor isolation, so every entry point MUST assert `DispatcherQueue.HasThreadAccess` or marshal via `DispatcherQueue.TryEnqueue` at the top of the method, since nothing else catches a wrong-thread call at compile time the way Swift's `@MainActor` does). The shared registry's role is filled by a class exposing `Register(ICommand)`, `Execute(string, object[])` and `Unregister(string, Guid token)`, where `ICommand`'s `Execute(object[] args)` mirrors the shared command's `([Any]) -> Any?` shape rather than WinUI's own parameterless `ICommand.Execute(object? parameter)`. `registerCommand`'s returned disposable becomes an `IDisposable` whose `Dispose()` is guarded by an `Interlocked.Exchange`-backed idempotence flag, matching the underlying disposable-building operation's single-call guarantee. The extension callback becomes whatever the chosen JavaScript engine binding uses — ClearScript's `ScriptObject`/`dynamic`, or Jint's `JsValue`, standing in for `JavaScriptCore.JSValue` — and `executeCommand`'s settled-promise handoff becomes a `TaskCompletionSource<object?>` that is already completed by the time it is returned, for the synchronous-dispatch case, or the extension's own awaited `Task` passed straight through for an async callback.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadCommands.swift` |

## Design Decisions

**Decision**: the caller flag is shared across every adaptor instance rather than held per instance, even though it exists only to answer a question about one dispatch.
**Rationale**: the bit belongs to the dispatch, not to the adaptor instance running it. When extension A's `executeCommand` awaits a command extension B registered, B's callback runs on a path that genuinely has a caller, and B's own adaptor instance is not the one that knows it — a per-instance flag would read `false` there and log B's rejection as noise. A second reason points the same way: the dispatch a registered command runs through captures no reference to the adaptor instance, which keeps the adaptor out of the registry's retain graph; reaching an instance flag from the invoke operation would reintroduce exactly that captured edge, or read a value that is unavailable after teardown and answer wrongly.
**Approved**: pending

**Decision**: `registerCommand` raises a synchronous exception on failure, while `executeCommand` and `getCommands` reject a returned promise on the equivalent failure.
**Rationale**: the choice follows each member's own return shape. `registerCommand` returns a disposable, not a thenable, so there is nothing for a failure to reject; answering `undefined` instead of raising would let an extension push nothing useful onto its own subscription list while believing it had registered a command. `executeCommand` and `getCommands` return a thenable, and a VS Code extension writes `await vscode.commands.executeCommand(...)` inside a `try` — a synchronous throw from underneath that `await` would reach a `catch` other than the one the extension wrote, so both reject instead.
**Approved**: pending

**Decision** (Swift implementation): the invoke operation returns private callback-failure and dispatch-unavailable wrapper values through the shared command's `([Any]) -> Any?` signature, rather than converting a callback's failure into a rejection or thrown error at the point of dispatch.
**Rationale**: that dispatch signature is shared with every non-extension command in the app, and giving it any awareness that a scripting engine or promises exist would leak this adaptor's concerns into a type the registry, the menu system, and the command palette all depend on. The two wrapper values are private to this file, and only the execute-command handler — the one member with a promise to settle — ever unwraps them.
**Approved**: pending

**Decision**: a duplicate registration is refused only when the *same* adaptor instance already owns the id; a duplicate the app or a different extension's adaptor owns falls through unchanged to the shared registry's own replace-and-warn (or built-in-refusal) behavior.
**Rationale**: whether one extension may register an id twice is a question the ownership record can answer outright — it is this adaptor's own bookkeeping. Whether an extension may shadow an id the app or a *different* extension already owns is a trust decision that belongs with the extension registry and the permissions work the class documentation explicitly defers to, not with a per-instance ownership check that has no visibility into who else registered what.
**Approved**: pending

**Decision**: the disposable returned when registering a command captures its registration token at registration time, and unregistering re-checks that captured token against the live entry in the ownership record before touching the shared registry at all.
**Rationale**: the captured token, not the disposed flag the underlying disposable-building operation already tracks, is what protects against a stale-but-unfired disposable. A disposable minted before a dispose-and-re-register cycle is still "unfired" as far as that operation is concerned, so without the token check its late dispose call would unregister the adaptor's own *fresh* registration of the same id, made after the earlier teardown — and, one level further, unregistering also confirms the token still matches what the shared registry itself has filed, so a registration that a different registrant has since displaced is never removed by someone else's stale token either.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` passes because the file's only responsibilities are the three `vscode.commands` members' own argument validation and the caller-flag bookkeeping around dispatch; everything else is delegated — actual command storage and dispatch to `CommandRegistry` (`AppCommand.swift`), and JavaScript call/promise/disposable ceremony to `VSCodeAPI` (`member`, `raise`, `call`, `canDispatch`, `dispatchUnavailableMessage`, `observeRejection`, `resolvedPromise`/`rejectedPromise`/`settledPromise`, `disposable`). `unit-test-coverage` is partial: the given `MainThreadCommandsTests.swift` suite thoroughly covers registration, duplicate refusal, argument/result delivery, both `CommandRegistryError` rejection messages, disposal idempotence and adaptor-wide teardown, the caller-versus-caller-less logging asymmetry, `getCommands` filtering, and the stale-token/torn-down-adaptor edge cases traced above — but no test in the given sources exercises **register-normalizes-nullish-this-arg**'s `false`/`0` (non-nullish falsy) branch, or **register-requires-callback-argument** in isolation from the non-function-callback case. `explicit-error-handling` passes: every failure path (bad arguments, non-function callback, duplicate id, unreachable dispatch context, torn-down adaptor, registry errors, callback throw, dispatch-unavailable) is either an explicit raise, an explicit promise rejection, or a logged-and-continued failure — nothing is swallowed into a discarded value. `secure-log-output` passes because no credential or secret value is ever read or logged by this file; the values logged (a command id, an exception's or rejection's own `toString()`) are diagnostic identifiers and the extension's own error text, not host secrets. `no-hardcoded-strings` fails because every raised and rejected message this file constructs directly (see Localization) is an English literal with no localization mechanism.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/vscode-api/commands/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
