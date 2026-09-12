import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A double for `ExtensionWorkspaceRoots`, standing in for `ProjectWorkspace`
/// exactly as `MainThreadWorkspace`'s own doc says a test should: this suite
/// never builds a real `ProjectWorkspace` (a `GitRepo` plus a `ProjectDatabase`
/// this bundle has no business constructing), only the two facts
/// `MainThreadWorkspace` actually reads.
@MainActor
private final class TestWorkspaceRoots: ExtensionWorkspaceRoots {
    var workspaceDisplayName: String?
    var workspaceRootURLs: [URL]

    init(displayName: String? = nil, roots: [URL] = []) {
        self.workspaceDisplayName = displayName
        self.workspaceRootURLs = roots
    }
}

/// A `FileSystemServicing` double whose `readFile` suspends until the test
/// releases it, for the one test that needs to dispose `MainThreadWorkspace`
/// while an operation is genuinely in flight — a race the real
/// `FileSystemService` actor gives no way to hold open.
///
/// `waitUntilEntered()` lets the test block until `readFile` has actually
/// been called and is suspended (rather than guessing with a delay), and
/// `release()` lets it resume. Every other operation just throws: nothing in
/// this suite calls them, and giving them a real implementation would only
/// invite a future test to depend on behavior this double does not exist to
/// provide.
private actor SuspendingFileSystemService: FileSystemServicing {
    private struct Unused: Error {}

    private var hasEntered = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitUntilEntered() async {
        if hasEntered { return }
        await withCheckedContinuation { enteredContinuation = $0 }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func readFile(atPath path: String) async throws -> Data {
        hasEntered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        await withCheckedContinuation { releaseContinuation = $0 }
        return Data("released".utf8)
    }

    func readDirectory(atPath path: String) async throws -> [FileSystemService.DirectoryEntry] {
        throw Unused()
    }

    func stat(atPath path: String) async throws -> FileSystemService.FileStat {
        throw Unused()
    }

    func writeFile(atPath path: String, contents: Data, create: Bool, overwrite: Bool) async throws {
        throw Unused()
    }

    func createDirectory(atPath path: String) async throws {
        throw Unused()
    }

    func delete(atPath path: String, recursive: Bool, useTrash: Bool) async throws {
        throw Unused()
    }

    func rename(fromPath: String, toPath: String, overwrite: Bool) async throws {
        throw Unused()
    }
}

/// `vscode.workspace` (task 5.4c): `fs`, `workspaceFolders`, `name` and
/// `getWorkspaceFolder`, wired onto a real `ExtensionHost` and, with one
/// exception, a real `FileSystemService` — never doubles, for the same
/// reason `MainThreadCommandsTests` gives: the point of this suite is the
/// boundary between JavaScript and Swift (and, here, the real filesystem
/// underneath it), and a double for any of the three would only ever agree
/// with itself. `FileSystemService`'s own contract has never compiled or run
/// before this task — every assertion that reaches it is exercising a
/// written contract, not a previously-verified one.
///
/// The one exception is `SuspendingFileSystemService` below, used by exactly
/// one test: a genuine in-flight-disposal race needs an operation the test
/// itself can hold open, and the real actor's private queue offers no such
/// hook. `MainThreadWorkspace` holds its dependency as the `FileSystemServicing`
/// protocol precisely so that one substitution is possible without the rest
/// of this suite giving up the real filesystem.
@MainActor
@Suite
struct MainThreadWorkspaceTests {

    // MARK: - Fixtures

    private func makeTempDirectory() throws -> URL {
        try ExtensionFixtures.makeTemporaryDirectory("MainThreadWorkspaceTests")
    }

    private func manifest(name: String, browser: String) throws -> ExtensionManifest {
        let json = """
        {
            "name": "\(name)",
            "publisher": "test",
            "version": "1.0.0",
            "engines": { "vscode": "^1.74.0" },
            "browser": "\(browser)"
        }
        """
        return try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
    }

    /// Writes `source` as the extension's `browser` entry point and returns a
    /// host over the result, carrying `workspaceRoots` exactly as a real
    /// caller would — see `ExtensionHost.workspaceRoots`'s own doc for why
    /// this is a constructor parameter rather than a second, independent
    /// binding `MainThreadWorkspace` could disagree with.
    private func makeHost(
        name: String = "alpha",
        source: String,
        entryPath: String = "dist/web.js",
        in directory: URL,
        workspaceRoots: ExtensionWorkspaceRoots? = nil,
        ledger: NotImplementedLedger = NotImplementedLedger()
    ) throws -> ExtensionHost {
        try ExtensionFixtures.write(source, to: entryPath, in: directory)
        let loaded = LoadedExtension(
            manifest: try manifest(name: name, browser: entryPath),
            directory: directory
        )
        return ExtensionHost(
            loadedExtension: loaded, notImplementedLedger: ledger, workspaceRoots: workspaceRoots)
    }

    /// Installs all four of `workspace`'s members onto `host`'s
    /// `vscode.workspace` namespace, exactly as a later `ExtensionsCoordinator`
    /// task will.
    private func install(_ workspace: MainThreadWorkspace, on host: ExtensionHost) throws {
        try host.defineVSCodeMember(namespacePath: "vscode.workspace", name: "fs", implementation: workspace.fs)
        try host.defineVSCodeMember(
            namespacePath: "vscode.workspace", name: "workspaceFolders", implementation: workspace.workspaceFolders)
        try host.defineVSCodeMember(namespacePath: "vscode.workspace", name: "name", implementation: workspace.name)
        try host.defineVSCodeMember(
            namespacePath: "vscode.workspace", name: "getWorkspaceFolder",
            implementation: workspace.getWorkspaceFolder)
    }

    /// Polls `expression` until it evaluates to something other than
    /// `null`/`undefined`, or gives up after one second — the same helper
    /// `MainThreadCommandsTests` uses, for the same reason: `fs`'s promises
    /// settle from inside a `Task`, so a `.then()` reaction is a microtask,
    /// never invoked synchronously no matter how settled the promise already
    /// is by the time `evaluateScript` returns.
    private func waitForGlobal(_ context: JSContext, _ expression: String) async throws -> JSValue? {
        for _ in 0..<400 {
            if let value = context.evaluateScript(expression), !value.isNull, !value.isUndefined {
                return value
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        return nil
    }

    // MARK: - fs: each of the seven members reaches the service and resolves

    /// `readFile` reaches the real `FileSystemService`, and the bytes that
    /// come back are a genuine `Uint8Array` carrying the file's exact
    /// contents — not a plain array, not a wrapped `Data` object. Node
    /// confirmed (see the task report) that `new Uint8Array([...])` round-
    /// trips byte values exactly, including 0 and 255; this is that claim
    /// exercised through the real bridge rather than through `node`.
    @Test
    func readFileReachesTheServiceAndResolvesWithARealUint8Array() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("hello.bin")
        try Data([0, 1, 127, 128, 255]).write(to: fileURL)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.workspace.fs.readFile(vscode.Uri.file('\(fileURL.path)')).then(
                    function (bytes) {
                        globalThis.__settled = {
                            ok: true,
                            isUint8Array: bytes instanceof Uint8Array,
                            length: bytes.length,
                            values: Array.from(bytes)
                        };
                    },
                    function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                );
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("isUint8Array")?.toBool() == true)
        #expect(settled.forProperty("length")?.toInt32() == 5)
        let values = (settled.forProperty("values")?.toArray() as? [NSNumber])?.map(\.intValue)
        #expect(values == [0, 1, 127, 128, 255])
    }

    /// `writeFile` reaches the service, and the bytes actually land on disk —
    /// proof the `Uint8Array` argument was read correctly, not just accepted.
    @Test
    func writeFileReachesTheServiceAndTheBytesLandOnDisk() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("written.bin")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                var bytes = new Uint8Array([9, 8, 7, 0, 255]);
                vscode.workspace.fs.writeFile(vscode.Uri.file('\(fileURL.path)'), bytes).then(
                    function () { globalThis.__settled = { ok: true }; },
                    function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                );
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        let onDisk = try Data(contentsOf: fileURL)
        #expect([UInt8](onDisk) == [9, 8, 7, 0, 255])
    }

    /// `readDirectory` reaches the service and answers VS Code's own
    /// `[string, FileType][]` shape — two-element arrays, not `{name, type}`
    /// objects, `FileType.File` (`1`) for a plain file and `FileType.Directory`
    /// (`2`) for a directory.
    ///
    /// Lists a dedicated subdirectory (`listing/`), not the extension's own
    /// root: `makeHost` writes `dist/web.js` into `directory` itself
    /// (`ExtensionTestSupport.swift` creates `dist/` there), so listing
    /// `directory` directly always carries that extra entry alongside
    /// whatever the test wrote — asserting `length == 1` against it can never
    /// pass. Asserted as an unordered set of `name` values, not `length` plus
    /// an index-`0` lookup: `FileSystemService.readDirectory`'s own doc says
    /// its order is `FileManager`'s, unsorted, so an index-based assertion
    /// would be asserting an ordering the service's contract explicitly does
    /// not promise. Kills a mutation that drops an entry, duplicates one, or
    /// reports the wrong type bit for either child.
    @Test
    func readDirectoryReachesTheServiceAndResolvesWithTheTupleShape() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let listingURL = directory.appendingPathComponent("listing", isDirectory: true)
        try FileManager.default.createDirectory(at: listingURL, withIntermediateDirectories: true)
        try "x".write(to: listingURL.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: listingURL.appendingPathComponent("sub", isDirectory: true), withIntermediateDirectories: true)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.workspace.fs.readDirectory(vscode.Uri.file('\(listingURL.path)')).then(
                    function (entries) { globalThis.__settled = { ok: true, entries: entries }; },
                    function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                );
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        let entries = try #require(settled.forProperty("entries"))
        let length = entries.forProperty("length")?.toInt32() ?? -1
        #expect(length == 2)
        var found: Set<String> = []
        for index in 0..<max(length, 0) {
            guard let pair = entries.atIndex(Int(index)),
                  let name = pair.atIndex(0)?.toString() else { continue }
            let type = pair.atIndex(1)?.toInt32() ?? -1
            found.insert("\(name):\(type)")
        }
        #expect(found == ["a.txt:1", "sub:2"])
    }

    /// `stat` reaches the service and answers `{type, ctime, mtime, size}`,
    /// with `type` VS Code's own integer bitmask (`1` for a file), `size` the
    /// file's real byte count, and `ctime`/`mtime` real milliseconds-since-
    /// epoch values — not merely `typeof === 'number'`, a check that passes
    /// equally for `0`, `NaN`, a seconds-valued timestamp a thousand times
    /// too small, or `ctime` and `mtime` swapped outright.
    ///
    /// Each timestamp is bracketed between wall-clock millisecond readings
    /// taken immediately before and after the filesystem operation that sets
    /// it, and the two operations are separated by a real delay so the two
    /// windows do not overlap. The file is created (setting both its birth
    /// time and its modification time, `ctime`/`mtime` in VS Code's naming —
    /// see `FileSystemService.FileStat`'s own doc), then, after the delay,
    /// its content is overwritten **in place** with a plain, non-atomic
    /// `Data.write(to:)` — not `String.write(atomically: true, ...)`, which
    /// replaces the file's inode via a temp-file rename and would reset its
    /// birth time along with it, destroying the very fact this test depends
    /// on. Only the in-place write moves `mtime` into the later window while
    /// leaving `ctime` in the earlier one, which is what makes a *swap* of
    /// the two fields fail this assertion specifically, rather than only the
    /// bare magnitude checks. Kills a mutation that: drops the `* 1000` in
    /// `millisecondsSinceEpoch`; returns `0` unconditionally; or swaps
    /// `ctime`/`mtime` in `statValue`.
    @Test
    func statReachesTheServiceAndResolvesWithTheStatShape() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("sized.txt")

        let beforeCreate = Date().timeIntervalSince1970 * 1000
        try Data(repeating: 0x41, count: 7).write(to: fileURL)
        let afterCreate = Date().timeIntervalSince1970 * 1000

        try await Task.sleep(for: .milliseconds(250))

        let beforeModify = Date().timeIntervalSince1970 * 1000
        try Data(repeating: 0x42, count: 11).write(to: fileURL)
        let afterModify = Date().timeIntervalSince1970 * 1000

        // The two windows must not overlap, or a swapped ctime/mtime could
        // still land inside both brackets and this test would not catch it.
        try #require(afterCreate < beforeModify)

        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.workspace.fs.stat(vscode.Uri.file('\(fileURL.path)')).then(
                    function (stat) {
                        globalThis.__settled = {
                            ok: true, type: stat.type, size: stat.size,
                            ctime: stat.ctime, mtime: stat.mtime
                        };
                    },
                    function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                );
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("type")?.toInt32() == 1)
        #expect(settled.forProperty("size")?.toInt32() == 11)
        let ctime = settled.forProperty("ctime")?.toDouble() ?? -1
        let mtime = settled.forProperty("mtime")?.toDouble() ?? -1
        #expect(ctime >= beforeCreate && ctime <= afterCreate)
        #expect(mtime >= beforeModify && mtime <= afterModify)
    }

    /// `delete` reaches the service, and the file is actually gone afterwards.
    @Test
    func deleteReachesTheServiceAndRemovesTheFile() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("doomed.txt")
        try "gone soon".write(to: fileURL, atomically: true, encoding: .utf8)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.workspace.fs.delete(vscode.Uri.file('\(fileURL.path)')).then(
                    function () { globalThis.__settled = { ok: true }; },
                    function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                );
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    /// `rename` reaches the service, and the source is actually gone while
    /// the target actually holds the original contents.
    @Test
    func renameReachesTheServiceAndMovesTheFile() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("source.txt")
        let targetURL = directory.appendingPathComponent("target.txt")
        try "payload".write(to: sourceURL, atomically: true, encoding: .utf8)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.workspace.fs.rename(
                    vscode.Uri.file('\(sourceURL.path)'), vscode.Uri.file('\(targetURL.path)')
                ).then(
                    function () { globalThis.__settled = { ok: true }; },
                    function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                );
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(try String(contentsOf: targetURL, encoding: .utf8) == "payload")
    }

    /// `createDirectory` reaches the service, and the directory actually
    /// exists afterwards.
    @Test
    func createDirectoryReachesTheServiceAndCreatesTheDirectory() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let newDirectoryURL = directory.appendingPathComponent("nested/child", isDirectory: true)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.workspace.fs.createDirectory(vscode.Uri.file('\(newDirectoryURL.path)')).then(
                    function () { globalThis.__settled = { ok: true }; },
                    function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                );
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: newDirectoryURL.path, isDirectory: &isDirectory)
        #expect(exists && isDirectory.boolValue)
    }

    // MARK: - Error mapping: each mapped code, plus one collapsed case

    /// `readFile` on a path nothing exists at rejects with `FileNotFound` —
    /// the direct mapping from `FileSystemServiceError.fileNotFound`. Kills a
    /// mutation that drops the `case .fileNotFound: return "FileNotFound"`
    /// arm (falling through to the `Unavailable` collapse, or to `nil`).
    @Test
    func readFileOnAMissingPathRejectsWithFileNotFound() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missingURL = directory.appendingPathComponent("does-not-exist.txt")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.workspace.fs.readFile(vscode.Uri.file('\(missingURL.path)')).then(
                    function () { globalThis.__settled = { ok: true }; },
                    function (error) { globalThis.__settled = { ok: false, code: error.code }; }
                );
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(settled.forProperty("code")?.toString() == "FileNotFound")
    }

    /// `readFile` on a directory rejects with `FileIsADirectory`. Kills a
    /// mutation that drops that mapping arm.
    @Test
    func readFileOnADirectoryRejectsWithFileIsADirectory() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.workspace.fs.readFile(vscode.Uri.file('\(directory.path)')).then(
                    function () { globalThis.__settled = { ok: true }; },
                    function (error) { globalThis.__settled = { ok: false, code: error.code }; }
                );
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(settled.forProperty("code")?.toString() == "FileIsADirectory")
    }

    /// `readDirectory` on a plain file rejects with `FileNotADirectory`.
    /// Kills a mutation that drops that mapping arm.
    @Test
    func readDirectoryOnAFileRejectsWithFileNotADirectory() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("plain.txt")
        try "not a directory".write(to: fileURL, atomically: true, encoding: .utf8)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.workspace.fs.readDirectory(vscode.Uri.file('\(fileURL.path)')).then(
                    function () { globalThis.__settled = { ok: true }; },
                    function (error) { globalThis.__settled = { ok: false, code: error.code }; }
                );
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(settled.forProperty("code")?.toString() == "FileNotADirectory")
    }

    /// `createDirectory` at a path a plain file already occupies rejects with
    /// `FileExists` — the one reachable route to that case through this
    /// adaptor's handlers, since `writeFile` always overwrites (see
    /// `handleWriteFile`'s own doc) and so can never trigger it. Kills a
    /// mutation that drops that mapping arm.
    @Test
    func createDirectoryOverAnExistingFileRejectsWithFileExists() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("occupied")
        try "already here".write(to: fileURL, atomically: true, encoding: .utf8)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.workspace.fs.createDirectory(vscode.Uri.file('\(fileURL.path)')).then(
                    function () { globalThis.__settled = { ok: true }; },
                    function (error) { globalThis.__settled = { ok: false, code: error.code }; }
                );
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(settled.forProperty("code")?.toString() == "FileExists")
    }

    /// `stat` on a path nothing exists at rejects with `FileNotFound`, the
    /// same direct mapping `readFile` gets, reached through a different
    /// operation: `FileSystemService.stat` (`FileSystemService.swift:359-376`)
    /// routes `attributesOfItem`'s failure through `distinguished`, so a
    /// missing path never falls through to the generic `.statFailed` case.
    /// Kills a mutation that routes `stat`'s failure straight to
    /// `.statFailed` without consulting `distinguished` first, which would
    /// surface as `Unavailable` instead of `FileNotFound`.
    @Test
    func statOnAMissingPathRejectsWithFileNotFound() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missingURL = directory.appendingPathComponent("does-not-exist.txt")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.workspace.fs.stat(vscode.Uri.file('\(missingURL.path)')).then(
                    function () { globalThis.__settled = { ok: true }; },
                    function (error) { globalThis.__settled = { ok: false, code: error.code }; }
                );
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(settled.forProperty("code")?.toString() == "FileNotFound")
    }

    /// `readFile` on a file whose permission bits deny reading rejects with
    /// `NoPermissions` — reached via `chmod`, not a mock, so the assertion
    /// carries a real `EACCES`/`fileReadNoPermission` through
    /// `distinguished` rather than assuming the classification exists. The
    /// pre-check (`resolvedTypeBits`, which only needs the containing
    /// directory to be traversable) still succeeds against a `0o000` file, so
    /// this exercises the *second* place a permission denial can surface —
    /// the read itself, not the stat that precedes it. Restores the original
    /// mode in `defer` so the temp-directory cleanup that follows does not
    /// itself fail on an unreadable file. Kills a mutation that drops the
    /// `case .noPermissions: return "NoPermissions"` arm (falling through to
    /// the `Unavailable` collapse, or to `nil`).
    @Test
    func readFileOnAnUnreadableFileRejectsWithNoPermissions() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("locked.txt")
        try "secret".write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fileURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        }
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.workspace.fs.readFile(vscode.Uri.file('\(fileURL.path)')).then(
                    function () { globalThis.__settled = { ok: true }; },
                    function (error) { globalThis.__settled = { ok: false, code: error.code }; }
                );
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(settled.forProperty("code")?.toString() == "NoPermissions")
    }

    /// `delete` on a non-empty directory without `recursive` rejects with
    /// `Unavailable` — `FileSystemServiceError.directoryNotEmpty` has no VS
    /// Code equivalent (see `vsCodeErrorCode`'s own doc), so it collapses
    /// there along with every `*Failed` case. Kills a mutation that answers
    /// `nil`/some other string for the collapsed cases, or that accidentally
    /// maps `directoryNotEmpty` to one of the five direct codes.
    @Test
    func deleteOnANonEmptyDirectoryWithoutRecursiveRejectsWithUnavailable() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let childDirectory = directory.appendingPathComponent("has-a-child", isDirectory: true)
        try FileManager.default.createDirectory(at: childDirectory, withIntermediateDirectories: true)
        try "x".write(
            to: childDirectory.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.workspace.fs.delete(vscode.Uri.file('\(childDirectory.path)')).then(
                    function () { globalThis.__settled = { ok: true }; },
                    function (error) { globalThis.__settled = { ok: false, code: error.code }; }
                );
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(settled.forProperty("code")?.toString() == "Unavailable")
    }

    // MARK: - workspaceFolders

    /// No workspace at all (`workspaceRoots: nil`) answers `undefined` —
    /// never an empty array, per VS Code's own contract for this member.
    /// Kills a mutation that answers `[]` instead of `undefined` when there
    /// are no roots.
    @Test
    func workspaceFoldersIsUndefinedWithNoWorkspace() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__isUndefined = vscode.workspace.workspaceFolders === undefined;
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__isUndefined")?.toBool() == true)
    }

    /// One root answers a one-element array whose entry is `{uri, name,
    /// index}`, with `uri` a real `vscode.Uri` — `instanceof` and `.fsPath`
    /// both work on it, not just a property bag with a string in it. Kills a
    /// mutation that builds `uri` as a plain `{fsPath: ...}` object, or that
    /// gets `name`/`index` wrong.
    @Test
    func workspaceFoldersAnswersOneRealFolderWithARealUri() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rootURL = directory.appendingPathComponent("root-one", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let roots = TestWorkspaceRoots(displayName: nil, roots: [rootURL])
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var folders = vscode.workspace.workspaceFolders;
                globalThis.__result = {
                    length: folders.length,
                    isUri: folders[0].uri instanceof vscode.Uri,
                    fsPath: folders[0].uri.fsPath,
                    name: folders[0].name,
                    index: folders[0].index
                };
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: roots,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let result = try #require(context.evaluateScript("globalThis.__result"))
        #expect(result.forProperty("length")?.toInt32() == 1)
        #expect(result.forProperty("isUri")?.toBool() == true)
        #expect(result.forProperty("fsPath")?.toString() == rootURL.path)
        #expect(result.forProperty("name")?.toString() == rootURL.lastPathComponent)
        #expect(result.forProperty("index")?.toInt32() == 0)
    }

    /// A workspace root nested several directories deep also answers a
    /// `fsPath` free of a trailing slash, matching `URL.path` exactly — not
    /// just a directory one level under the test's temp root. Every
    /// `appendingPathComponent` step below is built `isDirectory: true`,
    /// which is what puts a trailing slash in `absoluteString` in the first
    /// place; a fix that only special-cased a shallow root, or that happened
    /// to work by accident for one depth, would not survive this. Kills a
    /// mutation that reintroduces the trailing slash for any root whose path
    /// has more than one component below the workspace's own temp directory.
    @Test
    func workspaceFoldersAnswersANestedRootWithATrailingSlashFreeFsPath() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let nestedRootURL = directory
            .appendingPathComponent("workspace", isDirectory: true)
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedRootURL, withIntermediateDirectories: true)
        let roots = TestWorkspaceRoots(displayName: nil, roots: [nestedRootURL])
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__fsPath = vscode.workspace.workspaceFolders[0].uri.fsPath;
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: roots,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let fsPath = context.evaluateScript("globalThis.__fsPath")?.toString()
        #expect(fsPath == nestedRootURL.path)
        #expect(fsPath?.hasSuffix("/") == false)
    }

    /// A root whose own literal path already begins `/private/` still
    /// answers a `fsPath` with that prefix intact — the case neither test
    /// above reaches, because both build their root under
    /// `FileManager.default.temporaryDirectory`, which is already
    /// `/var/folders/...` and so is untouched by `standardizedFileURL`
    /// either way. `standardizedFileURL` strips a leading `/private` **only
    /// when the collapsed result currently exists on disk** — measured
    /// against Foundation directly, not assumed — so this fixture creates
    /// `root-private` at its literal `/private/...` path before asserting
    /// anything, via `#require`: without that precondition, a regression to
    /// `standardizedFileURL` would find the collapsed `/var/...` path does
    /// not exist, strip nothing, and pass this test for the wrong reason —
    /// vacuously, exactly as the brief warned.
    ///
    /// Two mutations, one each: `fsPath == privateRoot.path` kills a
    /// revert of `workspaceFolderValue` back to
    /// `url.standardizedFileURL.path`, since standardizing this real,
    /// on-disk `/private` root collapses it to `/var/folders/...` and the
    /// equality fails. `fsPath.hasPrefix("/private/")` kills a narrower
    /// mutation that strips a leading `/private/` some other way (a
    /// hand-written `replacingOccurrences`, say) while still passing the
    /// first assertion by coincidence on a differently-shaped path.
    @Test
    func workspaceFoldersAnswersAPrivatePrefixedRootWithThePrefixIntact() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let privateRoot = URL(fileURLWithPath: "/private" + directory.path, isDirectory: true)
            .appendingPathComponent("root-private", isDirectory: true)
        try FileManager.default.createDirectory(at: privateRoot, withIntermediateDirectories: true)
        try #require(FileManager.default.fileExists(atPath: privateRoot.path))
        let roots = TestWorkspaceRoots(displayName: nil, roots: [privateRoot])
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__fsPath = vscode.workspace.workspaceFolders[0].uri.fsPath;
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: roots,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let fsPath = context.evaluateScript("globalThis.__fsPath")?.toString()
        #expect(fsPath == privateRoot.path)
        #expect(fsPath?.hasPrefix("/private/") == true)
    }

    // MARK: - name

    /// `vscode.workspace.name` answers the display name a real workspace
    /// carries.
    @Test
    func nameAnswersTheDisplayNameWhenAWorkspaceIsOpen() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let roots = TestWorkspaceRoots(displayName: "My Project", roots: [directory])
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__name = vscode.workspace.name;
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: roots,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__name")?.toString() == "My Project")
    }

    /// No workspace at all answers `undefined` for `name` — not `null`, not
    /// an empty string. Kills a mutation that bridges the absent case as
    /// `null` (a bare Swift `nil` boxed in `Any`, per `VSCodeAPI
    /// .resolvedPromise`'s own doc comment on why that collapses to `NSNull`
    /// rather than genuine `undefined`).
    @Test
    func nameIsUndefinedWithNoWorkspace() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__isUndefined = vscode.workspace.name === undefined;
                globalThis.__isNull = vscode.workspace.name === null;
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__isUndefined")?.toBool() == true)
        #expect(context.evaluateScript("globalThis.__isNull")?.toBool() == false)
    }

    // MARK: - getWorkspaceFolder

    /// A file directly inside a root answers that root's folder object — the
    /// same object `workspaceFolders` itself produced (`===`, not merely
    /// equal fields).
    @Test
    func getWorkspaceFolderAnswersTheContainingRootForAFileInsideIt() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rootURL = directory.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileURL = rootURL.appendingPathComponent("inside.txt")
        try "x".write(to: fileURL, atomically: true, encoding: .utf8)
        let roots = TestWorkspaceRoots(displayName: nil, roots: [rootURL])
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var folders = vscode.workspace.workspaceFolders;
                var found = vscode.workspace.getWorkspaceFolder(vscode.Uri.file('\(fileURL.path)'));
                globalThis.__result = { sameObject: found === folders[0], name: found.name };
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: roots,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let result = try #require(context.evaluateScript("globalThis.__result"))
        #expect(result.forProperty("sameObject")?.toBool() == true)
        #expect(result.forProperty("name")?.toString() == "root")
    }

    /// The longest-prefix case: a nested root inside an outer one wins for a
    /// file under the nested root, not the outer root that also contains it.
    /// Kills a mutation that picks the *first* matching root (registration
    /// order) rather than the longest, or that matches `/outer/inner-extra`
    /// against root `/outer/inner` on the string prefix alone rather than at
    /// a path-component boundary.
    @Test
    func getWorkspaceFolderPicksTheLongestMatchingRoot() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outerURL = directory.appendingPathComponent("outer", isDirectory: true)
        let innerURL = outerURL.appendingPathComponent("inner", isDirectory: true)
        // A sibling whose name is the nested root's name plus a suffix, so a
        // naive string-prefix match (rather than a path-component boundary
        // one) would wrongly treat a file under it as being inside `inner`.
        let innerExtraURL = outerURL.appendingPathComponent("inner-extra", isDirectory: true)
        try FileManager.default.createDirectory(at: innerURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: innerExtraURL, withIntermediateDirectories: true)
        let nestedFileURL = innerURL.appendingPathComponent("deep.txt")
        try "x".write(to: nestedFileURL, atomically: true, encoding: .utf8)
        let siblingFileURL = innerExtraURL.appendingPathComponent("shallow.txt")
        try "x".write(to: siblingFileURL, atomically: true, encoding: .utf8)
        // Outer registered first: a mutation that returns the first match
        // rather than the longest would still pass if the nested root were
        // registered first, so registration order is deliberately the
        // opposite of the expected answer.
        let roots = TestWorkspaceRoots(displayName: nil, roots: [outerURL, innerURL])
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var nested = vscode.workspace.getWorkspaceFolder(vscode.Uri.file('\(nestedFileURL.path)'));
                var sibling = vscode.workspace.getWorkspaceFolder(vscode.Uri.file('\(siblingFileURL.path)'));
                globalThis.__result = { nestedName: nested.name, siblingName: sibling.name };
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: roots,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let result = try #require(context.evaluateScript("globalThis.__result"))
        #expect(result.forProperty("nestedName")?.toString() == "inner")
        // The sibling is not inside `inner` (only inside `outer`), despite
        // its name sharing `inner`'s name as a string prefix.
        #expect(result.forProperty("siblingName")?.toString() == "outer")
    }

    /// A file outside every root answers `undefined`.
    @Test
    func getWorkspaceFolderAnswersUndefinedForAFileOutsideEveryRoot() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rootURL = directory.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let outsideURL = directory.appendingPathComponent("elsewhere.txt")
        try "x".write(to: outsideURL, atomically: true, encoding: .utf8)
        let roots = TestWorkspaceRoots(displayName: nil, roots: [rootURL])
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var found = vscode.workspace.getWorkspaceFolder(vscode.Uri.file('\(outsideURL.path)'));
                globalThis.__isUndefined = found === undefined;
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: roots,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__isUndefined")?.toBool() == true)
    }

    // MARK: - Undefined member stays a throwing stub

    /// A `vscode.workspace` member this task did not implement (a stand-in
    /// for `onDidChangeWorkspaceFolders`, `openTextDocument`, and every other
    /// member the shim's `makeStubNamespace` proxy still owns) still throws
    /// `NotImplementedError` and is recorded in the ledger — implementing
    /// four members must not accidentally satisfy the proxy trap for a fifth.
    @Test
    func anUnimplementedWorkspaceMemberRemainsAThrowingStub() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = NotImplementedLedger()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__err = null;
                try {
                    vscode.workspace.openTextDocument('\\/tmp\\/anything.txt');
                } catch (error) {
                    globalThis.__err = error.name;
                }
            };
            """,
            in: directory,
            ledger: ledger
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__err")?.toString() == "NotImplementedError")
        #expect(ledger.accesses.map(\.memberPath) == ["vscode.workspace.openTextDocument"])
    }

    /// A `vscode.workspace.fs` member this task did not implement (`copy`
    /// stands in for it, and for `isWritableFileSystem` and everything else
    /// `subNamespace`'s own stub still owns) still throws
    /// `NotImplementedError` **and** is recorded in the ledger under
    /// `vscode.workspace.fs.copy` — the fix for the fix brief's item 3.
    /// Before that fix, `fs`'s `subNamespace` call passed `recordMiss: nil,
    /// recordProbe: nil`: the throw still happened (it is unconditional in
    /// the shim's `get` trap), but nothing under `fs` ever reached the
    /// ledger.
    ///
    /// The fixture probes before it calls: `'copy' in vscode.workspace.fs`
    /// first, then `vscode.workspace.fs.copy(...)`. `copy` is not in `fs`'s
    /// stub `members` table and not in the shim's `PROBE_KEYS`
    /// (`VSCodeAPI.swift`'s `has` trap), so the `in` check reaches
    /// `recordNegativeProbe` and genuinely bumps `probeCount`, landing on the
    /// same row the later `get` miss bumps `count` on
    /// (`NotImplementedLedger.bump` keys both on `(extensionIdentifier,
    /// memberPath)`, so a probe and a miss on the same member share one row,
    /// not two). Asserting the row whole — `count == 1`, `probeCount == 1`,
    /// `extensionIdentifier == host.identifier` — is what actually kills a
    /// mutation that reverts `recordMiss` or `recordProbe` to `nil` in
    /// `MainThreadWorkspace.fs` (either would leave its own counter at `0`
    /// instead of `1` on this row, where the prior assertion, reading only
    /// `memberPath`, saw no difference), or that wires either closure to the
    /// wrong `extensionIdentifier`.
    @Test
    func anUnimplementedFsMemberThrowsAndIsRecordedInTheLedger() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__probed = 'copy' in vscode.workspace.fs;
                globalThis.__err = null;
                try {
                    vscode.workspace.fs.copy('\\/tmp\\/a.txt', '\\/tmp\\/b.txt');
                } catch (error) {
                    globalThis.__err = error.name;
                }
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__probed")?.toBool() == false)
        #expect(context.evaluateScript("globalThis.__err")?.toString() == "NotImplementedError")
        let accesses = host.notImplementedLedger.accesses
        #expect(accesses.count == 1)
        let access = try #require(accesses.first)
        #expect(access.memberPath == "vscode.workspace.fs.copy")
        #expect(access.extensionIdentifier == host.identifier)
        #expect(access.count == 1)
        #expect(access.probeCount == 1)
    }

    // MARK: - Teardown: an in-flight operation rejects rather than crashing

    /// Disposing `MainThreadWorkspace` before the `Task` behind a pending
    /// `fs` operation has had its first turn on the run loop leaves that
    /// operation's promise rejecting — with the same "torn down" wording
    /// `VSCodeAPI.member`'s own teardown path uses — rather than delivering a
    /// result to (or crashing) an adaptor the caller has already abandoned.
    ///
    /// `dispose()` is called synchronously, immediately after the `then` is
    /// attached and before control returns to the run loop, so this
    /// specifically exercises `runFileSystemOperation`'s *first* teardown
    /// check (`guard let self, !self.isDisposed else { … }`, before
    /// `operation()` ever runs) — not the second one after `operation()`
    /// completes, which this test's real `FileSystemService` resolves too
    /// fast to reach mid-flight. `disposingWhileAnOperationIsGenuinelySuspendedRejectsRatherThanDeliveringAResult`
    /// below is the other half of this pair: it uses
    /// `SuspendingFileSystemService` to hold `operation()` open across
    /// `dispose()` and exercises that second, post-`await` guard instead.
    /// Kills a mutation that removes or weakens *this* test's first guard:
    /// without it, `operation()` runs to completion and the promise resolves
    /// with the file's real contents instead of rejecting.
    @Test
    func disposingWhileAnOperationIsInFlightRejectsRatherThanCrashing() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("in-flight.txt")
        try "still here".write(to: fileURL, atomically: true, encoding: .utf8)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                globalThis.run = function () {
                    vscode.workspace.fs.readFile(vscode.Uri.file('\(fileURL.path)')).then(
                        function () { globalThis.__settled = { ok: true }; },
                        function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                    );
                };
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier
        )
        defer { host.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.run();")
        // Disposed before the `Task` behind that call has had a single turn
        // on the run loop — no `await` has happened yet on this line.
        workspace.dispose()

        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(settled.forProperty("message")?.toString()?.contains("torn down") == true)
    }

    /// The other half of teardown: disposed **while an operation is
    /// genuinely suspended mid-`await`**, not merely before its `Task` has
    /// had a first turn. `SuspendingFileSystemService.readFile` suspends on
    /// a continuation the test holds; the test waits for the operation to
    /// actually enter that suspension (`waitUntilEntered()`, not a delay),
    /// disposes the workspace while it is still suspended there, and only
    /// then releases it. `operation()` therefore completes successfully
    /// *after* disposal, and the promise must still reject rather than
    /// deliver `readFile`'s real result or crash.
    ///
    /// This is the fix for the fix brief's item 5, and it exercises exactly
    /// the guard item 4 rewrote: `runFileSystemOperation`'s post-`await`
    /// `guard !self.isDisposed, let resultContext = …`. Kills a mutation
    /// that removes or weakens that `!self.isDisposed` check — without it,
    /// this test would observe `ok: true` with `readFile`'s real (fabricated)
    /// contents instead of a "torn down" rejection.
    @Test
    func disposingWhileAnOperationIsGenuinelySuspendedRejectsRatherThanDeliveringAResult() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suspending = SuspendingFileSystemService()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                globalThis.run = function () {
                    vscode.workspace.fs.readFile(vscode.Uri.file('/does/not/matter.txt')).then(
                        function () { globalThis.__settled = { ok: true }; },
                        function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                    );
                };
            };
            """,
            in: directory
        )
        let workspace = MainThreadWorkspace(
            workspaceRoots: nil,
            notImplementedLedger: host.notImplementedLedger,
            extensionIdentifier: host.identifier,
            fileSystemService: suspending
        )
        defer { host.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.run();")
        await suspending.waitUntilEntered()
        // `readFile` is now suspended inside `operation()`, past the
        // pre-flight guard and before the post-await guard has run.
        workspace.dispose()
        await suspending.release()

        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(settled.forProperty("message")?.toString()?.contains("torn down") == true)
    }
}
