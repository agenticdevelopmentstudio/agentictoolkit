import AgenticToolkitCore
import Foundation
import Testing
@testable import AgenticToolkitLanguage

/// The `contributes.snippets` contribution point.
///
/// Every test here writes a real extension directory and lets the store
/// resolve the manifest's paths against it, because path resolution is one of
/// the two things this class can get wrong — the other being which snippets
/// come back for a language — and neither is observable through a stubbed
/// file reader.
@MainActor
@Suite
struct SnippetStoreTests {

    // MARK: - Fixtures

    private static let logSnippets = #"""
    {
        "Log": { "prefix": "log", "body": "print($1)", "description": "Print a value" }
    }
    """#

    private static let scopedSnippets = #"""
    {
        "Component": { "prefix": "cmp", "body": "…", "scope": "typescriptreact" },
        "Anywhere": { "prefix": "any", "body": "…" }
    }
    """#

    /// A file that survives neither strict JSON nor comment stripping.
    private static let brokenSnippets = "// managed elsewhere; rewritten at runtime"

    private func makeExtensionDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnippetStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes a file *inside* `directory`.
    ///
    /// Deliberately not the resolution the store uses: a helper that resolved
    /// paths the same way the subject does would agree with it even when both
    /// are wrong, which is exactly how a base URL that resolved one level too
    /// high went unnoticed until the macOS editor tests read a real store.
    private func write(_ contents: String, to relativePath: String, in directory: URL) throws {
        let url = relativePath.split(separator: "/").reduce(directory) { url, component in
            url.appendingPathComponent(String(component))
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// A decoded manifest, built the way the registry builds one — from JSON —
    /// rather than through a memberwise initializer the type does not offer.
    private func manifest(snippetEntries: [(language: String, path: String)]) throws -> ExtensionManifest {
        let entries = snippetEntries
            .map { #"{ "language": "\#($0.language)", "path": "\#($0.path)" }"# }
            .joined(separator: ", ")
        let json = """
        {
            "name": "snippets",
            "publisher": "acme",
            "version": "1.0.0",
            "engines": { "vscode": "^1.74.0" },
            "contributes": { "snippets": [\(entries)] }
        }
        """
        return try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
    }

    private func apply(
        _ manifest: ExtensionManifest,
        at directory: URL,
        to store: SnippetStore
    ) throws {
        let contributions = try #require(manifest.contributes)
        try store.apply(contributions, from: manifest, at: directory)
    }

    // MARK: - Identity

    @Test("the store consumes the snippets key")
    func contributionKey() {
        #expect(SnippetStore().contributionKey == "snippets")
    }

    // MARK: - Applying

    @Test("snippets are read from a path relative to the extension's own directory")
    func readsRelativeToDirectory() throws {
        let directory = try makeExtensionDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(Self.logSnippets, to: "snippets/swift.json", in: directory)

        let store = SnippetStore()
        try apply(try manifest(snippetEntries: [("swift", "./snippets/swift.json")]), at: directory, to: store)

        let snippets = store.snippets(forLanguage: "swift")
        #expect(snippets.map(\.prefix) == ["log"])
        #expect(snippets.first?.extensionIdentifier == "acme.snippets")
        #expect(store.failures.isEmpty)
    }

    @Test("a path written without a ./ prefix resolves too")
    func resolvesPathWithoutDotSlash() throws {
        // One real entry in 160 is written this way, and a `hasPrefix("./")`
        // strip would leave it unresolved while the other 159 worked.
        let directory = try makeExtensionDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(Self.logSnippets, to: "snippets/.code-snippets", in: directory)

        let store = SnippetStore()
        try apply(try manifest(snippetEntries: [("swift", "snippets/.code-snippets")]), at: directory, to: store)

        #expect(store.snippets(forLanguage: "swift").map(\.prefix) == ["log"])
    }

    @Test("a base URL that does not announce itself as a directory still resolves")
    func resolvesAgainstAFilePathBaseURL() throws {
        // `URL(fileURLWithPath:relativeTo:)` resolves against the base's parent
        // unless the base is known to be a directory, and a caller that built
        // the extension's URL without `isDirectory: true` hands one that is
        // not. Every snippet file then reads one level too high — silently,
        // as a "no such file" failure rather than a crash.
        let directory = try makeExtensionDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(Self.logSnippets, to: "snippets/swift.json", in: directory)
        let asAFilePath = URL(fileURLWithPath: directory.path)

        let store = SnippetStore()
        try apply(
            try manifest(snippetEntries: [("swift", "./snippets/swift.json")]),
            at: asAFilePath,
            to: store
        )

        #expect(store.failures.isEmpty)
        #expect(store.snippets(forLanguage: "swift").map(\.prefix) == ["log"])
    }

    @Test("the manifest entry's language is the key")
    func languageKeying() throws {
        let directory = try makeExtensionDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(Self.logSnippets, to: "snippets/swift.json", in: directory)

        let store = SnippetStore()
        try apply(try manifest(snippetEntries: [("swift", "./snippets/swift.json")]), at: directory, to: store)

        #expect(store.snippets(forLanguage: "python").isEmpty)
    }

    @Test("a per-snippet scope narrows within the file's language")
    func scopeNarrowsWithinLanguage() throws {
        let directory = try makeExtensionDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(Self.scopedSnippets, to: "snippets/ts.json", in: directory)

        let store = SnippetStore()
        try apply(try manifest(snippetEntries: [("typescript", "./snippets/ts.json")]), at: directory, to: store)

        // The file is declared for `typescript`; the scoped snippet inside it
        // says `typescriptreact`, so only the unscoped one is offered here.
        #expect(store.snippets(forLanguage: "typescript").map(\.prefix) == ["any"])
        // And the scoped one is not offered for its own scope either — the
        // manifest entry, not the scope, decides which languages the file
        // participates in at all.
        #expect(store.snippets(forLanguage: "typescriptreact").isEmpty)
    }

    @Test("two files for the same language are both read")
    func twoFilesOneLanguage() throws {
        let directory = try makeExtensionDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(Self.logSnippets, to: "snippets/a.json", in: directory)
        try write(#"{"Guard": {"prefix": "guard", "body": "…"}}"#, to: "snippets/b.json", in: directory)

        let store = SnippetStore()
        try apply(
            try manifest(snippetEntries: [("swift", "./snippets/a.json"), ("swift", "./snippets/b.json")]),
            at: directory,
            to: store
        )

        #expect(store.snippets(forLanguage: "swift").map(\.prefix) == ["log", "guard"])
    }

    @Test("applying twice leaves one copy")
    func applyIsIdempotent() throws {
        let directory = try makeExtensionDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(Self.logSnippets, to: "snippets/swift.json", in: directory)

        let store = SnippetStore()
        let loaded = try manifest(snippetEntries: [("swift", "./snippets/swift.json")])
        try apply(loaded, at: directory, to: store)
        try apply(loaded, at: directory, to: store)

        #expect(store.snippets(forLanguage: "swift").count == 1)
    }

    // MARK: - Failures

    @Test("one unreadable file does not cost the extension its other files")
    func oneBadFileDoesNotSinkTheRest() throws {
        let directory = try makeExtensionDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(Self.brokenSnippets, to: "snippets/broken.json", in: directory)
        try write(Self.logSnippets, to: "snippets/good.json", in: directory)

        let store = SnippetStore()
        try apply(
            try manifest(snippetEntries: [("swift", "./snippets/broken.json"), ("swift", "./snippets/good.json")]),
            at: directory,
            to: store
        )

        #expect(store.snippets(forLanguage: "swift").map(\.prefix) == ["log"])
        #expect(store.failures.count == 1)
        let failure = try #require(store.failures.first)
        #expect(failure.extensionIdentifier == "acme.snippets")
        // The path as the manifest wrote it, which is what an author has to fix.
        #expect(failure.path == "./snippets/broken.json")
        #expect(!failure.reason.isEmpty)
    }

    @Test("a declared file that is not on disk is a recorded failure, not a crash")
    func missingFileIsRecorded() throws {
        let directory = try makeExtensionDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SnippetStore()
        try apply(try manifest(snippetEntries: [("swift", "./snippets/absent.json")]), at: directory, to: store)

        #expect(store.snippets(forLanguage: "swift").isEmpty)
        #expect(store.failures.map(\.path) == ["./snippets/absent.json"])
    }

    // MARK: - Withdrawing

    @Test("withdrawing removes the extension's snippets and its failures")
    func withdrawRemovesEverything() throws {
        let directory = try makeExtensionDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(Self.logSnippets, to: "snippets/good.json", in: directory)
        try write(Self.brokenSnippets, to: "snippets/broken.json", in: directory)

        let store = SnippetStore()
        try apply(
            try manifest(snippetEntries: [("swift", "./snippets/good.json"), ("swift", "./snippets/broken.json")]),
            at: directory,
            to: store
        )
        #expect(!store.snippets(forLanguage: "swift").isEmpty)
        #expect(!store.failures.isEmpty)

        store.withdraw(extensionIdentifier: "acme.snippets")

        #expect(store.snippets(forLanguage: "swift").isEmpty)
        #expect(store.failures.isEmpty)
    }

    @Test("withdrawing an identifier that was never applied is safe")
    func withdrawUnknownIsSafe() {
        let store = SnippetStore()
        store.withdraw(extensionIdentifier: "nobody.nothing")
        #expect(store.snippets(forLanguage: "swift").isEmpty)
    }

    @Test("withdrawing one extension leaves another's snippets alone")
    func withdrawIsPerExtension() throws {
        let first = try makeExtensionDirectory()
        let second = try makeExtensionDirectory()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        try write(Self.logSnippets, to: "snippets/swift.json", in: first)
        try write(#"{"Guard": {"prefix": "guard", "body": "…"}}"#, to: "snippets/swift.json", in: second)

        let store = SnippetStore()
        let firstManifest = try manifest(snippetEntries: [("swift", "./snippets/swift.json")])
        try apply(firstManifest, at: first, to: store)

        // A second extension, distinguished by name so its identifier differs.
        let secondJSON = """
        {
            "name": "more-snippets",
            "publisher": "acme",
            "version": "1.0.0",
            "engines": { "vscode": "^1.74.0" },
            "contributes": { "snippets": [{ "language": "swift", "path": "./snippets/swift.json" }] }
        }
        """
        let secondManifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(secondJSON.utf8))
        try apply(secondManifest, at: second, to: store)

        #expect(store.snippets(forLanguage: "swift").count == 2)

        store.withdraw(extensionIdentifier: firstManifest.identifier)

        #expect(store.snippets(forLanguage: "swift").map(\.prefix) == ["guard"])
    }

    // MARK: - Nothing to contribute

    @Test("an extension that declares no snippets contributes none")
    func noSnippetsDeclared() throws {
        let directory = try makeExtensionDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SnippetStore()
        try apply(try manifest(snippetEntries: []), at: directory, to: store)

        #expect(store.snippets(forLanguage: "swift").isEmpty)
        #expect(store.failures.isEmpty)
    }
}
