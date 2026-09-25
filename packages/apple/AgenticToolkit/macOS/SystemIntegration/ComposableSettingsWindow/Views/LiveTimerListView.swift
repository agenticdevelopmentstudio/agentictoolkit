import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI

extension ComposableSettings {

    /// A list of ``LiveTimerRowView``s whose clocks move once a second, with a
    /// line of text when nothing is running.
    ///
    /// Rows are kept by id across `setTimers`, so a timer that is still
    /// running keeps its row and its clock never jumps; rows are rebuilt only
    /// when timers start or stop. Only a manual timer shows a stop button —
    /// an automatic one ends on its own.
    ///
    /// The list owns its ``LiveTimerTicker`` and runs it only while it can be
    /// seen: in a window that is on screen and not covered, with something
    /// running. A window buried under others or left on another Space is open
    /// but not seen, and gets no `viewDidDisappear`, so occlusion is watched
    /// too; when the window is seen again the clocks catch up at once rather
    /// than a second later.
    @MainActor
    public final class LiveTimerListView: NSView {

        /// Stop was clicked on the row with this id.
        public var onStop: ((String) -> Void)?
        /// Runs after the rows' clocks move, for anything else on screen that
        /// counts the same seconds.
        public var onTick: (() -> Void)?

        /// The clock the rows count against. Injected so a test can state the
        /// time instead of waiting for it.
        public var now: () -> Date = Date.init {
            didSet { rows.forEach { $0.now = { [weak self] in self?.now() ?? Date() } } }
        }
        /// The tooltip on an automatic row's origin mark.
        public var automaticOriginTooltip = "Started automatically" {
            didSet { rows.forEach { $0.automaticOriginTooltip = automaticOriginTooltip } }
        }
        /// Whether any part of the window can be seen. Injected so a test can
        /// cover a window that is open but covered.
        public var windowIsVisible: () -> Bool

        /// The timers shown, in order.
        public private(set) var timers: [LiveTimerRowView.Model] = []
        /// One row per timer, in the same order.
        public private(set) var rows: [LiveTimerRowView] = []
        public let stack = NSStackView()
        public let emptyLabel: ThemedLabel
        /// Moves every clock once a second while the list can be seen.
        public let ticker: LiveTimerTicker

        private weak var observedWindow: NSWindow?

        /// - Parameters:
        ///   - emptyMessage: shown while nothing is running.
        ///   - interval: seconds between clock moves.
        public init(emptyMessage: String, interval: TimeInterval = 1) {
            emptyLabel = ThemedLabel(string: emptyMessage, role: .secondaryText, textRole: .body)
            ticker = LiveTimerTicker(interval: interval)
            windowIsVisible = { true }
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false
            windowIsVisible = { [weak self] in
                guard let window = self?.window else { return false }
                return window.occlusionState.contains(.visible)
            }

            stack.orientation = .vertical
            stack.alignment = .width
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(emptyLabel)
            addSubview(stack)
            Self.pinToEdges(stack, of: self)

            ticker.onTick = { [weak self] in self?.tick() }
        }

        public override init(frame frameRect: NSRect) {
            fatalError("init(frame:) has not been implemented")
        }

        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: - Content

        /// Shows `timers`, keeping the row of every timer that is still listed.
        public func setTimers(_ timers: [LiveTimerRowView.Model]) {
            self.timers = timers
            if timers.map(\.id) == rows.map(\.model.id) {
                for (row, model) in zip(rows, timers) where row.model != model {
                    row.update(model)
                }
            } else {
                var kept: [String: LiveTimerRowView] = [:]
                for row in rows {
                    kept[row.model.id] = row
                    stack.removeArrangedSubview(row)
                    row.removeFromSuperview()
                }
                rows = timers.map { model in
                    let row = kept[model.id] ?? makeRow(model)
                    if row.model != model { row.update(model) }
                    row.stopButton.isHidden = !model.isManual
                    stack.addArrangedSubview(row)
                    return row
                }
            }
            emptyLabel.isHidden = !timers.isEmpty
            updateTicker()
        }

        private func makeRow(_ model: LiveTimerRowView.Model) -> LiveTimerRowView {
            let row = LiveTimerRowView(model: model)
            row.automaticOriginTooltip = automaticOriginTooltip
            row.now = { [weak self] in self?.now() ?? Date() }
            row.onStop = { [weak self] id in self?.onStop?(id) }
            return row
        }

        // MARK: - Ticking

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observedWindow {
                NotificationCenter.default.removeObserver(
                    self, name: NSWindow.didChangeOcclusionStateNotification, object: observedWindow)
            }
            observedWindow = window
            if let window {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(occlusionChanged(_:)),
                    name: NSWindow.didChangeOcclusionStateNotification, object: window)
            }
            visibilityChanged()
        }

        @objc private func occlusionChanged(_ note: Notification) {
            visibilityChanged()
        }

        /// Starts or stops the clocks for whether the list can now be seen and,
        /// when it can, brings them up to date at once.
        public func visibilityChanged() {
            updateTicker()
            if isSeen { tick() }
        }

        private var isSeen: Bool {
            !timers.isEmpty && windowIsVisible()
        }

        private func updateTicker() {
            if isSeen { ticker.start() } else { ticker.stop() }
        }

        private func tick() {
            rows.forEach { $0.refreshElapsed() }
            onTick?()
        }
    }
}
