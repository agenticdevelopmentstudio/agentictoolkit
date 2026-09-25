import AppKit
import OSLog

extension ComposableSettings {

    /// The two sheets a record window needs: "are you sure?" before a delete,
    /// and "that didn't save". Always attached to a window as a sheet, never
    /// app-modal (see `NSAlertMessagePresenter` for why).
    @MainActor
    public enum Alerts {

        /// Asks a question whose yes is destructive. The arguments are the
        /// question, the explanation below it, and the answer callback.
        public typealias Confirm = @MainActor (String, String, @escaping (Bool) -> Void) -> Void
        /// Says that something the user did was not saved.
        public typealias Report = @MainActor (String) -> Void

        private static let log = Logger(subsystem: "AgenticToolkit", category: "ComposableSettings.Alerts")

        /// A warning sheet with a destructive `actionTitle` button and Cancel.
        /// Cancel is the default, so Return never deletes, and Esc cancels too.
        /// With no window, the answer is no.
        public static func confirmDestructive(
            _ question: String,
            detail: String,
            actionTitle: String = "Delete",
            on window: NSWindow?,
            _ answer: @escaping (Bool) -> Void
        ) {
            guard let window else {
                log.warning("confirmation with no window, declined: \(question, privacy: .public)")
                answer(false)
                return
            }
            let alert = makeDestructiveAlert(question, detail: detail, actionTitle: actionTitle)
            alert.beginSheetModal(for: window) { answer($0 == .alertFirstButtonReturn) }
        }

        /// The sheet `confirmDestructive` shows, built but not presented.
        ///
        /// A button carries one key equivalent. NSAlert gives a button titled
        /// Cancel the Esc key only while its key equivalent is unset, so making
        /// Cancel answer Return takes Esc away from it — and from the sheet,
        /// which then has no keyboard way out but the destructive-free Return.
        /// A second, invisible button owns Esc and clicks Cancel, so both keys
        /// decline. It is zero-size rather than hidden because a hidden button
        /// never sees its key equivalent.
        static func makeDestructiveAlert(_ question: String, detail: String, actionTitle: String) -> NSAlert {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = question
            alert.informativeText = detail
            let action = alert.addButton(withTitle: actionTitle)
            action.hasDestructiveAction = true
            action.keyEquivalent = ""
            let cancel = alert.addButton(withTitle: "Cancel")
            cancel.keyEquivalent = "\r"
            alert.layout()

            let escape = NSButton(frame: .zero)
            escape.isBordered = false
            escape.title = ""
            escape.keyEquivalent = "\u{1b}"
            escape.target = cancel
            escape.action = #selector(NSButton.performClick(_:))
            escape.setAccessibilityElement(false)
            alert.window.contentView?.addSubview(escape)
            return alert
        }

        /// A warning sheet with the message and OK. With no window, it is logged.
        public static func report(_ message: String, on window: NSWindow?) {
            let text = message.trimmingCharacters(in: .whitespaces)
            guard let window else {
                log.warning("report with no window: \(text, privacy: .public)")
                return
            }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = text
            alert.beginSheetModal(for: window)
        }
    }
}
