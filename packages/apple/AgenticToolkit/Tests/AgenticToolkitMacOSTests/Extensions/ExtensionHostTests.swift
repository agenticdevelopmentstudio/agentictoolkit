import Testing
import Foundation
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// Collects what an extension wrote to `console`.
///
/// A reference type rather than a captured `var`, because the closure that
/// fills it is stored on the host and called back later — from a timer, in the
/// tests that matter most. `@MainActor` for the same reason the host is: the
/// callback arrives there and nowhere else.
@MainActor
private final class ConsoleRecorder {

    private(set) var messages: [ExtensionConsoleMessage] = []

    var texts: [String] { messages.map(\.text) }

    func attach(to host: ExtensionHost) {
        host.onConsoleMessage = { [self] message in
            messages.append(message)
        }
    }
}

/// The JavaScriptCore extension host.
///
/// Every test builds a real extension directory on disk and runs real
/// JavaScript through a real `JSContext`. Nothing here is faked: the point of
/// this suite is the boundary between Swift and JavaScript, and a double for
/// either side would only ever agree with itself.
///
/// Not `.serialized` — each test owns its own temporary directory and its own
/// host, and the hosts share only a `JSVirtualMachine`, which is what
/// JavaScriptCore is for.
@MainActor
@Suite
struct ExtensionHostTests {

    // MARK: - Fixtures

    private func makeTempDirectory() throws -> URL {
        try ExtensionFixtures.makeTemporaryDirectory("ExtensionHostTests")
    }

    /// A manifest with whichever entry-point keys the caller names. Built by
    /// decoding JSON, because `ExtensionManifest` has no memberwise
    /// initializer and inventing one for tests would be a second answer to
    /// what a manifest is.
    private func manifest(
        name: String,
        browser: String? = nil,
        main: String? = nil
    ) throws -> ExtensionManifest {
        var entries: [String] = []
        if let browser { entries.append("\"browser\": \"\(browser)\"") }
        if let main { entries.append("\"main\": \"\(main)\"") }
        let entryJSON = entries.isEmpty ? "" : ",\n    \(entries.joined(separator: ",\n    "))"
        let json = """
        {
            "name": "\(name)",
            "publisher": "test",
            "version": "1.0.0",
            "engines": { "vscode": "^1.74.0" }\(entryJSON)
        }
        """
        return try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
    }

    /// Writes `source` as the extension's `browser` entry point and returns a
    /// host over the result.
    private func makeHost(
        name: String = "alpha",
        source: String,
        entryPath: String = "dist/web.js",
        in directory: URL,
        ledger: NotImplementedLedger = NotImplementedLedger()
    ) throws -> ExtensionHost {
        try ExtensionFixtures.write(source, to: entryPath, in: directory)
        let loaded = LoadedExtension(
            manifest: try manifest(name: name, browser: entryPath),
            directory: directory
        )
        return ExtensionHost(loadedExtension: loaded, notImplementedLedger: ledger)
    }

    // MARK: - Activation

    @Test
    func anExtensionWithABrowserEntryPointActivates() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = function () {
                console.log('activate ran');
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()

        #expect(host.isActivated)
        #expect(recorder.texts == ["activate ran"])
    }

    /// `module.exports = { activate }` is the other spelling extensions ship,
    /// and an extension that used it would export nothing if the wrapper only
    /// honoured `exports.x`.
    @Test
    func moduleExportsAssignmentIsHonouredAsWellAsExportsMembers() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            module.exports = {
                activate: function () { console.log('module.exports ran'); }
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()

        #expect(recorder.texts == ["module.exports ran"])
    }

    /// Activation is idempotent: `activate()` twice runs the module once. A
    /// second evaluation would leave a second set of registrations behind that
    /// one `dispose()` could not undo.
    @Test
    func activatingTwiceRunsTheExtensionOnce() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: "console.log('top level'); exports.activate = function () {};",
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()
        try await host.activate()

        #expect(recorder.texts == ["top level"])
    }

    // MARK: - Entry point selection

    @Test
    func anExtensionWithOnlyAMainEntryPointIsRefusedAsNeedingNode() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try ExtensionFixtures.write("exports.activate = function () {};", to: "out/node.js", in: directory)
        let loaded = LoadedExtension(
            manifest: try manifest(name: "nodey", main: "out/node.js"),
            directory: directory
        )
        let host = ExtensionHost(loadedExtension: loaded)
        defer { host.dispose() }

        // The refusal is by *kind*, not a generic load failure: the case names
        // the declared `main` so a report can quote it back.
        await #expect(throws: ExtensionHostError.requiresNodeRuntime(
            identifier: "test.nodey", declaredMain: "out/node.js")) {
            try await host.activate()
        }

        // And the message a user sees has to carry the distinction, not just
        // the enum case.
        let described = ExtensionHostError
            .requiresNodeRuntime(identifier: "test.nodey", declaredMain: "out/node.js")
            .localizedDescription
        #expect(described.contains("Node"))
        #expect(described.contains("browser"))
        #expect(described.contains("out/node.js"))
        #expect(!host.isActivated)
    }

    /// Neither key is a different fact from "the wrong kind of extension", and
    /// gets its own case so a report never tells an author to add a `browser`
    /// entry point they already have.
    @Test
    func anExtensionDeclaringNoCodeIsRefusedSeparately() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let loaded = LoadedExtension(manifest: try manifest(name: "codeless"), directory: directory)
        let host = ExtensionHost(loadedExtension: loaded)
        defer { host.dispose() }

        await #expect(throws: ExtensionHostError.noEntryPoint(identifier: "test.codeless")) {
            try await host.activate()
        }
    }

    /// The containment check, with its premise pinned.
    ///
    /// Task 4.6 round 3 taught this the hard way: `URL(fileURLWithPath:)`
    /// consults the file system, so a decoy that does not exist can make the
    /// resolution itself go a different way and the test passes while proving
    /// nothing. So the decoy here is a real, readable file whose reachability
    /// is asserted *before* the refusal is — and the refusal is asserted to
    /// name that exact resolved path, which is the only way to know the check
    /// looked at the escape rather than at something else.
    @Test
    func aBrowserEntryPointOutsideTheExtensionDirectoryIsRefused() async throws {
        let parent = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }

        let extensionDirectory = parent.appendingPathComponent("ext", isDirectory: true)
        try FileManager.default.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
        try ExtensionFixtures.write("console.log('decoy ran');", to: "outside/evil.js", in: parent)

        // Premise 1: the decoy exists and is readable. Written and read by a
        // route the subject does not use, so it cannot agree with the subject
        // by construction.
        let decoy = parent.appendingPathComponent("outside/evil.js")
        #expect(FileManager.default.isReadableFile(atPath: decoy.path))

        // Premise 2: the escape really does resolve to the decoy. Without
        // this, a refusal could be a refusal of some other path entirely.
        let escaped = URL(fileURLWithPath: "../outside/evil.js", relativeTo: extensionDirectory)
            .resolvingSymlinksInPath().standardizedFileURL
        let canonicalDecoy = decoy.resolvingSymlinksInPath().standardizedFileURL
        #expect(escaped.path == canonicalDecoy.path)

        let loaded = LoadedExtension(
            manifest: try manifest(name: "escaper", browser: "../outside/evil.js"),
            directory: extensionDirectory
        )
        let host = ExtensionHost(loadedExtension: loaded)
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        await #expect(throws: ExtensionHostError.entryPointEscapesExtensionDirectory(
            identifier: "test.escaper",
            declared: "../outside/evil.js",
            resolved: canonicalDecoy.path
        )) {
            try await host.activate()
        }
        // The behaviour that matters, stated directly: the decoy's code never ran.
        #expect(recorder.texts.isEmpty)
        #expect(!host.isActivated)
    }

    /// A sibling directory whose name merely *starts* with the extension
    /// directory's name. A containment check written on string prefixes lets
    /// this through, and the attacker picks the name.
    @Test
    func aSiblingDirectoryWithASharedNamePrefixDoesNotCountAsInside() async throws {
        let parent = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }

        let extensionDirectory = parent.appendingPathComponent("ext", isDirectory: true)
        try FileManager.default.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
        try ExtensionFixtures.write("console.log('sibling ran');", to: "ext-evil/web.js", in: parent)

        let decoy = parent.appendingPathComponent("ext-evil/web.js")
        #expect(FileManager.default.isReadableFile(atPath: decoy.path))

        let loaded = LoadedExtension(
            manifest: try manifest(name: "sibling", browser: "../ext-evil/web.js"),
            directory: extensionDirectory
        )
        let host = ExtensionHost(loadedExtension: loaded)
        defer { host.dispose() }

        await #expect(throws: ExtensionHostError.self) {
            try await host.activate()
        }
    }

    // MARK: - Failure in the extension's own code

    @Test
    func aTopLevelThrowIsCaughtAndReported() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: "throw new Error('the extension exploded');",
            in: directory
        )
        defer { host.dispose() }

        do {
            try await host.activate()
            Issue.record("A top-level throw must not activate.")
        } catch let error as ExtensionHostError {
            guard case let .entryPointThrew(identifier, message) = error else {
                Issue.record("Expected entryPointThrew, got \(error)")
                return
            }
            #expect(identifier == "test.alpha")
            #expect(message.contains("the extension exploded"))
        }
        #expect(!host.isActivated)
    }

    /// A throw from `activate()` is a different case from a throw while
    /// loading: the module did evaluate, and a report that conflated the two
    /// would send an author to the wrong half of their file.
    @Test
    func aThrowFromActivateIsReportedSeparately() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: "exports.activate = function () { throw new Error('activate exploded'); };",
            in: directory
        )
        defer { host.dispose() }

        do {
            try await host.activate()
            Issue.record("A throw from activate() must surface.")
        } catch let error as ExtensionHostError {
            guard case let .activationThrew(_, message) = error else {
                Issue.record("Expected activationThrew, got \(error)")
                return
            }
            #expect(message.contains("activate exploded"))
        }
    }

    // MARK: - Teardown

    /// Teardown is only real if it stops the clock.
    ///
    /// The positive control is the load-bearing half: a test that only
    /// asserted "nothing fired after dispose" would pass just as happily
    /// against a host whose timers never fire at all.
    @Test
    func teardownCancelsAPendingTimer() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = """
        exports.activate = function () {
            setTimeout(function () { console.log('timer fired'); }, 60);
        };
        """

        // Control: the same timer, on a host nobody disposes, does fire.
        let controlDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: controlDirectory) }
        let control = try makeHost(name: "control", source: source, in: controlDirectory)
        defer { control.dispose() }
        let controlRecorder = ConsoleRecorder()
        controlRecorder.attach(to: control)
        try await control.activate()
        try await Task.sleep(for: .milliseconds(400))
        #expect(controlRecorder.texts == ["timer fired"])

        // The subject: disposed before the timer comes due.
        let host = try makeHost(source: source, in: directory)
        let recorder = ConsoleRecorder()
        recorder.attach(to: host)
        try await host.activate()
        host.dispose()

        try await Task.sleep(for: .milliseconds(400))
        #expect(recorder.texts.isEmpty)
        #expect(host.isDisposed)
    }

    /// A repeating timer is the case a "fire once then forget" teardown misses.
    @Test
    func teardownCancelsARepeatingTimer() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = function () {
                setInterval(function () { console.log('tick'); }, 30);
            };
            """,
            in: directory
        )
        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()
        try await Task.sleep(for: .milliseconds(200))
        let ticksBeforeTeardown = recorder.texts.count
        #expect(ticksBeforeTeardown > 0)

        host.dispose()
        try await Task.sleep(for: .milliseconds(300))
        #expect(recorder.texts.count == ticksBeforeTeardown)
    }

    /// The half of teardown no callback can show you.
    ///
    /// Written because a mutation found the hole: deleting `task.cancel()` from
    /// `dispose()` killed nothing, since a disposed host's timer declines to
    /// fire for two other reasons anyway. What cancellation buys is that the
    /// task stops *now* — and with a ten-second period, "it woke up and decided
    /// not to fire" is not an explanation available to a test that finishes in
    /// half a second.
    @Test
    func teardownStopsTheClockRatherThanOnlyDecliningToFire() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = function () {
                setInterval(function () { console.log('tick'); }, 10000);
            };
            """,
            in: directory
        )
        try await host.activate()
        #expect(host.runningTimerCount == 1)

        host.dispose()

        // Cancellation makes the pending `Task.sleep` throw at once, so the
        // task finishes within a few scheduling hops. An uncancelled one is
        // still asleep, and stays asleep for the rest of its ten seconds.
        var attempts = 0
        while host.runningTimerCount != 0 && attempts < 50 {
            try await Task.sleep(for: .milliseconds(10))
            attempts += 1
        }
        #expect(host.runningTimerCount == 0)
    }

    /// The counter is not write-only: a one-shot timer that fires normally
    /// takes it back down too, so a zero after teardown means something.
    @Test
    func aTimerThatFiresNormallyStopsBeingCounted() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = function () {
                setTimeout(function () { console.log('fired'); }, 20);
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()
        #expect(host.runningTimerCount == 1)

        try await Task.sleep(for: .milliseconds(300))

        #expect(recorder.texts == ["fired"])
        #expect(host.runningTimerCount == 0)
    }

    /// `clearTimeout` from inside the extension reaches the Swift clock, not
    /// just the shim's own table.
    @Test
    func clearTimeoutStopsATimerBeforeItFires() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = function () {
                var id = setTimeout(function () { console.log('should not fire'); }, 60);
                setTimeout(function () { console.log('kept'); }, 60);
                clearTimeout(id);
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()
        try await Task.sleep(for: .milliseconds(400))

        #expect(recorder.texts == ["kept"])
    }

    // MARK: - console

    @Test
    func consoleLogOfAnObjectArrivesReadable() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = function () {
                console.log({ a: 1, b: 'two' });
                console.warn('count', [1, 2, 3]);
                console.error(new Error('boom'));
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()

        #expect(recorder.texts.first == "{ a: 1, b: \"two\" }")
        #expect(recorder.messages.first?.level == .log)
        #expect(recorder.texts.count == 3)
        #expect(recorder.texts[1] == "count [ 1, 2, 3 ]")
        #expect(recorder.messages[1].level == .warn)
        #expect(recorder.texts[2].contains("Error: boom"))
        #expect(recorder.messages[2].level == .error)
        #expect(recorder.messages.allSatisfy { $0.extensionIdentifier == "test.alpha" })
    }

    // MARK: - require

    @Test
    func requiringAnythingButVSCodeThrowsAndNamesTheSpecifier() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: "var fs = require('node:fs');",
            in: directory
        )
        defer { host.dispose() }

        do {
            try await host.activate()
            Issue.record("require of an unresolvable specifier must throw.")
        } catch let error as ExtensionHostError {
            guard case let .entryPointThrew(_, message) = error else {
                Issue.record("Expected entryPointThrew, got \(error)")
                return
            }
            #expect(message.contains("node:fs"))
            #expect(message.contains("Cannot find module"))
        }
    }

    @Test
    func requiringVSCodeResolves() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                console.log(typeof vscode);
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()

        #expect(recorder.texts == ["object"])
    }

    // MARK: - The NotImplemented contract

    /// The load-bearing test of this task.
    ///
    /// Three things at once, because they are one contract: the member access
    /// throws rather than answering `undefined`, the error names the *full*
    /// path (not the namespace it stopped traversing at), and the ledger holds
    /// one row for three reaches rather than three rows or one reach.
    @Test
    func anUnimplementedVSCodeMemberThrowsNamesItselfAndIsRecordedOnce() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let ledger = NotImplementedLedger()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                for (var i = 0; i < 3; i += 1) {
                    try {
                        vscode.commands.registerCommand('x', function () {});
                    } catch (error) {
                        console.log(error.name + '|' + error.message);
                    }
                }
            };
            """,
            in: directory,
            ledger: ledger
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()

        #expect(recorder.texts.count == 3)
        let first = try #require(recorder.texts.first)
        #expect(first.hasPrefix("NotImplementedError|"))
        #expect(first.contains("vscode.commands.registerCommand"))
        #expect(first.contains("not implemented yet"))

        let accesses = ledger.accesses
        #expect(accesses.count == 1)
        let access = try #require(accesses.first)
        #expect(access.memberPath == "vscode.commands.registerCommand")
        #expect(access.extensionIdentifier == "test.alpha")
        #expect(access.count == 3)
        #expect(ledger.accesses(for: "test.alpha").count == 1)
        #expect(ledger.accesses(for: "someone.else").isEmpty)
    }

    /// The stamp is the *first* access, not the latest.
    ///
    /// Task 5.8's question is whether the extension tripped on a member during
    /// activation or only later, and a stamp that moved on every reach would
    /// answer neither. Exercised on the ledger directly: a second reach through
    /// JavaScript would be indistinguishable from the first within one clock
    /// tick, and this needs the two to be measurably apart.
    @Test
    func repeatedAccessKeepsTheFirstStampAndCountsTheRest() async throws {
        let ledger = NotImplementedLedger()

        let first = ledger.record(memberPath: "vscode.window.showQuickPick", extensionIdentifier: "test.alpha")
        try await Task.sleep(for: .milliseconds(20))
        let second = ledger.record(memberPath: "vscode.window.showQuickPick", extensionIdentifier: "test.alpha")

        #expect(second.firstAccess == first.firstAccess)
        #expect(second.count == 2)
        #expect(ledger.accesses.count == 1)
    }

    /// Two different members are two rows, so the recording is a record and
    /// not a flag. A `fetch` reach is in here too: the shim's `fetch` stub is
    /// the standing record of a deliberate decision, and it must show up in
    /// the same ledger the report reads.
    @Test
    func distinctMembersAreRecordedSeparatelyIncludingFetch() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let ledger = NotImplementedLedger()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var reached = [];
                try { vscode.window.showInformationMessage('hi'); } catch (error) { reached.push(error.memberPath); }
                try { vscode.Uri.file('/tmp'); } catch (error) { reached.push(error.memberPath); }
                try { fetch('https://example.com'); } catch (error) { reached.push(error.memberPath); }
                console.log(reached.join(','));
            };
            """,
            in: directory,
            ledger: ledger
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()

        #expect(recorder.texts == ["vscode.window.showInformationMessage,vscode.Uri,fetch"])
        #expect(ledger.accesses.map(\.memberPath) == [
            "fetch", "vscode.Uri", "vscode.window.showInformationMessage"
        ])
        #expect(ledger.accesses.allSatisfy { $0.count == 1 })
    }

    /// One ledger, two extensions: the rows stay attributed. Task 5.8's report
    /// groups by extension, and a ledger that lost the identifier would make
    /// that impossible after the hosts are gone.
    @Test
    func oneLedgerKeepsTwoExtensionsApart() async throws {
        let first = try makeTempDirectory()
        let second = try makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        let ledger = NotImplementedLedger()
        let source = """
        var vscode = require('vscode');
        exports.activate = function () {
            try { vscode.workspace.workspaceFolders; } catch (error) {}
        };
        """
        let hostA = try makeHost(name: "alpha", source: source, in: first, ledger: ledger)
        let hostB = try makeHost(name: "beta", source: source, in: second, ledger: ledger)
        defer {
            hostA.dispose()
            hostB.dispose()
        }

        try await hostA.activate()
        try await hostB.activate()

        #expect(ledger.accesses.count == 2)
        #expect(ledger.accesses.map(\.extensionIdentifier) == ["test.alpha", "test.beta"])
        #expect(ledger.accesses(for: "test.beta").map(\.memberPath) == ["vscode.workspace.workspaceFolders"])
    }

    /// The activation argument is a stub too — an extension that reaches for
    /// `context.subscriptions` is told which member it wanted, rather than
    /// failing later on an `undefined`.
    @Test
    func theActivationContextIsARecordedStub() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let ledger = NotImplementedLedger()
        let host = try makeHost(
            source: """
            exports.activate = function (context) {
                try { context.subscriptions.push(1); } catch (error) { console.log(error.memberPath); }
            };
            """,
            in: directory,
            ledger: ledger
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()

        #expect(recorder.texts == ["vscode.ExtensionContext.subscriptions"])
        #expect(ledger.accesses.map(\.memberPath) == ["vscode.ExtensionContext.subscriptions"])
    }

    /// The `vscode` object may not be mutated into working. An extension that
    /// monkey-patched a stub would defeat the whole mechanism silently.
    @Test
    func theVSCodeNamespaceIsReadOnly() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                try {
                    vscode.commands.registerCommand = function () {};
                    console.log('assigned');
                } catch (error) {
                    console.log(error.name);
                }
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()

        #expect(recorder.texts == ["TypeError"])
    }

    // MARK: - The host globals

    /// The bridge the shim talks to the host through is gone by the time the
    /// extension's first statement runs. It carries blocks that schedule
    /// timers and write to the log; an extension that found it could use them
    /// without passing any of the shim's checks.
    @Test
    func theHostBridgeIsNotReachableFromExtensionCode() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = function () {
                console.log(typeof globalThis.__host + ',' + typeof globalThis.__extensionRuntime);
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()

        #expect(recorder.texts == ["undefined,undefined"])
    }

    // MARK: - The web-platform slice

    @Test
    func theShimSuppliesURLTextEncodingAndTheirRefusals() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = function () {
                var url = new URL('/a/../b/c?q=1&q=2#frag', 'https://example.com:8443/base/');
                console.log(url.href);
                console.log(url.searchParams.getAll('q').join('|') + ' ' + url.port + ' ' + url.hash);

                var bytes = new TextEncoder().encode('héllo');
                console.log(bytes.length + ' ' + new TextDecoder().decode(bytes));

                try { new TextDecoder('utf-16le'); } catch (error) { console.log(error.name); }
                try { new URL('not a url'); } catch (error) { console.log(error.name); }
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()

        #expect(recorder.texts == [
            "https://example.com:8443/b/c?q=1&q=2#frag",
            "1|2 8443 #frag",
            "6 héllo",
            "RangeError",
            "TypeError"
        ])
    }

    // MARK: - Disposed hosts

    @Test
    func activatingADisposedHostIsRefused() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(source: "exports.activate = function () {};", in: directory)
        host.dispose()

        await #expect(throws: ExtensionHostError.hostDisposed(identifier: "test.alpha")) {
            try await host.activate()
        }
    }

    @Test
    func disposingTwiceIsSafe() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(source: "exports.activate = function () {};", in: directory)
        try await host.activate()
        host.dispose()
        host.dispose()

        #expect(host.isDisposed)
    }

    /// An entry point the manifest names but the directory does not hold is
    /// the extension's problem, reported as such rather than as a crash.
    @Test
    func aMissingEntryPointIsReportedAsUnreadable() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let loaded = LoadedExtension(
            manifest: try manifest(name: "absent", browser: "dist/web.js"),
            directory: directory
        )
        let host = ExtensionHost(loadedExtension: loaded)
        defer { host.dispose() }

        do {
            try await host.activate()
            Issue.record("A missing entry point must not activate.")
        } catch let error as ExtensionHostError {
            guard case let .entryPointUnreadable(identifier, path, _) = error else {
                Issue.record("Expected entryPointUnreadable, got \(error)")
                return
            }
            #expect(identifier == "test.absent")
            #expect(path.hasSuffix("dist/web.js"))
        }
    }
}
