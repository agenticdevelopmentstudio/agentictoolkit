import XCTest
@testable import AgenticToolkitCore

/// A cursor over a line-counting reader: each scan reads from the resume
/// point to the last newline and adds the lines it saw to a running count.
final class AppendOnlyFileCursorTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private final class Counter: @unchecked Sendable {
        var bytesRead: Int64 = 0
    }

    private func makeCursor(_ counter: Counter) -> AppendOnlyFileCursor<Int> {
        AppendOnlyFileCursor<Int>(
            capacity: 8,
            initial: 0,
            fingerprint: { url, upTo in
                let data = try Data(contentsOf: url).prefix(Int(upTo))
                return String(data.hashValue)
            },
            read: { url, from, lines in
                let data = try Data(contentsOf: url)
                let tail = data.dropFirst(Int(from))
                guard let lastNewline = tail.lastIndex(of: UInt8(ascii: "\n")) else { return from }
                let complete = data[tail.startIndex...lastNewline]
                counter.bytesRead += Int64(complete.count)
                lines += complete.filter { $0 == UInt8(ascii: "\n") }.count
                return Int64(lastNewline + 1)
            }
        )
    }

    func testReadsOnlyWhatWasAppendedSinceTheLastScan() throws {
        let file = directory.appendingPathComponent("log.jsonl")
        try Data("a\nb\n".utf8).write(to: file)
        let counter = Counter()
        let cursor = makeCursor(counter)

        XCTAssertEqual(cursor.scan(path: file.path), 2)
        XCTAssertEqual(cursor.resumeOffset(path: file.path), 4)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("c\nhalf".utf8))
        try handle.close()

        XCTAssertEqual(cursor.scan(path: file.path), 3)
        XCTAssertEqual(counter.bytesRead, 6, "the second scan read only the appended complete line")
        XCTAssertEqual(cursor.resumeOffset(path: file.path), 6, "a half-written line is read again whole")
    }

    /// A file rewritten in place keeps its inode; the fingerprint catches it.
    func testAFileRewrittenInPlaceIsScannedFromTheStart() throws {
        let file = directory.appendingPathComponent("log.jsonl")
        try Data("a\nb\n".utf8).write(to: file)
        let cursor = makeCursor(Counter())
        XCTAssertEqual(cursor.scan(path: file.path), 2)

        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data("x\ny\nz\n".utf8))
        try handle.close()

        XCTAssertEqual(cursor.scan(path: file.path), 3)
    }

    func testAMissingFileHasNoState() {
        let cursor = makeCursor(Counter())
        XCTAssertNil(cursor.scan(path: directory.appendingPathComponent("absent").path))
    }

    func testForgettingAPathStartsItAgain() throws {
        let file = directory.appendingPathComponent("log.jsonl")
        try Data("a\n".utf8).write(to: file)
        let cursor = makeCursor(Counter())
        _ = cursor.scan(path: file.path)
        cursor.forget(path: file.path)
        XCTAssertNil(cursor.resumeOffset(path: file.path))
        XCTAssertEqual(cursor.scan(path: file.path), 1)
    }
}
