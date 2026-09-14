//
//  OnceOnlyContinuation.swift
//  AgenticToolkit
//

import Foundation

/// Holds one `CheckedContinuation` and resumes it at most once.
///
/// Two things in this feature need that guarantee and neither can get it from
/// the continuation itself. A picker panel has four ways to end — Return,
/// Escape, the window resigning key, and a second request replacing it (see
/// `ExtensionPickerPresenter`'s replacement rule) — and the last two can
/// arrive after one of the first two has already answered. A thenable handed
/// to `VSCodeAPI.settlement(of:in:)` is extension code, and calling both
/// `resolve` and `reject`, or either of them twice, is legal JavaScript.
/// Resuming a `CheckedContinuation` a second time traps, so every path to an
/// answer goes through `finish(_:)`, and only the first call does anything.
///
/// At the root of `Features/Extensions/` rather than in `UI/` or
/// `VSCodeAPI/`: those two are its callers, and neither imports the other.
///
/// Holding the continuation rather than borrowing it is load-bearing for both
/// callers — it has to outlive the function that created it, because the
/// closures and `@convention(block)` handlers that answer are the box's only
/// owners and they run later.
///
/// `@MainActor` because every caller answers from the main actor: the picker
/// from AppKit callbacks, the settlement handlers through
/// `MainActor.assumeIsolated`. That also makes `isFinished` a `var` the type
/// system protects.
@MainActor
final class OnceOnlyContinuation<Value> {

    private let continuation: CheckedContinuation<UncheckedSendableBox<Value>, Never>

    /// Whether `finish(_:)` has already resumed the continuation.
    private(set) var isFinished = false

    init(continuation: CheckedContinuation<UncheckedSendableBox<Value>, Never>) {
        self.continuation = continuation
    }

    /// Resumes with `value` the first time this is called, and does nothing on
    /// every later call — including a later call with a different value.
    /// Ignoring rather than logging: a second answer is the normal shape of
    /// both callers' problem, not a fault to report.
    ///
    /// `Value` is boxed on the way through `resume`, which declares its
    /// parameter `sending` (`CheckedContinuation.swift:164`): a value reaching
    /// it from this `@MainActor` method is main-actor-isolated rather than
    /// disconnected, which the compiler rejects by name ("sending 'value'
    /// risks causing data races"). Nothing actually crosses an isolation
    /// domain — whoever builds the value, this method, and the `await` that
    /// receives it are all on the same main actor — and the box states that
    /// without widening `Value` itself, which for
    /// `VSCodeAPI.settlement(of:in:)` is a public type carrying a `JSValue` no
    /// caller should be told is safe to move.
    func finish(_ value: Value) {
        guard !isFinished else { return }
        isFinished = true
        continuation.resume(returning: UncheckedSendableBox(value: value))
    }
}
