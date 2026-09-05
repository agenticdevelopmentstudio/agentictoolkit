import Foundation
import Testing
@testable import AgenticToolkitCore

@Suite("MessageFraming")
struct MessageFramingTests {

    // MARK: - Newline-delimited decoding

    @Test("a chunk holding three complete lines yields three frames, each ending in \\n")
    func newlineThreeCompleteLinesYieldThreeFrames() throws {
        var decoder = MessageFramingDecoder(framing: .newlineDelimited)
        let frames = try decoder.consume(Data("alpha\nbeta\ngamma\n".utf8))
        #expect(frames == [
            Data("alpha\n".utf8),
            Data("beta\n".utf8),
            Data("gamma\n".utf8)
        ])
    }

    @Test("a message split across three chunks mid-word yields exactly one frame once the newline arrives")
    func newlineMessageSplitAcrossThreeChunks() throws {
        var decoder = MessageFramingDecoder(framing: .newlineDelimited)
        var frames: [Data] = []
        frames += try decoder.consume(Data("hel".utf8))
        frames += try decoder.consume(Data("lo wor".utf8))
        #expect(frames.isEmpty)
        frames += try decoder.consume(Data("ld\n".utf8))
        #expect(frames == [Data("hello world\n".utf8)])
    }

    @Test("a lone newline yields one one-byte frame (the SSE blank-line case)")
    func newlineLoneNewlineYieldsOneByteFrame() throws {
        var decoder = MessageFramingDecoder(framing: .newlineDelimited)
        let frames = try decoder.consume(Data([0x0A]))
        #expect(frames == [Data([0x0A])])
    }

    @Test("finish() emits the unterminated remainder; a second finish() emits nothing")
    func newlineFinishEmitsRemainderOnce() throws {
        var decoder = MessageFramingDecoder(framing: .newlineDelimited)
        _ = try decoder.consume(Data("no newline yet".utf8))
        let firstFinish = try decoder.finish()
        #expect(firstFinish == [Data("no newline yet".utf8)])
        let secondFinish = try decoder.finish()
        #expect(secondFinish.isEmpty)
    }

    @Test("CRLF content survives byte-exactly — the frame ends \\r\\n, and the \\r is not stripped")
    func newlineCRLFContentSurvivesByteExactly() throws {
        var decoder = MessageFramingDecoder(framing: .newlineDelimited)
        let frames = try decoder.consume(Data("hello\r\n".utf8))
        #expect(frames == [Data("hello\r\n".utf8)])
    }

    @Test("multi-byte UTF-8 split across a chunk boundary mid-scalar reassembles intact")
    func newlineMultiByteUTF8SplitMidScalarReassemblesIntact() throws {
        var decoder = MessageFramingDecoder(framing: .newlineDelimited)
        let full = Data("celebration \u{1F389}\n".utf8)
        // Split inside the 4-byte UTF-8 encoding of the emoji scalar, not on a
        // scalar boundary — frame boundaries are bytes, not characters.
        let splitPoint = full.count - 2
        let firstChunk = full[full.startIndex..<full.index(full.startIndex, offsetBy: splitPoint)]
        let secondChunk = full[full.index(full.startIndex, offsetBy: splitPoint)...]

        var frames = try decoder.consume(Data(firstChunk))
        #expect(frames.isEmpty)
        frames += try decoder.consume(Data(secondChunk))
        #expect(frames == [full])
    }

    // MARK: - Content-Length decoding

    @Test("a well-formed message decodes to the body with no header bytes")
    func contentLengthWellFormedMessageDecodesToBodyOnly() throws {
        var decoder = MessageFramingDecoder(framing: .contentLength)
        let body = Data("hello".utf8)
        let framed = Data("Content-Length: 5\r\n\r\n".utf8) + body
        let frames = try decoder.consume(framed)
        #expect(frames == [body])
    }

    @Test("two messages in one chunk yield two frames")
    func contentLengthTwoMessagesInOneChunkYieldTwoFrames() throws {
        var decoder = MessageFramingDecoder(framing: .contentLength)
        let firstBody = Data("abc".utf8)
        let secondBody = Data("de".utf8)
        let framed = Data("Content-Length: 3\r\n\r\n".utf8) + firstBody
            + Data("Content-Length: 2\r\n\r\n".utf8) + secondBody
        let frames = try decoder.consume(framed)
        #expect(frames == [firstBody, secondBody])
    }

    @Test("a body split across chunks yields one frame when complete")
    func contentLengthBodySplitAcrossChunksYieldsOneFrameWhenComplete() throws {
        var decoder = MessageFramingDecoder(framing: .contentLength)
        let header = Data("Content-Length: 5\r\n\r\n".utf8)
        var frames = try decoder.consume(header + Data("he".utf8))
        #expect(frames.isEmpty)
        frames += try decoder.consume(Data("llo".utf8))
        #expect(frames == [Data("hello".utf8)])
    }

    @Test("extra headers in either order still parse", arguments: [
        "Content-Type: application/json\r\nContent-Length: 2\r\n\r\nhi",
        "Content-Length: 2\r\nContent-Type: application/json\r\n\r\nhi"
    ])
    func contentLengthExtraHeadersInEitherOrderStillParse(rawMessage: String) throws {
        var decoder = MessageFramingDecoder(framing: .contentLength)
        let frames = try decoder.consume(Data(rawMessage.utf8))
        #expect(frames == [Data("hi".utf8)])
    }

    @Test("Content-Length counts bytes, not characters")
    func contentLengthCountsBytesNotCharacters() throws {
        var decoder = MessageFramingDecoder(framing: .contentLength)
        let body = Data("héllo 🎉".utf8)
        #expect(body.count > "héllo 🎉".count)
        let framed = Data("Content-Length: \(body.count)\r\n\r\n".utf8) + body
        let frames = try decoder.consume(framed)
        #expect(frames == [body])
    }

    @Test("finish() with a partial body throws truncatedMessage(expected:received:)")
    func contentLengthFinishWithPartialBodyThrowsTruncatedMessage() throws {
        var decoder = MessageFramingDecoder(framing: .contentLength)
        _ = try decoder.consume(Data("Content-Length: 5\r\n\r\nhe".utf8))
        #expect(throws: MessageFramingError.truncatedMessage(expected: 5, received: 2)) {
            try decoder.finish()
        }
    }

    @Test("a header with no Content-Length throws missingContentLength")
    func contentLengthHeaderWithNoContentLengthThrowsMissingContentLength() throws {
        var decoder = MessageFramingDecoder(framing: .contentLength)
        #expect(throws: MessageFramingError.missingContentLength) {
            try decoder.consume(Data("Content-Type: application/json\r\n\r\nhi".utf8))
        }
    }

    // MARK: - Encoding and round trips

    @Test("frame(_:) output fed back through the decoder round-trips to the original message plus its newline",
          arguments: [MessageFraming.newlineDelimited])
    func newlineFrameRoundTripsWithNewline(framing: MessageFraming) throws {
        let message = Data("round trip".utf8)
        var decoder = MessageFramingDecoder(framing: framing)
        let frames = try decoder.consume(framing.frame(message))
        #expect(frames == [message + Data([0x0A])])
    }

    @Test("frame(_:) output fed back through the decoder round-trips to the original message",
          arguments: [MessageFraming.contentLength])
    func contentLengthFrameRoundTrips(framing: MessageFraming) throws {
        let message = Data("round trip".utf8)
        var decoder = MessageFramingDecoder(framing: framing)
        let frames = try decoder.consume(framing.frame(message))
        #expect(frames == [message])
    }

    @Test("frame(_:) on a message already ending in \\n appends nothing")
    func newlineFrameOnMessageAlreadyEndingInNewlineAppendsNothing() {
        let message = Data("already terminated\n".utf8)
        #expect(MessageFraming.newlineDelimited.frame(message) == message)
    }

    // MARK: - Unbounded-buffer guard

    @Test("exceeding maximumFrameBytes throws rather than buffering, for newline framing")
    func newlineExceedingMaximumFrameBytesThrows() {
        var decoder = MessageFramingDecoder(framing: .newlineDelimited)
        let oversized = Data(repeating: 0x41, count: MessageFramingDecoder.maximumFrameBytes + 1)
        #expect(throws: MessageFramingError.self) {
            try decoder.consume(oversized)
        }
    }

    @Test("a declared Content-Length above the cap throws before any body is buffered")
    func contentLengthExceedingMaximumFrameBytesThrows() {
        var decoder = MessageFramingDecoder(framing: .contentLength)
        let oversizedHeader = Data(
            "Content-Length: \(MessageFramingDecoder.maximumFrameBytes + 1)\r\n\r\n".utf8
        )
        #expect(throws: MessageFramingError.self) {
            try decoder.consume(oversizedHeader)
        }
    }
}
