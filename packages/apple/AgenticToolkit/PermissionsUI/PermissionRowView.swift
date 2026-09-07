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

        let button = NSButton(title: "Open Settings", target: self, action: #selector(actionTapped))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        // Namespaced by permission: the panel shows one row per pending
        // permission, so an unqualified "open-settings" would name several
        // buttons at once and a test could not say which it clicked.
        button.setAccessibilityIdentifier("permission.\(permission.identifierToken).open-settings")
        setAccessibilityIdentifier("permission.\(permission.identifierToken).row")

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
            button.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @objc private func actionTapped() {
        onAction(permission)
    }
}
