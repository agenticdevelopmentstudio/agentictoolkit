import Foundation

/// One SF Symbol shown beside the agent name, with a label for accessibility.
public struct TabPaneStatusSymbol: Equatable, Sendable {
    public let symbolName: String
    public let accessibilityLabel: String

    public init(symbolName: String, accessibilityLabel: String) {
        self.symbolName = symbolName
        self.accessibilityLabel = accessibilityLabel
    }

    /// The placeholder until agents report real status.
    public static let idle = TabPaneStatusSymbol(symbolName: "moon.zzz", accessibilityLabel: "Idle")
}
