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
/// never throws — every case here originates from `.contentLength` parsing
/// or from the shared unbounded-buffer guard.
public enum MessageFramingError: Error, LocalizedError, Equatable {
    case malformedHeader(String)
    case missingContentLength
    case truncatedMessage(expected: Int, received: Int)

    public var errorDescription: String? {
        switch self {
        case .malformedHeader(let reason):
            return "Malformed frame header: \(reason)"
        case .missingContentLength:
            return "Frame header is missing a Content-Length field."
        case .truncatedMessage(let expected, let received):
            return "Truncated message: expected \(expected) body bytes, received \(received)."
        }
    }
}

/// Incrementally turns a byte stream into discrete messages.
///
/// Fed arbitrary chunks of bytes — never aligned to message boundaries —
/// `consume(_:)` returns every frame the buffer now completes, in order,
/// and never returns a partial frame.
public struct MessageFramingDecoder {

    /// The largest buffer this decoder will accumulate before a frame
    /// completes. Guards against a peer that never sends a delimiter (or a
    /// complete header) growing the buffer without bound.
    public static let maximumFrameBytes = 16 * 1024 * 1024

    private static let headerTerminator = Data([0x0D, 0x0A, 0x0D, 0x0A])
    private static let lineSeparator = Data([0x0D, 0x0A])

    private let framing: MessageFraming
    private var buffer = Data()

    public init(framing: MessageFraming) {
        self.framing = framing
    }

    /// Appends `chunk` to the internal buffer and returns every frame the
    /// buffer now completes, in order. Never returns a partial frame.
    public mutating func consume(_ chunk: Data) throws -> [Data] {
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
        switch framing {
        case .newlineDelimited:
            guard !buffer.isEmpty else { return [] }
            let remainder = buffer
            buffer.removeAll()
            return [remainder]

        case .contentLength:
            guard !buffer.isEmpty else { return [] }
            defer { buffer.removeAll() }
            guard let headerRange = buffer.firstRange(of: Self.headerTerminator) else {
                // The stream ended before a complete header ever arrived —
                // there is no declared length to report a shortfall against,
                // so this is a malformed (incomplete) header rather than a
                // truncated body.
                throw MessageFramingError.malformedHeader(
                    "stream ended before the header was complete"
                )
            }
            let headerData = Data(buffer[buffer.startIndex..<headerRange.lowerBound])
            let expected = try parseContentLength(from: headerData)
            let received = buffer.distance(from: headerRange.upperBound, to: buffer.endIndex)
            throw MessageFramingError.truncatedMessage(expected: expected, received: received)
        }
    }

    // MARK: - Newline-delimited

    private mutating func consumeNewlineDelimited() throws -> [Data] {
        var frames: [Data] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let frameEnd = buffer.index(after: newlineIndex)
            frames.append(Data(buffer[buffer.startIndex..<frameEnd]))
            buffer.removeSubrange(buffer.startIndex..<frameEnd)
        }
        if buffer.count > Self.maximumFrameBytes {
            throw MessageFramingError.malformedHeader(
                "frame exceeds \(Self.maximumFrameBytes) bytes"
            )
        }
        return frames
    }

    // MARK: - Content-Length

    private mutating func consumeContentLength() throws -> [Data] {
        var frames: [Data] = []
        while true {
            guard let headerRange = buffer.firstRange(of: Self.headerTerminator) else {
                if buffer.count > Self.maximumFrameBytes {
                    throw MessageFramingError.malformedHeader(
                        "frame exceeds \(Self.maximumFrameBytes) bytes"
                    )
                }
                return frames
            }

            let headerData = Data(buffer[buffer.startIndex..<headerRange.lowerBound])
            let bodyLength = try parseContentLength(from: headerData)
            if bodyLength > Self.maximumFrameBytes {
                throw MessageFramingError.malformedHeader(
                    "frame exceeds \(Self.maximumFrameBytes) bytes"
                )
            }

            let bodyStart = headerRange.upperBound
            guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= bodyLength else {
                // Body has not fully arrived yet.
                return frames
            }
            let bodyEnd = buffer.index(bodyStart, offsetBy: bodyLength)
            frames.append(Data(buffer[bodyStart..<bodyEnd]))
            buffer.removeSubrange(buffer.startIndex..<bodyEnd)
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
