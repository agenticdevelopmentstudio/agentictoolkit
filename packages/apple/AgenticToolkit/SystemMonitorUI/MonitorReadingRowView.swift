import AppKit
import AgenticDeveloperToolkit
import AgenticDeveloperToolkitUI
import AgenticToolkitSystemMonitor

/// One monitor, as a card: a level dot and the title, the value on the right,
/// the detail under it, and a gauge along the bottom.
@MainActor
public final class MonitorReadingRowView: NSView, Themeable {

    public private(set) var reading: MonitorReading

    let titleLabel = ThemedLabel(role: .primaryText, textRole: .heading)
    let valueLabel = ThemedLabel(role: .primaryText, textRole: .body, weight: .semibold)
    let detailLabel = ThemedLabel(role: .secondaryText, textRole: .caption)
    let gauge = MonitorGaugeView()
    let dot = NSView()
    private let card = ThemedBox(fill: .surface, stroke: .outline, cornerRadius: 8)
    private var observer: ThemePaletteObserver?

    static let dotSize: CGFloat = 10

    public init(reading: MonitorReading) {
        self.reading = reading
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildLayout()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        observer = ThemePaletteObserver(host: self) { [weak self] palette in self?.applyTheme(palette) }
        update(with: reading)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    public func update(with reading: MonitorReading) {
        self.reading = reading
        titleLabel.stringValue = reading.title
        valueLabel.stringValue = reading.value
        detailLabel.stringValue = reading.detail
        detailLabel.isHidden = reading.detail.isEmpty
        gauge.update(fraction: reading.fraction, level: reading.level)
        let level = reading.level.accessibilityLabel
        setAccessibilityLabel("\(reading.title), \(level): \(reading.value). \(reading.detail)")
        applyTheme(resolvedThemeScope.palette)
    }

    public func applyTheme(_ palette: SemanticPalette) {
        dot.layer?.backgroundColor = palette.nsColor(reading.level.themeRole).cgColor
    }

    private func buildLayout() {
        dot.wantsLayer = true
        dot.layer?.cornerRadius = Self.dotSize / 2
        dot.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.alignment = .right
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.lineBreakMode = .byTruncatingTail
        detailLabel.lineBreakMode = .byTruncatingTail

        let header = NSStackView(views: [dot, titleLabel, valueLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.setHuggingPriority(.defaultLow, for: .horizontal)

        let column = NSStackView(views: [header, detailLabel, gauge])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.setCustomSpacing(10, after: detailLabel)
        column.translatesAutoresizingMaskIntoConstraints = false

        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(column)
        addSubview(card)

        let inset: CGFloat = 12
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),

            column.topAnchor.constraint(equalTo: card.topAnchor, constant: inset),
            column.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -inset),
            column.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: inset),
            column.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inset),

            header.widthAnchor.constraint(equalTo: column.widthAnchor),
            gauge.widthAnchor.constraint(equalTo: column.widthAnchor),
            // Under the title, past the dot, so the detail lines up with it.
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: column.trailingAnchor),

            dot.widthAnchor.constraint(equalToConstant: Self.dotSize),
            dot.heightAnchor.constraint(equalToConstant: Self.dotSize)
        ])
    }
}
