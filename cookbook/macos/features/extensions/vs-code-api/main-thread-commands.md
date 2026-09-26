---
id: 5141968f-3922-47f2-a31f-ba953b92a048
title: MainThreadCommands
domain: agentictoolkit://cookbook/macos/features/extensions/vs-code-api/main-thread-commands
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
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
- javascriptcore
- mainactor
depends-on: []
related:
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-event
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

# MainThreadCommands

## Overview

`MainThreadCommands.swift` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadCommands.swift`) is the extension host's `vscode.commands` adaptor: `registerCommand`, `executeCommand` and `getCommands`. All three terminate in the app's own `CommandRegistry` (`AppCommand.swift`) — the same table the app's menus and command palette dispatch through — rather than in a second, extension-private command table. The class is `@MainActor`-isolated (matching `CommandRegistry` and `ExtensionHost`, since `JSValue` is not `Sendable` and every member below is called by JavaScriptCore on the thread that made the call, which for this host is always the main actor) and is meant as **one instance per extension**, mirroring `ExtensionHost` itself: nothing in the type enforces that, but every ownership rule below — most importantly the duplicate-registration check — is answerable only if it holds, because it is what makes "an id *this adaptor* already owns" a question this type can see. `ownedCallbacks` is the ownership record (id to the registered `JSValue` callback and the `CommandRegistration` token that names that specific registration, never a second dispatch table — dispatch always goes through `registry`), and it is what `dispose()` walks to unregister everything this adaptor is responsible for when its owner tears the extension host down. There is deliberately no `deinit` net for that teardown; nothing in the framework calls `dispose()` today because nothing instantiates `ExtensionHost` in production yet, so the requirement to call it lives only in the class's own doc comment until the `ExtensionsCoordinator` task wires it in.

## Behavioral Requirements

- **main-actor-isolation**: `MainThreadCommands` MUST be declared `@MainActor`; every stored property read and write and every method body MUST execute on the main actor.
- **one-registry-per-adaptor-no-default**: `init(registry:)` MUST take `registry` as a required parameter with no default value, so a caller cannot receive a private registry silently and have every extension command vanish from the app's own command palette.
- **ownership-record-not-a-dispatch-table**: `ownedCallbacks` MUST record only the ids this specific adaptor instance has registered (each entry holding the registered `JSValue` callback and the `CommandRegistration` token for that registration); dispatch MUST always go through `registry`, never through `ownedCallbacks` directly.
- **register-raises-on-torn-down-adaptor**: `registerCommand` MUST be built with `VSCodeAPI.member(..., whenTornDown: .raisedException, ...)`, so a call after the adaptor's owner has been deallocated raises a JavaScript exception rather than resolving or returning `undefined`.
- **register-requires-string-command-id**: `handleRegisterCommand` MUST call `VSCodeAPI.raise("registerCommand requires a string command id.", in: context)` and return without registering anything when `arguments.first` is missing or is not a JavaScript string.
- **register-requires-callback-argument**: `handleRegisterCommand` MUST call `VSCodeAPI.raise("registerCommand requires a callback function.", in: context)` and return without registering anything when `arguments.count` is `1` or fewer (no second argument supplied).
- **register-requires-function-callback**: `handleRegisterCommand` MUST test `arguments[1]` with `isInstance(of:)` against the calling context's own `Function` constructor, and when that test fails (including when the `Function` constructor is unavailable) MUST call `VSCodeAPI.raise("registerCommand's callback must be a function.", in: context)` and return without registering anything.
- **register-rejects-duplicate-within-adaptor**: `handleRegisterCommand` MUST call `VSCodeAPI.raise("command '\(command)' already exists", in: context)` and return without registering anything when `ownedCallbacks[command]` is already non-`nil`; a duplicate the app or a different extension's adaptor instance owns is out of scope for this check and MUST fall through to `CommandRegistry.register(_:isExtensionContributed:)`'s own replace-and-warn (or built-in-refusal) behavior instead.
- **register-requires-dispatchable-context**: `handleRegisterCommand` MUST call `VSCodeAPI.raise(VSCodeAPI.dispatchUnavailableMessage(for: context), in: context)` and return without registering anything when `VSCodeAPI.canDispatch(in: context)` is `false`, refusing before a `Disposable` is ever handed back for a command that could never be invoked.
- **register-normalizes-nullish-this-arg**: `handleRegisterCommand` MUST treat a third argument that is absent, JavaScript `undefined`, or JavaScript `null` as "no `thisArg`" (binding `nil`), and MUST bind any other third argument value (including a JS `false` or `0`) as `thisArg` unchanged.
- **register-marks-registration-extension-contributed**: `handleRegisterCommand` MUST call `registry.register(_:isExtensionContributed:)` with `isExtensionContributed: true` for every command it registers, so `CommandRegistry`'s built-in-versus-extension collision refusal applies to it.
- **register-uses-the-command-id-as-its-title**: `handleRegisterCommand` MUST construct the `AppCommand` with `title` equal to `command` (the raw id), giving the command palette no separate human-readable title or category for an extension-registered command.
- **register-returns-a-disposable-that-unregisters-this-registration**: on success, `handleRegisterCommand` MUST return the `JSValue` produced by `makeDisposable(id:token:in:)`, whose `dispose()` removes exactly the registration just made and no other.
- **register-records-ownership-before-returning**: `handleRegisterCommand` MUST store the callback and token in `ownedCallbacks[command]` before constructing and returning the `Disposable`.
- **dispatch-consumes-the-caller-flag-exactly-once**: the closure passed to `AppCommand.run` inside `handleRegisterCommand` MUST call `MainThreadCommands.consumeDispatchHasCaller()` exactly once per dispatch, before calling `MainThreadCommands.invoke(...)`, reading and resetting `dispatchHasCaller` to `false` in the same step.
- **dispatch-has-caller-is-static-not-instance**: `dispatchHasCaller` MUST be a `static` property of `MainThreadCommands`, not an instance property, because the bit describes one dispatch (whether an `await`ing extension caller is waiting on it) rather than a fact about which adaptor instance is running it — an extension awaiting a command a *different* extension's adaptor registered must still be recognized as a caller by that other adaptor's dispatch.
- **dispatch-has-caller-restored-after-a-caller-dispatch**: `dispatchingForACaller(_:)` MUST save the previous value of `dispatchHasCaller`, set it to `true`, run `body`, and restore the previous value in a `defer` — so a nested `executeCommand` call made from inside a command callback that itself has no caller is not left permanently marked as having one.
- **invoke-returns-the-callback-value-on-success**: `MainThreadCommands.invoke` MUST, when `VSCodeAPI.call` answers `.returned(let value)`, return that `value` unchanged.
- **invoke-observes-async-rejection-only-when-caller-less**: `MainThreadCommands.invoke` MUST attach a rejection observer (`VSCodeAPI.observeRejection`) to a returned thenable value only when `hasCaller` is `false`; when `hasCaller` is `true`, it MUST attach nothing, leaving the extension's own `await`/`.catch` as the sole observer of that rejection.
- **invoke-logs-a-caller-less-async-rejection**: the rejection handler `invoke` attaches when `hasCaller` is `false` MUST log, at `error` level, the command id and the rejection reason's `toString()` (or `"<unprintable>"` when that is `nil`).
- **invoke-returns-callback-failure-on-throw**: `MainThreadCommands.invoke` MUST, when `VSCodeAPI.call` answers `.threw(let exception)`, return a `CallbackFailure` wrapping `exception`, and MUST NOT let the exception propagate as a Swift error or reach `ExtensionHost.pendingException`.
- **invoke-logs-a-caller-less-throw**: `MainThreadCommands.invoke` MUST log, at `error` level, the command id and the thrown exception's `toString()` (or `"<unprintable>"`) only when `hasCaller` is `false`; when `hasCaller` is `true` it MUST NOT log, leaving the rejection this throw becomes (via `executeCommand`) as the extension's own responsibility.
- **invoke-returns-dispatch-unavailable-never-nil**: `MainThreadCommands.invoke` MUST, when `VSCodeAPI.call` answers `.unavailable`, return a `DispatchUnavailable` value and MUST NOT return `nil`, because a `nil` here would resolve an `executeCommand` promise with `undefined`, which is what a `void` command that ran successfully also answers.
- **invoke-logs-dispatch-unavailable-unconditionally**: `MainThreadCommands.invoke` MUST log, at `error` level, the command id whenever `VSCodeAPI.call` answers `.unavailable`, regardless of the value of `hasCaller`, because that case is a host fault rather than an extension's, so an operator must be able to find it in the log even when the extension awaited nothing.
- **execute-rejects-on-torn-down-adaptor**: `executeCommand` MUST be built with `VSCodeAPI.member(..., whenTornDown: .rejectedPromise, ...)`, so a call after the adaptor's owner has been deallocated rejects the returned promise rather than raising synchronously or answering `undefined`.
- **execute-requires-string-command-id**: `handleExecuteCommand` MUST return `VSCodeAPI.rejectedPromise(message: "executeCommand requires a string command id.", in: context)` when `arguments.first` is missing or is not a JavaScript string.
- **execute-forwards-remaining-arguments-untouched**: `handleExecuteCommand` MUST pass every argument after the command id, as the same `JSValue`s the caller supplied and with no conversion through `toObject()`, to `registry.execute(id:arguments:)`.
- **execute-marks-its-dispatch-as-having-a-caller**: `handleExecuteCommand` MUST wrap its call to `registry.execute(id:arguments:)` in `Self.dispatchingForACaller { ... }`, marking that one dispatch as having a caller for `MainThreadCommands.invoke` to read.
- **execute-rejects-on-dispatch-unavailable**: `handleExecuteCommand` MUST return `VSCodeAPI.rejectedPromise(message: VSCodeAPI.dispatchUnavailableMessage(for: context), in: context)` when `registry.execute` answers a `DispatchUnavailable` value, and MUST NOT resolve with `undefined` in that case.
- **execute-rejects-with-the-extensions-own-exception**: `handleExecuteCommand` MUST return `VSCodeAPI.rejectedPromise(reason: failure.reason, in: context)`, unchanged, when `registry.execute` answers a `CallbackFailure`, preserving the extension's own `Error` subclass and `stack` rather than paraphrasing it.
- **execute-settles-a-thenable-result**: `handleExecuteCommand` MUST return `VSCodeAPI.settledPromise(for: jsResult, in: context)` when `registry.execute` answers a `JSValue`, so an `async` command callback's own promise (or a plain returned value) settles the extension's `await` with the value the command actually produced.
- **execute-resolves-a-native-result**: `handleExecuteCommand` MUST return `VSCodeAPI.resolvedPromise(with: result, in: context)` when `registry.execute` answers any value that is neither a `DispatchUnavailable`, a `CallbackFailure`, nor a `JSValue` (an app-registered command's native Swift return value, bridged by JavaScriptCore).
- **execute-translates-registry-errors-verbatim**: `handleExecuteCommand` MUST return `VSCodeAPI.rejectedPromise(message: error.description, in: context)` when `registry.execute` throws a `CommandRegistryError`, passing through `CommandRegistryError.description`'s own wording (`"No command is registered with id '<id>'"` for `.unknownCommand`, `"Command '<id>' is registered but currently disabled"` for `.commandDisabled`) rather than paraphrasing it.
- **execute-rejects-on-any-other-thrown-error**: `handleExecuteCommand` MUST return `VSCodeAPI.rejectedPromise(message: "\(error)", in: context)` for any error `registry.execute` throws that is not a `CommandRegistryError`.
- **get-commands-rejects-on-torn-down-adaptor**: `getCommands` MUST be built with `VSCodeAPI.member(..., whenTornDown: .rejectedPromise, ...)`.
- **get-commands-defaults-to-including-every-id**: `handleGetCommands` MUST treat a first argument that is absent, `undefined`, `false`, or any other JavaScript-falsy value as "do not filter", answering with every id in `registry.allCommands`.
- **get-commands-filters-underscore-prefixed-ids-on-true**: `handleGetCommands` MUST, when `arguments.first?.toBool()` is `true`, exclude every id whose `String` value starts with `"_"` from the result.
- **get-commands-never-rejects-for-its-own-reason**: `handleGetCommands` MUST always call `VSCodeAPI.resolvedPromise(with:in:)` and MUST NOT reject the promise itself, because reading `registry.allCommands` cannot throw; the only rejection this member can produce is the teardown rejection from **get-commands-rejects-on-torn-down-adaptor**.
- **get-commands-preserves-registration-order**: `handleGetCommands` MUST answer the ids in `registry.allCommands`'s own order, without re-sorting them.
- **dispose-unregisters-every-owned-command**: `dispose()` MUST call `unregisterOwned(id:token:)` for every entry currently in `ownedCallbacks`, and MUST leave `ownedCallbacks` empty when it returns.
- **unregister-is-guarded-by-both-ownership-and-token**: `unregisterOwned(id:token:)` MUST remove the registration named by `id` and `token` from both `ownedCallbacks` and `registry` only when `ownedCallbacks[id]` exists and its stored `token` equals the `token` argument; when either check fails it MUST do nothing.
- **disposable-is-idempotent**: the `JSValue` returned by `makeDisposable(id:token:in:)` MUST call `unregisterOwned(id:token:)` on its first `dispose()` call and MUST do nothing on every subsequent `dispose()` call on the same `JSValue`, per `VSCodeAPI.disposable(in:onDispose:)`'s own single-call guarantee.
- **disposable-captures-a-fixed-token**: the `token` a `Disposable` unregisters MUST be the one captured for it at `makeDisposable` call time, not re-read from `ownedCallbacks` at dispose time, so a `Disposable` minted before a `dispose()`-and-re-register cycle finds its captured token no longer matches the live registration and becomes a no-op rather than unregistering the adaptor's own fresh registration of the same id.
- **teardown-does-not-capture-self**: the closure `handleRegisterCommand` hands to `AppCommand.run` MUST capture no `self`, reading only `MainThreadCommands`'s `static` members and the `boundThisArg`/`callback` values captured at registration time, so the adaptor is not kept alive by the registry's own retain graph.
- **logging-conformance**: `MainThreadCommands` MUST conform to `Loggable`, exposing a `nonisolated static let logger` built with `makeLogger()`.

## Appearance

Not applicable — this is the extension host's `vscode.commands` adaptor, not a visual component.

## States

Not applicable — this is the extension host's `vscode.commands` adaptor, not a visual component. Its only lifecycle-shaped behavior is the registered-versus-disposed status of each command id it owns, which is captured under Behavioral Requirements (`disposable-is-idempotent`, `dispose-unregisters-every-owned-command`) rather than as a visual-state table.

## Accessibility

Not applicable — this is the extension host's `vscode.commands` adaptor, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| main-thread-commands-001 | register-requires-function-callback | `registerCommand('test.cmd', {})` — second argument is a plain object, not a function | `VSCodeAPI.raise` is called with `"registerCommand's callback must be a function."`; no registration is added — `MainThreadCommandsTests.nonFunctionCallbackRaisesRatherThanRegistering` |
| main-thread-commands-002 | register-rejects-duplicate-within-adaptor | `registerCommand('test.cmd', cb1)` then `registerCommand('test.cmd', cb2)` on the same adaptor instance | The second call raises `"command 'test.cmd' already exists"`; the first registration (dispatching to `cb1`) is left in place and still reachable through `executeCommand` — `MainThreadCommandsTests.duplicateRegistrationFromOneExtensionRaisesAndKeepsTheFirst` |
| main-thread-commands-003 | execute-forwards-remaining-arguments-untouched, execute-resolves-a-native-result | `executeCommand('test.cmd', 1, 2, 3)` against a command registered from Swift whose `run` echoes its arguments | The promise resolves with the same argument values the command received, delivered in order — `MainThreadCommandsTests.executeCommandDeliversArgumentsAndResolvesWithTheResult` |
| main-thread-commands-004 | execute-translates-registry-errors-verbatim | `executeCommand('no.such.command')` where no command is registered under that id | The promise rejects with an `Error` whose message is `"No command is registered with id 'no.such.command'"` — `MainThreadCommandsTests.executeCommandOnUnknownIDRejects` |
| main-thread-commands-005 | execute-translates-registry-errors-verbatim | `executeCommand('test.cmd')` where `test.cmd` is registered but its `isEnabled` returns `false` | The promise rejects with an `Error` whose message is `"Command 'test.cmd' is registered but currently disabled"` — `MainThreadCommandsTests.executeCommandOnDisabledCommandRejectsWithTheDisabledError` |
| main-thread-commands-006 | dispose-unregisters-every-owned-command, disposable-is-idempotent | Register two commands from one adaptor, call `dispose()`, then call `dispose()` again | After the first `dispose()`, both ids are gone from `registry.allCommands` and `executeCommand` on either id rejects as unknown; the second `dispose()` call changes nothing further — `MainThreadCommandsTests.disposeRemovesEveryCommandItRegistered` |
| main-thread-commands-007 | execute-rejects-with-the-extensions-own-exception, invoke-logs-a-caller-less-throw | `executeCommand('test.cmd')` where `test.cmd`'s registered callback throws | The promise rejects with the callback's own thrown value (same `Error` subclass, same message), and the throw never reaches `ExtensionHost`'s `pendingException` — `MainThreadCommandsTests.aThrowingCallbackRejectsAndNeverReachesTheHostsBookkeeping` |
| main-thread-commands-008 | invoke-logs-a-caller-less-throw, invoke-returns-callback-failure-on-throw | `registry.execute(id: "test.cmd")` (a palette-style dispatch with no `executeCommand` caller) where `test.cmd`'s callback throws | The throw is logged and swallowed — `registry.execute` returns normally, the extension host stays usable, and no exception reaches the caller — `MainThreadCommandsTests.aThrowingCallbackOnTheSwiftPathIsSwallowed` |
| main-thread-commands-009 | get-commands-filters-underscore-prefixed-ids-on-true, get-commands-defaults-to-including-every-id | Register a command whose id starts with `"_"` alongside an ordinary one, then call `getCommands(true)` and separately `getCommands()` | `getCommands(true)` resolves with a list excluding the underscore-prefixed id; `getCommands()` (no argument) resolves with a list that includes it — `MainThreadCommandsTests.getCommandsFiltersInternalIds` |
| main-thread-commands-010 | unregister-is-guarded-by-both-ownership-and-token, disposable-captures-a-fixed-token | Register `'test.cmd'`, keep its `Disposable`, `dispose()` the whole adaptor, let a different registrant register `'test.cmd'` again, then call the kept `Disposable`'s `dispose()` | The kept `Disposable`'s late `dispose()` call is a no-op — the newer registration under `'test.cmd'` survives untouched — `MainThreadCommandsTests.aStaleDisposableDoesNotRemoveSomebodyElsesCommand` |
| main-thread-commands-011 | execute-rejects-on-torn-down-adaptor, register-raises-on-torn-down-adaptor, get-commands-rejects-on-torn-down-adaptor | Deallocate the adaptor's owner, then call the previously captured `registerCommand`, `executeCommand`, and `getCommands` block values | `registerCommand` raises synchronously; `executeCommand` and `getCommands` each reject their returned promise; none of the three answers `undefined` as if it had succeeded — `MainThreadCommandsTests.aTornDownAdaptorRaisesOrRejectsButNeverAnswersUndefined` |

## Edge Cases

- **Null/empty input**: `registerCommand()` called with zero arguments MUST fail the string-command-id guard (since `arguments.first` is `nil`) and MUST raise the same message as a non-string first argument, per **register-requires-string-command-id** (MUST).
- **Null/empty input**: `registerCommand('id')` called with only one argument MUST fail the callback-argument guard and MUST raise `"registerCommand requires a callback function."`, per **register-requires-callback-argument** (MUST).
- **Null/empty input**: `getCommands()` called with zero arguments MUST be treated identically to `getCommands(false)` — `arguments.first?.toBool()` is `nil`, and the `?? false` default applies — per **get-commands-defaults-to-including-every-id** (MUST).
- **Boundary values**: a command id equal to the empty string is a valid `String` and reaches `handleRegisterCommand`'s duplicate check and `registry.register` exactly as any other id would; nothing in this file rejects it (MUST, per **register-requires-string-command-id**, which checks only that the value is a string).
- **Concurrent access**: `MainThreadCommands` is `@MainActor`-isolated with no additional locking; `ownedCallbacks` and the `static` `dispatchHasCaller` are read and mutated only on the main actor, so there is no data race to define behavior for (MUST).
- **Concurrent access**: `executeCommand` invoked reentrantly from inside a command callback that is itself running under an outer `executeCommand` dispatch MUST see the inner dispatch's own `dispatchingForACaller` set `dispatchHasCaller` to `true` for the inner call and restore the outer call's prior value afterward, per **dispatch-has-caller-restored-after-a-caller-dispatch** (MUST).
- **Error states**: a registered callback that throws MUST become a `CallbackFailure` rather than a Swift error or a value, per **invoke-returns-callback-failure-on-throw**; whether it is also logged depends on `hasCaller`, per **invoke-logs-a-caller-less-throw** (MUST).
- **Error states**: a context whose command dispatch trampoline cannot be installed MUST cause `registerCommand` to raise before any `Disposable` is returned, and MUST cause `executeCommand` to reject rather than resolve with `undefined`, per **register-requires-dispatchable-context** and **execute-rejects-on-dispatch-unavailable** (MUST).
- **Cancellation or timeout**: not applicable to any of the three members — dispatch through `registry.execute` is synchronous on the main actor; the only asynchronous element is a command callback's own `async` return value, which `executeCommand` hands back unresolved via `settledPromise` rather than awaiting or imposing a timeout on (fact, per **execute-settles-a-thenable-result**).
- **Missing or unreachable resource**: `executeCommand` on an id nothing has registered MUST reject with `CommandRegistryError.unknownCommand`'s own message, `"No command is registered with id '<id>'"`, per **execute-translates-registry-errors-verbatim** (MUST).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `registry` | `CommandRegistry` | none (required, no default) | The shared registry every `registerCommand`, `executeCommand` and `getCommands` call dispatches through; supplied by whoever constructs this adaptor for one extension host instance. |

## Deep Linking

Not applicable: `MainThreadCommands.swift` defines no URL, route, or navigable destination — it dispatches JavaScript-originated command calls into an in-process registry, with no navigation surface of its own.

## Localization

`MainThreadCommands` raises or rejects with hardcoded English string literals; none carries a localization key, `String(localized:)` call, or String Catalog entry. Every raised or rejected message reaches the extension as a thrown or rejected JavaScript error, so an extension author sees the literal English text regardless of locale. The two log-only messages inside `invoke` (a caller-less rejection or throw) reach only the host's own log, never the extension. `CommandRegistryError.description`'s two messages (`AppCommand.swift`) are not literals in this file, but `handleExecuteCommand` passes them through to the extension verbatim, so they are user-facing text this component is responsible for surfacing.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `registerCommand requires a string command id.` | Raised when `registerCommand`'s first argument is missing or not a string. |
| (none — literal only) | `registerCommand requires a callback function.` | Raised when `registerCommand`'s second argument is missing. |
| (none — literal only) | `registerCommand's callback must be a function.` | Raised when `registerCommand`'s second argument fails the `Function` instance check. |
| (none — literal only) | `command '<id>' already exists` | Raised when this adaptor already owns `<id>`. |
| (none — literal only) | `executeCommand requires a string command id.` | Rejected when `executeCommand`'s first argument is missing or not a string. |
| (none — literal only) | `The extension host could not install its command dispatch trampoline in JavaScript context '<context name>', so extension command callbacks cannot be invoked in it.` | Raised by `registerCommand` or rejected by `executeCommand` when `VSCodeAPI.canDispatch` is `false`. |
| (none — literal only, from `CommandRegistryError.description`) | `No command is registered with id '<id>'` | Rejected by `executeCommand` when `registry.execute` throws `.unknownCommand`. |
| (none — literal only, from `CommandRegistryError.description`) | `Command '<id>' is registered but currently disabled` | Rejected by `executeCommand` when `registry.execute` throws `.commandDisabled`. |

## Accessibility Options

Not applicable: `MainThreadCommands.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; `registerCommand`, `executeCommand` and `getCommands` are always available once a `MainThreadCommands` is constructed.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind; its only telemetry-adjacent calls are the `OSLog` lines covered under Logging, which are diagnostic logging, not analytics events.

## Privacy

- **Data collected**: `MainThreadCommands` collects no data of its own; `ownedCallbacks` holds, for the lifetime of each registration, the extension-supplied `JSValue` callback (and, indirectly through it, the `JSContext` and everything the extension's module graph captured). Arguments and results that pass through `executeCommand` are the caller's own values, forwarded untouched — never copied, stored, or inspected beyond the type checks the Behavioral Requirements describe.
- **Storage**: `MainThreadCommands` performs no storage of its own; `ownedCallbacks` is in-memory only and exists for the adaptor's lifetime. `CommandRegistry`'s own `registrationsByID` and `registrationOrder` are likewise in-memory, out of this file's scope.
- **Transmission**: nothing here leaves the process; every call is an in-process JavaScriptCore round trip between the host and a `JSContext` the same process owns.
- **Retention**: a registered callback's `JSValue` (and the `JSContext` it keeps alive) is retained in `ownedCallbacks` until its `Disposable` is disposed, until `dispose()` unregisters it, or until `CommandRegistry.register` replaces it under the same id — per **disposable-is-idempotent** and **dispose-unregisters-every-owned-command**.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `MainThreadCommands` (via `Loggable`'s default, derived from the type name)

| Event | Level | Message |
|-------|-------|---------|
| A registered callback's returned thenable rejects, and no `executeCommand` caller is awaiting it | error | `Extension command '<commandID>' rejected: <reason.toString() or "<unprintable>">` |
| A registered callback throws, and no `executeCommand` caller is awaiting it | error | `Extension command '<commandID>' threw: <exception.toString() or "<unprintable>">` |
| A registered callback could not be dispatched at all (its context has no usable trampoline) | error | `Extension command '<commandID>' could not be dispatched: its context has no usable command dispatch trampoline` |

No other event in this file is logged: `registerCommand`'s three refusals (missing id, missing callback, non-function callback, duplicate id, unreachable context) and `executeCommand`'s rejections are all surfaced directly to the extension as raised or rejected errors instead of being logged, per the corresponding Behavioral Requirements above. The "could not be dispatched" line is the one report logged unconditionally, per **invoke-logs-dispatch-unavailable-unconditionally**, whether or not an `executeCommand` caller is also told through its own rejected promise.

## Platform Notes

- **SwiftUI**: not applicable to this file — `MainThreadCommands.swift` imports only `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing in this component renders a view.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadCommands.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is `@MainActor`-isolated per its class declaration, and the `CommandRegistry` it wraps (`AppCommand.swift`) is likewise `@MainActor` and macOS-only in this codebase today.
- **Compose**: model `MainThreadCommands` as a Kotlin `class MainThreadCommands(private val registry: CommandRegistry)` confined to the main dispatcher, with `ownedCallbacks` as a plain `MutableMap` guarded by that confinement (no `Mutex` needed, matching the source's own single-actor argument). The extension callback's `JSValue` becomes whatever function-reference type the host's own JavaScript engine binding (a J2V8 or Rhino function reference, say) exposes, and the `dispatchHasCaller` bit becomes a top-level (or companion-object) `var`, matching its `static`-not-instance requirement.
- **React/Web**: this component's own upstream is VS Code's real `MainThreadCommands` (`mainThreadCommands.ts`), already TypeScript, so a web port is closer to restoring the original than translating it: a class wrapping a `CommandsRegistry`-equivalent map, with `registerCommand` returning a `Disposable`-shaped object and `executeCommand` returning a native `Promise` rather than the settled-synchronously `Thenable` this host constructs by hand.
- **WinUI 3**: model `MainThreadCommands` as a class whose every member runs on a captured `DispatcherQueue` (the `@MainActor` equivalent — WinUI 3 has no compiler-enforced actor isolation, so every entry point MUST assert `DispatcherQueue.HasThreadAccess` or marshal via `DispatcherQueue.TryEnqueue` at the top of the method, since nothing else catches a wrong-thread call at compile time the way Swift's `@MainActor` does). `CommandRegistry`'s role is filled by a class exposing `Register(ICommand)`, `Execute(string, object[])` and `Unregister(string, Guid token)`, where `ICommand`'s `Execute(object[] args)` mirrors `AppCommand.run`'s `([Any]) -> Any?` shape rather than WinUI's own parameterless `ICommand.Execute(object? parameter)`. `registerCommand`'s returned `Disposable` becomes an `IDisposable` whose `Dispose()` is guarded by an `Interlocked.Exchange`-backed idempotence flag, matching `VSCodeAPI.disposable(in:onDispose:)`'s single-call guarantee. The extension callback becomes whatever the chosen JavaScript engine binding uses — ClearScript's `ScriptObject`/`dynamic`, or Jint's `JsValue`, standing in for `JavaScriptCore.JSValue` — and `executeCommand`'s settled-promise handoff becomes a `TaskCompletionSource<object?>` that is already completed by the time it is returned, for the synchronous-dispatch case, or the extension's own awaited `Task` passed straight through for an `async` callback.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadCommands.swift` |

## Design Decisions

**Decision**: `dispatchHasCaller` is a `static` property of `MainThreadCommands`, not an instance property, even though it exists only to answer a question about one dispatch.
**Rationale**: the bit belongs to the dispatch, not to the adaptor instance running it. When extension A's `executeCommand` awaits a command extension B registered, B's callback runs on a path that genuinely has a caller, and B's own adaptor instance is not the one that knows it — a per-instance flag would read `false` there and log B's rejection as noise. A second reason points the same way: the closure `handleRegisterCommand` hands to `AppCommand.run` captures no `self`, which keeps the adaptor out of the registry's retain graph; reaching an instance flag from `invoke` would reintroduce exactly that captured edge, or read a weak reference that is `nil` after teardown and answer wrongly.
**Approved**: pending

**Decision**: `registerCommand` raises a synchronous JavaScript exception on failure, while `executeCommand` and `getCommands` reject a returned promise on the equivalent failure.
**Rationale**: the choice follows each member's own return shape. `registerCommand` returns a `Disposable`, not a `Thenable`, so there is nothing for a failure to reject; answering `undefined` instead of raising would let an extension push nothing useful onto `context.subscriptions` while believing it had registered a command. `executeCommand` and `getCommands` return a `Thenable`, and a VS Code extension writes `await vscode.commands.executeCommand(...)` inside a `try` — a synchronous throw from underneath that `await` would reach a `catch` other than the one the extension wrote, so both reject instead.
**Approved**: pending

**Decision**: `invoke` returns private `CallbackFailure` and `DispatchUnavailable` wrapper values through `AppCommand.run`'s `([Any]) -> Any?` signature, rather than converting a callback's failure into a rejection or thrown error at the point of dispatch.
**Rationale**: `AppCommand.run` is shared with every non-extension command in the app, and giving it any awareness that JavaScript or promises exist would leak this adaptor's concerns into a type the registry, the menu system, and the command palette all depend on. `CallbackFailure` and `DispatchUnavailable` are private to this file, and only `handleExecuteCommand` — the one member with a promise to settle — ever unwraps them.
**Approved**: pending

**Decision**: a duplicate registration is refused only when the *same* `MainThreadCommands` instance already owns the id; a duplicate the app or a different extension's adaptor owns falls through unchanged to `CommandRegistry.register(_:isExtensionContributed:)`'s own replace-and-warn (or built-in-refusal) behavior.
**Rationale**: whether one extension may register an id twice is a question `ownedCallbacks` can answer outright — it is this adaptor's own bookkeeping. Whether an extension may shadow an id the app or a *different* extension already owns is a trust decision that belongs with `ExtensionRegistry` and the permissions work the class doc explicitly defers to, not with a per-instance ownership check that has no visibility into who else registered what.
**Approved**: pending

**Decision**: `makeDisposable` captures the `CommandRegistration` token at registration time, and `unregisterOwned` re-checks that captured token against the live entry in `ownedCallbacks` before touching `registry` at all.
**Rationale**: the captured token, not the `disposed` flag `VSCodeAPI.disposable(in:onDispose:)` already tracks, is what protects against a stale-but-unfired `Disposable`. A `Disposable` minted before a `dispose()`-and-re-register cycle is still "unfired" as far as `VSCodeAPI.disposable` is concerned, so without the token check its late `dispose()` call would unregister the adaptor's own *fresh* registration of the same id, made after the earlier teardown — and, one level further, `unregisterOwned` also confirms the token still matches what `registry` itself has filed, so a registration that a different registrant has since displaced is never removed by someone else's stale token either.
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
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
