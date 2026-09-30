<!-- leaf: implement-general-2/networking-rpc · source: networking-rpc.md -->

# Networking RPC

## Overview

Networking RPC is the non-UI logic root, under `packages/apple/AgenticToolkit/Core/RPC/`, for talking to a child process as if it were an RPC peer. It has four parts:

- `MessageFraming` — the `Sendable` enum naming how a byte stream is split into discrete messages: `.newlineDelimited` (a frame is the byte-exact slice up to and including its trailing `0x0A`), `.contentLength` (a frame is the body only, with its `Content-Length: <n>\r\n...\r\n\r\n` header consumed and discarded), and `.unframed` (a stream with no message boundaries at all, where a "frame" is whatever chunk of bytes arrived). Its `frame(_:)` method encodes a message for a given case.
- `MessageFramingDecoder` — the incremental, mutating `struct` that turns arbitrary byte chunks (never aligned to message boundaries) into complete frames, one call to `consume(_:)` at a time, and flushes any end-of-stream remainder via `finish()`. It caps any single buffered frame at 16 MiB and recovers from a peer that exceeds that cap without losing frames already completed in the same call or letting the rejected frame's own bytes resynchronize the stream.
- `SubprocessChannel` — the `actor` that spawns a child process (`Process`, three `Pipe`s) and exposes its stdout as an `AsyncThrowingStream` of frames decoded by a `MessageFramingDecoder`, its stdin as a place to `send(_:)`/`sendRaw(_:)` bytes, and its stderr as a continuously drained, capped buffer. It owns launch, environment policy, and a `terminate()` sequence (SIGTERM, then SIGKILL, then reader teardown) that distinguishes a child ending its own output from one this method killed.
- `SubprocessChannel.run(_:budget:)` and `withWallClockBudget(_:_:)` (`SubprocessChannel+Run.swift`, `WallClockBudget.swift`) — a one-shot helper that launches a channel, drains all of stdout as `.unframed` regardless of the caller's configured framing, and returns a `RunResult`; and the general wall-clock race it (and `PluginTransport`, see `related`) uses to bound any `async` operation, cancelling — never awaiting — the loser.

This is the one shared replacement, per `SubprocessChannel.swift`'s own doc comment, for what had been several independent `Process` + three-`Pipe` implementations in the codebase.

