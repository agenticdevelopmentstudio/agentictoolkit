import AppKit

/// Declares the spatial rules and persistence policy for a managed window.
public struct WindowSpec: Codable, Sendable, Equatable {
    public let defaultSize: NSSize
    public let minSize: NSSize
    public let defaultPosition: WindowPosition
    public let behavior: Behavior
    public let toolbarButtons: ToolbarButtons

    public init(
        defaultSize: NSSize,
        minSize: NSSize,
        defaultPosition: WindowPosition,
        persistsFrame: Bool? = nil,
        behavior: Behavior = .default,
        toolbarButtons: ToolbarButtons = .all
    ) {
        self.defaultSize = defaultSize
        self.minSize = minSize
        self.defaultPosition = defaultPosition
        // `persistsFrame` is a `Behavior` flag now (default on). The legacy
        // `persistsFrame:` parameter is a convenience: when provided, it
        // overrides the `.persistsFrame` bit in `behavior`. Without it,
        // `behavior.contains(.persistsFrame)` from the caller's behavior set
        // (or `.default`) wins.
        var resolvedBehavior = behavior
        if let persistsFrame {
            if persistsFrame {
                resolvedBehavior.insert(.persistsFrame)
            } else {
                resolvedBehavior.remove(.persistsFrame)
            }
        }
        self.behavior = resolvedBehavior
        self.toolbarButtons = toolbarButtons
    }

    /// True when the window opts in to frame persistence. Shorthand for
    /// `behavior.contains(.persistsFrame)`.
    public var persistsFrame: Bool { behavior.contains(.persistsFrame) }

    /// True when the window opts in to visibility persistence. Shorthand for
    /// `behavior.contains(.persistsVisibility)`.
    public var persistsVisibility: Bool { behavior.contains(.persistsVisibility) }
}

extension WindowSpec {

    /// Per-window switches that opt windows into (or out of) toolkit-wide
    /// systems like recents tracking, launch-time reopen, and state
    /// persistence (frame + visibility).
    public struct Behavior: OptionSet, Codable, Sendable, Equatable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// Window participates in recents — the Open Recent menu for document
        /// windows, or the toolkit's window-recents tracker for non-document
        /// single windows.
        public static let includeInRecents = Behavior(rawValue: 1 << 0)

        /// Window may be re-shown at launch when the user's reopen-on-launch
        /// policy says so.
        public static let canReopenOnLaunch = Behavior(rawValue: 1 << 1)

        /// Window's frame (size + position) is saved on move/resize and
        /// restored on first show.
        public static let persistsFrame = Behavior(rawValue: 1 << 2)

        /// Window's visible/hidden state is saved on show/close and can be
        /// restored at launch via `SingleWindowController.restoreVisibilityIfNeeded()`.
        public static let persistsVisibility = Behavior(rawValue: 1 << 3)

        /// Default behavior: opt in to recents, reopen-on-launch, and both
        /// frame + visibility persistence.
        public static let `default`: Behavior = [
            .includeInRecents, .canReopenOnLaunch, .persistsFrame, .persistsVisibility
        ]
    }

    /// Mask selecting which of the standard window title-bar buttons
    /// (close, miniaturize, zoom) are active for this window.
    public struct ToolbarButtons: OptionSet, Codable, Sendable, Equatable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let close = ToolbarButtons(rawValue: 1 << 0)
        public static let miniaturize = ToolbarButtons(rawValue: 1 << 1)
        public static let zoom = ToolbarButtons(rawValue: 1 << 2)

        /// All three traffic-light buttons enabled.
        public static let all: ToolbarButtons = [.close, .miniaturize, .zoom]
        /// No traffic-light buttons.
        public static let none: ToolbarButtons = []
    }
}
