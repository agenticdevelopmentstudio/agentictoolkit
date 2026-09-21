//
//  BlockingWork.swift
//  AgenticToolkit
//

import Foundation

/// Runs work that blocks its thread somewhere that is allowed to block.
///
/// **`Task.detached` is not this, and that is the whole reason this exists.** A
/// detached task is detached from its parent's *context* — priority,
/// task-locals, cancellation — not from the executor. It runs on the same
/// cooperative pool as every other task, and that pool is sized to the core
/// count on the assumption that nothing on it ever blocks. Work that sits on a
/// semaphore or a `read(2)` for two minutes therefore does not move off the
/// pool by being detached; it removes one of a handful of threads from it, and
/// enough of them at once deadlocks every unrelated `await` in the process.
///
/// Two call sites arrived at this independently, which is why it is an
/// extraction rather than two copies. `VSIXInstaller` expands an archive
/// through `CommandRunner`, which is synchronous and waits on a
/// `DispatchSemaphore` for up to 124 seconds — a timeout plus two termination
/// graces — and it was reached from an `async` method with nothing in between.
/// `OpenDocumentReloader` reads a whole file with `String(contentsOf:)`, which
/// is an unbounded synchronous read of something that may be on a network
/// volume, and it was doing it on the main actor.
///
/// GCD's global queues are the right destination because they are the pool
/// that *is* allowed to block: they grow a thread when their existing ones are
/// stuck, which is precisely the behaviour the cooperative pool refuses to have.
///
/// **Not a cancellation point.** The continuation resumes when `work` returns,
/// and nothing here can interrupt a synchronous call that is already running —
/// cancelling the surrounding task leaves the thread where it is. Work that
/// needs to be abandoned needs its own deadline, the way `CommandRunner` has
/// one; this type only decides *where* it runs.
public enum BlockingWork {

    /// Runs `work` on a GCD global queue and resumes the caller with what it
    /// returned or threw.
    ///
    /// `T` and `work` are both `Sendable` because the value crosses a thread
    /// boundary in each direction. A caller holding something that is not —
    /// `Process`, for one — passes the parts it is built from and builds it
    /// inside the closure.
    public static func run<T: Sendable>(
        qos: DispatchQoS.QoSClass = .userInitiated,
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: qos).async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}
