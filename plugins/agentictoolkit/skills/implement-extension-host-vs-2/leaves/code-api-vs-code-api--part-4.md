<!-- leaf: implement-extension-host-vs-2/code-api-vs-code-api--part-4 · source: extension-host-vs-code-api-vs-code-api.md -->

# VSCodeAPI — continued (part 4)

## Privacy

- **Data collected**: none of its own; `VSCodeAPI` holds no stored state and collects nothing about the user. It transiently handles values an extension itself supplies (its callbacks, its thenables, its error objects) for the duration of one call.
- **Storage**: none — `VSCodeAPI` is a stateless enum with no persisted or cached data of its own; the trampoline objects it caches on `globalThis` live only for the lifetime of their `JSContext`.
- **Transmission**: none — everything happens in-process inside JavaScriptCore; nothing here makes a network call or writes to disk.
- **Retention**: an extension-supplied value is retained only as long as the call stack that produced it, or (for `settlement(of:in:)`) until the thenable it is watching settles or its `JSContext` is torn down; `member(_:of:whenTornDown:body:)`'s weak capture of `owner` ensures a torn-down adaptor is not kept alive by a still-reachable JavaScript callback.

## Platform Notes

- **SwiftUI**: not applicable — `VSCodeAPI.swift` imports only Foundation, JavaScriptCore, OSLog, and this framework's own `Loggable`; nothing here renders a view or depends on SwiftUI.
- **AppKit / UIKit**: this is the source. `VSCodeAPI.swift` lives in `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/`, part of the macOS-only `AgenticToolkitMacOS` module per `project.yml`; it is `@MainActor` because `JSValue` is not `Sendable` and JavaScriptCore always calls an installed block on the thread that made the call, which for this host is the main actor driven by AppKit's own run loop. No iOS target packages this file today.
- **Compose**: model `VSCodeAPI` as a Kotlin `object` (or a set of top-level functions) confined to the main dispatcher, since there is no per-instance state to gate; `JSValue`/`JSContext` become whatever the chosen embeddable JS engine binding uses, and the evaluate-once-and-cache-under-a-global trampoline pattern ports directly, since it depends only on the engine's own global-object and `Proxy` support, which most JVM-embeddable JS engines provide.
- **React/Web**: this component's own counterpart needs no cross-boundary bridging ceremony at all, since a real VS Code extension already runs as JavaScript inside the same runtime as the host (VS Code's own `vscode.d.ts` and extension host process fill this role); a from-scratch web port only needs the once-only-settlement guard around a native `Promise`'s `resolve`/`reject` and the `Proxy`-based stub namespace, both of which are already plain JavaScript in `helperSource`/`subNamespaceFactorySource` and need no translation.
- **WinUI 3**: model `VSCodeAPI` as a static class confined to a captured `DispatcherQueue` — WinUI 3's nearest equivalent to `@MainActor` — asserting `DispatcherQueue.HasThreadAccess` or marshaling via `TryEnqueue` at every entry point, since nothing catches a wrong-thread call at compile time the way Swift's actor isolation does. `JSContext`/`JSValue` become the chosen embeddable engine's types (ClearScript's `ScriptEngine`/`ScriptObject`, or Jint's `Engine`/`JsValue`); the promise builders and `settlement(of:in:)` become helpers around `TaskCompletionSource<object?>`, guarded by `Interlocked.CompareExchange` in place of the once-only continuation box, since .NET has no first-class `Promise` type and no `CheckedContinuation` leaked-continuation diagnostic to inherit. The frozen-trampoline-object pattern ports if the engine's script realm supports freezing a host-exposed object; the `Proxy`-based `subNamespace` stub has no built-in .NET equivalent and must be hand-rolled over `DynamicObject`/`IDynamicMetaObjectProvider` (ClearScript) or a custom `ObjectInstance` override (Jint) to reproduce the `get`/`has`/`set`/`deleteProperty`/`ownKeys`/`getOwnPropertyDescriptor` trap set this file defines directly in JavaScript.

## Design Decisions

- **Decision**: `call(_:thisArg:arguments:)` never falls back to invoking `function` directly when the trampoline cannot be installed.
  **Rationale**: an uncaught throw from a direct call is exactly what routing every call through the JavaScript trampoline exists to keep out of the host's own exception handling; a direct-call fallback would reopen that path for precisely the contexts where the trampoline is least trustworthy.
  **Approved**: pending

- **Decision**: `sharedHelper(in:)` and `subNamespaceFactory(in:)` adopt whatever object already exists under their cached global name rather than verifying its provenance.
  **Rationale**: a JavaScript object cannot prove its provenance to JavaScript, and freezing the object after installation cannot retroactively make an already-adopted impostor genuine. The blast radius is bounded to the pre-empting extension's own context: `outcome(of:in:)` refuses a malformed *returned* record from any caller, and an impostor that throws instead lands in that same extension's own pending-exception state, never another extension's.
  **Approved**: pending

- **Decision**: `settlement(of:in:)` imposes no timeout on an unsettled thenable.
  **Rationale**: upstream VS Code does not settle either, and answering after some fixed delay would invent user-visible-wrong behavior (an extension told a picker was dismissed that the user never saw). The cost — one leaked continuation and two capturing blocks per un-settling thenable — is confined to the extension whose own thenable never resolves.
  **Approved**: pending

- **Decision**: the `onFulfilled`/`onRejected` blocks in `settlement(of:in:)`, and `observeRejection`'s `onRejected`, capture no `JSValue`, reading their argument from `currentArguments()` or minting a fresh `undefined` from `JSContext.current()` at call time instead.
  **Rationale**: a `JSValue` retains its `JSContext`, so a block capturing one and exported to JavaScript creates a retain cycle between the block and the context; the leak would then be the whole context rather than one continuation.
  **Approved**: pending

- **Decision**: `CallOutcome.returned(nil)` is a distinct, narrow case rather than being folded into "the callback returned `undefined`".
  **Rationale**: a callback that genuinely returns nothing answers a `JSValue` holding `undefined`, not a Swift `nil`; `nil` here means the bridge itself declined to answer. Conflating the two would let a caller resolve an extension's promise with `undefined` — the same answer a successful `void` command produces — when the true situation was a dispatch failure.
  **Approved**: pending

- **Decision**: `UncheckedSendableBox` is one generic type rather than several private, purpose-built box structs.
  **Rationale**: several unrelated standard-library signatures independently require `Sendable` for values (`JSValue`s and closures over them) this module cannot conform, because `JSValue` is a JavaScriptCore class it does not own. One declaration replaces what would otherwise be several private structs under different names, each a copy of another.
  **Approved**: pending

- **Decision**: `VSCodeAPI`, `CallOutcome`, `Settlement`, and `ThenLookup` carry no `Sendable` conformance beyond `TeardownResponse`'s explicit one.
  **Rationale**: every value in play (`JSValue`, `JSContext`) is non-`Sendable` by nature, and every producer and consumer is already confined to `VSCodeAPI`'s own `@MainActor` isolation; adding a conformance would either be a false promise or require boxing types that have no reason to leave the actor.
  **Approved**: pending
