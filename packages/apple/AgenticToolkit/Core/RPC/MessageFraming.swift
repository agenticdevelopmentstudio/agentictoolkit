import Foundation

/// How a byte stream is split into discrete messages.
///
/// The two cases deliberately differ in what a decoded frame *contains*:
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
public enum MessageFraming: Sendable {
    case newlineDelimited
    case contentLength

    /// Encodes `message` for this framing.
    ///
    /// - `.newlineDelimited` appends a single `0x0A`, unless `message`
    ///   already ends in one, in which case it is returned unchanged —
    ///   double-newlining a JSONL record would inject a spurious blank frame
    ///   into the peer's SSE parse.
    /// - `.contentLength` prepends `Content-Length: \(message.count)\r\n\r\n`
    ///   in ASCII.
    public func frame(_ message: Data) -> Data {
        switch self {
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
    /// complete header) growing the buffer without bound.
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

    public init(framing: MessageFraming) {
        self.framing = framing
    }

    /// Appends `chunk` to the internal buffer and returns every frame the
    /// buffer now completes, in order. Never returns a partial frame.
    public mutating func consume(_ chunk: Data) throws -> [Data] {
        if let violation = pendingCapViolation {
            pendingCapViolation = nil
            throw violation
        }
        buffer.append(chunk)
        switch framing {
        case .newlineDelimited:
            return try consumeNewlineDelimited()
        case .contentLength:
            return try consumeContentLength()
        }
    }

    /// The stream ended. Returns any trailing content the framing defines as
    /// a final frame, and empties the buffer.
    ///
    /// - `.newlineDelimited` returns the trailing unterminated remainder as
    ///   one final frame if the buffer is non-empty, and `[]` if it is empty.
    /// - `.contentLength` never returns a frame here: a non-empty buffer at
    ///   end-of-stream is a truncated message, not a frame, so this throws.
    public mutating func finish() throws -> [Data] {
        if let violation = pendingCapViolation {
            pendingCapViolation = nil
            throw violation
        }
        switch framing {
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
        if buffer.count > Self.maximumFrameBytes {
            let violation = MessageFramingError.frameSizeExceeded(limit: Self.maximumFrameBytes)
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
