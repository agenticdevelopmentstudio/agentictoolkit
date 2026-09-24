import AppKit

/// One window a script may name: what it is called, how to find it, and how
/// to put it on screen.
///
/// Closures rather than an `NSWindow`, because a window is usually built
/// lazily — the settings window does not exist until something opens it — and
/// the name has to be answerable before then (`open window "settings"`).
@MainActor
public struct ScriptWindow {
    public let name: String
    /// The window, or `nil` while it has never been built.
    public let window: @MainActor () -> NSWindow?
    /// Builds the window if need be and brings it on screen.
    public let present: @MainActor () -> Void

    public init(
        name: String,
        window: @escaping @MainActor () -> NSWindow?,
        present: @escaping @MainActor () -> Void
    ) {
        self.name = name
        self.window = window
        self.present = present
    }
}

/// The host's list of windows a script may name.
///
/// A shared command cannot know which windows an app has, and an enum of them
/// in the app would put the command code there too. So the host registers each
/// window once, at launch, and the generic window commands read this list.
@MainActor
public enum ScriptWindows {

    private static var registered: [ScriptWindow] = []

    /// Extra facts the host wants in every `window list` reply — the hub adds
    /// `quiet_presentation`. The reply's own keys (`pid`, `bundle_path`,
    /// `windows`) always win over a fact of the same name.
    public static var processFacts: @MainActor () -> [String: Any] = { [:] }

    /// Adds a window, or replaces the one already registered under that name
    /// in its existing position, so the default-first window never shifts.
    ///
    /// A name that is not lowercase kebab is a programming error in the host,
    /// so it stops the process here rather than becoming a window no script
    /// can type.
    public static func register(_ entry: ScriptWindow) {
        precondition(isValidName(entry.name), "Script window name '\(entry.name)' is not lowercase-kebab.")
        if let index = registered.firstIndex(where: { $0.name == entry.name }) {
            registered[index] = entry
        } else {
            registered.append(entry)
        }
    }

    /// The window a script named, matched trimmed and case-insensitively.
    /// `nil` for anything else, including a non-string.
    public static func named(_ raw: Any?) -> ScriptWindow? {
        guard let text = raw as? String else { return nil }
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return registered.first { $0.name == key }
    }

    /// Every registered name, in registration order.
    public static var names: [String] { registered.map(\.name) }

    /// The first registered window — the one a command whose window parameter
    /// is optional acts on.
    public static var first: ScriptWindow? { registered.first }

    /// Lowercase ASCII letters, digits and single inner hyphens.
    public static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("-"), !name.hasSuffix("-") else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        return name.allSatisfy(allowed.contains)
    }

    /// Test seam: forget every registration and fact.
    static func reset() {
        registered = []
        processFacts = { [:] }
    }
}
