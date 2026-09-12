import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A non-suspending `ExtensionInputBoxPresenting` double: it records every
/// request, can invoke `validate` on demand (so a test can drive the
/// round trip from the Swift side as well as from JavaScript), and answers
/// `response`.
///
/// `response` defaults to `nil` — dismissed — deliberately **not** `""`: an
/// empty string is a real, different answer (test 4 pins the distinction),
/// and a double whose default conflated the two would make that test pass
/// for the wrong reason.
@MainActor
private final class RecordingInputBoxPresenter: ExtensionInputBoxPresenting {
    private(set) var requests: [ExtensionInputBoxRequest] = []
    private(set) var lastValidate: ((String) async -> ExtensionInputValidation?)?
    var response: String?

    func presentInputBox(
        _ request: ExtensionInputBoxRequest,
        validate: @escaping (String) async -> ExtensionInputValidation?
    ) async -> String? {
        requests.append(request)
        lastValidate = validate
        return response
    }
}

/// An `ExtensionInputBoxPresenting` double whose `presentInputBox` suspends
/// until the test releases it — the `SuspendingMessagePresenter` shape from
/// `MainThreadWindowTests` (`MainThreadWindowTests.swift:39`), for the same
/// reason: a disposal race is only a race if the presentation is genuinely in
/// flight when `dispose()` runs.
@MainActor
private final class SuspendingInputBoxPresenter: ExtensionInputBoxPresenting {
    private(set) var requests: [ExtensionInputBoxRequest] = []
    private var releaseContinuations: [CheckedContinuation<String?, Never>] = []
    private var enteredWaiters: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func waitUntilEntered(_ count: Int) async {
        if releaseContinuations.count >= count { return }
        await withCheckedContinuation { continuation in
            enteredWaiters.append((count, continuation))
        }
    }

    /// Removes the entry as well as resuming it, matching
    /// `SuspendingMessagePresenter.release(at:with:)`.
    func release(at index: Int, with result: String?) {
        let continuation = releaseContinuations.remove(at: index)
        continuation.resume(returning: result)
    }

    func presentInputBox(
        _ request: ExtensionInputBoxRequest,
        validate: @escaping (String) async -> ExtensionInputValidation?
    ) async -> String? {
        requests.append(request)
        return await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
            let enteredCount = releaseContinuations.count
            let satisfied = enteredWaiters.filter { enteredCount >= $0.threshold }
            enteredWaiters.removeAll { enteredCount >= $0.threshold }
            for waiter in satisfied {
                waiter.continuation.resume()
            }
        }
    }
}

/// The message and quick pick seams, for a suite that presents neither.
/// `MainThreadWindow.init` does not default either argument, so every
/// construction here has to name both, and doubles that record an `Issue`
/// turn a stray call into a failure rather than a silent pass — the same
/// judgement `MainThreadWindowQuickPickTests`' own `UnusedMessagePresenter`
/// makes.
@MainActor
private final class UnusedMessagePresenter: ExtensionMessagePresenting {
    func presentMessage(_ request: ExtensionMessageRequest) async -> Int? {
        Issue.record("presentMessage was called by a suite that exercises no message.")
        return nil
    }
}

@MainActor
private final class UnusedQuickPickPresenter: ExtensionQuickPickPresenting {
    func presentQuickPick(
        _ request: ExtensionQuickPickRequest,
        onHighlight: @escaping (Int) -> Void
    ) async -> [Int]? {
        Issue.record("presentQuickPick was called by a suite that exercises no quick pick.")
        return nil
    }
}

/// `vscode.window.showInputBox` (task 5.5b-iii), wired onto a real
/// `ExtensionHost` and an `ExtensionInputBoxPresenting` double.
///
/// A separate suite from `MainThreadWindowTests` and
/// `MainThreadWindowQuickPickTests` rather than more cases in either: this
/// one exercises a third seam through a third member, with its own request
/// shape and its own validation round trip. The fixtures below are
/// deliberate near-copies of those two files' own — `private` to this suite
/// and not worth promoting into a shared target for one duplicated
/// `makeHost`.
///
/// No conformer of `ExtensionInputBoxPresenting` ships in the module yet
/// (task 5.5b-iv builds the panel), so every presenter here is a double by
/// necessity.
@MainActor
@Suite
struct MainThreadWindowInputBoxTests {

    // MARK: - Fixtures

    private func makeTempDirectory() throws -> URL {
        try ExtensionFixtures.makeTemporaryDirectory("MainThreadWindowInputBoxTests")
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

    /// Installs `showInputBox` onto `vscode.window` and the
    /// `InputBoxValidationSeverity` table onto **`vscode`** — the top-level
    /// namespace, not `vscode.window`, matching
    /// `MainThreadWindow.inputBoxValidationSeverityMembers`'s own doc.
    private func install(_ window: MainThreadWindow, on host: ExtensionHost) throws {
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "showInputBox",
            implementation: window.showInputBox)
        try host.defineVSCodeMember(
            namespacePath: "vscode", name: "InputBoxValidationSeverity",
            implementation: MainThreadWindow.inputBoxValidationSeverityMembers)
    }

    /// Builds a window over `presenter`, installs it on `host`, and
    /// activates.
    private func activate(
        _ host: ExtensionHost,
        presenter: ExtensionInputBoxPresenting
    ) async throws -> MainThreadWindow {
        let window = MainThreadWindow(
            presenter: UnusedMessagePresenter(), quickPickPresenter: UnusedQuickPickPresenter(),
            inputBoxPresenter: presenter,
            notImplementedLedger: host.notImplementedLedger, extensionIdentifier: host.identifier)
        try install(window, on: host)
        try await host.activate()
        return window
    }

    /// Polls `expression` until it evaluates to something other than
    /// `null`/`undefined`, or gives up after two seconds — `MainThreadWindowTests`'
    /// own helper (400 × 5 ms), for the same reason: a `.then()` reaction is a
    /// microtask, never invoked synchronously no matter how settled the
    /// promise already is by the time `evaluateScript` returns.
    private func waitForGlobal(_ context: JSContext, _ expression: String) async throws -> JSValue? {
        for _ in 0..<400 {
            if let value = context.evaluateScript(expression), !value.isNull, !value.isUndefined {
                return value
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        return nil
    }

    // MARK: - 1. No arguments resolves through a request of pure defaults

    /// Kills a mutation to any one of the eight fields `handleShowInputBox`
    /// builds when argument 0 is absent — each is asserted on its own so a
    /// single wrong field names itself rather than hiding behind the other
    /// seven.
    @Test
    func noArgumentsProducesARequestOfPureDefaults() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingInputBoxPresenter()
        presenter.response = "answer"
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showInputBox().then(function (result) {
                    globalThis.__settled = { ok: true, result: result };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("result")?.toString() == "answer")

        let request = try #require(presenter.requests.first)
        #expect(request.title == nil)
        #expect(request.prompt == nil)
        #expect(request.placeHolder == nil)
        #expect(request.value == "")
        #expect(request.valueSelection == nil)
        #expect(request.isPassword == false)
        #expect(request.ignoreFocusOut == false)
        #expect(request.isValidating == false)
    }

    // MARK: - 2. A full options object arrives with all eight fields set

    /// Kills a mutation that drops, mis-reads, or swaps any one of the eight
    /// fields on the way from the options object into the request.
    @Test
    func aFullOptionsObjectReachesTheRequestWithAllEightFieldsSet() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingInputBoxPresenter()
        presenter.response = "answer"
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showInputBox({
                    title: 'Rename',
                    prompt: 'Enter a new name',
                    placeHolder: 'name',
                    value: 'hello',
                    valueSelection: [1, 3],
                    password: true,
                    ignoreFocusOut: true,
                    validateInput: function (value) { return undefined; }
                }).then(function (result) {
                    globalThis.__settled = { ok: true, result: result };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)

        let request = try #require(presenter.requests.first)
        #expect(request.title == "Rename")
        #expect(request.prompt == "Enter a new name")
        #expect(request.placeHolder == "name")
        #expect(request.value == "hello")
        #expect(request.valueSelection == 1..<3)
        #expect(request.isPassword == true)
        #expect(request.ignoreFocusOut == true)
        #expect(request.isValidating == true)
    }

    // MARK: - 3. The presenter answering a string resolves with that string

    /// Kills a mutation that resolves `undefined`, the request's own `value`,
    /// or any other stand-in instead of the presenter's actual answer.
    @Test
    func thePresenterAnsweringAStringResolvesWithThatString() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingInputBoxPresenter()
        presenter.response = "typed value"
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showInputBox().then(function (result) {
                    globalThis.__settled = { ok: true, result: result, isString: typeof result === 'string' };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("isString")?.toBool() == true)
        #expect(settled.forProperty("result")?.toString() == "typed value")
    }

    // MARK: - 4. The presenter answering the empty string resolves with an empty JS string, not undefined

    /// Without this test nothing stops a later edit collapsing an accepted
    /// empty value into a dismissal: kills a mutation that treats `""` the
    /// same as `nil` in `presentInputBoxPromise`.
    @Test
    func thePresenterAnsweringTheEmptyStringResolvesAnEmptyStringNotUndefined() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingInputBoxPresenter()
        presenter.response = ""
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showInputBox().then(function (result) {
                    globalThis.__settled = {
                        ok: true,
                        isUndefined: result === undefined,
                        isEmptyString: result === ''
                    };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("isUndefined")?.toBool() == false)
        #expect(settled.forProperty("isEmptyString")?.toBool() == true)
    }

    // MARK: - 5. The presenter answering `nil` resolves `undefined`

    /// Kills a mutation that resolves some other placeholder — `null`, an
    /// empty string, the request's own `value` — instead of `undefined` for
    /// a dismissal.
    @Test
    func thePresenterAnsweringNilResolvesUndefined() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingInputBoxPresenter()
        presenter.response = nil
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showInputBox().then(function (result) {
                    globalThis.__settled = { ok: true, isUndefined: result === undefined };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("isUndefined")?.toBool() == true)
    }

    // MARK: - 6. `valueSelection` parses `[2, 5]`, `[3, 3]`, and absent correctly

    /// Kills a mutation that swaps start/end, is off by one on either bound,
    /// fails to represent an empty selection, or treats "absent" as anything
    /// but `nil`.
    @Test
    func valueSelectionParsesANormalPairAnEmptyPairAndAbsent() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingInputBoxPresenter()
        presenter.response = "x"
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                Promise.all([
                    vscode.window.showInputBox({ value: 'hello', valueSelection: [2, 5] }),
                    vscode.window.showInputBox({ value: 'hello', valueSelection: [3, 3] }),
                    vscode.window.showInputBox({ value: 'hello' })
                ]).then(function () {
                    globalThis.__settled = { ok: true };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(presenter.requests.count == 3)
        #expect(presenter.requests[0].valueSelection == 2..<5)
        #expect(presenter.requests[1].valueSelection == 3..<3)
        #expect(presenter.requests[2].valueSelection == nil)
    }

    // MARK: - 7. A malformed `valueSelection` rejects, naming `valueSelection`

    /// Five malformed shapes, each its own sub-case: reversed, negative
    /// start, an end past `value`'s length, the wrong element count, and
    /// non-numeric elements. Kills a mutation that forwards any of these
    /// unexamined (which would trap constructing the `Range`), or one that
    /// rejects without naming `valueSelection` in the message.
    @Test
    func aMalformedValueSelectionRejectsNamingValueSelection() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cases: [(String, String)] = [
            ("reversed", "[5, 2]"),
            ("negativeStart", "[-1, 2]"),
            ("pastEnd", "[0, 99]"),
            ("wrongLength", "[1, 2, 3]"),
            ("nonNumeric", "['a', 'b']")
        ]
        for (name, literal) in cases {
            let presenter = RecordingInputBoxPresenter()
            let host = try makeHost(
                name: name,
                source: """
                var vscode = require('vscode');
                exports.activate = function () {
                    globalThis.__settled = null;
                    vscode.window.showInputBox({ value: 'hello', valueSelection: \(literal) }).then(function (result) {
                        globalThis.__settled = { ok: true, result: result };
                    }, function (error) {
                        globalThis.__settled = { ok: false, message: error.message };
                    });
                };
                """,
                in: directory
            )
            let window = try await activate(host, presenter: presenter)
            defer { host.dispose(); window.dispose() }

            let context = try #require(host.javaScriptContext)
            let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
            #expect(settled.forProperty("ok")?.toBool() == false, "case \(name)")
            let message = try #require(settled.forProperty("message")?.toString())
            #expect(message.contains("valueSelection"), "case \(name): \(message)")
            #expect(presenter.requests.isEmpty, "case \(name)")
        }
    }

    // MARK: - 8. `isValidating` is `false` with no `validateInput`, `true` with one

    /// The pair, in one test: either half alone would pass for the wrong
    /// reason — a mutation that hard-codes `true` passes the second call and
    /// a mutation that hard-codes `false` passes the first.
    @Test
    func isValidatingReflectsWhetherValidateInputWasSupplied() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingInputBoxPresenter()
        presenter.response = "x"
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                Promise.all([
                    vscode.window.showInputBox({}),
                    vscode.window.showInputBox({ validateInput: function (value) { return undefined; } })
                ]).then(function () {
                    globalThis.__settled = { ok: true };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(presenter.requests.count == 2)
        #expect(presenter.requests[0].isValidating == false)
        #expect(presenter.requests[1].isValidating == true)
    }

    // MARK: - 9. A validator returning a non-empty string reaches the presenter as `.error`

    /// Kills a mutation that drops the message, normalises a string result to
    /// `nil`, or attaches any severity but `.error`.
    @Test
    func aValidatorReturningANonEmptyStringReachesThePresenterAsError() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingInputBoxPresenter()
        presenter.response = "x"
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showInputBox({
                    validateInput: function (value) { return 'too short'; }
                }).then(function () {
                    globalThis.__settled = { ok: true };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__settled"))
        let validate = try #require(presenter.lastValidate)
        let result = try #require(await validate("anything"))
        #expect(result.message == "too short")
        #expect(result.severity == .error)
    }

    // MARK: - 10. `undefined`, `null` and `""` from a validator all reach the presenter as `nil`

    /// Three separate arms of the normalisation, each its own sub-case: kills
    /// a mutation that treats any one of the three as a message instead of
    /// "valid".
    @Test
    func aValidatorReturningUndefinedNullOrEmptyStringAllReachThePresenterAsNil() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cases: [(String, String)] = [
            ("undefinedCase", "return undefined;"),
            ("nullCase", "return null;"),
            ("emptyStringCase", "return '';")
        ]
        for (name, body) in cases {
            let presenter = RecordingInputBoxPresenter()
            presenter.response = "x"
            let host = try makeHost(
                name: name,
                source: """
                var vscode = require('vscode');
                exports.activate = function () {
                    globalThis.__settled = null;
                    vscode.window.showInputBox({
                        validateInput: function (value) { \(body) }
                    }).then(function () {
                        globalThis.__settled = { ok: true };
                    }, function (error) {
                        globalThis.__settled = { ok: false, message: error.message };
                    });
                };
                """,
                in: directory
            )
            let window = try await activate(host, presenter: presenter)
            defer { host.dispose(); window.dispose() }

            let context = try #require(host.javaScriptContext)
            _ = try #require(await waitForGlobal(context, "globalThis.__settled"))
            let validate = try #require(presenter.lastValidate)
            let result = await validate("anything")
            #expect(result == nil, "case \(name)")
        }
    }

    // MARK: - 11. severity 2 reaches the presenter as `.warning`; `1` → `.information`, `3` → `.error`

    /// Kills a mutation that maps any one of the three numbers to the wrong
    /// case, or that is off by one in either direction.
    @Test
    func aValidatorsSeverityNumberMapsToTheMatchingCase() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cases: [(String, Int, ExtensionInputValidationSeverity)] = [
            ("informationCase", 1, .information),
            ("warningCase", 2, .warning),
            ("errorCase", 3, .error)
        ]
        for (name, severityNumber, expected) in cases {
            let presenter = RecordingInputBoxPresenter()
            presenter.response = "x"
            let host = try makeHost(
                name: name,
                source: """
                var vscode = require('vscode');
                exports.activate = function () {
                    globalThis.__settled = null;
                    vscode.window.showInputBox({
                        validateInput: function (value) {
                            return { message: 'careful', severity: \(severityNumber) };
                        }
                    }).then(function () {
                        globalThis.__settled = { ok: true };
                    }, function (error) {
                        globalThis.__settled = { ok: false, message: error.message };
                    });
                };
                """,
                in: directory
            )
            let window = try await activate(host, presenter: presenter)
            defer { host.dispose(); window.dispose() }

            let context = try #require(host.javaScriptContext)
            _ = try #require(await waitForGlobal(context, "globalThis.__settled"))
            let validate = try #require(presenter.lastValidate)
            let result = try #require(await validate("anything"), "case \(name)")
            #expect(result.message == "careful", "case \(name)")
            #expect(result.severity == expected, "case \(name)")
        }
    }

    // MARK: - 12. The default-arm pair: a message with no severity is `.error`; a severity with no message is `nil`

    /// `:188-190`'s default arm, and the single most likely thing to be
    /// implemented backwards: kills a mutation that answers `nil` for
    /// `{message: "x"}` (treating an absent severity as "ignore" rather than
    /// the declaration's own default), and independently kills a mutation
    /// that manufactures a message for `{severity: 2}` instead of answering
    /// `nil` for an object with nothing usable to show.
    @Test
    func aMessageWithNoSeverityDefaultsToErrorAndASeverityWithNoMessageIsNil() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingInputBoxPresenter()
        presenter.response = "x"
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showInputBox({
                    validateInput: function (value) { return { message: 'x' }; }
                }).then(function () {
                    globalThis.__settled = { ok: true };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }
        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__settled"))
        let messageOnlyResult = try #require(await presenter.lastValidate?("anything"))
        #expect(messageOnlyResult.message == "x")
        #expect(messageOnlyResult.severity == .error)

        let severityOnlyDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: severityOnlyDirectory) }
        let severityOnlyPresenter = RecordingInputBoxPresenter()
        severityOnlyPresenter.response = "x"
        let severityOnlyHost = try makeHost(
            name: "severityOnly",
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showInputBox({
                    validateInput: function (value) { return { severity: 2 }; }
                }).then(function () {
                    globalThis.__settled = { ok: true };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: severityOnlyDirectory
        )
        let severityOnlyWindow = try await activate(severityOnlyHost, presenter: severityOnlyPresenter)
        defer { severityOnlyHost.dispose(); severityOnlyWindow.dispose() }
        let severityOnlyContext = try #require(severityOnlyHost.javaScriptContext)
        _ = try #require(await waitForGlobal(severityOnlyContext, "globalThis.__settled"))
        let severityOnlyResult = await severityOnlyPresenter.lastValidate?("anything")
        #expect(severityOnlyResult == nil)
    }

    // MARK: - 13. A validator returning a promise reaches the presenter as `.error` once it fulfils

    /// The round trip this task exists for: kills a mutation that reads the
    /// validator's immediate return value instead of awaiting its settlement,
    /// which would see a `Promise` object rather than the fulfilled result.
    @Test
    func aValidatorReturningAPromiseReachesThePresenterOnceItFulfils() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingInputBoxPresenter()
        presenter.response = "x"
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showInputBox({
                    validateInput: function (value) {
                        return Promise.resolve({ message: 'late', severity: 3 });
                    }
                }).then(function () {
                    globalThis.__settled = { ok: true };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__settled"))
        let validate = try #require(presenter.lastValidate)
        let result = try #require(await validate("anything"))
        #expect(result.message == "late")
        #expect(result.severity == .error)
    }

    // MARK: - 14. A validator whose promise rejects reaches the presenter as `nil`

    /// Kills a mutation that surfaces the rejection instead of answering
    /// "valid" — this file's first stated divergence from upstream, applied
    /// to the async case.
    @Test
    func aValidatorWhosePromiseRejectsReachesThePresenterAsNil() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingInputBoxPresenter()
        presenter.response = "x"
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showInputBox({
                    validateInput: function (value) {
                        return Promise.reject(new Error('broken validator'));
                    }
                }).then(function () {
                    globalThis.__settled = { ok: true };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__settled"))
        let validate = try #require(presenter.lastValidate)
        let result = await validate("anything")
        #expect(result == nil)
    }

    // MARK: - 15. A validator that throws synchronously reaches the presenter as `nil` and does not block the result

    /// Kills a mutation that lets the throw escape (which would surface as a
    /// pending-exception failure elsewhere) or that treats `.threw` as
    /// anything other than `nil`. The input box's own promise must still
    /// resolve — the throwing validator must not wedge it.
    @Test
    func aValidatorThatThrowsSynchronouslyReachesThePresenterAsNilAndTheResultStillResolves() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingInputBoxPresenter()
        presenter.response = "final answer"
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showInputBox({
                    validateInput: function (value) { throw new Error('validator exploded'); }
                }).then(function (result) {
                    globalThis.__settled = { ok: true, result: result };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("result")?.toString() == "final answer")

        let validate = try #require(presenter.lastValidate)
        let result = await validate("anything")
        #expect(result == nil)
    }

    // MARK: - 16. The validator is called with the exact string and the options object as `this`

    /// Assert from inside the JS validator, the only place `this` is
    /// observable. Kills a mutation that binds `this` to `nil`/`undefined`,
    /// to the window, or to anything but the options object, and
    /// independently kills a mutation that passes the wrong value string —
    /// e.g. the request's original `value` instead of the candidate the
    /// presenter is actually asking about.
    @Test
    func theValidatorSeesTheExactValueAndTheOptionsObjectAsThis() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingInputBoxPresenter()
        presenter.response = "x"
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                globalThis.__seenValues = [];
                globalThis.__seenThis = [];
                var options = {
                    validateInput: function (value) {
                        globalThis.__seenValues.push(value);
                        globalThis.__seenThis.push(this === options);
                        return undefined;
                    }
                };
                vscode.window.showInputBox(options).then(function () {
                    globalThis.__settled = { ok: true };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__settled"))
        let validate = try #require(presenter.lastValidate)
        _ = await validate("candidate text")

        let seenValues = try #require(context.evaluateScript("globalThis.__seenValues"))
        let seenThis = try #require(context.evaluateScript("globalThis.__seenThis"))
        #expect(seenValues.atIndex(0)?.toString() == "candidate text")
        #expect(seenThis.atIndex(0)?.toBool() == true)
    }

    // MARK: - 17. A window disposed before the presenter answers rejects with the torn-down wording

    /// `SuspendingInputBoxPresenter.presentInputBox` is confirmed parked on
    /// its continuation before `dispose()` runs, and is released only
    /// afterwards. Kills a mutation that removes the post-`await`
    /// `!self.isDisposed` guard in `presentInputBoxPromise`: the presenter's
    /// answer would be delivered into a torn-down window as `ok: true`
    /// instead of a "torn down" rejection.
    @Test
    func disposeWhileThePresenterIsGenuinelySuspendedRejectsRatherThanDeliveringAResult() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = SuspendingInputBoxPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                globalThis.run = function () {
                    vscode.window.showInputBox().then(
                        function (result) { globalThis.__settled = { ok: true, result: result }; },
                        function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                    );
                };
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose() }

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.run();")
        await presenter.waitUntilEntered(1)
        // Past the two pre-flight guards, before the post-await one.
        window.dispose()
        presenter.release(at: 0, with: "too late")

        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(try #require(settled.forProperty("message")?.toString()).contains("torn down"))
    }

    // MARK: - 18. `inputBoxValidationSeverityMembers` equals the exact table

    /// The three values the declaration gives: `Info = 1`, `Warning = 2`,
    /// `Error = 3` (`vscode.d.ts:2198-2206`). Kills a mutation to any one
    /// number, or to a key's spelling — including a mutation that "fixes"
    /// the keys to match `ExtensionInputValidationSeverity`'s own case names.
    @Test
    func inputBoxValidationSeverityMembersCarriesUpstreamsSpellingsAndNumbers() {
        #expect(MainThreadWindow.inputBoxValidationSeverityMembers == ["Info": 1, "Warning": 2, "Error": 3])
    }
}
