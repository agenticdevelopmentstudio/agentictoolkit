import Foundation

/// Stores the document as pretty JSON, written atomically. Watches the
/// containing directory, because atomic writes replace the file.
@MainActor
public final class JSONFileDocumentStore: DisplayDocumentStore {
    public let url: URL

    public init(url: URL) { self.url = url }

    private struct VersionProbe: Decodable { let version: Int? }

    public func load() throws -> DisplayDocument {
        guard FileManager.default.fileExists(atPath: url.path) else { return DisplayDocument() }
        let data = try read()
        try checkVersion(data)
        do {
            return try JSONDecoder().decode(DisplayDocument.self, from: data)
        } catch {
            throw DocumentStoreError.corrupt(String(describing: error))
        }
    }

    public func save(_ document: DisplayDocument) throws {
        if FileManager.default.fileExists(atPath: url.path) { try checkVersion(try read()) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(document).write(to: url, options: .atomic)
        } catch {
            throw DocumentStoreError.ioError(String(describing: error))
        }
    }

    /// Creates the containing directory if needed, then watches it. Throws
    /// `.ioError` when the directory cannot be opened for events.
    public func watch(_ onChange: @escaping @MainActor () -> Void) throws -> DocumentWatch {
        let directory = url.deletingLastPathComponent()
        // A failure here surfaces as the `open` failure below, with its errno.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw DocumentStoreError.ioError("cannot watch \(directory.path): \(String(cString: strerror(errno)))")
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename], queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { onChange() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return DocumentWatch { source.cancel() }
    }

    /// Moves a corrupt document to `<name>.corrupt-<UTC timestamp>.json`
    /// beside it and returns that URL. See `DisplayDocumentStore.resetCorrupt()`.
    public func resetCorrupt() throws -> URL? {
        do {
            _ = try load()
            return nil
        } catch DocumentStoreError.corrupt {
            let backup = url.deletingLastPathComponent().appendingPathComponent(
                "\(url.deletingPathExtension().lastPathComponent).corrupt-\(Self.backupStamp()).json")
            do {
                try FileManager.default.moveItem(at: url, to: backup)
            } catch {
                throw DocumentStoreError.ioError(String(describing: error))
            }
            return backup
        }
    }

    private static func backupStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmssSSS"
        return formatter.string(from: Date())
    }

    private func read() throws -> Data {
        do { return try Data(contentsOf: url) } catch { throw DocumentStoreError.ioError(String(describing: error)) }
    }

    private func checkVersion(_ data: Data) throws {
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data) else {
            throw DocumentStoreError.corrupt("not a JSON object with a version")
        }
        let found = probe.version ?? DisplayDocument.currentVersion
        if found > DisplayDocument.currentVersion {
            throw DocumentStoreError.unsupportedVersion(found: found, supported: DisplayDocument.currentVersion)
        }
    }
}
