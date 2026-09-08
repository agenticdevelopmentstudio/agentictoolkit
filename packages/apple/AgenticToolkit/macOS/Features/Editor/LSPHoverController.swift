//
//  LSPHoverController.swift
//  AgenticToolkit
//

import AgenticToolkitLanguage
import AppKit
import CodeEditTextView
import Foundation
import LanguageServerProtocol

/// Answers "what is this?" for the thing under the pointer: the diagnostic on
/// it if there is one, otherwise `textDocument/hover` from the language server.
///
/// One per open document, for the same reason as `LSPCompletionDelegate` and
/// `LSPJumpToDefinitionDelegate`: every offset↔`Position` conversion is
/// resolved against one specific `TextDocument`.
///
/// **Diagnostics win, and cost nothing.** A point inside a squiggle shows the
/// server's complaint and issues no hover request at all. That is not an
/// optimisation: a user pointing at a red underline is asking about the red
/// underline, and answering with the type signature of the identifier it
/// happens to sit on is answering a question nobody asked.
@MainActor
final class LSPHoverController {

    /// What the controller decided to show, recorded at the publish site.
    ///
    /// The card itself needs a window — `NSPopover.show` raises without one —
    /// so this, and not the popover's `isShown`, is the honest record of what
    /// the controller concluded. It is also what makes the generation guard
    /// testable off screen.
    struct PresentedContent: Equatable {

        enum Origin: Equatable {
            case diagnostic
            case server
        }

        let text: String
        let origin: Origin
    }

    /// Text pulled out of a `Hover`, and whether it should be read as markdown.
    struct HoverText: Equatable {
        let text: String
        let isMarkdown: Bool
    }

    /// Long enough that sweeping the pointer across a line asks nothing, short
    /// enough that stopping on a word feels answered rather than delayed.
    static let defaultDelay: Duration = .milliseconds(300)

    private let document: TextDocument
    private let registry: LanguageServerRegistry
    private let card: HoverCardPopoverController
    private let delay: Duration

    /// The view the card points at and whose layout manager resolves points to
    /// offsets. Weak: the text view outlives nothing here and owns the overlay
    /// that drives this controller.
    weak var textView: TextView?

    /// The diagnostics currently drawn under this document, in text-storage
    /// coordinates. Set by `LSPEditorAnnotationCoordinator` from the same array
    /// it gives the overlay, so the card can never disagree with the squiggle
    /// it is explaining.
    var marks: [DiagnosticMark] = []

    private(set) var presented: PresentedContent?

    /// The span the current card explains. While the pointer stays inside it,
    /// nothing is re-requested and nothing is dismissed — otherwise moving one
    /// character within a word would flicker the card.
    private var presentedRange: NSRange?

    /// Monotonic. Every asynchronous publish carries the value this held when
    /// its work started, and publishes only if it still holds it.
    private var generation = 0
    private var pending: Task<Void, Never>?

    init(
        document: TextDocument,
        registry: LanguageServerRegistry,
        card: HoverCardPopoverController = HoverCardPopoverController(),
        delay: Duration = LSPHoverController.defaultDelay
    ) {
        self.document = document
        self.registry = registry
        self.card = card
        self.delay = delay
        card.onDismiss = { [weak self] in
            // The user clicked the card away. Forget what was shown, or the
            // next move inside the same token would decide it is already
            // showing and never re-open it.
            self?.presented = nil
            self?.presentedRange = nil
        }
    }

    // MARK: - Pointer

    /// The pointer moved to `point`, in the **text view's** coordinate space.
    func pointerMoved(to point: NSPoint) {
        // Minted synchronously, at the top, before anything here can suspend.
        // Every later step compares against it; nothing read below is published
        // after an await without that comparison first.
        let token = advanceGeneration()
        pending?.cancel()
        pending = nil

        guard let textView, let offset = textView.layoutManager?.textOffsetAtPoint(point) else {
            dismiss()
            return
        }

        // Still on the thing the card is already explaining: leave it alone.
        // The generation has advanced, so any request in flight for a previous
        // token is now dead, which is correct — this one is answered.
        if isInsidePresentedRange(offset) { return }

        // The pointer left the token, so whatever is on screen is now about
        // something the user is no longer pointing at.
        dismiss()

        pending = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.present(offset: offset, point: point, token: token)
        }
    }

    /// Cancels anything in flight and takes the card down.
    ///
    /// Called when the text changes, the selection changes, the editor
    /// disappears, or the coordinator is destroyed. Advancing the generation is
    /// the whole point: a response already on its way back cannot be published
    /// against text that has since moved.
    func invalidate() {
        advanceGeneration()
        pending?.cancel()
        pending = nil
        dismiss()
    }

    func dismiss() {
        presented = nil
        presentedRange = nil
        card.dismiss()
    }

    // MARK: - Deciding what to show

    private func present(offset: Int, point: NSPoint, token: Int) async {
        guard token == generation else { return }

        // Diagnostics first, from memory, with no request and no suspension —
        // see the note on this type.
        let overlapping = marks
            .filter { $0.contains(offset) }
            .sorted { Self.rank($0.severity) < Self.rank($1.severity) }
        if let closest = overlapping.first {
            let text = overlapping.map(\.message).joined(separator: "\n\n")
            show(
                PresentedContent(text: text, origin: .diagnostic),
                content: .plainText(text),
                range: closest.range,
                fallbackPoint: point
            )
            return
        }

        // Read before the first await, so the request describes one consistent
        // version of the document — the same discipline as
        // `LSPJumpToDefinitionDelegate.queryLinks`. Neither of these is
        // *published* after the await; they are what the request is made of,
        // and the request is abandoned if the token has moved on.
        guard let session = registry.session(forLanguageId: document.languageId) else { return }
        let uri = document.uri
        let position = document.position(forUTF16Offset: offset)

        guard let capabilities = await session.capabilities(),
              Self.declaresHoverProvider(capabilities) else {
            return
        }
        guard token == generation else { return }

        let response: HoverResponse
        do {
            response = try await session.hover(TextDocumentPositionParams(uri: uri, position: position))
        } catch {
            return
        }

        guard token == generation, let hover = response else { return }

        let hoverText = Self.hoverText(from: hover.contents)
        guard !hoverText.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // The server's own range is the better anchor and the better "still
        // inside" test: it is the extent of the symbol it answered about, which
        // is what the user thinks they are pointing at. Without one, the card
        // is pinned to the character under the pointer.
        let range = hover.range.map { document.nsRange(for: $0) } ?? NSRange(location: offset, length: 0)
        show(
            PresentedContent(text: hoverText.text, origin: .server),
            content: hoverText.isMarkdown ? .markdown(hoverText.text) : .plainText(hoverText.text),
            range: range,
            fallbackPoint: point
        )
    }

    private func show(
        _ presented: PresentedContent,
        content: HoverCardContent,
        range: NSRange,
        fallbackPoint: NSPoint
    ) {
        self.presented = presented
        presentedRange = range
        guard let textView else { return }
        card.show(
            content,
            relativeTo: anchorRect(for: range, at: fallbackPoint, in: textView),
            of: textView,
            // Flipped coordinates: `.maxY` is the edge below the text, which is
            // where a card about the line above it belongs.
            preferredEdge: .maxY
        )
    }

    /// The rect the card points at: the first line fragment of `range` when the
    /// layout manager can measure one, and a hairline at the pointer when it
    /// cannot — which is the case for an empty range, since the layout manager
    /// discards zero-width fragments.
    private func anchorRect(for range: NSRange, at point: NSPoint, in textView: TextView) -> NSRect {
        if let rect = textView.layoutManager?.rectsFor(range: range).first {
            return rect
        }
        return NSRect(x: point.x, y: point.y, width: 1, height: 1)
    }

    private func isInsidePresentedRange(_ offset: Int) -> Bool {
        guard let presentedRange else { return false }
        // `max(length, 1)`: an empty range still occupies the character the
        // pointer is on, exactly as `DiagnosticMark.contains(_:)` treats it.
        return offset >= presentedRange.location
            && offset < presentedRange.location + max(presentedRange.length, 1)
    }

    /// Advances the generation and returns the new value. Every caller either
    /// uses what it returns or is deliberately discarding it to cancel; there
    /// is no third case, which is why the result is discardable.
    @discardableResult
    private func advanceGeneration() -> Int {
        generation &+= 1
        return generation
    }

    // MARK: - Reading the server's answer

    /// Flattens all three shapes `Hover.contents` can take.
    ///
    /// `MarkedString` is the deprecated pre-3.15 form and carries no markup
    /// kind, so it is read as plain text — rendering it as markdown would turn
    /// a C pointer type into emphasis. Only `MarkupContent` says which it is,
    /// and only when it says `.markdown` is markdown assumed.
    static func hoverText(from contents: ThreeTypeOption<MarkedString, [MarkedString], MarkupContent>) -> HoverText {
        switch contents {
        case .optionA(let marked):
            HoverText(text: marked.value, isMarkdown: false)
        case .optionB(let marked):
            HoverText(text: marked.map(\.value).joined(separator: "\n\n"), isMarkdown: false)
        case .optionC(let markup):
            HoverText(text: markup.value, isMarkdown: markup.kind == .markdown)
        }
    }

    /// A server may advertise `hoverProvider` as a bare `false`, which is a
    /// declaration that it does *not* provide hovers — not the same as omitting
    /// the key. Same shape as
    /// `LSPJumpToDefinitionDelegate.declaresDefinitionProvider`.
    static func declaresHoverProvider(_ capabilities: ServerCapabilities) -> Bool {
        switch capabilities.hoverProvider {
        case .optionA(let isSupported): isSupported
        case .optionB: true
        case nil: false
        }
    }

    /// Most severe first. A missing severity ranks with `.error`, for the
    /// reason given on `DiagnosticMark.severity`.
    private static func rank(_ severity: DiagnosticSeverity?) -> Int {
        switch severity {
        case .error, nil: 0
        case .warning: 1
        case .information: 2
        case .hint: 3
        }
    }
}
