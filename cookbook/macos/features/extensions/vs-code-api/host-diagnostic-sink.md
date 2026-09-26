---
id: 6a7598bd-afe0-4ae9-af93-237908b767f8
title: HostDiagnosticSink
domain: agentictoolkit://cookbook/macos/features/extensions/vs-code-api/host-diagnostic-sink
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The production ExtensionDiagnosticSink and write side of vscode.languages.onDidChangeDiagnostics:
  logs each mutation''s affected URLs, then fires the shared debounced event emitter.'
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- diagnostics
- event-emitter
- mainactor
depends-on:
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/extension-event
related: []
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/HostDiagnosticSink.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadDiagnostics.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/ExtensionEvent.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Host/ExtensionHostInstaller.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/MainThreadDiagnosticsTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is the extension host's diagnostic-change notifier, not a visual component.

## States

Not applicable — this is the extension host's diagnostic-change notifier, not a visual component. It has no lifecycle of its own beyond existing between construction and the extension host's teardown; the per-window state machine that follows a `fire(_:)` call belongs to `ExtensionEventEmitter` and is documented in the `extension-host-vs-code-api-extension-event` ingredient.

## Accessibility

Not applicable — this is the extension host's diagnostic-change notifier, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| host-diagnostic-sink-001 | fire-forwards-uris-unchanged, fire-called-unconditionally | Construct `HostDiagnosticSink(emitter: e)` where `e` has zero listeners; call `diagnosticsChanged(for: [URL(fileURLWithPath: "/one.txt")])` | `e.fire` runs with exactly `[URL(fileURLWithPath: "/one.txt")]`; end to end, this is `MainThreadDiagnosticsTests.eachOfTheFiveMutatingOperationsProducesAnEvent`'s step 1 (`c.set(vscode.Uri.file('/one.txt'), d)`), which reaches the real `HostDiagnosticSink` and records `/one.txt` at the listener |
| host-diagnostic-sink-002 | fire-called-unconditionally, log-before-fire | Call `diagnosticsChanged(for: [])` directly | `Self.logger.debug` logs `"diagnostics changed for 0 uri(s)"` and `emitter.fire([])` is still called once; no early return on an empty array |
| host-diagnostic-sink-003 | log-before-fire | Call `diagnosticsChanged(for: [urlA, urlB])` | `Self.logger.debug` runs (message `"diagnostics changed for 2 uri(s)"`) before `emitter.fire([urlA, urlB])` runs — traced to the method body's statement order |
| host-diagnostic-sink-004 | one-emitter-shared-across-adaptors, fire-forwards-uris-unchanged | Build a `HostDiagnosticSink` and a `MainThreadDiagnostics` sharing one `ExtensionEventEmitter<[URL]>` (the `makeEventWiring(store:)` pattern); install an `onDidChangeDiagnostics` listener; call `c.set(vscode.Uri.file('/a.txt'), d)` then `c.delete(vscode.Uri.file('/b.txt'))` inside one window, then close the window | The listener receives one event whose `uris` are `["/a.txt", "/b.txt"]` — `MainThreadDiagnosticsTests.twoMutationsInOneWindowArriveAsOneEventCarryingBothUris`, which exercises `HostDiagnosticSink.diagnosticsChanged(for:)` twice and the shared emitter's coalescing once |
| host-diagnostic-sink-005 | emitter-required-no-default | Attempt `HostDiagnosticSink()` with no arguments | Fails to compile: `init(emitter:)` declares no default for `emitter` |
| host-diagnostic-sink-006 | main-actor-isolation, non-sendable-confinement | Attempt to call `diagnosticsChanged(for:)` on a `HostDiagnosticSink` instance from a context not already isolated to `@MainActor`, with no `await` | Fails to compile: the call crosses actor isolation without a hop, since neither `HostDiagnosticSink` nor `ExtensionDiagnosticSink` is `Sendable` and both are `@MainActor` |
| host-diagnostic-sink-007 | protocol-conformance, loggable-conformance | Inspect `HostDiagnosticSink`'s declared conformances | Declares exactly `ExtensionDiagnosticSink` (in the primary declaration) and `Loggable` (in its own extension), satisfied by `diagnosticsChanged(for:)` and `static nonisolated let logger` respectively |

## Edge Cases

- **Null/empty input**: `diagnosticsChanged(for: [])` MUST still log (`"diagnostics changed for 0 uri(s)"`) and MUST still call `emitter.fire([])`; when the shared emitter has at least one live listener, that empty array is queued as one entry (per `ExtensionEventEmitter.fire`'s queue-before-open behavior — see the `extension-host-vs-code-api-extension-event` ingredient), so a window whose only fire was empty still delivers an empty `uris` array to listeners rather than delivering nothing (MUST).
- **Boundary values**: `HostDiagnosticSink` enforces no minimum or maximum on `uris.count`; a single-element array and an array of many thousands of `URL`s are logged and forwarded identically, with no truncation or batching (MUST).
- **Concurrent access**: `HostDiagnosticSink` is `@MainActor`-isolated with no locking of its own; two `MainThreadDiagnostics` adaptors (each backing a different extension's `DiagnosticCollection`) calling `diagnosticsChanged(for:)` "at the same time" from JavaScript are always serialized onto the main actor by the extension host, so there is no data race for this type to define behavior for (MUST).
- **Error states**: `diagnosticsChanged(for:)` has no dependency (no I/O, no network, no throwing call) that can fail; it cannot itself raise, throw, or return an error, so there is no failure path in this file to communicate (MUST — a fact about the source, not a gap: error handling for a failed delivery belongs to `ExtensionEventEmitter.deliver(_:)`, per the ingredient this recipe depends on).
- **Offline or disconnected state**: Not applicable — `HostDiagnosticSink` performs no network access of its own; it relays an already-in-process `[URL]` value to an in-process emitter, so there is no connectivity-loss case to define.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `emitter` | `ExtensionEventEmitter<[URL]>` | none (required) | The shared emitter `diagnosticsChanged(for:)` fires. Callers MUST pass the same instance handed to every `MainThreadDiagnostics` built for the same extension host, obtained from `MainThreadDiagnostics.makeOnDidChangeDiagnosticsEmitter(window:)`; `ExtensionHostInstaller.init` is the given source's one production wiring site for this. |

## Deep Linking

Not applicable: `HostDiagnosticSink.swift` defines no URL scheme, route, or navigable destination — it is an internal Swift notifier with no navigation surface.

## Localization

Not applicable: the only string literal in `HostDiagnosticSink.swift` is the debug log message `"diagnostics changed for \(uris.count) uri(s)"`, which reaches only the host's own log (see Logging), never an extension or an end user; the file defines no user-facing or extension-facing text.

## Accessibility Options

Not applicable: `HostDiagnosticSink.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; `diagnosticsChanged(for:)` is always active once a `HostDiagnosticSink` is constructed.

## Analytics

Not applicable: the source contains no analytics or telemetry event of any kind; its only instrumentation is the `OSLog` debug line covered under Logging, which is diagnostic logging, not an analytics event.

## Privacy

- **Data collected**: `HostDiagnosticSink` collects no data of its own; `diagnosticsChanged(for:)` receives whatever `[URL]` values `MainThreadDiagnostics`'s mutating methods already computed as affected and forwards them unchanged to `emitter.fire(uris)`. The only thing it derives independently is a count (`uris.count`), which is what it logs — not the URLs themselves.
- **Storage**: none; `HostDiagnosticSink` holds no state beyond its own `emitter` reference and performs no persistence.
- **Transmission**: nothing leaves the process; `emitter.fire(uris)` hands the array to `ExtensionEventEmitter<[URL]>`, which delivers it to a `JSContext` already running in the same process — see the `extension-host-vs-code-api-extension-event` ingredient.
- **Retention**: none; `HostDiagnosticSink` keeps no copy of `uris` after `diagnosticsChanged(for:)` returns.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `HostDiagnosticSink` (via `Loggable`'s default, derived from the type name)

| Event | Level | Message |
|-------|-------|---------|
| `diagnosticsChanged(for:)` is called | debug | `diagnostics changed for \(uris.count) uri(s)` |

No other event in this file is logged: `diagnosticsChanged(for:)` has exactly one statement before `emitter.fire(uris)`, and it is this one.

## Platform Notes

- **SwiftUI**: not applicable to this file — `HostDiagnosticSink.swift` imports only `Foundation`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing in this component renders a view.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/HostDiagnosticSink.swift` is part of the `AgenticToolkitMacOS` framework target, macOS-only per `project.yml`. It is `@MainActor`-isolated, constructed once by `ExtensionHostInstaller.init` alongside the shared `ExtensionEventEmitter<[URL]>` it fires, and consumed only through the `ExtensionDiagnosticSink` requirement `MainThreadDiagnostics` calls.
- **Compose**: model `HostDiagnosticSink` as a small Kotlin class, e.g. `HostDiagnosticSink(private val emitter: ExtensionEventEmitter<List<Uri>>)`, confined to the main dispatcher and implementing an `ExtensionDiagnosticSink` interface's single `fun diagnosticsChanged(uris: List<Uri>)`. Log via a Timber-style tree (or `android.util.Log`) tagged with the class's simple name before calling `emitter.fire(uris)`, keeping the same log-then-fire order and no guard on an empty list.
- **React/Web**: this component's own upstream (`extHostDiagnostics.ts`) never introduces a separate sink object — its mutating methods call `this._onDidChangeDiagnostics.fire(...)` directly. A web port can collapse the indirection this Swift host keeps for its own architectural reasons (Ledger Ruling 5's "extension diagnostics get their own store," and the doc comment's "opposite sides of the seam"): log via a small logger utility, then call the emitter's own `fire(uris)` inline from the diagnostics store's mutation, rather than routing through a separate sink type.
- **WinUI 3**: model `HostDiagnosticSink` as a sealed class implementing an `IExtensionDiagnosticSink` interface (`void DiagnosticsChanged(IReadOnlyList<Uri> uris)`), holding a required `ExtensionEventEmitter<IReadOnlyList<Uri>>` field passed through the constructor with no default. Since WinUI 3 has no compiler-enforced actor isolation, `DiagnosticsChanged` MUST assert `DispatcherQueue.HasThreadAccess` (or marshal via `DispatcherQueue.TryEnqueue`) at its top, where Swift's `@MainActor` would otherwise catch a wrong-thread call at compile time. Log via `Microsoft.Extensions.Logging.ILogger<HostDiagnosticSink>.LogDebug(...)` before calling `emitter.Fire(uris)`; `System.Text.Json`, `HttpClient`, and `Windows.Storage` have no role here, since nothing in this file serializes, transmits, or persists.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/HostDiagnosticSink.swift` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` passes because `HostDiagnosticSink` does exactly one thing — log, then forward to the emitter — and delegates every other concern (windowing, merging, mapping, JavaScript delivery) to the injected `ExtensionEventEmitter<[URL]>` rather than reimplementing any of it. `unit-test-coverage` is partial: no test in the given sources calls `HostDiagnosticSink.diagnosticsChanged(for:)` directly and asserts on it in isolation (the way `RecordingDiagnosticSink` is asserted on for the mutation-count suite); the given `MainThreadDiagnosticsTests.swift` "onDidChangeDiagnostics wiring" suite exercises the real `HostDiagnosticSink` only end to end, through `MainThreadDiagnostics`'s mutating methods and a subscribed JavaScript listener, and no given test asserts on the debug log message at all. `explicit-error-handling` passes, trivially: `diagnosticsChanged(for:)` has no failure path — it counts an array, logs, and calls `emitter.fire(uris)`, none of which can throw, return an error, or produce an optional — so there is nothing in this file for the open question of swallowed errors to apply to. `secure-log-output` passes because the only value logged is `uris.count`, a bare integer; no file path, URL, credential, or other potentially sensitive value is ever written to the log. `no-hardcoded-strings` fails because `"diagnostics changed for \(uris.count) uri(s)"` is an English string literal with no localization key, `String(localized:)` call, or String Catalog entry (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
