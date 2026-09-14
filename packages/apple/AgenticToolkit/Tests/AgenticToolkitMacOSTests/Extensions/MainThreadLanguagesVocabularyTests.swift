// `vscode.languages.getLanguages` (task 5.6d) is decided across three
// layers, one suite per layer in this file:
//
// - `MainThreadLanguagesGetLanguagesTests` — the adaptor; see its own doc
//   comment below.
// - `LanguageContributionPointVocabularyTests` — the extension half of
//   the vocabulary, `LanguageContributionPoint.contributedLanguageIdentifiers`
//   itself, against real `ExtensionManifest.Language` values decoded from
//   JSON exactly as `LanguageContributionPointTests` does, never a double.
// - `HostLanguageVocabularyTests` — the production conformer, proving it
//   actually merges CodeEditLanguages' built-in catalogue with a real
//   `LanguageContributionPoint`'s contributions rather than only one side.

import Testing
import Foundation
import JavaScriptCore
import CodeEditLanguages
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A double for `ExtensionLanguageVocabulary`, private to this file: the
/// conformer of the same name in `MainThreadLanguagesTests.swift` is `private`
/// there too, so it is not visible here even though both files see the same
/// `@testable import AgenticToolkitMacOS`.
@MainActor
private final class TestLanguageVocabulary: ExtensionLanguageVocabulary {
    var languageIdentifiers: [String]

    init(_ languageIdentifiers: [String] = []) {
        self.languageIdentifiers = languageIdentifiers
    }
}

/// `vscode.languages.getLanguages` (task 5.6d) — the adaptor, wired onto a
/// real `ExtensionHost` with a `TestLanguageVocabulary` double standing in
/// for `HostLanguageVocabulary`, exactly as `MainThreadLanguagesTests` does
/// for `setLanguageConfiguration`. What is pinned here is the JS/Swift
/// boundary itself: the promise shape, freshness across calls, and
/// teardown — never `HostLanguageVocabulary`'s own composition, which a
/// double makes irrelevant to these tests by construction.
@MainActor
@Suite
struct MainThreadLanguagesGetLanguagesTests {

    // MARK: - Fixtures

    private func makeTempDirectory() throws -> URL {
        try ExtensionFixtures.makeTemporaryDirectory("MainThreadLanguagesVocabularyTests")
    }

    /// Installs `languages.getLanguages` onto `host`'s `vscode.languages`
    /// namespace — the one member this suite exercises, deliberately not
    /// `setLanguageConfiguration`, which `MainThreadLanguagesTests` already
    /// owns.
    private func install(_ languages: MainThreadLanguages, on host: ExtensionHost) throws {
        try host.defineVSCodeMember(
            namespacePath: "vscode.languages", name: "getLanguages",
            implementation: languages.getLanguages)
    }

    /// Polls `expression` until it evaluates to something other than
    /// `null`/`undefined`, or gives up after one second — the same polling
    /// `MainThreadCommandsTests.waitForGlobal` uses, and its doc comment's
    /// reasoning applies verbatim here: a `.then()` reaction is a microtask,
    /// never invoked synchronously regardless of how settled the promise
    /// already is, so nothing in this host's public surface promises *when*
    /// that queue drains relative to a bare `evaluateScript` call.
    private func waitForGlobal(_ context: JSContext, _ expression: String) async throws -> JSValue? {
        for _ in 0..<200 {
            if let value = context.evaluateScript(expression), !value.isNull, !value.isUndefined {
                return value
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        return nil
    }

    // MARK: - Resolution

    /// `getLanguages()` resolves — not rejects, not hangs — with exactly
    /// `vocabulary.languageIdentifiers`, in order. Kills mutation #2: an
    /// implementation that answers a pending promise (one that never settles
    /// on its own, or only settles in reaction to something this test never
    /// does) times out here, because nothing beyond the plain `.then()` below
    /// ever runs.
    @Test
    func getLanguagesResolvesWithTheVocabularysIdentifiersInOrder() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LanguageConfigurationStore()
        let vocabulary = TestLanguageVocabulary(["gamma", "alpha", "beta"])
        let languages = MainThreadLanguages(store: store, vocabulary: vocabulary)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__ids = null;
                vscode.languages.getLanguages().then(function (ids) { globalThis.__ids = ids; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languages, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let ids = try #require(await waitForGlobal(context, "globalThis.__ids"))
        #expect((ids.toArray() as? [String]) == ["gamma", "alpha", "beta"])
    }

    /// Ruling 16: mutating one call's answer (`.push`, `.sort`) must not
    /// change a later call's answer. Kills mutation #1 — an implementation
    /// that hands back a stored/shared `JSValue` reused across calls fails
    /// only this assertion; the resolution test above cannot see it, because
    /// it never calls twice or mutates what it got back. This fixture is
    /// unsorted too, independently of the resolution test's above — not a
    /// copy-paste of it.
    @Test
    func mutatingOneCallsAnswerDoesNotAffectTheNextCall() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LanguageConfigurationStore()
        let vocabulary = TestLanguageVocabulary(["zeta", "alpha", "mu"])
        let languages = MainThreadLanguages(store: store, vocabulary: vocabulary)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__second = null;
                vscode.languages.getLanguages().then(function (first) {
                    first.push('intruder');
                    first.sort();
                    return vscode.languages.getLanguages();
                }).then(function (second) {
                    globalThis.__second = second;
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(languages, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let second = try #require(await waitForGlobal(context, "globalThis.__second"))
        #expect((second.toArray() as? [String]) == ["zeta", "alpha", "mu"])
    }

    // MARK: - Teardown

    /// A torn-down adaptor rejects `getLanguages()` rather than answering or
    /// raising: `vscode.d.ts:14733` declares this member `Thenable<string[]>`,
    /// so `VSCodeAPI.member`'s `.rejectedPromise` teardown response is the one
    /// this member must use. Kills mutation #8 — wiring `getLanguages` with
    /// `.raisedException` instead makes the bare `vscode.languages.getLanguages()`
    /// call itself throw synchronously (it never returns a thenable to call
    /// `.then` on), so the exception escapes `run()` entirely,
    /// `globalThis.__afterTeardown` is never set, and `waitForGlobal` times
    /// out — the same failure shape
    /// `MainThreadCommandsTests.aTornDownAdaptorRaisesOrRejectsButNeverAnswersUndefined`
    /// relies on for `.raisedException` members.
    @Test
    func aTornDownAdaptorRejectsGetLanguagesRatherThanAnsweringOrRaising() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LanguageConfigurationStore()
        var languages: MainThreadLanguages? = MainThreadLanguages(
            store: store, vocabulary: TestLanguageVocabulary(["alpha"]))
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__afterTeardown = null;
                globalThis.run = function () {
                    vscode.languages.getLanguages().then(
                        function (ids) {
                            globalThis.__afterTeardown = { outcome: 'resolved', value: ids };
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
        // Scoped deliberately, mirroring `MainThreadCommandsTests`'s own
        // torn-down test: a `let` binding at test scope would itself keep the
        // adaptor alive past `languages = nil` below.
        if let live = languages { try install(live, on: host) }
        try await host.activate()

        // Nothing else holds the adaptor now: `getLanguages` captures it
        // weakly, and this extension's `activate` registered nothing that
        // would.
        languages = nil

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.run();")

        let out = try #require(await waitForGlobal(context, "globalThis.__afterTeardown"))
        #expect(out.forProperty("outcome")?.toString() == "rejected")
        #expect(out.forProperty("message")?.toString()
            == "vscode.languages.getLanguages is unavailable: this extension's host has been torn down.")
    }
}

/// `LanguageContributionPoint.contributedLanguageIdentifiers` (task 5.6d):
/// the extension half of `getLanguages`'s vocabulary, against real
/// `ExtensionManifest.Language` values decoded from JSON — mirroring
/// `LanguageContributionPointTests`'s own fixture pattern, over the
/// file-scope `manifest`/`apply` fixtures at the end of this file, which this
/// suite shares with `HostLanguageVocabularyTests`.
@MainActor
@Suite
struct LanguageContributionPointVocabularyTests {

    // MARK: - Deduplication across extensions

    /// Two extensions each contributing an entry named `dockerfile` yield one
    /// identifier, not two: `vscode.languages.getLanguages()` returns "the
    /// identifiers of all known languages," not one entry per contributor.
    /// Kills mutation #3 — an implementation that concatenates every
    /// extension's language ids without deduplicating would return
    /// `dockerfile` twice here.
    @Test
    func contributedIdentifiersDeduplicateAcrossExtensions() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(name: "one", languages: #"[{ "id": "dockerfile", "extensions": [".one"] }]"#),
            to: point
        )
        try apply(
            manifest(name: "two", languages: #"[{ "id": "dockerfile", "extensions": [".two"] }]"#),
            to: point
        )

        #expect(point.contributedLanguageIdentifiers.filter { $0 == "dockerfile" }.count == 1)
    }

    // MARK: - Order

    /// Order is `languagesByExtension.keys.sorted()` — the extension
    /// identifier, lexicographically — never hash order. Kills mutation #5,
    /// which is dropping `.sorted()` at `LanguageContributionPoint.swift:236`:
    /// `languagesByExtension` is a `Dictionary`, which has no insertion order
    /// to begin with, so an "apply order" mutant is not reachable at all;
    /// the mutant `.sorted()` actually guards against is `.keys` alone,
    /// whatever order `Dictionary` happens to hash its keys into. Swift
    /// randomizes that hash seed per process — nothing in this tree sets
    /// `SWIFT_DETERMINISTIC_HASHING` — so six extensions are registered here,
    /// out of sorted order, and the full resulting sequence is asserted:
    /// with six keys, a hash order that coincidentally reproduces the sorted
    /// sequence is roughly a 1-in-720 chance — 6! is the count of permutations,
    /// but Swift's key order is bucket order over a capacity-8 table with
    /// linear probing, not a uniform draw, so the true figure is near that
    /// rather than equal to it. Either way it is not a coin flip.
    @Test
    func contributedIdentifiersOrderBySortedExtensionIdentifierNotHashOrder() throws {
        let point = LanguageContributionPoint()
        try apply(manifest(name: "f", languages: #"[{ "id": "flang" }]"#), to: point)
        try apply(manifest(name: "d", languages: #"[{ "id": "dlang" }]"#), to: point)
        try apply(manifest(name: "b", languages: #"[{ "id": "blang" }]"#), to: point)
        try apply(manifest(name: "e", languages: #"[{ "id": "elang" }]"#), to: point)
        try apply(manifest(name: "c", languages: #"[{ "id": "clang" }]"#), to: point)
        try apply(manifest(name: "a", languages: #"[{ "id": "alang" }]"#), to: point)

        #expect(point.contributedLanguageIdentifiers == ["alang", "blang", "clang", "dlang", "elang", "flang"])
    }

    /// Within one extension, manifest order is preserved rather than
    /// re-sorted. Kills mutation #7 — an implementation that sorts each
    /// extension's own language array (alphabetically, or by any rule other
    /// than "as written") would reorder `["second", "first", "third"]` here;
    /// this is the one assertion in this suite that a merely-deduplicating,
    /// merely-cross-extension-sorted implementation could still fail.
    @Test
    func contributedIdentifiersPreserveManifestOrderWithinOneExtension() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(
                name: "multi",
                languages: #"[{ "id": "second" }, { "id": "first" }, { "id": "third" }]"#
            ),
            to: point
        )

        #expect(point.contributedLanguageIdentifiers == ["second", "first", "third"])
    }
}

/// `HostLanguageVocabulary` (task 5.6d): the production
/// `ExtensionLanguageVocabulary`, proving it actually merges
/// CodeEditLanguages' built-in catalogue with a real
/// `LanguageContributionPoint`'s contributions — never a double for either
/// side, because the whole point of this suite is that composition.
@MainActor
@Suite
struct HostLanguageVocabularyTests {

    /// A contributed `swift` does not appear twice: CodeEditLanguages already
    /// has a built-in `swift`, and an extension separately contributing a
    /// `swift` entry must not duplicate it. Kills mutation #4 — an
    /// implementation that concatenates `CodeLanguage.allLanguages`'s ids with
    /// `contributionPoint.contributedLanguageIdentifiers` without
    /// deduplicating against the built-ins would return `swift` twice here.
    @Test
    func aContributedBuiltInIdentifierIsNotDuplicated() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(name: "resw", languages: #"[{ "id": "swift", "extensions": [".notswift"] }]"#),
            to: point
        )
        let vocabulary = HostLanguageVocabulary(contributionPoint: point)

        #expect(vocabulary.languageIdentifiers.filter { $0 == "swift" }.count == 1)
    }

    /// `plainText` (`CodeLanguage.default.id`) is present, even though it is
    /// not a member of `CodeLanguage.allLanguages`. Kills mutation #6 —
    /// deleting the `CodeLanguage.default` line from `HostLanguageVocabulary`
    /// turns this assertion red while leaving every other test in this file
    /// green, since none of them mention `plainText`.
    @Test
    func plainTextIsPresent() {
        let point = LanguageContributionPoint()
        let vocabulary = HostLanguageVocabulary(contributionPoint: point)

        #expect(vocabulary.languageIdentifiers.contains(CodeLanguage.default.id.rawValue))
    }

    /// The composition this suite exists to prove: a genuine built-in
    /// identifier (`python`, a member of `CodeLanguage.allLanguages`) and a
    /// genuine contributed identifier (`cobol`, contributed here and not a
    /// member of `CodeLanguage.allLanguages`) both reach the output, and the
    /// built-in comes first. Kills two mutations — deleting the built-in loop
    /// (`HostLanguageVocabulary.swift:65-70` at `507721e3`) makes the `python`
    /// `#require` fail outright, since nothing else in this vocabulary supplies
    /// it; deleting the contributed loop (`:76-78`) makes the `cobol`
    /// `#require` fail outright, since nothing else supplies it either — and the
    /// `#expect` pins "built-ins lead" as an ordering claim beyond either
    /// `#require`.
    @Test
    func mergesBuiltInAndContributedIdentifiersWithBuiltInsLeading() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(name: "cobolext", languages: #"[{ "id": "cobol", "extensions": [".cob"] }]"#),
            to: point
        )
        let vocabulary = HostLanguageVocabulary(contributionPoint: point)

        let identifiers = vocabulary.languageIdentifiers
        let builtInIndex = try #require(identifiers.firstIndex(of: "python"))
        let contributedIndex = try #require(identifiers.firstIndex(of: "cobol"))
        #expect(builtInIndex < contributedIndex)
    }
}

// MARK: - Fixtures

/// Handed to `apply` and never opened — a language contribution point
/// resolves no paths, so a directory that does not exist is the cheapest way to
/// keep that true.
private let unusedDirectory = URL(fileURLWithPath: "/var/empty/agentic-tests-nonexistent")

/// A manifest contributing `languages`, for the two suites in this file that
/// need a contribution-point key where `ExtensionTestSupport`'s shared
/// `manifest` takes entry points.
///
/// File-scope rather than per-suite, which is the shape
/// `ExtensionTestSupport.swift:164-167` describes: one overload shadows the
/// shared one for every caller in the file. Both suites here need exactly this
/// manifest, so declaring it twice made the same fixture two answers to one
/// question — and the copies were byte-identical, so neither was the reason
/// for the other.
private func manifest(name: String, languages: String) throws -> ExtensionManifest {
    let json = """
    {
        "name": "\(name)",
        "publisher": "acme",
        "version": "1.0.0",
        "engines": { "vscode": "^1.74.0" },
        "contributes": { "languages": \(languages) }
    }
    """
    return try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
}

/// `@MainActor` because `LanguageContributionPoint` is
/// (`LanguageContributionPoint.swift:108`), matching how the shared helpers in
/// `ExtensionTestSupport.swift` that touch main-actor state are marked.
@MainActor
private func apply(_ manifest: ExtensionManifest, to point: LanguageContributionPoint) throws {
    let contributions = try #require(manifest.contributes)
    try point.apply(contributions, from: manifest, at: unusedDirectory)
}
