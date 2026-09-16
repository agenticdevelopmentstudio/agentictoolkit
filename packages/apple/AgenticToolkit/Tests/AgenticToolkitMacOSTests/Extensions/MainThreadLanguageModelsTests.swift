import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A double for `ExtensionLanguageModelProviding`, private to this file —
/// this task writes no production conformer (there is no model provider in
/// this host to conform one to yet), so every test here supplies its own set
/// of models directly rather than reaching a real provider.
///
/// `streamResponseHandler` is `nil` by default, answering an already-finished
/// empty stream, so every test that never calls `sendRequest` (all of task
/// 5.7a-ii's tests, above) needs no change. `last*` captures record what
/// `sendRequest`'s one call this segment last passed through the seam, for
/// task 5.7b's Ruling 54 tests.
@MainActor
private final class TestLanguageModelProvider: ExtensionLanguageModelProviding {
    var availableChatModels: [LanguageModelChatDescriptor]

    var streamResponseHandler: (
        (
            LanguageModelChatDescriptor, [ExtensionLanguageModelMessage], String?, String
        ) throws -> AsyncThrowingStream<ExtensionLanguageModelResponsePart, Error>
    )?

    private(set) var lastMessages: [ExtensionLanguageModelMessage]?
    private(set) var lastJustification: String?
    private(set) var lastExtensionIdentifier: String?
    private(set) var callCount = 0

    init(_ availableChatModels: [LanguageModelChatDescriptor] = []) {
        self.availableChatModels = availableChatModels
    }

    func streamResponse(
        for model: LanguageModelChatDescriptor,
        messages: [ExtensionLanguageModelMessage],
        justification: String?,
        extensionIdentifier: String
    ) async throws -> AsyncThrowingStream<ExtensionLanguageModelResponsePart, Error> {
        callCount += 1
        lastMessages = messages
        lastJustification = justification
        lastExtensionIdentifier = extensionIdentifier
        if let handler = streamResponseHandler {
            return try handler(model, messages, justification, extensionIdentifier)
        }
        return AsyncThrowingStream { continuation in continuation.finish() }
    }
}

/// `vscode.lm.selectChatModels` and the `LanguageModelChat` object it hands
/// back (task 5.7a-ii), plus `sendRequest`'s real streaming response (task
/// 5.7b) — wired onto a real `ExtensionHost` with a `TestLanguageModelProvider`
/// double standing in for a production model provider, exactly as
/// `MainThreadLanguagesGetLanguagesTests` does for `HostLanguageVocabulary`.
/// What is pinned here is the JS/Swift boundary itself: selector semantics,
/// the readonly object-handback shape, both `countTokens` argument shapes,
/// and `sendRequest`'s tee'd `stream`/`text` response (Rulings 51-54) —
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

    /// Installs `lm.selectChatModels` onto `host`'s `vscode.lm` namespace —
    /// the adaptor-with-owner route `MainThreadLanguages.getLanguages` is
    /// installed through in its own suite, not 5.7a-i's host-ceremony route.
    private func install(_ languageModels: MainThreadLanguageModels, on host: ExtensionHost) throws {
        try host.defineVSCodeMember(
            namespacePath: "vscode.lm", name: "selectChatModels",
            implementation: languageModels.selectChatModels)
    }

    /// Installs `lm.onDidChangeChatModels` onto `host`'s `vscode.lm`
    /// namespace — a sibling to `install(_:on:)` above rather than an
    /// extension of it, so task 5.7c's tests below (which need only this
    /// member) leave the ~30 tests above (which need only
    /// `selectChatModels`) undisturbed.
    private func installOnDidChangeChatModels(
        _ languageModels: MainThreadLanguageModels, on host: ExtensionHost
    ) throws {
        try host.defineVSCodeMember(
            namespacePath: "vscode.lm", name: "onDidChangeChatModels",
            implementation: languageModels.onDidChangeChatModels)
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

    /// An already-finished stream carrying exactly `parts`, in order — for
    /// every task 5.7b test below that does not need to control the pump's
    /// timing by hand (T8, T11 do, via their own held `continuation`s).
    private static func makeStream(
        _ parts: [ExtensionLanguageModelResponsePart]
    ) -> AsyncThrowingStream<ExtensionLanguageModelResponsePart, Error> {
        AsyncThrowingStream { continuation in
            for part in parts {
                continuation.yield(part)
            }
            continuation.finish()
        }
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

    // MARK: - Task 5.7b: sendRequest's real streaming response

    /// T1, gate zero: pins as a permanent test the 4-question probe already
    /// verified by hand before this task wrote a line of the tee
    /// (`LanguageModelResponseRequest`, `MainThreadLanguageModels.swift`) —
    /// that `for await…of` never holds more than one outstanding `next()`
    /// call on the same async iterator at a time, which is what lets each
    /// `CursorState` carry a single `waiter` rather than a queue of them.
    /// Monkey-patches `response.stream.next` to count concurrent calls
    /// in-flight against a provider that yields three parts, so the drained
    /// loop actually calls `next()` more than once, then asserts the
    /// observed maximum. Kills a `CursorState` that grew a queue instead of a
    /// single `PromiseSettlementBox?` for the wrong reason.
    ///
    /// One of the 4-question probe's questions — that settlement happens on
    /// the main actor — is not asserted directly by anything below; it is
    /// pinned only implicitly, by `MainActor.assumeIsolated` trapping if any
    /// of this ever ran off the main actor.
    @Test
    func gateZeroForAwaitNeverHoldsMoreThanOneOutstandingNext() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        provider.streamResponseHandler = { _, _, _, _ in
            MainThreadLanguageModelsTests.makeStream(
                [.text("a"), .text("b"), .text("c"), .end(stopReason: nil)])
        }
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__maxOutstanding = null;
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([]);
                }).then(function (response) {
                    var outstanding = 0;
                    var maxOutstanding = 0;
                    var originalNext = response.stream.next.bind(response.stream);
                    response.stream.next = function () {
                        outstanding++;
                        if (outstanding > maxOutstanding) { maxOutstanding = outstanding; }
                        return originalNext().then(function (result) {
                            outstanding--;
                            return result;
                        });
                    };
                    return (async function () {
                        for await (const part of response.stream) {
                            // Draining is the point: each iteration calls
                            // the patched `next()` above.
                        }
                        globalThis.__maxOutstanding = maxOutstanding;
                    })();
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let maxOutstanding = try #require(await waitForGlobal(context, "globalThis.__maxOutstanding"))
        #expect(maxOutstanding.toInt32() == 1)
    }

    /// Gate zero (T1, above) pins that `for await…of` never issues a
    /// second `next()` before the first settles — but nothing in the
    /// async-iterator protocol *forbids* an extension calling `next()` twice
    /// by hand without awaiting the first, and `setWaiter` used to overwrite
    /// the stored waiter unconditionally, silently stranding the first
    /// call's promise forever. Holds the
    /// seam's own `AsyncThrowingStream.Continuation` so `buffer` is
    /// guaranteed empty when both `next()` calls are issued back-to-back in
    /// the same synchronous block — both land in `.pending`, no timing race
    /// possible, since no data exists until this test yields it below. The
    /// first call must reject with the new named-constraint message; the
    /// second must still resolve normally once data arrives, proving only
    /// the displaced waiter is punished, not every waiter thereafter.
    @Test
    func aSecondConcurrentNextRejectsTheDisplacedFirstWaiter() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        var heldContinuation:
            AsyncThrowingStream<ExtensionLanguageModelResponsePart, Error>.Continuation?
        provider.streamResponseHandler = { _, _, _, _ in
            AsyncThrowingStream { continuation in heldContinuation = continuation }
        }
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__bothIssued = null;
                globalThis.__firstOutcome = null;
                globalThis.__secondOutcome = null;
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([]);
                }).then(function (response) {
                    response.text.next().then(
                        function (result) {
                            globalThis.__firstOutcome = { outcome: 'resolved', value: result.value };
                        },
                        function (error) {
                            globalThis.__firstOutcome = { outcome: 'rejected', message: error.message };
                        }
                    );
                    response.text.next().then(
                        function (result) {
                            globalThis.__secondOutcome = { outcome: 'resolved', value: result.value };
                        },
                        function (error) {
                            globalThis.__secondOutcome = { outcome: 'rejected', message: error.message };
                        }
                    );
                    globalThis.__bothIssued = true;
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__bothIssued"))

        heldContinuation?.yield(.text("only"))
        heldContinuation?.finish()

        let firstOutcome = try #require(await waitForGlobal(context, "globalThis.__firstOutcome"))
        let secondOutcome = try #require(await waitForGlobal(context, "globalThis.__secondOutcome"))
        #expect(firstOutcome.forProperty("outcome")?.toString() == "rejected")
        #expect(firstOutcome.forProperty("message")?.toString()?.contains(
            "only supports one outstanding") == true)
        #expect(secondOutcome.forProperty("outcome")?.toString() == "resolved")
        #expect(secondOutcome.forProperty("value")?.toString() == "only")
    }

    /// T2: `sendRequest` resolves with exactly `vscode.LanguageModelChatResponse`'s
    /// two declared members (`vscode.d.ts:20194-20235`) — no third key a
    /// wider `makeResponseObject(in:)` might have grown.
    @Test
    func sendRequestResolvesWithExactlyStreamAndText() async throws {
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
                globalThis.__keys = null;
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([]);
                }).then(function (response) {
                    globalThis.__keys = Object.keys(response).sort();
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let keys = try #require(await waitForGlobal(context, "globalThis.__keys"))
        #expect((keys.toArray() as? [String]) == ["stream", "text"])
    }

    /// T3: `.stream` yields a real `vscode.LanguageModelTextPart` (`instanceof`
    /// against the same cached vocabulary constructor 5.7a-i installs), not a
    /// plain object shaped like one.
    @Test
    func streamYieldsALanguageModelTextPart() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        provider.streamResponseHandler = { _, _, _, _ in
            MainThreadLanguageModelsTests.makeStream([.text("hello"), .end(stopReason: nil)])
        }
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__result = null;
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([]);
                }).then(function (response) {
                    return response.stream.next();
                }).then(function (result) {
                    globalThis.__result = {
                        done: result.done,
                        isTextPart: result.value instanceof vscode.LanguageModelTextPart,
                        value: result.value.value
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
        let result = try #require(await waitForGlobal(context, "globalThis.__result"))
        #expect(result.forProperty("done")?.toBool() == false)
        #expect(result.forProperty("isTextPart")?.toBool() == true)
        #expect(result.forProperty("value")?.toString() == "hello")
    }

    /// T4: `.stream` yields a real `vscode.LanguageModelToolCallPart` with its
    /// id, name, and `argumentsJSON` parsed (via the context's own
    /// `JSON.parse`, not handed over as a raw string) into `.input`.
    @Test
    func streamYieldsALanguageModelToolCallPartWithIdNameAndParsedInput() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        provider.streamResponseHandler = { _, _, _, _ in
            MainThreadLanguageModelsTests.makeStream([
                .toolCall(id: "call-1", name: "myTool", argumentsJSON: Data(#"{"x":1}"#.utf8)),
                .end(stopReason: nil)
            ])
        }
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__result = null;
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([]);
                }).then(function (response) {
                    return response.stream.next();
                }).then(function (result) {
                    globalThis.__result = {
                        done: result.done,
                        isToolCallPart: result.value instanceof vscode.LanguageModelToolCallPart,
                        callId: result.value.callId,
                        name: result.value.name,
                        x: result.value.input.x
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
        let result = try #require(await waitForGlobal(context, "globalThis.__result"))
        #expect(result.forProperty("done")?.toBool() == false)
        #expect(result.forProperty("isToolCallPart")?.toBool() == true)
        #expect(result.forProperty("callId")?.toString() == "call-1")
        #expect(result.forProperty("name")?.toString() == "myTool")
        #expect(result.forProperty("x")?.toInt32() == 1)
    }

    /// T5: `.text` yields plain strings and skips a tool call in the middle —
    /// filtering, not stringifying, per Ruling 53.
    @Test
    func textYieldsStringsOnlyAndSkipsToolCalls() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        provider.streamResponseHandler = { _, _, _, _ in
            MainThreadLanguageModelsTests.makeStream([
                .text("a"),
                .toolCall(id: "call-1", name: "myTool", argumentsJSON: Data("{}".utf8)),
                .text("b"),
                .end(stopReason: nil)
            ])
        }
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__texts = null;
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([]);
                }).then(function (response) {
                    return (async function () {
                        var texts = [];
                        for await (const t of response.text) {
                            texts.push(t);
                        }
                        return texts;
                    })();
                }).then(function (texts) { globalThis.__texts = texts; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let texts = try #require(await waitForGlobal(context, "globalThis.__texts"))
        #expect((texts.toArray() as? [String]) == ["a", "b"])
    }

    /// T6: the tee — both `.stream` and `.text` see every part the seam
    /// yields, each at its own pace, from the one shared buffer. `.stream`
    /// sees all three non-`.end` parts; `.text` sees only the two text ones.
    @Test
    func teeDeliversEveryPartToBothBranches() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        provider.streamResponseHandler = { _, _, _, _ in
            MainThreadLanguageModelsTests.makeStream([
                .text("a"),
                .toolCall(id: "call-1", name: "myTool", argumentsJSON: Data("{}".utf8)),
                .text("b"),
                .end(stopReason: nil)
            ])
        }
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__streamCount = null;
                globalThis.__textCount = null;
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([]);
                }).then(function (response) {
                    var drainStream = (async function () {
                        var count = 0;
                        for await (const part of response.stream) { count++; }
                        globalThis.__streamCount = count;
                    })();
                    var drainText = (async function () {
                        var count = 0;
                        for await (const part of response.text) { count++; }
                        globalThis.__textCount = count;
                    })();
                    return Promise.all([drainStream, drainText]);
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let streamCount = try #require(await waitForGlobal(context, "globalThis.__streamCount"))
        let textCount = try #require(await waitForGlobal(context, "globalThis.__textCount"))
        #expect(streamCount.toInt32() == 3)
        #expect(textCount.toInt32() == 2)
    }

    /// T7: iterating only `.text` to completion terminates on its own — an
    /// untouched `.stream` never blocks it, because the pump is not lazy
    /// (Ruling 53): it drains the seam into `buffer` regardless of whether
    /// any cursor is currently being read.
    ///
    /// This fixture is byte-identical to T5's above — T5 pins *what*
    /// `.text` yields, this one pins *that* it terminates on its own with
    /// `.stream` untouched; a lazy-pump
    /// regression here would not produce a wrong answer, it would hang, and
    /// only surface as `waitForGlobal`'s one-second poll giving up and
    /// `#require` failing — a timeout is this test's deadlock-detection
    /// signal, not an incidental slowness.
    @Test
    func iteratingOnlyTextTerminatesWithoutTouchingStream() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        provider.streamResponseHandler = { _, _, _, _ in
            MainThreadLanguageModelsTests.makeStream(
                [.text("a"), .text("b"), .end(stopReason: nil)])
        }
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__texts = null;
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([]);
                }).then(function (response) {
                    return (async function () {
                        var texts = [];
                        for await (const t of response.text) {
                            texts.push(t);
                        }
                        return texts;
                    })();
                }).then(function (texts) { globalThis.__texts = texts; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let texts = try #require(await waitForGlobal(context, "globalThis.__texts"))
        #expect((texts.toArray() as? [String]) == ["a", "b"])
    }

    /// The seam's source can finish without ever emitting an `.end` part
    /// at all (a well-behaved provider always
    /// does, per Ruling 53, but `scan`'s own `self.isSourceFinished`
    /// fallback branch — reached only once `buffer` is exhausted for a
    /// cursor and no `.end` was seen — is what has to answer `.done` in
    /// that case). `makeStream` here deliberately never yields `.end`; if
    /// that fallback ever regressed to firing only on an explicit `.end`,
    /// neither `for await…of` loop below would ever see `done: true`, and
    /// this test would hang until `waitForGlobal`'s one-second poll gives
    /// up and `#require` fails, rather than reporting a wrong value.
    @Test
    func sourceFinishingWithoutEndStillFinishesBothCursors() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        provider.streamResponseHandler = { _, _, _, _ in
            MainThreadLanguageModelsTests.makeStream([.text("a"), .text("b")])
        }
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__streamCount = null;
                globalThis.__texts = null;
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([]);
                }).then(function (response) {
                    var drainStream = (async function () {
                        var count = 0;
                        for await (const part of response.stream) { count++; }
                        globalThis.__streamCount = count;
                    })();
                    var drainText = (async function () {
                        var texts = [];
                        for await (const t of response.text) { texts.push(t); }
                        globalThis.__texts = texts;
                    })();
                    return Promise.all([drainStream, drainText]);
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let streamCount = try #require(await waitForGlobal(context, "globalThis.__streamCount"))
        let texts = try #require(await waitForGlobal(context, "globalThis.__texts"))
        #expect(streamCount.toInt32() == 2)
        #expect((texts.toArray() as? [String]) == ["a", "b"])
    }

    /// `vscode.LanguageModelChatResponse` has no third member to carry
    /// `.end(stopReason:)`'s payload
    /// (`makeResponseObject(in:)`'s own doc), so a *non-nil* `stopReason` —
    /// the case T3/T5/T6/T7's fixtures never exercise, all using `nil` —
    /// must still be dropped, not surfaced, exactly like the `nil` case.
    @Test
    func nonNilEndStopReasonIsDroppedNotSurfaced() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        provider.streamResponseHandler = { _, _, _, _ in
            MainThreadLanguageModelsTests.makeStream([.text("a"), .end(stopReason: "length")])
        }
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__texts = null;
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([]);
                }).then(function (response) {
                    return (async function () {
                        var texts = [];
                        for await (const t of response.text) {
                            texts.push(t);
                        }
                        return texts;
                    })();
                }).then(function (texts) { globalThis.__texts = texts; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let texts = try #require(await waitForGlobal(context, "globalThis.__texts"))
        #expect((texts.toArray() as? [String]) == ["a"])
    }

    /// A part yielded after `.end` is ignored, not trapped — proven here
    /// by holding the seam's own
    /// continuation and yielding one more part (`"after-end"`), and even
    /// finishing the stream, only *after* `.end`, then asserting it never
    /// appears in `.text`. This does not pin *which* layer ignores it: the
    /// pump's own `break` on `.end` is one way to get this result, but
    /// `scan` also intercepts `.end` and finishes the `.text` cursor on its
    /// own, so this test would still pass even without the pump's `break`
    /// — which is to say this test is not proof that the `break` is what
    /// stops `"after-end"` from reaching `buffer`; nothing here observes
    /// that. Waits for a
    /// Swift-independent `__ready` flag JS sets immediately after starting
    /// the `for await…of` drain — synchronously, before that async
    /// function's first `await` — which proves the drain has started, so
    /// the parts this test yields land in a live iteration rather than
    /// racing the drain's own startup (the seam's `heldContinuation` is
    /// already non-nil well before this point: the provider handler
    /// captures it during `sendRequest` itself, long before any `next()`).
    @Test
    func aPartAfterEndIsIgnoredNotTrapped() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        var heldContinuation:
            AsyncThrowingStream<ExtensionLanguageModelResponsePart, Error>.Continuation?
        provider.streamResponseHandler = { _, _, _, _ in
            AsyncThrowingStream { continuation in heldContinuation = continuation }
        }
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__ready = null;
                globalThis.__texts = null;
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([]);
                }).then(function (response) {
                    var drain = (async function () {
                        var texts = [];
                        for await (const t of response.text) {
                            texts.push(t);
                        }
                        return texts;
                    })();
                    globalThis.__ready = true;
                    return drain;
                }).then(function (texts) { globalThis.__texts = texts; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__ready"))

        heldContinuation?.yield(.text("a"))
        heldContinuation?.yield(.end(stopReason: nil))
        heldContinuation?.yield(.text("after-end"))
        heldContinuation?.finish()

        let texts = try #require(await waitForGlobal(context, "globalThis.__texts"))
        #expect((texts.toArray() as? [String]) == ["a"])
    }

    /// T8: an error mid-stream rejects the in-flight `next()` of *both*
    /// branches, not only whichever one happened to be reading. Holds the
    /// seam's own `AsyncThrowingStream.Continuation` by hand so the error can
    /// be raised only after both `next()` calls are already outstanding —
    /// `__bothIssued` is set synchronously inside the promise executor
    /// (`JSValue(newPromiseIn:executor:)` runs its executor synchronously),
    /// so polling for it proves both waiters are registered before the
    /// Swift side ever throws.
    @Test
    func errorMidStreamRejectsInFlightNextOfBothBranches() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        var heldContinuation:
            AsyncThrowingStream<ExtensionLanguageModelResponsePart, Error>.Continuation?
        provider.streamResponseHandler = { _, _, _, _ in
            AsyncThrowingStream { continuation in heldContinuation = continuation }
        }
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__bothIssued = null;
                globalThis.__streamResult = null;
                globalThis.__textResult = null;
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([]);
                }).then(function (response) {
                    response.stream.next().then(
                        function () { globalThis.__streamResult = { outcome: 'resolved' }; },
                        function (error) {
                            globalThis.__streamResult = { outcome: 'rejected', message: error.message };
                        }
                    );
                    response.text.next().then(
                        function () { globalThis.__textResult = { outcome: 'resolved' }; },
                        function (error) {
                            globalThis.__textResult = { outcome: 'rejected', message: error.message };
                        }
                    );
                    globalThis.__bothIssued = true;
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__bothIssued"))

        struct StubStreamFailure: Error {}
        heldContinuation?.finish(throwing: StubStreamFailure())

        let streamResult = try #require(await waitForGlobal(context, "globalThis.__streamResult"))
        let textResult = try #require(await waitForGlobal(context, "globalThis.__textResult"))
        #expect(streamResult.forProperty("outcome")?.toString() == "rejected")
        #expect(textResult.forProperty("outcome")?.toString() == "rejected")
    }

    /// T9: the seam throwing synchronously (before ever returning a stream)
    /// must still produce a **rejected** promise from `sendRequest`, never a
    /// synchronous JS throw — the shape the `NotImplemented` stub this task
    /// replaces got wrong.
    @Test
    func seamSynchronousThrowProducesARejectedPromiseNotASynchronousThrow() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        struct StubSeamFailure: Error {}
        provider.streamResponseHandler = { _, _, _, _ in throw StubSeamFailure() }
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__result = null;
                vscode.lm.selectChatModels().then(function (models) {
                    var chat = models[0];
                    try {
                        chat.sendRequest([]).then(
                            function () { globalThis.__result = { outcome: 'resolved' }; },
                            function (error) {
                                globalThis.__result = { outcome: 'rejected', message: error.message };
                            }
                        );
                    } catch (error) {
                        globalThis.__result = { outcome: 'threw', message: error.message };
                    }
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let result = try #require(await waitForGlobal(context, "globalThis.__result"))
        #expect(result.forProperty("outcome")?.toString() == "rejected")
    }

    /// T10: a torn-down adaptor rejects `sendRequest` rather than answering
    /// or raising — the same weak-capture-drop pattern
    /// `aTornDownAdaptorRejectsSelectChatModelsRatherThanAnsweringOrRaising`
    /// (below, in "Teardown," left byte-for-byte unchanged by this task)
    /// pins for `selectChatModels`, applied to `sendRequest`'s own member
    /// instead: `VSCodeAPI.member` weakly captures the same owner for both.
    @Test
    func aTornDownAdaptorRejectsSendRequestRatherThanAnsweringOrRaising() async throws {
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
                globalThis.__chat = null;
                globalThis.__afterTeardown = null;
                globalThis.capture = function () {
                    vscode.lm.selectChatModels().then(function (models) {
                        globalThis.__chat = models[0];
                    });
                };
                globalThis.run = function () {
                    globalThis.__chat.sendRequest([]).then(
                        function () { globalThis.__afterTeardown = { outcome: 'resolved' }; },
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
        if let live = languageModels { try install(live, on: host) }
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.capture();")
        _ = try #require(await waitForGlobal(context, "globalThis.__chat"))

        // Nothing else holds the adaptor now, mirroring the sibling teardown
        // test below: `sendRequest` captures it weakly.
        languageModels = nil

        context.evaluateScript("globalThis.run();")
        let out = try #require(await waitForGlobal(context, "globalThis.__afterTeardown"))
        #expect(out.forProperty("outcome")?.toString() == "rejected")
        #expect(out.forProperty("message")?.toString()
            == "vscode.LanguageModelChat.sendRequest is unavailable: this extension's host has been torn down.")
    }

    /// T11: tearing the adaptor down mid-stream rejects each branch's
    /// in-flight `next()` with the torn-down wording, using that cursor's own
    /// `memberPath` — `dispose()`'s step 2, exercised directly rather than
    /// through a weak-capture drop, since `dispose()` needs a live `self` to
    /// call.
    @Test
    func teardownMidStreamRejectsInFlightNextWithTornDownWording() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        var heldContinuation:
            AsyncThrowingStream<ExtensionLanguageModelResponsePart, Error>.Continuation?
        provider.streamResponseHandler = { _, _, _, _ in
            AsyncThrowingStream { continuation in heldContinuation = continuation }
        }
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__bothIssued = null;
                globalThis.__streamResult = null;
                globalThis.__textResult = null;
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([]);
                }).then(function (response) {
                    response.stream.next().then(
                        function () { globalThis.__streamResult = { outcome: 'resolved' }; },
                        function (error) {
                            globalThis.__streamResult = { outcome: 'rejected', message: error.message };
                        }
                    );
                    response.text.next().then(
                        function () { globalThis.__textResult = { outcome: 'resolved' }; },
                        function (error) {
                            globalThis.__textResult = { outcome: 'rejected', message: error.message };
                        }
                    );
                    globalThis.__bothIssued = true;
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__bothIssued"))

        // Deliberately left unfinished: `dispose()` must reject these two
        // waiters on its own, without the seam ever reporting an error.
        _ = heldContinuation
        languageModels.dispose()

        let streamResult = try #require(await waitForGlobal(context, "globalThis.__streamResult"))
        let textResult = try #require(await waitForGlobal(context, "globalThis.__textResult"))
        #expect(streamResult.forProperty("outcome")?.toString() == "rejected")
        #expect(streamResult.forProperty("message")?.toString()
            == "vscode.LanguageModelChatResponse.stream is unavailable: "
                + "this extension's host has been torn down.")
        #expect(textResult.forProperty("outcome")?.toString() == "rejected")
        #expect(textResult.forProperty("message")?.toString()
            == "vscode.LanguageModelChatResponse.text is unavailable: "
                + "this extension's host has been torn down.")
    }

    /// `dispose()` used to call `liveRequests.removeAll()`, dropping every
    /// `LanguageModelResponseRequest` out of the dictionary at teardown — so
    /// a `next()` issued *afterward*, against a response object obtained
    /// *before* teardown, found no owner at all and silently answered
    /// `undefined` rather than rejecting.
    /// Ruling 81/82 keep the request in `liveRequests` at `dispose()` on
    /// purpose, so `next()` still finds it and hits the `!owner.isDisposed`
    /// guard in `attemptSettleOrStore` — which runs before `scan` is ever
    /// called, so this holds for a response whose cursors have not both
    /// finished. It does not hold once both cursors have already finished:
    /// `checkCompletion()` would have removed the request and deallocated
    /// it by then, and a further `next()` goes back to answering
    /// `undefined` — unchanged by Ruling 81/82, and out of this test's
    /// scope. Distinct from
    /// `teardownMidStreamRejectsInFlightNextWithTornDownWording` above
    /// (which tears down while a `next()` is already outstanding): this one
    /// tears down first, on an idle response object, and only then calls
    /// `next()`.
    @Test
    func nextCalledAfterDisposeOnAnAlreadyObtainedResponseRejectsRatherThanAnsweringUndefined() async throws {
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
                globalThis.__response = null;
                globalThis.__streamAfterDispose = null;
                globalThis.__textAfterDispose = null;
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([]);
                }).then(function (response) {
                    globalThis.__response = response;
                });
                globalThis.runAfterDispose = function () {
                    globalThis.__response.stream.next().then(
                        function (result) {
                            globalThis.__streamAfterDispose = { outcome: 'resolved', done: result.done };
                        },
                        function (error) {
                            globalThis.__streamAfterDispose = { outcome: 'rejected', message: error.message };
                        }
                    );
                    globalThis.__response.text.next().then(
                        function (result) {
                            globalThis.__textAfterDispose = { outcome: 'resolved', done: result.done };
                        },
                        function (error) {
                            globalThis.__textAfterDispose = { outcome: 'rejected', message: error.message };
                        }
                    );
                };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__response"))

        languageModels.dispose()

        context.evaluateScript("globalThis.runAfterDispose();")

        let streamResult = try #require(await waitForGlobal(context, "globalThis.__streamAfterDispose"))
        let textResult = try #require(await waitForGlobal(context, "globalThis.__textAfterDispose"))
        #expect(streamResult.forProperty("outcome")?.toString() == "rejected")
        #expect(streamResult.forProperty("message")?.toString()
            == "vscode.LanguageModelChatResponse.stream is unavailable: "
                + "this extension's host has been torn down.")
        #expect(textResult.forProperty("outcome")?.toString() == "rejected")
        #expect(textResult.forProperty("message")?.toString()
            == "vscode.LanguageModelChatResponse.text is unavailable: "
                + "this extension's host has been torn down.")
    }

    /// T12: `justification` reaches the seam as-is, and is `nil` when
    /// omitted; `modelOptions`/`tools`/`toolMode` never reach the seam at
    /// all, and are ledgered into `notImplementedLedger` (one entry each,
    /// under their exact `vscode.d.ts` member paths) only when present —
    /// Ruling 54, two calls in one test so both directions of "reaches the
    /// seam" and "omitted means nil" are pinned against the same provider.
    ///
    /// **The two phases are separated by a flag Swift sets, not one JS sets
    /// for itself.** `ledgerDegradedOptions(_:)` runs *synchronously*
    /// inside `handleSendRequest`, before the promise is even constructed,
    /// so a JS side that set its own flag and issued the second
    /// `sendRequest` in the same synchronous statement would record that
    /// call's three ledger entries before Swift regained control at all —
    /// `#expect(ledger.accesses.isEmpty)` would fail deterministically
    /// rather than race. So the JS side spins on `setTimeout` (a real,
    /// `Task`-backed timer here, not a synchronous microtask loop) until
    /// `globalThis.__proceed` appears, which guarantees the second
    /// `sendRequest` cannot start until this test has already made its
    /// phase-one assertions.
    @Test
    func sendRequestPassesJustificationAndLedgersDegradedOptionsWhenPresent() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = NotImplementedLedger()
        let provider = TestLanguageModelProvider([Self.alpha])
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: ledger,
            extensionIdentifier: "test.ext")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__firstDone = null;
                globalThis.__secondDone = null;
                vscode.lm.selectChatModels().then(function (models) {
                    var chat = models[0];
                    chat.sendRequest([], { justification: 'because' }).then(function () {
                        globalThis.__firstDone = true;
                        return new Promise(function (resolve) {
                            (function waitForProceed() {
                                if (globalThis.__proceed) {
                                    resolve();
                                } else {
                                    setTimeout(waitForProceed, 0);
                                }
                            })();
                        });
                    }).then(function () {
                        return chat.sendRequest([], {
                            modelOptions: { temperature: 0.5 },
                            tools: [{ name: 'a' }],
                            toolMode: 1
                        });
                    }).then(function () {
                        globalThis.__secondDone = true;
                    });
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
        _ = try #require(await waitForGlobal(context, "globalThis.__firstDone"))
        // Provably true at this point, not merely likely: the second
        // `sendRequest` has not been issued yet, because the JS side is
        // still spinning on `__proceed`, which this test has not set.
        #expect(provider.lastJustification == "because")
        #expect(provider.callCount == 1)
        #expect(ledger.accesses.isEmpty)

        context.evaluateScript("globalThis.__proceed = true;")

        _ = try #require(await waitForGlobal(context, "globalThis.__secondDone"))
        #expect(provider.lastJustification == nil)
        #expect(provider.callCount == 2)

        let accesses = ledger.accesses
        #expect(Set(accesses.map { $0.memberPath }) == Set([
            "vscode.LanguageModelChatRequestOptions.modelOptions",
            "vscode.LanguageModelChatRequestOptions.tools",
            "vscode.LanguageModelChatRequestOptions.toolMode"
        ]))
        #expect(accesses.allSatisfy { $0.count == 1 })
    }

    /// T13: breaking a `for await…of` loop over `.stream` calls its
    /// `return()`, which ends only that branch — `.text`, iterated
    /// independently, still drains to completion.
    @Test
    func breakingOneBranchsForAwaitEndsOnlyThatBranch() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        provider.streamResponseHandler = { _, _, _, _ in
            MainThreadLanguageModelsTests.makeStream(
                [.text("a"), .text("b"), .text("c"), .end(stopReason: nil)])
        }
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__streamCount = null;
                globalThis.__texts = null;
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([]);
                }).then(function (response) {
                    var breakStream = (async function () {
                        var count = 0;
                        for await (const part of response.stream) {
                            count++;
                            break;
                        }
                        globalThis.__streamCount = count;
                    })();
                    var drainText = (async function () {
                        var texts = [];
                        for await (const t of response.text) {
                            texts.push(t);
                        }
                        globalThis.__texts = texts;
                    })();
                    return Promise.all([breakStream, drainText]);
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let streamCount = try #require(await waitForGlobal(context, "globalThis.__streamCount"))
        let texts = try #require(await waitForGlobal(context, "globalThis.__texts"))
        #expect(streamCount.toInt32() == 1)
        #expect((texts.toArray() as? [String]) == ["a", "b", "c"])
    }

    /// T14: `sendRequest` records **nothing** into `notImplementedLedger` —
    /// it is a real implementation now, not the shim's not-implemented stub.
    /// Replaces `sendRequestRecordsANotImplementedAccessAndThrows`, this
    /// task's one test deletion: that test pinned the stub `sendRequest` is
    /// replacing, and a member that no longer throws has nothing left for
    /// that test to assert.
    @Test
    func sendRequestRecordsNothingIntoTheNotImplementedLedger() async throws {
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
                globalThis.__done = null;
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([]);
                }).then(function () { globalThis.__done = true; });
            };
            """,
            in: directory,
            ledger: ledger
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__done"))
        #expect(ledger.accesses.isEmpty)
    }

    // MARK: - The cancellation token

    /// The third argument `sendRequest` declares (`vscode.d.ts:20302`),
    /// built in JS because that is where it comes from in life: this host
    /// installs no `CancellationToken` type and no `CancellationTokenSource`,
    /// so the object that reaches the adaptor is whatever the extension
    /// brought, and a Swift-side fixture would be testing a token the
    /// adaptor can never actually receive.
    ///
    /// `onCancellationRequested` parks the host's listener on
    /// `globalThis.__fire`, so a test cancels by calling that — at the
    /// moment it chooses, which is the whole difference between the two
    /// halves of the contract. `requested` seeds
    /// `isCancellationRequested`: the only difference between a token that
    /// arrives already cancelled and one cancelled afterwards.
    private static func tokenSource(alreadyCancelled: Bool) -> String {
        """
        globalThis.__fire = null;
        globalThis.__token = {
            isCancellationRequested: \(alreadyCancelled),
            onCancellationRequested: function (listener) { globalThis.__fire = listener; }
        };
        """
    }

    /// A token already cancelled when the request would start rejects the
    /// promise **and never reaches the seam at all** — the guard runs
    /// before `provider.streamResponse`, so `callCount` is what tells
    /// "refused before starting" apart from "started, then cancelled". A
    /// rejection alone cannot: both halves of the contract reject.
    @Test
    func aTokenAlreadyCancelledRejectsSendRequestWithoutCallingTheSeam() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__result = null;
                \(Self.tokenSource(alreadyCancelled: true))
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([], {}, globalThis.__token);
                }).then(
                    function () { globalThis.__result = { outcome: 'resolved' }; },
                    function (error) {
                        globalThis.__result = { outcome: 'rejected', message: error.message };
                    }
                );
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let result = try #require(await waitForGlobal(context, "globalThis.__result"))
        #expect(result.forProperty("outcome")?.toString() == "rejected")
        #expect(result.forProperty("message")?.toString()
            == "vscode.LanguageModelChat.sendRequest failed: "
            + "the CancellationToken passed to sendRequest was cancelled")
        #expect(provider.callCount == 0)
    }

    /// A token cancelled *after* the response object is handed back fails
    /// both cursors' in-flight `next()` — the source is put into the state
    /// a source that threw leaves it in, so the failure arrives by the
    /// `sourceFailure` route rather than by a second path of its own. The
    /// source here never yields and never finishes, so both promises are
    /// genuinely outstanding at the moment the token fires.
    @Test
    func cancellingAfterTheResponseArrivesRejectsInFlightNextOnBothCursors() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        var heldContinuation:
            AsyncThrowingStream<ExtensionLanguageModelResponsePart, Error>.Continuation?
        provider.streamResponseHandler = { _, _, _, _ in
            AsyncThrowingStream { continuation in heldContinuation = continuation }
        }
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__bothIssued = null;
                globalThis.__streamResult = null;
                globalThis.__textResult = null;
                \(Self.tokenSource(alreadyCancelled: false))
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([], {}, globalThis.__token);
                }).then(function (response) {
                    response.stream.next().then(
                        function () { globalThis.__streamResult = { outcome: 'resolved' }; },
                        function (error) {
                            globalThis.__streamResult = { outcome: 'rejected', message: error.message };
                        }
                    );
                    response.text.next().then(
                        function () { globalThis.__textResult = { outcome: 'resolved' }; },
                        function (error) {
                            globalThis.__textResult = { outcome: 'rejected', message: error.message };
                        }
                    );
                    globalThis.__bothIssued = true;
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__bothIssued"))
        // The subscription happens synchronously inside `sendRequest`, so
        // the listener is parked by the time the response resolves.
        #expect(context.evaluateScript("typeof globalThis.__fire")?.toString() == "function")

        context.evaluateScript("globalThis.__fire();")

        let streamResult = try #require(await waitForGlobal(context, "globalThis.__streamResult"))
        let textResult = try #require(await waitForGlobal(context, "globalThis.__textResult"))
        let cancelled = "vscode.LanguageModelChat.sendRequest failed: "
            + "the CancellationToken passed to sendRequest was cancelled"
        #expect(streamResult.forProperty("outcome")?.toString() == "rejected")
        #expect(streamResult.forProperty("message")?.toString() == cancelled)
        #expect(textResult.forProperty("outcome")?.toString() == "rejected")
        #expect(textResult.forProperty("message")?.toString() == cancelled)
        // Keeps the source alive to the end of the test rather than being
        // dropped at the `provider.streamResponseHandler` closure's exit.
        heldContinuation?.finish()
    }

    /// Parts already buffered when the token fires are still delivered,
    /// and the failure arrives only once that buffer is exhausted — a
    /// cancellation discards the future, not the past. The test waits for
    /// JS to have *seen* both texts before cancelling, so the ordering it
    /// asserts is established rather than raced for.
    @Test
    func partsBufferedBeforeCancellationAreDeliveredBeforeTheFailure() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        var heldContinuation:
            AsyncThrowingStream<ExtensionLanguageModelResponsePart, Error>.Continuation?
        provider.streamResponseHandler = { _, _, _, _ in
            AsyncThrowingStream { continuation in heldContinuation = continuation }
        }
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__seenBoth = null;
                globalThis.__outcome = null;
                \(Self.tokenSource(alreadyCancelled: false))
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([], {}, globalThis.__token);
                }).then(function (response) {
                    var texts = [];
                    (async function () {
                        try {
                            for await (const t of response.text) {
                                texts.push(t);
                                if (texts.length === 2) { globalThis.__seenBoth = true; }
                            }
                            globalThis.__outcome = { outcome: 'done', texts: texts };
                        } catch (error) {
                            globalThis.__outcome = {
                                outcome: 'rejected', message: error.message, texts: texts
                            };
                        }
                    })();
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        // Yielding needs the handler to have run, which happens inside the
        // promise's `Task`; poll for the continuation rather than assuming
        // it is already there.
        for _ in 0..<200 where heldContinuation == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        let continuation = try #require(heldContinuation)
        continuation.yield(.text("a"))
        continuation.yield(.text("b"))
        _ = try #require(await waitForGlobal(context, "globalThis.__seenBoth"))

        context.evaluateScript("globalThis.__fire();")

        let outcome = try #require(await waitForGlobal(context, "globalThis.__outcome"))
        #expect(outcome.forProperty("outcome")?.toString() == "rejected")
        #expect((outcome.forProperty("texts")?.toArray() as? [String]) == ["a", "b"])
        continuation.finish()
    }

    /// A token that fires after the source has already finished leaves the
    /// completed response completed: there is nothing left to cancel, and
    /// overwriting the outcome would turn a response the extension
    /// successfully received into a failed one. Pinned on the `stream`
    /// cursor, which has not been iterated at all when the token fires —
    /// a cursor that had already drained would report `done` whether or
    /// not the cancellation was suppressed, and so would prove nothing.
    @Test
    func cancellingAfterTheSourceFinishedLeavesTheCompletedResponseCompleted() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        provider.streamResponseHandler = { _, _, _, _ in
            MainThreadLanguageModelsTests.makeStream([.text("a"), .end(stopReason: nil)])
        }
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__textDone = null;
                globalThis.__streamOutcome = null;
                \(Self.tokenSource(alreadyCancelled: false))
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([], {}, globalThis.__token);
                }).then(function (response) {
                    globalThis.drainStream = function () {
                        (async function () {
                            var count = 0;
                            try {
                                for await (const part of response.stream) { count++; }
                                globalThis.__streamOutcome = { outcome: 'done', count: count };
                            } catch (error) {
                                globalThis.__streamOutcome = {
                                    outcome: 'rejected', message: error.message
                                };
                            }
                        })();
                    };
                    (async function () {
                        var texts = [];
                        for await (const t of response.text) { texts.push(t); }
                        globalThis.__textDone = texts.length;
                    })();
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__textDone"))

        context.evaluateScript("globalThis.__fire();")
        context.evaluateScript("globalThis.drainStream();")

        let outcome = try #require(await waitForGlobal(context, "globalThis.__streamOutcome"))
        #expect(outcome.forProperty("outcome")?.toString() == "done")
        #expect(outcome.forProperty("count")?.toInt32() == 1)
    }

    /// A token whose `onCancellationRequested` is not a function is left
    /// permanently un-cancelled rather than failing the call — the token
    /// is optional in the declared signature, so an object that does not
    /// answer the declared shape is no worse than an absent one. The
    /// evidence that the host declined to subscribe is that nothing was
    /// ever handed anywhere for it to park: the request simply runs to
    /// completion.
    @Test
    func aTokenWithoutACallableSubscriberLeavesTheRequestUncancelledNotFailed() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        provider.streamResponseHandler = { _, _, _, _ in
            MainThreadLanguageModelsTests.makeStream([.text("a"), .end(stopReason: nil)])
        }
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__texts = null;
                var token = {
                    isCancellationRequested: false,
                    onCancellationRequested: 'not a function'
                };
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest([], {}, token);
                }).then(function (response) {
                    (async function () {
                        var texts = [];
                        for await (const t of response.text) { texts.push(t); }
                        globalThis.__texts = texts;
                    })();
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let texts = try #require(await waitForGlobal(context, "globalThis.__texts"))
        #expect((texts.toArray() as? [String]) == ["a"])
        #expect(provider.callCount == 1)
    }

    /// The token is **acted on**, so it is not a degraded argument and
    /// nothing is recorded for it — unlike `modelOptions`, which makes the
    /// request answer wrongly and is ledgered. Both travel in the same
    /// call here, so the ledger's single entry is what separates them: a
    /// test passing only a token could not tell "not ledgered because it
    /// is honoured" from "not ledgered because this call ledgers nothing".
    @Test
    func anHonouredCancellationTokenIsNotLedgeredAlongsideADegradedOption() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = NotImplementedLedger()
        let languageModels = MainThreadLanguageModels(
            provider: TestLanguageModelProvider([Self.alpha]),
            notImplementedLedger: ledger,
            extensionIdentifier: "test.ext")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__done = null;
                \(Self.tokenSource(alreadyCancelled: false))
                vscode.lm.selectChatModels().then(function (models) {
                    return models[0].sendRequest(
                        [], { modelOptions: { temperature: 0.5 } }, globalThis.__token);
                }).then(function () { globalThis.__done = true; });
            };
            """,
            in: directory,
            ledger: ledger
        )
        defer { host.dispose() }
        try install(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__done"))
        #expect(ledger.accesses.map { $0.memberPath }
            == ["vscode.LanguageModelChatRequestOptions.modelOptions"])
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

    // MARK: - vscode.lm.onDidChangeChatModels (task 5.7c)

    // Every `@Test` below drives the real `vscode.lm.onDidChangeChatModels`
    // member through `installOnDidChangeChatModels(_:on:)`, over a real
    // `MainThreadLanguageModels` and a `TestLanguageModelProvider` double —
    // never a Swift-side stand-in for the emitter or the JS callable, for the
    // same reason `ExtensionEventTests`'s own doc gives: the boundary under
    // test is JavaScript-to-Swift, and a double for the JavaScript half would
    // only ever agree with itself. Delivery is triggered by mutating the
    // provider's `availableChatModels` and then calling
    // `languageModels.availableChatModelsDidChange()` directly — the seam
    // this task adds no caller for in production (that class's own doc). No
    // test here sleeps or polls a window closed: `ChatModelsImmediateWindow`
    // calls `onClose` synchronously from inside `openWindow`, and
    // `ExtensionEventEmitter.fire(_:)` (`ExtensionEvent.swift`) queues this
    // call's payload *before* calling `openWindow` for exactly that reason —
    // see its own doc — so the payload is already present when the
    // synchronous close runs. That is what makes a listener's delivery
    // synchronous with the `availableChatModelsDidChange()` call that
    // triggered it, and Ruling 85's reorder is what makes it so: `fire(_:)`
    // used to open the window first and queue after, which for this window
    // meant the close ran against an as-yet-empty queue and delivered
    // nothing on the call that should have fired — the payload surfaced one
    // signal late on the *next* `fire` instead.

    /// **A changed id set fires the event, exactly once.** `alpha` alone at
    /// construction, `[alpha, beta]` when `availableChatModelsDidChange()`
    /// runs — a real id genuinely added.
    ///
    /// Kills an implementation that never fires (`__count` stays 0) and one
    /// that fires more than once for a single call (`__count` reads 2).
    @Test
    func aChangedIdSetFiresTheEventOnce() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__count = 0;
                vscode.lm.onDidChangeChatModels(function () { globalThis.__count += 1; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try installOnDidChangeChatModels(languageModels, on: host)
        try await host.activate()

        provider.availableChatModels = [Self.alpha, Self.beta]
        languageModels.availableChatModelsDidChange()

        let context = try #require(host.javaScriptContext)
        let count = try #require(context.evaluateScript("globalThis.__count"))
        #expect(count.isNumber)
        #expect(Int(count.toInt32()) == 1)
    }

    /// **A metadata-only republish does not fire.** Same `id`, different
    /// `name`/`version`/`maxInputTokens` — exactly what
    /// `mainThreadLanguageModels.ts:75-77`'s filter exists to suppress.
    ///
    /// Kills both an unconditional-fire mutant and one that compares
    /// `[LanguageModelChatDescriptor]` arrays rather than `Set<String>` ids:
    /// the descriptor is `Equatable` over all six of its stored properties,
    /// so an array comparison would see this pair as different and fire
    /// anyway.
    @Test
    func aMetadataOnlyChangeDoesNotFire() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__count = 0;
                vscode.lm.onDidChangeChatModels(function () { globalThis.__count += 1; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try installOnDidChangeChatModels(languageModels, on: host)
        try await host.activate()

        let republished = LanguageModelChatDescriptor(
            name: "Alpha Model Renamed", id: Self.alpha.id, vendor: Self.alpha.vendor,
            family: Self.alpha.family, version: "9.9.9", maxInputTokens: 1)
        provider.availableChatModels = [republished]
        languageModels.availableChatModelsDidChange()

        let context = try #require(host.javaScriptContext)
        let count = try #require(context.evaluateScript("globalThis.__count"))
        #expect(count.isNumber)
        #expect(Int(count.toInt32()) == 0)
    }

    /// **The snapshot is actually replaced.** A real change fires once, and
    /// a second call with no further change (the set already equals the
    /// snapshot `availableChatModelsDidChange()` just wrote) fires nothing
    /// more — one delivery total, not two.
    ///
    /// Kills an implementation that fires correctly but never updates
    /// `lastModelIdentifiers`, which would fire again here because it would
    /// still be comparing against the original `[alpha]` snapshot.
    @Test
    func theSnapshotIsReplacedSoAFurtherUnchangedSignalDoesNotFireAgain() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__count = 0;
                vscode.lm.onDidChangeChatModels(function () { globalThis.__count += 1; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try installOnDidChangeChatModels(languageModels, on: host)
        try await host.activate()

        provider.availableChatModels = [Self.alpha, Self.beta]
        languageModels.availableChatModelsDidChange()
        languageModels.availableChatModelsDidChange()

        let context = try #require(host.javaScriptContext)
        let count = try #require(context.evaluateScript("globalThis.__count"))
        #expect(count.isNumber)
        #expect(Int(count.toInt32()) == 1)
    }

    /// **The snapshot is seeded in `init`, not lazily.** The provider already
    /// answers a non-empty `[alpha]` at construction, and a call to
    /// `availableChatModelsDidChange()` with nothing changed never fires.
    ///
    /// Kills an implementation that seeds `lastModelIdentifiers` lazily
    /// (empty until first read): that version would see `{}` != `{alpha-id}`
    /// on this very first call and fire unconditionally, the opposite of
    /// upstream's reason for filtering at all
    /// (`mainThreadLanguageModels.ts:75-77`).
    @Test
    func theSnapshotIsSeededInInitNotLazily() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__count = 0;
                vscode.lm.onDidChangeChatModels(function () { globalThis.__count += 1; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try installOnDidChangeChatModels(languageModels, on: host)
        try await host.activate()

        languageModels.availableChatModelsDidChange()

        let context = try #require(host.javaScriptContext)
        let count = try #require(context.evaluateScript("globalThis.__count"))
        #expect(count.isNumber)
        #expect(Int(count.toInt32()) == 0)
    }

    /// **Reordering is not a change.** `[alpha, beta]` at construction,
    /// `[beta, alpha]` when `availableChatModelsDidChange()` runs: the same
    /// two ids, in the other order, deliver nothing.
    ///
    /// Kills an implementation that compares an ordered sequence (an array,
    /// or a set-like structure that happens to preserve insertion order and
    /// is compared that way) rather than a `Set<String>`.
    @Test
    func reorderingIsNotAChange() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha, Self.beta])
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__count = 0;
                vscode.lm.onDidChangeChatModels(function () { globalThis.__count += 1; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try installOnDidChangeChatModels(languageModels, on: host)
        try await host.activate()

        provider.availableChatModels = [Self.beta, Self.alpha]
        languageModels.availableChatModelsDidChange()

        let context = try #require(host.javaScriptContext)
        let count = try #require(context.evaluateScript("globalThis.__count"))
        #expect(count.isNumber)
        #expect(Int(count.toInt32()) == 0)
    }

    /// **Removal is a change too.** `[alpha, beta]` at construction, `[alpha]`
    /// when `availableChatModelsDidChange()` runs: fewer ids than before
    /// fires, the same as more ids than before (mutation 1).
    ///
    /// Kills an implementation that only checks for *added* ids (a subset
    /// check, or `currentModelIdentifiers.isSubset(of: lastModelIdentifiers)`
    /// used as the guard) rather than full set inequality.
    @Test
    func removalIsAlsoAChange() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha, Self.beta])
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__count = 0;
                vscode.lm.onDidChangeChatModels(function () { globalThis.__count += 1; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try installOnDidChangeChatModels(languageModels, on: host)
        try await host.activate()

        provider.availableChatModels = [Self.alpha]
        languageModels.availableChatModelsDidChange()

        let context = try #require(host.javaScriptContext)
        let count = try #require(context.evaluateScript("globalThis.__count"))
        #expect(count.isNumber)
        #expect(Int(count.toInt32()) == 1)
    }

    /// **The member is reachable, answers a callable, and records no
    /// `NotImplemented` access.** Both halves matter: an implementation that
    /// installs nothing would still be reachable as `undefined` (never
    /// `'function'`) and would hit `extension-runtime.js`'s stub `get` trap,
    /// recording the access — so a bare "didn't throw" assertion would pass
    /// against that implementation too.
    @Test
    func theMemberIsReachableAsACallableAndRecordsNoNotImplementedAccess() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = NotImplementedLedger()
        let provider = TestLanguageModelProvider([Self.alpha])
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: ledger, extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                try {
                    globalThis.__result = {
                        threw: false,
                        isFunction: typeof vscode.lm.onDidChangeChatModels === 'function'
                    };
                } catch (error) {
                    globalThis.__result = { threw: true, isFunction: false };
                }
            };
            """,
            in: directory,
            ledger: ledger
        )
        defer { host.dispose() }
        try installOnDidChangeChatModels(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let result = try #require(context.evaluateScript("globalThis.__result"))
        let threw = try #require(result.forProperty("threw"))
        #expect(threw.isBoolean)
        #expect(threw.toBool() == false)
        let isFunction = try #require(result.forProperty("isFunction"))
        #expect(isFunction.isBoolean)
        #expect(isFunction.toBool() == true)
        #expect(ledger.accesses.isEmpty)
    }

    /// **The registration's `Disposable` is both returned and pushed onto
    /// the `disposables` array passed as the third argument** — one object,
    /// not two: an implementation doing only one turns exactly one of these
    /// two assertions red.
    @Test
    func theRegistrationDisposableIsBothReturnedAndPushedOntoTheDisposablesArray() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__bag = [];
                globalThis.__returned =
                    vscode.lm.onDidChangeChatModels(function () {}, null, globalThis.__bag);
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try installOnDidChangeChatModels(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let length = try #require(context.evaluateScript("globalThis.__bag.length"))
        #expect(length.isNumber)
        #expect(Int(length.toInt32()) == 1)

        let identical = try #require(
            context.evaluateScript("globalThis.__bag[0] === globalThis.__returned"))
        #expect(identical.isBoolean)
        #expect(identical.toBool() == true)
    }

    /// **`thisArgs` is honoured, on truthiness rather than a mere
    /// `!== undefined` check.** A truthy second argument becomes the
    /// listener's `this`; the `null` of the idiomatic
    /// `onDidChangeChatModels(fn, null, context.subscriptions)` binds
    /// nothing at all.
    ///
    /// Kills an implementation that drops the second argument (the bound
    /// listener would read `undefined`) and one that binds any
    /// non-`undefined` value (the `null` listener would read the target's
    /// tag).
    @Test
    func aTruthyThisArgsIsBoundAndNullIsNot() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__target = { tag: 'bound' };
                globalThis.__boundSaw = 'unset';
                globalThis.__nullSaw = 'unset';
                vscode.lm.onDidChangeChatModels(
                    function () { globalThis.__boundSaw = this.tag; }, globalThis.__target);
                vscode.lm.onDidChangeChatModels(
                    function () { globalThis.__nullSaw = this === globalThis.__target; }, null);
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try installOnDidChangeChatModels(languageModels, on: host)
        try await host.activate()

        provider.availableChatModels = [Self.alpha, Self.beta]
        languageModels.availableChatModelsDidChange()

        let context = try #require(host.javaScriptContext)
        let boundSaw = try #require(context.evaluateScript("globalThis.__boundSaw"))
        #expect(boundSaw.toString() == "bound")
        let nullSaw = try #require(context.evaluateScript("globalThis.__nullSaw"))
        #expect(nullSaw.isBoolean)
        #expect(nullSaw.toBool() == false)
    }

    /// **Disposing a listener stops delivery, and disposing twice is a
    /// no-op** — the idempotence `VSCodeAPI.disposable(in:onDispose:)`
    /// already guarantees. Two listeners, not one, so the survivor is what
    /// proves the second `dispose()` call removed nothing else.
    @Test
    func disposingAListenerStopsDeliveryAndDisposingTwiceIsANoOp() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__first = 0;
                globalThis.__second = 0;
                globalThis.__firstDisposable =
                    vscode.lm.onDidChangeChatModels(function () { globalThis.__first += 1; });
                vscode.lm.onDidChangeChatModels(function () { globalThis.__second += 1; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try installOnDidChangeChatModels(languageModels, on: host)
        try await host.activate()

        provider.availableChatModels = [Self.alpha, Self.beta]
        languageModels.availableChatModelsDidChange()

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("""
        globalThis.__firstDisposable.dispose();
        globalThis.__firstDisposable.dispose();
        """)

        provider.availableChatModels = [Self.alpha]
        languageModels.availableChatModelsDidChange()

        let first = try #require(context.evaluateScript("globalThis.__first"))
        #expect(first.isNumber)
        #expect(Int(first.toInt32()) == 1)
        let second = try #require(context.evaluateScript("globalThis.__second"))
        #expect(second.isNumber)
        #expect(Int(second.toInt32()) == 2)
    }

    /// **Two listeners both receive the event, and one throwing does not
    /// prevent the other from being called** — 5.6b's own decision for
    /// `ExtensionEventEmitter` delivery (`ExtensionEventTests.swift`'s
    /// `aThrowingListenerDoesNotStopTheOthersOrBreakTheNextWindow`), pinned
    /// here rather than re-decided: the exception is reported and delivery
    /// continues to the next listener, and the emitter is left usable for a
    /// later fire.
    @Test
    func twoListenersBothReceiveTheEventAndOneThrowingDoesNotStopTheOther() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__survivor = 0;
                vscode.lm.onDidChangeChatModels(function () { throw new Error('boom'); });
                vscode.lm.onDidChangeChatModels(function () { globalThis.__survivor += 1; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try installOnDidChangeChatModels(languageModels, on: host)
        try await host.activate()

        provider.availableChatModels = [Self.alpha, Self.beta]
        languageModels.availableChatModelsDidChange()

        let context = try #require(host.javaScriptContext)
        let afterFirst = try #require(context.evaluateScript("globalThis.__survivor"))
        #expect(afterFirst.isNumber)
        #expect(Int(afterFirst.toInt32()) == 1)

        provider.availableChatModels = [Self.alpha]
        languageModels.availableChatModelsDidChange()

        let afterSecond = try #require(context.evaluateScript("globalThis.__survivor"))
        #expect(afterSecond.isNumber)
        #expect(Int(afterSecond.toInt32()) == 2)
    }

    /// **A torn-down adaptor raises rather than returning `undefined` or
    /// rejecting.** `Event<T>` (`vscode.d.ts:1755-1767`) answers a
    /// `Disposable` synchronously, not a `Thenable`, so
    /// `VSCodeAPI.TeardownResponse.raisedException` is the member's answer —
    /// the same choice `MainThreadCommands.registerCommand` makes, pinned in
    /// `MainThreadCommandsTests.aTornDownAdaptorRaisesOrRejectsButNeverAnswersUndefined`.
    ///
    /// Scoped deliberately: a `let` binding at test scope would itself keep
    /// the adaptor alive past `languageModels = nil` below, the same
    /// reasoning `aTornDownAdaptorRejectsSelectChatModelsRatherThanAnsweringOrRaising`
    /// gives for its own `var`.
    @Test
    func aTornDownAdaptorRaisesRatherThanAnsweringOrRejecting() async throws {
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
                    try {
                        vscode.lm.onDidChangeChatModels(function () {});
                        globalThis.__afterTeardown = { outcome: 'returned' };
                    } catch (error) {
                        globalThis.__afterTeardown = { outcome: 'threw', message: error.message };
                    }
                };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        if let live = languageModels { try installOnDidChangeChatModels(live, on: host) }
        try await host.activate()

        // Nothing else holds the adaptor now: `onDidChangeChatModels`
        // captures it weakly, and this extension's `activate` registered
        // nothing that would.
        languageModels = nil

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.run();")

        let out = try #require(context.evaluateScript("globalThis.__afterTeardown"))
        #expect(out.forProperty("outcome")?.toString() == "threw")
        #expect(out.forProperty("message")?.toString()
            == "vscode.lm.onDidChangeChatModels is unavailable: this extension's host has been torn down.")
    }

    /// **`dispose()` stops delivery to an already-registered listener**, on
    /// `MainThreadDiagnostics.dispose()`'s own pattern
    /// (`MainThreadDiagnostics.swift:876`): a registration holds its listener
    /// `JSValue`, and through it that extension's `JSContext`, strongly, so
    /// leaving it behind after `dispose()` would leave a torn-down
    /// extension's context outliving its host until that listener goes —
    /// exactly what `ExtensionEvent.swift`'s own "Lifetime" doc
    /// (`:119-129`) says of every registration. (Not because `onDidChangeChatModelsEmitter` is shared —
    /// it is a private, per-instance `let`, and `Registration.owner`
    /// (`ExtensionEvent.swift:144`) holds its owner only as an
    /// `ObjectIdentifier`, never strongly, so there is no retain path from
    /// the emitter back to the adaptor either way.)
    ///
    /// This is a different scenario from
    /// `aTornDownAdaptorRaisesRatherThanAnsweringOrRejecting`, above: that
    /// test deallocates the adaptor itself, which is what makes a *new*
    /// registration raise (`VSCodeAPI.member`'s weak-owner capture, not
    /// `dispose()`). `dispose()` sets a flag; it does not deinit the
    /// adaptor. So the only question here is whether a listener registered
    /// *before* `dispose()` still hears a later
    /// `availableChatModelsDidChange()` once the adaptor is disposed but
    /// still alive — it must not.
    ///
    /// The post-dispose assertion is an absolute `__count == 1`, not a
    /// comparison against whatever the first fire produced, so a fixture
    /// whose listener never registered — or whose delivery was broken for
    /// an unrelated reason — reads 0 and fails it with or without the
    /// pre-dispose `__count` pair. That pair localizes a failure rather
    /// than catching one the post-dispose assertion would miss: it says the
    /// delivery broke before `dispose()` rather than after, without making
    /// you read the rest of the test to work that out. Nor is a
    /// post-dispose delivery reachable here for it to rule out — the
    /// `onDidChangeChatModelsListenerCount == 0` assertion below pins the
    /// registration count at 0 immediately after `dispose()`, nothing
    /// registers between there and the second fire, and
    /// `ExtensionEventEmitter.fire` queues nothing when `registrations` is
    /// empty.
    ///
    /// **Two obligations; only teardown is observable here (Ruling 88).**
    /// `dispose()` removes the sole registration, and
    /// `availableChatModelsDidChange()` separately guards on `isDisposed`
    /// and returns before its own `onDidChangeChatModelsEmitter.fire(())`.
    /// Either one alone stops the post-dispose delivery, so `__count` stays
    /// 1 whichever of them you delete: neither obligation can be assigned
    /// to the `__count` pair as its mutant. What that pair does kill is a
    /// delivery mutant — drop `onDidChangeChatModelsEmitter.fire(())` from
    /// `availableChatModelsDidChange()` and both `__count` reads come back
    /// 0 while both listener-count assertions still pass. The
    /// `onDidChangeChatModelsListenerCount` pair below is what covers
    /// teardown: delete `removeListeners(ownedBy:)` from `dispose()` and
    /// the post-dispose count reads 1 instead of 0. The guard's own effect
    /// — not recomputing `lastModelIdentifiers` — has no observable here:
    /// the field is `private` with no accessor.
    @Test
    func disposeStopsDeliveryToAnAlreadyRegisteredListener() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = TestLanguageModelProvider([Self.alpha])
        let languageModels = MainThreadLanguageModels(
            provider: provider, notImplementedLedger: NotImplementedLedger(),
            extensionIdentifier: "unused")
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__count = 0;
                vscode.lm.onDidChangeChatModels(function () { globalThis.__count += 1; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try installOnDidChangeChatModels(languageModels, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)

        // Positive control: before dispose, a fire is actually delivered.
        provider.availableChatModels = [Self.alpha, Self.beta]
        languageModels.availableChatModelsDidChange()
        let afterFirstFire = try #require(context.evaluateScript("globalThis.__count"))
        #expect(afterFirstFire.isNumber)
        #expect(Int(afterFirstFire.toInt32()) == 1)
        #expect(languageModels.onDidChangeChatModelsListenerCount == 1)

        languageModels.dispose()

        // dispose() has removed the registration outright — not merely
        // guarded against firing into it.
        #expect(languageModels.onDidChangeChatModelsListenerCount == 0)

        // A fire after dispose must not reach the now-unregistered listener.
        provider.availableChatModels = [Self.alpha]
        languageModels.availableChatModelsDidChange()

        let afterDispose = try #require(context.evaluateScript("globalThis.__count"))
        #expect(afterDispose.isNumber)
        #expect(Int(afterDispose.toInt32()) == 1)
    }
}
