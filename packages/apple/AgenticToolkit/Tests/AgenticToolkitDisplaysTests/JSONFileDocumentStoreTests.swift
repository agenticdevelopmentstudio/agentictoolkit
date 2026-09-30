import Foundation
import Testing
@testable import AgenticToolkitDisplays

@MainActor @Suite struct JSONFileDocumentStoreTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var url: URL { directory.appendingPathComponent("displays.json") }

    @Test func missingFileLoadsEmptyDocument() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(try JSONFileDocumentStore(url: url).load() == DisplayDocument())
    }

    @Test func saveCreatesDirectoryAndRoundTrips() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFileDocumentStore(url: url)
        var document = DisplayDocument()
        document.layouts = [LayoutCodingTests.deskLayout()]
        try store.save(document)
        #expect(try JSONFileDocumentStore(url: url).load() == document)
    }

    @Test func newerVersionIsRefusedAndNeverOverwritten() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let future = Data(#"{"version":99,"layouts":[],"futureField":true}"#.utf8)
        try future.write(to: url)
        let store = JSONFileDocumentStore(url: url)
        #expect(throws: DocumentStoreError.unsupportedVersion(found: 99, supported: 1)) { try store.load() }
        #expect(throws: DocumentStoreError.unsupportedVersion(found: 99, supported: 1)) {
            try store.save(DisplayDocument())
        }
        #expect(try Data(contentsOf: url) == future)
    }

    @Test func corruptFileThrowsCorrupt() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        #expect(throws: (any Error).self) { try JSONFileDocumentStore(url: url).load() }
        do { _ = try JSONFileDocumentStore(url: url).load() } catch let error as DocumentStoreError {
            guard case .corrupt = error else { Issue.record("expected corrupt, got \(error)"); return }
        }
    }

    @Test func watchFiresWhenAnotherProcessWrites() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFileDocumentStore(url: url)
        try store.save(DisplayDocument())
        var fired = 0
        let watch = try store.watch { fired += 1 }
        defer { watch.cancel() }
        var other = DisplayDocument()
        other.preferences.autoApplyEnabled = false
        try JSONFileDocumentStore(url: url).save(other)
        for _ in 0..<50 where fired == 0 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(fired > 0)
    }

    /// Releasing the token without `cancel()` runs its cancel action, which
    /// for the JSON store cancels the source and closes the descriptor (M2).
    @Test func releasingAWatchCancelsItOnce() {
        var cancels = 0
        var watch: DocumentWatch? = DocumentWatch { cancels += 1 }
        #expect(watch != nil)
        watch = nil
        #expect(cancels == 1)
        let cancelled = DocumentWatch { cancels += 1 }
        cancelled.cancel()
        #expect(cancels == 2)
    }

    /// The directory to watch cannot exist: its parent is a regular file.
    @Test func watchingAnUnopenableDirectoryThrows() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appendingPathComponent("file")
        try Data().write(to: blocker)
        let store = JSONFileDocumentStore(url: blocker.appendingPathComponent("sub/displays.json"))
        do {
            _ = try store.watch {}
            Issue.record("expected ioError")
        } catch let error as DocumentStoreError {
            guard case .ioError = error else { Issue.record("expected ioError, got \(error)"); return }
        }
    }

    @Test func resetCorruptBacksUpTheFileAndTheStoreLoadsEmpty() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: url)
        let store = JSONFileDocumentStore(url: url)
        #expect(throws: (any Error).self) { try LayoutService(system: FakeDisplaySystem.desk(), store: store) }
        let backup = try #require(try store.resetCorrupt())
        #expect(backup.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
        #expect(backup.lastPathComponent.hasPrefix("displays.corrupt-"))
        #expect(backup.pathExtension == "json")
        #expect(try Data(contentsOf: backup) == corrupt)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try store.load() == DisplayDocument())
        #expect(try LayoutService(system: FakeDisplaySystem.desk(), store: store).layouts.isEmpty)
    }

    @Test func resetCorruptLeavesAbsentValidAndNewerFilesAlone() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFileDocumentStore(url: url)
        #expect(try store.resetCorrupt() == nil)
        try store.save(DisplayDocument())
        #expect(try store.resetCorrupt() == nil)
        let future = Data(#"{"version":99}"#.utf8)
        try future.write(to: url)
        #expect(throws: DocumentStoreError.unsupportedVersion(found: 99, supported: 1)) { try store.resetCorrupt() }
        #expect(try Data(contentsOf: url) == future)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["displays.json"])
    }
}
