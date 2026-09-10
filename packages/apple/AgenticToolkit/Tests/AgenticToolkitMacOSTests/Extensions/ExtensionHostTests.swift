import Testing
import Foundation
import JavaScriptCore
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

/// Watches a host from *inside* its own activation, and can cancel it there.
///
/// Two things are only observable from inside. `.activating` is over by the
/// time `activate()` returns; and the state where an activation *succeeds* with
/// a cancellation already recorded against it needs that cancellation delivered
/// in the window between the two, which nothing outside the host can aim at.
/// The extension's own `console` call is the one hook reliably inside it.
///
/// A reference type for `ConsoleRecorder`'s reason and one more: the task it
/// cancels is assigned *after* the closure that cancels it.
@MainActor
private final class ActivationWatcher {

    var task: Task<Void, Error>?

    private(set) var texts: [String] = []
    private(set) var statesSeen: [ExtensionHost.ActivationState] = []
    private var cancelTrigger: String?

    /// `weak host`, so the closure the host stores does not hold the host.
    func attach(to host: ExtensionHost, cancellingOn trigger: String? = nil) {
        cancelTrigger = trigger
        host.onConsoleMessage = { [self, weak host] message in
            texts.append(message.text)
            if let host { statesSeen.append(host.activationState) }
            if message.text == cancelTrigger { task?.cancel() }
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

        // Premise 1: the decoy exists and is readable, by a route the subject
        // does not use.
        let decoy = parent.appendingPathComponent("ext-evil/web.js")
        #expect(FileManager.default.isReadableFile(atPath: decoy.path))

        // Premise 2: the escape really does resolve to the decoy. This is not
        // ceremony — `URL(fileURLWithPath:)` consults the file system, and a
        // decoy that resolved somewhere else would leave the refusal proving
        // nothing about sibling prefixes.
        let escaped = URL(fileURLWithPath: "../ext-evil/web.js", relativeTo: extensionDirectory)
            .resolvingSymlinksInPath().standardizedFileURL
        let canonicalDecoy = decoy.resolvingSymlinksInPath().standardizedFileURL
        #expect(escaped.path == canonicalDecoy.path)

        // Premise 3: the two directory paths really are in the prefix relation
        // this test exists to defeat. A fixture rename that broke it would
        // otherwise turn this into a duplicate of the `../outside/` test.
        #expect(canonicalDecoy.path.hasPrefix(
            extensionDirectory.resolvingSymlinksInPath().standardizedFileURL.path))

        let loaded = LoadedExtension(
            manifest: try manifest(name: "sibling", browser: "../ext-evil/web.js"),
            directory: extensionDirectory
        )
        let host = ExtensionHost(loadedExtension: loaded)
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        await #expect(throws: ExtensionHostError.entryPointEscapesExtensionDirectory(
            identifier: "test.sibling",
            declared: "../ext-evil/web.js",
            resolved: canonicalDecoy.path
        )) {
            try await host.activate()
        }
        #expect(recorder.texts.isEmpty)
        #expect(!host.isActivated)
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

        // And it is terminal, for the reason a cancellation is: the module was
        // evaluated - it threw *while running* - so this host's JavaScript has
        // already happened and cannot be made not to have happened.
        #expect(host.activationState == .terminal(.failed))
        await #expect(throws: ExtensionHostError.activationAlreadyFailed(identifier: "test.alpha")) {
            try await host.activate()
        }
    }

    /// A failed activation is terminal, and the retry every caller reaches for
    /// is refused rather than run.
    ///
    /// This is MD-A's rule arriving at the state by the route that is actually
    /// common. Cancellation is not what makes a host unrepeatable; *evaluating
    /// the module* is, and every failing path gets there - a sync throw, a
    /// rejected promise, a throwing `.then` getter, a top-level throw. Measured
    /// before the guard existed: the module's top level and its `activate` both
    /// ran a second time, a second `JSContext` was built beside the live first
    /// one, and `runningTimerCount` reached 2 for a host with one live runtime,
    /// so the teardown invariant stopped meaning one host-worth of timers.
    /// Worse, timer IDs restart at 1 in a new runtime, so the retry's first
    /// `setInterval` destroyed the abandoned instance's timer by ID collision -
    /// the abandoned extension simply stopped, with nothing recorded anywhere.
    ///
    /// The console line and the timer count are the assertions that separate a
    /// refusal from a second evaluation that also failed.
    @Test(.timeLimit(.minutes(1)))
    func aFailedActivationIsTerminalAndRefusesTheRetry() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            console.log('top level ran');
            setInterval(function () { console.log('tick'); }, 3600000);
            exports.activate = function () {
                console.log('activate ran');
                throw new Error('boom');
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        do {
            try await host.activate()
            Issue.record("A throw from activate() must fail the activation.")
        } catch let error as ExtensionHostError {
            guard case .activationThrew = error else {
                Issue.record("Expected activationThrew, got \(error)")
                return
            }
        }

        #expect(!host.isActivated)
        #expect(host.activationState == .terminal(.failed))
        #expect(host.runningTimerCount == 1)

        await #expect(throws: ExtensionHostError.activationAlreadyFailed(identifier: "test.alpha")) {
            try await host.activate()
        }

        // The refusal is a refusal, not a second evaluation that then failed
        // the same way: the module ran once.
        #expect(recorder.texts == ["top level ran", "activate ran"])
        #expect(host.runningTimerCount == 1)
    }

    /// The vocabulary itself, walked end to end, including the two states that
    /// are only visible from inside an activation.
    ///
    /// `.disposed` outranking `.activated` is the half that is easy to get
    /// backwards and impossible to notice: a host torn down after a successful
    /// activation would go on describing itself as `.activated`, and every
    /// guard that reads the state would let it through.
    @Test(.timeLimit(.minutes(1)))
    func activationStateNamesEveryStepFromFreshToDisposed() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: "exports.activate = function () { console.log('inside'); };",
            in: directory
        )

        let watcher = ActivationWatcher()
        watcher.attach(to: host)

        #expect(host.activationState == .neverActivated)

        try await host.activate()

        #expect(watcher.statesSeen == [.activating], "a call inside activate() is .activating")
        #expect(host.activationState == .activated)

        host.dispose()

        #expect(host.activationState == .disposed)
        // `isActivated` records what happened, and teardown does not unhappen
        // it - only `activationState` moves on.
        #expect(host.isActivated)
    }

    /// A cancellation that lands while the activation is already succeeding
    /// leaves the host **activated**, not terminal.
    ///
    /// This is the state that makes the ordering in `activationState`
    /// load-bearing rather than arbitrary, and the reason the termination
    /// reason is not exposed as a public `isCancelled`: it is true here, on a
    /// host that genuinely activated. Reversing `.activated` and `.terminal`
    /// turns a working extension into one that refuses every later call.
    ///
    /// The window is real but narrow, so the extension opens it itself: the
    /// cancellation is issued from a `console` call inside `activate`, which
    /// runs while the host is deep inside `performActivation` on the main
    /// actor. The hop that records the cancellation is queued behind that, and
    /// the activation completes either side of it - both orderings produce this
    /// state. `recordedTerminationReason` is asserted first because without it
    /// a run where the cancellation never landed would pass in silence.
    ///
    /// The reason both orderings agree lives in the other file:
    /// `extension-runtime.js`'s `callActivate` reaches `done(true, '')`
    /// *synchronously* for an `activate` that returns a non-thenable, so the
    /// continuation is already taken and cleared before the hop can run and the
    /// hop's `finishActivation` is a guaranteed no-op. A future `callActivate`
    /// that deferred that callback would invalidate this test's premise while
    /// leaving it green, which is why the dependency is written down here.
    @Test(.timeLimit(.minutes(1)))
    func aCancellationLandingAsActivationSucceedsLeavesTheHostActivated() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: "exports.activate = function () { console.log('cancel me now'); };",
            in: directory
        )
        defer { host.dispose() }

        let watcher = ActivationWatcher()
        watcher.attach(to: host, cancellingOn: "cancel me now")
        watcher.task = Task { @MainActor in try await host.activate() }

        try await watcher.task?.value

        #expect(
            host.recordedTerminationReason == .cancelled,
            "the cancellation never landed, so this test proved nothing")
        #expect(host.activationState == .activated)
        #expect(host.isActivated)

        // And the host behaves as an activated one: a later call is the no-op
        // it is for any activated host, not the refusal a terminal one gives.
        try await host.activate()
        #expect(watcher.texts == ["cancel me now"])
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

        // `context.subscriptions`, not `vscode.ExtensionContext.subscriptions`:
        // the ledger is read by a person looking for the line they wrote, and
        // the type's name appears nowhere in their file.
        #expect(recorder.texts == ["context.subscriptions"])
        #expect(ledger.accesses.map(\.memberPath) == ["context.subscriptions"])
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

    // MARK: - Asynchronous activation

    /// The failure this whole file exists to prevent.
    ///
    /// `export async function activate()` is what most real extensions ship,
    /// and a throw from one produces a *rejected promise*. JavaScriptCore does
    /// not route an unhandled rejection to a context's `exceptionHandler`, so
    /// nothing on the Swift side sees it: without the shim's completion
    /// callback the host reports a clean activation for an extension that
    /// failed, which is exactly "activated fine, did nothing".
    @Test
    func aRejectingAsyncActivateFailsWithItsReason() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = async function () {
                await new Promise(function (resolve) { setTimeout(resolve, 1); });
                throw new Error('async activate exploded');
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        do {
            try await host.activate()
            Issue.record("A rejected activate() promise must fail activation.")
        } catch let error as ExtensionHostError {
            guard case let .activationThrew(identifier, message) = error else {
                Issue.record("Expected activationThrew, got \(error)")
                return
            }
            #expect(identifier == "test.alpha")
            #expect(message.contains("async activate exploded"))
        }
        #expect(!host.isActivated)
    }

    /// A rejection that is not an `Error` still has to arrive as something.
    /// `Promise.reject('nope')` is legal and libraries do it.
    @Test
    func aRejectionThatIsNotAnErrorIsStillReported() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: "exports.activate = function () { return Promise.reject('a bare string'); };",
            in: directory
        )
        defer { host.dispose() }

        await #expect(throws: ExtensionHostError.activationThrew(
            identifier: "test.alpha",
            message: "Non-Error thrown: a bare string"
        )) {
            try await host.activate()
        }
    }

    /// A rejection reason that fights back.
    ///
    /// Reporting a rejection means *describing* the reason, and describing an
    /// arbitrary value runs the extension's own code: a getter, a `Proxy` trap,
    /// a decorated `stack`. A throw from any of them happens inside a promise
    /// reaction job, where there is no `catch` to reach and no JavaScriptCore
    /// exception handler either — so the completion callback was never called
    /// and `activate()` waited for a settle that had already happened. A vague
    /// message is the requirement; hanging is not one of the options.
    ///
    /// The time limit is part of the test. The defect this guards is a *hang*,
    /// so a regression presents as an `xcodebuild` that stops printing while
    /// naming this test - the failure shape most likely to be read as a wedged
    /// machine and re-run. A minute is far longer than the test needs (it
    /// finishes in milliseconds) and far shorter than a person's patience.
    @Test(.timeLimit(.minutes(1)))
    func aRejectionWhoseDescriptionThrowsFailsActivationRatherThanHanging() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = function () {
                var reason = {};
                Object.defineProperty(reason, 'detail', {
                    enumerable: true,
                    get: function () { throw new Error('describing me throws'); }
                });
                return Promise.reject(reason);
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        do {
            try await host.activate()
            Issue.record("A rejection must fail activation even when its reason cannot be described.")
        } catch let error as ExtensionHostError {
            guard case let .activationThrew(identifier, message) = error else {
                Issue.record("Expected activationThrew, got \(error)")
                return
            }
            #expect(identifier == "test.alpha")
            #expect(message.contains("could not be described"), "message was: \(message)")
        }
        #expect(!host.isActivated)
    }

    /// An extension that replaces `Function.prototype.call` must not be able to
    /// make the host report an activation that never happened.
    ///
    /// `.call` resolves dynamically, and the extension's own top-level code
    /// runs before its `activate` is ever reached - so a module that assigns
    /// `Function.prototype.call = function () {}` at the top level used to make
    /// `activate.call(exports, context)` return `undefined` without calling
    /// anything. The shim saw no thenable, reported success, and the host
    /// recorded a clean activation for an extension whose `activate` never ran:
    /// the exact false success the shim exists to prevent. It needs no malice -
    /// a bundled SES/lockdown shim or a call-instrumenting polyfill does it by
    /// accident.
    ///
    /// The console line is the assertion. `isActivated` alone would pass
    /// against the defect, because the defect *is* a reported activation; only
    /// evidence from inside `activate` separates the two.
    ///
    /// The timer is the second half. `setTimeout`'s extra arguments are cut
    /// from `arguments` by the same shape of call, and they are cut *after* the
    /// extension's top level has run - so unlike the module wrapper, this one
    /// is reachable by a poisoned prototype.
    @Test
    func anExtensionThatReplacesFunctionPrototypeCallCannotFakeActivation() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            Function.prototype.call = function () {};
            exports.activate = function () {
                console.log('activate really ran');
                setTimeout(function (marker) { console.log('timer saw ' + marker); }, 1, 'extra');
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()

        #expect(
            recorder.texts.first == "activate really ran",
            "activation was reported without activate() running: \(recorder.texts)"
        )
        #expect(host.isActivated)

        for _ in 0..<100 where recorder.texts.count < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(recorder.texts == ["activate really ran", "timer saw extra"])
    }

    /// The same poison aimed at `apply`, which is what actually *dispatches* a
    /// timer callback.
    ///
    /// Hardening `tail` made the arguments survive a poisoned prototype; the
    /// call that consumes them was still `timer.callback.apply(...)`. With
    /// `Function.prototype.apply` replaced, every `setTimeout` and
    /// `setInterval` callback was dropped - no callback, no error, no console
    /// line, forever. It cannot make the host report a false activation, which
    /// is why it is the mildest of these, but it is the only one whose failure
    /// mode is *silence* rather than a degraded string, and silence is the one
    /// thing this shim exists to refuse.
    @Test(.timeLimit(.minutes(1)))
    func aPoisonedFunctionPrototypeApplyCannotSilenceTimerCallbacks() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            Function.prototype.apply = function () {};
            exports.activate = function () {
                console.log('activate really ran');
                setTimeout(function (marker) { console.log('timer saw ' + marker); }, 1, 'extra');
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()
        #expect(host.isActivated)

        for _ in 0..<100 where recorder.texts.count < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(recorder.texts == ["activate really ran", "timer saw extra"])
    }

    /// The other half of M1, and the one 5.3 depends on: activation is not
    /// signalled until `activate()` has actually finished.
    ///
    /// The extension registers its work *after* a timer, which is what an
    /// async `activate` really does. A host that did not await the returned
    /// promise would return here with `registered` still empty, and the command
    /// a palette asked for a moment later would not exist.
    @Test
    func activationWaitsForASlowAsyncActivateToFinish() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = async function () {
                console.log('activate started');
                await new Promise(function (resolve) { setTimeout(resolve, 30); });
                console.log('activate registered its command');
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()

        #expect(recorder.texts == ["activate started", "activate registered its command"])
        #expect(host.isActivated)
    }

    /// An `activate()` that resolves normally still activates — the positive
    /// control for the two tests above, which would both pass against a host
    /// that failed every async activation.
    @Test
    func aResolvingAsyncActivateActivates() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = async function () {
                await Promise.resolve();
                console.log('resolved cleanly');
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()

        #expect(host.isActivated)
        #expect(recorder.texts == ["resolved cleanly"])
    }

    /// Teardown is the escape from an `activate()` that never settles. There is
    /// no timeout, deliberately — a real extension may await a network round
    /// trip, and a host that gave up at *n* seconds would report a failure that
    /// did not happen.
    @Test
    func disposingReleasesAnActivateThatNeverSettles() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = function () {
                console.log('hanging');
                return new Promise(function () {});
            };
            """,
            in: directory
        )

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        let activation = Task { @MainActor in try await host.activate() }

        // The dispose has to land after `activate()` has suspended, which is
        // why it waits for the extension's own first line to arrive. Bounded,
        // so a regression that never reached it fails rather than hangs.
        for _ in 0..<100 where recorder.texts.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(recorder.texts == ["hanging"])

        host.dispose()

        await #expect(throws: ExtensionHostError.hostDisposed(identifier: "test.alpha")) {
            try await activation.value
        }
        #expect(!host.isActivated)
    }

    /// Cancellation is the second escape, and the one a caller owns.
    ///
    /// `performActivation` runs in an unstructured task, so awaiting
    /// `task.value` forwards nothing on its own: a caller who wrapped
    /// `activate()` in a cancellable task used to cancel only their own
    /// wrapper while the activation went on waiting for a promise that never
    /// settles. The cancellation has to reach the continuation.
    ///
    /// The second half is the one that matters. The extension's promise is
    /// still running when the cancellation lands, and it settles a moment
    /// later into a continuation that is already gone — and a
    /// `CheckedContinuation` resumed twice is a crash, not a warning. Letting
    /// it settle, rather than stopping at the throw, is the whole point of the
    /// test: reaching the last line is the assertion.
    @Test
    func cancellingAnActivationEndsItAndALaterSettleIsHarmless() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = function () {
                console.log('waiting');
                return new Promise(function (resolve) {
                    setTimeout(function () { console.log('settled anyway'); resolve(); }, 60);
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        let activation = Task { @MainActor in try await host.activate() }

        // Bounded, so a regression that never reached the promise at all fails
        // here rather than hanging.
        for _ in 0..<100 where recorder.texts.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(recorder.texts == ["waiting"])

        activation.cancel()

        await #expect(throws: ExtensionHostError.activationCancelled(identifier: "test.alpha")) {
            try await activation.value
        }
        #expect(!host.isActivated)

        for _ in 0..<100 where recorder.texts.count < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(recorder.texts == ["waiting", "settled anyway"])
        #expect(!host.isActivated)
    }

    /// Cancelling an activation *whose module has been evaluated* is terminal:
    /// the host refuses to activate again, and `dispose()` is what follows.
    ///
    /// Cancellation ends the *call*, not the activation - the extension's
    /// promise is still pending inside a runtime nothing can un-run. A retry is
    /// the reflex response to a cancellation, and a host that allowed one would
    /// evaluate the module into a second runtime beside the abandoned one:
    /// `context` overwritten under a still-running activation, and
    /// `runningTimerCount` counting both instances.
    ///
    /// The evaluation is what makes it terminal, not the cancellation, which is
    /// why this test waits for the extension's own `console.log` before
    /// cancelling. The other side of that boundary is
    /// `aCancellationBeforeTheModuleIsEvaluatedLeavesTheHostRetryable`.
    ///
    /// Time-limited for LO-D's reason, and it is not hypothetical here:
    /// removing the guard makes the retry evaluate a module whose `activate`
    /// returns a promise that never settles, so the regression is a *hang*
    /// unless something bounds it. Measured - that is how the guard's mutation
    /// presented before this trait was added.
    @Test(.timeLimit(.minutes(1)))
    func aCancelledHostRefusesToActivateAgain() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = function () {
                console.log('waiting');
                return new Promise(function () {});
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        let activation = Task { @MainActor in try await host.activate() }
        for _ in 0..<100 where recorder.texts.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(recorder.texts == ["waiting"])

        await #expect(throws: ExtensionHostError.activationCancelled(identifier: "test.alpha")) {
            activation.cancel()
            try await activation.value
        }

        // Named, not merely refused. The cancellation is what made this host
        // terminal, and the assertion is what distinguishes this state from
        // the pre-evaluation one the sibling test pins.
        #expect(host.activationState == .terminal(.cancelled))
        #expect(host.recordedTerminationReason == .cancelled)

        await #expect(throws: ExtensionHostError.activationCancelled(identifier: "test.alpha")) {
            try await host.activate()
        }

        // The refusal is a refusal, not a second evaluation that then failed:
        // the module never ran again, so the console never saw a second line.
        #expect(recorder.texts == ["waiting"])
        #expect(!host.isActivated)
    }

    /// The other side of the boundary: a cancellation that lands before the
    /// module is evaluated leaves the host exactly as it was, and it activates
    /// afterwards.
    ///
    /// Reading the entry point off disk is a real suspension point and it sits
    /// *before* the first `JSContext` exists, so a caller who does what
    /// `activate()`'s own documentation recommends - wrap it in a timeout -
    /// over a bundled extension that is routinely megabytes, on a slow volume,
    /// cancels a host in which nothing has run. Spending it there refuses the
    /// retry *and*, since `defineVSCodeMember` reads the same terminal
    /// predicate, refuses the caller even the chance to re-prepare the host
    /// with its adaptor members. Both are asserted here, in that order.
    ///
    /// The cancellation is delivered before the wrapping task has begun, which
    /// is the one timing that is not a race: the test body runs to
    /// `cancel()` synchronously on the main actor, so `activate()` cannot have
    /// started, and the only thing the activation can then be doing when the
    /// cancellation handler's main-actor hop runs is the read - the hop is
    /// enqueued before the read completes and the main actor is serial.
    @Test(.timeLimit(.minutes(1)))
    func aCancellationBeforeTheModuleIsEvaluatedLeavesTheHostRetryable() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = function () {
                var vscode = require('vscode');
                console.log('ran:' + vscode.window.showSomethingReal());
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        let activation = Task { @MainActor in try await host.activate() }
        activation.cancel()

        await #expect(throws: ExtensionHostError.activationCancelled(identifier: "test.alpha")) {
            try await activation.value
        }

        // Nothing ran, so nothing was abandoned.
        #expect(recorder.texts.isEmpty)
        #expect(host.runningTimerCount == 0)
        #expect(host.javaScriptContext == nil)
        #expect(host.recordedTerminationReason == nil)
        #expect(host.activationState == .neverActivated)

        // So the host is still preparable...
        let real: @convention(block) () -> String = { "ok" }
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "showSomethingReal", implementation: real)

        // ...and still activatable, with the member the caller just defined.
        try await host.activate()

        #expect(host.isActivated)
        #expect(host.activationState == .activated)
        #expect(recorder.texts == ["ran:ok"])
    }

    /// Cancelling an activation stops the *waiting*, not the JavaScript: the
    /// context is still there, the extension's timer is still counted, and
    /// `dispose()` is still the only thing that ends either. A cancellation
    /// that tore down half the host would leave teardown with nothing to do
    /// and this test with nothing to observe.
    @Test
    func disposeStillWorksAfterACancelledActivation() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = function () {
                console.log('waiting');
                setTimeout(function () { console.log('much later'); }, 10000);
                return new Promise(function () {});
            };
            """,
            in: directory
        )

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        let activation = Task { @MainActor in try await host.activate() }
        for _ in 0..<100 where recorder.texts.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }

        await #expect(throws: ExtensionHostError.activationCancelled(identifier: "test.alpha")) {
            activation.cancel()
            try await activation.value
        }

        // Cancellation left the JavaScript side exactly as it was.
        #expect(host.runningTimerCount == 1)
        weak var released: JSContext?
        released = host.javaScriptContext
        #expect(released != nil)

        host.dispose()

        #expect(host.isDisposed)
        #expect(host.javaScriptContext == nil)
        #expect(released == nil, "dispose() must release the JSContext after a cancelled activation too")

        var attempts = 0
        while host.runningTimerCount != 0 && attempts < 50 {
            try await Task.sleep(for: .milliseconds(10))
            attempts += 1
        }
        #expect(host.runningTimerCount == 0)

        await #expect(throws: ExtensionHostError.hostDisposed(identifier: "test.alpha")) {
            try await host.activate()
        }
    }

    // MARK: - The 5.3-5.7 seam

    /// Replacing one stub with a real implementation, which is what stages 5.3
    /// through 5.7 each do. Three things at once because they are one contract:
    /// the defined member runs, it is *not* recorded as unimplemented, and its
    /// siblings still throw and are still recorded.
    @Test
    func aDefinedMemberRunsIsNotRecordedAndLeavesItsSiblingsThrowing() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let ledger = NotImplementedLedger()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                console.log(vscode.commands.registerCommand('hello.world'));
                try { vscode.commands.executeCommand('x'); } catch (error) { console.log(error.memberPath); }
            };
            """,
            in: directory,
            ledger: ledger
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        let register: @convention(block) (String) -> String = { "registered:\($0)" }
        try host.defineVSCodeMember(
            namespacePath: "vscode.commands", name: "registerCommand", implementation: register)

        try await host.activate()

        #expect(recorder.texts == ["registered:hello.world", "vscode.commands.executeCommand"])
        #expect(ledger.accesses.map(\.memberPath) == ["vscode.commands.executeCommand"])
    }

    /// A member defined *after* activation is live too — an adaptor wired late,
    /// or one that grows a member while an extension is already running.
    @Test
    func aMemberDefinedAfterActivationIsLiveImmediately() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                // Captured now, called later — the closure holds the namespace
                // from before the member existed.
                globalThis.ask = function () {
                    try { return vscode.window.showInformationMessage('hi'); } catch (error) { return error.name; }
                };
                console.log(globalThis.ask());
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()
        #expect(recorder.texts == ["NotImplementedError"])

        let show: @convention(block) (String) -> String = { "shown:\($0)" }
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "showInformationMessage", implementation: show)

        let context = try #require(host.javaScriptContext)
        let answer = context.evaluateScript("globalThis.ask()")
        #expect(answer?.toString() == "shown:hi")
    }

    /// A namespace the shim does not have is an adaptor's bug, and it is
    /// refused rather than silently leaving the member throwing.
    @Test
    func definingAMemberOnAnUnknownNamespaceIsRefused() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(source: "exports.activate = function () {};", in: directory)
        defer { host.dispose() }

        let nothing: @convention(block) () -> Void = {}
        try host.defineVSCodeMember(
            namespacePath: "vscode.notANamespace", name: "x", implementation: nothing)

        do {
            try await host.activate()
            Issue.record("An unknown namespace must refuse the definition.")
        } catch let error as ExtensionHostError {
            guard case let .vscodeMemberNotDefinable(identifier, namespacePath, name, message) = error else {
                Issue.record("Expected vscodeMemberNotDefinable, got \(error)")
                return
            }
            #expect(identifier == "test.alpha")
            #expect(namespacePath == "vscode.notANamespace")
            #expect(name == "x")
            // The refusal lists what *does* exist, so the author of the adaptor
            // does not have to go read the shim to find the spelling.
            #expect(message.contains("vscode.commands"))
            // And it names the call site that asked for it. The definition is
            // replayed at activation, so the throw happens far from the line
            // that is wrong; without the captured origin the message describes
            // a mistake with no address.
            #expect(message.contains("ExtensionHostTests.swift:"), "message was: \(message)")
        }
        #expect(!host.isActivated)
    }

    /// And the refused definition is withdrawn, so the host that reports
    /// `.neverActivated` can actually still activate.
    ///
    /// Definitions are queued and replayed into every context a later
    /// `activate()` builds, and a misspelled namespace fails identically on
    /// every replay. Left in the queue it is a permanent doom with no remedy —
    /// there is no API to withdraw a queued definition, the host is not
    /// terminal (nothing ran, so nothing was abandoned), and `.neverActivated`
    /// means "everything still ahead of it" about a host with nothing ahead of
    /// it. Withdrawing the one entry that cannot work makes the name true.
    ///
    /// The good definition is queued *first* deliberately: it proves the
    /// withdrawal takes out the offending entry rather than the queue.
    @Test
    func aRefusedDefinitionIsWithdrawnSoTheHostStillActivates() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = function () {
                var vscode = require('vscode');
                console.log('ran:' + vscode.window.showSomethingReal());
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        let real: @convention(block) () -> String = { "ok" }
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "showSomethingReal", implementation: real)
        let nothing: @convention(block) () -> Void = {}
        try host.defineVSCodeMember(
            namespacePath: "vscode.notANamespace", name: "x", implementation: nothing)

        await #expect(throws: ExtensionHostError.self) {
            try await host.activate()
        }
        #expect(recorder.texts.isEmpty)
        #expect(host.activationState == .neverActivated)

        // The retry is not the same failure again: the entry that raised it is
        // gone, and the one that works is not.
        try await host.activate()

        #expect(host.isActivated)
        #expect(recorder.texts == ["ran:ok"])
    }

    /// A member defined on a disposed host is refused rather than accepted and
    /// dropped. Definitions are kept and replayed into the context the *next*
    /// activation makes — and a disposed host never activates again, so
    /// without the guard the call succeeded, silently, and the member it
    /// promised existed nowhere.
    @Test
    func definingAMemberOnADisposedHostIsRefused() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(source: "exports.activate = function () {};", in: directory)
        try await host.activate()
        host.dispose()

        let nothing: @convention(block) () -> Void = {}
        #expect(throws: ExtensionHostError.hostDisposed(identifier: "test.alpha")) {
            try host.defineVSCodeMember(
                namespacePath: "vscode.window", name: "showSomethingReal", implementation: nothing)
        }
    }

    /// A member defined on a *cancelled* host is refused too, and this one is
    /// worse than the disposed case rather than milder.
    ///
    /// A disposed host drops the definition on the floor. A cancelled host
    /// still has its runtime: without the guard the definition was queued
    /// *and applied*, so the abandoned extension - the one the app has decided
    /// it is not running - had a real adaptor implementation installed under it
    /// and its still-running `setInterval` began calling it on the next tick.
    /// Measured. The queued copy, meanwhile, can never be replayed, because the
    /// host can never activate again.
    @Test(.timeLimit(.minutes(1)))
    func definingAMemberOnACancelledHostIsRefused() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = function () {
                console.log('waiting');
                setInterval(function () {}, 5);
                return new Promise(function () {});
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        let activation = Task { @MainActor in try await host.activate() }
        for _ in 0..<100 where recorder.texts.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        await #expect(throws: ExtensionHostError.activationCancelled(identifier: "test.alpha")) {
            activation.cancel()
            try await activation.value
        }

        // The abandoned runtime is still there and still ticking - which is
        // exactly what makes accepting a definition harmful.
        #expect(host.runningTimerCount == 1)

        let nothing: @convention(block) () -> Void = {}
        #expect(throws: ExtensionHostError.activationCancelled(identifier: "test.alpha")) {
            try host.defineVSCodeMember(
                namespacePath: "vscode.window", name: "showSomethingReal", implementation: nothing)
        }
    }

    /// And on a host whose activation *failed*, with the error that says which
    /// of the two terminal states it is in.
    @Test(.timeLimit(.minutes(1)))
    func definingAMemberOnAFailedHostIsRefused() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: "exports.activate = function () { throw new Error('boom'); };",
            in: directory
        )
        defer { host.dispose() }

        await #expect(throws: ExtensionHostError.self) {
            try await host.activate()
        }
        #expect(host.activationState == .terminal(.failed))

        let nothing: @convention(block) () -> Void = {}
        #expect(throws: ExtensionHostError.activationAlreadyFailed(identifier: "test.alpha")) {
            try host.defineVSCodeMember(
                namespacePath: "vscode.window", name: "showSomethingReal", implementation: nothing)
        }
    }

    // MARK: - Coercion and formatting

    /// Every way JavaScript turns an object into a string, applied to a
    /// namespace stub. All four used to throw `TypeError: Cannot convert object
    /// to primitive value` — an error that names nothing and points at nothing,
    /// from code the author did not write.
    @Test
    func aNamespaceStubCoercesToSomethingThatSaysWhatItIs() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let ledger = NotImplementedLedger()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                console.log('concat: ' + vscode);
                console.log(`template: ${vscode.commands}`);
                console.log(String(vscode.window));
                console.log(vscode.workspace.toString() + ' ' + vscode.languages.valueOf());
                console.log(vscode);
                console.log('%s', vscode.window);
                console.log(vscode.hasOwnProperty('commands') + ',' + vscode.hasOwnProperty('nope'));
                console.log(JSON.stringify(vscode));
            };
            """,
            in: directory,
            ledger: ledger
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()

        #expect(recorder.texts == [
            "concat: [VSCodeNamespace vscode]",
            "template: [VSCodeNamespace vscode.commands]",
            "[VSCodeNamespace vscode.window]",
            "[VSCodeNamespace vscode.workspace] [VSCodeNamespace vscode.languages]",
            // Inspecting a namespace shows what is *in* it, which is a
            // different and more useful answer than stringifying it.
            "{ commands: {}, workspace: {}, window: {}, languages: {}, lm: {} }",
            "[VSCodeNamespace vscode.window]",
            "true,false",
            "{\"commands\":{},\"workspace\":{},\"window\":{},\"languages\":{},\"lm\":{}}"
        ])
        // None of that is a reach for an unimplemented member, and none of it
        // may be recorded as one.
        #expect(ledger.accesses.isEmpty)
    }

    /// Node's `util.format` specifiers. Extension authors write
    /// `console.log('%s took %dms', name, elapsed)`, and a host that printed
    /// the format string literally would make its own logging look broken.
    @Test
    func consoleHonoursNodeFormatSpecifiers() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = function () {
                console.log('%s took %dms and %i%% of %j', 'load', 12.7, 42.9, { a: 1 });
                console.log('100% sure');
                console.log('a %s b');
                console.log('%o and %f', [1, 2], '3.5kg');
                console.warn('count', [1, 2, 3]);
                console.log('%c styled', 'color: red', 'tail');
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()

        #expect(recorder.texts == [
            "load took 12.7ms and 42% of {\"a\":1}",
            // A `%` with no specifier after it is not a specifier.
            "100% sure",
            // A specifier with no argument left is printed as written.
            "a %s b",
            "[ 1, 2 ] and 3.5",
            // No format string, so the arguments are inspected and joined.
            "count [ 1, 2, 3 ]",
            // `%c` is a devtools CSS directive: it consumes its argument and
            // prints nothing, as Node does.
            " styled tail"
        ])
    }

    // MARK: - Feature detection

    /// `'x' in ns`, `Object.keys(ns)` and `getOwnPropertyDescriptor(ns, 'x')`
    /// must answer honestly rather than throw — every library that guards its
    /// own calls would break otherwise. But the question is worth recording:
    /// an extension that *looked* and quietly took its fallback path is telling
    /// us what it wanted, and nothing else in this host would ever notice.
    @Test
    func aNegativeProbeIsAnsweredHonestlyAndStillRecorded() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let ledger = NotImplementedLedger()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                console.log(('registerCommand' in vscode.commands) + ',' +
                            (Object.getOwnPropertyDescriptor(vscode.window, 'activeTextEditor') === undefined));
                // Probed twice, and the second is not a second row.
                if ('registerCommand' in vscode.commands) { console.log('unreachable'); }
                // A member that *is* there answers yes and is not recorded.
                console.log('commands' in vscode);
                console.log(Object.keys(vscode).join(','));
            };
            """,
            in: directory,
            ledger: ledger
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()

        #expect(recorder.texts == ["false,true", "true", "commands,workspace,window,languages,lm"])

        #expect(ledger.accesses.map(\.memberPath) == [
            "vscode.commands.registerCommand", "vscode.window.activeTextEditor"
        ])
        let probed = try #require(ledger.accesses.first)
        #expect(probed.memberPath == "vscode.commands.registerCommand")
        #expect(probed.probeCount == 2)
        // Looking is not using: nothing here was refused a call.
        #expect(ledger.accesses.allSatisfy { $0.count == 0 })
    }

    /// A member reached both ways is one row carrying both numbers — a library
    /// commonly feature-detects once and then calls anyway, and two rows would
    /// read as two different members.
    @Test
    func probingAndThenUsingTheSameMemberIsOneRow() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let ledger = NotImplementedLedger()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                if (!('registerCommand' in vscode.commands)) {
                    try { vscode.commands.registerCommand('x'); } catch (error) { console.log(error.memberPath); }
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

        #expect(recorder.texts == ["vscode.commands.registerCommand"])
        #expect(ledger.accesses.count == 1)
        let access = try #require(ledger.accesses.first)
        #expect(access.count == 1)
        #expect(access.probeCount == 1)
    }

    // MARK: - Stack traces

    /// The author of a throwing extension has to be able to find their own
    /// line. JavaScriptCore attributes dynamically compiled code — `eval`,
    /// `new Function` — to no script at all: a `//# sourceURL=` directive
    /// reaches Web Inspector and never `Error.stack`, whose frames come back
    /// with an empty location. So the module wrapper is compiled host-side with
    /// the entry point as its source URL, and the wrapper's prefix carries no
    /// newline so that line *n* of the author's file stays line *n*.
    @Test
    func aThrowNamesTheExtensionsOwnFileAndLine() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            var unused = 1;
            var alsoUnused = 2;
            throw new Error('top-level boom');
            """,
            in: directory
        )
        defer { host.dispose() }

        do {
            try await host.activate()
            Issue.record("A top-level throw must not activate.")
        } catch let error as ExtensionHostError {
            guard case let .entryPointThrew(_, message) = error else {
                Issue.record("Expected entryPointThrew, got \(error)")
                return
            }
            // Line 3 of the file above, named as the file the author wrote.
            #expect(message.contains("web.js:3:"), "stack was: \(message)")
        }
    }

    /// The same, from inside `activate()`, which travels a different route —
    /// the shim catches it and describes it rather than the context's exception
    /// handler seeing it.
    @Test
    func aThrowFromActivateAlsoNamesTheFileAndLine() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            var unused = 1;
            exports.activate = function () {
                throw new Error('activate boom');
            };
            """,
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
            #expect(message.contains("web.js:3:"), "stack was: \(message)")
        }
    }

    // MARK: - Teardown, continued

    /// `dispose()` releasing the context is correct-but-unobservable from
    /// outside: every behaviour a test can see afterwards — no callbacks, no
    /// timers, refused re-activation — is guaranteed by `isDisposed` alone, so
    /// a `dispose()` that leaked the whole JavaScript heap would pass all of
    /// them. A weak reference is the only way to state it, and the context is
    /// the largest thing this host owns.
    @Test
    func teardownActuallyReleasesTheJavaScriptContext() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: "exports.activate = function () { console.log('ran'); };",
            in: directory
        )

        try await host.activate()

        weak var released: JSContext?
        released = host.javaScriptContext
        // The positive control: without it this test would pass against a host
        // that never made a context at all.
        #expect(released != nil)

        host.dispose()

        #expect(host.javaScriptContext == nil)
        #expect(released == nil, "dispose() must release the JSContext, not merely stop using it")
    }

    // MARK: - The web-platform slice, continued

    /// The `URL`/`URLSearchParams` surface an extension actually reaches for.
    ///
    /// The shim implements a lot of this, and the alternative to testing it was
    /// to cut it back to what one test happened to touch. Coverage went up
    /// instead: every line of it is on the path of ordinary extension code —
    /// building a request URL, reading one apart, following a
    /// protocol-relative asset reference — and cutting it would mean the next
    /// extension to use it fails on a member that silently is not there.
    @Test
    func theShimSuppliesTheURLSurfaceExtensionsActuallyUse() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = function () {
                // Protocol-relative: the host belongs to the authority, not to
                // the path. Common in real extension code, and swallowing the
                // host into the path produces a request to the wrong server.
                var cdn = new URL('//cdn.example.com/lib/x.js', 'https://ext.example.com/a/b');
                console.log(cdn.href + ' | ' + cdn.hostname + ' | ' + cdn.pathname);

                // `searchParams` is a live view: a mutation writes back to href.
                var api = new URL('https://a.example.com/p?x=1');
                api.searchParams.set('y', 'a b!');
                api.searchParams.append('x', '2');
                console.log(api.href + ' | ' + api.search + ' | ' + api.searchParams.getAll('x').join(','));

                var creds = new URL('https://user:pw@a.example.com:8443/p');
                console.log(creds.origin + ' | ' + creds.username + ':' + creds.password + ' | ' + creds.href);

                var params = new URLSearchParams('b=3&a=1&b=2');
                params.sort();
                var sorted = params.toString();
                params.delete('b');
                console.log(sorted + ' | ' + params.toString() + ' | ' + params.size);

                console.log(String(new URL('./d/../e?q#h', 'https://a.example.com/base/c')));

                try { new URL('/x', 'not-a-url'); } catch (error) { console.log(error.name); }
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()

        #expect(recorder.texts == [
            "https://cdn.example.com/lib/x.js | cdn.example.com | /lib/x.js",
            // `!` is not escaped by form encoding; a space becomes `+`.
            "https://a.example.com/p?x=1&y=a+b%21&x=2 | ?x=1&y=a+b%21&x=2 | 1,2",
            "https://a.example.com:8443 | user:pw | https://user:pw@a.example.com:8443/p",
            // A stable sort: `b=3` was before `b=2` and stays before it.
            "a=1&b=3&b=2 | a=1 | 1",
            "https://a.example.com/base/e?q#h",
            "TypeError"
        ])
    }

    /// The percent-encoder, where it used to disagree with WHATWG.
    ///
    /// Two gaps, both measured against Node's `URL` before and after: the path
    /// class matched surrogate *halves*, so `encodeURIComponent` refused each
    /// one and the fallback handed an astral character back unencoded - an
    /// emoji in a file name being the shape an extension is most likely to
    /// produce; and the fragment was not encoded at all, unlike the query,
    /// which defers to `URLSearchParams` because that really is a second owner.
    ///
    /// `#a{b}c` is here to hold the two sets apart: braces are legal in a
    /// fragment and encoding them would be a new disagreement in the other
    /// direction.
    @Test
    func theURLEncoderMatchesWHATWGForAstralCharactersAndFragments() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let host = try makeHost(
            source: """
            exports.activate = function () {
                console.log(new URL('./a😀bé c', 'https://a.com/').href);
                console.log(new URL('https://a.com/p#f g').href);
                console.log(new URL('https://a.com/p#a{b}c').href);
                console.log(new URL('https://a.com/p#😀').href);
                var setter = new URL('https://a.com/p');
                setter.hash = 'x y';
                console.log(setter.href);
            };
            """,
            in: directory
        )
        defer { host.dispose() }

        let recorder = ConsoleRecorder()
        recorder.attach(to: host)

        try await host.activate()

        #expect(recorder.texts == [
            "https://a.com/a%F0%9F%98%80b%C3%A9%20c",
            "https://a.com/p#f%20g",
            "https://a.com/p#a{b}c",
            "https://a.com/p#%F0%9F%98%80",
            "https://a.com/p#x%20y"
        ])
    }
}
