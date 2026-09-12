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

        // The callback's value crosses back untouched, so what the registry
        // hands over is the `JSValue` the callback returned — not a bridged
        // Swift `String`. The conversion is the reader's to make, here, rather
        // than something the adaptor does silently on the way past.
        let result = try #require(try registry.execute(id: "ext.dup", arguments: []) as? JSValue)
        #expect(result.toString() == "first")
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

        // Asserted as an ordered array, not a `Set`: Ruling 8 says ids come
        // back "in registration order", and a `Set` comparison would leave
        // that half of the ruling pinned by nothing.
        #expect(allIDs == ["ext.visible", "_ext.hidden"])
        #expect(filteredIDs == ["ext.visible"])
    }

    // MARK: - Ruling 6 verification: a raise leaves the host usable

    /// A `registerCommand` that raises — where "raises" means the exception
    /// genuinely escapes into `ExtensionHost`'s own `exceptionHandler`, not
    /// into a JavaScript `catch` the test wrote for it — leaves the host and
    /// its context perfectly usable afterwards.
    ///
    /// That distinction is the setup, not the claim. An exception an extension
    /// catches never reaches the host's handler at all, so a test built that
    /// way proves that an interaction which cannot happen does not happen.
    /// Here the duplicate registration is triggered from a bare
    /// `evaluateScript`, with nothing between it and the host: JavaScriptCore
    /// reports it to the context's handler, which is the one that writes
    /// `pendingException`.
    ///
    /// What is asserted afterwards is deliberately modest, and the reason is
    /// worth writing down so nobody re-asserts the stronger thing: this test
    /// **cannot** detect a stale `pendingException`, because every reader of
    /// that field clears it first — `ExtensionHost.apply` opens with
    /// `pendingException = nil` before it invokes `defineMember`. A
    /// `defineVSCodeMember` throwing `vscodeMemberNotDefinable` with a stale
    /// message is not a failure mode this call has. The falsifiable claims
    /// left are the ones that matter for Ruling 6's raise: the raise really
    /// escaped, the first registration survived, and a member defined after it
    /// is live. The "does a callback's throw stay out of the host's
    /// bookkeeping" question is pinned instead by
    /// `aThrowingCallbackRejectsAndNeverReachesTheHostsBookkeeping` below,
    /// whose first half puts an exception into the one window where the
    /// answer is observable at all and shows what the host does with it.
    @Test
    func aRaisedRegisterCommandExceptionLeavesTheHostUsable() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.commands.registerCommand('ext.dup', function () {});
                // Deliberately *not* wrapped in a `try`: called below from
                // `evaluateScript`, so the duplicate's exception leaves
                // JavaScript entirely and lands in the host's handler.
                globalThis.registerDuplicate = function () {
                    vscode.commands.registerCommand('ext.dup', function () {});
                };
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

        let context = try #require(host.javaScriptContext)

        // `evaluateScript` answers `undefined` rather than the trailing
        // expression exactly when the script threw, so this pins that the
        // exception really did escape to the host instead of being swallowed
        // somewhere on the way. Without the throw, this would be `'reached'`.
        let raised = context.evaluateScript("globalThis.registerDuplicate(); 'reached';")
        #expect(raised?.isUndefined == true)
        #expect(registry.allCommands.map(\.id) == ["ext.dup"])

        // A member defined after the raise is live, and reachable through the
        // closure `activate` captured. Not an assertion about
        // `pendingException`: `apply` clears it before `defineMember`, so a
        // stale value could not surface here even if one existed.
        let real: @convention(block) () -> String = { "ok" }
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "showSomethingReal", implementation: real)

        let answer = context.evaluateScript("globalThis.callReal()")
        #expect(answer?.toString() == "ok")
    }

    // MARK: - A command callback's exception belongs to the adaptor

    /// A command callback that throws rejects `executeCommand`'s promise with
    /// the extension's own error — and, crucially, does **not** reach
    /// `ExtensionHost.pendingException` on the way.
    ///
    /// The ordering here is the damaging one, reproduced deliberately. The
    /// extension's `activate` is `async`, so `callActivate` returns while its
    /// promise is still pending and the host then reads `pendingException` to
    /// decide whether activation threw. A command callback that throws inside
    /// that synchronous window used to write there, so the host failed the
    /// extension with `activationThrew` carrying a message from a command
    /// dispatch that had nothing to do with `activate()`. `await
    /// host.activate()` returning normally *is* the assertion that it no
    /// longer does: were the exception still reaching the host's handler, this
    /// line would throw.
    ///
    /// That assertion is only worth anything if the read point is live, so
    /// **part one is a control that demonstrates it rather than assuming it**.
    /// `pendingException` is `private`, unreachable even under `@testable`,
    /// and every reader of it clears it first — `apply`, `defineMember`,
    /// `evaluate` and `callActivate` all open with `pendingException = nil`.
    /// So there is exactly one span in which a write to it is both possible
    /// and observable: the one `callActivate` opens, between its own clear and
    /// the read immediately after `invokeMethod("callActivate", …)` that turns
    /// a non-`nil` value into `ExtensionHostError.activationThrew`. The
    /// control puts an exception into precisely that span — an `activate` that
    /// returns a thenable whose `then` *getter* throws, which the shim reads
    /// outside its own `try` for exactly this reason — and shows activation
    /// failing with the getter's message. Part two then runs a command
    /// callback's throw through the same span and requires activation to
    /// succeed. Regress `VSCodeAPI.call` to let a callback's throw escape and
    /// part two fails on `try await host.activate()`.
    @Test
    func aThrowingCallbackRejectsAndNeverReachesTheHostsBookkeeping() async throws {
        // Part one — the control. An exception raised inside the window the
        // host reads really does fail activation, so the read point is live.
        let probeDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: probeDirectory) }
        let probeHost = try makeHost(
            source: """
            var unused = 1;
            exports.activate = function () {
                return { get then() { throw new Error('window-probe'); } };
            };
            """,
            in: probeDirectory
        )
        defer { probeHost.dispose() }
        let probeCommands = MainThreadCommands(registry: CommandRegistry())
        try install(probeCommands, on: probeHost)
        do {
            try await probeHost.activate()
            Issue.record("An exception raised inside callActivate's window must fail activation.")
        } catch let error as ExtensionHostError {
            guard case let .activationThrew(_, message) = error else {
                Issue.record("Expected activationThrew, got \(error)")
                return
            }
            #expect(message.contains("window-probe"), "message was: \(message)")
        }

        // Part two — the claim. Same window, a command callback's throw.
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = async function () {
                vscode.commands.registerCommand('ext.throws', function () {
                    var error = new Error('callback-boom');
                    error.name = 'CallbackError';
                    throw error;
                });
                globalThis.__settled = null;
                vscode.commands.executeCommand('ext.throws').then(
                    function (value) { globalThis.__settled = { ok: true, value: value }; },
                    function (error) {
                        globalThis.__settled = { ok: false, message: error.message, name: error.name };
                    }
                );
                await Promise.resolve();
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)

        // Would throw `activationThrew(message: "CallbackError: callback-boom")`
        // if the callback's exception still landed in `pendingException`.
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(settled.forProperty("message")?.toString() == "callback-boom")
        // The raw error object, not a paraphrase: the extension's own
        // subclassed `name` survives the round trip.
        #expect(settled.forProperty("name")?.toString() == "CallbackError")
    }

    /// The palette's path — `CommandRegistry.execute(id:)`, which returns
    /// `Void` — swallows a throwing callback rather than trapping or leaking
    /// the exception, because there is no caller to tell. The command after it
    /// must still run.
    @Test
    func aThrowingCallbackOnTheSwiftPathIsSwallowed() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.laterRan = false;
                vscode.commands.registerCommand('ext.throws', function () { throw new Error('boom'); });
                vscode.commands.registerCommand('ext.later', function () { globalThis.laterRan = true; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        // Does not throw: `CommandRegistryError` is about *dispatch* refusing,
        // and the registry is deliberately kept ignorant of JavaScript.
        try registry.execute(id: "ext.throws")
        try registry.execute(id: "ext.later")

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.laterRan")?.toBool() == true)
        // And the extension context is still usable afterwards — the absorbed
        // exception left nothing latched anywhere.
        #expect(context.evaluateScript("1 + 1")?.toInt32() == 2)
    }

    // MARK: - Values cross the boundary untouched

    /// An `async` command's eventual value arrives at `await
    /// executeCommand(...)`.
    ///
    /// The failure this replaces: the callback's returned `Promise` was pushed
    /// through `toObject()`, which yields an empty dictionary for an object
    /// with no enumerable own properties, so `await` resolved with `{}`
    /// instead of the number the command computed — with no error anywhere.
    @Test
    func anAsyncCommandsValueArrivesAtTheAwait() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.commands.registerCommand('ext.async', async function (n) {
                    await Promise.resolve();
                    return n * 2;
                });
                globalThis.__awaited = null;
                globalThis.run = function () {
                    (async function () {
                        var value = await vscode.commands.executeCommand('ext.async', 21);
                        globalThis.__awaited = { type: typeof value, value: value };
                    })();
                };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.run();")

        let awaited = try #require(await waitForGlobal(context, "globalThis.__awaited"))
        #expect(awaited.forProperty("type")?.toString() == "number")
        #expect(awaited.forProperty("value")?.toInt32() == 42)
    }

    /// An `async` command callback that throws **rejects**, and the rejection
    /// reaches `await executeCommand(...)` as the extension's own error.
    ///
    /// The distinction this pins is the one a synchronous-throw test cannot:
    /// an `async` function does not throw at all from the adaptor's point of
    /// view — the call returns a pending promise and succeeds, and the failure
    /// arrives on a later microtask. So nothing on the `.threw` path runs, and
    /// the rejection handler the adaptor attaches for the palette's benefit
    /// must not consume it. This asserts the second half of that: the promise
    /// handed back still rejects, with the same `Error` subclass and message.
    @Test
    func anAsyncCallbacksRejectionReachesTheAwait() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.commands.registerCommand('ext.asyncThrows', async function () {
                    await Promise.resolve();
                    var error = new Error('disk full');
                    error.name = 'AsyncCommandError';
                    throw error;
                });
                globalThis.__asyncSettled = null;
                globalThis.run = function () {
                    (async function () {
                        try {
                            var value = await vscode.commands.executeCommand('ext.asyncThrows');
                            globalThis.__asyncSettled = { ok: true, value: String(value) };
                        } catch (error) {
                            globalThis.__asyncSettled =
                                { ok: false, message: error.message, name: error.name };
                        }
                    })();
                };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.run();")

        let settled = try #require(await waitForGlobal(context, "globalThis.__asyncSettled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(settled.forProperty("message")?.toString() == "disk full")
        #expect(settled.forProperty("name")?.toString() == "AsyncCommandError")
    }

    /// The palette's path — `CommandRegistry.execute(id:)`, which returns
    /// `Void` — attaches a rejection handler to a thenable result, so an
    /// `async` callback's rejection is reported rather than dropped in
    /// silence.
    ///
    /// The log line itself is not assertable from here, so this pins the
    /// machinery that produces it, which is the part a regression would
    /// delete: the callback returns a hand-rolled thenable that records how
    /// its `then` was called, and the assertions are that the adaptor called
    /// it exactly once on this path, passed a real function as the rejection
    /// arm, and that invoking that arm reaches Swift without throwing back
    /// into JavaScript. Remove `VSCodeAPI.observeRejection` from `invoke` and
    /// `then` is never called at all and every assertion below fails.
    ///
    /// A hand-rolled thenable rather than a real rejected `Promise` for two
    /// reasons: a native promise's reactions are microtasks, so nothing would
    /// have happened by the time `execute(id:)` returns and the test would be
    /// asserting on a queue rather than on the adaptor; and a real rejected
    /// promise with no handler attached is exactly the unobservable case this
    /// is meant to rule out.
    @Test
    func aPaletteDispatchObservesAnAsyncCallbacksRejection() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__observed = null;
                vscode.commands.registerCommand('ext.rejects', function () {
                    return {
                        then: function (onFulfilled, onRejected) {
                            var record = {
                                calls: globalThis.__observed ? globalThis.__observed.calls + 1 : 1,
                                rejectionArmIsFunction: typeof onRejected === 'function',
                                delivered: false
                            };
                            globalThis.__observed = record;
                            if (typeof onRejected === 'function') {
                                onRejected(new Error('disk full'));
                                record.delivered = true;
                            }
                        }
                    };
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        // The palette's dispatch: no caller to reject, so the adaptor's own
        // observer is the only thing that can notice the failure.
        try registry.execute(id: "ext.rejects")

        let context = try #require(host.javaScriptContext)
        let observed = try #require(context.evaluateScript("globalThis.__observed"))
        #expect(observed.isObject)
        #expect(observed.forProperty("calls")?.toInt32() == 1)
        #expect(observed.forProperty("rejectionArmIsFunction")?.toBool() == true)
        // `delivered` is set *after* the rejection arm returns, so it is also
        // the assertion that calling into Swift and back left JavaScript
        // running rather than unwinding.
        #expect(observed.forProperty("delivered")?.toBool() == true)
        #expect(context.evaluateScript("1 + 1")?.toInt32() == 2)
    }

    /// The extension's own path — `executeCommand` — attaches **no** rejection
    /// observer, because the extension is the caller and owns the failure.
    ///
    /// The falsifiable negative for the pair above, and the only one of the
    /// three that can fail if the caller-aware bit is dropped: delete
    /// `dispatchHasCaller` and `invoke` observes on both paths, so `then` is
    /// called here and `__observed` stops being `null`. The other two tests
    /// pass either way.
    ///
    /// The returned thenable is **discarded** deliberately. An `await` would
    /// call `then` itself — proving nothing about who called it — so the test
    /// drops the result on the floor, which is also the shape that would make
    /// an over-eager observer's log line pure noise. Nothing in the adaptor
    /// may call `then` on that path: `VSCodeAPI.settledPromise` only *reads*
    /// the property to decide the value is already a promise, and hands the
    /// extension's own object straight back.
    @Test
    func anAwaitedDispatchGetsNoObserverBecauseTheExtensionOwnsTheRejection() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__observed = null;
                globalThis.__dispatched = null;
                vscode.commands.registerCommand('ext.rejects', function () {
                    return {
                        then: function (onFulfilled, onRejected) {
                            globalThis.__observed = { calls: 1 };
                        }
                    };
                });
                globalThis.run = function () {
                    vscode.commands.executeCommand('ext.rejects');
                    globalThis.__dispatched = { done: true };
                };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.run();")

        // `__dispatched` is the liveness control: without it, a `run` that
        // threw before reaching `executeCommand` would leave `__observed`
        // `null` and the assertion below would pass for the wrong reason.
        let dispatched = try #require(await waitForGlobal(context, "globalThis.__dispatched"))
        #expect(dispatched.forProperty("done")?.toBool() == true)

        let observed = try #require(context.evaluateScript("globalThis.__observed"))
        #expect(observed.isNull)
    }

    /// An extension that tries to pre-empt `__vscodeAPITrampoline` from its
    /// own top-level module code never gets the chance: the real dispatch
    /// still runs, and the impostor is a silent no-op.
    ///
    /// This test used to pin the opposite outcome — a rejection — because the
    /// trampoline was installed lazily, on the *first dispatch*. That left a
    /// window between a context's creation and that first dispatch during
    /// which an extension's own top-level code ran first and could assign an
    /// impostor into `globalThis.__vscodeAPITrampoline` ahead of the host,
    /// hijacking every later dispatch. Task 5.4a closed that window: `VSCodeAPI`
    /// now installs the trampoline **eagerly**, inside `ExtensionHost.installRuntime`,
    /// which runs before `evaluateModule` executes a single line of the
    /// extension's own source (see `ExtensionHost.performActivation`, which
    /// calls the former strictly before the latter). By the time this
    /// fixture's top-level `globalThis.__vscodeAPITrampoline = { … }` line
    /// runs, the real trampoline is already sitting under that name via
    /// `Object.defineProperty(..., { writable: false, configurable: false })`.
    /// The extension module has no `'use strict'` pragma, so a plain `=`
    /// assignment against a non-writable, non-configurable property is not a
    /// `TypeError` — sloppy-mode JavaScript silently drops it. The impostor
    /// object is simply never installed, the real trampoline answers the
    /// dispatch, and the real callback runs.
    ///
    /// This removes the one test route this suite had onto
    /// `CallOutcome.unavailable`'s reject path for a *whole-object*
    /// replacement (see the history of this test for that version) — but it
    /// does not close every route onto that path, and an earlier version of
    /// this doc claimed it did. It was wrong: a *member-level* hijack —
    /// `globalThis.__vscodeAPITrampoline.call = function () { … }`, leaving
    /// the binding itself untouched — was reachable before this fix round,
    /// because the binding-level freeze this test above describes
    /// (`writable: false, configurable: false` on the `__vscodeAPITrampoline`
    /// name) says nothing about the *object* under that name; only the
    /// binding was protected, not `helper.call` itself, and
    /// `helperFunction(_:in:)` re-reads `.call` off that object on every
    /// dispatch. This fix round closes that hole too, by having
    /// `VSCodeAPI.helperSource` call `Object.freeze(helper)` on the
    /// trampoline object itself before ever caching it — see
    /// `VSCodeAPI.sharedHelper(in:)`'s own doc for the two-layer picture this
    /// leaves. `theMemberLevelHijackIsAlsoIgnored` below is the test that pins
    /// the closure of that specific hole, the way this test pins the
    /// whole-object case.
    ///
    /// **This test still depends on the trampoline's global name**, and that
    /// is the same deliberate trade the old version made: the name is already
    /// a documented part of the design, with its own doc comment on
    /// `helperGlobalName`, so a test that must be updated when it changes is
    /// honest coupling.
    @Test
    func theEagerlyInstalledTrampolineIgnoresALatePreemptionAttempt() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            // Top-level, so it runs before anything else in this module —
            // but strictly after the host's eager install inside
            // installRuntime. Against a non-writable, non-configurable
            // property, this plain assignment is a silent sloppy-mode
            // no-op: it neither throws nor replaces the real trampoline.
            globalThis.__vscodeAPITrampoline = {
                call: function () { return { impostor: true }; },
                thenOf: function () { return { impostor: true }; }
            };
            exports.activate = function () {
                globalThis.__callbackRan = false;
                vscode.commands.registerCommand('ext.preempted', function () {
                    globalThis.__callbackRan = true;
                    return 'the real callback ran';
                });
                globalThis.__settled = null;
                globalThis.run = function () {
                    (async function () {
                        try {
                            var value = await vscode.commands.executeCommand('ext.preempted');
                            globalThis.__settled = { ok: true, value: String(value) };
                        } catch (error) {
                            globalThis.__settled = { ok: false, message: String(error.message) };
                        }
                    })();
                };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.run();")

        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        // Resolved, not rejected: the impostor never displaced the real
        // trampoline, so the real dispatch ran to completion.
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("value")?.toString() == "the real callback ran")

        // The real callback ran — the impostor was never called at all.
        let callbackRan = try #require(context.evaluateScript("globalThis.__callbackRan"))
        #expect(callbackRan.toBool() == true)
    }

    /// The narrower hijack the test above's doc calls out by name: instead of
    /// replacing `globalThis.__vscodeAPITrampoline` wholesale, the extension
    /// only overwrites its `.call` member, leaving the binding itself alone.
    /// Before this fix round that member-level write succeeded silently — the
    /// binding-level `writable: false, configurable: false` never protected
    /// the object's own properties — and the dispatch below would have
    /// observed the impostor's `{ impostor: true }` instead of the real
    /// command result. `VSCodeAPI.helperSource` now calls
    /// `Object.freeze(helper)` before caching the trampoline, so this
    /// assignment is refused too, on the same real, host-installed context
    /// `theEagerlyInstalledTrampolineIgnoresALatePreemptionAttempt` uses.
    @Test
    func theMemberLevelHijackIsAlsoIgnored() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            // A member-level hijack, not a whole-object replacement: the
            // binding itself is untouched, only `.call` is targeted.
            globalThis.__hijackThrew = false;
            try {
                globalThis.__vscodeAPITrampoline.call = function () {
                    return { impostor: true };
                };
            } catch (error) {
                // A strict-mode extension would land here instead of
                // silently no-opping; either outcome is consistent with the
                // trampoline object being frozen.
                globalThis.__hijackThrew = true;
            }
            exports.activate = function () {
                globalThis.__callbackRan = false;
                vscode.commands.registerCommand('ext.memberHijacked', function () {
                    globalThis.__callbackRan = true;
                    return 'the real callback ran';
                });
                globalThis.__settled = null;
                globalThis.run = function () {
                    (async function () {
                        try {
                            var value = await vscode.commands.executeCommand('ext.memberHijacked');
                            globalThis.__settled = { ok: true, value: String(value) };
                        } catch (error) {
                            globalThis.__settled = { ok: false, message: String(error.message) };
                        }
                    })();
                };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.run();")

        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("value")?.toString() == "the real callback ran")

        let callbackRan = try #require(context.evaluateScript("globalThis.__callbackRan"))
        #expect(callbackRan.toBool() == true)
    }

    /// The other half of item 2's freezing (F2): `vscode.Uri.parse` reaches
    /// extension code the same way `vscode.Uri.file` does in
    /// `ExtensionHostTests.distinctMembersAreRecordedSeparatelyIncludingFetch`,
    /// but through a real, activated `ExtensionHost` here rather than a bare
    /// `JSContext` — the "on a context the host installed into" case item 2's
    /// fix round called for. Before `Uri.swift`'s `uriClassSource` froze
    /// `Uri` and `Uri.prototype`, `Uri.parse = ...` from extension code would
    /// have succeeded, and every later `vscode.Uri.parse(...)` call in this
    /// context — including the one `uriValue(for:in:)` itself makes when
    /// bridging a Swift `URL` back into JavaScript — would have run the
    /// extension's replacement instead of the host's.
    @Test
    func vscodeUriParseReassignmentIsRefusedThroughARealHost() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var originalParse = vscode.Uri.parse;
                globalThis.__reassignThrew = false;
                try {
                    vscode.Uri.parse = function () { return 'impostor'; };
                } catch (error) {
                    globalThis.__reassignThrew = true;
                }
                globalThis.__parseUnchanged = vscode.Uri.parse === originalParse;
                globalThis.__classFrozen = Object.isFrozen(vscode.Uri);
                globalThis.__prototypeFrozen = Object.isFrozen(vscode.Uri.prototype);
                globalThis.__stillWorks = vscode.Uri.parse('file:///tmp') instanceof vscode.Uri;
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        // Either sloppy-mode silent no-op or strict-mode `TypeError` is a
        // valid outcome of a frozen object rejecting a write; what matters is
        // that the real `Uri.parse` is what every subsequent call finds.
        let parseUnchanged = try #require(context.evaluateScript("globalThis.__parseUnchanged"))
        #expect(parseUnchanged.toBool() == true)
        let classFrozen = try #require(context.evaluateScript("globalThis.__classFrozen"))
        #expect(classFrozen.toBool() == true)
        let prototypeFrozen = try #require(context.evaluateScript("globalThis.__prototypeFrozen"))
        #expect(prototypeFrozen.toBool() == true)
        let stillWorks = try #require(context.evaluateScript("globalThis.__stillWorks"))
        #expect(stillWorks.toBool() == true)
    }

    /// The real-host counterpart `UriTests`' header now points to instead of
    /// the false claim it used to make: `vscode.Uri` reached through a real,
    /// activated `ExtensionHost` — not a bare `JSContext` — behaves like the
    /// class `UriTests` exercises directly, and stays usable after the
    /// activation ceremony `ExtensionHost.installRuntime` runs around it.
    @Test
    func vscodeUriIsUsableAndFrozenThroughARealHost() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var uri = vscode.Uri.file('/tmp/example.txt');
                globalThis.__result = {
                    isUri: uri instanceof vscode.Uri,
                    scheme: uri.scheme,
                    path: uri.path,
                    frozen: Object.isFrozen(vscode.Uri) && Object.isFrozen(vscode.Uri.prototype)
                };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let result = try #require(context.evaluateScript("globalThis.__result"))
        #expect(result.forProperty("isUri")?.toBool() == true)
        #expect(result.forProperty("scheme")?.toString() == "file")
        #expect(result.forProperty("path")?.toString() == "/tmp/example.txt")
        #expect(result.forProperty("frozen")?.toBool() == true)
    }

    /// An object passed to `executeCommand` and handed straight back is the
    /// **same** object in JavaScript — `===`, with the mutations the callback
    /// made visible to the caller.
    ///
    /// VS Code passes command arguments by reference, and the moment tasks
    /// 5.4–5.7 introduce a typed object (`vscode.Uri`, `Range`), a copy would
    /// arrive stripped of its prototype and every method on it.
    @Test
    func objectsCrossExecuteCommandByReference() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            function Marker(label) { this.label = label; }
            Marker.prototype.describe = function () { return 'marker:' + this.label; };
            exports.activate = function () {
                vscode.commands.registerCommand('ext.identity', function (marker) {
                    marker.touched = true;
                    return marker;
                });
                globalThis.__identity = null;
                globalThis.run = function () {
                    var sent = new Marker('one');
                    vscode.commands.executeCommand('ext.identity', sent).then(function (got) {
                        globalThis.__identity = {
                            same: got === sent,
                            described: typeof got.describe === 'function' ? got.describe() : null,
                            mutationSeenByCaller: sent.touched === true
                        };
                    });
                };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.run();")

        let identity = try #require(await waitForGlobal(context, "globalThis.__identity"))
        #expect(identity.forProperty("same")?.toBool() == true)
        #expect(identity.forProperty("described")?.toString() == "marker:one")
        #expect(identity.forProperty("mutationSeenByCaller")?.toBool() == true)
    }

    /// A callback that returns nothing resolves with `undefined`; one that
    /// returns `null` resolves with `null`. An extension's `if (result ===
    /// undefined)` takes the wrong branch if those are conflated, and
    /// `toObject()` conflated them — both became `nil`, and `nil as Any`
    /// bridges back as `null`.
    ///
    /// The third case is the **app**-registered command, and it is a separate
    /// route to the same mistake rather than a repeat of the first one. An
    /// `AppCommand` built with the legacy `() -> Void` initializer wraps its
    /// closure as `{ _ in run(); return nil }`, so every command the app
    /// already contributes answers `Optional<Any>.none` — and handing that
    /// straight to `JSValue(newPromiseResolvedWithResult:)` bridges it through
    /// `NSNull` and reaches the extension as `null`. There is no JavaScript
    /// callback anywhere on that path to make it `undefined` for free, which
    /// is exactly why it needs its own case here.
    @Test
    func undefinedAndNullResultsStayDistinct() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.commands.registerCommand('ext.nothing', function () {});
                vscode.commands.registerCommand('ext.null', function () { return null; });
                globalThis.__shapes = null;
                globalThis.run = function () {
                    var shapes = {};
                    function describe(value) {
                        if (value === undefined) { return 'undefined'; }
                        if (value === null) { return 'null'; }
                        return 'other:' + String(value);
                    }
                    function record(key) {
                        return function (value) {
                            shapes[key] = describe(value);
                            if (shapes.nothing && shapes.null && shapes.app) {
                                globalThis.__shapes = shapes;
                            }
                        };
                    }
                    vscode.commands.executeCommand('ext.nothing').then(record('nothing'));
                    vscode.commands.executeCommand('ext.null').then(record('null'));
                    vscode.commands.executeCommand('app.void').then(record('app'));
                };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)

        // Bound to a `let` of the exact closure type first: `AppCommand` has
        // two `run:` overloads, and a bare trailing `{ }` leaves the compiler
        // to guess which one this is.
        let voidRun: () -> Void = { }
        registry.register(AppCommand(id: "app.void", title: "Void", run: voidRun))

        try await host.activate()

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.run();")

        let shapes = try #require(await waitForGlobal(context, "globalThis.__shapes"))
        #expect(shapes.forProperty("nothing")?.toString() == "undefined")
        #expect(shapes.forProperty("null")?.toString() == "null")
        #expect(shapes.forProperty("app")?.toString() == "undefined")
    }

    // MARK: - Unregistering removes this adaptor's registration, not the id

    /// A `Disposable` held past a *later* registration of the same id removes
    /// nothing.
    ///
    /// The scenario, end to end: the extension registers an id, the app then
    /// registers that same id (Ruling 5 permits the shadowing, and `register`
    /// replaces in place), and only afterwards does the extension's
    /// `Disposable` fire. By id alone that deletes the app's brand-new
    /// command, permanently, with only `register`'s collision warning anywhere
    /// in the log. The registration token is what makes it the no-op it should
    /// be.
    @Test
    func aStaleDisposableDoesNotRemoveSomebodyElsesCommand() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.disposable =
                    vscode.commands.registerCommand('shared.id', function () { return 'extension'; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        // Somebody else takes the id over, replacing the extension's
        // registration in place.
        registry.register(AppCommand(id: "shared.id", title: "App owns it now", run: { _ in "app" }))

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.disposable.dispose();")

        #expect(registry.command(id: "shared.id")?.title == "App owns it now")
        let answer = try registry.execute(id: "shared.id", arguments: [])
        #expect(answer as? String == "app")
    }

    /// The same guard on the wholesale path: `MainThreadCommands.dispose()`
    /// unregisters what the adaptor registered, and leaves an id another
    /// registrant has since taken over alone.
    @Test
    func adaptorDisposeLeavesAnIDSomebodyElseHasTakenOver() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.commands.registerCommand('shared.id', function () { return 'extension'; });
                vscode.commands.registerCommand('ext.own', function () { return 'own'; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        registry.register(AppCommand(id: "shared.id", title: "App owns it now", run: { _ in "app" }))

        commands.dispose()

        #expect(registry.command(id: "ext.own") == nil)
        #expect(registry.command(id: "shared.id")?.title == "App owns it now")
    }

    /// A `Disposable` minted before `dispose()` does not unregister the
    /// adaptor's **own** later re-registration of the same id.
    ///
    /// This is the case a by-id `Disposable` gets wrong even with every other
    /// guard in place, and it needs no second registrant to reproduce. The
    /// stale `Disposable` never fired, so its idempotence flag is still
    /// `false`; `dispose()` emptied `ownedCallbacks`, so the "do I still own
    /// this id" check passes again the moment the same id is re-registered;
    /// and the registry genuinely holds a registration under that id, so
    /// `unregister(id:)` would happily remove it. Only comparing the captured
    /// `CommandRegistration` against the one the adaptor now holds tells the
    /// two registrations apart.
    ///
    /// Live in practice as soon as an extension is deactivated and
    /// reactivated, or a host is torn down and rebuilt against the same
    /// registry — `context.subscriptions` from the first run outlives it by
    /// exactly one `dispose()` that the extension's own teardown forgot.
    @Test
    func aDisposableFromBeforeDisposeDoesNotRemoveTheReRegisteredCommand() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.stale =
                    vscode.commands.registerCommand('ext.recycled', function () { return 'first'; });
                globalThis.reregister = function () {
                    vscode.commands.registerCommand('ext.recycled', function () { return 'second'; });
                };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(commands, on: host)
        try await host.activate()

        // Teardown, then the same adaptor takes the id again — a second
        // registration with a new token, which `globalThis.stale` knows
        // nothing about.
        commands.dispose()
        #expect(registry.command(id: "ext.recycled") == nil)
        host.javaScriptContext?.evaluateScript("globalThis.reregister();")
        #expect(registry.command(id: "ext.recycled") != nil)

        host.javaScriptContext?.evaluateScript("globalThis.stale.dispose();")

        let context = try #require(host.javaScriptContext)
        #expect(registry.command(id: "ext.recycled") != nil)
        let answer = try #require(try registry.execute(id: "ext.recycled", arguments: []) as? JSValue)
        #expect(answer.toString() == "second")
        #expect(context.evaluateScript("1 + 1")?.toInt32() == 2)
    }

    // MARK: - A torn-down adaptor

    /// Once the adaptor has been deallocated while JavaScript still holds the
    /// installed functions, all three members answer in the shape their return
    /// type promises: `registerCommand` raises, and the two `Thenable`s reject.
    ///
    /// What none of them may do is answer `undefined`, which is what returning
    /// `nil` from the block reaches JavaScript as. For `executeCommand` and
    /// `getCommands` that makes the extension's own `.then` throw
    /// synchronously — precisely the failure Ruling 6 exists to prevent, in its
    /// worst form. For `registerCommand` it lets the extension push `undefined`
    /// onto `context.subscriptions` and believe it registered a command.
    @Test
    func aTornDownAdaptorRaisesOrRejectsButNeverAnswersUndefined() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = CommandRegistry()
        var commands: MainThreadCommands? = MainThreadCommands(registry: registry)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__afterTeardown = null;
                globalThis.run = function () {
                    var out = {};
                    function done() {
                        if (out.register && out.execute && out.getCommands) {
                            globalThis.__afterTeardown = out;
                        }
                    }
                    try {
                        vscode.commands.registerCommand('ext.late', function () {});
                        out.register = 'no-throw';
                    } catch (error) {
                        out.register = error.message;
                    }
                    vscode.commands.executeCommand('ext.late').then(
                        function () { out.execute = 'resolved'; done(); },
                        function (error) { out.execute = error.message; done(); }
                    );
                    vscode.commands.getCommands().then(
                        function () { out.getCommands = 'resolved'; done(); },
                        function (error) { out.getCommands = error.message; done(); }
                    );
                    done();
                };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        // Scoped deliberately: a `let` binding at test scope would itself keep
        // the adaptor alive past the `commands = nil` below and the teardown
        // this test is about would never happen.
        if let live = commands { try install(live, on: host) }
        try await host.activate()

        // Nothing else holds the adaptor now: the registry holds no command of
        // its making (this extension's `activate` registers none), and the
        // three installed blocks capture it weakly.
        commands = nil

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.run();")

        let out = try #require(await waitForGlobal(context, "globalThis.__afterTeardown"))
        #expect(out.forProperty("register")?.toString()
            == "vscode.commands.registerCommand is unavailable: this extension's host has been torn down.")
        #expect(out.forProperty("execute")?.toString()
            == "vscode.commands.executeCommand is unavailable: this extension's host has been torn down.")
        #expect(out.forProperty("getCommands")?.toString()
            == "vscode.commands.getCommands is unavailable: this extension's host has been torn down.")
        #expect(registry.command(id: "ext.late") == nil)
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
