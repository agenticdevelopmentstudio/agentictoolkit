import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A double for `ExtensionLanguageVocabulary`, standing in for
/// `HostLanguageVocabulary` (task 5.6d) — this suite's own tests are all
/// about `setLanguageConfiguration`, so an empty vocabulary is all any of
/// them needs; see `MainThreadLanguagesVocabularyTests` for `getLanguages`
/// itself.
@MainActor
private final class TestLanguageVocabulary: ExtensionLanguageVocabulary {
    var languageIdentifiers: [String]

    init(_ languageIdentifiers: [String] = []) {
        self.languageIdentifiers = languageIdentifiers
    }
}

/// `vscode.languages.setLanguageConfiguration` (task 5.6c): validation,
/// translation, storage and the returned `Disposable` — wired onto a real
/// `ExtensionHost` and a real `LanguageConfigurationStore`, never doubles,
/// for the same reason `MainThreadCommandsTests` gives: the point of this
/// suite is the boundary between JavaScript and Swift, and a double for
/// either side would only ever agree with itself.
///
/// **What is not re-tested here.** Three existing `MainThreadCommandsTests`
/// — `theDisposableUnregistersAndIsIdempotent`,
/// `disposeRemovesEveryCommandItRegistered` and
/// `aDisposableFromBeforeDisposeDoesNotRemoveTheReRegisteredCommand` — still
/// pass unmodified after `MainThreadCommands.makeDisposable` was rewritten to
/// call `VSCodeAPI.disposable(in:onDispose:)`: that is evidence the
/// extraction changed nothing observable about `MainThreadCommands`'s own
/// disposables, because both callers' own teardowns
/// (`unregisterOwned`'s dictionary guard here,
/// `LanguageConfigurationStore.remove(handle:)` there) are independently
/// idempotent and would stay green even if `VSCodeAPI.disposable`'s own
/// `disposed` guard were deleted. It is **not** evidence that the guard
/// itself is covered — see `VSCodeAPIDisposableTests` for the one test in
/// the repository that pins it directly. This suite's own disposal tests
/// exist because `MainThreadLanguages` has different ownership state
/// (`LanguageConfigurationStore`, keyed by handle) for `onDispose` to close
/// over, not to repeat any idempotence proof.
@MainActor
@Suite
struct MainThreadLanguagesTests {

    // MARK: - Fixtures

    private func makeTempDirectory() throws -> URL {
        try ExtensionFixtures.makeTemporaryDirectory("MainThreadLanguagesTests")
    }

    /// Installs `languages.setLanguageConfiguration` onto `host`'s
    /// `vscode.languages` namespace — the one member this shell class has so
    /// far.
    private func install(_ languages: MainThreadLanguages, on host: ExtensionHost) throws {
        try host.defineVSCodeMember(
            namespacePath: "vscode.languages", name: "setLanguageConfiguration",
            implementation: languages.setLanguageConfiguration)
    }

    // MARK: - Ruling 12: the one refusal, and its other branch

    /// A `wordPattern` that compiles under `NSRegularExpression` and matches
    /// the empty string is refused, reproducing
    /// `extHostLanguageFeatures.ts:3009-3012`'s exact message shape. Kills a
    /// mutant that drops the refusal entirely (would leave `globalThis.err ==
    /// null` and register the configuration anyway) and a mutant that gets
    /// the message text wrong (a byte-for-byte `#expect` on the string, not
    /// just "is non-nil").
    @Test
    func wordPatternMatchingEmptyStringIsRefused() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LanguageConfigurationStore()
        let languages = MainThreadLanguages(store: store, vocabulary: TestLanguageVocabulary())
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.err = null;
                try {
                    vscode.languages.setLanguageConfiguration('plaintext', {
                        wordPattern: { source: 'a*', flags: '' }
                    });
                } catch (error) {
                    globalThis.err = error.message;
                }
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languages, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.err")?.toString()
            == "Invalid language configuration: wordPattern '/a*/' is not allowed to match the empty string.")
        #expect(store.configurations(forLanguage: "plaintext").isEmpty)
    }

    /// A `wordPattern` that compiles and does **not** match the empty string
    /// is accepted, and its exact `source`/`flags` survive translation
    /// verbatim — passed here as a genuine `RegExp` **literal**, not a
    /// duck-typed `{ source, flags }` object like the other two `wordPattern`
    /// fixtures in this file. `.source` and `.flags` are accessors inherited
    /// from `RegExp.prototype`, not own properties of a `RegExp` instance;
    /// this pins prototype-chain resolution for `wordPattern` specifically (a
    /// `hasOwnProperty`-only reader would silently translate every real
    /// extension's `wordPattern` to `nil`, which no duck-typed fixture can
    /// catch). It is not the only test that routes a real `RegExp` literal
    /// through `SerializedRegExp.make(from:)`'s `forProperty` calls —
    /// `indentationRulesAllFourPatternsSurviveTranslation` and
    /// `onEnterRuleWithAllFieldsTranslatesIndentActionToIndentOutdent` do too
    /// — but it is the only one where the `RegExp` sits directly on the
    /// top-level configuration object rather than nested inside an
    /// `indentationRules` or `onEnterRules` entry. Kills a mutant that
    /// refuses every `wordPattern` unconditionally (Ruling 12 over-applied)
    /// and a mutant that stores `flags` as always empty.
    @Test
    func wordPatternNotMatchingEmptyStringIsAcceptedFlagsAndAll() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LanguageConfigurationStore()
        let languages = MainThreadLanguages(store: store, vocabulary: TestLanguageVocabulary())
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.err = null;
                try {
                    vscode.languages.setLanguageConfiguration('rust', {
                        wordPattern: /[a-zA-Z_][a-zA-Z0-9_]*/gi
                    });
                } catch (error) {
                    globalThis.err = error.message;
                }
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languages, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.err")?.isNull == true)
        let configurations = store.configurations(forLanguage: "rust")
        #expect(configurations.count == 1)
        #expect(configurations.first?.wordPattern?.pattern == "[a-zA-Z_][a-zA-Z0-9_]*")
        #expect(configurations.first?.wordPattern?.flags == "gi")
    }

    /// No `wordPattern` at all — the overwhelmingly common case — is
    /// accepted with `wordPattern == nil`, not treated as "matches the empty
    /// string" by some default. Kills a mutant that treats an absent
    /// `wordPattern` as present-and-empty (`wordPatternRefusal`'s `guard let
    /// wordPattern else { return nil }` turned into unwrapping a default).
    @Test
    func absentWordPatternIsAcceptedAndStaysNil() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LanguageConfigurationStore()
        let languages = MainThreadLanguages(store: store, vocabulary: TestLanguageVocabulary())
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.err = null;
                try {
                    vscode.languages.setLanguageConfiguration('plaintext', { brackets: [['(', ')']] });
                } catch (error) {
                    globalThis.err = error.message;
                }
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languages, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.err")?.isNull == true)
        let configuration = try #require(store.configurations(forLanguage: "plaintext").first)
        #expect(configuration.wordPattern == nil)
    }

    /// A `wordPattern` that is syntactically valid to store as two strings
    /// but fails to **compile** under `NSRegularExpression` (an unbalanced
    /// group — ICU and V8 disagree about plenty of syntax, but this one is
    /// invalid everywhere except as a bare pair of strings crossing the
    /// bridge) is stored unvalidated rather than refused — Ruling 12's other
    /// branch. Kills a mutant that treats a `catch` from
    /// `NSRegularExpression`'s initializer as a refusal (collapsing the two
    /// branches Ruling 12 requires kept separate).
    @Test
    func wordPatternFailingToCompileIsStoredUnvalidatedNotRefused() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LanguageConfigurationStore()
        let languages = MainThreadLanguages(store: store, vocabulary: TestLanguageVocabulary())
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.err = null;
                try {
                    vscode.languages.setLanguageConfiguration('weird', {
                        wordPattern: { source: '(unclosed', flags: '' }
                    });
                } catch (error) {
                    globalThis.err = error.message;
                }
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languages, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.err")?.isNull == true)
        let configuration = try #require(store.configurations(forLanguage: "weird").first)
        #expect(configuration.wordPattern?.pattern == "(unclosed")
    }

    // MARK: - Translation: the union and enum members

    /// `comments.lineComment` round-trips both legal shapes:
    /// `vscode.d.ts:6501-6512`'s bare-string form, and its `LineCommentRule`
    /// object form, including `noIndent`. Kills a mutant that only checks
    /// `.isString` and never falls through to the object shape (or the
    /// reverse — checks the object shape first and never reads a bare
    /// string).
    @Test
    func lineCommentRoundTripsBothStringAndRuleShapes() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LanguageConfigurationStore()
        let languages = MainThreadLanguages(store: store, vocabulary: TestLanguageVocabulary())
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.languages.setLanguageConfiguration('lang-a', {
                    comments: { lineComment: '//' }
                });
                vscode.languages.setLanguageConfiguration('lang-b', {
                    comments: { lineComment: { comment: ';', noIndent: true } }
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languages, on: host)
        try await host.activate()

        let stringForm = try #require(store.configurations(forLanguage: "lang-a").first?.comments?.lineComment)
        guard case .string(let comment) = stringForm else {
            Issue.record("expected .string, got \(stringForm)")
            return
        }
        #expect(comment == "//")

        let ruleForm = try #require(store.configurations(forLanguage: "lang-b").first?.comments?.lineComment)
        guard case .rule(let rule) = ruleForm else {
            Issue.record("expected .rule, got \(ruleForm)")
            return
        }
        #expect(rule.comment == ";")
        #expect(rule.noIndent == true)
    }

    /// `autoClosingPairs[].notIn`'s numbers arrive as the matching
    /// `SyntaxTokenType` cases, in order, dropping neither valid nor invalid
    /// entries incorrectly. Kills a mutant that maps `notIn` positionally by
    /// index instead of by value (e.g. `SyntaxTokenType(rawValue: index)`)
    /// and a mutant that reads `notIn` as a single number rather than an
    /// array.
    @Test
    func autoClosingPairNotInTranslatesToTheMatchingEnumCases() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LanguageConfigurationStore()
        let languages = MainThreadLanguages(store: store, vocabulary: TestLanguageVocabulary())
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.languages.setLanguageConfiguration('lang-c', {
                    autoClosingPairs: [
                        { open: '"', close: '"', notIn: [1, 3] },
                        { open: '(', close: ')' }
                    ]
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languages, on: host)
        try await host.activate()

        let pairs = try #require(store.configurations(forLanguage: "lang-c").first?.autoClosingPairs)
        #expect(pairs.count == 2)
        #expect(pairs[0].open == "\"")
        #expect(pairs[0].notIn == [.comment, .regEx])
        #expect(pairs[1].notIn == nil)
    }

    /// All four `indentationRules` patterns — the two required
    /// (`increaseIndentPattern`, `decreaseIndentPattern`) and the two
    /// optional (`indentNextLinePattern`, `unIndentedLinePattern`) — survive
    /// translation with their `source`/`flags` intact, each pattern passed as
    /// a genuine `RegExp` literal per the same prototype-chain reasoning
    /// `wordPatternNotMatchingEmptyStringIsAcceptedFlagsAndAll` gives. Kills
    /// a mutant that reads only the two required patterns and leaves the
    /// optional two always `nil`, and a mutant that transposes
    /// increase/decrease (assigning `increaseIndentPattern`'s value to
    /// `decreaseIndentPattern` or vice versa).
    @Test
    func indentationRulesAllFourPatternsSurviveTranslation() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LanguageConfigurationStore()
        let languages = MainThreadLanguages(store: store, vocabulary: TestLanguageVocabulary())
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.languages.setLanguageConfiguration('lang-indent', {
                    indentationRules: {
                        increaseIndentPattern: /increase$/g,
                        decreaseIndentPattern: /^decrease/i,
                        indentNextLinePattern: /nextline/,
                        unIndentedLinePattern: /unindented/m
                    }
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languages, on: host)
        try await host.activate()

        let rules = try #require(store.configurations(forLanguage: "lang-indent").first?.indentationRules)
        #expect(rules.increaseIndentPattern.pattern == "increase$")
        #expect(rules.increaseIndentPattern.flags == "g")
        #expect(rules.decreaseIndentPattern.pattern == "^decrease")
        #expect(rules.decreaseIndentPattern.flags == "i")
        #expect(rules.indentNextLinePattern?.pattern == "nextline")
        #expect(rules.indentNextLinePattern?.flags == "")
        #expect(rules.unIndentedLinePattern?.pattern == "unindented")
        #expect(rules.unIndentedLinePattern?.flags == "m")
    }

    /// An `onEnterRules` entry with all four fields present —
    /// `beforeText`/`afterText`/`previousLineText` as real `RegExp` literals,
    /// and `action.indentAction: 2` — translates `indentAction` to
    /// `.indentOutdent`, matching `vscode.d.ts:6539-6558`'s quoted raw value.
    /// Kills a mutant that gets `IndentAction`'s raw values out of step with
    /// upstream (e.g. swapping `.indent` and `.indentOutdent`'s raw values),
    /// which `IndentAction`'s own doc comment calls out as a defect no
    /// compiler catches. Also asserts `action.appendText`/`action.removeText`,
    /// which kills an `EnterAction.make(from:)` mutant that drops either
    /// optional field or swaps them.
    @Test
    func onEnterRuleWithAllFieldsTranslatesIndentActionToIndentOutdent() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LanguageConfigurationStore()
        let languages = MainThreadLanguages(store: store, vocabulary: TestLanguageVocabulary())
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.languages.setLanguageConfiguration('lang-enter', {
                    onEnterRules: [{
                        beforeText: /before$/,
                        afterText: /^after/,
                        previousLineText: /prev/,
                        action: { indentAction: 2, appendText: '  ', removeText: 1 }
                    }]
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languages, on: host)
        try await host.activate()

        let onEnterRules = try #require(store.configurations(forLanguage: "lang-enter").first?.onEnterRules)
        #expect(onEnterRules.count == 1)
        let rule = try #require(onEnterRules.first)
        #expect(rule.beforeText.pattern == "before$")
        #expect(rule.afterText?.pattern == "^after")
        #expect(rule.previousLineText?.pattern == "prev")
        #expect(rule.action.indentAction == .indentOutdent)
        #expect(rule.action.appendText == "  ")
        #expect(rule.action.removeText == 1)
    }

    /// A required field missing drops the whole rule, at two different
    /// granularities: an `indentationRules` object missing
    /// `increaseIndentPattern` makes the whole `indentationRules` field
    /// `nil` (per `IndentationRule.make(from:)`'s own doc), while an
    /// `onEnterRules` array with one entry missing `beforeText` drops only
    /// that entry, keeping a sibling valid entry (per
    /// `OnEnterRule.makeArray(from:)`'s own doc). Kills a mutant that
    /// substitutes a default pattern for a missing required field instead of
    /// invalidating the rule, and a mutant that drops the whole
    /// `onEnterRules` array when any one entry is malformed rather than just
    /// that entry.
    @Test
    func requiredFieldMissingDropsWholeIndentationRuleButOnlyTheOffendingOnEnterRuleEntry() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LanguageConfigurationStore()
        let languages = MainThreadLanguages(store: store, vocabulary: TestLanguageVocabulary())
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.languages.setLanguageConfiguration('lang-missing', {
                    indentationRules: {
                        decreaseIndentPattern: /^decrease/
                    },
                    onEnterRules: [
                        { afterText: /no-beforeText/, action: { indentAction: 0 } },
                        { beforeText: /valid$/, action: { indentAction: 1 } }
                    ]
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languages, on: host)
        try await host.activate()

        let configuration = try #require(store.configurations(forLanguage: "lang-missing").first)
        #expect(configuration.indentationRules == nil)
        let onEnterRules = try #require(configuration.onEnterRules)
        #expect(onEnterRules.count == 1)
        #expect(onEnterRules.first?.beforeText.pattern == "valid$")
    }

    // MARK: - Ruling 13: the two deprecated members are dropped

    /// `__electricCharacterSupport` and `__characterPairSupport` are
    /// accepted (the call does not raise) and a sibling member on the same
    /// object still translates normally. Kills a mutant that makes either
    /// deprecated member's mere presence a refusal.
    ///
    /// **Does not kill a mutant that reintroduces either member as a stored
    /// field.** No assertion here inspects `LanguageConfiguration` for the
    /// *absence* of a field — only `globalThis.err` and `brackets` — so
    /// adding `public let electricCharacterSupport: …` and populating it in
    /// `make(from:)` would compile and leave both green. Pinning that would
    /// need asserting the whole translated value against a fully-spelled
    /// expected `LanguageConfiguration`, which was deliberately not done
    /// here: it would fail this test on every future field addition to
    /// `LanguageConfiguration`, a brittleness cost paid to guard a
    /// refactor that is not itself a defect.
    @Test
    func deprecatedMembersAreAcceptedAndTranslateToNothing() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LanguageConfigurationStore()
        let languages = MainThreadLanguages(store: store, vocabulary: TestLanguageVocabulary())
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.err = null;
                try {
                    vscode.languages.setLanguageConfiguration('lang-d', {
                        brackets: [['{', '}']],
                        __electricCharacterSupport: { docComment: {} },
                        __characterPairSupport: { autoClosingPairs: [] }
                    });
                } catch (error) {
                    globalThis.err = error.message;
                }
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languages, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.err")?.isNull == true)
        let configuration = try #require(store.configurations(forLanguage: "lang-d").first)
        #expect(configuration.brackets == [CharacterPair(open: "{", close: "}")])
    }

    // MARK: - Ruling 9: the store, and the returned Disposable

    /// The returned `Disposable`'s `dispose()` actually removes the
    /// registration from the store — asserted on store state before and
    /// after, not merely "does not throw". Kills a mutant that returns a
    /// `Disposable` whose `dispose` block is empty (`VSCodeAPI.disposable`'s
    /// `onDispose` never wired to `store.remove(handle:)`).
    @Test
    func disposeRemovesTheRegistrationFromTheStore() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LanguageConfigurationStore()
        let languages = MainThreadLanguages(store: store, vocabulary: TestLanguageVocabulary())
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.disposable = vscode.languages.setLanguageConfiguration('lang-e', {
                    brackets: [['[', ']']]
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languages, on: host)
        try await host.activate()

        #expect(store.configurations(forLanguage: "lang-e").count == 1)

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.disposable.dispose()")

        #expect(store.configurations(forLanguage: "lang-e").isEmpty)
    }

    /// Calling `dispose()` a second time is a no-op — it does not throw, and
    /// it does not affect a since-added registration for the same language.
    /// Kills a mutant that re-derives "what to remove" per call (reading the
    /// current registration for `lang-f` at fire time, say, instead of the
    /// handle this `Disposable` was minted for) and so removes the wrong,
    /// later registration. Does **not** kill a dropped `disposed` guard in
    /// `VSCodeAPI.disposable` — see `VSCodeAPIDisposableTests` for that; a
    /// second `store.remove(handle:)` call for the same handle is harmless
    /// by itself, so this test would stay green either way.
    @Test
    func disposingTwiceIsANoOpAndDoesNotTouchALaterRegistration() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LanguageConfigurationStore()
        let languages = MainThreadLanguages(store: store, vocabulary: TestLanguageVocabulary())
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.disposable = vscode.languages.setLanguageConfiguration('lang-f', {
                    brackets: [['[', ']']]
                });
                globalThis.disposable.dispose();
                globalThis.second = vscode.languages.setLanguageConfiguration('lang-f', {
                    brackets: [['<', '>']]
                });
                globalThis.err = null;
                try {
                    globalThis.disposable.dispose();
                } catch (error) {
                    globalThis.err = error.message;
                }
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languages, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.err")?.isNull == true)
        let remaining = store.configurations(forLanguage: "lang-f")
        #expect(remaining.count == 1)
        #expect(remaining.first?.brackets == [CharacterPair(open: "<", close: ">")])
    }

    /// Two configurations for the same language both survive registration —
    /// the store is keyed by an opaque handle, not by language id — and
    /// disposing one leaves exactly the other. Kills a mutant that keys
    /// `LanguageConfigurationStore` by `languageId` (the second `add` would
    /// silently overwrite the first, leaving `count == 1` immediately after
    /// both registrations, before either is disposed).
    @Test
    func twoConfigurationsForOneLanguageBothSurviveAndDisposingOneLeavesTheOther() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LanguageConfigurationStore()
        let languages = MainThreadLanguages(store: store, vocabulary: TestLanguageVocabulary())
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.first = vscode.languages.setLanguageConfiguration('lang-g', {
                    brackets: [['(', ')']]
                });
                globalThis.secondDisposable = vscode.languages.setLanguageConfiguration('lang-g', {
                    brackets: [['[', ']']]
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languages, on: host)
        try await host.activate()

        #expect(store.configurations(forLanguage: "lang-g").count == 2)

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.secondDisposable.dispose()")

        let remaining = store.configurations(forLanguage: "lang-g")
        #expect(remaining.count == 1)
        #expect(remaining.first?.brackets == [CharacterPair(open: "(", close: ")")])
    }

    /// Two `MainThreadLanguages` adaptors sharing one `LanguageConfiguration
    /// Store` — as the type's own doc says a test may construct — each own
    /// only what they themselves added. A third registration seeded directly
    /// through `store.add(languageId:configuration:)`, owned by neither
    /// adaptor, survives `languagesA.dispose()` exactly as `languagesB`'s own
    /// registration does. Kills a mutant that has `dispose()` walk `store`'s
    /// entire registration table instead of only `ownedHandles` (would also
    /// remove `languagesB`'s and the seeded registration), and proves
    /// `LanguageConfigurationStore.contains(handle:)` keeps answering `true`
    /// for a handle no adaptor's own `dispose()` has any reason to touch.
    @Test
    func disposeOnOneAdaptorLeavesASharedStoresOtherRegistrationsAlone() async throws {
        let directoryA = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directoryA) }
        let directoryB = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directoryB) }

        let store = LanguageConfigurationStore()
        let languagesA = MainThreadLanguages(store: store, vocabulary: TestLanguageVocabulary())
        let languagesB = MainThreadLanguages(store: store, vocabulary: TestLanguageVocabulary())

        let hostA = try makeHost(
            name: "alpha",
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.languages.setLanguageConfiguration('lang-shared-a', {
                    brackets: [['(', ')']]
                });
            };
            """,
            in: directoryA
        )
        defer { hostA.dispose() }
        try install(languagesA, on: hostA)
        try await hostA.activate()

        let hostB = try makeHost(
            name: "beta",
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.languages.setLanguageConfiguration('lang-shared-b', {
                    brackets: [['[', ']']]
                });
            };
            """,
            in: directoryB
        )
        defer { hostB.dispose() }
        try install(languagesB, on: hostB)
        try await hostB.activate()

        let seeded = store.add(
            languageId: "lang-shared-c",
            configuration: LanguageConfiguration.make(from: nil))
        #expect(store.contains(handle: seeded))

        languagesA.dispose()

        #expect(store.configurations(forLanguage: "lang-shared-a").isEmpty)
        #expect(store.configurations(forLanguage: "lang-shared-b").count == 1)
        #expect(store.contains(handle: seeded))
    }

    // MARK: - task 5.3's Ruling 6-equivalent: a malformed id raises synchronously

    /// A non-string language id raises rather than registering something no
    /// editor could ever be. Kills a mutant that coerces a non-string first
    /// argument (e.g. `String(describing:)`) instead of refusing it, and a
    /// mutant that silently no-ops instead of raising.
    @Test
    func nonStringLanguageIdRaisesRatherThanRegistering() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LanguageConfigurationStore()
        let languages = MainThreadLanguages(store: store, vocabulary: TestLanguageVocabulary())
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.err = null;
                try {
                    vscode.languages.setLanguageConfiguration(42, { brackets: [['(', ')']] });
                } catch (error) {
                    globalThis.err = error.message;
                }
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languages, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.err")?.toString()
            == "setLanguageConfiguration requires a string language id.")
        #expect(store.count == 0)
    }
}
