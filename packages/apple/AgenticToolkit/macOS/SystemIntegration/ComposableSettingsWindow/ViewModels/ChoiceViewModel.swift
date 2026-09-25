import AgenticToolkitCore

extension ComposableSettings {

    public class ChoiceViewModel<Value: Codable & Sendable & Equatable>: ViewModel<Value> {

        /// The items offered. Settable because some lists are records: a
        /// project's client is picked from clients that come and go while the
        /// pane is open. Only `PopupMenuChoiceView` follows a change; the radio
        /// and slider views are laid out once for a fixed set of answers.
        public var choices: [Choice] {
            didSet { onChoicesChange?() }
        }

        /// Fired after `choices` or `commands` is replaced.
        public var onChoicesChange: (() -> Void)?

        /// Actions offered after the choices, below a separator — "Add
        /// Client…" at the foot of a client chooser. Picking one runs it and
        /// leaves the stored value, and the selection, where they were: a
        /// command is never a value, so no sentinel value can leak into the
        /// setting. Only `PopupMenuChoiceView` shows them.
        public var commands: [Command] = [] {
            didSet { onChoicesChange?() }
        }

        /// Replaces `choices` only when the list really differs — a label, a
        /// value, an icon or the order changed. A caller that re-reads its
        /// records on every poll otherwise rebuilds the popup's menu each time,
        /// which closes it under a person mid-pick. Answers whether it replaced.
        @discardableResult
        public func updateChoices(_ newChoices: [Choice]) -> Bool {
            if newChoices == choices { return false }
            choices = newChoices
            return true
        }

        public init(
            title: String,
            setting: UserSetting<Value>,
            choices: [Choice],
            explanation: String? = nil
        ) {
            self.choices = choices
            super.init(title: title, setting: setting, explanation: explanation)
        }

        /// A choice row bound to something other than `UserDefaults`.
        public init(
            title: String,
            choices: [Choice],
            get: @escaping () -> Value,
            set: @escaping (Value) -> Void,
            explanation: String? = nil
        ) {
            self.choices = choices
            super.init(title: title, get: get, set: set, explanation: explanation)
        }
    }
}

extension ComposableSettings.ChoiceViewModel {

    /// A label/value pair for a `ChoiceViewModel`. Optionally carries a system
    /// symbol name; views that support iconography render it next to the label.
    public struct Choice: Sendable, Equatable {
        public let label: String
        public let value: Value
        public let imageSystemName: String?

        public init(label: String, value: Value, imageSystemName: String? = nil) {
            self.label = label
            self.value = value
            self.imageSystemName = imageSystemName
        }
    }

    /// An action offered in a choice list — see `ChoiceViewModel.commands`.
    public struct Command {
        /// The menu item's title, e.g. "Add Client…".
        public let title: String
        /// Run when the item is picked.
        public let action: @MainActor () -> Void

        public init(title: String, action: @escaping @MainActor () -> Void) {
            self.title = title
            self.action = action
        }
    }
}
