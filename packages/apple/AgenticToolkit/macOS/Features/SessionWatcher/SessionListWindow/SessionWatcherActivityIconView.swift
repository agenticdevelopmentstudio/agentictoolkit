//
//  SessionWatcherActivityIconView.swift
//  AgenticToolkit
//
//  The one glyph at the end of a session row's header line, showing whether the
//  agent is working, idle, or blocked on the user.
//

import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

extension SessionWatcher {

    /// The session row's activity indicator: chasing arrows while the agent works,
    /// a quiet dot when it's idle, a pulsing badge when it's waiting on the user.
    ///
    /// The animations are CoreAnimation rather than SF Symbol effects because
    /// `.rotate` needs macOS 15 and this framework ships to macOS 14.
    ///
    /// The glyph is drawn into a sublayer the view owns, not into the view's own
    /// layer. AppKit keeps a view's backing layer in step with its frame and puts
    /// the anchor point back at the corner whenever it does, so a spin installed on
    /// that layer turned about the glyph's corner: the arrows orbited down over the
    /// output line beneath them instead of spinning in place. AppKit never touches a
    /// sublayer's geometry, so its centred anchor holds.
    public final class SessionWatcherActivityIconView: NSView, Themeable {
        private var activity: SessionWatcherActivity
        private var isSummarizing: Bool
        private var tint: NSColor = .tertiaryLabelColor
        private let glyph = CALayer()

        /// Side of the glyph's box. Small enough to sit inside a two-line row
        /// without pushing its height around.
        private static let side: CGFloat = 13
        private static let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)

        private static let rotationKey = "session-activity-rotation"
        private static let pulseKey = "session-activity-pulse"

        public init(activity: SessionWatcherActivity, isSummarizing: Bool) {
            self.activity = activity
            self.isSummarizing = isSummarizing
            super.init(frame: .zero)
            wantsLayer = true
            glyph.contentsGravity = .resizeAspect
            layer?.addSublayer(glyph)
            setAccessibilityElement(true)
            setAccessibilityRole(.image)
            translatesAutoresizingMaskIntoConstraints = false
            setContentCompressionResistancePriority(.required, for: .horizontal)
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: Self.side),
                heightAnchor.constraint(equalToConstant: Self.side)
            ])
            describeState()
            renderGlyph()
            applyQuiet()
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { fatalError() }

        /// Moves an existing glyph to a new state instead of replacing the view.
        ///
        /// A session's activity changes on every poll, and rebuilding the icon
        /// restarted its animation from zero each time — the "working" arrows
        /// visibly stuttered rather than spinning. Returning early when nothing
        /// changed is what keeps them spinning: `startAnimation()` is a no-op for
        /// an animation that is already installed, but the removal below is not.
        public func update(activity: SessionWatcherActivity, isSummarizing: Bool) {
            guard self.activity != activity || self.isSummarizing != isSummarizing else { return }
            self.activity = activity
            self.isSummarizing = isSummarizing
            describeState()
            renderGlyph()
            applyQuiet()
            // The state that was animating may not be the state that is, so the old
            // animation goes before the new one is chosen.
            stopAnimation()
            if window != nil { startAnimation() }
        }

        /// Idle is the state a row is in most of the time, so a dot for it is a
        /// mark on nearly every row at once — which makes the marks say nothing,
        /// and leaves the two states worth noticing competing with a column of
        /// noise. An empty slot is the accurate rendering of *nothing is
        /// happening*, and it is what makes a glyph appearing anywhere in the
        /// list mean something.
        ///
        /// Summarizing is not quiet even while idle: the sparkles say work is
        /// being done *about* the session, which is exactly the fact a blank
        /// slot would deny.
        private var isQuiet: Bool { activity == .idle && !isSummarizing }

        /// The stack this sits in detaches a hidden arranged subview, so the
        /// row closes up around the gap rather than reserving a blank square.
        private func applyQuiet() {
            isHidden = isQuiet
        }

        private var symbolName: String {
            if isSummarizing { return "sparkles" }
            switch activity {
            case .working: return "arrow.triangle.2.circlepath"
            case .idle:    return "circle.fill"
            case .waiting: return "exclamationmark.circle.fill"
            }
        }

        private var accessibilityText: String {
            if isSummarizing { return "Summarizing" }
            switch activity {
            case .working: return "Working"
            case .idle:    return "Idle"
            case .waiting: return "Waiting for you"
            }
        }

        private func describeState() {
            accessibilityID("session-panel.activity.\(isSummarizing ? "summarizing" : activity.rawValue)")
            setAccessibilityLabel(accessibilityText)
            toolTip = accessibilityText
        }

        /// Colours the glyph. Waiting is the one state meant to catch the eye
        /// across a full window of rows, so it takes the warning colour.
        public func applyTheme(_ palette: SemanticPalette) {
            if isSummarizing {
                tint = palette.accentColor
            } else {
                switch activity {
                case .working: tint = palette.accentColor
                case .idle:    tint = palette.tertiaryTextColor
                case .waiting: tint = palette.warningColor
                }
            }
            renderGlyph()
        }

        // MARK: - Drawing

        /// Rasterises the tinted symbol into the glyph layer.
        ///
        /// Tinted by filling over the symbol's own pixels rather than through a
        /// palette configuration, which paints every layer of a multi-layer symbol
        /// the one colour — the exclamation mark would vanish into its circle.
        private func renderGlyph() {
            guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityText)?
                .withSymbolConfiguration(Self.symbolConfiguration) else {
                glyph.contents = nil
                return
            }
            let color = tint
            let tinted = NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect)
                color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            // A dynamic colour resolves against the appearance current while drawing.
            effectiveAppearance.performAsCurrentDrawingAppearance {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                glyph.contentsScale = scale
                glyph.contents = tinted.layerContents(forContentsScale: scale)
                CATransaction.commit()
            }
        }

        public override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            glyph.bounds = bounds
            glyph.position = CGPoint(x: bounds.midX, y: bounds.midY)
            CATransaction.commit()
        }

        public override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            renderGlyph()
        }

        public override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            renderGlyph()
        }

        // MARK: - Animation

        // Layer animations are dropped when the view leaves the window, so they are
        // (re)installed on every move into one rather than once at construction.
        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                stopAnimation()
            } else {
                renderGlyph()
                startAnimation()
            }
        }

        private func stopAnimation() {
            glyph.removeAnimation(forKey: Self.rotationKey)
            glyph.removeAnimation(forKey: Self.pulseKey)
        }

        private func startAnimation() {
            if isSummarizing || activity == .waiting {
                guard glyph.animation(forKey: Self.pulseKey) == nil else { return }
                let pulse = CABasicAnimation(keyPath: "opacity")
                pulse.fromValue = 1.0
                pulse.toValue = 0.25
                pulse.duration = 0.7
                pulse.autoreverses = true
                pulse.repeatCount = .greatestFiniteMagnitude
                glyph.add(pulse, forKey: Self.pulseKey)
                return
            }
            guard activity == .working else { return }
            guard glyph.animation(forKey: Self.rotationKey) == nil else { return }
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -Double.pi * 2   // clockwise on screen (AppKit's y is up)
            spin.duration = 1.1
            spin.repeatCount = .greatestFiniteMagnitude
            spin.timingFunction = CAMediaTimingFunction(name: .linear)
            glyph.add(spin, forKey: Self.rotationKey)
        }

        // MARK: - Test seams

        /// The layer the glyph is drawn into and animated on.
        var glyphLayer: CALayer { glyph }
    }
}
