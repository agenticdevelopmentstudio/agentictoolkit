import Foundation

/// How a byte stream is split into discrete messages.
///
/// The cases deliberately differ in what a decoded frame *contains*:
///
/// - `.newlineDelimited` treats the newline as a delimiter *within* the
///   stream: a decoded frame is the byte-exact slice up to and including its
///   trailing `0x0A`. Callers that parse line-oriented wire formats (SSE,
///   JSONL) are entitled to see that byte — an SSE parser uses a blank line
///   as its event boundary, and stripping the newline would silently destroy
///   line breaks the caller's own decoder depends on.
/// - `.contentLength` treats its `Content-Length: <n>\r\n...\r\n\r\n` header
///   as a wrapper *around* the payload, not part of it: a decoded frame is
///   the body only, with the header consumed and discarded.
/// - `.unframed` declares that the stream has no message boundaries at all.
///   There is no delimiter to look for, so a "frame" is simply whatever
///   chunk of bytes arrived, handed straight on.
public enum MessageFraming: Sendable {
    case newlineDelimited
    case contentLength
    /// A byte stream that carries no messages — the child's output *is* the
    /// payload, and the only thing to do with it is read all of it.
    ///
    /// This is the framing for a one-shot capture (`SubprocessChannel.run`),
    /// and choosing it is not a detail: the other two cases buffer until a
    /// boundary arrives and refuse a frame that grows past
    /// `MessageFramingDecoder.maximumFrameBytes`, which is the right guard
    /// against a peer that never sends a delimiter and exactly the wrong one
    /// against a child whose whole output legitimately contains no delimiter.
    /// git's machine-readable status (`GitVerb.status`) is that child: its
    /// records are NUL-terminated and carry no `0x0A` anywhere, so a large
    /// repository's status is one 16 MB-plus "frame" and a guard meant for a
    /// malformed peer throws away a correct answer. Nothing accumulates
    /// here, so nothing needs capping.
    case unframed

    /// Encodes `message` for this framing.
    ///
    /// - `.newlineDelimited` appends a single `0x0A`, unless `message`
    ///   already ends in one, in which case it is returned unchanged —
    ///   double-newlining a JSONL record would inject a spurious blank frame
    ///   into the peer's SSE parse.
    /// - `.contentLength` prepends `Content-Length: \(message.count)\r\n\r\n`
    ///   in ASCII.
    /// - `.unframed` returns `message` unchanged: there is no envelope to add.
    public func frame(_ message: Data) -> Data {
        switch self {
        case .unframed:
            return message

        case .newlineDelimited:
            if message.last == 0x0A {
                return message
            }
            var framed = message
            framed.append(0x0A)
            return framed

        case .contentLength:
            var framed = Data("Content-Length: \(message.count)\r\n\r\n".utf8)
            framed.append(message)
            return framed
        }
    }
}

/// Errors thrown while decoding a framed byte stream. `.newlineDelimited`
/// only ever throws the unbounded-buffer guard; every other case here
/// originates from `.contentLength` parsing.
public enum MessageFramingError: Error, LocalizedError, Equatable {
    case malformedHeader(String)
    case missingContentLength
    case truncatedMessage(expected: Int, received: Int)
    case frameSizeExceeded(limit: Int)

    public var errorDescription: String? {
        switch self {
        case .malformedHeader(let reason):
            return "Malformed frame header: \(reason)"
        case .missingContentLength:
            return "Frame header is missing a Content-Length field."
        case .truncatedMessage(let expected, let received):
            return "Truncated message: expected \(expected) body bytes, received \(received)."
        case .frameSizeExceeded(let limit):
            return "Frame exceeds the \(limit)-byte cap."
        }
    }
}

/// Incrementally turns a byte stream into discrete messages.
///
/// Fed arbitrary chunks of bytes — never aligned to message boundaries —
/// `consume(_:)` returns every frame the buffer now completes, in order,
/// and never returns a partial frame.
///
/// Every byte handed to this type is examined at most once, whether it
/// arrives as one chunk or is split across many `consume(_:)` calls. A
/// newline search resumes from a cursor rather than rescanning the buffer's
/// unconsumed tail from the start, and a `Content-Length` header is parsed
/// exactly once — the moment its terminator is seen — never re-parsed while
/// the body is still arriving. Feeding this decoder one byte at a time
/// defeats none of that, but it does turn every `consume(_:)` call into
/// mostly-wasted overhead; callers should feed it real chunks (see
/// `SubprocessChannel`'s pump, which reads with `read(upToCount:)` rather
/// than iterating `FileHandle.bytes` one byte at a time).
public struct MessageFramingDecoder {

    /// The largest buffer this decoder will accumulate before a frame
    /// completes. Guards against a peer that never sends a delimiter (or a
    /// complete header) growing the buffer without bound. `.unframed` never
    /// reaches it: with no boundary to wait for, it accumulates nothing.
    public static let maximumFrameBytes = 16 * 1024 * 1024

    private static let headerTerminator = Data([0x0D, 0x0A, 0x0D, 0x0A])
    private static let lineSeparator = Data([0x0D, 0x0A])

    private let framing: MessageFraming
    private var buffer = Data()

    /// Newline framing only: how many leading bytes of `buffer` have already
    /// been scanned for `0x0A` with no match. When completed frames are cut
    /// off the front of `buffer`, this is *shifted* by the number of bytes
    /// removed (`scanCursor -= consumedThrough`), not reset — the bytes that
    /// remain behind a frame have already been looked at, and rescanning them
    /// is exactly the O(n²) behaviour this cursor exists to prevent (114
    /// seconds to decode a single 256 KB line, measured). Do not "simplify"
    /// this to `scanCursor = 0`.
    private var scanCursor = 0

    /// Content-Length framing only: the body length declared by the header
    /// already consumed from the front of `buffer`, once a header has been
    /// seen and stripped. `nil` means `buffer` currently starts with an
    /// unparsed (possibly incomplete) header rather than pending body bytes.
    /// Caching this is what makes the header parse-once rather than
    /// re-running on every call while a large body trickles in.
    private var pendingBodyLength: Int?

    /// A cap violation detected while a call also had complete frames ready
    /// to return. `consume(_:)` and `finish()` return those frames first and
    /// throw this on the very next opportunity, so a chunk holding several
    /// good frames followed by the start of an oversized one does not lose
    /// the good frames to the same throw that reports the bad one.
    private var pendingCapViolation: MessageFramingError?

    /// Content-Length framing only: how many bytes of an over-cap body are
    /// still to be thrown away before the next header is looked for.
    ///
    /// **This is what keeps a rejected frame from becoming protocol.** The
    /// header of an over-cap frame is consumed and its declared length is
    /// known, so the body's extent is known too; without recording it, those
    /// peer-controlled bytes stay in the buffer and the next header scan runs
    /// *over the body*, letting a body that contains a `Content-Length:` line
    /// resynchronise the stream onto boundaries the peer chose. Reporting the
    /// violation is not enough on its own: the decoder is a value the caller
    /// still holds, and `consume(_:)` after a throw must be safe by
    /// construction rather than by the caller's good manners.
    private var pendingDiscardLength = 0

    /// Newline framing only: the same idea where there is no declared length.
    /// An over-cap line's extent is "until the next `0x0A`", so this drops
    /// bytes until one arrives, and the oversized line is never delivered as
    /// a frame. It also bounds the buffer, which the previous behaviour —
    /// keep accumulating and re-throw — did not.
    private var isDiscardingToDelimiter = false

    public init(framing: MessageFraming) {
        self.framing = framing
    }

    /// Appends `chunk` to the internal buffer and returns every frame the
    /// buffer now completes, in order. Never returns a partial frame.
    ///
    /// **The chunk is taken before a deferred violation is thrown**, and the
    /// order matters. Throwing first would silently drop a whole chunk of the
    /// stream, and the byte accounting that skips a rejected frame's body
    /// (`pendingDiscardLength`) would then come up short by exactly that many
    /// bytes — the discard would run off the end of the bad frame and eat the
    /// front of the next good one, which is the desync this decoder is meant
    /// to make impossible.
    public mutating func consume(_ chunk: Data) throws -> [Data] {
        // Nothing to look for and nothing to wait for: an unframed stream's
        // bytes are complete the moment they arrive, so they are handed on
        // without ever entering `buffer`. That is also why the cap below does
        // not apply — a decoder that buffers nothing cannot grow.
        if case .unframed = framing {
            return chunk.isEmpty ? [] : [chunk]
        }
        buffer.append(chunk)
        if let violation = pendingCapViolation {
            pendingCapViolation = nil
            throw violation
        }
        switch framing {
        case .newlineDelimited:
            return try consumeNewlineDelimited()
        case .contentLength:
            return try consumeContentLength()
        case .unframed:
            // Answered above. Spelled out rather than folded into a `default`,
            // so a case added to `MessageFraming` later fails to compile here
            // instead of silently decoding as nothing.
            return []
        }
    }

    /// The stream ended. Returns any trailing content the framing defines as
    /// a final frame, and empties the buffer.
    ///
    /// - `.newlineDelimited` returns the trailing unterminated remainder as
    ///   one final frame if the buffer is non-empty, and `[]` if it is empty.
    /// - `.contentLength` never returns a frame here: a non-empty buffer at
    ///   end-of-stream is a truncated message, not a frame, so this throws.
    /// - `.unframed` has nothing held back to return: every chunk was a
    ///   complete frame when it arrived. A stream that simply ends is how an
    ///   unframed stream ends, so this neither returns a frame nor throws.
    public mutating func finish() throws -> [Data] {
        if let violation = pendingCapViolation {
            pendingCapViolation = nil
            throw violation
        }
        // Whatever is still buffered while a rejected frame is being skipped
        // belongs to that frame, not to a final one. Dropping it here is what
        // keeps `finish()` from handing back half of an over-cap line as a
        // frame, or reporting its unarrived body as a truncated message.
        if isDiscardingToDelimiter || pendingDiscardLength > 0 {
            isDiscardingToDelimiter = false
            pendingDiscardLength = 0
            buffer.removeAll()
            scanCursor = 0
            pendingBodyLength = nil
            return []
        }

        switch framing {
        case .unframed:
            return []

        case .newlineDelimited:
            guard !buffer.isEmpty else { return [] }
            let remainder = buffer
            buffer.removeAll()
            scanCursor = 0
            return [remainder]

        case .contentLength:
            guard !buffer.isEmpty || pendingBodyLength != nil else { return [] }
            defer {
                buffer.removeAll()
                pendingBodyLength = nil
            }
            if let expected = pendingBodyLength {
                // The header was already parsed and stripped, so whatever is
                // left in `buffer` is exactly the body bytes that arrived.
                throw MessageFramingError.truncatedMessage(expected: expected, received: buffer.count)
            }
            // The stream ended before a complete header ever arrived —
            // there is no declared length to report a shortfall against,
            // so this is a malformed (incomplete) header rather than a
            // truncated body.
            throw MessageFramingError.malformedHeader(
                "stream ended before the header was complete"
            )
        }
    }

    // MARK: - Newline-delimited

    private mutating func consumeNewlineDelimited() throws -> [Data] {
        var frames: [Data] = []
        var consumedThrough = 0

        if isDiscardingToDelimiter {
            guard let newlineIndex = buffer.firstIndex(of: 0x0A) else {
                // Every byte held is part of the rejected line. Drop them
                // rather than accumulate: none of them will ever be a frame.
                buffer.removeAll()
                scanCursor = 0
                return frames
            }
            let resumeFrom = buffer.index(after: newlineIndex)
            buffer.removeSubrange(buffer.startIndex..<resumeFrom)
            scanCursor = 0
            isDiscardingToDelimiter = false
        }

        while true {
            let searchStart = buffer.index(buffer.startIndex, offsetBy: max(scanCursor, consumedThrough))
            guard let newlineIndex = buffer[searchStart...].firstIndex(of: 0x0A) else {
                scanCursor = buffer.count
                break
            }
            let frameEndOffset = buffer.distance(from: buffer.startIndex, to: newlineIndex) + 1
            let frameStart = buffer.index(buffer.startIndex, offsetBy: consumedThrough)
            let frameEnd = buffer.index(buffer.startIndex, offsetBy: frameEndOffset)
            frames.append(Data(buffer[frameStart..<frameEnd]))
            consumedThrough = frameEndOffset
            scanCursor = frameEndOffset
        }

        if consumedThrough > 0 {
            let cut = buffer.index(buffer.startIndex, offsetBy: consumedThrough)
            buffer.removeSubrange(buffer.startIndex..<cut)
            scanCursor -= consumedThrough
        }

        // A chunk holding several complete frames followed by the start of an
        // oversized, still-unterminated one should not lose the complete
        // frames to the same throw that reports the overflow — return them
        // now and report the violation the next time this decoder is asked
        // for more (see `pendingCapViolation`).
        //
        // The rejected line is *dropped*, not kept: it is over the cap and so
        // will never be handed back as a frame, and holding it would let the
        // buffer grow without bound while a peer that never sends a delimiter
        // keeps writing. Everything up to the next `0x0A` belongs to it.
        if buffer.count > Self.maximumFrameBytes {
            let violation = MessageFramingError.frameSizeExceeded(limit: Self.maximumFrameBytes)
            isDiscardingToDelimiter = true
            buffer.removeAll()
            scanCursor = 0
            if frames.isEmpty {
                throw violation
            }
            pendingCapViolation = violation
        }
        return frames
    }

    // MARK: - Content-Length

    private mutating func consumeContentLength() throws -> [Data] {
        var frames: [Data] = []

        while true {
            if pendingDiscardLength > 0 {
                // Bytes belonging to a frame already rejected for exceeding
                // the cap. They are dropped before anything else looks at the
                // buffer, so no header scan ever runs over a rejected body.
                let dropped = min(pendingDiscardLength, buffer.count)
                let cut = buffer.index(buffer.startIndex, offsetBy: dropped)
                buffer.removeSubrange(buffer.startIndex..<cut)
                pendingDiscardLength -= dropped
                if pendingDiscardLength > 0 {
                    // The rest of the rejected body has not arrived yet.
                    return frames
                }
            }

            if pendingBodyLength == nil {
                guard let headerRange = buffer.firstRange(of: Self.headerTerminator) else {
                    if buffer.count > Self.maximumFrameBytes {
                        let violation = MessageFramingError.frameSizeExceeded(limit: Self.maximumFrameBytes)
                        if frames.isEmpty {
                            throw violation
                        }
                        pendingCapViolation = violation
                    }
                    return frames
                }

                let headerData = Data(buffer[buffer.startIndex..<headerRange.lowerBound])
                let bodyLength = try parseContentLength(from: headerData)
                // The header itself is consumed here, once, regardless of
                // how much of the body has arrived — nothing re-parses it.
                buffer.removeSubrange(buffer.startIndex..<headerRange.upperBound)

                if bodyLength > Self.maximumFrameBytes {
                    let violation = MessageFramingError.frameSizeExceeded(limit: Self.maximumFrameBytes)
                    // The header has just been consumed, so the body's extent
                    // is known exactly: record it as bytes to throw away.
                    // Without this the body would stay in the buffer and the
                    // next header scan would run over peer-controlled bytes —
                    // a `Content-Length:` line *inside* the rejected body
                    // would then set the stream's next frame boundary.
                    pendingDiscardLength = bodyLength
                    if frames.isEmpty {
                        throw violation
                    }
                    pendingCapViolation = violation
                    return frames
                }
                pendingBodyLength = bodyLength
            }

            guard let bodyLength = pendingBodyLength else {
                // Unreachable: the branch above always sets this before
                // falling through, except when it already returned.
                return frames
            }
            guard buffer.count >= bodyLength else {
                // Body has not fully arrived yet; nothing left to parse.
                return frames
            }
            let bodyEnd = buffer.index(buffer.startIndex, offsetBy: bodyLength)
            frames.append(Data(buffer[buffer.startIndex..<bodyEnd]))
            buffer.removeSubrange(buffer.startIndex..<bodyEnd)
            pendingBodyLength = nil
        }
    }

    private func headerLines(from headerData: Data) -> [Data] {
        var lines: [Data] = []
        var remaining = headerData[...]
        while let range = remaining.firstRange(of: Self.lineSeparator) {
            lines.append(Data(remaining[remaining.startIndex..<range.lowerBound]))
            remaining = remaining[range.upperBound...]
        }
        if !remaining.isEmpty {
            lines.append(Data(remaining))
        }
        return lines
    }

    private func parseContentLength(from headerData: Data) throws -> Int {
        var contentLength: Int?
        for line in headerLines(from: headerData) {
            guard let text = String(data: line, encoding: .utf8) else {
                throw MessageFramingError.malformedHeader("header line is not valid UTF-8")
            }
            guard let colonIndex = text.firstIndex(of: ":") else {
                throw MessageFramingError.malformedHeader(
                    "header line \"\(text)\" has no ':' separator"
                )
            }
            let key = text[text.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
            let value = text[text.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            if key.caseInsensitiveCompare("Content-Length") == .orderedSame {
                guard let parsed = Int(value), parsed >= 0 else {
                    throw MessageFramingError.malformedHeader(
                        "Content-Length value \"\(value)\" is not a non-negative integer"
                    )
                }
                contentLength = parsed
            }
            // Other headers (Content-Type, etc.) are tolerated and discarded.
        }
        guard let contentLength else {
            throw MessageFramingError.missingContentLength
        }
        return contentLength
    }
}
