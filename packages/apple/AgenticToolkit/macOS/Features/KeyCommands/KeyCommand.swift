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

    /// The heading the settings panel puts a run of sections under. Where a
    /// command is listened for is the first thing a reader needs to know about
    /// it, so it is the outermost grouping rather than a word in a caption.
    public var settingsHeading: String {
        switch self {
        case .app: "App"
        case .global: "Global"
        }
    }

    /// Shown under that heading — once, for every section in the scope. Each
    /// section used to carry its own copy of this sentence, which is one
    /// explanation of what a scope means written once per window that happens
    /// to be in it.
    public var settingsCaption: String {
        switch self {
        case .app:
            "These work while this app is frontmost."
        case .global:
            "These work whatever app is frontmost, which also means they are taken "
                + "away from that app. They ship switched off."
        }
    }
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

    /// Where it is listened for. Not the declarer's to state per command: it is
    /// a property of the section, which is why it is set by
    /// ``KeyCommandSection`` rather than passed in. A section that said `.app`
    /// while one of its commands said `.global` could otherwise list a command
    /// under a heading that was not where it actually fired.
    public internal(set) var scope: KeyCommandScope = .app

    /// The chord shipped with the command. `nil` means the command is listed
    /// with no key command until the user gives it one.
    public let defaultShortcut: KeyboardShortcuts.Shortcut?

    /// Whether the shipped chord is live out of the box. A command can ship
    /// *with* a suggested chord and still be off — which is exactly what the
    /// global window shortcuts do.
    ///
    /// A global command is always off out of the box, whatever its declarer
    /// said: ``KeyCommandScope/settingsCaption`` promises the user so, and a
    /// system-wide hotkey switched on by an upgrade takes a chord away from
    /// every other app without the user ever having asked for it.
    public internal(set) var isEnabledByDefault: Bool

    /// Performs the command, and says whether it did anything. `false` means
    /// "not mine to handle right now" — the Conversations window's ⌘↑ while
    /// the caret is in a text field — so the key event goes on to whoever
    /// would have had it, instead of being swallowed by a command that
    /// declined it.
    public let perform: () -> Bool

    public init(
        id: String,
        title: String,
        defaultShortcut: KeyboardShortcuts.Shortcut? = nil,
        isEnabledByDefault: Bool = true,
        perform: @escaping () -> Bool
    ) {
        self.id = id
        self.title = title
        self.defaultShortcut = defaultShortcut
        self.isEnabledByDefault = isEnabledByDefault
        self.perform = perform
    }

    /// A command that always handles its chord.
    public init(
        id: String,
        title: String,
        defaultShortcut: KeyboardShortcuts.Shortcut? = nil,
        isEnabledByDefault: Bool = true,
        run: @escaping () -> Void
    ) {
        self.init(
            id: id, title: title, defaultShortcut: defaultShortcut,
            isEnabledByDefault: isEnabledByDefault,
            perform: {
                run()
                return true
            })
    }

    /// Perform the command, ignoring whether it handled anything.
    public func run() {
        _ = perform()
    }

    /// What a command is bound to before the user touches it.
    public var defaultBinding: KeyCommandBinding {
        KeyCommandBinding(shortcut: defaultShortcut, isEnabled: isEnabledByDefault)
    }

    /// The same command, listened for in `scope`. Used by ``KeyCommandSection``
    /// to stamp its own scope through everything it carries.
    func scoped(to scope: KeyCommandScope) -> KeyCommandDescriptor {
        var copy = self
        copy.scope = scope
        if scope == .global {
            copy.isEnabledByDefault = false
        }
        return copy
    }
}

/// A named run of commands *inside* a section: the feature of that window they
/// operate on.
///
/// A window's commands are not one flat list to the person using them — two of
/// the Conversations window's three only exist in single conversation mode, and
/// a list that did not say so read as three equal commands, one of which
/// mysteriously did nothing.
@MainActor
public struct KeyCommandFeature {

    public let title: String
    public let commands: [KeyCommandDescriptor]

    public init(title: String, commands: [KeyCommandDescriptor]) {
        self.title = title
        self.commands = commands
    }

    func scoped(to scope: KeyCommandScope) -> KeyCommandFeature {
        KeyCommandFeature(title: title, commands: commands.map { $0.scoped(to: scope) })
    }
}

/// One surface's commands: a window, usually, and within it the features they
/// belong to.
///
/// The settings panel draws the three levels the section describes — the scope
/// as a heading, the section as a card under it, and each feature as a named
/// run inside that card — so a command is read as *where* it works before it is
/// read as *what* it does.
@MainActor
public struct KeyCommandSection {

    /// Also the section's identity: installing a section whose title matches an
    /// installed one replaces it, so a host can re-declare its commands (after
    /// a plugin loads, say) without stacking duplicates.
    public let title: String

    /// Shown under the title in the panel; `nil` for no caption. What the
    /// *scope* means is not this — that is said once, by
    /// ``KeyCommandScope/settingsCaption``.
    public let caption: String?

    /// Where every command in the section is listened for.
    public let scope: KeyCommandScope

    /// The surface's own commands — the ones that are not particular to any one
    /// feature of it.
    public let commands: [KeyCommandDescriptor]

    /// Named runs within the section.
    public let features: [KeyCommandFeature]

    public init(
        title: String,
        caption: String? = nil,
        scope: KeyCommandScope,
        commands: [KeyCommandDescriptor] = [],
        features: [KeyCommandFeature] = []
    ) {
        self.title = title
        self.caption = caption
        self.scope = scope
        self.commands = commands.map { $0.scoped(to: scope) }
        self.features = features.map { $0.scoped(to: scope) }
    }

    /// Everything the section carries, in the order the panel lists it: the
    /// surface's own commands, then each feature's.
    public var allCommands: [KeyCommandDescriptor] {
        commands + features.flatMap(\.commands)
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
