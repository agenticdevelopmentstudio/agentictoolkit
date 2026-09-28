import AppKit
import AgenticDeveloperToolkit
import AgenticDeveloperToolkitUI
import AgenticToolkitMacOS
import AgenticToolkitSystemMonitor

/// Every monitor's latest reading, one card per monitor, over the theme's
/// window background, with when they were last sampled above them.
@MainActor
public final class SystemStatusView: NSView {

    /// The cards, in the readings' order. When the set of ids changes the
    /// cards are rebuilt, so the order always matches the readings'.
    public private(set) var rows: [MonitorReadingRowView] = []

    let updatedLabel = ThemedLabel(string: "Waiting for the first sample…", role: .tertiaryText, textRole: .caption)
    private let background = ThemedBackgroundView(role: .windowBackground)
    private let stack = NSStackView()
    private let scrollView = ComposableSettings.PanelScrollView()

    private static let timeFormat = Date.FormatStyle(date: .omitted, time: .standard)

    public init() {
        super.init(frame: .zero)
        buildLayout()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    /// Shows `readings`, and `refreshedAt` as the time they were sampled —
    /// `nil` before the first sample, which leaves the waiting message up.
    public func show(_ readings: [MonitorReading], refreshedAt: Date?) {
        if rows.map(\.reading.id) == readings.map(\.id) {
            for (row, reading) in zip(rows, readings) { row.update(with: reading) }
        } else {
            rows.forEach { $0.removeFromSuperview() }
            rows = readings.map { MonitorReadingRowView(reading: $0) }
            for row in rows {
                stack.addArrangedSubview(row)
                let insets = stack.edgeInsets.left + stack.edgeInsets.right
                row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -insets).isActive = true
            }
        }
        if let refreshedAt {
            updatedLabel.stringValue = "Updated \(refreshedAt.formatted(Self.timeFormat))"
        }
    }

    private func buildLayout() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.addArrangedSubview(updatedLabel)
        stack.setCustomSpacing(14, after: updatedLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor)
        ])
        scrollView.setContent(content)

        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
}
