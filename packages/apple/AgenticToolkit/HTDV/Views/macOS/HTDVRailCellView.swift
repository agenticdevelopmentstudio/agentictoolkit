#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

public enum HTDVBadgeColorMapping {
    public static func nsColor(_ color: HTDVBadgeColor) -> NSColor {
        switch color {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .gray: .systemGray
        }
    }
}

/// One row in an `HTDVRailView`: optional icon, title, optional subtitle, optional badge, optional chevron.
public final class HTDVRailCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("HTDVRailCellView")

    let iconView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let subtitleLabel = NSTextField(labelWithString: "")
    let badgeLabel = NSTextField(labelWithString: "")
    let badgeDot = NSView()
    let chevron = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func build() {
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        badgeLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        badgeLabel.textColor = .secondaryLabelColor
        badgeDot.wantsLayer = true
        badgeDot.layer?.cornerRadius = 4
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Shows more")
        chevron.contentTintColor = .tertiaryLabelColor
        iconView.contentTintColor = .secondaryLabelColor

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        let row = NSStackView(views: [iconView, textStack, badgeDot, badgeLabel, chevron])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            badgeDot.widthAnchor.constraint(equalToConstant: 8),
            badgeDot.heightAnchor.constraint(equalToConstant: 8)
        ])
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    public func apply(_ content: HTDVCellContent) {
        titleLabel.stringValue = content.label
        subtitleLabel.stringValue = content.sublabel ?? ""
        subtitleLabel.isHidden = content.sublabel == nil
        if let name = content.systemImage {
            iconView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            iconView.isHidden = false
        } else {
            iconView.image = nil
            iconView.isHidden = true
        }
        switch content.badge {
        case .count(let count):
            badgeLabel.stringValue = String(count)
            badgeLabel.isHidden = false
            badgeDot.isHidden = true
        case .dot(let color):
            badgeDot.layer?.backgroundColor = HTDVBadgeColorMapping.nsColor(color).cgColor
            badgeDot.isHidden = false
            badgeLabel.stringValue = ""
            badgeLabel.isHidden = true
        case nil:
            badgeLabel.stringValue = ""
            badgeLabel.isHidden = true
            badgeDot.isHidden = true
        }
        chevron.isHidden = !content.isDisclosing
    }
}
#endif
