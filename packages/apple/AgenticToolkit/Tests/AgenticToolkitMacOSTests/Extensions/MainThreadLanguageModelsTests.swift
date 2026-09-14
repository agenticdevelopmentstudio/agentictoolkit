import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A double for `ExtensionLanguageModelProviding`, private to this file —
/// this task writes no production conformer (there is no model provider in
/// this host to conform one to yet), so every test here supplies its own set
/// of models directly rather than reaching a real provider.
@MainActor
private final class TestLanguageModelProvider: ExtensionLanguageModelProviding {
    var availableChatModels: [LanguageModelChatDescriptor]

    init(_ availableChatModels: [LanguageModelChatDescriptor] = []) {
        self.availableChatModels = availableChatModels
    }
}

/// `vscode.lm.selectChatModels` and the `LanguageModelChat` object it hands
/// back (task 5.7a-ii) — wired onto a real `ExtensionHost` with a
/// `TestLanguageModelProvider` double standing in for a production model
/// provider, exactly as `MainThreadLanguagesGetLanguagesTests` does for
/// `HostLanguageVocabulary`. What is pinned here is the JS/Swift boundary
/// itself: selector semantics, the readonly object-handback shape, both
/// `countTokens` argument shapes, and the `sendRequest` NotImplemented stub —
/// never a real provider's own composition, which a double makes irrelevant
/// to these tests by construction.
@MainActor
@Suite
struct MainThreadLanguageModelsTests {

    // MARK: - Fixtures

    /// Six pairwise-distinct values, so a field swap (`family`/`version`,
    /// say) is visible rather than masked by two fields sharing a value.
    private static let alpha = LanguageModelChatDescriptor(
        name: "Alpha Model", id: "alpha-id", vendor: "acme",
        family: "alpha-family", version: "1.0.0", maxInputTokens: 4096)

    private static let beta = LanguageModelChatDescriptor(
        name: "Beta Model", id: "beta-id", vendor: "other-vendor",
        family: "beta-family", version: "2.0.0", maxInputTokens: 8192)

    private func makeTempDirectory() throws -> URL {
        try ExtensionFixtures.makeTemporaryDirectory("MainThreadLanguageModelsTests")
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

    /// Installs `lm.selectChatModels` onto `host`'s `vscode.lm` namespace —
    /// the adaptor-with-owner route `MainThreadLanguages.getLanguages` is
    /// installed through in its own suite, not 5.7a-i's host-ceremony route.
    private func install(_ languageModels: MainThreadLanguageModels, on host: ExtensionHost) throws {
        try host.defineVSCodeMember(
            namespacePath: "vscode.lm", name: "selectChatModels",
            implementation: languageModels.selectChatModels)
    }

    /// Polls `expression` until it evaluates to something other than
    /// `null`/`undefined`, or gives up after one second — the same polling
    /// `MainThreadLanguagesVocabularyTests.swift`'s own `waitForGlobal` (on
    /// `MainThreadLanguagesGetLanguagesTests`) uses, for the same
    /// reason: a `.then()` reaction is a microtask, never invoked
    /// synchronously regardless of how settled the promise already is.
    private func waitForGlobal(_ context: JSContext, _ expression: String) async throws -> JSValue? {
        for _ in 0..<200 {
            if let value = context.evaluateScript(expression), !value.isNull, !value.isUndefined {
                return value
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        return nil
    }

    // MARK: - Mutation 1: an empty provider resolves with [], never rejects or throws

    /// `vscode.d.ts:20767`'s own doc: "can be empty!" — a provider with no
    /// models resolves with `[]`. The fixture's `try`/`catch` around the call
    /// itself, not only around `.then`'s rejection branch, is what lets this
    /// test tell "resolved with `[]`" apart from "threw synchronously" —
    /// which a plain `.then(resolve, reject)` without the wrapping `try`
    /// cannot distinguish, because a synchronous throw never reaches either
    /// callback. Kills mutation 1.
    @Test
    func selectChatModelsWithNoProviderResolvesWithEmptyArrayRatherThanRejectingOrThrowing() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = NotImplementedLedger()
        let languageModels = MainThreadLanguageModels(
            provider: TestLanguageModelProvider([]),
            notImplementedLedger: ledger,
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__result = null;
                try {
                    vscode.lm.selectChatModels().then(
                        function (models) { globalThis.__result = { outcome: 'resolved', length: models.length }; },
                        function (error) { globalThis.__result = { outcome: 'rejected', message: error.message }; }
                    );
                } catch (error) {
                    globalThis.__result = { outcome: 'threw', message: error.message };
                }
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let result = try #require(await waitForGlobal(context, "globalThis.__result"))
        #expect(result.forProperty("outcome")?.toString() == "resolved")
        #expect(result.forProperty("length")?.toInt32() == 0)
        #expect(ledger.accesses.isEmpty)
    }

    // MARK: - Mutations 2 and 3: an absent selector and an empty selector both match everything

    /// `selectChatModels()` — no argument at all — matches every model, not
    /// none: `currentArguments().first` is `nil` here, which
    /// `LanguageModelChatSelectorCriteria.make(from:)` must read as "every
    /// field unconstrained," never as "match nothing." Kills mutation 2.
    @Test
    func selectChatModelsWithNoSelectorArgumentMatchesEveryModel() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let languageModels = MainThreadLanguageModels(
            provider: TestLanguageModelProvider([Self.alpha, Self.beta]),
            notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__ids = null;
                vscode.lm.selectChatModels().then(function (models) {
                    globalThis.__ids = models.map(function (m) { return m.id; });
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let ids = try #require(await waitForGlobal(context, "globalThis.__ids"))
        #expect((ids.toArray() as? [String]) == ["alpha-id", "beta-id"])
    }

    /// `selectChatModels({})` also matches every model — through a different
    /// branch of `LanguageModelChatSelectorCriteria.make(from:)` than the
    /// no-argument case above: `{}` is `.isObject`, so this exercises the
    /// four `forProperty(...)` reads each answering `undefined`, while the
    /// no-argument test above never reaches property access at all. A mutant
    /// that special-cased an empty object to mean "match nothing" would pass
    /// the previous test and fail this one. Kills mutation 3.
    @Test
    func selectChatModelsWithEmptyObjectSelectorAlsoMatchesEveryModel() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let languageModels = MainThreadLanguageModels(
            provider: TestLanguageModelProvider([Self.alpha, Self.beta]),
            notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__ids = null;
                vscode.lm.selectChatModels({}).then(function (models) {
                    globalThis.__ids = models.map(function (m) { return m.id; });
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let ids = try #require(await waitForGlobal(context, "globalThis.__ids"))
        #expect((ids.toArray() as? [String]) == ["alpha-id", "beta-id"])
    }

    // MARK: - Mutation 4: a selector field excludes a non-matching model and includes a matching one

    /// `{ vendor: 'acme' }` excludes `beta` (`vendor: 'other-vendor'`) and
    /// includes `alpha` (`vendor: 'acme'`) — one assertion proving both
    /// directions for the `vendor` field, per the brief's own alternative to
    /// four near-identical per-field tests.
    ///
    /// Does not kill: a mutant that reads `family`, `version` or `id` instead
    /// of `vendor` while ignoring `vendor` itself — only `vendor` is
    /// exercised here. Kills mutation 4.
    @Test
    func selectorFieldExcludesNonMatchingModelAndIncludesMatchingModel() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let languageModels = MainThreadLanguageModels(
            provider: TestLanguageModelProvider([Self.alpha, Self.beta]),
            notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__ids = null;
                vscode.lm.selectChatModels({ vendor: 'acme' }).then(function (models) {
                    globalThis.__ids = models.map(function (m) { return m.id; });
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let ids = try #require(await waitForGlobal(context, "globalThis.__ids"))
        #expect((ids.toArray() as? [String]) == ["alpha-id"])
    }

    // MARK: - Mutation 5: two fields are a conjunction, not a disjunction

    /// `{ vendor: 'acme', family: 'beta-family' }`: `vendor` matches only
    /// `alpha`, `family` matches only `beta`, and neither model matches both
    /// — the conjunction must exclude both. A disjunctive (OR) implementation
    /// would include both models here (each satisfies one field), which an
    /// all-fields-match fixture could never distinguish from a correct
    /// conjunction. Kills mutation 5.
    @Test
    func selectorWithTwoFieldsRequiresBothToMatchNotEither() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let languageModels = MainThreadLanguageModels(
            provider: TestLanguageModelProvider([Self.alpha, Self.beta]),
            notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__ids = null;
                vscode.lm.selectChatModels({ vendor: 'acme', family: 'beta-family' }).then(function (models) {
                    globalThis.__ids = models.map(function (m) { return m.id; });
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let ids = try #require(await waitForGlobal(context, "globalThis.__ids"))
        #expect((ids.toArray() as? [String]) == [])
    }

    // MARK: - Mutation 7: each property carries its own value, not a neighbor's

    /// `alpha`'s six fields are pairwise distinct; this reads all six off the
    /// handed-back object and pins each one against its own expected value,
    /// so a swap (`family`/`version`, or any other pair) is visible rather
    /// than masked. Kills mutation 7.
    @Test
    func chatModelObjectExposesEachDescriptorFieldWithoutMixingThem() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let languageModels = MainThreadLanguageModels(
            provider: TestLanguageModelProvider([Self.alpha]),
            notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__model = null;
                vscode.lm.selectChatModels().then(function (models) {
                    var m = models[0];
                    globalThis.__model = {
                        name: m.name, id: m.id, vendor: m.vendor,
                        family: m.family, version: m.version, maxInputTokens: m.maxInputTokens
                    };
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let model = try #require(await waitForGlobal(context, "globalThis.__model"))
        #expect(model.forProperty("name")?.toString() == "Alpha Model")
        #expect(model.forProperty("id")?.toString() == "alpha-id")
        #expect(model.forProperty("vendor")?.toString() == "acme")
        #expect(model.forProperty("family")?.toString() == "alpha-family")
        #expect(model.forProperty("version")?.toString() == "1.0.0")
        #expect(model.forProperty("maxInputTokens")?.toInt32() == 4096)
    }

    // MARK: - Mutation 6: every data property is readonly

    /// Assigns to all six data properties from JS, then re-reads: non-strict
    /// JavaScript's own behaviour for a `defineProperty` descriptor with no
    /// setter is a silent no-op, so every value must come back unchanged.
    /// One test covering all six properties, not six. Kills mutation 6.
    @Test
    func chatModelDataPropertiesAreReadonlyAssignmentIsASilentNoOp() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let languageModels = MainThreadLanguageModels(
            provider: TestLanguageModelProvider([Self.alpha]),
            notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__model = null;
                vscode.lm.selectChatModels().then(function (models) {
                    var m = models[0];
                    m.name = 'intruder';
                    m.id = 'intruder';
                    m.vendor = 'intruder';
                    m.family = 'intruder';
                    m.version = 'intruder';
                    m.maxInputTokens = -1;
                    globalThis.__model = {
                        name: m.name, id: m.id, vendor: m.vendor,
                        family: m.family, version: m.version, maxInputTokens: m.maxInputTokens
                    };
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let model = try #require(await waitForGlobal(context, "globalThis.__model"))
        #expect(model.forProperty("name")?.toString() == "Alpha Model")
        #expect(model.forProperty("id")?.toString() == "alpha-id")
        #expect(model.forProperty("vendor")?.toString() == "acme")
        #expect(model.forProperty("family")?.toString() == "alpha-family")
        #expect(model.forProperty("version")?.toString() == "1.0.0")
        #expect(model.forProperty("maxInputTokens")?.toInt32() == 4096)
    }

    // MARK: - Mutation 8: countTokens(string)

    /// `countTokens` given a bare string counts its whitespace-separated
    /// words. Kills mutation 8.
    @Test
    func countTokensWithAStringArgumentCountsItsWords() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let languageModels = MainThreadLanguageModels(
            provider: TestLanguageModelProvider([Self.alpha]),
            notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__count = null;
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].countTokens('one two three four');
                }).then(function (count) { globalThis.__count = count; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let count = try #require(await waitForGlobal(context, "globalThis.__count"))
        #expect(count.toInt32() == 4)
    }

    // MARK: - Mutation 9: countTokens(LanguageModelChatMessage) reads the array content, not a string

    /// `vscode.LanguageModelChatMessage.User(...)` (5.7a-i's host-ceremony
    /// vocabulary, installed on every activation) coerces its string argument
    /// into `[new LanguageModelTextPart(value)]` — `content` is always an
    /// array. An implementation that reads `content` as a string gets
    /// `undefined` and silently counts zero; this pins the real count
    /// instead.
    ///
    /// Does not kill: a `countTokens` that mishandles more than one content
    /// part, or a part with no string `.value` — only a single
    /// `LanguageModelTextPart` is exercised. Kills mutation 9.
    @Test
    func countTokensWithAMessageArgumentReadsItsArrayContentNotAString() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let languageModels = MainThreadLanguageModels(
            provider: TestLanguageModelProvider([Self.alpha]),
            notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__count = null;
                var message = vscode.LanguageModelChatMessage.User('one two three four five');
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].countTokens(message);
                }).then(function (count) { globalThis.__count = count; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let count = try #require(await waitForGlobal(context, "globalThis.__count"))
        #expect(count.toInt32() == 5)
    }

    // MARK: - Mutation 10: sendRequest records a NotImplemented access and throws

    /// `sendRequest` both records into `notImplementedLedger` and throws a
    /// `NotImplementedError` matching the shim's own shape — a mutant that
    /// drops either half survives the other half's assertions here, so both
    /// are pinned in one test rather than split, since dropping the throw
    /// alone or the record alone are the only two single-line mutations this
    /// call site admits. Kills mutation 10.
    @Test
    func sendRequestRecordsANotImplementedAccessAndThrows() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = NotImplementedLedger()
        let languageModels = MainThreadLanguageModels(
            provider: TestLanguageModelProvider([Self.alpha]),
            notImplementedLedger: ledger,
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__result = null;
                vscode.lm.selectChatModels().then(function (models) {
                    var chat = models[0];
                    try {
                        chat.sendRequest([]);
                        globalThis.__result = { outcome: 'no-throw' };
                    } catch (error) {
                        globalThis.__result = { outcome: 'threw', name: error.name, memberPath: error.memberPath };
                    }
                });
            };
            """,
            in: directory,
            ledger: ledger
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let result = try #require(await waitForGlobal(context, "globalThis.__result"))
        #expect(result.forProperty("outcome")?.toString() == "threw")
        #expect(result.forProperty("name")?.toString() == "NotImplementedError")
        #expect(result.forProperty("memberPath")?.toString() == "vscode.LanguageModelChat.sendRequest")

        let accesses = ledger.accesses
        #expect(accesses.count == 1)
        #expect(accesses.first?.memberPath == "vscode.LanguageModelChat.sendRequest")
        #expect(accesses.first?.count == 1)
    }

    // MARK: - Teardown

    /// A torn-down adaptor rejects `selectChatModels()` rather than answering
    /// or raising: `vscode.d.ts:20769` declares this member `Thenable<...>`,
    /// so `VSCodeAPI.member`'s `.rejectedPromise` teardown response is the
    /// one this member must use, the same choice
    /// `MainThreadLanguagesGetLanguagesTests` pins for `getLanguages`. Not
    /// one of the ten listed mutations — this is the seam's teardown
    /// contract, established practice for every sibling suite in this
    /// folder.
    @Test
    func aTornDownAdaptorRejectsSelectChatModelsRatherThanAnsweringOrRaising() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var languageModels: MainThreadLanguageModels? = MainThreadLanguageModels(
            provider: TestLanguageModelProvider([Self.alpha]),
            notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__afterTeardown = null;
                globalThis.run = function () {
                    vscode.lm.selectChatModels().then(
                        function (models) {
                            globalThis.__afterTeardown = { outcome: 'resolved', value: models };
                        },
                        function (error) {
                            globalThis.__afterTeardown = { outcome: 'rejected', message: error.message };
                        }
                    );
                };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        // Scoped deliberately, mirroring `MainThreadLanguagesGetLanguagesTests`'s
        // own torn-down test: a `let` binding at test scope would itself keep
        // the adaptor alive past `languageModels = nil` below.
        if let live = languageModels { try install(live, on: host) }
        try await host.activate()

        // Nothing else holds the adaptor now: `selectChatModels` captures it
        // weakly, and this extension's `activate` registered nothing that
        // would.
        languageModels = nil

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.run();")

        let out = try #require(await waitForGlobal(context, "globalThis.__afterTeardown"))
        #expect(out.forProperty("outcome")?.toString() == "rejected")
        #expect(out.forProperty("message")?.toString()
            == "vscode.lm.selectChatModels is unavailable: this extension's host has been torn down.")
    }
}
