import AgenticToolkitCore

extension ComposableSettings {

    public class RangeViewModel<Value: Codable & Sendable>: ViewModel<Value> {

        public let maxValue: Value
        public let minValue: Value

        public init(
            title: String,
            setting: UserSetting<Value>,
            minValue: Value,
            maxValue: Value,
            explanation: String? = nil
        ) {
            self.maxValue = maxValue
            self.minValue = minValue

            super.init(title: title, setting: setting, explanation: explanation)
        }

        /// A ranged row bound to something other than `UserDefaults`.
        public init(
            title: String,
            minValue: Value,
            maxValue: Value,
            get: @escaping () -> Value,
            set: @escaping (Value) -> Void,
            explanation: String? = nil
        ) {
            self.maxValue = maxValue
            self.minValue = minValue
            super.init(title: title, get: get, set: set, explanation: explanation)
        }
    }
}
