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

        /// Fired after `choices` is replaced.
        public var onChoicesChange: (() -> Void)?

        /// Replaces `choices` only when the list really differs — a label, a
        /// value, an icon or the order changed. A caller that re-reads its
        /// records on every poll otherwise rebuilds the popup's menu each time,
        /// which closes it under a person mid-pick. Answers whether it replaced.
        @discardableResult
        public func updateChoices(_ newChoices: [Choice]) -> Bool {
            let same = newChoices.count == choices.count
                && zip(newChoices, choices).allSatisfy { lhs, rhs in
                    lhs.label == rhs.label && lhs.value == rhs.value
                        && lhs.imageSystemName == rhs.imageSystemName
                }
            if same { return false }
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
    public struct Choice: Sendable {
        public let label: String
        public let value: Value
        public let imageSystemName: String?

        public init(label: String, value: Value, imageSystemName: String? = nil) {
            self.label = label
            self.value = value
            self.imageSystemName = imageSystemName
        }
    }
}
