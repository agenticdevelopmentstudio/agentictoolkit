#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AgenticDeveloperToolkit
import AgenticDeveloperToolkitUI
import AppKit

/// One row in an `HTDVRailView`: optional icon, title, optional subtitle, optional badge, optional chevron.
public final class HTDVRailCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("HTDVRailCellView")

    let iconView = NSImageView()
    let titleLabel = ThemedLabel()
    let subtitleLabel = ThemedLabel(role: .secondaryText, textRole: .caption)
    let badgeLabel = ThemedLabel(role: .secondaryText, textRole: .caption)
    let badgeDot = ThemedBackgroundView(role: .secondaryText)
    let chevron = NSImageView()

    /// The badge dot's colour is a *value* the row carries, not a role the cell
    /// has — so it is kept here and re-resolved on every theme change, the way
    /// every other painted colour in this cell is. Held as the semantic badge
    /// rather than an `NSColor` for the same reason: a colour resolved once
    /// would still be the old theme's after a swap.
    private var badgeColor: HTDVBadgeColor? {
        didSet { badgeDot.colorOverride = badgeColor.map { palette.nsColor($0.themeRole) } }
    }

    private var palette: SemanticPalette = ThemePaletteObserver.currentPalette

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func build() {
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.lineBreakMode = .byTruncatingTail
        // The count badge was the one monospaced-digit font here, so digits
        // would not jitter as a count ticked. `code` is the theme's monospaced
        // role, which keeps that property and gains the theme's family and
        // scale.
        badgeLabel.textRole = .code
        badgeDot.wantsLayer = true
        badgeDot.layer?.cornerRadius = 4
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Shows more")
        // Tints, not text, so neither has a themed subclass to inherit — but
        // both are painted colours the theme owns, and a cell is reused, so
        // they re-resolve on every change rather than once at build.
        chevron.observeTheme { chevron, palette in
            chevron.contentTintColor = palette.tertiaryTextColor
        }
        iconView.observeTheme { icon, palette in
            icon.contentTintColor = palette.secondaryTextColor
        }
        // The cell itself watches the palette so the badge dot's *value*
        // colour — which no themed subclass can resolve, since it comes from
        // the row's content — is recomputed on a theme swap too.
        observeTheme { cell, palette in
            cell.palette = palette
            cell.badgeDot.colorOverride = cell.badgeColor.map { palette.nsColor($0.themeRole) }
        }

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
            badgeColor = nil
            badgeLabel.stringValue = String(count)
            badgeLabel.isHidden = false
            badgeDot.isHidden = true
        case .dot(let color):
            badgeColor = color
            badgeDot.isHidden = false
            badgeLabel.stringValue = ""
            badgeLabel.isHidden = true
        case nil:
            badgeColor = nil
            badgeLabel.stringValue = ""
            badgeLabel.isHidden = true
            badgeDot.isHidden = true
        }
        chevron.isHidden = !content.isDisclosing
    }
}
#endif
