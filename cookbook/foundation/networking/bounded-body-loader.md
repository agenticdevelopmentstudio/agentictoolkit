---
id: 14abf162-be65-4a58-9ffd-31f2145a50d3
title: Bounded Body Loader
domain: agentictoolkit://cookbook/foundation/networking/bounded-body-loader
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A bounded, per-chunk-checked HTTP body reader that refuses a response
  past a caller-set byte ceiling, used by an extension-registry client for
  downloads and metadata reads.
platforms:
- swift
- macos
tags:
- networking
- http
- streaming
- concurrency
- memory-safety
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/Core/Networking/BoundedBodyLoader.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/OpenVSXClient.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/OpenVSXClientLimitsTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Bounded Body Loader

## Overview

This component is a single internal type, visible only within its own
module: a bounded HTTP body reader that reads a response body into memory
at the rate the system delivers it, and refuses one that grows past a
caller-supplied ceiling. Its one operation — read the body at a URL,
bounded by a limit — is the sole caller-facing surface, used by an
extension-registry client for both its package downloads (an installable
bundle, a signature archive, a public key) and its metadata reads (search,
detail) — one bounded-read rule shared by two ceilings. The design exists
because the two more obvious ways to read a response body could not do
this: one cannot be bounded at all, and the other can be bounded but reads
roughly two orders of magnitude slower against a local benchmark because it
yields the body one byte at a time. Reading whole chunks at the transport's
own rate, with the ceiling checked after each chunk, gets both properties.

## Behavioral Requirements

- **dedicated-session**: The loader MUST build its own transport session
  from the configuration it is given (not reuse a caller-supplied session
  instance), so that a configuration the caller customized — including any
  injected protocol handlers — still governs the loader's own transfers.
- **delegate-object**: The loader's session MUST use a separate callback
  object (not the loader itself) to receive transport events, holding only
  a reference to the shared per-transfer state and nothing that points
  back to the loader.
- **body-transfer**: Reading a body at a given URL and limit MUST start an
  independent transfer on the loader's own session and, on success, return
  the accumulated body together with the response value once the transfer
  completes without the accumulated size exceeding the limit.
- **per-call-task**: Each call to read a body MUST start an independent
  transfer; a single loader instance MUST support multiple such calls,
  sequential or concurrent.
- **header-ceiling-check**: When a received response declares an expected
  length greater than the limit, the loader MUST refuse the transfer —
  cancelling it as soon as the response arrives — before any body chunk is
  read.
- **chunked-length-fallthrough**: A response that declares no expected
  length (for example, a chunked transfer encoding) MUST NOT be refused by
  the declared-length check; such a transfer MUST instead be bounded
  solely by the running per-chunk check below.
- **running-ceiling-check**: The loader MUST append each received chunk to
  a per-transfer running buffer, and once that buffer's size exceeds the
  limit it MUST cancel the underlying transfer and MUST discard the buffer
  (reset it to empty) rather than return, or continue to accumulate, a
  partial body.
- **overflow-error**: When a transfer is refused for exceeding the limit by
  either the declared-length check or the running check, reading the body
  MUST throw the too-large failure, carrying the response received before
  the refusal, or nothing when no response had yet been recorded.
- **status-agnosticism**: The loader MUST NOT itself inspect or validate
  the HTTP status code of any response; a non-2xx response's body is read
  (or refused for size) exactly as a 2xx response's would be, and its
  response value is what the too-large failure or a successful return
  carries back so the caller can make that status decision itself.
- **underlying-error-propagation**: When the transport reports a transfer's
  completion with an error and that transfer was not refused for size,
  reading the body MUST rethrow that error unchanged.
- **missing-response-fallback**: If a transfer finishes with neither an
  error nor any response ever recorded, reading the body MUST throw a
  bad-server-response error.
- **cooperative-cancellation**: Reading a body MUST cancel its underlying
  transfer when the calling context is cancelled, and MUST let the
  resulting failure reach the caller through the same error path as any
  other transport error.
- **concurrent-isolation**: The loader MUST keep each in-flight transfer's
  buffer, limit, response, and continuation isolated by that transfer's own
  identifier, guarded by one lock, so that concurrent calls to read a body
  on the same loader instance never corrupt or merge one transfer's
  accumulated data with another's.
- **concurrent-sharing-safe**: The loader MUST be safe to share across
  concurrent callers; a single instance MAY be used from multiple
  concurrent calling contexts without the caller adding synchronization of
  its own.
- **stale-callback-tolerance**: A transport callback naming a transfer
  identifier the shared state no longer tracks (already finished and
  removed) MUST be treated as a no-op — it MUST NOT throw or crash.
- **disposal-allows-in-flight-completion**: Disposing of the loader MUST
  let any in-flight transfers run to completion rather than aborting them.
- **no-automatic-retry**: The loader MUST NOT retry a failed or
  oversized transfer on its own; every failure — size or transport — is
  surfaced exactly once, to the caller, which decides whether to retry.
- **no-added-timeout**: The loader MUST NOT impose any timeout of its own
  beyond what the caller's session configuration already specifies for the
  request.
- **buffer-preallocation**: On accepting a response (the declared-length
  check does not refuse it), the loader SHOULD reserve capacity for the
  accumulated buffer sized from the declared expected length, clamped to
  zero-or-more and capped at 1,048,576 bytes (1 MiB) — a performance hint,
  not a correctness requirement, so a SHOULD deviation carries no
  behavioral risk.
- **failure-shape**: The loader's failure type MUST expose exactly one
  case, too-large (carrying an optional response value), as this
  component's sole error type.

## Appearance

Not applicable — this is a headless HTTP body reader, not a visual
component.

## States

Not applicable — this is a headless HTTP body reader, not a visual
component.

## Accessibility

Not applicable — this is a headless HTTP body reader, not a visual
component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| networking-001 | body-transfer | Limit 1,048,576 bytes (1 MiB); response body of 512 KiB; no misleading declared length. | Returns the full 512 KiB payload, byte for byte, paired with the response value. |
| networking-002 | running-ceiling-check | Limit 4096 bytes; response body of exactly 4096 bytes. | Returns a body of exactly 4096 bytes. |
| networking-003 | running-ceiling-check, overflow-error | Limit 4096 bytes; response body of 4097 bytes; no declared-length header. | Throws the too-large failure; never returns the 4097-byte body. |
| networking-004 | header-ceiling-check, overflow-error | Limit 1000 bytes; response declares an expected length of over a billion bytes but actually sends 10 bytes. | Throws the too-large failure immediately; the 10 bytes are never read into the returned body. |
| networking-005 | chunked-length-fallthrough, running-ceiling-check, overflow-error | Limit 1000 bytes; response declares an expected length of 1 byte but actually sends 4096 bytes. | Throws the too-large failure once the running total exceeds 1000 bytes — not accepted on the strength of the understated declared length. |
| networking-006 | status-agnosticism, overflow-error | Response status 503; body of 64 KiB past a limit of 1024 bytes. | Throws the too-large failure carrying a non-nil response whose status is 503, letting the caller check status ahead of size. |
| networking-007 | underlying-error-propagation | Connection drops mid-transfer before any ceiling is crossed. | Reading the body throws the underlying transport error unchanged, not the too-large failure. |
| networking-008 | cooperative-cancellation | The calling context is cancelled while reading the body is in progress. | The underlying transfer is cancelled and the call throws rather than hanging. |
| networking-009 | stale-callback-tolerance | A data-received or response-received callback arrives for a transfer identifier already removed from the shared state. | The state update returns without effect, without throwing or mutating any other transfer's record. |

## Edge Cases

- **Empty body**: A response with a zero-byte body MUST succeed under any
  limit of zero or more, returning an empty body paired with the response —
  the running total (0) never exceeds a non-negative limit. MUST.
- **Zero or negative limit**: A limit of zero or less MUST cause the
  transfer to be refused as too-large as soon as either the declared-length
  check (true for almost any declared length once the limit is
  non-positive) or the first non-empty chunk pushes the running total past
  that ceiling; a response that sends no bytes and declares no length
  would still succeed as an empty body. MUST.
- **Exact-boundary body**: A body of exactly limit bytes MUST be accepted
  in full; a body of limit + 1 bytes, with no declared-length header to
  short-circuit the declared-length check, MUST be refused by the running
  check alone. MUST.
- **Concurrent transfers on one loader**: Multiple simultaneous calls to
  read a body on the same loader instance MUST each receive independent
  bookkeeping keyed by their own transfer's identifier under the shared
  lock; one transfer overflowing its limit MUST NOT affect another
  concurrent transfer's buffer, limit, or outcome. MUST.
- **Unreachable host / DNS or TLS failure**: When the underlying connection
  never succeeds, the transport reports the failure through its completion
  callback, and the loader MUST rethrow that error unchanged rather than
  reporting it as too-large or swallowing it. MUST.
- **Connectivity lost mid-transfer (offline/disconnected)**: If the network
  drops after some chunks arrived but before completion, and the running
  total had not yet crossed the limit, the loader MUST rethrow the
  resulting transport error and MUST NOT return the partial body collected
  so far — a transfer that does not finish MUST NOT hand back a partial
  result. MUST.
- **A cancellation racing an overflow**: If the calling context is
  cancelled at the same moment the running check would have overflowed,
  either outcome (a cancellation error or the too-large failure) is
  acceptable; the design does not order the two, and completion is only
  ever signaled once per transfer, so exactly one of them MUST reach the
  caller — not both, and not neither. MUST.
- **Deallocation with a transfer in flight**: If the loader is disposed of
  while a transfer is outstanding, disposal MUST let that transfer's task
  run to completion and resume normally, since the callback object and
  shared state it still needs are retained by the transport session
  itself, independent of the loader. MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `configuration` | session configuration (opaque to this contract) | none — required at construction | Supplies the loader's own transport session's behavior (including any injected protocol handlers, cache policy, and timeout fields); the loader adds no timeout, retry, or backoff of its own on top of it. |
| `limit` | integer (bytes) | none — required parameter of every read-body call | The maximum number of bytes the returned body may contain; enforced both against the declared expected length and against the running total of bytes actually received. |

## Deep Linking

Not applicable: this component has no URL scheme or navigable surface of
its own — it consumes a URL argument the caller already produced.

## Localization

Not applicable: the source contains no user-facing strings; its only error
value, the too-large failure, carries data, not a message.

## Accessibility Options

Not applicable: this is a headless HTTP body reader with no rendered UI to
apply a platform's display accessibility options to.

## Feature Flags

Not applicable: the source contains no feature-flag or remote-config check
gating any of its behavior.

## Analytics

Not applicable: the source emits no analytics or telemetry event of its
own; it returns data or throws to its caller and nothing else.

## Privacy

Not applicable: the loader collects, stores, and transmits nothing of its
own — it forwards whatever bytes and headers the caller's request and the
server's response already produce, and returns them to the caller as
opaque data it does not retain past the call.

## Logging

Not applicable: the source contains no logging calls of any kind — every
failure surfaces only as a thrown error to the caller, never as a log
line.

## Platform Notes

- **SwiftUI**: The source (`Core/Networking/BoundedBodyLoader.swift`) has no
  SwiftUI dependency at all — it is plain Foundation
  (`URLSession`/`URLSessionDataDelegate`/`NSLock`) consumed by a non-UI
  Swift type, `Core/Extensions/OpenVSXClient.swift`. A SwiftUI app ports
  this verbatim as a model-layer type with no `@Observable`/`@State`
  surface of its own.
- **AppKit / UIKit**: This is in fact the source's own platform:
  `BoundedBodyLoader` (`Core/Networking/BoundedBodyLoader.swift`) is a
  `final class`, not `public`, visible only inside `AgenticToolkitCore`,
  which builds for macOS but uses only the plain
  `URLSession`/`URLSessionDataDelegate` API available identically on
  iOS — nothing in it is AppKit-specific. Its one method,
  `body(at:limit:)`, builds its own `URLSession` from the given
  `URLSessionConfiguration` in `init(configuration:)`
  (**dedicated-session**) and hands that session a separate `Delegate`
  object conforming to `URLSessionDataDelegate` that holds only a `State`
  box, never a reference back to the loader (**delegate-object**),
  breaking the retain cycle a self-delegating loader would create (see
  Design Decisions). The declared-length check compares a response's
  `expectedContentLength` against `Int64(limit)` inside `didReceive
  response:completionHandler:`, answering `.cancel` to refuse it
  (**header-ceiling-check**); the running check appends each `didReceive
  data:` chunk to a per-transfer buffer inside `State`, keyed by the
  task's `taskIdentifier` and guarded by one `NSLock`
  (**running-ceiling-check**, **concurrent-isolation**). `BoundedBodyLoader`
  is declared `Sendable` (**concurrent-sharing-safe**). The too-large
  failure is `BoundedBodyLoader.Failure.tooLarge(URLResponse?)`, its sole
  case (**failure-shape**, **overflow-error**); the missing-response
  fallback throws `URLError(.badServerResponse)`
  (**missing-response-fallback**); cooperative cancellation is wired
  through `withTaskCancellationHandler`'s `onCancel: { task.cancel() }`
  (**cooperative-cancellation**); and `deinit` calls
  `session.finishTasksAndInvalidate()` rather than
  `invalidateAndCancel()`, letting in-flight tasks finish
  (**disposal-allows-in-flight-completion**).
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Networking/BoundedBodyLoader.swift` |

## Design Decisions

**Decision**: The transfer is driven by a delegate-style callback on a
dedicated data task rather than by an async byte-stream API.
**Rationale** (Swift/Foundation implementation): `URLSession.bytes(from:)`'s
`AsyncBytes` yields one `UInt8` per `await`, measured at 23.8 MB/s against
an in-process stub where `data(from:)` — which cannot be bounded — measures
2.5 GB/s. A delegate on a data task gets whole chunks at the system's rate
while still checking the ceiling per chunk, so the 20-second worst case on
a 512 MB artifact stays a delegate callback loop rather than a
half-million-iteration `await` loop, and the same code path also serves
the metadata read behind every keystroke of a search field.
**Approved**: pending

**Decision**: The session's callback object is a separate object that
holds only the shared state, rather than the loader being its own
delegate.
**Rationale** (Swift implementation): `URLSession` retains its delegate for
as long as the session is not invalidated. A loader that were its own
delegate would be retained by its own session and could never be
deallocated, so it could never reach its own teardown to invalidate that
same session — a retain cycle with no way out. Splitting the delegate into
an object with no reference back to the loader breaks that cycle.
**Approved**: pending

**Decision**: The byte ceiling is checked twice — once against the
declared expected length before any chunk is read, and again against the
running total as chunks arrive — rather than relying on either check
alone.
**Rationale**: The header alone is the sender's unverified claim: an
understated declared length costs the sender nothing to write and would
let an oversized body slip past a header-only check, which is exactly what
the understated-length test vector (networking-005) pins. The running
check alone would still work correctly but would always cost reading at
least one chunk before refusing an obviously oversized answer; checking
the header first lets the claimed-oversized case (networking-004) refuse
before a single byte of a claimed-oversized transfer is read.
**Approved**: pending

**Decision**: An overflowed transfer's buffer is reset to empty
immediately, rather than left populated until completion is signaled.
**Rationale**: Holding a body that has already been refused is exactly the
unbounded-memory condition the ceiling exists to prevent, and cancellation
is not instantaneous — more chunks can still arrive on the wire before it
takes effect. Clearing the buffer the moment the overflow is detected
keeps that window from costing any additional retained memory.
**Approved**: pending

**Decision**: All per-transfer state across every concurrent call on one
loader instance is guarded by a single lock, rather than one lock per
transfer or an actor.
**Rationale** (Swift implementation): The writes arrive from the session's
delegate queue, which is not an async context, ruling out an `actor`
without a bridging layer. A single lock over a dictionary keyed by the
transfer's identifier is the simplest construction that still keeps every
transfer's bookkeeping correct — each critical section is a short
dictionary read-modify-write, not a long hold.
**Approved**: pending

**Decision**: Reading the body does not validate the HTTP status code, and
the too-large failure carries the response it had (or nothing) rather
than resolving the status-versus-size question itself.
**Rationale**: A response whose body is both oversized and behind an error
status (a proxy's lengthy 503 page, for instance) is more usefully reported
by its status than by its size — reporting "too large" would send a reader
looking for a limit to raise when the real fix is to retry later. Deciding
that precedence needs the status code, and this loader's only job is
bounding bytes, so it hands the response back either way and lets the
caller — which already knows what "success" means for its own request —
make that call, exactly as the extension-registry client's own body helper
does immediately after unwrapping the too-large failure.
**Approved**: pending

**Decision**: The accumulated buffer's preallocated capacity is capped at
1,048,576 bytes (1 MiB) regardless of how large the declared expected
length claims the body will be.
**Rationale**: The limit itself can be as large as 512 MB for the artifact
path this loader serves elsewhere in the module; reserving capacity for
the full claimed length up front would commit a very large allocation
before a single byte has been verified as real. Capping the hint at 1 MiB
still avoids repeated reallocation for the common case (a small metadata
response) while never letting the preallocation itself become the
oversized-allocation problem the ceiling exists to prevent.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [resource-efficiency](agenticdevelopercookbook://compliance/performance#resource-efficiency) | passed | Performance |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | partial | Reliability |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | failed | Access Patterns |

`unit-test-coverage` is **partial**: no test file in the module targets
`BoundedBodyLoader` directly; its ceiling and cancellation behavior is
exercised only indirectly, through `OpenVSXClientLimitsTests.swift`'s
assertions against `OpenVSXClient.data(at:)` and `.search(_:)`, which call
`loader.body(at:limit:)` underneath. `separation-of-concerns` **passed**:
the loader does exactly one thing — bound and deliver a response body — and
leaves status validation, URL-scheme checks, and JSON decoding entirely to
its caller (see `status-agnosticism`). `explicit-error-handling`
**passed**: every completion path in `finish` resumes the continuation —
with `Failure.tooLarge`, the underlying error, the returned data, or
`URLError(.badServerResponse)` — and none of the four is dropped silently.
`resource-efficiency` **passed**: this file's entire purpose is bounding
memory use of a response body read, via the per-chunk running check, the
eager header check, and the capped preallocation hint. `timeout-handling`
is **partial**: the loader adds no stall or idle timeout beyond whatever
the caller's `URLSessionConfiguration` already specifies (see
`no-added-timeout`) — a slow trickle that never crosses the byte ceiling is
bounded only by that configuration, not by anything in this file.
`retry-with-backoff` is **failed**, honestly: the source implements no
retry or backoff of any kind (see `no-automatic-retry`); every failure — a
transport error, a `Failure.tooLarge`, or a cancellation — reaches the
caller once and the caller alone decides whether to retry.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to foundation/networking/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
