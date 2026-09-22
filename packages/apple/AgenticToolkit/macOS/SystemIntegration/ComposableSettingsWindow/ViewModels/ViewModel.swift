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
    }
}
