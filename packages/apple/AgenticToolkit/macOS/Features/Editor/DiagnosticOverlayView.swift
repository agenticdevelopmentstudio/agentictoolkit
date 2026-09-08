//
//  DiagnosticOverlayView.swift
//  AgenticToolkit
//

import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AppKit
import CodeEditTextView
import LanguageServerProtocol

/// One thing a server said about one span of text, in the editor's own
/// vocabulary: a UTF-16 range in the text storage, how bad it is, and what to
/// say about it.
///
/// This is the whole of the overlay's and the hover card's shared input. The
/// conversion from `Diagnostic` — whose ranges are line/character `Position`s
/// against one specific `TextDocument` — happens once, in
/// `LSPEditorAnnotationCoordinator`, so neither of the two views that consume
/// this has to hold a document to understand it.
struct DiagnosticMark: Equatable {

    /// A UTF-16 range in the text view's storage. May be empty: "expected '}'
    /// here" is a real diagnostic at a point, not over a span.
    let range: NSRange

    /// `nil` is what a server sends when it declines to say. LSP leaves the
    /// interpretation to the client; this one reads it as an error, on the
    /// grounds that under-reporting severity is the more expensive mistake.
    let severity: DiagnosticSeverity?

    /// What the server said, shown verbatim in the hover card.
    let message: String

    /// Whether `offset` is inside this mark, as the user sees it.
    ///
    /// A zero-length range is drawn one character wide (see
    /// `DiagnosticOverlayView.rects(for:)`), so containment has to match the
    /// mark on screen rather than the empty interval the server sent —
    /// otherwise the one diagnostic most worth hovering is the one that cannot
    /// be hovered.
    func contains(_ offset: Int) -> Bool {
        offset >= range.location && offset < range.location + max(range.length, 1)
    }
}

/// Draws the squiggles.
///
/// A transparent, non-interactive sheet of glass over the text view, whose
/// entire job is to paint one squiggle per line fragment of each diagnostic
/// range and to report where the pointer is. It knows nothing about sessions,
/// URIs or `PublishDiagnosticsParams` — `LSPEditorAnnotationCoordinator` hands
/// it `DiagnosticMark`s and it draws them.
///
/// **No gutter marker, deliberately.** The usual companion to squiggles is an
/// error badge in the gutter, and this does not draw one because it cannot:
/// `CodeEditSourceEditor`'s `TextViewController.gutterView` is declared without
/// a `public` modifier, so from outside that module there is no gutter to
/// attach to and no width to inset. Nothing else is missing — the marks, the
/// severities and the theme colours are all already here — so the day
/// `gutterView` becomes public this becomes an addition to this one file and a
/// change to nothing else. Recorded here, at the type it would change, rather
/// than as a tracked work item: it is not work anyone can pick up, it is a fact
/// about a dependency.
@MainActor
final class DiagnosticOverlayView: NSView {

    /// One squiggle: a rect from the layout manager, and the severity whose
    /// colour it is drawn in.
    struct Squiggle: Equatable {
        let rect: CGRect
        let severity: DiagnosticSeverity?
    }

    /// Peak-to-baseline height of the wave, in points.
    private static let amplitude: CGFloat = 1.5

    /// Length of one full up-and-down cycle, in points.
    private static let period: CGFloat = 4

    /// Used when the text view has no usable font metrics, which is only true
    /// before the first layout pass.
    private static let fallbackCharacterWidth: CGFloat = 7

    /// What to draw. Setting it redraws — this is the "redraw on diagnostics
    /// change" half of the contract.
    var marks: [DiagnosticMark] = [] {
        didSet {
            guard marks != oldValue else { return }
            needsDisplay = true
        }
    }

    /// Called on every pointer move inside the overlay, with the point in this
    /// view's — and therefore the text view's — coordinate space.
    var mouseMovedHandler: ((NSPoint) -> Void)?

    /// The view whose layout manager turns ranges into rects. Weak: it is this
    /// view's superview, and a subview never owns its parent.
    private weak var textView: TextView?

    private var palette: SemanticPalette = ThemePaletteObserver.currentPalette
    private var themeObserver: ThemePaletteObserver?
    private var trackingArea: NSTrackingArea?

    init(textView: TextView) {
        self.textView = textView
        super.init(frame: textView.bounds)
        autoresizingMask = [.width, .height]
        // Nothing here is drawn opaquely: the text underneath has to show
        // through every squiggle.
        wantsLayer = true
        layer?.backgroundColor = .clear
        themeObserver = ThemePaletteObserver(host: self) { [weak self] palette in self?.apply(palette) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The text view's coordinates are flipped and every rect drawn here comes
    /// from the text view's layout manager, so the two have to agree — or every
    /// squiggle lands a document-height away from its text.
    override var isFlipped: Bool { true }

    override var isOpaque: Bool { false }

    // MARK: - Not in the way

    /// Transparent to the mouse at every point, including where a squiggle is
    /// drawn. The text view underneath keeps its selection, its caret and its
    /// cmd-click; this view still learns where the pointer is, because a
    /// tracking area delivers to its owner regardless of hit testing.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        // `.inVisibleRect` makes the rect argument moot and keeps the area
        // right as the document scrolls, which matters here because this view
        // is as tall as the whole document and only a sliver is ever on screen.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        mouseMovedHandler?(convert(event.locationInWindow, from: nil))
    }

    // MARK: - Redrawing

    /// The "redraw on text change" half of the contract. Every stored range now
    /// refers to text that has moved, and the layout manager has new rects for
    /// all of them.
    func textChanged() {
        needsDisplay = true
    }

    private func apply(_ palette: SemanticPalette) {
        self.palette = palette
        needsDisplay = true
    }

    // MARK: - Geometry

    /// Every squiggle this view would draw right now, in drawing order.
    ///
    /// Separate from `draw(_:)` so that what is drawn is exactly what can be
    /// asserted on — a test that counted rects by re-deriving them would be
    /// testing its own arithmetic.
    func squiggles() -> [Squiggle] {
        marks.flatMap { mark in
            rects(for: mark.range).map { Squiggle(rect: $0, severity: mark.severity) }
        }
    }

    /// The colour a severity is drawn in. Theme roles only: an editor that
    /// ignored the theme would paint a hardcoded red onto the light background
    /// the user chose.
    func color(for severity: DiagnosticSeverity?) -> NSColor {
        switch severity {
        case .warning: palette.nsColor(.warning)
        case .information: palette.nsColor(.info)
        case .hint: palette.nsColor(.tertiaryText)
        // `.error` and the omitted severity share a colour: see
        // `DiagnosticMark.severity`.
        case .error, nil: palette.nsColor(.danger)
        }
    }

    /// One rect per line fragment the range touches, in this view's coordinate
    /// space, each at least one character wide.
    ///
    /// **The measurement is done one line at a time on purpose.** Handed a
    /// range that spans lines, `rectsFor(range:)` answers with the first line's
    /// rect and nothing else: it converts the range to line-relative
    /// coordinates by subtracting the line's start from *both* ends, so on
    /// every line after the first the start goes negative and the fragment
    /// lookup finds nothing. A three-line error would therefore underline only
    /// its first line. Clipping to each line before asking keeps every
    /// sub-range inside the line it is measured against, which is the input
    /// shape that method is correct for.
    ///
    /// **Nothing measurable still draws.** The layout manager discards
    /// fragments of zero width (`TextLayoutManager+Public.rectsFor(range:in:)`
    /// guards on `fragmentRect.width > 0`), and a line terminator typesets to
    /// zero advance — so a diagnostic sited at the end of a line, on an empty
    /// line, or on an empty document measures to no rects at all, and the
    /// widening in the trailing `map` cannot rescue what never came back.
    /// Those are not exotic: "expected '}'" at end of line is the single most
    /// common thing a parser emits. When the measurement is empty the caret
    /// rect at the diagnostic's own offset is used instead, widened to one
    /// character — `rectForOffset(_:)` has no such guard and answers for a
    /// newline, an empty line and an empty document alike.
    private func rects(for range: NSRange) -> [CGRect] {
        guard let textView, let layoutManager = textView.layoutManager else { return [] }

        let documentLength = textView.documentRange.length
        guard range.location >= 0, range.location <= documentLength else { return [] }

        let minimumWidth = characterWidth(in: textView)
        let measured = measurableRange(for: range, documentLength: documentLength).map { probe in
            layoutManager.linesInRange(probe).flatMap { line -> [CGRect] in
                guard let onThisLine = line.range.intersection(probe), onThisLine.length > 0 else { return [] }
                return layoutManager.rectsFor(range: onThisLine)
            }
        } ?? []

        guard !measured.isEmpty else {
            guard let caret = layoutManager.rectForOffset(range.location) else { return [] }
            return [CGRect(x: caret.minX, y: caret.minY, width: minimumWidth, height: caret.height)]
        }

        // A range that measures thinner than a character — which a composed
        // sequence at a fragment boundary can — is widened after.
        return measured.map { rect in
            guard rect.width < minimumWidth else { return rect }
            return CGRect(x: rect.minX, y: rect.minY, width: minimumWidth, height: rect.height)
        }
    }

    /// The range to hand the layout manager, or `nil` when there is nothing it
    /// can measure.
    ///
    /// An empty range is widened to one character so that it has a fragment to
    /// land on — forwards, or backwards at the very end of the document where
    /// there is no character after it. The widening is a best effort and is
    /// allowed to fail: the caller falls back to the caret rect, which is the
    /// only answer available on an empty line or an empty document.
    private func measurableRange(for range: NSRange, documentLength: Int) -> NSRange? {
        var probe = range
        if probe.length == 0 {
            if probe.location < documentLength {
                probe.length = 1
            } else if probe.location > 0 {
                probe.location -= 1
                probe.length = 1
            }
        }
        guard probe.length > 0,
              probe.location >= 0,
              probe.location + probe.length <= documentLength
        else { return nil }
        return probe
    }

    private func characterWidth(in textView: TextView) -> CGFloat {
        let advance = textView.font.maximumAdvancement.width
        return advance > 0 ? advance : Self.fallbackCharacterWidth
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for squiggle in squiggles() {
            // The wave rides above and below the rect's bottom edge, so the
            // intersection test has to allow for the amplitude or the top half
            // of a scrolled-in squiggle is clipped away.
            guard squiggle.rect.insetBy(dx: 0, dy: -Self.amplitude).intersects(dirtyRect) else { continue }
            color(for: squiggle.severity).setStroke()
            path(under: squiggle.rect).stroke()
        }
    }

    private func path(under rect: CGRect) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = 1
        path.lineJoinStyle = .round

        // Flipped coordinates: `maxY` is the bottom of the text, and the wave
        // sits just inside it so a descender does not collide with a peak.
        let baseline = rect.maxY - Self.amplitude
        var cursor = rect.minX
        var isUp = true
        path.move(to: CGPoint(x: cursor, y: baseline))
        while cursor < rect.maxX {
            cursor = min(cursor + Self.period / 2, rect.maxX)
            path.line(to: CGPoint(x: cursor, y: baseline + (isUp ? -Self.amplitude : Self.amplitude)))
            isUp.toggle()
        }
        return path
    }
}
