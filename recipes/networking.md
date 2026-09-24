---
id: 14abf162-be65-4a58-9ffd-31f2145a50d3
title: Bounded Body Loader
domain: agentictoolkit://recipes/networking
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Bounded, per-chunk-checked HTTP body reader that refuses a response past
  a caller-set byte ceiling, used by OpenVSXClient for registry downloads and metadata
  reads.
platforms:
- swift
- macos
tags:
- networking
- http
- streaming
- url-session
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
| networking-001 | body-transfer | `limit: 1 << 20`, response body of 512 KiB, no misleading `Content-Length` | Returns `Data` equal to the full 512 KiB payload, byte for byte, with the paired `URLResponse` (traced to `aBodyUnderTheCapArrivesIntact`, exercised through `OpenVSXClient.data(at:)`) |
| networking-002 | running-ceiling-check | `limit: 4096`, response body of exactly 4096 bytes | Returns `Data` with `count == 4096` (traced to `aBodyOfExactlyTheCapIsAccepted`) |
| networking-003 | running-ceiling-check, overflow-error | `limit: 4096`, response body of 4097 bytes, no `Content-Length` header | Throws `Failure.tooLarge`, never returns the 4097-byte body (traced to `aBodyOneByteOverTheCapIsRefused`) |
| networking-004 | header-ceiling-check, overflow-error | `limit: 1000`, response claims `expectedContentLength: 1 << 30`, actually sends 10 bytes | Throws `Failure.tooLarge` immediately; the 10 bytes are never read into the returned `Data` (traced to `aClaimedLengthPastTheCapIsRefused`) |
| networking-005 | chunked-length-fallthrough, running-ceiling-check, overflow-error | `limit: 1000`, response claims `expectedContentLength: 1`, actually sends 4096 bytes | Throws `Failure.tooLarge` once the running total exceeds 1000, not accepted on the strength of the understated header (traced to `anUnderstatedLengthIsNotBelieved`) |
| networking-006 | status-agnosticism, overflow-error | Response status `503`, body of 64 KiB past a `limit: 1024` | Throws `Failure.tooLarge(response)` where `response` is non-nil and its `statusCode == 503`, letting the caller check status ahead of size (traced to `anErrorStatusOutranksTheCeiling`) |
| networking-007 | underlying-error-propagation | Connection drops mid-transfer before any ceiling is crossed | `body(at:limit:)` throws the underlying `URLError` unchanged, not `Failure.tooLarge` (traced to `finish`'s `else if let error` branch) |
| networking-008 | cooperative-cancellation | Calling `Task` is cancelled while `body(at:limit:)` is awaiting | The underlying `URLSessionDataTask` is cancelled (`onCancel: { task.cancel() }`) and the call throws rather than hanging |
| networking-009 | stale-callback-tolerance | A `didReceive data:` or `didReceive response:` callback arrives for a `taskIdentifier` already removed from `state.transfers` | `accept`/`append` return `false` without throwing or mutating any other transfer's record |

## Edge Cases

- **Empty body**: A response with a zero-byte body MUST succeed under any
  `limit >= 0`, returning empty `Data` paired with the response — the
  running total (0) never exceeds a non-negative limit. MUST.
- **Zero or negative `limit`**: A `limit` of `0` or less MUST cause the
  transfer to be refused as `Failure.tooLarge` as soon as either the header
  check (`expectedContentLength > Int64(limit)`, true for almost any
  declared length once `limit` is non-positive) or the first non-empty
  chunk pushes the running total past that ceiling; a response that sends
  no bytes and declares no length would still succeed as an empty body.
  MUST.
- **Exact-boundary body**: A body of exactly `limit` bytes MUST be accepted
  in full; a body of `limit + 1` bytes, with no `Content-Length` header to
  short-circuit the header check, MUST be refused by the running check
  alone. MUST.
- **Concurrent transfers on one loader**: Multiple simultaneous calls to
  `body(at:limit:)` on the same `BoundedBodyLoader` instance MUST each
  receive independent bookkeeping keyed by their own task's
  `taskIdentifier` under the shared lock; one transfer overflowing its
  `limit` MUST NOT affect another concurrent transfer's buffer, limit, or
  outcome. MUST.
- **Unreachable host / DNS or TLS failure**: When the underlying connection
  never succeeds, `URLSession` reports the failure via
  `didCompleteWithError`, and the loader MUST rethrow that `URLError`
  unchanged rather than reporting it as `Failure.tooLarge` or swallowing it.
  MUST.
- **Connectivity lost mid-transfer (offline/disconnected)**: If the network
  drops after some chunks arrived but before completion, and the running
  total had not yet crossed `limit`, the loader MUST rethrow the resulting
  transport error (e.g. `URLError(.networkConnectionLost)`) and MUST NOT
  return the partial `Data` collected so far — a transfer that does not
  finish MUST NOT hand back a partial result. MUST.
- **A cancellation racing an overflow**: If the calling `Task` is cancelled
  at the same moment the running check would have overflowed, either
  outcome (cancellation error or `Failure.tooLarge`) is acceptable; the
  source does not order the two, and `finish` is only ever invoked once per
  transfer, so exactly one of them MUST reach the caller — not both, and
  not neither. MUST.
- **Deallocation with a transfer in flight**: If the loader is deallocated
  while a transfer is outstanding, `deinit`'s
  `finishTasksAndInvalidate()` MUST let that transfer's task run to
  completion and resume its continuation normally, since the `Delegate` and
  `State` objects the session still needs are retained by the session
  itself, independent of the loader. MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `configuration` | `URLSessionConfiguration` | none — required `init` parameter | Supplies the loader's own `URLSession` its behavior (including any injected `protocolClasses`, cache policy, and timeout fields); the loader adds no timeout, retry, or backoff of its own on top of it. |
| `limit` | `Int` | none — required parameter of every `body(at:limit:)` call | The maximum number of bytes the returned body may contain; enforced both against the declared `expectedContentLength` and against the running total of bytes actually received. |

## Deep Linking

Not applicable: `BoundedBodyLoader` has no URL scheme or navigable surface
of its own — it consumes a `url` argument the caller already produced.

## Localization

Not applicable: the source contains no user-facing strings; its only error
value, `Failure.tooLarge(URLResponse?)`, carries data, not a message.

## Accessibility Options

Not applicable: this is a headless HTTP body reader with no rendered UI to
apply Reduce Motion, Increase Contrast, or Differentiate Without Color to.

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
opaque `Data` it does not retain past the call.

## Logging

Not applicable: the source contains no logging calls (no `os_log` or
`Logger` usage) — every failure surfaces only as a thrown Swift error to
the caller, never as a log line.

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

## Design Decisions

**Decision**: The transfer is driven by a `URLSessionDataDelegate` on a
dedicated data task rather than by `URLSession.bytes(from:)`'s
`AsyncBytes`.
**Rationale**: `AsyncBytes` yields one `UInt8` per `await`, measured at
23.8 MB/s against an in-process stub where `data(from:)` — which cannot be
bounded — measures 2.5 GB/s. A delegate on a data task gets whole chunks at
the system's rate while still checking the ceiling per chunk, so the
20-second worst case on a 512 MB artifact stays a delegate callback loop
rather than a half-million-iteration `await` loop, and the same code path
also serves the metadata read behind every keystroke of a search field.
**Approved**: pending

**Decision**: The session's delegate is a separate `Delegate` object that
holds only the shared `State` box, rather than the loader being its own
delegate.
**Rationale**: `URLSession` retains its delegate for as long as the session
is not invalidated. A loader that were its own delegate would be retained
by its own session and could never be deallocated, so it could never reach
`deinit` to invalidate that same session — a retain cycle with no way out.
Splitting the delegate into an object with no reference back to the loader
breaks that cycle.
**Approved**: pending

**Decision**: The byte ceiling is checked twice — once against the
declared `expectedContentLength` before any chunk is read, and again
against the running total as chunks arrive — rather than relying on either
check alone.
**Rationale**: The header alone is the sender's unverified claim: an
understated `Content-Length` costs the sender nothing to write and would
let an oversized body slip past a header-only check, which is exactly what
`anUnderstatedLengthIsNotBelieved` pins. The running check alone would
still work correctly but would always cost reading at least one chunk
before refusing an obviously oversized answer; checking the header first
lets `aClaimedLengthPastTheCapIsRefused`'s case refuse before a single byte
of a claimed-oversized transfer is read.
**Approved**: pending

**Decision**: An overflowed transfer's buffer is reset to an empty `Data()`
immediately, rather than left populated until `finish` runs.
**Rationale**: Holding a body that has already been refused is exactly the
unbounded-memory condition the ceiling exists to prevent, and the
`dataTask.cancel()` that follows is not instantaneous — more chunks can
still arrive on the wire before cancellation takes effect. Clearing the
buffer the moment `overflowed` is set keeps that window from costing any
additional retained memory.
**Approved**: pending

**Decision**: All per-transfer state (`transfers: [Int: Transfer]`) across
every concurrent call on one loader instance is guarded by a single
`NSLock`, rather than one lock per transfer or an `actor`.
**Rationale**: The writes arrive from the session's delegate queue, which
is not an async context, ruling out an `actor` without a bridging layer.
A single lock over a dictionary keyed by `taskIdentifier` is the simplest
construction that still keeps every transfer's bookkeeping correct — each
critical section is a short dictionary read-modify-write, not a long hold —
and the source's own comment marks this choice explicitly: "A lock rather
than an actor because the writes come from the session's delegate queue,
which is not an async context... *(simplicity)*."
**Approved**: pending

**Decision**: `body(at:limit:)` does not validate the HTTP status code, and
`Failure.tooLarge` carries the `URLResponse` it had (or `nil`) rather than
resolving the status-versus-size question itself.
**Rationale**: A response whose body is both oversized and behind an error
status (a proxy's lengthy 503 page, for instance) is more usefully reported
by its status than by its size — reporting "too large" would send a reader
looking for a limit to raise when the real fix is to retry later. Deciding
that precedence needs the status code, and this loader's only job is
bounding bytes, so it hands the `URLResponse` back either way and lets the
caller — which already knows what "success" means for its own request —
make that call, exactly as `OpenVSXClient`'s private `body` helper does
immediately after unwrapping `Failure.tooLarge`.
**Approved**: pending

**Decision**: The accumulated buffer's preallocated capacity is capped at
1,048,576 bytes (`1 << 20`) regardless of how large `expectedContentLength`
claims the body will be.
**Rationale**: `limit` itself can be as large as 512 MB for the artifact
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
