import AgenticDeveloperToolkit
import AgenticToolkitSystemMonitor

extension MonitorLevel {
    /// The theme's color for this level, so every surface that shows a level —
    /// a row's dot, its gauge, a menu bar icon — agrees with the others.
    public var themeRole: ThemeRole {
        switch self {
        case .unknown: .tertiaryText
        case .normal: .success
        case .warning: .warning
        case .critical: .danger
        }
    }

    /// For VoiceOver, and for anywhere the color alone must not carry the meaning.
    public var accessibilityLabel: String {
        switch self {
        case .unknown: "Unknown"
        case .normal: "OK"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}
