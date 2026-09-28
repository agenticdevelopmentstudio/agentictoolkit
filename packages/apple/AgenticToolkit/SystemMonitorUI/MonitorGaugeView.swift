import AppKit
import AgenticDeveloperToolkit
import AgenticDeveloperToolkitUI
import AgenticToolkitSystemMonitor

/// A thin horizontal bar filled to a reading's fraction, in its level's color.
/// With no fraction it shows the empty track.
@MainActor
public final class MonitorGaugeView: NSView, Themeable {

    public static let height: CGFloat = 6

    public private(set) var fraction: Double?
    public private(set) var level: MonitorLevel = .unknown

    let fillLayer = CALayer()
    private var observer: ThemePaletteObserver?

    public init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Self.height / 2
        layer?.masksToBounds = true
        fillLayer.cornerRadius = Self.height / 2
        layer?.addSublayer(fillLayer)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.levelIndicator)
        observer = ThemePaletteObserver(host: self) { [weak self] palette in self?.applyTheme(palette) }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    public func update(fraction: Double?, level: MonitorLevel) {
        self.fraction = fraction
        self.level = level
        setAccessibilityValue(fraction.map { Int(($0 * 100).rounded()) })
        applyTheme(resolvedThemeScope.palette)
        needsLayout = true
    }

    public func applyTheme(_ palette: SemanticPalette) {
        layer?.backgroundColor = palette.nsColor(.controlBackground).cgColor
        fillLayer.backgroundColor = palette.nsColor(level.themeRole).cgColor
    }

    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let width = bounds.width * CGFloat(fraction ?? 0)
        fillLayer.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        CATransaction.commit()
    }
}
