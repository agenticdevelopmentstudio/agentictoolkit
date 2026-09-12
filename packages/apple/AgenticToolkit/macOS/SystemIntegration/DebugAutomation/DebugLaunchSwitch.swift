import Foundation

/// A boolean an automated session can turn on for one launch of a **Debug**
/// build, and that does not exist at all in a shipping one.
///
/// ```swift
/// static let multipleInstances = DebugLaunchSwitch("MultipleInstances")
/// open -n -g -a MyApp.app --args -MultipleInstances YES
/// ```
///
/// Two properties are the whole point, and both are why this is a type rather
/// than a `UserDefaults.bool(forKey:)` at each call site:
///
/// - **The argument domain, not a written preference.** A switch passed as a
///   launch argument lasts exactly as long as the process. A stale
///   `defaults write` cannot leave a developer — or a user who once ran a Debug
///   build — wondering months later why the app behaves oddly.
/// - **`#if DEBUG`, evaluated here.** A Release build returns `false` without
///   consulting anything, so the switch cannot be flipped on in a shipping app
///   by any argument, preference, or profile. Call sites get that guarantee by
///   using this type instead of re-deriving it, which is what keeps one of them
///   from forgetting the `#if`.
public struct DebugLaunchSwitch: Sendable, Hashable {

    /// The `UserDefaults` key, which is also the launch-argument name.
    public let key: String

    public init(_ key: String) {
        self.key = key
    }

    /// Whether the switch is on for this process.
    public var isOn: Bool { isOn(defaults: .standard) }

    /// The decision with its input passed in, so a test can exercise the `true`
    /// branch without touching the developer's own preferences.
    public func isOn(defaults: UserDefaults) -> Bool {
        #if DEBUG
        return defaults.bool(forKey: key)
        #else
        return false
        #endif
    }
}
