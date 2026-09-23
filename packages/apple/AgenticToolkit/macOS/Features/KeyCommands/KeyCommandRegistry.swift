import AppKit
import Carbon.HIToolbox
@preconcurrency import KeyboardShortcuts
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
/// `UserSettings.shared` is: the code that must reach it — the command palette,
/// the window-context shortcuts, a host declaring its commands — is started by
/// AppKit down paths with nowhere to thread a registry through, and a chord
/// owner that could not find one would silently go unchecked for clashes.
@MainActor
public final class KeyCommandRegistry {

    public static let shared = KeyCommandRegistry()

    /// Posted, with the registry as its object, whenever any binding changes.
    /// A chord given to one command is a chord taken from every other row's
    /// point of view, so each row re-reads its readout on this rather than only
    /// when it itself is edited.
    public static let bindingsDidChangeNotification =
        Notification.Name("KeyCommandRegistry.bindingsDidChange")

    public private(set) var sections: [KeyCommandSection] = []

    private var descriptorsByID: [String: KeyCommandDescriptor] = [:]

    private let store = UserSettings.keyCommandBindings

    /// Global commands whose `KeyboardShortcuts` handler is already installed.
    /// Handlers are permanent; only the chord they answer to is changed, by
    /// ``apply(_:)``.
    private var handledGlobalIDs: Set<String> = []

    /// Chords registered with `KeyboardShortcuts` by code that does not go
    /// through this registry — the command palette, the window-context
    /// shortcuts — and what to call their owner in a refusal. Their handlers
    /// fire alongside ours, so a chord one of them holds is not free.
    private var externalOwners: [(name: KeyboardShortcuts.Name, owner: String)] = []

    /// The one app-wide key monitor that performs app-scope commands. Installed
    /// with the first app-scope section; `nonisolated(unsafe)` only so `deinit`
    /// can remove it.
    private nonisolated(unsafe) var appMonitor: Any?

    /// True while a settings row is recording a chord. Nothing is dispatched
    /// then — neither scope — because the chord being pressed is the one the
    /// user is trying to *assign*, and running whatever currently holds it
    /// (opening a window over Settings, say) is the opposite of recording it.
    public var isRecordingChord = false {
        didSet {
            // Soft-unregisters every `KeyboardShortcuts` hotkey, ours and the
            // external owners' alike, and restores them afterwards.
            KeyboardShortcuts.isEnabled = !isRecordingChord
        }
    }

    public init() {}

    deinit {
        if let appMonitor {
            NSEvent.removeMonitor(appMonitor)
        }
    }

    // MARK: - Declaring commands

    /// Add a section, or replace the installed one with the same title.
    ///
    /// A command the replacement no longer carries is withdrawn completely: its
    /// descriptor goes, so its handler finds nothing to run, and a global one
    /// gives its system-wide chord back. Left in place it would keep firing
    /// from a list that no longer shows it, and hold a chord every other row
    /// reads as free. What the user authored for it is kept, so a section that
    /// brings the command back brings their chord back with it.
    public func install(_ section: KeyCommandSection) {
        if let index = sections.firstIndex(where: { $0.title == section.title }) {
            let kept = Set(section.allCommands.map(\.id))
            for dropped in sections[index].allCommands where !kept.contains(dropped.id) {
                withdraw(dropped)
            }
            sections[index] = section
        } else {
            sections.append(section)
        }

        for command in section.allCommands {
            descriptorsByID[command.id] = command
            if command.scope == .global {
                installGlobalHandler(for: command)
            }
            apply(command)
        }
        if section.scope == .app {
            installAppMonitor()
        }
        postBindingsDidChange()
    }

    private func withdraw(_ command: KeyCommandDescriptor) {
        descriptorsByID[command.id] = nil
        if command.scope == .global {
            KeyboardShortcuts.setShortcut(nil, for: keyboardName(for: command.id))
        }
    }

    /// Declare chords that other code registers with `KeyboardShortcuts`
    /// directly, so ``availability(of:for:)`` refuses them as taken by `owner`
    /// instead of reporting them free — both handlers would otherwise fire.
    /// Re-declaring a name replaces its owner.
    public func reserveExternal(_ names: [KeyboardShortcuts.Name], owner: String) {
        let raw = Set(names.map(\.rawValue))
        externalOwners.removeAll { raw.contains($0.name.rawValue) }
        externalOwners += names.map { (name: $0, owner: owner) }
    }

    /// Give up a ``reserveExternal(_:owner:)`` — for an owner that has stopped
    /// listening, whose stored chord no longer fires anything.
    public func releaseExternal(_ names: [KeyboardShortcuts.Name]) {
        let raw = Set(names.map(\.rawValue))
        externalOwners.removeAll { raw.contains($0.name.rawValue) }
    }

    public var allCommands: [KeyCommandDescriptor] {
        sections.flatMap(\.allCommands)
    }

    /// The installed sections listened for in `scope`, in the order they were
    /// declared. The settings panel draws one heading per scope, so it asks the
    /// registry this way round rather than sorting the whole list itself.
    public func sections(in scope: KeyCommandScope) -> [KeyCommandSection] {
        sections.filter { $0.scope == scope }
    }

    public func descriptor(for id: String) -> KeyCommandDescriptor? {
        descriptorsByID[id]
    }

    // MARK: - Reading and writing bindings

    /// Whether the user has ever authored a binding for `id` — as opposed to
    /// it still carrying what it shipped with.
    public func hasAuthoredBinding(for id: String) -> Bool {
        store.currentValue[id] != nil
    }

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
        postBindingsDidChange()
    }

    /// Put `id` back to what it shipped with.
    public func resetBinding(for id: String) {
        var all = store.currentValue
        all[id] = nil
        store.value = all

        if let command = descriptorsByID[id] {
            apply(command)
        }
        postBindingsDidChange()
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

    /// Perform whatever `event` is bound to in `scope`. Returns whether the
    /// command handled it — not merely whether a chord matched — which is what
    /// a local event monitor needs in order to swallow the event, or let a
    /// command that declined it pass it on.
    @discardableResult
    public func perform(matching event: NSEvent, scope: KeyCommandScope = .app) -> Bool {
        guard !isRecordingChord,
              let command = command(matching: event, scope: scope)
        else { return false }
        return command.perform()
    }

    /// Every app-scope command is performed from here: one local monitor for
    /// the whole app, rather than one per window that owns commands.
    ///
    /// A local monitor rather than a responder-chain override because a
    /// window's commands are meant to work wherever in it the user happens to
    /// be — and the Conversations window's list is usually a *collapsed* split
    /// item, which AppKit hides and never offers key equivalents to. Whether a
    /// command applies to the window the key event is in is the command's own
    /// question, answered by its `perform` returning `false`.
    private func installAppMonitor() {
        guard appMonitor == nil else { return }
        appMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.perform(matching: event, scope: .app) ? nil : event
        }
    }

    private func postBindingsDidChange() {
        NotificationCenter.default.post(name: Self.bindingsDidChangeNotification, object: self)
    }

    // MARK: - Availability

    /// Whether `shortcut` can be given to `id`.
    ///
    /// The library's own `isTakenBySystem` / `menuItemWithMatchingShortcut`
    /// are internal to the package, so the system and menu checks below are
    /// ours.
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

        // Another command holding it is checked before anything else: that
        // clash can arise *after* this command was given the chord — another
        // row claimed it while this one was switched off — so "it is already
        // mine" does not settle it.
        if let clash = allCommands.first(where: { $0.id != id && self.shortcut(for: $0.id) == shortcut }) {
            return .unavailable("taken by “\(clash.title)”")
        }

        if let owner = externalOwners.first(where: { KeyboardShortcuts.getShortcut(for: $0.name) == shortcut }) {
            return .unavailable("taken by \(owner.owner)")
        }

        // macOS takes these before any app sees them, so a command bound to
        // one would save and never fire.
        if Self.systemShortcuts().contains(shortcut) {
            return .unavailable("taken by macOS")
        }

        // Re-recording what the command already has is not a clash with
        // itself, and returning here keeps the menu walk below from finding
        // this command's own menu item.
        if shortcut == binding(for: id).shortcut {
            return .available
        }

        if let item = Self.mainMenuItem(matching: shortcut) {
            let name = item.title.isEmpty ? "a menu item" : "“\(item.title)”"
            return .unavailable("taken by \(name)")
        }

        return .available
    }

    /// The symbolic hotkeys macOS has switched on — Spotlight's ⌘Space,
    /// Mission Control's ⌃↑, the screenshot chords. Read fresh each time,
    /// because the user can change them in System Settings while we run.
    private static func systemShortcuts() -> [KeyboardShortcuts.Shortcut] {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let entries = unmanaged?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return entries.compactMap { entry in
            guard (entry[kHISymbolicHotKeyEnabled] as? Bool) == true,
                  let code = entry[kHISymbolicHotKeyCode] as? Int,
                  let modifiers = entry[kHISymbolicHotKeyModifiers] as? Int
            else { return nil }
            return KeyboardShortcuts.Shortcut(carbonKeyCode: code, carbonModifiers: modifiers)
        }
    }

    /// The main-menu item carrying `shortcut`, if any.
    ///
    /// A menu item's key equivalent is the character the chord *types*, with
    /// shift folded into it: View › Bigger is written `+` with ⌘ alone, and
    /// ⇧⌘D is written `D`. A recorded chord is a key and its modifiers — ⇧⌘=
    /// — so a comparison of the two as written misses both. Each item is
    /// matched as written, and again as the shifted character the chord's key
    /// produces on the current layout.
    private static func mainMenuItem(matching shortcut: KeyboardShortcuts.Shortcut) -> NSMenuItem? {
        guard let mainMenu = NSApp?.mainMenu else { return nil }
        return menuItem(matching: shortcut, in: mainMenu)
    }

    static func menuItem(
        matching shortcut: KeyboardShortcuts.Shortcut,
        in menu: NSMenu
    ) -> NSMenuItem? {
        let shifted = shortcut.modifiers.contains(.shift)
            ? shiftedCharacter(forKeyCode: shortcut.carbonKeyCode)
            : nil
        return menuItem(matching: shortcut, shifted: shifted, in: menu)
    }

    private static func menuItem(
        matching shortcut: KeyboardShortcuts.Shortcut,
        shifted: String?,
        in menu: NSMenu
    ) -> NSMenuItem? {
        let relevant: NSEvent.ModifierFlags = [.command, .control, .option, .shift, .function]
        let modifiers = shortcut.modifiers.intersection(relevant)
        for item in menu.items {
            let written = item.keyEquivalent
            let mask = item.keyEquivalentModifierMask.intersection(relevant)

            if !written.isEmpty {
                // As written: ⇧⌘[ against an item stored as `[` with ⇧⌘.
                if written == shortcut.nsMenuItemKeyEquivalent, mask == modifiers {
                    return item
                }
                // Shift folded into the character: ⇧⌘D against `D`, ⇧⌘=
                // against `+`.
                if let shifted, written == shifted, mask == modifiers.subtracting(.shift) {
                    return item
                }
            }

            if let submenu = item.submenu,
               let found = menuItem(matching: shortcut, shifted: shifted, in: submenu) {
                return found
            }
        }
        return nil
    }

    /// The character `keyCode` types with shift held on the current keyboard
    /// layout — `+` for the `=` key on a US layout, `D` for `d`.
    static func shiftedCharacter(forKeyCode keyCode: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)

        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay),
            UInt32(shiftKey >> 8) & 0xFF, UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState, characters.count, &length, &characters)
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
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
