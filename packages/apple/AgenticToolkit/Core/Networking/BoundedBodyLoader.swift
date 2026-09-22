//
//  BoundedBodyLoader.swift
//  AgenticToolkit
//

import Foundation

/// Reads an HTTP response body into memory at the rate the system delivers it,
/// refusing one that grows past a ceiling.
///
/// **Why this exists rather than one of the two obvious answers.**
/// `URLSession.data(from:)` cannot be bounded: by the time it returns, however
/// much a stranger decided to send is already in this process's memory.
/// `URLSession.bytes(from:)` can be — that is what this replaced — but its
/// `AsyncBytes` yields one `UInt8` per `await`, and an asynchronous call per
/// byte costs about two orders of magnitude: 23.8 MB/s against an in-process
/// stub where `data(from:)` measures 2.5 GB/s. On a 512 MB artifact that is
/// twenty seconds of a cooperative-pool thread spent counting to five hundred
/// million, and the same routine also serves the metadata read behind a search
/// field, once per keystroke.
///
/// A data-task delegate gets both properties at once. The system hands over
/// whole chunks, exactly as it does for `data(from:)`, and the ceiling is
/// checked per chunk — so the refusal is a `cancel()` that stops the transfer
/// where it stands, rather than a check that arrives after the bytes do.
///
/// **The session, the delegate and the cycle.** `URLSession` retains its
/// delegate until it is invalidated, so a loader that were its own delegate
/// could never be deallocated and could therefore never invalidate itself. The
/// delegate is a separate object holding the shared state box; nothing it
/// retains points back here, so `deinit` runs and the session goes with it.
final class BoundedBodyLoader: Sendable {

    /// Raised when a body passed the ceiling. Carries the response, when one
    /// arrived, so a caller can still prefer its own reading of a failed
    /// status over "too large" — an error document from a 404 is a 404 first.
    enum Failure: Error {
        case tooLarge(URLResponse?)
    }

    private let session: URLSession
    private let state: State

    /// - Parameter configuration: Taken from the session the owner was given,
    ///   so an injected `protocolClasses` — which is how every test here
    ///   stands in for the registry — still applies.
    init(configuration: URLSessionConfiguration) {
        let state = State()
        self.state = state
        self.session = URLSession(
            configuration: configuration, delegate: Delegate(state: state), delegateQueue: nil)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    /// The body at `url` and the response it came with, or `Failure.tooLarge`
    /// once more than `limit` bytes have arrived.
    ///
    /// The ceiling is tested twice for the same reason the streaming version
    /// tested it twice: `expectedContentLength` is the sender's claim, so it
    /// can refuse an honest oversized answer before a byte of it is read, and
    /// it can never be trusted in the other direction — an understated header
    /// is exactly how a body walks past a ceiling.
    func body(at url: URL, limit: Int) async throws -> (data: Data, response: URLResponse) {
        let task = session.dataTask(with: url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.begin(task.taskIdentifier, limit: limit, continuation: continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }
}

// MARK: - The transfers in flight

/// What each live task has collected, behind one lock.
///
/// A lock rather than an actor because the writes come from the session's
/// delegate queue, which is not an async context, and the reads that matter
/// are the same three call sites *(simplicity)*.
private final class State: @unchecked Sendable {

    private struct Transfer {
        var limit: Int
        var data = Data()
        var response: URLResponse?
        var overflowed = false
        var continuation: CheckedContinuation<(data: Data, response: URLResponse), any Error>
    }

    private let lock = NSLock()
    private var transfers: [Int: Transfer] = [:]

    func begin(
        _ identifier: Int, limit: Int,
        continuation: CheckedContinuation<(data: Data, response: URLResponse), any Error>
    ) {
        lock.withLock {
            transfers[identifier] = Transfer(limit: limit, continuation: continuation)
        }
    }

    /// Records the response and answers whether the transfer may proceed.
    func accept(_ identifier: Int, response: URLResponse) -> Bool {
        lock.withLock {
            guard var transfer = transfers[identifier] else { return false }
            transfer.response = response
            // Only ever a short circuit: it refuses a refusal the byte count
            // below would reach anyway, and -1 for a chunked reply falls
            // through to it.
            if response.expectedContentLength > Int64(transfer.limit) {
                transfer.overflowed = true
            } else {
                transfer.data.reserveCapacity(
                    min(max(Int(response.expectedContentLength), 0), 1 << 20))
            }
            let allowed = !transfer.overflowed
            transfers[identifier] = transfer
            return allowed
        }
    }

    /// Appends a chunk and answers whether the task should now be cancelled.
    func append(_ identifier: Int, chunk: Data) -> Bool {
        lock.withLock {
            guard var transfer = transfers[identifier], !transfer.overflowed else { return false }
            transfer.data.append(chunk)
            guard transfer.data.count > transfer.limit else {
                transfers[identifier] = transfer
                return false
            }
            // Dropped on the spot. Holding a body that has already been
            // refused is the thing the ceiling exists to prevent, and the
            // cancellation below is not instantaneous.
            transfer.overflowed = true
            transfer.data = Data()
            transfers[identifier] = transfer
            return true
        }
    }

    func finish(_ identifier: Int, error: (any Error)?) {
        guard let transfer = lock.withLock({ transfers.removeValue(forKey: identifier) }) else {
            return
        }
        if transfer.overflowed {
            // Ahead of `error`, which for this transfer is the cancellation
            // this object asked for and would otherwise report as the cause.
            transfer.continuation.resume(
                throwing: BoundedBodyLoader.Failure.tooLarge(transfer.response))
        } else if let error {
            transfer.continuation.resume(throwing: error)
        } else if let response = transfer.response {
            transfer.continuation.resume(returning: (transfer.data, response))
        } else {
            transfer.continuation.resume(throwing: URLError(.badServerResponse))
        }
    }
}

// MARK: - The session's side

private final class Delegate: NSObject, URLSessionDataDelegate {

    private let state: State

    init(state: State) {
        self.state = state
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        completionHandler(state.accept(dataTask.taskIdentifier, response: response) ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if state.append(dataTask.taskIdentifier, chunk: data) {
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
    ) {
        state.finish(task.taskIdentifier, error: error)
    }
}
