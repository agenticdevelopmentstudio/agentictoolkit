---
id: 6a7598bd-afe0-4ae9-af93-237908b767f8
title: Host Diagnostic Sink
domain: agentictoolkit://cookbook/workspace/extensions/vscode-api/languages/host-diagnostic-sink
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The production diagnostic sink and write side of vscode.languages.onDidChangeDiagnostics:
  logs each mutation''s affected URLs, then fires the shared debounced event emitter.'
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- diagnostics
- event-emitter
depends-on:
- agentictoolkit://cookbook/workspace/extensions/host/extension-event
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

# Host Diagnostic Sink

## Overview

This component is the production conformer of the diagnostic-sink protocol (declared alongside the diagnostics bridge) and, per its own documentation, "the write side of `vscode.languages.onDidChangeDiagnostics`." Every mutation the diagnostics bridge makes to an extension-visible diagnostic collection — both `set` overloads, `delete`, `clear`, and a collection's own `dispose()` — already reports the URLs it touched to this sink through the single diagnostics-changed requirement; this component's whole job is to log that call and then fire the shared debounced event emitter that publishes those changes to extensions as `vscode.languages.onDidChangeDiagnostics`. The type performs no windowing, merging, deduplication, or script delivery itself — that contract belongs to the shared event emitter, specified in the `extension-host-vs-code-api-extension-event` ingredient this recipe depends on. This sink is constructed once per extension host and handed the same emitter instance that every diagnostics-bridge instance built for that host also holds, so one extension's diagnostic change is visible to every other extension's `onDidChangeDiagnostics` listener.

## Behavioral Requirements

- **protocol-conformance**: This component MUST conform to the diagnostic-sink protocol, whose only requirement is a `diagnosticsChanged(for:)` operation taking a list of URLs.
- **type-is-final**: This component MUST NOT be designed for subclassing.
- **emitter-required-no-default**: The sink's constructor MUST take the shared emitter as a required parameter with no default value, matching the diagnostics bridge's own required constructor parameters.
- **emitter-stored-once**: This component MUST store the constructor's emitter argument in a property set exactly once at initialization and never reassigned.
- **log-before-fire**: `diagnosticsChanged(for:)` MUST log, recording the count of URLs, before it fires the emitter.
- **fire-forwards-uris-unchanged**: `diagnosticsChanged(for:)` MUST fire the emitter with the exact list it was given, in the same order, without deduplicating, filtering, copying, or transforming any element.
- **fire-called-unconditionally**: `diagnosticsChanged(for:)` MUST fire the emitter exactly once per call, with no guard on the list's count; it MUST fire even when the list is empty.
- **one-emitter-shared-across-adaptors**: The emitter instance passed to the sink's constructor MUST be the same instance passed to every diagnostics-bridge instance constructed for the same extension host; the extension host's own installer MUST construct exactly one such emitter and share it between the two.
- **loggable-conformance**: This component MUST conform to the shared logging convention, giving it the host application's own subsystem and a category named after this component, per that convention's own defaults.

## Appearance

Not applicable — this is the extension host's diagnostic-change notifier, not a visual component.

## States

Not applicable — this is the extension host's diagnostic-change notifier, not a visual component. It has no lifecycle of its own beyond existing between construction and the extension host's teardown; the per-window state machine that follows a fire call belongs to the shared event emitter and is documented in the `extension-host-vs-code-api-extension-event` ingredient.

## Accessibility

Not applicable — this is the extension host's diagnostic-change notifier, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| host-diagnostic-sink-001 | fire-forwards-uris-unchanged, fire-called-unconditionally | Construct the sink with an emitter that has zero listeners; call `diagnosticsChanged(for:)` with the URL for `/one.txt` | The emitter fires with exactly `[/one.txt]`; end to end, this is `MainThreadDiagnosticsTests.eachOfTheFiveMutatingOperationsProducesAnEvent`'s step 1 (`c.set(vscode.Uri.file('/one.txt'), d)`), which reaches the real sink and records `/one.txt` at the listener |
| host-diagnostic-sink-002 | fire-called-unconditionally, log-before-fire | Call `diagnosticsChanged(for:)` with an empty list | The sink logs `"diagnostics changed for 0 uri(s)"` and fires the emitter with an empty list; no early return on an empty list |
| host-diagnostic-sink-003 | log-before-fire | Call `diagnosticsChanged(for:)` with two URLs | The log line (`"diagnostics changed for 2 uri(s)"`) runs before the emitter fires — traced to the operation's statement order |
| host-diagnostic-sink-004 | one-emitter-shared-across-adaptors, fire-forwards-uris-unchanged | Build a sink and a diagnostics bridge sharing one emitter; install an `onDidChangeDiagnostics` listener; call `c.set(vscode.Uri.file('/a.txt'), d)` then `c.delete(vscode.Uri.file('/b.txt'))` inside one window, then close the window | The listener receives one event whose URLs are `["/a.txt", "/b.txt"]` — `MainThreadDiagnosticsTests.twoMutationsInOneWindowArriveAsOneEventCarryingBothUris`, which exercises `diagnosticsChanged(for:)` twice and the shared emitter's coalescing once |
| host-diagnostic-sink-005 | emitter-required-no-default | Attempt to construct the sink with no arguments | Fails to compile: the constructor declares no default for the emitter parameter |
| host-diagnostic-sink-007 | protocol-conformance, loggable-conformance | Inspect the sink's declared conformances | Declares exactly the diagnostic-sink protocol (in the primary declaration) and the shared logging convention (in its own extension), satisfied by `diagnosticsChanged(for:)` and the shared logger property respectively |

## Edge Cases

- **Null/empty input**: `diagnosticsChanged(for:)` called with an empty list MUST still log (`"diagnostics changed for 0 uri(s)"`) and MUST still fire the emitter with an empty list; when the shared emitter has at least one live listener, that empty list is queued as one entry (per the event emitter's queue-before-open behavior — see the `extension-host-vs-code-api-extension-event` ingredient), so a window whose only fire was empty still delivers an empty list to listeners rather than delivering nothing (MUST).
- **Boundary values**: this component enforces no minimum or maximum on the list's count; a single-element list and a list of many thousands of URLs are logged and forwarded identically, with no truncation or batching (MUST).
- **Concurrent access**: this component is confined to a single serialized execution domain with no locking of its own; two diagnostics-bridge adaptors (each backing a different extension's diagnostic collection) calling `diagnosticsChanged(for:)` "at the same time" from an extension are always serialized onto that domain by the extension host, so there is no data race for this type to define behavior for; see Platform Notes for how the confinement is enforced (MUST).
- **Error states**: `diagnosticsChanged(for:)` has no dependency (no I/O, no network, no throwing call) that can fail; it cannot itself raise, throw, or return an error, so there is no failure path in this component to communicate (MUST — a fact about the source, not a gap: error handling for a failed delivery belongs to the event emitter, per the ingredient this recipe depends on).
- **Offline or disconnected state**: Not applicable — this component performs no network access of its own; it relays an already-in-process list of URLs to an in-process emitter, so there is no connectivity-loss case to define.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `emitter` | event emitter (list of URLs) | none (required) | The shared emitter `diagnosticsChanged(for:)` fires. Callers MUST pass the same instance handed to every diagnostics-bridge instance built for the same extension host; the extension host's own installer is the given source's one production wiring site for this. |

## Deep Linking

Not applicable: this component defines no URL scheme, route, or navigable destination — it is an internal host notifier with no navigation surface.

## Localization

Not applicable: the only string literal in this component is the debug log message `"diagnostics changed for \(uris.count) uri(s)"`, which reaches only the host's own log (see Logging), never an extension or an end user; the component defines no user-facing or extension-facing text.

## Accessibility Options

Not applicable: this component renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; `diagnosticsChanged(for:)` is always active once this component is constructed.

## Analytics

Not applicable: the source contains no analytics or telemetry event of any kind; its only instrumentation is the debug log line covered under Logging, which is diagnostic logging, not an analytics event.

## Privacy

- **Data collected**: this component collects no data of its own; `diagnosticsChanged(for:)` receives whatever list of URLs the diagnostics bridge's mutating operations already computed as affected and forwards them unchanged to the emitter. The only thing it derives independently is a count, which is what it logs — not the URLs themselves.
- **Storage**: none; this component holds no state beyond its own emitter reference and performs no persistence.
- **Transmission**: nothing leaves the process; firing the emitter hands the list to the shared event emitter, which delivers it to a script context already running in the same process — see the `extension-host-vs-code-api-extension-event` ingredient.
- **Retention**: none; this component keeps no copy of the list after `diagnosticsChanged(for:)` returns.

## Logging

Subsystem: the host application's own bundle identifier (falling back to a default when unavailable) | Category: a name derived from this component's own type name, per the shared logging convention's defaults

| Event | Level | Message |
|-------|-------|---------|
| `diagnosticsChanged(for:)` is called | debug | `diagnostics changed for \(uris.count) uri(s)` |

No other event in this component is logged: `diagnosticsChanged(for:)` has exactly one statement before firing the emitter, and it is this one.

## Platform Notes

- **SwiftUI**: not applicable to this file — `HostDiagnosticSink.swift` imports only `Foundation`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing in this component renders a view.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/HostDiagnosticSink.swift` is part of the `AgenticToolkitMacOS` framework target, macOS-only per `project.yml`. It is `@MainActor`-isolated, constructed once by `ExtensionHostInstaller.init` alongside the shared `ExtensionEventEmitter<[URL]>` it fires, and consumed only through the `ExtensionDiagnosticSink` requirement `MainThreadDiagnostics` calls. `HostDiagnosticSink` MUST be declared `@MainActor`; `emitter`'s reads and every `diagnosticsChanged(for:)` call MUST execute on the main actor, matching `ExtensionDiagnosticSink`'s own `@MainActor` protocol declaration. `HostDiagnosticSink` MUST NOT declare `Sendable` conformance; being a `public final class` isolated only by `@MainActor`, the compiler MUST keep every instance confined to the main actor's isolation domain rather than allow it to cross actors implicitly — so a call to `diagnosticsChanged(for:)` from a context not already isolated to `@MainActor`, with no `await`, fails to compile.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/vscode-api/languages/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
