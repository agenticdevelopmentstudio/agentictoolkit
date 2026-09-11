import AppKit
import AgenticToolkitPermissions

/// Card-style row showing one `Permission`'s live grant status, with a button
/// that triggers its grant flow. Reusable and free of any settings framework.
@MainActor
public final class PermissionRowView: NSView {

    public let permission: Permission
    private let checker: any PermissionChecking
    private let onAction: (Permission, PermissionStatus) -> Void

    /// The status the button is currently offering to act on.
    ///
    /// Handed to the action rather than re-read when it fires: the two can
    /// disagree — the user revokes the permission in System Settings while the
    /// panel is open — and re-reading turns a button labelled "Revoke" into a
    /// live consent prompt. What the user pressed is what should happen.
    private var displayedStatus: PermissionStatus = .undetermined

    private let titleLabel: NSTextField
    private let statusDot = NSView()
    private let statusLabel = NSTextField(labelWithString: "Checking…")
    private let actionButton = NSButton()

    public init(
        permission: Permission,
        checker: any PermissionChecking,
        onAction: @escaping (Permission, PermissionStatus) -> Void
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

    /// Test seam: fires the action the way the button does, so what the action
    /// is handed can be checked without an event.
    func performActionForTesting() { actionTapped() }

    /// Re-reads the grant state and updates the status dot + label.
    public func refresh() async {
        let status = await checker.status(permission)
        // A status read is a cross-process round trip — the Automation one is a
        // synchronous Apple Event with a timeout — and several refreshes can be
        // in flight at once. A cancelled one must not land: it is holding a
        // snapshot older than whatever replaced it.
        guard !Task.isCancelled else { return }
        apply(status: status)
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
        displayedStatus = status
        statusDot.layer?.backgroundColor = color.cgColor
        statusLabel.stringValue = text
        statusLabel.textColor = color
        // The button names what is left to do, which is not the same thing in
        // both directions. Granting can often happen inline, through the
        // system's own consent prompt; taking a grant back never can — macOS
        // offers no revoke API — so both titles lead to the one place that can
        // do either, and only the wording differs.
        actionButton.title = status == .granted
            ? Permission.ActionTitle.revoke
            : permission.actionTitle
    }

    /// The width every title is given, so that flipping between them doesn't
    /// reflow the card's description and rows in differing states still line
    /// their buttons up. Measured rather than spelled as a constant: these are
    /// words, and a number that fits them in English fits nothing else.
    /// A `let`, so the measurements happen once for the process rather
    /// than once per row — the answer depends only on the titles and the system
    /// font, and is the same for every row on screen.
    private static let widestActionWidth: CGFloat = {
        let probe = NSButton(title: "", target: nil, action: nil)
        probe.bezelStyle = .rounded
        probe.controlSize = .small
        return Permission.ActionTitle.all.reduce(0) { widest, title in
            probe.title = title
            return max(widest, probe.fittingSize.width)
        }
    }()

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
        button.title = permission.actionTitle
        button.target = self
        button.action = #selector(actionTapped)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        // Namespaced by permission: the panel shows one row per permission, so
        // an unqualified name would match several buttons at once and a test
        // could not say which it clicked. Named for the slot rather than for
        // one of its titles — the same button reads "Revoke" on a granted row,
        // and an identifier that said "open-settings" there would promise a
        // behaviour the element no longer has. Which is doubly true now that
        // the ungranted title is the permission's to choose.
        button.setAccessibilityIdentifier("permission.\(permission.identifierToken).action")
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
            // An exact width, not a floor plus content hugging. Both were
            // needed to stop the button stretching across a wide card, but as
            // two required rules they only agree in whichever title happens to
            // be the wider one — satisfiable today only because AppKit treats a
            // button's hugging as a preference rather than a ceiling. One
            // constraint sized to the longer title says the same thing without
            // resting on that.
            button.widthAnchor.constraint(equalToConstant: Self.widestActionWidth)
        ])
    }

    @objc private func actionTapped() {
        onAction(permission, displayedStatus)
    }
}
