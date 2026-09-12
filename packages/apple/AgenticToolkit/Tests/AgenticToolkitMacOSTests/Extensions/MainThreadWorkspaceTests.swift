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

/// `vscode.workspace` (task 5.4c): `fs`, `workspaceFolders`, `name` and
/// `getWorkspaceFolder`, wired onto a real `ExtensionHost` and a real
/// `FileSystemService` — never doubles, for the same reason
/// `MainThreadCommandsTests` gives: the point of this suite is the boundary
/// between JavaScript and Swift (and, here, the real filesystem underneath
/// it), and a double for any of the three would only ever agree with itself.
/// `FileSystemService`'s own contract has never compiled or run before this
/// task — every assertion that reaches it is exercising a written contract,
/// not a previously-verified one.
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
        let workspace = MainThreadWorkspace(workspaceRoots: nil)
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
        let workspace = MainThreadWorkspace(workspaceRoots: nil)
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
    /// objects, and `FileType.File` (`1`) for a plain file.
    @Test
    func readDirectoryReachesTheServiceAndResolvesWithTheTupleShape() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try "x".write(to: directory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let workspace = MainThreadWorkspace(workspaceRoots: nil)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.workspace.fs.readDirectory(vscode.Uri.file('\(directory.path)')).then(
                    function (entries) { globalThis.__settled = { ok: true, entries: entries }; },
                    function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                );
            };
            """,
            in: directory
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        let entries = try #require(settled.forProperty("entries"))
        #expect(entries.forProperty("length")?.toInt32() == 1)
        let first = entries.atIndex(0)
        #expect(first?.atIndex(0)?.toString() == "a.txt")
        #expect(first?.atIndex(1)?.toInt32() == 1)
    }

    /// `stat` reaches the service and answers `{type, ctime, mtime, size}`,
    /// with `type` VS Code's own integer bitmask (`1` for a file) and `size`
    /// the file's real byte count.
    @Test
    func statReachesTheServiceAndResolvesWithTheStatShape() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("sized.txt")
        try Data(repeating: 0x41, count: 7).write(to: fileURL)
        let workspace = MainThreadWorkspace(workspaceRoots: nil)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.workspace.fs.stat(vscode.Uri.file('\(fileURL.path)')).then(
                    function (stat) {
                        globalThis.__settled = {
                            ok: true, type: stat.type, size: stat.size,
                            ctimeIsNumber: typeof stat.ctime === 'number',
                            mtimeIsNumber: typeof stat.mtime === 'number'
                        };
                    },
                    function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                );
            };
            """,
            in: directory
        )
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("type")?.toInt32() == 1)
        #expect(settled.forProperty("size")?.toInt32() == 7)
        #expect(settled.forProperty("ctimeIsNumber")?.toBool() == true)
        #expect(settled.forProperty("mtimeIsNumber")?.toBool() == true)
    }

    /// `delete` reaches the service, and the file is actually gone afterwards.
    @Test
    func deleteReachesTheServiceAndRemovesTheFile() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("doomed.txt")
        try "gone soon".write(to: fileURL, atomically: true, encoding: .utf8)
        let workspace = MainThreadWorkspace(workspaceRoots: nil)
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
        let workspace = MainThreadWorkspace(workspaceRoots: nil)
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
        let workspace = MainThreadWorkspace(workspaceRoots: nil)
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
        let workspace = MainThreadWorkspace(workspaceRoots: nil)
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
        let workspace = MainThreadWorkspace(workspaceRoots: nil)
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
        let workspace = MainThreadWorkspace(workspaceRoots: nil)
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
        let workspace = MainThreadWorkspace(workspaceRoots: nil)
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
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(settled.forProperty("code")?.toString() == "FileExists")
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
        let workspace = MainThreadWorkspace(workspaceRoots: nil)
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
        let workspace = MainThreadWorkspace(workspaceRoots: nil)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__isUndefined = vscode.workspace.workspaceFolders === undefined;
            };
            """,
            in: directory
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
        let workspace = MainThreadWorkspace(workspaceRoots: roots)
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

    // MARK: - name

    /// `vscode.workspace.name` answers the display name a real workspace
    /// carries.
    @Test
    func nameAnswersTheDisplayNameWhenAWorkspaceIsOpen() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let roots = TestWorkspaceRoots(displayName: "My Project", roots: [directory])
        let workspace = MainThreadWorkspace(workspaceRoots: roots)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__name = vscode.workspace.name;
            };
            """,
            in: directory
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
        let workspace = MainThreadWorkspace(workspaceRoots: nil)
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
        let workspace = MainThreadWorkspace(workspaceRoots: roots)
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
        let workspace = MainThreadWorkspace(workspaceRoots: roots)
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
        let workspace = MainThreadWorkspace(workspaceRoots: roots)
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
        let workspace = MainThreadWorkspace(workspaceRoots: nil)
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
        defer { host.dispose(); workspace.dispose() }
        try install(workspace, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__err")?.toString() == "NotImplementedError")
        #expect(ledger.accesses.map(\.memberPath) == ["vscode.workspace.openTextDocument"])
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
    /// completes, which a synchronous test cannot force without a mock
    /// `FileSystemService` this task does not have. Kills a mutation that
    /// removes or weakens that first guard: without it, `operation()` runs
    /// to completion and the promise resolves with the file's real contents
    /// instead of rejecting.
    @Test
    func disposingWhileAnOperationIsInFlightRejectsRatherThanCrashing() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("in-flight.txt")
        try "still here".write(to: fileURL, atomically: true, encoding: .utf8)
        let workspace = MainThreadWorkspace(workspaceRoots: nil)
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
}
