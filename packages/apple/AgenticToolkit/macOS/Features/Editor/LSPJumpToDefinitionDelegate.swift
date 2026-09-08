//
//  LSPJumpToDefinitionDelegate.swift
//  AgenticToolkit
//

import AgenticToolkitLanguage
import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol

/// Answers `CodeEditSourceEditor`'s cmd-click with `textDocument/definition`.
///
/// One per open document, for the same reason as `LSPCompletionDelegate`: every
/// offset↔`Position` conversion is resolved against one specific
/// `TextDocument`, and `FileEditorState.Slot` owns it because `SourceEditor`
/// holds `jumpToDefinitionDelegate` weakly.
///
/// This type knows nothing about a file browser. Opening a cross-file target is
/// an injected closure, supplied by the one view that already holds both the
/// selection and the editor.
@MainActor
final class LSPJumpToDefinitionDelegate: JumpToDefinitionDelegate {

    private let document: TextDocument
    private let registry: LanguageServerRegistry
    private let openFile: @MainActor (URL) -> Void

    init(
        document: TextDocument,
        registry: LanguageServerRegistry,
        openFile: @escaping @MainActor (URL) -> Void
    ) {
        self.document = document
        self.registry = registry
        self.openFile = openFile
    }

    // MARK: - JumpToDefinitionDelegate

    func queryLinks(forRange range: NSRange, textView: TextViewController) async -> [JumpToDefinitionLink]? {
        // Read before the first await, so the request describes one consistent
        // version of the document.
        guard let session = registry.session(forLanguageId: document.languageId) else { return nil }
        let uri = document.uri
        let position = document.position(forUTF16Offset: range.location)

        guard let capabilities = await session.capabilities(),
              Self.declaresDefinitionProvider(capabilities) else {
            return nil
        }

        let response: DefinitionResponse
        do {
            response = try await session.definition(
                TextDocumentPositionParams(uri: uri, position: position)
            )
        } catch {
            return nil
        }

        // `DefinitionResponse` is `ThreeTypeOption<Location, [Location],
        // [LocationLink]>?` and offers no convenience unwrapper, so all three
        // shapes are handled here. A `LocationLink` carries two ranges;
        // `targetSelectionRange` is the identifier itself rather than the whole
        // declaration body, which is where a jump should land.
        guard let response else { return nil }
        let targets: [(uri: DocumentUri, range: LSPRange)]
        switch response {
        case .optionA(let location):
            targets = [(location.uri, location.range)]
        case .optionB(let locations):
            targets = locations.map { ($0.uri, $0.range) }
        case .optionC(let links):
            targets = links.map { ($0.targetUri, $0.targetSelectionRange) }
        }

        return targets.compactMap { makeLink(targetUri: $0.uri, targetRange: $0.range) }
    }

    /// Declared `nonisolated` because `JumpToDefinitionDelegate` is **not**
    /// `@MainActor` and this requirement is synchronous — a main-actor method
    /// cannot witness it. `assumeIsolated` rather than a `Task` hop because the
    /// only caller is `JumpToDefinitionModel`, a `@MainActor final class` that
    /// calls this from inside its own main-actor `Task`
    /// (`JumpToDefinitionModel.performJump`), so the assertion is one the call
    /// graph already guarantees — and hopping would let the jump land after the
    /// user has moved on.
    nonisolated func openLink(link: JumpToDefinitionLink) {
        // Only ever called for a cross-file target: `performJump` moves the
        // selection itself when `link.url` is `nil`.
        guard let url = link.url else { return }
        MainActor.assumeIsolated {
            openFile(url)
        }
    }

    // MARK: - Links

    /// A server may advertise `definitionProvider` as a bare `false`, which is
    /// a declaration that it does *not* provide definitions — not the same as
    /// omitting the key.
    private static func declaresDefinitionProvider(_ capabilities: ServerCapabilities) -> Bool {
        switch capabilities.definitionProvider {
        case .optionA(let isSupported): return isSupported
        case .optionB: return true
        case nil: return false
        }
    }

    private func makeLink(targetUri: DocumentUri, targetRange: LSPRange) -> JumpToDefinitionLink? {
        let isSameDocument = Self.isSameFile(targetUri, as: document.uri)

        if isSameDocument {
            // `url == nil` is the same-file switch `JumpToDefinitionModel`
            // branches on, and `targetRange` is then the range it selects — so
            // it must be built with `CursorPosition(range:)`. A
            // `CursorPosition(line:column:)` leaves `.range` at
            // `NSRange.notFound`, and every same-file jump would silently do
            // nothing.
            let nsRange = document.nsRange(for: targetRange)
            return JumpToDefinitionLink(
                url: nil,
                targetRange: CursorPosition(range: nsRange),
                typeName: sourceLine(around: nsRange) ?? document.uri,
                sourcePreview: sourceLine(around: nsRange) ?? "",
                documentation: nil
            )
        }

        guard let url = URL(string: targetUri), url.isFileURL else { return nil }
        // A range inside another file cannot be resolved against this document's
        // line index, and nothing reads it on the cross-file path — `performJump`
        // hands the link straight to `openLink(link:)`. An empty range at the
        // start of the file is the honest placeholder.
        return JumpToDefinitionLink(
            url: url,
            targetRange: CursorPosition(range: NSRange(location: 0, length: 0)),
            typeName: url.lastPathComponent,
            sourcePreview: "",
            documentation: nil
        )
    }

    /// The trimmed source line `nsRange` starts on, used as the label and
    /// preview for a same-file target.
    private func sourceLine(around nsRange: NSRange) -> String? {
        let text = document.text as NSString
        guard nsRange.location <= text.length else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: nsRange.location, length: 0))
        let line = text.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : line
    }

    /// URI equality by resolved file path rather than by string.
    ///
    /// A server echoes back a URI it built itself, so its percent-encoding and
    /// its symlink resolution need not match the one this client sent — and a
    /// mismatch here is not cosmetic: it turns a same-file jump into a
    /// cross-file one, which reopens the file the user is already in.
    private static func isSameFile(_ lhs: DocumentUri, as rhs: DocumentUri) -> Bool {
        if lhs == rhs { return true }
        guard let left = URL(string: lhs), left.isFileURL,
              let right = URL(string: rhs), right.isFileURL else {
            return false
        }
        return left.standardizedFileURL.resolvingSymlinksInPath().path
            == right.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
