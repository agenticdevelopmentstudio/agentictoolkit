import Foundation
import LanguageServerProtocol
import Testing
@testable import AgenticToolkitLanguage

/// Reading one VS Code snippets file.
///
/// The fixtures are the shapes measured across 113 real files: an object keyed
/// by snippet name, a `body` that is as often an array of lines as a single
/// string, undocumented keys in the majority of files, and — twice — a file
/// that does not survive comment stripping at all.
@Suite
struct SnippetFileTests {

    private static let identifier = "acme.snippets"

    private func parse(_ text: String) throws -> [ExtensionSnippet] {
        try SnippetFile.parse(Data(text.utf8), extensionIdentifier: Self.identifier)
    }

    // MARK: - The documented four fields

    @Test("a snippet's four documented fields are read, and the key is its name")
    func documentedFields() throws {
        let snippets = try parse("""
        {
            "For Loop": {
                "prefix": "for",
                "body": "for (const item of list) { $0 }",
                "description": "A for-of loop"
            }
        }
        """)

        #expect(snippets.count == 1)
        let snippet = try #require(snippets.first)
        #expect(snippet.name == "For Loop")
        #expect(snippet.prefix == "for")
        #expect(snippet.body == "for (const item of list) { $0 }")
        #expect(snippet.description == "A for-of loop")
        #expect(snippet.scopes.isEmpty)
        #expect(snippet.extensionIdentifier == Self.identifier)
    }

    @Test("an array body is joined with newlines")
    func arrayBodyIsJoined() throws {
        let snippets = try parse("""
        {
            "Guard": {
                "prefix": "guard",
                "body": ["guard let ${1:value} else {", "    return", "}"]
            }
        }
        """)

        let snippet = try #require(snippets.first)
        #expect(snippet.body == "guard let ${1:value} else {\n    return\n}")
    }

    @Test("a description is optional")
    func descriptionIsOptional() throws {
        let snippets = try parse(#"{"Log": {"prefix": "log", "body": "print($1)"}}"#)
        #expect(try #require(snippets.first).description == nil)
    }

    // MARK: - Scope

    @Test("a scope is split on commas, trimmed, and stripped of empties")
    func scopeIsSplit() throws {
        let snippets = try parse("""
        {
            "Component": {
                "prefix": "cmp",
                "body": "…",
                "scope": "typescript, typescriptreact ,,javascript"
            }
        }
        """)

        #expect(try #require(snippets.first).scopes == ["typescript", "typescriptreact", "javascript"])
    }

    // MARK: - Entries that cannot be summoned

    @Test("a snippet with no prefix is skipped, and its siblings are kept")
    func missingPrefixIsSkipped() throws {
        let snippets = try parse("""
        {
            "Unusable": { "body": "nothing can type this" },
            "Usable": { "prefix": "ok", "body": "fine" }
        }
        """)

        #expect(snippets.map(\.name) == ["Usable"])
    }

    @Test("a snippet with no body, or a body of the wrong type, is skipped")
    func missingOrWrongTypedBodyIsSkipped() throws {
        let snippets = try parse("""
        {
            "No body": { "prefix": "a" },
            "Numeric body": { "prefix": "b", "body": 42 },
            "Mixed array body": { "prefix": "c", "body": ["line", 2] },
            "Usable": { "prefix": "d", "body": "fine" }
        }
        """)

        #expect(snippets.map(\.name) == ["Usable"])
    }

    // MARK: - Everything the schema does not document

    @Test("undocumented keys never reject a snippet")
    func undocumentedKeysAreIgnored() throws {
        // `key` and `isFileTemplate` are real and undocumented; `descriptison`
        // is one real file's misspelling. A strict decoder would throw on all
        // three and lose a file that VS Code reads perfectly well.
        let snippets = try parse("""
        {
            "Odd": {
                "prefix": "odd",
                "body": "…",
                "key": "ctrl+alt+o",
                "isFileTemplate": true,
                "descriptison": "misspelled by its author"
            }
        }
        """)

        #expect(snippets.count == 1)
        #expect(try #require(snippets.first).description == nil)
    }

    @Test("a file that nests snippets under a category loses the category, not the file")
    func nestedCategoryIsSkipped() throws {
        // A handful of real files put a category name where a snippet name
        // belongs. The nested object has no `prefix`, so it is skipped like
        // any other unusable entry — and the well-formed entries beside it
        // still load.
        let snippets = try parse("""
        {
            "Category": { "Inner": { "prefix": "in", "body": "…" } },
            "Flat": { "prefix": "flat", "body": "…" }
        }
        """)

        #expect(snippets.map(\.name) == ["Flat"])
    }

    @Test("snippets come back in a stable order")
    func stableOrder() throws {
        // A deserialized JSON object has no order, so the reader imposes one.
        // Without it the completion list reshuffles between launches.
        let snippets = try parse("""
        {
            "charlie": { "prefix": "c", "body": "…" },
            "alpha": { "prefix": "a", "body": "…" },
            "bravo": { "prefix": "b", "body": "…" }
        }
        """)

        #expect(snippets.map(\.name) == ["alpha", "bravo", "charlie"])
    }

    // MARK: - JSONC

    @Test("a JSONC snippets file parses")
    func jsoncParses() throws {
        // Three of 113 real files are JSONC. A strict-only reader drops them
        // silently, which is why this goes through `JSONCPreprocessor`.
        let snippets = try parse("""
        {
            // The only snippet anyone uses
            "Log": {
                "prefix": "log",
                "body": "console.log($1)", /* trailing comma below is legal here */
            },
        }
        """)

        #expect(snippets.map(\.prefix) == ["log"])
    }

    // MARK: - Empty versus broken

    @Test("an empty object is an empty import, not a failure")
    func emptyObjectIsEmpty() throws {
        #expect(try parse("{}").isEmpty)
    }

    @Test("a root that is not an object throws")
    func rootArrayThrows() {
        #expect(throws: SnippetFileParseError.notAnObject) {
            try SnippetFile.parse(Data("[]".utf8), extensionIdentifier: Self.identifier)
        }
    }

    @Test("the parse failure describes itself to a person")
    func parseFailureDescribesItself() {
        // `SnippetStore` records `localizedDescription` for every error a read
        // can throw, and an `Error` with no `LocalizedError` conformance gets
        // Foundation's "The operation couldn't be completed. (… error 0.)" —
        // which names nothing the user could fix.
        let description = SnippetFileParseError.notAnObject.localizedDescription
        #expect(!description.isEmpty)
        #expect(!description.contains("couldn't be completed"))
        #expect(description.contains("JSON object"))
    }

    /// The `abusaidm.html-snippets` shape: a file that is mostly commented-out
    /// snippets and does not parse even after the comments are stripped.
    /// Shortened to the shape — a dangling comma and an unclosed object are
    /// what remains once the comment goes.
    @Test("a file that is malformed after comment stripping throws")
    func malformedAfterStrippingThrows() {
        let text = """
        {
            // "Old": { "prefix": "old", "body": "…" },
            "Current": { "prefix": "cur", "body": "…"
        """

        #expect(throws: (any Error).self) {
            try SnippetFile.parse(Data(text.utf8), extensionIdentifier: Self.identifier)
        }
    }

    /// The `snowflake.snowflake-vsc` shape: a `.code-snippets` file that is one
    /// comment and nothing else, because the extension writes its real
    /// snippets from code at runtime. Reporting it is the whole point — an
    /// empty array here would say "this extension contributes no snippets",
    /// which is not true and not actionable.
    @Test("a file that is only a comment throws rather than importing nothing")
    func commentOnlyFileThrows() {
        let text = "// This file is managed by the snippets.middleware so any changes to it will be overwritten"

        #expect(throws: (any Error).self) {
            try SnippetFile.parse(Data(text.utf8), extensionIdentifier: Self.identifier)
        }
    }

    // MARK: - Reading from disk

    @Test("parsing from a URL reads the file")
    func parseFromURL() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnippetFileTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("swift.json")
        try #"{"Log": {"prefix": "log", "body": "print($1)"}}"#.write(to: url, atomically: true, encoding: .utf8)

        let snippets = try SnippetFile.parse(contentsOf: url, extensionIdentifier: Self.identifier)
        #expect(snippets.map(\.prefix) == ["log"])
    }

    @Test("parsing a file that is not there throws")
    func parseMissingFileThrows() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnippetFileTests-absent-\(UUID().uuidString).json")

        #expect(throws: (any Error).self) {
            try SnippetFile.parse(contentsOf: url, extensionIdentifier: Self.identifier)
        }
    }
}

/// The conversion that lets extension snippets travel the completion path the
/// editor already has.
@Suite
struct ExtensionSnippetTests {

    private func snippet(description: String? = "Logs a value", scopes: [String] = []) -> ExtensionSnippet {
        ExtensionSnippet(
            name: "Log",
            prefix: "log",
            body: "console.log(${1:value})$0",
            description: description,
            scopes: scopes,
            extensionIdentifier: "acme.snippets"
        )
    }

    @Test("a snippet becomes a snippet-formatted completion item")
    func completionItemMapping() {
        let item = snippet().completionItem()

        #expect(item.label == "log")
        #expect(item.kind == .snippet)
        #expect(item.detail == "Logs a value")
        #expect(item.filterText == "log")
        #expect(item.insertText == "console.log(${1:value})$0")
        // The whole point: `.snippet` is what routes this through
        // `LSPCompletionDelegate.plainText(ofSnippet:)` instead of being
        // inserted with its markup intact.
        #expect(item.insertTextFormat == .snippet)
        // No `textEdit`: a snippet file has no document range to name, and the
        // delegate's fallback chain is what should apply.
        #expect(item.textEdit == nil)
    }

    @Test("the name is the detail when there is no description")
    func detailFallsBackToName() {
        #expect(snippet(description: nil).completionItem().detail == "Log")
    }

    @Test("the body parses as the LSP snippet it claims to be")
    func bodyParsesAsAnLSPSnippet() {
        // The reason no snippet-body parser was written: the vendored one
        // already understands this grammar, and the editor already calls it.
        var elements: [String] = []
        Snippet(value: snippet().body).enumerateElements { element in
            switch element {
            case .text(let text): elements.append(text)
            case .placeholder(_, let text): elements.append(text)
            default: break
            }
        }

        #expect(elements.joined() == "console.log(value)")
    }

    @Test("a snippet with no scope applies to every language its file covers")
    func unscopedApplies() {
        #expect(snippet().applies(to: "swift"))
    }

    @Test("a scope narrows, and only narrows")
    func scopeNarrows() {
        let scoped = snippet(scopes: ["typescript", "javascript"])
        #expect(scoped.applies(to: "typescript"))
        #expect(!scoped.applies(to: "swift"))
    }
}
