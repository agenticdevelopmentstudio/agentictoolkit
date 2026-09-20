import Foundation
import Testing
@testable import AgenticToolkitCore

/// The cheap answer to "is this the same file it was?".
///
/// Two places had rebuilt it privately — the extension host, deciding whether
/// an entry point moved, and the open-document reloader, deciding whether a
/// watcher event was worth reading a whole file for. This is the one of them.
@Suite("FileSignature")
struct FileSignatureTests {

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("signature-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("a file that has not been touched signs the same twice")
    func anUntouchedFileIsUnchanged() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Steady.txt")
        try "contents".write(to: file, atomically: true, encoding: .utf8)

        let first = try #require(FileSignature(of: file))
        let second = try #require(FileSignature(of: file))
        #expect(first == second)
        #expect(first.size == 8)
    }

    @Test("a rewrite changes the signature")
    func aRewriteIsNoticed() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Rewritten.txt")
        try "contents".write(to: file, atomically: true, encoding: .utf8)
        let before = try #require(FileSignature(of: file))

        try "other contents entirely".write(to: file, atomically: true, encoding: .utf8)
        let after = try #require(FileSignature(of: file))
        #expect(before != after)
    }

    /// What it does not catch, plainly: a rewrite that lands on the same byte
    /// count *and* the same modification date. On APFS that date has
    /// nanosecond resolution, so it takes deliberate effort — which is exactly
    /// what this does, to state the limit rather than imply there isn't one.
    ///
    /// The date is pinned to a whole second because `Date` is a `Double` of
    /// seconds and a present-day instant has about 100 ns of room left in the
    /// mantissa: reading a live modification date and writing it back moves it
    /// by a hair, which would make this test pass for the wrong reason.
    @Test("same length and same date is indistinguishable, by design")
    func anIdenticallyStampedRewriteIsMissed() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Forged.txt")
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)

        try "contents".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: pinned], ofItemAtPath: file.path)
        let before = try #require(FileSignature(of: file))

        try "CONTENTS".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: pinned], ofItemAtPath: file.path)

        #expect(FileSignature(of: file) == before)
    }

    /// `nil` rather than a throw: every caller treats "cannot stat it" as
    /// "I have nothing to compare", and none of them has anything to do with
    /// *why*.
    @Test("a file that is not there has no signature")
    func anAbsentFileHasNone() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(FileSignature(of: directory.appendingPathComponent("Gone.txt")) == nil)
    }
}
