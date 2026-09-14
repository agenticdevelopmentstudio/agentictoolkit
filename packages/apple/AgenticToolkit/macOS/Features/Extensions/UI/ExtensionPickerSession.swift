//
//  ExtensionPickerSession.swift
//  AgenticToolkit
//

import Foundation

/// Holds one presentation's continuation and resumes it at most once.
///
/// A picker panel has four ways to end — Return, Escape, the window resigning
/// key, and a second request replacing it (see `ExtensionPickerPresenter`'s
/// replacement rule) — and the last two can arrive after one of the first two
/// has already answered. Resuming a `CheckedContinuation` a second time traps,
/// so every path to an answer goes through `finish(_:)`, and only the first
/// call does anything.
///
/// `internal`, not `public`: nothing outside this framework hands one across.
///
/// **Deliberately not unified with `VSCodeAPI.swift`'s
/// `SettlementContinuationBox`.** That box is the same shape — `@MainActor`,
/// a stored continuation, a once-only guard — but it is non-generic, private
/// to `VSCodeAPI.swift`, and already reviewed and landed; folding it into
/// this generic would be a refactor of shipped code this task did not ask
/// for. The duplication here is a recorded decision, not an oversight.
@MainActor
final class ExtensionPickerSession<Answer: Sendable> {

    private let continuation: CheckedContinuation<Answer?, Never>

    /// Whether `finish(_:)` has already resumed the continuation.
    private(set) var isFinished = false

    init(continuation: CheckedContinuation<Answer?, Never>) {
        self.continuation = continuation
    }

    /// Resumes with `answer` the first time this is called, and does nothing
    /// on every later call — including a later call with a different answer.
    func finish(_ answer: Answer?) {
        guard !isFinished else { return }
        isFinished = true
        continuation.resume(returning: answer)
    }
}
