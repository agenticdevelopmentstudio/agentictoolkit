import AppKit
import KeyboardShortcuts
import AgenticToolkitCore

/// The list of bindable commands, what each is bound to, and the dispatch for
/// both scopes.
///
/// One registry holds both scopes because the interesting question — *is this
/// chord free?* — spans them: a global hotkey that collides with an in-app one
/// is a bug the user experiences as "sometimes it does the wrong thing", and a
/// check that only looked at its own scope could not see it.
///
/// Reached through ``shared`` rather than injected, for the same reason
/// `UserSettings.shared` is: the windows that need to read a binding
/// (`ConversationsSplitViewController` among them) are built by AppKit down a
/// path with nowhere to thread a registry through, and a window that could not
/// find one would silently lose its keyboard navigation.
@MainActor
public final class KeyCommandRegistry {

    public static let shared = KeyCommandRegistry()

    public private(set) var sections: [KeyCommandSection] = []

    private var descriptorsByID: [String: KeyCommandDescriptor] = [:]

    private let store = UserSettings.keyCommandBindings

    /// Global commands whose `KeyboardShortcuts` handler is already installed.
    /// Handlers are permanent; only the chord they answer to is changed, by
    /// ``apply(_:)``.
    private var handledGlobalIDs: Set<String> = []

    public init() {}

    // MARK: - Declaring commands

    /// Add a section, or replace the installed one with the same title.
    public func install(_ section: KeyCommandSection) {
        if let index = sections.firstIndex(where: { $0.title == section.title }) {
            sections[index] = section
        } else {
            sections.append(section)
        }

        for command in section.commands {
            descriptorsByID[command.id] = command
            if command.scope == .global {
                installGlobalHandler(for: command)
            }
            apply(command)
        }
    }

    public var allCommands: [KeyCommandDescriptor] {
        sections.flatMap(\.commands)
    }

    public func descriptor(for id: String) -> KeyCommandDescriptor? {
        descriptorsByID[id]
    }

    // MARK: - Reading and writing bindings

    /// What `id` is bound to: what the user authored, or the shipped default
    /// when they never touched it.
    public func binding(for id: String) -> KeyCommandBinding {
        if let authored = store.currentValue[id] {
            return authored
        }
        return descriptorsByID[id]?.defaultBinding
            ?? KeyCommandBinding(shortcut: nil, isEnabled: false)
    }

    /// The chord that will actually fire for `id`, or `nil`.
    public func shortcut(for id: String) -> KeyboardShortcuts.Shortcut? {
        binding(for: id).effectiveShortcut
    }

    public func setBinding(_ binding: KeyCommandBinding, for id: String) {
        var all = store.currentValue
        all[id] = binding
        store.value = all

        if let command = descriptorsByID[id] {
            apply(command)
        }
    }

    /// Put `id` back to what it shipped with.
    public func resetBinding(for id: String) {
        var all = store.currentValue
        all[id] = nil
        store.value = all

        if let command = descriptorsByID[id] {
            apply(command)
        }
    }

    // MARK: - Dispatch

    /// The app-scope command `event` is bound to, if any.
    ///
    /// Global commands are dispatched by `KeyboardShortcuts`' own tap and are
    /// never matched here, so a window's local monitor cannot fire one twice.
    public func command(
        matching event: NSEvent,
        scope: KeyCommandScope = .app
    ) -> KeyCommandDescriptor? {
        guard let pressed = KeyboardShortcuts.Shortcut(event: event) else { return nil }
        return allCommands.first { command in
            command.scope == scope && shortcut(for: command.id) == pressed
        }
    }

    /// Run whatever `event` is bound to in `scope`. Returns whether it matched,
    /// which is what a local event monitor needs in order to swallow the event.
    @discardableResult
    public func perform(matching event: NSEvent, scope: KeyCommandScope = .app) -> Bool {
        guard let command = command(matching: event, scope: scope) else { return false }
        command.run()
        return true
    }

    // MARK: - Availability

    /// Whether `shortcut` can be given to `id`.
    ///
    /// The three refusals are the three a user can actually hit. The library's
    /// own `isTakenBySystem` / `isDisallowed` / `menuItemWithMatchingShortcut`
    /// are internal to the package, so the menu walk below is ours.
    public func availability(
        of shortcut: KeyboardShortcuts.Shortcut?,
        for id: String
    ) -> KeyCommandAvailability {
        guard let shortcut else {
            return .unavailable("press a key combination")
        }

        // Without a modifier the chord would swallow ordinary typing — the
        // filter box in the very window most of these commands drive.
        guard !shortcut.modifiers.isDisjoint(with: [.command, .control, .option]) else {
            return .unavailable("needs ⌘, ⌃ or ⌥")
        }

        // Re-recording what the command already has is not a conflict with
        // itself, and checking it first keeps the menu walk below from finding
        // this command's own menu item.
        if shortcut == binding(for: id).shortcut {
            return .available
        }

        if let clash = allCommands.first(where: { $0.id != id && self.shortcut(for: $0.id) == shortcut }) {
            return .unavailable("taken by “\(clash.title)”")
        }

        if let item = Self.mainMenuItem(matching: shortcut) {
            let name = item.title.isEmpty ? "a menu item" : "“\(item.title)”"
            return .unavailable("taken by \(name)")
        }

        return .available
    }

    /// The main-menu item carrying `shortcut`, if any.
    ///
    /// The shift dance mirrors what AppKit itself does: a menu item written as
    /// `⌘{` stores an uppercase key equivalent and *no* shift flag, so a naive
    /// comparison against a recorded `⇧⌘[` misses it.
    private static func mainMenuItem(matching shortcut: KeyboardShortcuts.Shortcut) -> NSMenuItem? {
        guard let mainMenu = NSApp.mainMenu else { return nil }
        return menuItem(matching: shortcut, in: mainMenu)
    }

    private static func menuItem(
        matching shortcut: KeyboardShortcuts.Shortcut,
        in menu: NSMenu
    ) -> NSMenuItem? {
        for item in menu.items {
            var equivalent = item.keyEquivalent
            var mask = item.keyEquivalentModifierMask

            if shortcut.modifiers.contains(.shift), equivalent.lowercased() != equivalent {
                equivalent = equivalent.lowercased()
                mask.insert(.shift)
            }

            if let ours = shortcut.nsMenuItemKeyEquivalent,
               ours == equivalent,
               shortcut.modifiers == mask {
                return item
            }

            if let submenu = item.submenu,
               let found = menuItem(matching: shortcut, in: submenu) {
                return found
            }
        }
        return nil
    }

    // MARK: - Applying the global scope

    /// The `KeyboardShortcuts` name a global command's tap is registered under.
    /// Namespaced so it can never collide with a name declared directly against
    /// `KeyboardShortcuts.Name` elsewhere in the toolkit.
    private func keyboardName(for id: String) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("keyCommand.\(id)")
    }

    private func installGlobalHandler(for command: KeyCommandDescriptor) {
        guard !handledGlobalIDs.contains(command.id) else { return }
        handledGlobalIDs.insert(command.id)

        let id = command.id
        // Looked up at fire time rather than captured: a section can be
        // re-installed with a new closure, and a handler holding the old one
        // would keep running yesterday's action.
        KeyboardShortcuts.onKeyDown(for: keyboardName(for: id)) { [weak self] in
            self?.descriptorsByID[id]?.run()
        }
    }

    /// Hand the command's effective chord to `KeyboardShortcuts` — or `nil`,
    /// which tears the tap down. A command switched off therefore holds no
    /// system-wide hotkey at all, rather than holding one that does nothing.
    private func apply(_ command: KeyCommandDescriptor) {
        guard command.scope == .global else { return }
        KeyboardShortcuts.setShortcut(
            binding(for: command.id).effectiveShortcut,
            for: keyboardName(for: command.id))
    }
}
