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
    public final class SessionWatcherActivityIconView: NSImageView {
        private let activity: SessionWatcherActivity
        private let isSummarizing: Bool

        /// Side of the glyph's box. Small enough to sit inside a two-line row
        /// without pushing its height around.
        private static let side: CGFloat = 13

        private static let rotationKey = "session-activity-rotation"
        private static let pulseKey = "session-activity-pulse"

        public init(activity: SessionWatcherActivity, isSummarizing: Bool) {
            self.activity = activity
            self.isSummarizing = isSummarizing
            super.init(frame: .zero)
            accessibilityID("session-panel.activity.\(isSummarizing ? "summarizing" : activity.rawValue)")
            wantsLayer = true
            imageScaling = .scaleProportionallyUpOrDown
            symbolConfiguration = .init(pointSize: 11, weight: .semibold)
            image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
            toolTip = accessibilityLabel
            translatesAutoresizingMaskIntoConstraints = false
            setContentCompressionResistancePriority(.required, for: .horizontal)
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: Self.side),
                heightAnchor.constraint(equalToConstant: Self.side)
            ])
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { fatalError() }

        private var symbolName: String {
            if isSummarizing { return "sparkles" }
            switch activity {
            case .working: return "arrow.triangle.2.circlepath"
            case .idle:    return "circle.fill"
            case .waiting: return "exclamationmark.circle.fill"
            }
        }

        private var accessibilityLabel: String {
            if isSummarizing { return "Summarizing" }
            switch activity {
            case .working: return "Working"
            case .idle:    return "Idle"
            case .waiting: return "Waiting for you"
            }
        }

        /// Colours the glyph. Waiting is the one state meant to catch the eye
        /// across a full window of rows, so it takes the warning colour.
        public func applyTheme(_ palette: SemanticPalette) {
            if isSummarizing {
                contentTintColor = palette.accentColor
                return
            }
            switch activity {
            case .working: contentTintColor = palette.accentColor
            case .idle:    contentTintColor = palette.tertiaryTextColor
            case .waiting: contentTintColor = palette.warningColor
            }
        }

        // MARK: - Animation

        // Layer animations are dropped when the view leaves the window, so they are
        // (re)installed on every move into one rather than once at construction.
        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                layer?.removeAnimation(forKey: Self.rotationKey)
                layer?.removeAnimation(forKey: Self.pulseKey)
            } else {
                startAnimation()
            }
        }

        public override func layout() {
            super.layout()
            // Rotate about the glyph's centre. Setting the anchor point moves the
            // layer, so its position is restored to the view's own centre after.
            guard let layer else { return }
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: frame.midX, y: frame.midY)
        }

        private func startAnimation() {
            guard let layer else { return }
            if isSummarizing || activity == .waiting {
                guard layer.animation(forKey: Self.pulseKey) == nil else { return }
                let pulse = CABasicAnimation(keyPath: "opacity")
                pulse.fromValue = 1.0
                pulse.toValue = 0.25
                pulse.duration = 0.7
                pulse.autoreverses = true
                pulse.repeatCount = .greatestFiniteMagnitude
                layer.add(pulse, forKey: Self.pulseKey)
                return
            }
            guard activity == .working else { return }
            guard layer.animation(forKey: Self.rotationKey) == nil else { return }
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -Double.pi * 2   // clockwise on screen (AppKit's y is up)
            spin.duration = 1.1
            spin.repeatCount = .greatestFiniteMagnitude
            spin.timingFunction = CAMediaTimingFunction(name: .linear)
            layer.add(spin, forKey: Self.rotationKey)
        }
    }
}
