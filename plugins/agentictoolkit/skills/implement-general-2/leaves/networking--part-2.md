<!-- leaf: implement-general-2/networking--part-2 · source: networking.md -->

# Bounded Body Loader — continued (part 2)

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
