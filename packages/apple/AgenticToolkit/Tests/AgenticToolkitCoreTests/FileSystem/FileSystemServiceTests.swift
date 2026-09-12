import Foundation
import Testing
@testable import AgenticToolkitCore

/// The seven operations, their flags, and the bitmask `stat` answers.
///
/// Every assertion here is chosen so it fails when the behaviour is absent
/// rather than passing on a default. The flag tests come in pairs — the
/// refusal and the permission — because a refusal test alone would still pass
/// against an implementation that refused everything, and a success test alone
/// would still pass against one that ignored the flag. The symbolic-link tests
/// check the raw bitmask, not `contains`, because `contains` on an option set
/// cannot tell 66 from 2.
@Suite
struct FileSystemServiceTests {

    // MARK: - Fixtures

    /// A fresh directory under the system temp directory. Private to this
    /// file: every other suite in this package rolls its own, and promoting a
    /// shared one is a decision for all of them, not for this test file.
    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileSystemServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Runs `body`, expecting a `FileSystemServiceError`, and hands it back.
    /// Records an issue and answers `nil` when nothing was thrown — which is
    /// the polarity that matters, because a helper that stayed silent there
    /// would turn every failure test into a test that cannot fail.
    private func expectingFileSystemError(
        _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ body: () async throws -> Void
    ) async -> FileSystemServiceError? {
        do {
            try await body()
            Issue.record("\(label) did not throw", sourceLocation: sourceLocation)
            return nil
        } catch let error as FileSystemServiceError {
            return error
        } catch {
            Issue.record(
                "\(label) threw \(error), not a FileSystemServiceError",
                sourceLocation: sourceLocation
            )
            return nil
        }
    }

    // MARK: - Happy paths

    @Test("readFile answers exactly the bytes on disk")
    func readFileAnswersTheBytesOnDisk() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = Data("the bytes that were written\u{0}and a NUL".utf8)
        let file = directory.appendingPathComponent("payload.bin")
        try payload.write(to: file)

        let read = try await FileSystemService().readFile(atPath: file.path)

        #expect(read == payload)
    }

    @Test("writeFile puts exactly the given bytes on disk")
    func writeFileWritesTheGivenBytes() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("written.bin")
        let payload = Data("written through the service".utf8)

        try await FileSystemService().writeFile(
            atPath: file.path,
            contents: payload,
            create: true,
            overwrite: true
        )

        let onDisk = try Data(contentsOf: file)
        #expect(onDisk == payload)
    }

    @Test("readDirectory answers every child with its own type")
    func readDirectoryAnswersEveryChildWithItsType() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = FileManager.default
        let child = directory.appendingPathComponent("child.txt")
        try Data("child".utf8).write(to: child)
        try manager.createDirectory(
            at: directory.appendingPathComponent("nested"),
            withIntermediateDirectories: true
        )
        try manager.createSymbolicLink(
            atPath: directory.appendingPathComponent("link").path,
            withDestinationPath: child.path
        )

        let entries = try await FileSystemService().readDirectory(atPath: directory.path)
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0.type.rawValue) })

        #expect(entries.count == 3)
        #expect(byName["child.txt"] == 1)
        #expect(byName["nested"] == 2)
        #expect(byName["link"] == 65)
    }

    @Test("stat answers a file's type, size and modification time")
    func statAnswersAFilesTypeSizeAndTime() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("sized.bin")
        let payload = Data(repeating: 7, count: 1024)
        try payload.write(to: file)

        let stat = try await FileSystemService().stat(atPath: file.path)

        #expect(stat.type == .file)
        #expect(stat.size == payload.count)
        #expect(stat.modificationDate != nil)
        #expect(stat.creationDate != nil)
    }

    @Test("delete removes the file")
    func deleteRemovesTheFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("doomed.txt")
        try Data("doomed".utf8).write(to: file)

        try await FileSystemService().delete(atPath: file.path, recursive: false, useTrash: false)

        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("rename moves the item and its contents, leaving nothing behind")
    func renameMovesTheItem() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("before.txt")
        let target = directory.appendingPathComponent("after.txt")
        let payload = Data("carried across".utf8)
        try payload.write(to: source)

        try await FileSystemService().rename(
            fromPath: source.path,
            toPath: target.path,
            overwrite: false
        )

        #expect(!FileManager.default.fileExists(atPath: source.path))
        let onDisk = try Data(contentsOf: target)
        #expect(onDisk == payload)
    }

    @Test("createDirectory creates the directory and any missing parents")
    func createDirectoryCreatesTheDirectoryAndItsParents() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let leaf = directory.appendingPathComponent("one/two/three")

        try await FileSystemService().createDirectory(atPath: leaf.path)

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: leaf.path, isDirectory: &isDirectory)
        #expect(exists)
        #expect(isDirectory.boolValue)
    }

    // MARK: - Missing paths

    @Test("readFile on a missing path reports fileNotFound, naming the path")
    func readingAMissingFileReportsFileNotFound() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("absent.txt").path
        let service = FileSystemService()

        let thrown = await expectingFileSystemError("readFile on a missing path") {
            _ = try await service.readFile(atPath: missing)
        }

        guard let thrown else { return }
        guard case .fileNotFound(let reported) = thrown else {
            Issue.record("expected .fileNotFound, got \(thrown)")
            return
        }
        #expect(reported == missing)
    }

    @Test("stat on a missing path reports fileNotFound, naming the path")
    func stattingAMissingPathReportsFileNotFound() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("absent.txt").path
        let service = FileSystemService()

        let thrown = await expectingFileSystemError("stat on a missing path") {
            _ = try await service.stat(atPath: missing)
        }

        guard let thrown else { return }
        guard case .fileNotFound(let reported) = thrown else {
            Issue.record("expected .fileNotFound, got \(thrown)")
            return
        }
        #expect(reported == missing)
    }

    // MARK: - The write flags

    @Test("writeFile with create: false refuses a missing path and creates nothing")
    func writingWithoutCreateRefusesAMissingPath() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("absent.txt").path
        let service = FileSystemService()

        let thrown = await expectingFileSystemError("writeFile with create: false") {
            try await service.writeFile(
                atPath: missing,
                contents: Data("nope".utf8),
                create: false,
                overwrite: true
            )
        }

        guard let thrown else { return }
        guard case .fileNotFound(let reported) = thrown else {
            Issue.record("expected .fileNotFound, got \(thrown)")
            return
        }
        #expect(reported == missing)
        #expect(!FileManager.default.fileExists(atPath: missing))
    }

    @Test("writeFile with create: true writes the same missing path")
    func writingWithCreateWritesAMissingPath() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("absent.txt")
        let payload = Data("created".utf8)

        try await FileSystemService().writeFile(
            atPath: file.path,
            contents: payload,
            create: true,
            overwrite: false
        )

        let onDisk = try Data(contentsOf: file)
        #expect(onDisk == payload)
    }

    @Test("writeFile with overwrite: false refuses an existing file and leaves its bytes alone")
    func writingWithoutOverwriteRefusesAnExistingFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("occupied.txt")
        let original = Data("the original bytes".utf8)
        try original.write(to: file)
        let service = FileSystemService()

        let thrown = await expectingFileSystemError("writeFile with overwrite: false") {
            try await service.writeFile(
                atPath: file.path,
                contents: Data("the replacement".utf8),
                create: true,
                overwrite: false
            )
        }

        guard let thrown else { return }
        guard case .fileExists(let reported) = thrown else {
            Issue.record("expected .fileExists, got \(thrown)")
            return
        }
        #expect(reported == file.path)
        let onDisk = try Data(contentsOf: file)
        #expect(onDisk == original)
    }

    @Test("writeFile with overwrite: true replaces the same file's bytes")
    func writingWithOverwriteReplacesAnExistingFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("occupied.txt")
        try Data("the original bytes".utf8).write(to: file)
        let replacement = Data("the replacement".utf8)

        try await FileSystemService().writeFile(
            atPath: file.path,
            contents: replacement,
            create: false,
            overwrite: true
        )

        let onDisk = try Data(contentsOf: file)
        #expect(onDisk == replacement)
    }

    @Test("writeFile onto a directory reports fileIsADirectory")
    func writingOntoADirectoryReportsFileIsADirectory() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = FileSystemService()

        let thrown = await expectingFileSystemError("writeFile onto a directory") {
            try await service.writeFile(
                atPath: directory.path,
                contents: Data("nope".utf8),
                create: true,
                overwrite: true
            )
        }

        guard let thrown else { return }
        guard case .fileIsADirectory(let reported) = thrown else {
            Issue.record("expected .fileIsADirectory, got \(thrown)")
            return
        }
        #expect(reported == directory.path)
    }

    // MARK: - The delete flags

    @Test("delete with recursive: false refuses a directory with entries in it and removes nothing")
    func deletingANonEmptyDirectoryWithoutRecursiveRefuses() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let populated = directory.appendingPathComponent("populated")
        try FileManager.default.createDirectory(at: populated, withIntermediateDirectories: true)
        let child = populated.appendingPathComponent("child.txt")
        try Data("child".utf8).write(to: child)
        let service = FileSystemService()

        let thrown = await expectingFileSystemError("delete with recursive: false") {
            try await service.delete(atPath: populated.path, recursive: false, useTrash: false)
        }

        guard let thrown else { return }
        guard case .directoryNotEmpty(let reported) = thrown else {
            Issue.record("expected .directoryNotEmpty, got \(thrown)")
            return
        }
        #expect(reported == populated.path)
        #expect(FileManager.default.fileExists(atPath: child.path))
    }

    @Test("delete with recursive: true removes the same directory and its contents")
    func deletingANonEmptyDirectoryRecursivelyRemovesIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let populated = directory.appendingPathComponent("populated")
        try FileManager.default.createDirectory(at: populated, withIntermediateDirectories: true)
        try Data("child".utf8).write(to: populated.appendingPathComponent("child.txt"))

        try await FileSystemService().delete(atPath: populated.path, recursive: true, useTrash: false)

        #expect(!FileManager.default.fileExists(atPath: populated.path))
    }

    @Test("delete on a symbolic link removes the link and leaves its target")
    func deletingASymbolicLinkLeavesItsTarget() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.txt")
        try Data("target".utf8).write(to: target)
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: target.path
        )

        try await FileSystemService().delete(atPath: link.path, recursive: false, useTrash: false)

        #expect(!FileManager.default.fileExists(atPath: link.path))
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    // MARK: - The rename flag

    @Test("rename with overwrite: false refuses an occupied target and moves nothing")
    func renamingOntoAnExistingPathRefuses() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.txt")
        let target = directory.appendingPathComponent("target.txt")
        let targetBytes = Data("the target's own bytes".utf8)
        try Data("the source".utf8).write(to: source)
        try targetBytes.write(to: target)
        let service = FileSystemService()

        let thrown = await expectingFileSystemError("rename with overwrite: false") {
            try await service.rename(fromPath: source.path, toPath: target.path, overwrite: false)
        }

        guard let thrown else { return }
        guard case .fileExists(let reported) = thrown else {
            Issue.record("expected .fileExists, got \(thrown)")
            return
        }
        #expect(reported == target.path)
        #expect(FileManager.default.fileExists(atPath: source.path))
        let onDisk = try Data(contentsOf: target)
        #expect(onDisk == targetBytes)
    }

    @Test("rename with overwrite: true replaces the same occupied target")
    func renamingOntoAnExistingPathWithOverwriteReplacesIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.txt")
        let target = directory.appendingPathComponent("target.txt")
        let sourceBytes = Data("the source's bytes".utf8)
        try sourceBytes.write(to: source)
        try Data("the target's own bytes".utf8).write(to: target)

        try await FileSystemService().rename(
            fromPath: source.path,
            toPath: target.path,
            overwrite: true
        )

        #expect(!FileManager.default.fileExists(atPath: source.path))
        let onDisk = try Data(contentsOf: target)
        #expect(onDisk == sourceBytes)
    }

    @Test("rename from a missing path reports fileNotFound, naming the source")
    func renamingFromAMissingPathReportsFileNotFound() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("absent.txt").path
        let target = directory.appendingPathComponent("target.txt").path
        let service = FileSystemService()

        let thrown = await expectingFileSystemError("rename from a missing path") {
            try await service.rename(fromPath: missing, toPath: target, overwrite: true)
        }

        guard let thrown else { return }
        guard case .fileNotFound(let reported) = thrown else {
            Issue.record("expected .fileNotFound, got \(thrown)")
            return
        }
        #expect(reported == missing)
        #expect(!FileManager.default.fileExists(atPath: target))
    }

    // MARK: - Kind mismatches

    @Test("readFile on a directory reports fileIsADirectory")
    func readingADirectoryReportsFileIsADirectory() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = FileSystemService()

        let thrown = await expectingFileSystemError("readFile on a directory") {
            _ = try await service.readFile(atPath: directory.path)
        }

        guard let thrown else { return }
        guard case .fileIsADirectory(let reported) = thrown else {
            Issue.record("expected .fileIsADirectory, got \(thrown)")
            return
        }
        #expect(reported == directory.path)
    }

    @Test("readDirectory on a file reports fileNotADirectory")
    func listingAFileReportsFileNotADirectory() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("plain.txt")
        try Data("plain".utf8).write(to: file)
        let service = FileSystemService()

        let thrown = await expectingFileSystemError("readDirectory on a file") {
            _ = try await service.readDirectory(atPath: file.path)
        }

        guard let thrown else { return }
        guard case .fileNotADirectory(let reported) = thrown else {
            Issue.record("expected .fileNotADirectory, got \(thrown)")
            return
        }
        #expect(reported == file.path)
    }

    @Test("createDirectory over an existing file reports fileExists")
    func creatingADirectoryOverAFileReportsFileExists() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("plain.txt")
        try Data("plain".utf8).write(to: file)
        let service = FileSystemService()

        let thrown = await expectingFileSystemError("createDirectory over a file") {
            try await service.createDirectory(atPath: file.path)
        }

        guard let thrown else { return }
        guard case .fileExists(let reported) = thrown else {
            Issue.record("expected .fileExists, got \(thrown)")
            return
        }
        #expect(reported == file.path)
    }

    // MARK: - The bitmask

    @Test("the raw values are VS Code's: unknown 0, file 1, directory 2, symbolic link 64")
    func rawValuesMatchTheContract() {
        #expect(FileSystemService.FileType.unknown.rawValue == 0)
        #expect(FileSystemService.FileType.file.rawValue == 1)
        #expect(FileSystemService.FileType.directory.rawValue == 2)
        #expect(FileSystemService.FileType.symbolicLink.rawValue == 64)

        let linkedDirectory: FileSystemService.FileType = [.directory, .symbolicLink]
        #expect(linkedDirectory.rawValue == 66)

        #expect(FileSystemService.FileType.unknown.isUnknown)
        #expect(!FileSystemService.FileType.file.isUnknown)
        #expect(!linkedDirectory.isUnknown)
    }

    @Test("stat of a directory answers the directory bit alone")
    func statOfADirectoryAnswersTheDirectoryBit() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let stat = try await FileSystemService().stat(atPath: directory.path)

        #expect(stat.type.rawValue == 2)
    }

    @Test("stat of a symbolic link to a file answers both bits, raw value 65")
    func statOfALinkToAFileAnswersBothBits() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.txt")
        try Data("target".utf8).write(to: target)
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: target.path
        )

        let stat = try await FileSystemService().stat(atPath: link.path)

        #expect(stat.type.rawValue == 65)
    }

    @Test("stat of a symbolic link to a directory answers both bits, raw value 66")
    func statOfALinkToADirectoryAnswersBothBits() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: target.path
        )

        let stat = try await FileSystemService().stat(atPath: link.path)

        #expect(stat.type.rawValue == 66)
    }

    @Test("stat of a dangling symbolic link answers the link bit alone")
    func statOfADanglingLinkAnswersTheLinkBit() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: directory.appendingPathComponent("never-existed").path
        )

        let stat = try await FileSystemService().stat(atPath: link.path)

        #expect(stat.type.rawValue == 64)
    }

    @Test("stat reports the link's own size, not its target's")
    func statDoesNotReportTheTargetsSize() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.bin")
        let payload = Data(repeating: 3, count: 4096)
        try payload.write(to: target)
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: target.path
        )

        let stat = try await FileSystemService().stat(atPath: link.path)

        #expect(stat.size != payload.count)
    }

    @Test("readDirectory follows a symbolic link to the directory it lists")
    func readDirectoryFollowsALinkToADirectory() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("inside".utf8).write(to: target.appendingPathComponent("inside.txt"))
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: target.path
        )

        let entries = try await FileSystemService().readDirectory(atPath: link.path)

        #expect(entries.map(\.name) == ["inside.txt"])
    }

    // MARK: - Concurrency

    @Test("eight concurrent reads each answer their own file's bytes")
    func concurrentReadsEachAnswerTheirOwnBytes() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var paths: [String] = []
        for index in 0..<8 {
            let file = directory.appendingPathComponent("file-\(index).txt")
            try Data("payload-\(index)".utf8).write(to: file)
            paths.append(file.path)
        }
        let frozenPaths = paths
        let service = FileSystemService()

        let seen = try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for index in 0..<8 {
                group.addTask {
                    let data = try await service.readFile(atPath: frozenPaths[index])
                    return (index, data)
                }
            }
            var collected: [Int: Data] = [:]
            for try await (index, data) in group {
                collected[index] = data
            }
            return collected
        }

        #expect(seen.count == 8)
        for index in 0..<8 {
            #expect(seen[index] == Data("payload-\(index)".utf8))
        }
    }
}
