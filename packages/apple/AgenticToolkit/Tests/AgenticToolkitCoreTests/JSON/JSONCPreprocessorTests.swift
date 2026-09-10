import Foundation
import Testing
@testable import AgenticToolkitCore

/// The JSONC reader, tested directly rather than through a theme.
///
/// It was a private half of `VSCodeThemeImporter` until a second framework
/// needed it, and `VSCodeThemeImporterTests` only ever reached it through a
/// complete colour theme — so the cases that say what the *scanner* does (a
/// `//` inside a string, an escaped quote, a UTF-16 payload) had to be
/// expressed as whole themes or not at all. They are expressed here as the
/// documents they are about.
@Suite
struct JSONCPreprocessorTests {

    // MARK: - Helpers

    /// The object graph `text` parses to, as a dictionary, or a failed
    /// expectation. Every case below is an object at the root.
    private func object(_ text: String) throws -> [String: Any] {
        let parsed = try JSONCPreprocessor.jsonObject(from: Data(text.utf8))
        return try #require(parsed as? [String: Any])
    }

    // MARK: - Comments

    @Test("a line comment is removed")
    func lineComment() throws {
        let root = try object("""
        {
            // the answer
            "a": 1
        }
        """)
        #expect(root["a"] as? Int == 1)
    }

    @Test("a block comment is removed, including one spanning lines")
    func blockComment() throws {
        let root = try object("""
        {
            /* the answer,
               at length */
            "a": 1, /* and inline */ "b": 2
        }
        """)
        #expect(root["a"] as? Int == 1)
        #expect(root["b"] as? Int == 2)
    }

    @Test("an unterminated block comment swallows the rest of the document")
    func unterminatedBlockComment() {
        // Documenting the scanner's actual behaviour rather than wishing for
        // recovery: the run-to-end loop consumes everything after `/*`, so the
        // document is truncated and fails to parse. That is the honest outcome
        // for a file whose author left a comment open.
        #expect(throws: (any Error).self) {
            try JSONCPreprocessor.jsonObject(from: Data(#"{"a": 1 /* oops }"#.utf8))
        }
    }

    // MARK: - String-awareness

    @Test("a // inside a string literal is left alone")
    func slashesInsideStringSurvive() throws {
        // The regression this scanner exists for: `$schema` values are URLs,
        // and a comment stripper without string state truncates the document
        // at the first one.
        let root = try object("""
        {
            "$schema": "https://example.com/schema.json"
        }
        """)
        #expect(root["$schema"] as? String == "https://example.com/schema.json")
    }

    @Test("an escaped quote does not end the string it is inside")
    func escapedQuoteInsideString() throws {
        let root = try object(#"{"a": "say \"hi\" // not a comment"}"#)
        #expect(root["a"] as? String == #"say "hi" // not a comment"#)
    }

    @Test("a comma inside a string is not a trailing comma")
    func commaInsideString() throws {
        // The comma scanner blanks characters in place, so a false positive
        // here would silently rewrite the *value*, not just the punctuation.
        let root = try object(#"{"a": "one, two", "b": 2}"#)
        #expect(root["a"] as? String == "one, two")
        #expect(root["b"] as? Int == 2)
    }

    @Test("a trailing backslash inside a string does not escape the closing quote")
    func escapedBackslashEndsTheString() throws {
        let root = try object(#"{"a": "back\\", "b": 2}"#)
        #expect(root["a"] as? String == #"back\"#)
        #expect(root["b"] as? Int == 2)
    }

    // MARK: - Trailing commas

    @Test("a trailing comma before } is dropped")
    func trailingCommaBeforeBrace() throws {
        let root = try object("""
        {
            "a": 1,
        }
        """)
        #expect(root["a"] as? Int == 1)
    }

    @Test("a trailing comma before ] is dropped")
    func trailingCommaBeforeBracket() throws {
        let root = try object("""
        {
            "a": [1, 2, ]
        }
        """)
        #expect(root["a"] as? [Int] == [1, 2])
    }

    @Test("a trailing comma left behind by a removed comment is dropped")
    func trailingCommaAfterComment() throws {
        // Comment removal runs first precisely so this shape parses: the comma
        // is only *trailing* once the comment between it and the bracket is
        // gone.
        let root = try object("""
        {
            "a": [1, /* stale */]
        }
        """)
        #expect(root["a"] as? [Int] == [1])
    }

    // MARK: - Encodings

    @Test("a UTF-16 payload is transcoded before stripping")
    func utf16Payload() throws {
        let text = """
        {
            // a comment, which is what forces the transcoding
            "a": 1
        }
        """
        let data = try #require(text.data(using: .utf16))
        let root = try #require(try JSONCPreprocessor.jsonObject(from: data) as? [String: Any])
        #expect(root["a"] as? Int == 1)
    }

    @Test("a UTF-8 BOM is skipped")
    func utf8BOM() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(#"{"a": 1}"#.utf8))
        let root = try #require(try JSONCPreprocessor.jsonObject(from: data) as? [String: Any])
        #expect(root["a"] as? Int == 1)
    }

    // MARK: - Pass-through and failure

    @Test("strict JSON passes through unchanged")
    func strictJSONUnchanged() {
        let text = #"{"a":1,"b":["x","y"],"c":{"d":true},"e":null}"#
        #expect(JSONCPreprocessor.strip(text) == text)
    }

    @Test("a document that is malformed after stripping throws")
    func malformedThrows() {
        // Nothing is repaired and nothing is invented: the caller learns the
        // file is broken rather than receiving an empty document.
        #expect(throws: (any Error).self) {
            try JSONCPreprocessor.jsonObject(from: Data(#"{"a": 1"#.utf8))
        }
    }

    @Test("a document that is only a comment throws")
    func commentOnlyThrows() {
        #expect(throws: (any Error).self) {
            try JSONCPreprocessor.jsonObject(from: Data("// nothing here\n".utf8))
        }
    }
}
