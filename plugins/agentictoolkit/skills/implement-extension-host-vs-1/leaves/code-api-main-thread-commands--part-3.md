<!-- leaf: implement-extension-host-vs-1/code-api-main-thread-commands--part-3 · source: extension-host-vs-code-api-main-thread-commands.md -->

# MainThreadCommands — continued (part 3)

**Rules** (cite as `implement-extension-host-vs-1/code-api-main-thread-commands--part-3#<slug>`):

- `execute-translates-registry-errors-verbatim` MUST
- `execute-rejects-on-any-other-thrown-error` MUST
- `get-commands-rejects-on-torn-down-adaptor` MUST
- `get-commands-defaults-to-including-every-id` MUST
- `get-commands-filters-underscore-prefixed-ids-on-true` MUST
- `get-commands-never-rejects-for-its-own-reason` MUST
- `get-commands-preserves-registration-order` MUST
- `dispose-unregisters-every-owned-command` MUST
- `unregister-is-guarded-by-both-ownership-and-token` MUST
- `disposable-is-idempotent` MUST
- `disposable-captures-a-fixed-token` MUST
- `teardown-does-not-capture-self` MUST
- `logging-conformance` MUST

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
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `registry` | `CommandRegistry` | none (required, no default) | The shared registry every `registerCommand`, `executeCommand` and `getCommands` call dispatches through; supplied by whoever constructs this adaptor for one extension host instance. |

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

## Privacy

- **Data collected**: `MainThreadCommands` collects no data of its own; `ownedCallbacks` holds, for the lifetime of each registration, the extension-supplied `JSValue` callback (and, indirectly through it, the `JSContext` and everything the extension's module graph captured). Arguments and results that pass through `executeCommand` are the caller's own values, forwarded untouched — never copied, stored, or inspected beyond the type checks the Behavioral Requirements describe.
- **Storage**: `MainThreadCommands` performs no storage of its own; `ownedCallbacks` is in-memory only and exists for the adaptor's lifetime. `CommandRegistry`'s own `registrationsByID` and `registrationOrder` are likewise in-memory, out of this file's scope.
- **Transmission**: nothing here leaves the process; every call is an in-process JavaScriptCore round trip between the host and a `JSContext` the same process owns.
- **Retention**: a registered callback's `JSValue` (and the `JSContext` it keeps alive) is retained in `ownedCallbacks` until its `Disposable` is disposed, until `dispose()` unregisters it, or until `CommandRegistry.register` replaces it under the same id — per **disposable-is-idempotent** and **dispose-unregisters-every-owned-command**.

