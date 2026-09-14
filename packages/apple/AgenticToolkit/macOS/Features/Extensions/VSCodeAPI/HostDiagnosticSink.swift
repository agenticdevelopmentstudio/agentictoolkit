//
//  HostDiagnosticSink.swift
//  AgenticToolkit
//

import Foundation
import OSLog
import AgenticToolkitCore

/// The production `ExtensionDiagnosticSink`, and — as of task 5.6b — the
/// write side of `vscode.languages.onDidChangeDiagnostics`.
///
/// **No longer unconsumed.** 5.6a-iii's version of this doc said the
/// `Event<T>` this sink would feed was task 5.6b's and that until 5.6b landed
/// the conformer existed only to log; 5.6b has landed, and this is where it
/// landed. Every mutation `MainThreadDiagnostics` makes already reports here
/// — `set` (both overloads), `delete`, `clear`, and a collection's own
/// `dispose()` — so firing the emitter from this one method is the whole
/// wiring, in place of a second notification path down the same eight call
/// sites. See `MainThreadDiagnostics`'s own doc for why the event's read and
/// write halves sit on opposite sides of this seam.
///
/// The log line is kept rather than replaced. It is the host's own record,
/// and it is the only observable left when no extension has subscribed —
/// which, per `event.ts:1585`, is exactly when the emitter drops the event
/// on the floor.
///
/// `emitter` is not defaulted, matching `MainThreadDiagnostics`'s own
/// `store`/`sink`/`events` parameters: one emitter is meant to be shared by
/// this sink and by every `MainThreadDiagnostics` (upstream has one
/// `_onDidChangeDiagnostics` per extension host, `extHostDiagnostics.ts:240`),
/// and a privately constructed default would silently disconnect the two
/// halves while still compiling. Build it with
/// `MainThreadDiagnostics.makeOnDidChangeDiagnosticsEmitter(window:)`.
@MainActor
public final class HostDiagnosticSink: ExtensionDiagnosticSink {

    /// The shared emitter behind every extension's
    /// `vscode.languages.onDidChangeDiagnostics`. `public` so the host can
    /// hand the same instance to each `MainThreadDiagnostics` it builds.
    public let emitter: ExtensionEventEmitter<[URL]>

    public init(emitter: ExtensionEventEmitter<[URL]>) {
        self.emitter = emitter
    }

    public func diagnosticsChanged(for uris: [URL]) {
        Self.logger.debug("diagnostics changed for \(uris.count) uri(s)")
        emitter.fire(uris)
    }
}

extension HostDiagnosticSink: Loggable {
    public static nonisolated let logger = makeLogger()
}
