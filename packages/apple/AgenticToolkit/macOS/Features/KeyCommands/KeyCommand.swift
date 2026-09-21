import AppKit
import KeyboardShortcuts

/// Where a key command is listened for.
///
/// The distinction is not cosmetic: an app command is matched against a key
/// event this app already received, while a global one needs a system-wide
/// event tap that fires whatever the user is doing. That tap is a real cost —
/// it asks for accessibility trust and it can steal a chord from whatever app
/// is frontmost — which is why the global section ships off by default.
public enum KeyCommandScope: String, Codable, Sendable, CaseIterable {

    /// Delivered only while this app is frontmost.
    case app

    /// Delivered system-wide, through `KeyboardShortcuts`' global event tap.
    case global
}

/// What the user authored for one command: the chord, and whether it is on.
///
/// The two are stored separately rather than collapsing "off" into "no
/// shortcut", so turning a command off and back on gives the user their chord
/// back instead of an empty field.
public struct KeyCommandBinding: Codable, Hashable, Sendable {

    public var shortcut: KeyboardShortcuts.Shortcut?
    public var isEnabled: Bool

    public init(shortcut: KeyboardShortcuts.Shortcut?, isEnabled: Bool) {
        self.shortcut = shortcut
        self.isEnabled = isEnabled
    }

    /// The chord that should actually fire — `nil` when there is none or the
    /// command is switched off. This is the only reading of a binding that
    /// dispatch and conflict-checking use, so a disabled command can never
    /// shadow an enabled one.
    public var effectiveShortcut: KeyboardShortcuts.Shortcut? {
        isEnabled ? shortcut : nil
    }
}

/// One thing the user can bind a chord to.
///
/// A descriptor is declared by whoever owns the action — the Conversations
/// window declares its own navigation commands, the host app declares its
/// windows — and handed to ``KeyCommandRegistry``. That is what lets the
/// settings panel be shared while the list of commands stays the property of
/// the feature that can actually perform them.
@MainActor
public struct KeyCommandDescriptor {

    /// Stable across releases: it is the key this command's binding is stored
    /// under. Convention is `<namespace>.<verbNoun>`, e.g.
    /// `conversations.moveSelectionUp`.
    public let id: String

    /// What the settings row calls it.
    public let title: String

    public let scope: KeyCommandScope

    /// The chord shipped with the command. `nil` means the command is listed
    /// with no key command until the user gives it one.
    public let defaultShortcut: KeyboardShortcuts.Shortcut?

    /// Whether the shipped chord is live out of the box. A command can ship
    /// *with* a suggested chord and still be off — which is exactly what the
    /// global window shortcuts do.
    public let isEnabledByDefault: Bool

    public let run: () -> Void

    public init(
        id: String,
        title: String,
        scope: KeyCommandScope,
        defaultShortcut: KeyboardShortcuts.Shortcut? = nil,
        isEnabledByDefault: Bool = true,
        run: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.scope = scope
        self.defaultShortcut = defaultShortcut
        self.isEnabledByDefault = isEnabledByDefault
        self.run = run
    }

    /// What a command is bound to before the user touches it.
    public var defaultBinding: KeyCommandBinding {
        KeyCommandBinding(shortcut: defaultShortcut, isEnabled: isEnabledByDefault)
    }
}

/// A titled run of commands, which is how the settings panel groups them.
@MainActor
public struct KeyCommandSection {

    /// Also the section's identity: installing a section whose title matches an
    /// installed one replaces it, so a host can re-declare its commands (after
    /// a plugin loads, say) without stacking duplicates.
    public let title: String

    /// Shown under the title in the panel; `nil` for no caption.
    public let caption: String?

    public let commands: [KeyCommandDescriptor]

    public init(title: String, caption: String? = nil, commands: [KeyCommandDescriptor]) {
        self.title = title
        self.caption = caption
        self.commands = commands
    }
}

/// Whether a chord can be assigned, and if not, what has it.
public enum KeyCommandAvailability: Equatable, Sendable {

    case available
    case unavailable(String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    /// The word the recorder shows beneath the field while the user types.
    public var label: String {
        isAvailable ? "available" : "unavailable"
    }

    /// Why it is unavailable, for the rest of the readout line.
    public var reason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}
