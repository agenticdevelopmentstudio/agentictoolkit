//
//  FileSystemService.swift
//  AgenticToolkit
//

import Foundation

/// Why a `FileSystemService` operation failed.
///
/// Shaped after `SystemWindowContextStoreError`: `Error, LocalizedError`, a
/// `path: String` on every case that names one, and the underlying
/// `FileManager` error carried where there is a cause to carry.
///
/// Carrying an `any Error` is what costs this enum `Equatable` and `Sendable`.
/// Three error enums in this package flatten their cause to a `String` to keep
/// those conformances; this one deliberately does not, because a caller
/// translating a failure into another system's error vocabulary needs the real
/// `CocoaError` to branch on, and `localizedDescription` cannot be branched on.
/// Compare a thrown value on its case and its path rather than with `==`.
///
/// The first six cases name failures a caller is expected to tell apart. The
/// rest are operation-shaped fallbacks: the operation failed and the error it
/// produced carried nothing this type could classify.
public enum FileSystemServiceError: Error, LocalizedError {

    /// Nothing exists at `path`.
    case fileNotFound(path: String)

    /// Something already exists at `path` and the operation was told not to
    /// replace it.
    case fileExists(path: String)

    /// `path` resolves to a directory and the operation requires a file.
    case fileIsADirectory(path: String)

    /// `path` does not resolve to a directory and the operation requires one.
    case fileNotADirectory(path: String)

    /// `path` is a directory with entries in it and the delete was not
    /// recursive.
    case directoryNotEmpty(path: String)

    /// The operation was refused for want of permission.
    ///
    /// Detection is best-effort. It fires when Foundation reports one of its
    /// permission-specific `CocoaError` codes, or when an underlying
    /// `EACCES`/`EPERM` is reachable from the thrown error. A permission
    /// failure reported some other way arrives as the operation-shaped case
    /// for that operation instead.
    case noPermissions(path: String, underlying: Error)

    /// Reading a file's bytes failed for a reason none of the cases above
    /// names.
    case readFailed(path: String, underlying: Error)

    /// Writing a file's bytes failed for a reason none of the cases above
    /// names.
    case writeFailed(path: String, underlying: Error)

    /// Reading an item's attributes failed for a reason none of the cases
    /// above names.
    case statFailed(path: String, underlying: Error)

    /// Listing a directory failed for a reason none of the cases above names.
    case readDirectoryFailed(path: String, underlying: Error)

    /// Deleting an item failed for a reason none of the cases above names.
    case deleteFailed(path: String, underlying: Error)

    /// Moving an item failed for a reason none of the cases above names.
    /// `path` is the source and `destination` the target.
    case renameFailed(path: String, destination: String, underlying: Error)

    /// Creating a directory failed for a reason none of the cases above names.
    case createDirectoryFailed(path: String, underlying: Error)

    /// A sentence describing the failure, for logs and for display.
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "No such file or directory: \(path)"
        case .fileExists(let path):
            return "Already exists: \(path)"
        case .fileIsADirectory(let path):
            return "Is a directory: \(path)"
        case .fileNotADirectory(let path):
            return "Not a directory: \(path)"
        case .directoryNotEmpty(let path):
            return "Directory is not empty: \(path)"
        case .noPermissions(let path, let underlying):
            return "Permission denied at \(path): \(underlying.localizedDescription)"
        case .readFailed(let path, let underlying):
            return "Failed to read file at \(path): \(underlying.localizedDescription)"
        case .writeFailed(let path, let underlying):
            return "Failed to write file at \(path): \(underlying.localizedDescription)"
        case .statFailed(let path, let underlying):
            return "Failed to read attributes at \(path): \(underlying.localizedDescription)"
        case .readDirectoryFailed(let path, let underlying):
            return "Failed to list directory at \(path): \(underlying.localizedDescription)"
        case .deleteFailed(let path, let underlying):
            return "Failed to delete \(path): \(underlying.localizedDescription)"
        case .renameFailed(let path, let destination, let underlying):
            return "Failed to move \(path) to \(destination): \(underlying.localizedDescription)"
        case .createDirectoryFailed(let path, let underlying):
            return "Failed to create directory at \(path): \(underlying.localizedDescription)"
        }
    }
}

/// Seven file-system operations over `FileManager`, all `async`, all throwing
/// `FileSystemServiceError`.
///
/// Read bytes, write bytes, list a directory, stat a path, delete, rename and
/// create a directory. Nothing else: no globbing, no recursive copy, no
/// watching, no multi-file transaction. The bound is deliberate — it is the
/// surface a `workspace.fs`-shaped adaptor needs, and every member beyond it
/// would be a member with no caller.
///
/// This type knows nothing about JavaScript, VS Code or extensions. Paths are
/// file-system paths (`String`), never URLs or URIs; a caller holding a URI
/// converts before it calls in.
///
/// ## Concurrency
///
/// An actor whose blocking work runs on one dedicated serial `DispatchQueue`,
/// bridged back into `async` with `withCheckedThrowingContinuation`. Two
/// properties follow: no `FileManager` call is ever made on a thread of
/// Swift's fixed-width cooperative pool, and the actor itself is free while
/// one runs, because the awaiting task is suspended rather than blocked.
///
/// `Core/RPC/SubprocessChannel.swift` is the other piece of async I/O in this
/// tier and it is **not** the template here, despite arguing at length (in the
/// doc comments on `sendRaw(_:)` and on its reader) for `DispatchIO` over a
/// blocking call. Half of that reasoning applies and half does not. The half
/// that does: a blocking call must not park a cooperative-pool thread, which
/// is why `Task.detached` is ruled out here too. The half that does not: a
/// pipe read waits on a child process that may never write again, so a parked
/// thread is parked forever, whereas a read of a local file returns in bounded
/// time. `DispatchIO`'s callback plumbing buys nothing for seven operations
/// with no streaming shape and costs a great deal of machinery to get right.
///
/// The cost of that ruling, if it is wrong, is a throughput ceiling under
/// concurrent reads — one serial queue serves every caller. Widening it is a
/// change to one property.
///
/// A fresh `FileManager` is constructed inside each queued block rather than
/// shared: it keeps a non-`Sendable` object from crossing the queue boundary
/// at all, and `FileManager.default` is the process-wide shared instance
/// rather than a per-worker one.
public actor FileSystemService {

    // MARK: - Value types

    /// What an item is, as a bitmask rather than a choice of four.
    ///
    /// The raw values match VS Code's `FileType`: `Unknown = 0`, `File = 1`,
    /// `Directory = 2`, `SymbolicLink = 64`. A symbolic link to a directory
    /// answers `[.directory, .symbolicLink]`, raw value 66 — a combination an
    /// enum of four cases could not express, and one a caller would otherwise
    /// have to reconstruct.
    ///
    /// Nested inside the service because `FileType` is a generic enough name
    /// to collide in a framework this widely imported;
    /// `SubprocessChannel.Configuration` is this package's precedent for
    /// nesting a `Sendable` value type in an actor.
    public struct FileType: OptionSet, Sendable, Equatable {

        /// The bitmask, matching VS Code's `FileType` values.
        public let rawValue: Int

        /// Wraps a raw bitmask.
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// A regular file.
        public static let file = FileType(rawValue: 1)

        /// A directory.
        public static let directory = FileType(rawValue: 2)

        /// A symbolic link. Set alongside the target's own bit when the
        /// target's type could be determined.
        public static let symbolicLink = FileType(rawValue: 64)

        /// Neither a file, a directory nor a link — a socket, a FIFO, a
        /// device, or an item whose type could not be read.
        ///
        /// This is the empty set, so `contains(.unknown)` is `true` for every
        /// value and is never the test you want. Use ``isUnknown``.
        public static let unknown: FileType = []

        /// Whether no type bit is set at all.
        public var isUnknown: Bool {
            rawValue == 0
        }
    }

    /// What `stat(atPath:)` answers about one item.
    ///
    /// The timestamps are `Date`, not milliseconds since the epoch: this tier
    /// has no opinion about any particular caller's wire format, and a caller
    /// that needs VS Code's integer milliseconds converts with
    /// `timeIntervalSince1970 * 1000`. Storing the integer instead would bake
    /// one consumer's representation into a shared type.
    ///
    /// Both dates are optional because `FileManager` reports them as
    /// attributes that may be absent. `nil` means "not reported", which is a
    /// distinction a caller can collapse and this type cannot invent.
    public struct FileStat: Sendable, Equatable {

        /// The item's type bits. For a symbolic link this describes the link,
        /// not its target — see ``FileSystemService/stat(atPath:)``.
        public let type: FileType

        /// When the item was created, or `nil` when not reported. VS Code
        /// calls this `ctime`.
        public let creationDate: Date?

        /// When the item's contents last changed, or `nil` when not reported.
        /// VS Code calls this `mtime`.
        public let modificationDate: Date?

        /// The item's size in bytes, or `0` when not reported.
        public let size: Int

        /// Records one item's type, timestamps and size.
        public init(type: FileType, creationDate: Date?, modificationDate: Date?, size: Int) {
            self.type = type
            self.creationDate = creationDate
            self.modificationDate = modificationDate
            self.size = size
        }
    }

    /// One child of a directory: its name and its type, and nothing else.
    ///
    /// Not a full ``FileStat``. Statting every child of a large directory to
    /// answer a listing is a cost no caller asked for, and a name-and-type
    /// pair is what a `readDirectory` contract answers.
    public struct DirectoryEntry: Sendable, Equatable {

        /// The child's name within its directory, not a path.
        public let name: String

        /// The child's type bits, on the same terms as ``FileStat/type``: a
        /// symbolic link describes the link, with its target's bit set beside
        /// it where that could be determined.
        public let type: FileType

        /// Records one directory child.
        public init(name: String, type: FileType) {
            self.name = name
            self.type = type
        }
    }

    // MARK: - State

    /// The one queue every blocking call runs on. See the type's discussion of
    /// concurrency for why it is serial and why it is a `DispatchQueue`.
    private let queue = DispatchQueue(
        label: "com.agentictoolkit.core.filesystemservice",
        qos: .userInitiated
    )

    /// Creates a service. It owns no state beyond its queue, so several may
    /// exist; each gets its own.
    public init() {}

    // MARK: - Reading

    /// Answers the bytes of the file at `path`.
    ///
    /// Symbolic links are followed, as reading a file always does. Throws
    /// ``FileSystemServiceError/fileNotFound(path:)`` when nothing resolves at
    /// `path` (a dangling link included) and
    /// ``FileSystemServiceError/fileIsADirectory(path:)`` when it resolves to
    /// a directory.
    public func readFile(atPath path: String) async throws -> Data {
        try await perform {
            let manager = FileManager()
            guard let resolved = Self.resolvedTypeBits(atPath: path, using: manager) else {
                throw FileSystemServiceError.fileNotFound(path: path)
            }
            guard !resolved.contains(.directory) else {
                throw FileSystemServiceError.fileIsADirectory(path: path)
            }
            do {
                return try Data(contentsOf: URL(fileURLWithPath: path))
            } catch {
                throw Self.distinguished(error, path: path)
                    ?? FileSystemServiceError.readFailed(path: path, underlying: error)
            }
        }
    }

    /// Answers the name and type of every child of the directory at `path`.
    ///
    /// A symbolic link at `path` is followed, as opening a directory does. The
    /// listing is not recursive and the order is `FileManager`'s.
    ///
    /// A child whose own type could not be read is reported as
    /// ``FileType/unknown`` rather than aborting the listing — that is what
    /// VS Code's `Unknown = 0` exists for. A failure to read the directory
    /// itself still throws.
    public func readDirectory(atPath path: String) async throws -> [DirectoryEntry] {
        try await perform {
            let manager = FileManager()
            guard let resolved = Self.resolvedTypeBits(atPath: path, using: manager) else {
                throw FileSystemServiceError.fileNotFound(path: path)
            }
            guard resolved.contains(.directory) else {
                throw FileSystemServiceError.fileNotADirectory(path: path)
            }
            let names: [String]
            do {
                names = try manager.contentsOfDirectory(atPath: path)
            } catch {
                throw Self.distinguished(error, path: path)
                    ?? FileSystemServiceError.readDirectoryFailed(path: path, underlying: error)
            }
            let directoryURL = URL(fileURLWithPath: path)
            return names.map { name in
                let childPath = directoryURL.appendingPathComponent(name).path
                return DirectoryEntry(name: name, type: Self.fileType(atPath: childPath, using: manager))
            }
        }
    }

    /// Answers the type, timestamps and size of the item at `path`.
    ///
    /// **This does not follow a terminal symbolic link.** A link is reported
    /// as the link — its own timestamps and size, with
    /// ``FileType/symbolicLink`` set and the resolved target's type bit set
    /// beside it where that could be determined cheaply, so a link to a
    /// directory answers raw value 66. That is the answer that loses no
    /// information: a caller wanting the target can resolve and stat again,
    /// whereas a caller handed only the target's stat cannot discover it went
    /// through a link.
    ///
    /// A link whose target does not exist answers ``FileType/symbolicLink``
    /// alone.
    public func stat(atPath path: String) async throws -> FileStat {
        try await perform {
            let manager = FileManager()
            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try manager.attributesOfItem(atPath: path)
            } catch {
                throw Self.distinguished(error, path: path)
                    ?? FileSystemServiceError.statFailed(path: path, underlying: error)
            }
            return FileStat(
                type: Self.typeBits(ofLinkAttributes: attributes, atPath: path, using: manager),
                creationDate: attributes[.creationDate] as? Date,
                modificationDate: attributes[.modificationDate] as? Date,
                size: (attributes[.size] as? NSNumber)?.intValue ?? 0
            )
        }
    }

    // MARK: - Writing

    /// Writes `contents` to the file at `path`.
    ///
    /// `create` and `overwrite` name two different failures and are not
    /// collapsed into one flag: `create: false` where nothing exists throws
    /// ``FileSystemServiceError/fileNotFound(path:)``, and `overwrite: false`
    /// where something does throws
    /// ``FileSystemServiceError/fileExists(path:)``. A path resolving to a
    /// directory throws ``FileSystemServiceError/fileIsADirectory(path:)``.
    ///
    /// Existence is judged at the link, not through it, so a dangling symbolic
    /// link counts as something already there — consistent with
    /// ``stat(atPath:)``.
    ///
    /// The write is not atomic. Writing in place, rather than to a temporary
    /// file and renaming over it, is what preserves the existing file's inode
    /// and permissions and what writes *through* a symbolic link instead of
    /// replacing it.
    public func writeFile(
        atPath path: String,
        contents: Data,
        create: Bool,
        overwrite: Bool
    ) async throws {
        try await perform {
            let manager = FileManager()
            if Self.linkExists(atPath: path, using: manager) {
                guard overwrite else {
                    throw FileSystemServiceError.fileExists(path: path)
                }
                if Self.resolvedTypeBits(atPath: path, using: manager)?.contains(.directory) == true {
                    throw FileSystemServiceError.fileIsADirectory(path: path)
                }
            } else {
                guard create else {
                    throw FileSystemServiceError.fileNotFound(path: path)
                }
            }
            do {
                try contents.write(to: URL(fileURLWithPath: path))
            } catch {
                throw Self.distinguished(error, path: path)
                    ?? FileSystemServiceError.writeFailed(path: path, underlying: error)
            }
        }
    }

    /// Creates the directory at `path`, creating any missing parents.
    ///
    /// Succeeds silently when `path` is already a directory. Throws
    /// ``FileSystemServiceError/fileExists(path:)`` when something that is not
    /// a directory is there.
    public func createDirectory(atPath path: String) async throws {
        try await perform {
            let manager = FileManager()
            if let existing = Self.resolvedTypeBits(atPath: path, using: manager),
               !existing.contains(.directory) {
                throw FileSystemServiceError.fileExists(path: path)
            }
            do {
                try manager.createDirectory(
                    at: URL(fileURLWithPath: path),
                    withIntermediateDirectories: true
                )
            } catch {
                throw Self.distinguished(error, path: path)
                    ?? FileSystemServiceError.createDirectoryFailed(path: path, underlying: error)
            }
        }
    }

    // MARK: - Removing and moving

    /// Deletes the item at `path`.
    ///
    /// A symbolic link is deleted as the link; its target is untouched.
    ///
    /// `recursive: false` against a directory with entries in it throws
    /// ``FileSystemServiceError/directoryNotEmpty(path:)`` and deletes
    /// nothing. `useTrash: true` moves the item to the user's Trash through
    /// `FileManager.trashItem(at:resultingItemURL:)`, which is declared in
    /// Foundation's `NSFileManager.h` and available from macOS 10.8, so
    /// honouring the flag needs nothing from a higher tier. The resulting
    /// Trash location is not surfaced: this surface has no member that could
    /// answer it, and the Trash may rename an item to avoid a collision.
    public func delete(atPath path: String, recursive: Bool, useTrash: Bool) async throws {
        try await perform {
            let manager = FileManager()
            guard let attributes = try? manager.attributesOfItem(atPath: path) else {
                throw FileSystemServiceError.fileNotFound(path: path)
            }
            let bits = Self.typeBits(for: attributes[.type] as? FileAttributeType)
            if bits.contains(.directory), !recursive {
                let children = (try? manager.contentsOfDirectory(atPath: path)) ?? []
                guard children.isEmpty else {
                    throw FileSystemServiceError.directoryNotEmpty(path: path)
                }
            }
            let url = URL(fileURLWithPath: path)
            do {
                if useTrash {
                    try manager.trashItem(at: url, resultingItemURL: nil)
                } else {
                    try manager.removeItem(at: url)
                }
            } catch {
                throw Self.distinguished(error, path: path)
                    ?? FileSystemServiceError.deleteFailed(path: path, underlying: error)
            }
        }
    }

    /// Moves the item at `fromPath` to `toPath`. Rename and move are one
    /// operation here, as they are one `rename(2)`.
    ///
    /// Throws ``FileSystemServiceError/fileNotFound(path:)`` when nothing is
    /// at `fromPath`, and ``FileSystemServiceError/fileExists(path:)`` when
    /// something is at `toPath` and `overwrite` is `false`.
    ///
    /// Overwriting removes the existing item and then moves, which is two
    /// steps and not atomic: a failure of the move leaves `toPath` empty.
    /// Foundation offers no atomic replace that spans files and directories
    /// alike, and nothing in this surface's contract promises one.
    public func rename(fromPath: String, toPath: String, overwrite: Bool) async throws {
        try await perform {
            let manager = FileManager()
            guard Self.linkExists(atPath: fromPath, using: manager) else {
                throw FileSystemServiceError.fileNotFound(path: fromPath)
            }
            if Self.linkExists(atPath: toPath, using: manager) {
                guard overwrite else {
                    throw FileSystemServiceError.fileExists(path: toPath)
                }
                do {
                    try manager.removeItem(at: URL(fileURLWithPath: toPath))
                } catch {
                    throw Self.distinguished(error, path: toPath)
                        ?? FileSystemServiceError.deleteFailed(path: toPath, underlying: error)
                }
            }
            do {
                try manager.moveItem(
                    at: URL(fileURLWithPath: fromPath),
                    to: URL(fileURLWithPath: toPath)
                )
            } catch {
                throw Self.distinguished(error, path: fromPath)
                    ?? FileSystemServiceError.renameFailed(
                        path: fromPath,
                        destination: toPath,
                        underlying: error
                    )
            }
        }
    }

    // MARK: - The queue bridge

    /// Runs `body` on the service's serial queue and resumes the caller with
    /// its result.
    ///
    /// The continuation is what keeps the actor free: the awaiting task
    /// suspends, so no cooperative-pool thread is parked for the duration of a
    /// blocking `FileManager` call, and no other caller of this actor queues
    /// behind it at the actor. They queue at the `DispatchQueue` instead,
    /// which owns a thread that exists to be blocked.
    private func perform<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        let queue = self.queue
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let value = try body()
                    continuation.resume(returning: value)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Type bits

    /// The type bits for one `FileAttributeKey.type` value.
    ///
    /// Anything that is not a regular file, a directory or a symbolic link —
    /// a socket, a FIFO, a device, an absent or unrecognised value — is
    /// ``FileType/unknown``.
    private static func typeBits(for attributeType: FileAttributeType?) -> FileType {
        switch attributeType {
        case .some(.typeRegular):
            return .file
        case .some(.typeDirectory):
            return .directory
        case .some(.typeSymbolicLink):
            return .symbolicLink
        default:
            return .unknown
        }
    }

    /// The type bits for an item whose own attributes are already in hand,
    /// with its target's bit unioned in when it is a symbolic link.
    ///
    /// `FileManager.attributesOfItem(atPath:)` is documented in Foundation's
    /// `NSFileManager.h` not to traverse a terminal symbolic link, so
    /// `attributes` always describes the item itself.
    private static func typeBits(
        ofLinkAttributes attributes: [FileAttributeKey: Any],
        atPath path: String,
        using manager: FileManager
    ) -> FileType {
        var bits = typeBits(for: attributes[.type] as? FileAttributeType)
        if bits.contains(.symbolicLink) {
            bits.formUnion(resolvedTypeBits(atPath: path, using: manager) ?? .unknown)
        }
        return bits
    }

    /// The type bits for the item at `path`, on the same terms as
    /// ``typeBits(ofLinkAttributes:atPath:using:)``. ``FileType/unknown`` when
    /// nothing is there or its attributes could not be read — a listing
    /// reports that rather than failing.
    private static func fileType(atPath path: String, using manager: FileManager) -> FileType {
        guard let attributes = try? manager.attributesOfItem(atPath: path) else {
            return .unknown
        }
        return typeBits(ofLinkAttributes: attributes, atPath: path, using: manager)
    }

    /// The type bits of what `path` ultimately refers to, following every
    /// symbolic link on the way, or `nil` when that resolves to nothing.
    private static func resolvedTypeBits(atPath path: String, using manager: FileManager) -> FileType? {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard let attributes = try? manager.attributesOfItem(atPath: resolved) else {
            return nil
        }
        return typeBits(for: attributes[.type] as? FileAttributeType)
    }

    /// Whether anything is at `path`, judged at the link rather than through
    /// it, so a dangling symbolic link counts as present.
    private static func linkExists(atPath path: String, using manager: FileManager) -> Bool {
        (try? manager.attributesOfItem(atPath: path)) != nil
    }

    // MARK: - Error classification

    /// The distinguished case `error` identifies, or `nil` when it carries
    /// nothing that names one and the caller should fall back to its own
    /// operation-shaped case.
    private static func distinguished(_ error: Error, path: String) -> FileSystemServiceError? {
        if let code = posixCode(in: error) {
            if code == POSIXError.ENOENT {
                return .fileNotFound(path: path)
            }
            if code == POSIXError.EEXIST {
                return .fileExists(path: path)
            }
            if code == POSIXError.EISDIR {
                return .fileIsADirectory(path: path)
            }
            if code == POSIXError.ENOTDIR {
                return .fileNotADirectory(path: path)
            }
            if code == POSIXError.ENOTEMPTY {
                return .directoryNotEmpty(path: path)
            }
            if code == POSIXError.EACCES || code == POSIXError.EPERM {
                return .noPermissions(path: path, underlying: error)
            }
        }
        guard let cocoa = error as? CocoaError else {
            return nil
        }
        switch cocoa.code {
        case .fileNoSuchFile, .fileReadNoSuchFile:
            return .fileNotFound(path: path)
        case .fileWriteFileExists:
            return .fileExists(path: path)
        case .fileReadNoPermission, .fileWriteNoPermission:
            return .noPermissions(path: path, underlying: error)
        default:
            return nil
        }
    }

    /// The errno `error` carries, looked for on the error itself and then down
    /// its chain of `NSUnderlyingErrorKey` errors.
    ///
    /// The depth bound is a guard against a cyclic chain, not a judgement
    /// about how deep Foundation nests.
    private static func posixCode(in error: Error, depth: Int = 0) -> POSIXError.Code? {
        if let posix = error as? POSIXError {
            return posix.code
        }
        guard depth < 4 else {
            return nil
        }
        let nsError = error as NSError
        guard let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError else {
            return nil
        }
        return posixCode(in: underlying, depth: depth + 1)
    }
}
