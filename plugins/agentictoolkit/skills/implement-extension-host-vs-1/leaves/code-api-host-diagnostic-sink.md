<!-- leaf: implement-extension-host-vs-1/code-api-host-diagnostic-sink · source: extension-host-vs-code-api-host-diagnostic-sink.md -->

**Rules** (cite as `implement-extension-host-vs-1/code-api-host-diagnostic-sink#<slug>`):

- `protocol-conformance` MUST
- `main-actor-isolation` MUST
- `non-sendable-confinement` MUST
- `type-is-final` MUST
- `emitter-required-no-default` MUST
- `emitter-stored-once` MUST
- `log-before-fire` MUST
- `fire-forwards-uris-unchanged` MUST
- `fire-called-unconditionally` MUST
- `one-emitter-shared-across-adaptors` MUST
- `loggable-conformance` MUST
- `winui-3` MUST — model HostDiagnosticSink as a sealed class implementing an IExtensionDiagnosticSink interface (void …

# HostDiagnosticSink

## Overview

`HostDiagnosticSink` (`packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/HostDiagnosticSink.swift`) is the production conformer of `ExtensionDiagnosticSink` (declared in `MainThreadDiagnostics.swift`) and, per its own doc comment, "the write side of `vscode.languages.onDidChangeDiagnostics`." Every mutation `MainThreadDiagnostics` makes to an extension-visible diagnostic collection — both `set` overloads, `delete`, `clear`, and a collection's own `dispose()` — already reports the `URL`s it touched to this sink through the single `ExtensionDiagnosticSink.diagnosticsChanged(for:)` requirement; `HostDiagnosticSink`'s whole job is to log that call and then fire the shared `ExtensionEventEmitter<[URL]>` that publishes those changes to extensions as `vscode.languages.onDidChangeDiagnostics`. The class performs no windowing, merging, deduplication, or JavaScript delivery itself — that contract belongs to `ExtensionEventEmitter`, specified in the `extension-host-vs-code-api-extension-event` ingredient this recipe depends on. `HostDiagnosticSink` is constructed once per extension host, in `ExtensionHostInstaller.init`, and handed the same emitter instance that every `MainThreadDiagnostics` built for that host also holds, so one extension's diagnostic change is visible to every other extension's `onDidChangeDiagnostics` listener.

## Behavioral Requirements

- **protocol-conformance**: `HostDiagnosticSink` MUST conform to `ExtensionDiagnosticSink`, whose only requirement is `func diagnosticsChanged(for uris: [URL])`.
- **main-actor-isolation**: `HostDiagnosticSink` MUST be declared `@MainActor`; `emitter`'s reads and every `diagnosticsChanged(for:)` call MUST execute on the main actor, matching `ExtensionDiagnosticSink`'s own `@MainActor` protocol declaration.
- **non-sendable-confinement**: `HostDiagnosticSink` MUST NOT declare `Sendable` conformance; being a `public final class` isolated only by `@MainActor`, the compiler MUST keep every instance confined to the main actor's isolation domain rather than allow it to cross actors implicitly.
- **type-is-final**: `HostDiagnosticSink` MUST be declared `final`; it MUST NOT be designed for subclassing.
- **emitter-required-no-default**: `HostDiagnosticSink.init(emitter:)` MUST take `emitter` as a required parameter with no default value, matching `MainThreadDiagnostics.init`'s own `store`/`sink`/`events` parameters.
- **emitter-stored-once**: `HostDiagnosticSink` MUST store the constructor's `emitter` argument in a `public let emitter: ExtensionEventEmitter<[URL]>` property, set exactly once at initialization and never reassigned.
- **log-before-fire**: `diagnosticsChanged(for:)` MUST call `Self.logger.debug(...)`, recording `uris.count`, before it calls `emitter.fire(uris)`.
- **fire-forwards-uris-unchanged**: `diagnosticsChanged(for:)` MUST call `emitter.fire(uris)` with the exact array it was given, in the same order, without deduplicating, filtering, copying, or transforming any element.
- **fire-called-unconditionally**: `diagnosticsChanged(for:)` MUST call `emitter.fire(uris)` exactly once per call, with no guard on `uris.count`; it MUST fire even when `uris` is empty.
- **one-emitter-shared-across-adaptors**: the `ExtensionEventEmitter<[URL]>` instance passed to `HostDiagnosticSink.init(emitter:)` MUST be the same instance passed as the `events` parameter to every `MainThreadDiagnostics` constructed for the same extension host, both built from `MainThreadDiagnostics.makeOnDidChangeDiagnosticsEmitter(window:)`; `ExtensionHostInstaller.init` MUST construct exactly one such emitter and share it between the two.
- **loggable-conformance**: `HostDiagnosticSink` MUST conform to `Loggable` via `extension HostDiagnosticSink: Loggable { public static nonisolated let logger = makeLogger() }`, giving it subsystem `Bundle.main.bundleIdentifier` and category `"HostDiagnosticSink"` per `Loggable`'s own defaults.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `emitter` | `ExtensionEventEmitter<[URL]>` | none (required) | The shared emitter `diagnosticsChanged(for:)` fires. Callers MUST pass the same instance handed to every `MainThreadDiagnostics` built for the same extension host, obtained from `MainThreadDiagnostics.makeOnDidChangeDiagnosticsEmitter(window:)`; `ExtensionHostInstaller.init` is the given source's one production wiring site for this. |

## Privacy

- **Data collected**: `HostDiagnosticSink` collects no data of its own; `diagnosticsChanged(for:)` receives whatever `[URL]` values `MainThreadDiagnostics`'s mutating methods already computed as affected and forwards them unchanged to `emitter.fire(uris)`. The only thing it derives independently is a count (`uris.count`), which is what it logs — not the URLs themselves.
- **Storage**: none; `HostDiagnosticSink` holds no state beyond its own `emitter` reference and performs no persistence.
- **Transmission**: nothing leaves the process; `emitter.fire(uris)` hands the array to `ExtensionEventEmitter<[URL]>`, which delivers it to a `JSContext` already running in the same process — see the `extension-host-vs-code-api-extension-event` ingredient.
- **Retention**: none; `HostDiagnosticSink` keeps no copy of `uris` after `diagnosticsChanged(for:)` returns.

## Platform Notes

- **SwiftUI**: not applicable to this file — `HostDiagnosticSink.swift` imports only `Foundation`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing in this component renders a view.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/HostDiagnosticSink.swift` is part of the `AgenticToolkitMacOS` framework target, macOS-only per `project.yml`. It is `@MainActor`-isolated, constructed once by `ExtensionHostInstaller.init` alongside the shared `ExtensionEventEmitter<[URL]>` it fires, and consumed only through the `ExtensionDiagnosticSink` requirement `MainThreadDiagnostics` calls.
- **Compose**: model `HostDiagnosticSink` as a small Kotlin class, e.g. `HostDiagnosticSink(private val emitter: ExtensionEventEmitter<List<Uri>>)`, confined to the main dispatcher and implementing an `ExtensionDiagnosticSink` interface's single `fun diagnosticsChanged(uris: List<Uri>)`. Log via a Timber-style tree (or `android.util.Log`) tagged with the class's simple name before calling `emitter.fire(uris)`, keeping the same log-then-fire order and no guard on an empty list.
- **React/Web**: this component's own upstream (`extHostDiagnostics.ts`) never introduces a separate sink object — its mutating methods call `this._onDidChangeDiagnostics.fire(...)` directly. A web port can collapse the indirection this Swift host keeps for its own architectural reasons (Ledger Ruling 5's "extension diagnostics get their own store," and the doc comment's "opposite sides of the seam"): log via a small logger utility, then call the emitter's own `fire(uris)` inline from the diagnostics store's mutation, rather than routing through a separate sink type.
- **WinUI 3**: model `HostDiagnosticSink` as a sealed class implementing an `IExtensionDiagnosticSink` interface (`void DiagnosticsChanged(IReadOnlyList<Uri> uris)`), holding a required `ExtensionEventEmitter<IReadOnlyList<Uri>>` field passed through the constructor with no default. Since WinUI 3 has no compiler-enforced actor isolation, `DiagnosticsChanged` MUST assert `DispatcherQueue.HasThreadAccess` (or marshal via `DispatcherQueue.TryEnqueue`) at its top, where Swift's `@MainActor` would otherwise catch a wrong-thread call at compile time. Log via `Microsoft.Extensions.Logging.ILogger<HostDiagnosticSink>.LogDebug(...)` before calling `emitter.Fire(uris)`; `System.Text.Json`, `HttpClient`, and `Windows.Storage` have no role here, since nothing in this file serializes, transmits, or persists.

## Design Decisions

**Decision**: `HostDiagnosticSink` is a distinct type from `MainThreadDiagnostics`, rather than `MainThreadDiagnostics` firing the emitter itself from its eight mutation call sites.
**Rationale**: per the source's own doc comment, this reuses the `ExtensionDiagnosticSink` seam an earlier task already built instead of laying a second notification path beside it, and it means a future host-side source of diagnostics that never goes through `MainThreadDiagnostics` (the analogue of upstream's `$acceptMarkersChange`) reaches extensions for free by calling the same sink.
**Approved**: pending

**Decision**: `diagnosticsChanged(for:)` logs before firing, and keeps the log line rather than removing it now that a real consumer of the emitter exists.
**Rationale**: per the source's own doc comment, the log line is "the host's own record, and it is the only observable left when no extension has subscribed — which... is exactly when the emitter drops the event on the floor" (per `ExtensionEventEmitter.fire`'s zero-listener guard, specified in the `extension-host-vs-code-api-extension-event` ingredient). Keeping it means a diagnostics change is never completely silent from the host's own perspective, even when no extension is listening yet.
**Approved**: pending

**Decision**: `HostDiagnosticSink.init(emitter:)` takes `emitter` with no default value.
**Rationale**: per the source's own doc comment, one emitter is meant to be shared by this sink and by every `MainThreadDiagnostics` built for the same host; a privately constructed default emitter would compile but silently disconnect the sink from the adaptors it is meant to notify, defeating the reason `emitter` is a constructor parameter at all.
**Approved**: pending

**Decision**: `diagnosticsChanged(for:)` has no guard on an empty `uris` array.
**Rationale**: not documented in the source beyond the absence of a guard; every one of `MainThreadDiagnostics`'s eight call sites already guards on `!affected.isEmpty` before calling the sink, so in the given production wiring this method is never actually called with an empty array. The method itself still fires unconditionally, which is a fact about this file worth recording (see Edge Cases) even though today's one caller never exercises it.
**Approved**: pending
