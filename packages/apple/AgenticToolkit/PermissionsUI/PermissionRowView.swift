import AppKit
import AgenticToolkitPermissions

/// Card-style row showing one `Permission`'s live grant status, with a button
/// that triggers its grant flow. Reusable and free of any settings framework.
@MainActor
public final class PermissionRowView: NSView {

    public let permission: Permission
    private let checker: any PermissionChecking
    private let onAction: (Permission) -> Void

    private let titleLabel: NSTextField
    private let statusDot = NSView()
    private let statusLabel = NSTextField(labelWithString: "Checking…")
    private let actionButton = NSButton()

    public init(
        permission: Permission,
        checker: any PermissionChecking,
        onAction: @escaping (Permission) -> Void
    ) {
        self.permission = permission
        self.checker = checker
        self.onAction = onAction
        self.titleLabel = NSTextField(labelWithString: permission.displayName)
        super.init(frame: .zero)
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Test seam: current status label text.
    var statusText: String { statusLabel.stringValue }

    /// Test seam: current action-button title.
    var actionTitle: String { actionButton.title }

    /// Re-reads the grant state and updates the status dot + label.
    public func refresh() async {
        apply(status: await checker.status(permission))
    }

    private func apply(status: PermissionStatus) {
        let color: NSColor
        let text: String
        switch status {
        case .granted:
            color = .systemGreen
            text = "Granted"
        case .denied:
            color = .systemOrange
            text = "Not Granted"
        case .undetermined:
            // Can't prove granted or denied (e.g. the Automation target app isn't
            // running) — show a neutral state rather than a misleading "Not Granted".
            color = .secondaryLabelColor
            text = "Unknown"
        }
        statusDot.layer?.backgroundColor = color.cgColor
        statusLabel.stringValue = text
        statusLabel.textColor = color
        // The button names what is left to do, which is not the same thing in
        // both directions. Granting can often happen inline, through the
        // system's own consent prompt; taking a grant back never can — macOS
        // offers no revoke API — so both titles lead to the one place that can
        // do either, and only the wording differs.
        actionButton.title = status == .granted ? Self.revokeTitle : Self.grantTitle
    }

    /// What the button says while the permission is not granted. Named
    /// "Open Settings" rather than "Grant" because that is where every one of
    /// these ends up, prompt or no prompt.
    private static let grantTitle = "Open Settings"
    private static let revokeTitle = "Revoke"

    /// The width both titles are given, so that flipping between them doesn't
    /// reflow the card's description and rows in differing states still line
    /// their buttons up. Measured rather than spelled as a constant: these are
    /// words, and a number that fits them in English fits nothing else.
    private static func widestActionWidth() -> CGFloat {
        let probe = NSButton(title: "", target: nil, action: nil)
        probe.bezelStyle = .rounded
        probe.controlSize = .small
        return [grantTitle, revokeTitle].reduce(0) { widest, title in
            probe.title = title
            return max(widest, probe.fittingSize.width)
        }
    }

    private func buildLayout() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.03).cgColor
        layer?.cornerRadius = 8
        layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor
        layer?.borderWidth = 0.5

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: permission.systemImageName, accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 16, weight: .regular)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = NSTextField(wrappingLabelWithString: permission.explanation)
        descLabel.font = .systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusRow = NSStackView(views: [statusDot, statusLabel])
        statusRow.orientation = .horizontal
        statusRow.spacing = 6
        statusRow.alignment = .centerY
        statusRow.translatesAutoresizingMaskIntoConstraints = false

        let button = actionButton
        button.title = Self.grantTitle
        button.target = self
        button.action = #selector(actionTapped)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        // Hug the title, so the button stays button-sized however wide the row
        // gets. Without this it and the wrapping description both stretch to
        // fill, and the card in a wide window grows a button several inches
        // long. The width floor below keeps that hug from re-flowing the
        // description every time the title changes.
        button.setContentHuggingPriority(.required, for: .horizontal)
        // Namespaced by permission: the panel shows one row per pending
        // permission, so an unqualified "open-settings" would name several
        // buttons at once and a test could not say which it clicked.
        button.setAccessibilityIdentifier("permission.\(permission.identifierToken).open-settings")
        // The row itself carries no identifier. A plain `NSView` is not an
        // accessibility element, so an identifier set on one is never
        // published — `XCUIElement` cannot see it, and nothing here calls
        // `setAccessibilityElement(true)`. Making the container a group to
        // hold a name would add an element VoiceOver has to step through and
        // no test asks for; the button, which is a real element, is the
        // per-permission handle.

        addSubview(icon)
        addSubview(titleLabel)
        addSubview(descLabel)
        addSubview(statusRow)
        addSubview(button)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 72),

            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            descLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            descLabel.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -12),

            statusRow.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusRow.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 6),
            statusRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),

            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.widestActionWidth())
        ])
    }

    @objc private func actionTapped() {
        onAction(permission)
    }
}
