//
//  LSPEditorAnnotationCoordinator.swift
//  AgenticToolkit
//

import AgenticToolkitLanguage
import AppKit
import CodeEditSourceEditor
import Combine
import Foundation
import LanguageServerProtocol

/// Attaches the diagnostic overlay and the hover card to one document's editor,
/// and keeps both fed from the `DiagnosticStore`.
///
/// One per open document, held by `FileEditorState.Slot` beside the completion
/// and jump-to-definition delegates, for the same reason: `SourceEditor` keeps
/// its coordinators only for as long as the controller lives, and the slot's
/// lifetime is exactly the cached editor's.
///
/// This is the only object in the pair that knows about a `DocumentUri` or a
/// `Diagnostic`. `DiagnosticOverlayView` draws `DiagnosticMark`s and
/// `LSPHoverController` explains them; the conversion from LSP `Position`s to
/// text-storage ranges happens here, once, against the one document both of
/// them are about.
///
/// **`TextViewCoordinator` is not `@MainActor`.** Every requirement below is
/// therefore `nonisolated` with a `MainActor.assumeIsolated` body — the same
/// spelling, and the same argument, as
/// `LSPJumpToDefinitionDelegate.openLink(link:)`: `TextViewController` is an
/// `NSViewController` and calls all six of these from its own main-actor
/// methods, so the assertion is one the call graph already guarantees, and a
/// `Task` hop would land after the text has moved on.
@MainActor
final class LSPEditorAnnotationCoordinator: TextViewCoordinator {

    private let document: TextDocument
    private let store: DiagnosticStore
    /// Internal rather than private: the coordinator's teardown promise is
    /// that the card comes down with the editor, and the card's own
    /// `isShown` cannot be asserted off screen — `hover.presented` is the
    /// record of that decision, and a test has to be able to read it.
    let hover: LSPHoverController

    private weak var controller: TextViewController?
    private var overlay: DiagnosticOverlayView?
    private var subscription: AnyCancellable?

    /// The marks currently on screen, in text-storage coordinates.
    ///
    /// Held here as well as pushed to the overlay and the hover card because
    /// they have to be *re-anchored* between diagnostic publications: this is
    /// the copy the shift is applied to, and the two views are refreshed from
    /// it. Before, the two views were the only holders and nothing shifted
    /// them at all.
    private var marks: [DiagnosticMark] = []

    /// The text storage this coordinator is watching for edits, and the
    /// observer token that watches it.
    ///
    /// The storage is held here rather than read out of the notification so
    /// nothing non-`Sendable` has to cross out of the observer closure — the
    /// observer is registered with `object:`, so it only ever fires for this
    /// one storage anyway.
    private weak var observedStorage: NSTextStorage?
    private var editObserver: (any NSObjectProtocol)?

    init(
        document: TextDocument,
        registry: LanguageServerRegistry,
        store: DiagnosticStore,
        card: HoverCardPopoverController = HoverCardPopoverController()
    ) {
        self.document = document
        self.store = store
        self.hover = LSPHoverController(document: document, registry: registry, card: card)
    }

    // MARK: - TextViewCoordinator

    nonisolated func prepareCoordinator(controller: TextViewController) {
        MainActor.assumeIsolated {
            install(in: controller)
        }
    }

    nonisolated func textViewDidChangeText(controller: TextViewController) {
        MainActor.assumeIsolated {
            // Redraw only. The *re-anchoring* cannot happen here: this
            // requirement is handed no range and no delta, and the marks need
            // both. It is done from the storage's own edit notification (see
            // `install(in:)`), which fires first — synchronously, from inside
            // `processEditing()` — so by the time this runs the marks already
            // describe the new text and the squiggles are redrawn from the
            // layout manager's new rects. The card, which was explaining a
            // token that may no longer be there, goes away until the pointer
            // asks again.
            overlay?.textChanged()
            hover.invalidate()
        }
    }

    nonisolated func textViewDidChangeSelection(controller: TextViewController, newPositions: [CursorPosition]) {
        MainActor.assumeIsolated {
            hover.invalidate()
        }
    }

    nonisolated func controllerDidDisappear(controller: TextViewController) {
        MainActor.assumeIsolated {
            // A popover anchored to a view that is no longer on screen is a
            // window floating over whatever replaced the editor.
            hover.invalidate()
        }
    }

    nonisolated func destroy() {
        MainActor.assumeIsolated {
            hover.invalidate()
            hover.textView = nil
            overlay?.removeFromSuperview()
            overlay = nil
            subscription = nil
            if let editObserver {
                NotificationCenter.default.removeObserver(editObserver)
            }
            editObserver = nil
            observedStorage = nil
            marks = []
            controller = nil
        }
    }

    // MARK: - Installation

    private func install(in controller: TextViewController) {
        guard let textView = controller.textView else { return }
        self.controller = controller

        // A subview of the text view, not a floating subview of the scroll
        // view. The rects the overlay draws come from
        // `textView.layoutManager.rectsFor(range:)` and are in the text view's
        // own coordinate space; as its subview, the overlay shares that space
        // exactly and scrolls with the text for free. A floating subview sits
        // in the scroll view's coordinates and stays put while the document
        // moves underneath it, which would need the content offset applied to
        // every rect on every scroll.
        let overlay = DiagnosticOverlayView(textView: textView)
        textView.addSubview(overlay)
        overlay.mouseMovedHandler = { [weak self, weak overlay, weak textView] point in
            guard let self, let overlay, let textView else { return }
            // The overlay is pinned to the text view's bounds, so this is
            // usually the identity — converted anyway, because "usually" is not
            // an invariant anything here enforces.
            hover.pointerMoved(to: overlay.convert(point, to: textView))
        }
        self.overlay = overlay

        hover.textView = textView

        // **Marks are re-anchored from the storage's own edit notification.**
        // A squiggle on line 40 has to still be on line 40's text after three
        // lines are inserted above it; the marks hold already-converted
        // `NSRange`s, and nothing shifted them, so they drifted onto whatever
        // text had moved under them and only corrected themselves when the
        // debounced `publishDiagnostics` round-trip came back. A deletion big
        // enough to shrink the buffer past a mark left the overlay drawing
        // against offsets that addressed nothing.
        //
        // This notification, rather than `textViewDidChangeText(controller:)`,
        // because it is the only edit signal that carries the range and the
        // delta — `NSTextStorage` posts it from `processEditing()` with
        // `editedRange` describing the *new* text and `changeInLength` the
        // difference, which is exactly what a shift needs. Scoped to this
        // editor's own storage by `object:`.
        //
        // `queue: nil`, so the block runs synchronously on the posting thread
        // rather than being enqueued onto the main `OperationQueue`. Two
        // reasons, and both are correctness rather than speed: the marks have
        // to describe the new text before `textViewDidChangeText(controller:)`
        // redraws the squiggles from them, and `editedRange`/`changeInLength`
        // are properties of the storage that the *next* edit overwrites — read
        // them a runloop turn late and a fast typist's second keystroke has
        // already replaced the delta belonging to the first. Text storage is
        // edited on the main thread by AppKit's own contract, which is the
        // same assumption `TextDocumentStorage.replaceCharacters` makes.
        if let storage = textView.textStorage {
            observedStorage = storage
            editObserver = NotificationCenter.default.addObserver(
                forName: NSTextStorage.didProcessEditingNotification,
                object: storage,
                queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.storageDidEdit() }
            }
        }

        // `publisher(for:)` emits once immediately, so a document opened after
        // its diagnostics arrived — which is every reopened file — is marked up
        // without waiting for the server to say anything again.
        subscription = store.publisher(for: document.uri)
            .sink { [weak self] diagnostics in
                MainActor.assumeIsolated {
                    self?.apply(diagnostics)
                }
            }
    }

    private func apply(_ diagnostics: [Diagnostic]) {
        publish(diagnostics.map { diagnostic in
            DiagnosticMark(
                range: document.nsRange(for: diagnostic.range),
                severity: diagnostic.severity,
                message: diagnostic.message
            )
        })

        // A card explaining a diagnostic that has just been replaced is
        // explaining something the server no longer says. A card showing the
        // server's *hover* answer is about the identifier, not the complaint,
        // and survives.
        if hover.presented?.origin == .diagnostic {
            hover.invalidate()
        }
    }

    private func publish(_ newMarks: [DiagnosticMark]) {
        marks = newMarks
        overlay?.marks = newMarks
        hover.marks = newMarks
    }

    /// Shifts every mark by one character edit, so a squiggle keeps sitting on
    /// the text it was published against.
    ///
    /// Only character edits: the same notification fires for the attribute
    /// runs the highlighter writes on every repaint, and those move nothing.
    private func storageDidEdit() {
        guard let storage = observedStorage else { return }
        guard storage.editedMask.contains(.editedCharacters) else { return }
        guard !marks.isEmpty else { return }

        // `editedRange` describes the text as it is *now*; the range that was
        // replaced was `changeInLength` shorter (or longer, for a deletion).
        let delta = storage.changeInLength
        let newRange = storage.editedRange
        let replacedLength = max(0, newRange.length - delta)
        reanchor(replacedStart: newRange.location, replacedLength: replacedLength, delta: delta)
    }

    /// Applies one edit's delta to the stored marks.
    ///
    /// Three cases, checked in this order because the first two overlap for a
    /// zero-width insertion: a mark starting at or after the end of what was
    /// replaced moves by the delta (an insertion at a mark's own start pushes
    /// the mark right, which is what the user sees); a mark ending at or
    /// before the start of what was replaced does not move; and a mark the
    /// edit lands *inside* is dropped, because the text it was describing is
    /// no longer the text it covers and drawing a squiggle over the
    /// replacement would be a lie until the server answers again.
    private func reanchor(replacedStart: Int, replacedLength: Int, delta: Int) {
        let replacedEnd = replacedStart + replacedLength
        let shifted: [DiagnosticMark] = marks.compactMap { mark in
            if mark.range.location >= replacedEnd {
                return DiagnosticMark(
                    range: NSRange(location: max(0, mark.range.location + delta), length: mark.range.length),
                    severity: mark.severity,
                    message: mark.message
                )
            }
            if mark.range.location + mark.range.length <= replacedStart {
                return mark
            }
            return nil
        }
        guard shifted != marks else { return }
        publish(shifted)
    }
}
