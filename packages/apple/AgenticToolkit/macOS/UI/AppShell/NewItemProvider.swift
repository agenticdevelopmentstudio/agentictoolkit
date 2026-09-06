import Foundation

/// What a feature's "New" means while its window is key. `MenuManager`
/// installs one File-menu item on Cmd-N and retitles it from whichever
/// provider claims the key window.
public struct NewItemProvider: Sendable {
    /// Higher wins when two providers both claim the key window.
    public let priority: Int
    /// Whether this provider owns the key window right now.
    public let claimsKeyWindow: @MainActor @Sendable () -> Bool
    /// The item's title while claimed, e.g. "New Note".
    public let title: @MainActor @Sendable () -> String
    public let action: @MainActor @Sendable () -> Void

    public init(
        priority: Int = 0,
        claimsKeyWindow: @escaping @MainActor @Sendable () -> Bool,
        title: @escaping @MainActor @Sendable () -> String,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.priority = priority
        self.claimsKeyWindow = claimsKeyWindow
        self.title = title
        self.action = action
    }
}

/// Resolves the winning provider, or nil when nobody claims the key window.
@MainActor
public enum NewItemRegistry {
    /// The highest-`priority` provider among those whose `claimsKeyWindow`
    /// answers true right now, or `nil` when none do.
    public static func resolve(_ providers: [NewItemProvider]) -> NewItemProvider? {
        providers
            .filter { $0.claimsKeyWindow() }
            .max { $0.priority < $1.priority }
    }
}
