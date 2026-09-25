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
        /// Shows a folder chooser on a window and answers with the folder, or
        /// nil when it was cancelled or there was no window to show it on.
        public typealias ChooseFolder = @MainActor (NSWindow?, @escaping (URL?) -> Void) -> Void

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

        /// `confirmDestructive`, awaited: true only when the destructive button
        /// was clicked.
        public static func confirmDestructive(
            _ question: String,
            detail: String,
            actionTitle: String = "Delete",
            on window: NSWindow?
        ) async -> Bool {
            await withCheckedContinuation { continuation in
                confirmDestructive(question, detail: detail, actionTitle: actionTitle, on: window) {
                    continuation.resume(returning: $0)
                }
            }
        }

        /// Awaits an injected ``Confirm`` — the form a window takes its
        /// confirmation in so a test can answer it — the way
        /// `confirmDestructive(_:detail:actionTitle:on:) async` awaits the sheet.
        public static func ask(_ confirm: Confirm, _ question: String, detail: String) async -> Bool {
            await withCheckedContinuation { continuation in
                confirm(question, detail) { continuation.resume(returning: $0) }
            }
        }

        /// A one-folder chooser, as a sheet on `window`, never app-modal — the
        /// same rule as every other sheet here. `prompt` titles the choose
        /// button; `message` says what the folder is for. With no window the
        /// answer is nil: a chooser with nothing to attach to would have to be
        /// app-modal.
        public static func chooseFolder(
            on window: NSWindow?,
            prompt: String,
            message: String,
            _ answer: @escaping (URL?) -> Void
        ) {
            guard let window else {
                log.warning("folder chooser with no window, cancelled: \(message, privacy: .public)")
                answer(nil)
                return
            }
            let panel = makeFolderPanel(prompt: prompt, message: message)
            panel.beginSheetModal(for: window) { answer($0 == .OK ? panel.url : nil) }
        }

        /// The panel `chooseFolder` shows, built but not presented.
        static func makeFolderPanel(prompt: String, message: String) -> NSOpenPanel {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = prompt
            panel.message = message
            return panel
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
