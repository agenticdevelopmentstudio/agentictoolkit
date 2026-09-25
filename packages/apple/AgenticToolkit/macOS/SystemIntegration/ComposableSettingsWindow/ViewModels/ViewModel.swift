import AgenticToolkitCore

extension ComposableSettings {

    public class ViewModel<Value: Codable & Sendable>: AbstractViewModel {

        /// The row's storage. An existential rather than a concrete
        /// `UserSettingObserver` so a row can be backed by a database record —
        /// see `SettingObserving`.
        public let settingObserver: any SettingObserving<Value>

        public init(
            title: String,
            setting: UserSetting<Value>,
            explanation: String? = nil
        ) {
            self.settingObserver = UserSettingObserver(setting)
            super.init(title: title, explanation: explanation)
        }

        /// A row bound to something other than `UserDefaults`.
        public init(
            title: String,
            get: @escaping () -> Value,
            set: @escaping (Value) -> Void,
            explanation: String? = nil
        ) {
            self.settingObserver = ClosureSettingObserver(get: get, set: set)
            super.init(title: title, explanation: explanation)
        }

        public var onChange: ((_ newValue: Value) -> Void)? {
            get { settingObserver.onChange }
            set { settingObserver.onChange = newValue }
        }

        public var value: Value {
            settingObserver.value
        }

        /// How the row this model backs re-shows the stored value. Set by the
        /// row view; `force` says whether an edit in progress is discarded.
        var refreshHandler: ((_ force: Bool) -> Void)?

        /// Re-reads the stored value into the row, leaving alone a field the
        /// user is typing in — a poll that lands mid-word never replaces what
        /// is being typed. For a row bound through `get`/`set` to a record
        /// that changes under it, which no `onChange` announces.
        public func refresh() {
            refreshHandler?(false)
        }

        /// Re-reads the stored value into the row and discards any edit in
        /// progress: after a write that was refused, the text on screen is
        /// exactly what failed, and ending the edit later must not send it again.
        public func revert() {
            refreshHandler?(true)
        }
    }
}
