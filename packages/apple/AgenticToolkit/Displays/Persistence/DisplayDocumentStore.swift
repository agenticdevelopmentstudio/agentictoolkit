import Foundation

public enum DocumentStoreError: Error, Equatable, Sendable {
    /// Written by a newer version; refused for both read and write.
    case unsupportedVersion(found: Int, supported: Int)
    case corrupt(String)
    case ioError(String)
}

/// Token for an active `watch`. The watch stops on `cancel()` or when the
/// token is released, whichever comes first.
@MainActor
public final class DocumentWatch {
    private var onCancel: (() -> Void)?
    public init(onCancel: @escaping () -> Void) { self.onCancel = onCancel }
    public func cancel() {
        onCancel?()
        onCancel = nil
    }

    isolated deinit { cancel() }
}

@MainActor
public protocol DisplayDocumentStore: AnyObject {
    func load() throws -> DisplayDocument
    func save(_ document: DisplayDocument) throws
    /// Calls `onChange` on the main actor when the stored document changes
    /// externally, until the returned token is cancelled or released.
    /// Throws `DocumentStoreError.ioError` when the watch cannot be set up.
    func watch(_ onChange: @escaping @MainActor () -> Void) throws -> DocumentWatch
    /// Moves an undecodable document aside so the store loads empty again.
    /// Returns the backup's location, or nil when there was nothing corrupt
    /// to move (no document, or one that loads). Other load errors, such as
    /// `unsupportedVersion`, are rethrown untouched: that file is not corrupt.
    func resetCorrupt() throws -> URL?
}

/// Volatile store for tests and previews.
@MainActor
public final class InMemoryDocumentStore: DisplayDocumentStore {
    public var document: DisplayDocument
    public var failNextSave: DocumentStoreError?
    public init(_ document: DisplayDocument = DisplayDocument()) { self.document = document }
    public func load() throws -> DisplayDocument { document }
    public func save(_ document: DisplayDocument) throws {
        if let failure = failNextSave {
            failNextSave = nil
            throw failure
        }
        self.document = document
    }
    public func watch(_ onChange: @escaping @MainActor () -> Void) throws -> DocumentWatch { DocumentWatch {} }
    /// Always nil: an in-memory document is never corrupt.
    public func resetCorrupt() throws -> URL? { nil }
}
