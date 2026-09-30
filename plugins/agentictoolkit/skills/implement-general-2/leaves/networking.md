<!-- leaf: implement-general-2/networking · source: networking.md -->

**Rules** (cite as `implement-general-2/networking#<slug>`):

- `dedicated-session` MUST
- `delegate-object` MUST
- `body-transfer` MUST
- `per-call-task` MUST
- `header-ceiling-check` MUST
- `chunked-length-fallthrough` MUST
- `running-ceiling-check` MUST
- `overflow-error` MUST
- `status-agnosticism` MUST
- `underlying-error-propagation` MUST
- `missing-response-fallback` MUST
- `cooperative-cancellation` MUST
- `concurrent-isolation` MUST
- `sendable-conformance` MUST
- `stale-callback-tolerance` MUST
- `deinit-invalidation` MUST
- `no-automatic-retry` MUST
- `no-added-timeout` MUST
- `buffer-preallocation` SHOULD
- `failure-shape` MUST

# Bounded Body Loader

## Overview

`BoundedBodyLoader` (`Core/Networking/BoundedBodyLoader.swift`) is a single
internal type in `AgenticToolkitCore`: a `final class`, not `public`, so it is
visible only inside that module. It reads an HTTP response body into memory
at the rate the system delivers it, and refuses one that grows past a
caller-supplied ceiling. Its one method, `body(at:limit:)`, is the sole
current caller-facing surface, used by `OpenVSXClient`'s private `body(at:limit:tooLarge:)`
helper for both the OpenVSX registry's artifact downloads (`.vsix`,
`.sigzip`, public key) and its metadata JSON reads (`search`, `detail`) —
one bounded-read rule shared by two ceilings. The type's own doc comment
states its reason for existing over the two more obvious answers:
`URLSession.data(from:)` cannot be bounded at all, and `URLSession.bytes(from:)`
can be bounded but measures 23.8 MB/s against an in-process stub where
`data(from:)` measures 2.5 GB/s, because `AsyncBytes` yields one `UInt8` per
`await`. A data-task delegate gets both properties — whole chunks at the
system's rate, with the ceiling checked per chunk.

## Behavioral Requirements

- **dedicated-session**: `init(configuration:)` MUST build the loader's own
  `URLSession` from the `URLSessionConfiguration` it is given (not from a
  caller's `URLSession` instance), so that a configuration the caller
  customized — including an injected `protocolClasses` — still governs the
  loader's own transfers.
- **delegate-object**: The loader's session MUST use a separate `Delegate`
  object (not the loader itself) as its `URLSessionDataDelegate`, holding
  only a reference to the shared state box and nothing that points back to
  the loader.
- **body-transfer**: `body(at:limit:)` MUST start a data task for `url` on
  the loader's own session and, on success, return the accumulated response
  `Data` together with the `URLResponse` once the transfer completes without
  the accumulated size exceeding `limit`.
- **per-call-task**: Each call to `body(at:limit:)` MUST start an
  independent `URLSessionDataTask`; a single loader instance MUST support
  multiple such calls, sequential or concurrent.
- **header-ceiling-check**: When a received response's
  `expectedContentLength` is greater than `Int64(limit)`, the loader MUST
  refuse the transfer — answering `.cancel` from
  `didReceive response:completionHandler:` — before any body chunk is read.
- **chunked-length-fallthrough**: A response that reports no expected length
  (`expectedContentLength == -1`, e.g. `Transfer-Encoding: chunked`) MUST NOT
  be refused by the header check; such a transfer MUST instead be bounded
  solely by the running per-chunk check below.
- **running-ceiling-check**: The loader MUST append each received chunk to a
  per-transfer running buffer, and once that buffer's size exceeds `limit`
  it MUST cancel the underlying task and MUST discard the buffer (reset it
  to empty) rather than return, or continue to accumulate, a partial body.
- **overflow-error**: When a transfer is refused for exceeding `limit` by
  either the header or the running check, `body(at:limit:)` MUST throw
  `BoundedBodyLoader.Failure.tooLarge`, carrying the `URLResponse` received
  before the refusal, or `nil` when no response had yet been recorded.
- **status-agnosticism**: The loader MUST NOT itself inspect or validate the
  HTTP status code of any response; a non-2xx response's body is read (or
  refused for size) exactly as a 2xx response's would be, and its
  `URLResponse` is what `Failure.tooLarge` or a successful return carries
  back so the caller can make that status decision itself.
- **underlying-error-propagation**: When `URLSession` reports a transfer's
  completion with an error via `didCompleteWithError` and that transfer was
  not refused for size, `body(at:limit:)` MUST rethrow that error unchanged.
- **missing-response-fallback**: If a transfer finishes with neither an
  error nor any response ever recorded, `body(at:limit:)` MUST throw
  `URLError(.badServerResponse)`.
- **cooperative-cancellation**: `body(at:limit:)` MUST cancel its underlying
  `URLSessionDataTask` when the calling `Task` is cancelled, using
  `withTaskCancellationHandler`'s `onCancel`, and MUST let the resulting
  failure reach the caller through the same error path as any other
  transport error.
- **concurrent-isolation**: The loader MUST keep each in-flight transfer's
  buffer, limit, response, and continuation isolated by the originating
  `URLSessionTask`'s `taskIdentifier`, guarded by one lock, so that
  concurrent calls to `body(at:limit:)` on the same loader instance never
  corrupt or merge one transfer's accumulated data with another's.
- **sendable-conformance**: `BoundedBodyLoader` MUST be declared `Sendable`;
  a single instance MAY be shared across concurrent tasks and actors without
  the caller adding synchronization of its own.
- **stale-callback-tolerance**: A delegate callback naming a task identifier
  the shared state no longer tracks (already finished and removed) MUST be
  treated as a no-op — it MUST NOT throw or crash.
- **deinit-invalidation**: `deinit` MUST call
  `session.finishTasksAndInvalidate()`, letting any in-flight tasks run to
  completion rather than aborting them when the loader itself is
  deallocated.
- **no-automatic-retry**: The loader MUST NOT retry a failed or
  oversized transfer on its own; every failure — size or transport — is
  surfaced exactly once, to the caller, which decides whether to retry.
- **no-added-timeout**: The loader MUST NOT impose any timeout of its own
  beyond what the caller's `URLSessionConfiguration` already specifies for
  the request.
- **buffer-preallocation**: On accepting a response (the header check does
  not refuse it), the loader SHOULD reserve capacity for the accumulated
  buffer sized from `expectedContentLength`, clamped to zero-or-more and
  capped at 1,048,576 bytes (`1 << 20`) — a performance hint, not a
  correctness requirement, so a SHOULD deviation carries no behavioral risk.
- **failure-shape**: `BoundedBodyLoader.Failure` MUST expose exactly one
  case, `tooLarge(URLResponse?)`, as this component's sole error type.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `configuration` | `URLSessionConfiguration` | none — required `init` parameter | Supplies the loader's own `URLSession` its behavior (including any injected `protocolClasses`, cache policy, and timeout fields); the loader adds no timeout, retry, or backoff of its own on top of it. |
| `limit` | `Int` | none — required parameter of every `body(at:limit:)` call | The maximum number of bytes the returned body may contain; enforced both against the declared `expectedContentLength` and against the running total of bytes actually received. |

## Platform Notes

- **SwiftUI**: The source (`Core/Networking/BoundedBodyLoader.swift`) has no
  SwiftUI dependency at all — it is plain Foundation
  (`URLSession`/`URLSessionDataDelegate`/`NSLock`) consumed by a non-UI
  Swift type, `Core/Extensions/OpenVSXClient.swift`. A SwiftUI app ports
  this verbatim as a model-layer type with no `@Observable`/`@State`
  surface of its own.
- **AppKit / UIKit**: This is in fact the source's own platform: the
  `AgenticToolkitCore` target that holds this file builds for `macOS` only
  (`platform: macOS` in `packages/apple/AgenticToolkit/project.yml`), and
  nothing in the file is AppKit-specific — it is the same plain
  `URLSession`/`URLSessionDataDelegate` API available identically on iOS.
- **Compose**: Start from OkHttp or Ktor's `HttpClient` with a streaming
  interceptor (or a `Ktor` `HttpResponse.bodyAsChannel()` read loop) that
  checks `Content-Length` against the ceiling before reading, then reads
  chunks from the `ByteReadChannel`/`ResponseBody` and cancels once the
  running total exceeds it; the per-transfer state box becomes a
  `ConcurrentHashMap` keyed by request/coroutine id guarded by a `Mutex` or
  `synchronized` block in place of `NSLock`, and structured-concurrency
  `Job` cancellation replaces `withTaskCancellationHandler`.
- **React/Web**: Start from `fetch`'s `response.body.getReader()`
  (`ReadableStreamDefaultReader`); check `response.headers.get('content-length')`
  against the ceiling before the first `reader.read()`, then accumulate
  chunks and call `controller.abort()` on an `AbortController` tied to that
  `fetch` once the running total exceeds the ceiling — `AbortController`
  is the direct equivalent of `URLSessionDataTask.cancel()`, and the
  single-threaded event loop replaces the `NSLock`-guarded state box
  outright, since no two chunk callbacks for the same fetch can interleave.
- **WinUI 3**: Start from `System.Net.Http.HttpClient.SendAsync` with
  `HttpCompletionOption.ResponseHeadersRead` so headers arrive before the
  body is read; check `response.Content.Headers.ContentLength` against the
  ceiling the way `accept` does, then read the body through
  `Stream.ReadAsync` in a loop, accumulating into a buffer and enforcing the
  running ceiling exactly as `append` does, honoring a `CancellationToken`
  passed through the same `Task`-based `async`/`await` model as the
  source's `withTaskCancellationHandler`. The per-transfer bookkeeping this
  file keeps in a `taskIdentifier`-keyed dictionary behind an `NSLock`
  becomes a `ConcurrentDictionary` keyed by a request id, or simply local
  state per `SendAsync` call, since .NET's `HttpClient` does not multiplex
  many transfers through one shared delegate the way `URLSessionDataDelegate`
  does; there is no `System.Text.Json` involvement at this layer, since
  decoding the returned bytes is the caller's job, exactly as it is for
  `OpenVSXClient` here.

