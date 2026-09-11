import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// `vscode.commands` (task 5.3): `registerCommand`, `executeCommand` and
/// `getCommands`, wired onto a real `ExtensionHost` and a real
/// `CommandRegistry` — never doubles, for the same reason
/// `ExtensionHostTests` gives: the point of this suite is the boundary
/// between JavaScript and Swift, and a double for either side would only
/// ever agree with itself.
///
/// Not `.serialized` — each test owns its own temporary directory, its own
/// registry and its own host.
@MainActor
@Suite
struct MainThreadCommandsTests {

    // MARK: - Fixtures

    private func makeTempDirectory() throws -> URL {
        try ExtensionFixtures.makeTemporaryDirectory("MainThreadCommandsTests")
    }

    /// A manifest with a `browser` entry point, decoded rather than
    /// memberwise-initialised for the same reason `ExtensionHostTests` does
    /// it that way: `ExtensionManifest` has no memberwise initialiser, and
    /// inventing one here would be a second answer to what a manifest is.
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

    /// Installs all three of `commands`'s members onto `host`'s
    /// `vscode.commands` namespace, exactly as a later `ExtensionsCoordinator`
    /// task will. `registerTextEditorCommand` is deliberately absent — it is
    /// the shim's own throwing stub, and test 14 pins that it stays that way.
    private func install(_ commands: MainThreadCommands, on host: ExtensionHost) throws {
        try host.defineVSCodeMember(
            namespacePath: "vscode.commands", name: "registerCommand",
            implementation: commands.registerCommand)
        try host.defineVSCodeMember(
            namespacePath: "vscode.commands", name: "executeCommand",
            implementation: commands.executeCommand)
        try host.defineVSCodeMember(
            namespacePath: "vscode.commands", name: "getCommands",
            implementation: commands.getCommands)
    }

    /// Polls `expression` until it evaluates to something other than
    /// `null`/`undefined`, or gives up after one second.
    ///
    /// `executeCommand` and `getCommands` return an already-settled promise,
    /// but a `.then()` reaction is still a job on JavaScriptCore's microtask
    /// queue — it is never invoked synchronously, by spec, no matter how
    /// settled the promise already is. This polls rather than asserting the
    /// reaction has already run by the time `evaluateScript` returns, because
    /// nothing in this host's public surface promises *when* that queue
    /// drains relative to a bare `evaluateScript` call — only that it does,
    /// which is what every other asynchronous test in this suite family
    /// already depends on (`ExtensionHostTests`'s own polling loops).
    private func waitForGlobal(_ context: JSContext, _ expression: String) async throws -> JSValue? {
        for _ in 0..<200 {
            if let value = context.evaluateScript(expression), !value.isNull, !value.isUndefined {
                return value
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        return nil
    }

    // MARK: - registerCommand + dispatch

    /// A command registered from extension JavaScript appears in
    /// `CommandRegistry.allCommands` under the id the extension gave —
    /// proof the adaptor terminates in the app's own registry rather than a
    /// second, extension-private table.
    @Test
    func aRegisteredCommandAppearsInAllCommands() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.commands.registerCommand('ext.hello', function () { return 'ran'; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)

        try await host.activate()

        #expect(registry.allCommands.map(\.id) == ["ext.hello"])
    }

    /// Running the extension's command from **Swift** — the command
    /// palette's own path — actually runs the callback the extension
    /// registered, not a stand-in.
    @Test
    func executingFromSwiftRunsTheExtensionsCallback() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.ran = false;
                vscode.commands.registerCommand('ext.hello', function () { globalThis.ran = true; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        try registry.execute(id: "ext.hello")

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.ran")?.toBool() == true)
    }

    // MARK: - executeCommand

    /// `vscode.commands.executeCommand('id', 1, 'two')` delivers both
    /// arguments to the callback and resolves with whatever the callback
    /// returned.
    @Test
    func executeCommandDeliversArgumentsAndResolvesWithTheResult() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.commands.registerCommand('ext.echo', function (a, b) {
                    globalThis.received = [a, b];
                    return 'echo:' + a + ':' + b;
                });
                globalThis.__settled = null;
                globalThis.exec = function (id) {
                    var args = Array.prototype.slice.call(arguments, 1);
                    vscode.commands.executeCommand.apply(vscode.commands, [id].concat(args)).then(
                        function (value) { globalThis.__settled = { ok: true, value: value }; },
                        function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                    );
                };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.exec('ext.echo', 1, 'two');")

        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("value")?.toString() == "echo:1:two")

        let received = context.evaluateScript("globalThis.received")
        #expect(received?.atIndex(0)?.toInt32() == 1)
        #expect(received?.atIndex(1)?.toString() == "two")
    }

    /// `executeCommand` on an unknown id **rejects** — it neither throws
    /// synchronously nor resolves with `undefined`, either of which would
    /// land in the wrong `catch`/`then` inside an extension's own
    /// `await`-wrapped `try`.
    @Test
    func executeCommandOnUnknownIDRejects() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                globalThis.exec = function (id) {
                    vscode.commands.executeCommand(id).then(
                        function (value) { globalThis.__settled = { ok: true, value: value }; },
                        function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                    );
                };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.exec('ext.doesNotExist');")

        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(settled.forProperty("message")?.toString()
            == CommandRegistryError.unknownCommand(id: "ext.doesNotExist").description)
    }

    /// `executeCommand` on a registered-but-disabled command rejects with
    /// the *disabled* wording, not the unknown-command one — the two must
    /// stay distinguishable from inside the extension's `catch`.
    @Test
    func executeCommandOnDisabledCommandRejectsWithTheDisabledError() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        var ran = false
        registry.register(AppCommand(
            id: "app.disabled",
            title: "Disabled",
            isEnabled: { false },
            run: { _ in
                ran = true
                return nil
            }
        ))
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                globalThis.exec = function (id) {
                    vscode.commands.executeCommand(id).then(
                        function (value) { globalThis.__settled = { ok: true, value: value }; },
                        function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                    );
                };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.exec('app.disabled');")

        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(settled.forProperty("message")?.toString()
            == CommandRegistryError.commandDisabled(id: "app.disabled").description)
        #expect(!ran)
    }

    /// `executeCommand` reaches a command the **app** registered, not just
    /// one an extension registered — the bridge is bidirectional or it is
    /// not a bridge.
    @Test
    func executeCommandReachesAnAppRegisteredCommand() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        var appRan = false
        registry.register(AppCommand(id: "app.ping", title: "Ping", run: { _ in
            appRan = true
            return "pong"
        }))
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                globalThis.exec = function (id) {
                    vscode.commands.executeCommand(id).then(
                        function (value) { globalThis.__settled = { ok: true, value: value }; },
                        function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                    );
                };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.exec('app.ping');")

        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(appRan)
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("value")?.toString() == "pong")
    }

    // MARK: - Disposable and teardown

    /// The `Disposable` `registerCommand` returns actually unregisters the
    /// command, and calling `dispose()` a second time is not an error —
    /// VS Code's own `Disposable` contract.
    @Test
    func theDisposableUnregistersAndIsIdempotent() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.disposable = vscode.commands.registerCommand('ext.temp', function () { return 'temp'; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        #expect(registry.command(id: "ext.temp") != nil)

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.disposable.dispose();")
        #expect(registry.command(id: "ext.temp") == nil)

        let secondDispose = context.evaluateScript("globalThis.disposable.dispose(); 'still-ok';")
        #expect(secondDispose?.toString() == "still-ok")
    }

    /// `MainThreadCommands.dispose()` removes every command it registered —
    /// what a torn-down `ExtensionHost` must do so the palette does not keep
    /// a row that invokes a `JSValue` on a dead `JSContext`.
    @Test
    func disposeRemovesEveryCommandItRegistered() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.commands.registerCommand('ext.one', function () {});
                vscode.commands.registerCommand('ext.two', function () {});
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        #expect(Set(registry.allCommands.map(\.id)) == ["ext.one", "ext.two"])

        commands.dispose()

        #expect(registry.command(id: "ext.one") == nil)
        #expect(registry.command(id: "ext.two") == nil)
    }

    // MARK: - Ruling 5: duplicates

    /// Registering the same id twice from **one** extension raises a JS
    /// exception (Ruling 5), and the first registration is left intact.
    @Test
    func duplicateRegistrationFromOneExtensionRaisesAndKeepsTheFirst() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.commands.registerCommand('ext.dup', function () { return 'first'; });
                globalThis.secondError = null;
                try {
                    vscode.commands.registerCommand('ext.dup', function () { return 'second'; });
                } catch (error) {
                    globalThis.secondError = error.message;
                }
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.secondError")?.toString() == "command 'ext.dup' already exists")

        let result = try registry.execute(id: "ext.dup", arguments: [])
        #expect(result as? String == "first")
    }

    // MARK: - Ruling 6: registerCommand raises synchronously

    /// A non-function callback raises a JS exception rather than
    /// registering something nothing could ever run.
    @Test
    func nonFunctionCallbackRaisesRatherThanRegistering() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.err = null;
                try {
                    vscode.commands.registerCommand('ext.bad', 'not a function');
                } catch (error) {
                    globalThis.err = error.message;
                }
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.err")?.toString()
            == "registerCommand's callback must be a function.")
        #expect(registry.command(id: "ext.bad") == nil)
    }

    // MARK: - Ruling 7: thisArg

    /// `thisArg`, when present and neither `undefined` nor `null`, binds
    /// `this` for the callback.
    @Test
    func thisArgBindsForTheCallback() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var obj = { label: 'ctx' };
                vscode.commands.registerCommand('ext.thisArg', function () {
                    globalThis.seenLabel = this.label;
                }, obj);
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        try registry.execute(id: "ext.thisArg")

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.seenLabel")?.toString() == "ctx")
    }

    // MARK: - Ruling 8: getCommands

    /// `getCommands()` lists every id; `getCommands(true)` drops the one
    /// that begins with `_`.
    @Test
    func getCommandsFiltersInternalIds() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.commands.registerCommand('ext.visible', function () {});
                vscode.commands.registerCommand('_ext.hidden', function () {});
                globalThis.__all = null;
                globalThis.__filtered = null;
                vscode.commands.getCommands().then(function (ids) { globalThis.__all = ids; });
                vscode.commands.getCommands(true).then(function (ids) { globalThis.__filtered = ids; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let all = try #require(await waitForGlobal(context, "globalThis.__all"))
        let filtered = try #require(await waitForGlobal(context, "globalThis.__filtered"))

        let allIDs = (all.toArray() as? [String]) ?? []
        let filteredIDs = (filtered.toArray() as? [String]) ?? []

        #expect(Set(allIDs) == ["ext.visible", "_ext.hidden"])
        #expect(filteredIDs == ["ext.visible"])
    }

    // MARK: - Ruling 6 verification: pendingException bookkeeping

    /// The host's `pendingException` bookkeeping survives a `registerCommand`
    /// that raises: a later `defineVSCodeMember` call must not fail, and must
    /// not report a stale message from the exception raised above. This is
    /// the empirical check Ruling 6 asks for, not just an argument from
    /// reading `ExtensionHost.apply(_:to:)`.
    @Test
    func pendingExceptionBookkeepingSurvivesARaisedException() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.commands.registerCommand('ext.dup', function () {});
                try {
                    vscode.commands.registerCommand('ext.dup', function () {});
                } catch (error) {
                    // Swallowed deliberately: the extension already saw its
                    // own exception. What this test pins is what the *host*
                    // does with `pendingException` afterwards, not this catch.
                }
                // Captured now, called later, exactly as
                // `aMemberDefinedAfterActivationIsLiveImmediately` does in
                // `ExtensionHostTests` — `vscode` is a `require('vscode')`
                // module-scope binding, not a JS global, so a member defined
                // after activation is reached through a closure like this one
                // rather than a bare `vscode....` expression handed to
                // `evaluateScript`.
                globalThis.callReal = function () {
                    return vscode.window.showSomethingReal();
                };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        // If `registerCommand`'s raise had left `pendingException` set, this
        // call would throw `vscodeMemberNotDefinable` carrying that stale
        // message instead of succeeding.
        let real: @convention(block) () -> String = { "ok" }
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "showSomethingReal", implementation: real)

        let context = try #require(host.javaScriptContext)
        let answer = context.evaluateScript("globalThis.callReal()")
        #expect(answer?.toString() == "ok")
    }

    // MARK: - registerTextEditorCommand stays a stub

    /// Implementing the three members above must leave
    /// `registerTextEditorCommand` exactly as the shim made it: a throwing
    /// stub, recorded in the ledger.
    @Test
    func registerTextEditorCommandRemainsAThrowingStub() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let ledger = NotImplementedLedger()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.err = null;
                try {
                    vscode.commands.registerTextEditorCommand('ext.textEditor', function () {});
                } catch (error) {
                    globalThis.err = error.name;
                }
            };
            """,
            in: directory,
            ledger: ledger
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.err")?.toString() == "NotImplementedError")
        #expect(ledger.accesses.map(\.memberPath) == ["vscode.commands.registerTextEditorCommand"])
    }
}
