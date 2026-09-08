//
//  LanguageServerClientCapabilitiesTests.swift
//  AgenticToolkit
//

import Foundation
import LanguageServerProtocol
import Testing
@testable import AgenticToolkitLanguage

/// What the handshake promises a real server.
///
/// A declared capability is a promise to render what the server sends. The two
/// asserted here are the ones a wrong answer makes *silently* wrong rather than
/// broken: a server that believes we handle multiline tokens paints the wrong
/// characters, and one that believes we have no syntax highlighting of our own
/// sends a token for every lexeme in the file.
@Suite("Language server client capabilities")
struct LanguageServerClientCapabilitiesTests {

    @Test("semantic tokens are declared single-line, and as an augmentation of our own highlighting")
    func semanticTokenCapabilitiesMatchWhatWeActuallyRender() throws {
        let semanticTokens = try #require(
            LanguageServerSession.clientCapabilities.textDocument?.semanticTokens
        )

        // False, not the library's `true` default: `TokenRepresentation`'s
        // decoder ends every token on the line it started on.
        #expect(semanticTokens.multilineTokenSupport == false)

        // True, and deliberately still the default: tree-sitter is underneath.
        #expect(semanticTokens.augmentsSyntaxTokens == true)
    }
}
