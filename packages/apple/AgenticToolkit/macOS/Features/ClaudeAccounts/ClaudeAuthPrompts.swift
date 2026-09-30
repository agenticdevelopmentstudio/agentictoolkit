import AgenticToolkitCore
import AppKit
import Foundation

/// Every alert and modal the Claude authentication UI puts up.
///
/// They live together because they are the same conversation in four places —
/// the settings panel, both Claude menus and the quotas window's gear popover
/// all ask "log into this account?" and all report the same failures — and a
/// second copy of an alert is a second wording of a promise about somebody's
/// credentials.
@MainActor
public enum ClaudeAuthPrompts {

    // MARK: - Yes/no

    /// A confirmation with a named affirmative button. Returns true for it.
    public static func confirm(
        title: String,
        message: String,
        confirmTitle: String,
        cancelTitle: String = "Cancel",
        isDestructive: Bool = false
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = isDestructive ? .warning : .informational
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: cancelTitle)
        if isDestructive { alert.buttons.first?.hasDestructiveAction = true }
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// "Log into this account?" — the gear popover's and the Auth menu's shared
    /// wording, so rotating from either place reads the same.
    public static func confirmSwitch(to account: String) -> Bool {
        confirm(
            title: "Log into this account?",
            message: "Claude Code will run as \(account) everywhere on this Mac until you "
                + "switch again. A terminal that carries its own account in its "
                + "environment keeps the account it was given.",
            confirmTitle: "Yes",
            cancelTitle: "No")
    }

    /// Offered after a login the user asked for, when autosave is off.
    public static func confirmSaveLogin(named account: String) -> Bool {
        confirm(
            title: "Save these credentials?",
            message: "\(ClaudeAccounts.appName) can keep a copy of the login for \(account) so you can "
                + "switch back to it later. Without a saved copy, logging in as another "
                + "account replaces it and getting it back needs a fresh browser login.",
            confirmTitle: "Save",
            cancelTitle: "Don't Save")
    }

    /// Asked before `claude setup-token` runs, because minting is a browser
    /// round trip the user has to be ready for.
    public static func confirmMint() -> Bool {
        confirm(
            title: "Mint a new long-lived token?",
            message: "This runs `claude setup-token` in a terminal window. It opens your "
                + "browser to authorize as the account you are currently logged in as, "
                + "and the new token is stored under that account's name.",
            confirmTitle: "Mint",
            cancelTitle: "Cancel")
    }

    /// The warning the `-` button owes a reader before deleting the saved copy
    /// of the account they are logged in as: this removes the app's copy,
    /// and touches nothing Claude Code itself holds.
    public static func confirmForgetCurrentLogin(named account: String) -> Bool {
        confirm(
            title: "Delete the saved copy of \(account)?",
            message: "This is the account you are currently logged in to Claude Code as. "
                + "Deleting it here removes only the copy \(ClaudeAccounts.appName) saved — it does "
                + "not log you out and does not delete the token Claude Code manages. "
                + "You will not be able to switch back to this account without logging "
                + "in again.",
            confirmTitle: "Delete",
            cancelTitle: "Cancel",
            isDestructive: true)
    }

    public static func confirmForget(named account: String, kind: String) -> Bool {
        confirm(
            title: "Delete \(account)?",
            message: "The saved \(kind.lowercased()) credentials for this account are "
                + "removed from \(ClaudeAccounts.appName)'s store. This cannot be undone.",
            confirmTitle: "Delete",
            cancelTitle: "Cancel",
            isDestructive: true)
    }

    // MARK: - Reporting

    public static func report(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Shows `store.lastError` under `title` when there is one. Callers hand the
    /// result of a mutation straight to this rather than each deciding what a
    /// failure looks like.
    public static func reportFailure(title: String) {
        let message = ClaudeAuthStore.shared.lastError ?? "The command failed."
        report(title: title, message: message)
    }

    // MARK: - Add a long-lived token

    /// The "Add Long-Lived Token" dialog: an account name (prepopulated with
    /// whoever is logged in, since that is who a token in the clipboard almost
    /// always belongs to) and the token itself.
    public static func addLongLivedToken(defaultName: String) -> (name: String, token: String)? {
        let nameField = NSTextField(string: defaultName)
        nameField.placeholderString = "you@example.com"
        let tokenField = NSSecureTextField(string: "")
        tokenField.placeholderString = "sk-ant-…"

        let accessory = fieldGrid([
            ("Account name:", nameField),
            ("Token:", tokenField)
        ])

        let alert = NSAlert()
        alert.messageText = "Add a long-lived token"
        alert.informativeText = "Paste a token from `claude setup-token`. It is stored under "
            + "the account name you give it, and used whenever that account is pinned."
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = defaultName.isEmpty ? nameField : tokenField
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !token.isEmpty else {
            report(
                title: "Nothing was added",
                message: "An account name and a token are both needed.")
            return nil
        }
        return (name, token)
    }

    /// Shows a freshly minted token with a copy button. Its dismiss button is
    /// "Save" because dismissing it is what stores the token — there is nothing
    /// else to do with a token that has already been minted, and a "Cancel"
    /// here would throw away a credential that now exists.
    public static func presentMintedToken(_ token: String, account: String) {
        let field = NSTextField(labelWithString: token)
        field.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        field.isSelectable = true
        field.lineBreakMode = .byCharWrapping
        field.maximumNumberOfLines = 4
        field.preferredMaxLayoutWidth = 320

        let copy = copyButton(tooltip: "Copy the token") { copyToPasteboard(token) }

        let row = NSStackView(views: [field, copy])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.frame = NSRect(x: 0, y: 0, width: 360, height: 60)
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: 360),
            field.widthAnchor.constraint(equalToConstant: 320)
        ])

        let alert = NSAlert()
        alert.messageText = "New long-lived token"
        alert.informativeText = "Copy it now if you want it elsewhere — it is stored for "
            + "\(account), and \(ClaudeAccounts.appName) can show it to you again from the details pane."
        alert.accessoryView = row
        alert.addButton(withTitle: "Save")
        alert.runModal()
    }

    // MARK: - Shared pieces

    /// A right-aligned label column beside a field column — the shape every
    /// two-field dialog in AppKit wants and none of them get for free.
    public static func fieldGrid(_ rows: [(String, NSTextField)]) -> NSView {
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        for (title, field) in rows {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 260).isActive = true
            grid.addRow(with: [NSTextField(labelWithString: title), field])
        }
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: CGFloat(rows.count) * 32))
        host.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            grid.topAnchor.constraint(equalTo: host.topAnchor),
            grid.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        return host
    }

    /// A borderless symbol button running a closure — the shape every control
    /// next to a secret takes, because a row of credentials has no room for a
    /// button that spells out what it does.
    public static func iconButton(
        symbol: String, tooltip: String, action: @escaping () -> Void
    ) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        let proxy = ActionProxy(action: action)
        button.target = proxy
        button.action = #selector(ActionProxy.fire)
        // The button is the proxy's only owner: an alert's accessory view goes
        // away with the alert, and so must its target.
        objc_setAssociatedObject(
            button, ActionProxy.associationKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return button
    }

    /// The copy control used everywhere a secret is shown: an icon, never a
    /// button that says "copy".
    public static func copyButton(tooltip: String, action: @escaping () -> Void) -> NSButton {
        iconButton(symbol: "doc.on.doc", tooltip: tooltip, action: action)
    }

    public static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Runs `presentation` on the next run-loop turn.
    ///
    /// A modal entered inline from a SwiftUI update — or from a popover that is
    /// still closing — leaves its newly added AppKit controls unpainted. It has
    /// to get off that call stack, and it has to be `CFRunLoopPerformBlock` and
    /// not `DispatchQueue.main.async`: a modal loop never returns from the block
    /// that starts it, so a main-*queue* block that never returns stops the
    /// queue draining and strands every `await` inside the modal.
    public static func deferPresentation(_ presentation: @escaping () -> Void) {
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            MainActor.assumeIsolated { presentation() }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    /// Target for a control that wants a closure instead of a selector, kept
    /// alive by the control it serves (`target` is unowned, so something has to
    /// be).
    @MainActor
    public final class ActionProxy: NSObject {
        /// The address is the key; the byte it points at is never read.
        nonisolated(unsafe) static let associationKey =
            UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

        private let action: () -> Void

        public init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc public func fire() { action() }
    }
}
