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
            // Every stored range now describes text that has moved, so the
            // squiggles are redrawn from the layout manager's new rects and the
            // card — which was explaining a token that may no longer be there —
            // goes away until the pointer asks again.
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
        let marks = diagnostics.map { diagnostic in
            DiagnosticMark(
                range: document.nsRange(for: diagnostic.range),
                severity: diagnostic.severity,
                message: diagnostic.message
            )
        }
        overlay?.marks = marks
        hover.marks = marks

        // A card explaining a diagnostic that has just been replaced is
        // explaining something the server no longer says. A card showing the
        // server's *hover* answer is about the identifier, not the complaint,
        // and survives.
        if hover.presented?.origin == .diagnostic {
            hover.invalidate()
        }
    }
}
