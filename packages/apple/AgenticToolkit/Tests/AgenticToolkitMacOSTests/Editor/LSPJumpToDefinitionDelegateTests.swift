//
//  LSPJumpToDefinitionDelegateTests.swift
//  AgenticToolkit
//

import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import Testing
@testable import AgenticToolkitLanguage
@testable import AgenticToolkitMacOS

/// Cmd-click, answered by `textDocument/definition`.
///
/// The two things that can quietly break here are the response shapes — LSP
/// allows three, and a server may use any of them — and the same-file switch,
/// which is signalled by `url == nil` and read through `targetRange.range`.
@Suite("LSPJumpToDefinitionDelegate")
@MainActor
struct LSPJumpToDefinitionDelegateTests {

    // MARK: - Fixtures

    private static let sampleText = "let alpha = 1\nprint(alpha)"
    private static let documentURI: DocumentUri = "file:///Workspace/Sample.swift"
    private static let otherURI: DocumentUri = "file:///Workspace/Other.swift"

    /// `alpha` in the declaration on line 0 — offsets 4..<9.
    private static let declarationRange = LSPRange(
        start: Position(line: 0, character: 4),
        end: Position(line: 0, character: 9)
    )

    /// The whole declaration line, which is what a `LocationLink` puts in
    /// `targetRange` while `targetSelectionRange` names the identifier.
    private static let declarationLineRange = LSPRange(
        start: Position(line: 0, character: 0),
        end: Position(line: 0, character: 13)
    )

    /// The use on line 1, which is where the cmd-click lands.
    private static let clickedRange = NSRange(location: 20, length: 5)

    private func makeDelegate(
        fixture: LSPEditorFixture,
        document: TextDocument,
        recorder: OpenedFileRecorder = OpenedFileRecorder()
    ) -> LSPJumpToDefinitionDelegate {
        LSPJumpToDefinitionDelegate(
            document: document,
            registry: fixture.registry,
            openFile: recorder.open
        )
    }

    private func queryLinks(
        behavior: FakeEditorSessionBehavior,
        registersConfiguration: Bool = true
    ) async throws -> (links: [JumpToDefinitionLink]?, document: TextDocument, log: EditorSessionLog) {
        let fixture = LSPEditorFixture(
            behavior: behavior,
            registersConfiguration: registersConfiguration
        )
        if registersConfiguration {
            _ = try await fixture.startedSession()
        }
        let document = makeEditorDocument(uri: Self.documentURI, text: Self.sampleText)
        let delegate = makeDelegate(fixture: fixture, document: document)
        let controller = makeEditorTextViewController(text: Self.sampleText)

        let links = await delegate.queryLinks(forRange: Self.clickedRange, textView: controller)
        return (links, document, fixture.log)
    }

    // MARK: - 14. Gating and the three response shapes

    @Test("a query with no server for the document's language returns nil")
    func noSessionReturnsNil() async throws {
        let result = try await queryLinks(
            behavior: FakeEditorSessionBehavior(),
            registersConfiguration: false
        )

        #expect(result.links == nil)
        #expect(result.log.events.isEmpty)
    }

    @Test("a query to a server that advertises no definitionProvider returns nil")
    func noDefinitionProviderReturnsNil() async throws {
        // Completion but not definitions — a real combination, and one that
        // must not be read as "definitions are fine".
        let result = try await queryLinks(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(),
                definitionResponse: .optionA(Location(uri: Self.documentURI, range: Self.declarationRange))
            )
        )

        #expect(result.links == nil)
        #expect(!result.log.events.contains("definition"))
    }

    @Test("a server that advertises definitionProvider as a bare false is taken at its word")
    func explicitFalseDefinitionProviderReturnsNil() async throws {
        // `false` is a declaration that the server does *not* provide
        // definitions — not the same as omitting the key, and not the same as
        // "present, therefore supported".
        let result = try await queryLinks(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeDefiningCapabilities(provides: false),
                definitionResponse: .optionA(Location(uri: Self.documentURI, range: Self.declarationRange))
            )
        )

        #expect(result.links == nil)
        #expect(!result.log.events.contains("definition"))
    }

    @Test("a single Location becomes one link at that range")
    func convertsSingleLocation() async throws {
        let result = try await queryLinks(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeDefiningCapabilities(),
                definitionResponse: .optionA(Location(uri: Self.documentURI, range: Self.declarationRange))
            )
        )

        let links = try #require(result.links)
        #expect(links.count == 1)
        let link = try #require(links.first)
        #expect(link.targetRange.range == result.document.nsRange(for: Self.declarationRange))
    }

    @Test("an array of Locations becomes one link each, in order")
    func convertsLocationArray() async throws {
        let result = try await queryLinks(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeDefiningCapabilities(),
                definitionResponse: .optionB([
                    Location(uri: Self.documentURI, range: Self.declarationRange),
                    Location(uri: Self.otherURI, range: Self.declarationRange)
                ])
            )
        )

        let links = try #require(result.links)
        #expect(links.count == 2)
        #expect(links.map(\.url) == [nil, URL(string: Self.otherURI)])
    }

    @Test("a LocationLink jumps to its targetSelectionRange, not its targetRange")
    func convertsLocationLink() async throws {
        let result = try await queryLinks(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeDefiningCapabilities(),
                definitionResponse: .optionC([LocationLink(
                    targetUri: Self.documentURI,
                    targetRange: Self.declarationLineRange,
                    targetSelectionRange: Self.declarationRange
                )])
            )
        )

        let links = try #require(result.links)
        #expect(links.count == 1)
        let link = try #require(links.first)
        // `targetRange` is the whole declaration body; landing there would put
        // the caret at the start of the line rather than on the symbol.
        #expect(link.targetRange.range == result.document.nsRange(for: Self.declarationRange))
        #expect(link.targetRange.range != result.document.nsRange(for: Self.declarationLineRange))
    }

    // MARK: - 17. Same file vs. another file

    @Test("a target in this document has no url and a real range; one elsewhere has the file's url")
    func distinguishesSameFileFromCrossFile() async throws {
        let result = try await queryLinks(
            behavior: FakeEditorSessionBehavior(
                capabilities: makeDefiningCapabilities(),
                definitionResponse: .optionB([
                    Location(uri: Self.documentURI, range: Self.declarationRange),
                    Location(uri: Self.otherURI, range: Self.declarationRange)
                ])
            )
        )

        let links = try #require(result.links)
        let sameFile = try #require(links.first)
        let crossFile = try #require(links.last)

        // `url == nil` is the switch `JumpToDefinitionModel` branches on to
        // move the selection itself rather than asking us to open a file.
        #expect(sameFile.url == nil)
        // And on that branch the range is what it selects. `CursorPosition`
        // built from a line/column leaves `.range` at `NSRange.notFound`, and
        // every same-file jump would silently do nothing.
        #expect(sameFile.targetRange.range != NSRange.notFound)
        #expect(sameFile.targetRange.range == result.document.nsRange(for: Self.declarationRange))

        #expect(crossFile.url == URL(string: Self.otherURI))
        #expect(crossFile.targetRange.range != NSRange.notFound)
    }

    // MARK: - 18. Opening a cross-file link

    @Test("opening a cross-file link calls the injected openFile once, with the link's url")
    func openLinkCallsTheInjectedClosure() async throws {
        let fixture = LSPEditorFixture()
        let document = makeEditorDocument(uri: Self.documentURI, text: Self.sampleText)
        let recorder = OpenedFileRecorder()
        let delegate = makeDelegate(fixture: fixture, document: document, recorder: recorder)
        let url = try #require(URL(string: Self.otherURI))

        delegate.openLink(link: JumpToDefinitionLink(
            url: url,
            targetRange: CursorPosition(range: NSRange(location: 0, length: 0)),
            typeName: "Other.swift",
            sourcePreview: "",
            documentation: nil
        ))

        #expect(recorder.urls == [url])
    }

    @Test("opening a same-file link does nothing: the package moves the caret itself")
    func openLinkIgnoresSameFileLink() async throws {
        let fixture = LSPEditorFixture()
        let document = makeEditorDocument(uri: Self.documentURI, text: Self.sampleText)
        let recorder = OpenedFileRecorder()
        let delegate = makeDelegate(fixture: fixture, document: document, recorder: recorder)

        delegate.openLink(link: JumpToDefinitionLink(
            url: nil,
            targetRange: CursorPosition(range: NSRange(location: 4, length: 5)),
            typeName: "alpha",
            sourcePreview: "let alpha = 1",
            documentation: nil
        ))

        // Reopening the file the user is already in would scroll them away from
        // the jump the package just performed.
        #expect(recorder.urls.isEmpty)
    }
}
