//
//  LSPEditorAnnotationTests.swift
//  AgenticToolkit
//

import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol
import Testing
@testable import AgenticToolkitCore
@testable import AgenticToolkitCoreMacOS
@testable import AgenticToolkitLanguage
@testable import AgenticToolkitMacOS

/// The squiggles, the hover card, and the coordinator that installs both.
///
/// `.serialized` because every test here drives a real `TextViewController`
/// with a real layout manager and, in half of them, a real `NSPopover`. AppKit
/// object graphs built on several threads at once are a source of failures that
/// have nothing to do with what is being asserted.
@Suite("LSP editor annotations", .serialized)
@MainActor
struct LSPEditorAnnotationTests {

    private static let pollSeconds: TimeInterval = 3

    // MARK: - Fixtures

    /// A controller whose text has actually been laid out.
    ///
    /// `loadView()` alone is not enough: `rectsFor(range:)` and
    /// `textOffsetAtPoint(_:)` both read line fragments, and fragments are
    /// typeset during layout. Without this every geometric assertion below
    /// would pass or fail on whether AppKit had got round to a layout pass.
    private func laidOutEditor(text: String) -> TextViewController {
        let frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let controller = makeEditorTextViewController(text: text)
        controller.view.frame = frame
        controller.textView.frame = frame
        controller.view.layoutSubtreeIfNeeded()
        _ = controller.textView.layoutManager.layoutLines(in: frame)
        return controller
    }

    private func makeOverlay(in controller: TextViewController) -> DiagnosticOverlayView {
        let overlay = DiagnosticOverlayView(textView: controller.textView)
        controller.textView.addSubview(overlay)
        return overlay
    }

    /// A point in the middle of the character at `offset`, in text-view space.
    private func point(forOffset offset: Int, in controller: TextViewController) -> NSPoint? {
        guard let rect = controller.textView.layoutManager
            .rectsFor(range: NSRange(location: offset, length: 1))
            .first
        else { return nil }
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    private func makeMark(
        location: Int,
        length: Int,
        severity: DiagnosticSeverity? = .error,
        message: String = "something is wrong"
    ) -> DiagnosticMark {
        DiagnosticMark(range: NSRange(location: location, length: length), severity: severity, message: message)
    }

    private func poll(
        seconds: TimeInterval = LSPEditorAnnotationTests.pollSeconds,
        until condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func pollAsync(
        seconds: TimeInterval = LSPEditorAnnotationTests.pollSeconds,
        until condition: () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    // MARK: - 9. One squiggle per line fragment

    /// What it catches: an overlay that draws one rect per *diagnostic* rather
    /// than one per line fragment, which underlines the bounding box of a
    /// multi-line error — including the whitespace to the left of it — instead
    /// of the text.
    @Test("a range produces one squiggle per rect, and more than one when it spans lines")
    func oneSquigglePerLineFragment() throws {
        let controller = laidOutEditor(text: "let first = 1\nlet second = 2\nlet third = 3\n")
        let overlay = makeOverlay(in: controller)

        overlay.marks = [makeMark(location: 4, length: 5)]
        let single = overlay.squiggles()
        #expect(single.count == 1)

        // Across the first line's end and into the second.
        overlay.marks = [makeMark(location: 4, length: 20)]
        let spanning = overlay.squiggles()
        #expect(spanning.count > 1)
        // On different lines, which is the property that matters: a single
        // bounding box over both lines would also be "more than one rect" if
        // the range happened to wrap.
        #expect(Set(spanning.map(\.rect.minY)).count > 1)
        #expect(spanning.allSatisfy { $0.severity == .error })
    }

    // MARK: - 10. Zero-length ranges

    /// What it catches: the layout manager discards zero-width fragments, so a
    /// diagnostic at a point — "expected '}' here", the single most common
    /// shape a parser emits — silently draws nothing at all.
    @Test("a zero-length range is still marked, at least one character wide")
    func zeroLengthRangeIsStillMarked() throws {
        let controller = laidOutEditor(text: "let value = 1\n")
        let overlay = makeOverlay(in: controller)

        overlay.marks = [makeMark(location: 4, length: 0)]
        let squiggles = overlay.squiggles()
        #expect(squiggles.count >= 1)

        let width = try #require(squiggles.first?.rect.width)
        #expect(width > 0)
        // One character of the editor's monospaced 12pt font is comfortably
        // wider than this; the point is that it is a character and not a hair.
        #expect(width >= 3)
    }

    // MARK: - 10b. Zero-length ranges at a line boundary

    /// The case test 10 misses, and the one that matters most.
    ///
    /// What it catches: widening an empty range *forwards* onto the `"\n"`.
    /// A line terminator typesets to zero advance, and the layout manager drops
    /// zero-width fragments before the overlay's minimum-width fixup can run —
    /// so nothing is drawn at all. "expected '}'" at the end of a line, and a
    /// diagnostic at column 0 of an empty line, are exactly this shape, and
    /// they are what a parser emits most often. Test 10 probes mid-line, where
    /// the forward widening lands on a real glyph and the hole is invisible.
    @Test("a zero-length diagnostic at a line boundary still draws")
    func zeroLengthRangeAtALineBoundaryIsStillMarked() throws {
        // "let value = 1\n\nlet other = 2\n"
        //   ^ 0                       offset 13 is line 0's terminator,
        //                             offset 14 is column 0 of the empty line.
        let controller = laidOutEditor(text: "let value = 1\n\nlet other = 2\n")
        let overlay = makeOverlay(in: controller)

        overlay.marks = [makeMark(location: 13, length: 0)]
        let endOfLine = overlay.squiggles()
        #expect(endOfLine.count >= 1)
        #expect((endOfLine.first?.rect.width ?? 0) >= 3)

        overlay.marks = [makeMark(location: 14, length: 0)]
        let emptyLine = overlay.squiggles()
        #expect(emptyLine.count >= 1)
        #expect((emptyLine.first?.rect.width ?? 0) >= 3)

        // Not the same mark drawn twice: the two sit on different lines.
        let endOfLineY = try #require(endOfLine.first?.rect.minY)
        let emptyLineY = try #require(emptyLine.first?.rect.minY)
        #expect(endOfLineY != emptyLineY)

        // A server that sends the same thing as a length-1 range over the line
        // break is the same problem wearing a different hat.
        overlay.marks = [makeMark(location: 13, length: 1)]
        #expect(overlay.squiggles().count >= 1)
    }

    /// The degenerate end of the same family: an empty document.
    ///
    /// What it catches: `documentLength == 0`, so neither widening direction
    /// applies and the measured range is empty. `expected declaration` on a new
    /// empty file would draw nothing.
    @Test("a diagnostic on an empty document still draws")
    func zeroLengthRangeOnAnEmptyDocumentIsStillMarked() {
        let controller = laidOutEditor(text: "")
        let overlay = makeOverlay(in: controller)

        overlay.marks = [makeMark(location: 0, length: 0, message: "expected declaration")]
        let squiggles = overlay.squiggles()
        #expect(squiggles.count == 1)
        #expect((squiggles.first?.rect.width ?? 0) >= 3)
        #expect((squiggles.first?.rect.height ?? 0) > 0)
    }

    // MARK: - 11. Out of the way

    /// What it catches: an overlay that swallows clicks. It covers the entire
    /// text view, so a single missing `hitTest` override costs the editor its
    /// selection, its caret placement and its cmd-click — with no error
    /// anywhere, just an editor that stops responding to the mouse.
    @Test("the overlay is transparent to the mouse everywhere inside it")
    func overlayNeverHitTests() {
        let controller = laidOutEditor(text: "let value = 1\n")
        let overlay = makeOverlay(in: controller)
        overlay.marks = [makeMark(location: 0, length: 13)]

        #expect(overlay.hitTest(NSPoint(x: 1, y: 1)) == nil)
        #expect(overlay.hitTest(NSPoint(x: overlay.bounds.midX, y: overlay.bounds.midY)) == nil)
    }

    // MARK: - 12. Severity colours

    /// What it catches: severities that all resolve to one colour (a warning
    /// indistinguishable from an error), and colours hardcoded as `NSColor`
    /// literals, which is how an editor ends up drawing system red on a light
    /// theme the user deliberately chose.
    @Test("error and warning are different colours, and both come from the palette")
    func severityColoursComeFromTheTheme() {
        let controller = laidOutEditor(text: "let value = 1\n")
        let overlay = makeOverlay(in: controller)
        let palette = ThemePaletteObserver.currentPalette

        let error = overlay.color(for: .error)
        let warning = overlay.color(for: .warning)

        #expect(error != warning)
        #expect(error == palette.nsColor(.danger))
        #expect(warning == palette.nsColor(.warning))
        #expect(overlay.color(for: .information) == palette.nsColor(.info))
        #expect(overlay.color(for: .hint) == palette.nsColor(.tertiaryText))
        // An omitted severity is read as an error rather than silently dropped.
        #expect(overlay.color(for: nil) == palette.nsColor(.danger))
    }

    // MARK: - 13. The generation guard

    /// What it catches: the whole-branch defect — state read before an `await`
    /// published after it. The pointer has moved on by the time this answer
    /// arrives, and showing it would put a card about the previous token over
    /// the current one.
    @Test("a hover answer that arrives after the pointer moved on is not shown")
    func staleHoverAnswerIsNotPublished() async throws {
        let fixture = LSPEditorFixture(behavior: FakeEditorSessionBehavior(
            capabilities: makeHoveringCapabilities(),
            hoverResponse: Hover(contents: "stale documentation")
        ))
        let session = try await fixture.startedSession()
        let controller = laidOutEditor(text: "let value = 1\n")
        let document = makeEditorDocument(text: "let value = 1\n")
        let hover = LSPHoverController(
            document: document,
            registry: fixture.registry,
            delay: .milliseconds(5)
        )
        hover.textView = controller.textView

        await session.holdNextHovers(1)
        hover.pointerMoved(to: try #require(point(forOffset: 4, in: controller)))
        #expect(await pollAsync { await session.heldHoverCount == 1 })

        // The text changed while the request was in flight — the one thing the
        // generation exists for.
        hover.invalidate()
        await session.releaseHeldHovers()

        // Give the resumed request every chance to publish, then assert it did
        // not: a negative that has to survive the delay it is denying.
        try await Task.sleep(for: .milliseconds(200))
        #expect(hover.presented == nil)
    }

    /// The other half of the same guard: an answer that is still current *is*
    /// shown. Without this the test above passes for a controller that never
    /// shows anything.
    @Test("a hover answer that is still current is shown")
    func currentHoverAnswerIsPublished() async throws {
        let fixture = LSPEditorFixture(behavior: FakeEditorSessionBehavior(
            capabilities: makeHoveringCapabilities(),
            hoverResponse: Hover(contents: "let value: Int")
        ))
        _ = try await fixture.startedSession()
        let controller = laidOutEditor(text: "let value = 1\n")
        let document = makeEditorDocument(text: "let value = 1\n")
        let hover = LSPHoverController(
            document: document,
            registry: fixture.registry,
            delay: .milliseconds(5)
        )
        hover.textView = controller.textView

        hover.pointerMoved(to: try #require(point(forOffset: 4, in: controller)))

        #expect(await poll { hover.presented != nil })
        #expect(hover.presented?.text == "let value: Int")
        #expect(hover.presented?.origin == .server)
    }

    // MARK: - 14. Diagnostics beat the server

    /// What it catches: a hover that asks the server about a token the user is
    /// pointing at *because it is underlined in red*, and then answers with its
    /// type signature. It also catches the round trip: pointing at a squiggle
    /// must issue no request at all.
    @Test("a point inside a diagnostic shows the message and asks the server nothing")
    func diagnosticWinsAndIssuesNoRequest() async throws {
        let fixture = LSPEditorFixture(behavior: FakeEditorSessionBehavior(
            capabilities: makeHoveringCapabilities(),
            hoverResponse: Hover(contents: "the server's answer")
        ))
        _ = try await fixture.startedSession()
        let controller = laidOutEditor(text: "let value = 1\n")
        let document = makeEditorDocument(text: "let value = 1\n")
        let hover = LSPHoverController(
            document: document,
            registry: fixture.registry,
            delay: .milliseconds(5)
        )
        hover.textView = controller.textView
        hover.marks = [
            makeMark(location: 0, length: 13, severity: .warning, message: "shadows an outer binding"),
            makeMark(location: 0, length: 13, severity: .error, message: "cannot find 'value' in scope")
        ]

        hover.pointerMoved(to: try #require(point(forOffset: 4, in: controller)))

        #expect(await poll { hover.presented != nil })
        #expect(hover.presented?.origin == .diagnostic)
        // Most severe first, both shown: two servers can disagree about one
        // span and the user needs both.
        #expect(hover.presented?.text == "cannot find 'value' in scope\n\nshadows an outer binding")
        #expect(!fixture.log.events.contains("hover"))
    }

    // MARK: - 15. A server that says no

    /// What it catches: treating a bare `false` as "the key is present, so the
    /// feature is there". Every hover then becomes a request the server has
    /// already said it will not answer.
    @Test("a server advertising hoverProvider: false is never asked")
    func bareFalseHoverProviderIsHonoured() async throws {
        let fixture = LSPEditorFixture(behavior: FakeEditorSessionBehavior(
            capabilities: makeHoveringCapabilities(provides: false),
            hoverResponse: Hover(contents: "never asked for")
        ))
        _ = try await fixture.startedSession()
        let controller = laidOutEditor(text: "let value = 1\n")
        let document = makeEditorDocument(text: "let value = 1\n")
        let hover = LSPHoverController(
            document: document,
            registry: fixture.registry,
            delay: .milliseconds(5)
        )
        hover.textView = controller.textView

        hover.pointerMoved(to: try #require(point(forOffset: 4, in: controller)))

        try await Task.sleep(for: .milliseconds(200))
        #expect(!fixture.log.events.contains("hover"))
        #expect(hover.presented == nil)
    }

    // MARK: - 16. All three content shapes

    /// What it catches: a reader that handles only `MarkupContent`, which is
    /// what a modern server sends — and silently shows nothing for the two
    /// older shapes that the protocol still permits and that plenty of servers
    /// still use.
    @Test("all three Hover.contents shapes reduce to the expected text")
    func everyHoverContentShapeIsRead() {
        let plain = LSPHoverController.hoverText(from: .optionA(.optionA("a plain string")))
        #expect(plain.text == "a plain string")
        #expect(!plain.isMarkdown)

        let pair = LanguageStringPair(language: .swift, value: "func f() -> Int")
        let coded = LSPHoverController.hoverText(from: .optionA(.optionB(pair)))
        #expect(coded.text == "func f() -> Int")
        #expect(!coded.isMarkdown)

        let list = LSPHoverController.hoverText(from: .optionB([.optionA("first"), .optionB(pair)]))
        #expect(list.text == "first\n\nfunc f() -> Int")
        #expect(!list.isMarkdown)

        let markdown = LSPHoverController.hoverText(
            from: .optionC(MarkupContent(kind: .markdown, value: "# Heading"))
        )
        #expect(markdown.text == "# Heading")
        #expect(markdown.isMarkdown)

        // Only `MarkupContent` says which it is, and only `.markdown` means
        // markdown: plaintext rendered as markdown eats its own punctuation.
        let plaintext = LSPHoverController.hoverText(
            from: .optionC(MarkupContent(kind: .plaintext, value: "*not emphasis*"))
        )
        #expect(plaintext.text == "*not emphasis*")
        #expect(!plaintext.isMarkdown)
    }

    // MARK: - 17. Teardown

    /// What it catches: a coordinator that leaves its overlay in the text view
    /// after the editor is gone — a second one is installed on the next mount,
    /// each with its own tracking area — and a card left on screen over
    /// whatever replaced the editor.
    @Test("destroy removes the overlay and takes the card down")
    func destroyRemovesEverything() async throws {
        let fixture = LSPEditorFixture(behavior: FakeEditorSessionBehavior(
            capabilities: makeHoveringCapabilities(),
            hoverResponse: Hover(contents: "documentation")
        ))
        _ = try await fixture.startedSession()
        let controller = laidOutEditor(text: "let value = 1\n")
        let document = makeEditorDocument(text: "let value = 1\n")
        let store = DiagnosticStore()
        let coordinator = LSPEditorAnnotationCoordinator(
            document: document,
            registry: fixture.registry,
            store: store
        )

        coordinator.prepareCoordinator(controller: controller)
        #expect(controller.textView.subviews.contains { $0 is DiagnosticOverlayView })

        // Put a card up first, so the dismissal below has something to undo.
        coordinator.hover.marks = [makeMark(location: 0, length: 13, message: "unused")]
        coordinator.hover.pointerMoved(to: try #require(point(forOffset: 4, in: controller)))
        #expect(await poll { coordinator.hover.presented != nil })

        coordinator.destroy()

        #expect(!controller.textView.subviews.contains { $0 is DiagnosticOverlayView })
        #expect(coordinator.hover.presented == nil)
        #expect(coordinator.hover.textView == nil)
    }

    // MARK: - The store reaches the overlay

    /// Not one of the numbered cases, and the one thing they leave uncovered:
    /// that a diagnostic published by a server actually arrives at the view.
    /// Every test above hands the marks over by hand.
    @Test("a diagnostic in the store becomes a mark on the overlay")
    func storeDiagnosticsReachTheOverlay() async throws {
        let fixture = LSPEditorFixture(behavior: FakeEditorSessionBehavior(
            capabilities: makeHoveringCapabilities()
        ))
        let session = try await fixture.startedSession()
        let uri = "file:///Workspace/Sample.swift"
        let controller = laidOutEditor(text: "let value = 1\n")
        let document = makeEditorDocument(uri: uri, text: "let value = 1\n")
        let store = DiagnosticStore()
        store.observe(session)
        let coordinator = LSPEditorAnnotationCoordinator(
            document: document,
            registry: fixture.registry,
            store: store
        )
        coordinator.prepareCoordinator(controller: controller)

        session.publish(PublishDiagnosticsParams(
            uri: uri,
            version: 1,
            diagnostics: [
                Diagnostic(
                    range: LSPRange(
                        start: Position(line: 0, character: 4),
                        end: Position(line: 0, character: 9)
                    ),
                    severity: .warning,
                    message: "never used"
                )
            ]
        ))

        let overlay = try #require(
            controller.textView.subviews.compactMap { $0 as? DiagnosticOverlayView }.first
        )
        #expect(await poll { !overlay.squiggles().isEmpty })
        #expect(overlay.squiggles().allSatisfy { $0.severity == .warning })
        #expect(coordinator.hover.marks.first?.message == "never used")
    }

    // MARK: - Marks are re-anchored across edits

    /// Installs a coordinator with one published diagnostic already on it, and
    /// hands back everything a re-anchoring assertion needs.
    ///
    /// The diagnostic goes through a real `DiagnosticStore` rather than being
    /// poked into the views, because the coordinator's own copy of the marks
    /// is what gets shifted and only the publish path fills it.
    private func makeAnnotatedEditor(
        text: String,
        diagnostic: LSPRange
    ) async throws -> (controller: TextViewController, coordinator: LSPEditorAnnotationCoordinator) {
        let fixture = LSPEditorFixture(behavior: FakeEditorSessionBehavior(
            capabilities: makeHoveringCapabilities()
        ))
        let session = try await fixture.startedSession()
        let uri = "file:///Workspace/Sample.swift"
        let controller = laidOutEditor(text: text)
        let document = makeEditorDocument(uri: uri, text: text)
        let store = DiagnosticStore()
        store.observe(session)
        let coordinator = LSPEditorAnnotationCoordinator(
            document: document,
            registry: fixture.registry,
            store: store
        )
        coordinator.prepareCoordinator(controller: controller)

        session.publish(PublishDiagnosticsParams(
            uri: uri,
            version: 1,
            diagnostics: [Diagnostic(range: diagnostic, severity: .warning, message: "never used")]
        ))
        #expect(await poll { !coordinator.hover.marks.isEmpty })
        return (controller, coordinator)
    }

    /// What it catches: marks that hold already-converted `NSRange`s and are
    /// never shifted, so an insertion above them leaves every squiggle
    /// underlining the wrong text until the server happens to publish again.
    @Test("an insertion above a mark moves the mark down by the inserted length")
    func insertionAboveAMarkShiftsIt() async throws {
        // "let a = 1\n" is ten units, so line 1 starts at 10 and its "b" is
        // at 14.
        let (controller, coordinator) = try await makeAnnotatedEditor(
            text: "let a = 1\nlet b = 2\nlet c = 3\n",
            diagnostic: LSPRange(
                start: Position(line: 1, character: 4),
                end: Position(line: 1, character: 5)
            )
        )
        #expect(coordinator.hover.marks.first?.range == NSRange(location: 14, length: 1))

        controller.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "// header\n")

        #expect(
            coordinator.hover.marks.first?.range == NSRange(location: 24, length: 1),
            "a mark below an insertion has to move by the inserted length"
        )
    }

    /// The other direction, which is the one that can address text that no
    /// longer exists: deleting above a mark must pull it back up.
    @Test("a deletion above a mark moves the mark up, and never off the end of the buffer")
    func deletionAboveAMarkShiftsItBack() async throws {
        let (controller, coordinator) = try await makeAnnotatedEditor(
            text: "let a = 1\nlet b = 2\nlet c = 3\n",
            diagnostic: LSPRange(
                start: Position(line: 2, character: 4),
                end: Position(line: 2, character: 5)
            )
        )
        let before = try #require(coordinator.hover.marks.first?.range)
        #expect(before == NSRange(location: 24, length: 1))

        // Delete the whole first line.
        controller.textView.replaceCharacters(in: NSRange(location: 0, length: 10), with: "")

        let after = try #require(coordinator.hover.marks.first?.range)
        #expect(after == NSRange(location: 14, length: 1))
        #expect(
            after.location + after.length <= (controller.textView.string as NSString).length,
            "a mark must never address past the end of the buffer"
        )
    }

    /// A mark entirely above the edit describes text nothing touched, so it
    /// must be left exactly as it is — a blanket shift would be as wrong as no
    /// shift at all.
    @Test("an edit below a mark leaves the mark alone")
    func editBelowAMarkLeavesItAlone() async throws {
        let (controller, coordinator) = try await makeAnnotatedEditor(
            text: "let a = 1\nlet b = 2\nlet c = 3\n",
            diagnostic: LSPRange(
                start: Position(line: 0, character: 4),
                end: Position(line: 0, character: 5)
            )
        )
        let before = try #require(coordinator.hover.marks.first?.range)

        controller.textView.replaceCharacters(in: NSRange(location: 20, length: 0), with: "// tail\n")

        #expect(coordinator.hover.marks.first?.range == before)
    }

    /// The text under the mark is gone, so the complaint about it is stale.
    /// Keeping the mark would underline the replacement, which is a claim the
    /// server never made.
    @Test("an edit inside a mark drops it rather than underlining the replacement")
    func editInsideAMarkDropsIt() async throws {
        let (controller, coordinator) = try await makeAnnotatedEditor(
            text: "let a = 1\nlet b = 2\nlet c = 3\n",
            diagnostic: LSPRange(
                start: Position(line: 1, character: 4),
                end: Position(line: 1, character: 9)
            )
        )
        #expect(coordinator.hover.marks.count == 1)

        // Retype the middle of the marked span.
        controller.textView.replaceCharacters(in: NSRange(location: 15, length: 2), with: "XYZ")

        #expect(coordinator.hover.marks.isEmpty)
    }

    /// The overlay draws from its own copy, so a shift that only updated the
    /// coordinator's array would move nothing on screen.
    @Test("the re-anchored marks reach the overlay, not just the coordinator")
    func reanchoredMarksReachTheOverlay() async throws {
        let (controller, coordinator) = try await makeAnnotatedEditor(
            text: "let a = 1\nlet b = 2\nlet c = 3\n",
            diagnostic: LSPRange(
                start: Position(line: 1, character: 4),
                end: Position(line: 1, character: 5)
            )
        )
        let overlay = try #require(
            controller.textView.subviews.compactMap { $0 as? DiagnosticOverlayView }.first
        )
        #expect(overlay.marks.first?.range == NSRange(location: 14, length: 1))

        controller.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "// header\n")

        #expect(overlay.marks.first?.range == NSRange(location: 24, length: 1))
        _ = coordinator
    }

    /// A coordinator torn down with the editor must stop watching that
    /// storage; an observer left registered against a live text storage is a
    /// callback into a dead object graph.
    @Test("destroy stops the coordinator re-anchoring against further edits")
    func destroyStopsReanchoring() async throws {
        let (controller, coordinator) = try await makeAnnotatedEditor(
            text: "let a = 1\nlet b = 2\nlet c = 3\n",
            diagnostic: LSPRange(
                start: Position(line: 1, character: 4),
                end: Position(line: 1, character: 5)
            )
        )

        let overlay = try #require(
            controller.textView.subviews.compactMap { $0 as? DiagnosticOverlayView }.first
        )
        coordinator.destroy()
        controller.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "// header\n")

        // The overlay is off the view by now; what matters is that the edit
        // did not reach a torn-down coordinator at all, which it would have
        // done through an observer left registered on a still-live storage.
        #expect(overlay.marks.first?.range == NSRange(location: 14, length: 1))
        #expect(overlay.superview == nil)
    }
}
