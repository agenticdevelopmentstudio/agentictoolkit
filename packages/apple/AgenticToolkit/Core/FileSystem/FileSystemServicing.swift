//
//  FileSystemServicing.swift
//  AgenticToolkit
//

import Foundation

/// The seven operations ``FileSystemService`` exposes, named as a protocol so
/// a caller can hold something other than the concrete actor.
///
/// The only caller today is `MainThreadWorkspace` in the macOS tier, which
/// stores its file-system dependency as this protocol rather than as
/// ``FileSystemService`` so a test can substitute a double whose operations
/// suspend under the test's own control — the concrete actor's queue offers no
/// such hook, and a lower tier does not get to know that its only reason to
/// exist is a higher tier's test.
///
/// Signatures are copied verbatim from ``FileSystemService``; see that type
/// for what each operation does and throws. ``FileSystemService`` conforms
/// with an empty extension below, so this seam costs its callers nothing.
public protocol FileSystemServicing: Sendable {

    /// See ``FileSystemService/readFile(atPath:)``.
    func readFile(atPath path: String) async throws -> Data

    /// See ``FileSystemService/readDirectory(atPath:)``.
    func readDirectory(atPath path: String) async throws -> [FileSystemService.DirectoryEntry]

    /// See ``FileSystemService/stat(atPath:)``.
    func stat(atPath path: String) async throws -> FileSystemService.FileStat

    /// See ``FileSystemService/writeFile(atPath:contents:create:overwrite:)``.
    func writeFile(atPath path: String, contents: Data, create: Bool, overwrite: Bool) async throws

    /// See ``FileSystemService/createDirectory(atPath:)``.
    func createDirectory(atPath path: String) async throws

    /// See ``FileSystemService/delete(atPath:recursive:useTrash:)``.
    func delete(atPath path: String, recursive: Bool, useTrash: Bool) async throws

    /// See ``FileSystemService/rename(fromPath:toPath:overwrite:)``.
    func rename(fromPath: String, toPath: String, overwrite: Bool) async throws
}

/// `FileSystemService` already implements every requirement above with
/// matching signatures; there is nothing left to write.
extension FileSystemService: FileSystemServicing {}
