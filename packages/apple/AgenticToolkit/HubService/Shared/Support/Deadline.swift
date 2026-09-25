import Foundation

/// Runs `operation`, giving up after `duration` and returning `fallback()`.
///
/// Unlike a task group, this never waits for the loser. A task group's
/// implicit `await` on its remaining children means a child that ignores
/// cancellation — a URL load with no timeout of its own, an actor call parked
/// behind one — still holds the caller past the deadline, which is exactly the
/// failure this guards. Here the losing task is cancelled and then *abandoned*:
/// the caller resumes on the deadline whatever the operation does next, and a
/// late result is discarded.
///
/// The cost of that guarantee is that an uncooperative operation keeps running
/// in the background. Use it where the caller must make progress — launch
/// bootstrap — not as a general-purpose timeout.
func withDeadline<T: Sendable>(
    _ duration: Duration,
    fallback: @escaping @Sendable () -> T,
    operation: @escaping @Sendable () async -> T
) async -> T {
    let gate = DeadlineGate<T>()
    let work = Task {
        let value = await operation()
        await gate.settle(value)
    }
    let timer = Task {
        try? await Task.sleep(for: duration)
        guard !Task.isCancelled else { return }
        await gate.settle(fallback())
    }
    let winner = await gate.firstValue
    work.cancel()
    timer.cancel()
    return winner
}

/// One-shot rendezvous between the operation and the timer: the first `settle`
/// wins and unparks `firstValue`; every later one is dropped. There is only
/// ever a single waiter — the `withDeadline` call that owns this gate.
private actor DeadlineGate<T: Sendable> {
    private var settled: T?
    private var waiter: CheckedContinuation<T, Never>?

    var firstValue: T {
        get async {
            if let settled { return settled }
            return await withCheckedContinuation { waiter = $0 }
        }
    }

    func settle(_ value: T) {
        guard settled == nil else { return }
        settled = value
        guard let waiter else { return }
        self.waiter = nil
        waiter.resume(returning: value)
    }
}
