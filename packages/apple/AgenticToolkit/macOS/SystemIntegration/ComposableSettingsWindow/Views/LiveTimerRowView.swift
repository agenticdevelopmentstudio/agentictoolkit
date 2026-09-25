import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI

extension ComposableSettings {

    /// One running timer: what it is, how long it has been going, and a way to
    /// stop it. Knows nothing about billing — the caller writes whatever it
    /// wants into `title` and `subtitle`.
    @MainActor
    public final class LiveTimerRowView: NSView {

        /// What one row shows.
        public struct Model: Equatable, Sendable {
            /// The caller's id for the run; reported back through `onStop`.
            public var id: String
            /// The main line — what is being timed.
            public var title: String
            /// A second, smaller line. Hidden when nil or empty.
            public var subtitle: String?
            /// When the run began; the clock counts from here.
            public var startedAt: Date
            /// Drawn as a filled dot for a hand-started run, a hollow one for a
            /// run started automatically. The tooltips are the row's
            /// `manualOriginTooltip` / `automaticOriginTooltip`.
            public var isManual: Bool

            /// A row model; `subtitle` is optional.
            public init(
                id: String,
                title: String,
                subtitle: String? = nil,
                startedAt: Date,
                isManual: Bool
            ) {
                self.id = id
                self.title = title
                self.subtitle = subtitle
                self.startedAt = startedAt
                self.isManual = isManual
            }
        }

        /// What the row currently shows. Replaced through `update(_:)`.
        public private(set) var model: Model

        /// The clock. Injected so a test can state the time instead of waiting
        /// for it.
        public var now: () -> Date = Date.init

        /// Called with the model's `id` when the stop button is pressed.
        public var onStop: ((String) -> Void)?

        /// The origin dot's tooltip for a hand-started run.
        public var manualOriginTooltip = "Started by hand" {
            didSet { apply(model) }
        }

        /// The origin dot's tooltip for a run that started on its own. What
        /// started it is the caller's vocabulary, so the caller may say.
        public var automaticOriginTooltip = "Started automatically" {
            didSet { apply(model) }
        }

        /// The ● / ○ dot: hand-started or automatic.
        public let originLabel = ThemedLabel(string: "", role: .secondaryText, textRole: .caption)
        /// Shows `model.title`.
        public let titleLabel = ThemedLabel(string: "", role: .primaryText, textRole: .body)
        /// Shows `model.subtitle`.
        public let subtitleLabel = ThemedLabel(string: "", role: .secondaryText, textRole: .caption)
        /// `.code`, so the digits are monospaced and the row does not twitch
        /// sideways every time the seconds roll over.
        public let elapsedLabel = ThemedLabel(string: "", role: .primaryText, textRole: .code)
        /// Reports through `onStop`.
        public let stopButton: NSButton

        /// What the clock reads right now, e.g. `"1:02:03"`.
        public var elapsedText: String { elapsedLabel.stringValue }

        /// A row showing `model`, its clock already set from `now`.
        public init(model: Model) {
            self.model = model
            self.stopButton = NSButton(
                title: "",
                image: .symbol(named: "stop.fill", accessibilityDescription: "Stop timer"),
                target: nil,
                action: nil
            )

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            stopButton.bezelStyle = .accessoryBar
            stopButton.imagePosition = .imageOnly
            stopButton.target = self
            stopButton.action = #selector(stopPressed)
            stopButton.toolTip = "Stop this timer"

            titleLabel.lineBreakMode = .byTruncatingTail
            subtitleLabel.lineBreakMode = .byTruncatingTail
            // Below the labels' hugging, so a long project name gives way
            // before the clock does.
            titleLabel.setContentCompressionResistancePriority(.init(499), for: .horizontal)
            subtitleLabel.setContentCompressionResistancePriority(.init(499), for: .horizontal)
            elapsedLabel.setContentHuggingPriority(.required, for: .horizontal)

            let text = NSStackView(views: [titleLabel, subtitleLabel])
            text.orientation = .vertical
            text.alignment = .leading
            text.spacing = 2
            text.translatesAutoresizingMaskIntoConstraints = false

            let spacing = SettingsLayout.default[.rowSpacing]
            let row = NSStackView(views: [originLabel, text, elapsedLabel, stopButton])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = spacing
            row.translatesAutoresizingMaskIntoConstraints = false
            addSubview(row)

            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: leadingAnchor),
                row.trailingAnchor.constraint(equalTo: trailingAnchor),
                row.topAnchor.constraint(equalTo: topAnchor),
                row.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])

            apply(model)
            refreshElapsed()
        }

        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// Swap in a new model — a rename, or a different run reusing this row.
        public func update(_ model: Model) {
            self.model = model
            apply(model)
            refreshElapsed()
        }

        /// Recompute the clock. Called by whoever owns the `LiveTimerTicker`.
        public func refreshElapsed() {
            let seconds = max(0, Int(now().timeIntervalSince(model.startedAt)))
            elapsedLabel.stringValue = DurationFormatter.clock(seconds: seconds)
        }

        private func apply(_ model: Model) {
            originLabel.stringValue = model.isManual ? "●" : "○"
            originLabel.toolTip = model.isManual ? manualOriginTooltip : automaticOriginTooltip
            titleLabel.stringValue = model.title
            subtitleLabel.stringValue = model.subtitle ?? ""
            subtitleLabel.isHidden = (model.subtitle ?? "").isEmpty
            _ = stopButton.accessibilityID("timer.\(model.id).stop")
            _ = elapsedLabel.accessibilityID("timer.\(model.id).elapsed")
        }

        @objc private func stopPressed() {
            onStop?(model.id)
        }
    }

    /// One timer for a whole list of `LiveTimerRowView`s.
    ///
    /// Separate from the row so the rows stay a rendering concern and the
    /// scheduling happens once. `.common` run-loop mode, so the clocks keep
    /// moving while a menu is open or a list is being scrolled.
    @MainActor
    public final class LiveTimerTicker {

        /// Called on the main actor once per interval while started.
        public var onTick: (() -> Void)?

        private let interval: TimeInterval
        private var timer: Timer?

        /// - Parameter interval: seconds between ticks.
        public init(interval: TimeInterval = 1.0) {
            self.interval = interval
        }

        isolated deinit {
            timer?.invalidate()
        }

        /// Starts ticking. Calling it again while running changes nothing.
        public func start() {
            guard timer == nil else { return }
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.onTick?() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        /// Stops ticking. Safe to call when not started.
        public func stop() {
            timer?.invalidate()
            timer = nil
        }

        /// Deliver one tick synchronously. A test asserts on the tick, not on
        /// the run loop having got round to it.
        public func fireForTests() {
            guard timer != nil else { return }
            onTick?()
        }
    }
}
