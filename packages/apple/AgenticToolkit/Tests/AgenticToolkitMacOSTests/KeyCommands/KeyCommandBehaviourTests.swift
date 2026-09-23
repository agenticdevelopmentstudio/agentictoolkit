import AppKit
import Carbon.HIToolbox
import XCTest
@preconcurrency import KeyboardShortcuts
@testable import AgenticToolkitCoreMacOS
@testable import AgenticToolkitMacOS

/// What a key command does once it is bound: whether a chord is really free,
/// what a keystroke reaches, and how the recorder and its ✓/✗ pair treat the
/// keys that mean something to an edit.
///
/// Bindings persist through `UserSettings`, which every registry shares, so
/// each test binds ids of its own and resets them afterwards.
@MainActor
final class KeyCommandBehaviourTests: XCTestCase {
    private var usedIDs: [String] = []
    private var windows: [NSWindow] = []
    private let registry = KeyCommandRegistry()

    override func tearDown() async throws {
        usedIDs.forEach(registry.resetBinding(for:))
        windows.forEach { $0.orderOut(nil) }
        registry.isRecordingChord = false
        try await super.tearDown()
    }

    // MARK: - Declaring

    func testAGlobalCommandShipsSwitchedOffWhateverItsDeclarerSaid() {
        let section = KeyCommandSection(
            title: "Windows", scope: .global,
            commands: [KeyCommandDescriptor(id: id("open"), title: "Open", run: {})])
        XCTAssertFalse(section.allCommands[0].isEnabledByDefault)
        XCTAssertFalse(section.allCommands[0].defaultBinding.isEnabled)
    }

    func testReinstallingASectionWithdrawsTheCommandsItDropped() {
        let chord = KeyboardShortcuts.Shortcut(.f17, modifiers: .command)
        let kept = id("kept"), dropped = id("dropped")
        registry.install(KeyCommandSection(title: "W", scope: .app, commands: [
            command(kept), command(dropped, chord: chord)
        ]))
        XCTAssertFalse(registry.availability(of: chord, for: kept).isAvailable)

        registry.install(KeyCommandSection(title: "W", scope: .app, commands: [command(kept)]))
        XCTAssertNil(registry.descriptor(for: dropped))
        XCTAssertTrue(registry.availability(of: chord, for: kept).isAvailable,
                      "a command no longer listed still holds its chord")
    }

    // MARK: - Availability

    /// The command's own chord is not automatically fine: another command may
    /// have taken it while this one was switched off.
    func testAChordIsNotFreeBecauseItIsTheCommandsOwnWhenAnotherHoldsIt() {
        let chord = KeyboardShortcuts.Shortcut(.f16, modifiers: .command)
        let sleeper = id("sleeper"), holder = id("holder")
        registry.install(KeyCommandSection(title: "W", scope: .app, commands: [
            command(sleeper), command(holder, chord: chord)
        ]))
        registry.setBinding(KeyCommandBinding(shortcut: chord, isEnabled: false), for: sleeper)

        XCTAssertEqual(registry.availability(of: chord, for: sleeper).reason, "taken by “holder”")
    }

    func testAChordAnotherOwnerRegisteredIsTakenUntilReleased() {
        let chord = KeyboardShortcuts.Shortcut(.f15, modifiers: [.command, .option])
        let name = KeyboardShortcuts.Name("keyCommandBehaviourTests.external")
        KeyboardShortcuts.setShortcut(chord, for: name)
        defer { KeyboardShortcuts.setShortcut(nil, for: name) }

        registry.reserveExternal([name], owner: "the palette")
        XCTAssertEqual(registry.availability(of: chord, for: id("any")).reason, "taken by the palette")

        registry.releaseExternal([name])
        XCTAssertTrue(registry.availability(of: chord, for: id("any")).isAvailable)
    }

    /// View › Bigger is written `+` with ⌘ alone; the chord that reaches it is
    /// ⇧⌘= — neither spelling matches the other as written.
    func testAShiftedSymbolMenuItemIsFoundFromTheChordThatTypesIt() throws {
        let equalsKey = KeyboardShortcuts.Shortcut(.equal, modifiers: [.command, .shift])
        let typed = try XCTUnwrap(KeyCommandRegistry.shiftedCharacter(forKeyCode: equalsKey.carbonKeyCode))
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Bigger", action: nil, keyEquivalent: typed))

        XCTAssertEqual(KeyCommandRegistry.menuItem(matching: equalsKey, in: menu)?.title, "Bigger")
        XCTAssertNil(KeyCommandRegistry.menuItem(
            matching: KeyboardShortcuts.Shortcut(.equal, modifiers: .command), in: menu))
    }

    func testAnUppercaseLetterMenuItemIsShiftCommandLetter() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Duplicate", action: nil, keyEquivalent: "D"))
        let chord = KeyboardShortcuts.Shortcut(.d, modifiers: [.command, .shift])
        XCTAssertEqual(KeyCommandRegistry.menuItem(matching: chord, in: menu)?.title, "Duplicate")
    }

    // MARK: - Dispatch

    func testAKeystrokeACommandDeclinesIsNotSwallowed() throws {
        let chord = KeyboardShortcuts.Shortcut(.f14, modifiers: .command)
        var handles = false
        var asked = 0
        registry.install(KeyCommandSection(title: "W", scope: .app, commands: [
            KeyCommandDescriptor(id: id("move"), title: "Move", defaultShortcut: chord, perform: {
                asked += 1
                return handles
            })
        ]))
        let event = try keyEvent(keyCode: UInt16(kVK_F14), modifiers: .command)

        XCTAssertFalse(registry.perform(matching: event))
        handles = true
        XCTAssertTrue(registry.perform(matching: event))
        XCTAssertEqual(asked, 2)
    }

    func testNothingIsPerformedWhileAChordIsBeingRecorded() throws {
        var ran = false
        registry.install(KeyCommandSection(title: "W", scope: .app, commands: [
            KeyCommandDescriptor(
                id: id("run"), title: "Run",
                defaultShortcut: KeyboardShortcuts.Shortcut(.f13, modifiers: .command),
                run: { ran = true })
        ]))
        registry.isRecordingChord = true
        XCTAssertFalse(KeyboardShortcuts.isEnabled, "global hotkeys still fire under the recorder")

        XCTAssertFalse(registry.perform(matching: try keyEvent(keyCode: UInt16(kVK_F13), modifiers: .command)))
        XCTAssertFalse(ran)

        registry.isRecordingChord = false
        XCTAssertTrue(KeyboardShortcuts.isEnabled)
    }

    // MARK: - The row

    /// A suggested chord that ships off is not the user's "off": recording over
    /// it must switch the command on, or the chord saves and never fires.
    func testRecordingOverAShippedOffCommandSwitchesItOn() throws {
        let cmd = id("suggested")
        let descriptor = KeyCommandDescriptor(
            id: cmd, title: "Suggested",
            defaultShortcut: KeyboardShortcuts.Shortcut(.f12, modifiers: [.command, .option]),
            isEnabledByDefault: false, run: {})
        registry.install(KeyCommandSection(title: "W", scope: .app, commands: [descriptor]))
        let row = try hosted(KeyCommandRowView(command: descriptor, registry: registry))
        let field = try XCTUnwrap(first(KeyCommandCaptureField.self, in: row))

        field.onCapture?(KeyboardShortcuts.Shortcut(.f11, modifiers: [.command, .option]))
        field.onCommit?()

        XCTAssertEqual(registry.binding(for: cmd).shortcut,
                       KeyboardShortcuts.Shortcut(.f11, modifiers: [.command, .option]))
        XCTAssertTrue(registry.binding(for: cmd).isEnabled)
    }

    func testTheSwitchRefusesToPutATakenChordBackInPlay() throws {
        let chord = KeyboardShortcuts.Shortcut(.f10, modifiers: [.command, .option])
        let sleeper = command(id("sleeper"))
        registry.install(KeyCommandSection(title: "W", scope: .app, commands: [
            sleeper, command(id("holder"), chord: chord)
        ]))
        registry.setBinding(KeyCommandBinding(shortcut: chord, isEnabled: false), for: sleeper.id)
        let row = try hosted(KeyCommandRowView(command: sleeper, registry: registry))
        let toggle = try XCTUnwrap(first(NSSwitch.self, in: row))

        toggle.state = .on
        toggle.sendAction(toggle.action, to: toggle.target)

        XCTAssertFalse(registry.binding(for: sleeper.id).isEnabled, "two commands now fire on one chord")
        XCTAssertEqual(toggle.state, .off)
    }

    // MARK: - The recorder

    func testShiftTabLeavesTheRecorderInsteadOfBeingRecorded() throws {
        let field = try recordingField()
        var captured: KeyboardShortcuts.Shortcut?
        field.onCapture = { captured = $0 }

        field.keyDown(with: try keyEvent(keyCode: UInt16(kVK_Tab), modifiers: .shift, characters: "\t"))
        XCTAssertNil(captured)
    }

    func testReturnCommitsInsteadOfBeingRecorded() throws {
        let field = try recordingField()
        var captured: KeyboardShortcuts.Shortcut?
        var committed = false
        field.onCapture = { captured = $0 }
        field.onCommit = { committed = true }

        field.keyDown(with: try keyEvent(keyCode: UInt16(kVK_Return), modifiers: [], characters: "\r"))
        XCTAssertNil(captured)
        XCTAssertTrue(committed)
    }

    func testAHiddenConfirmPairIgnoresReturn() throws {
        let pair = ConfirmCancelControl()
        _ = try hosted(pair)
        var confirmed = false
        pair.onConfirm = { confirmed = true }
        pair.isHidden = true

        XCTAssertFalse(pair.performKeyEquivalent(
            with: try keyEvent(keyCode: UInt16(kVK_Return), modifiers: [], characters: "\r")))
        XCTAssertFalse(confirmed)
    }

    // MARK: - Fixtures

    private func id(_ name: String) -> String {
        let id = "keyCommandBehaviourTests.\(name)"
        usedIDs.append(id)
        return id
    }

    private func command(_ id: String, chord: KeyboardShortcuts.Shortcut? = nil) -> KeyCommandDescriptor {
        let title = String(id.split(separator: ".").last ?? "")
        return KeyCommandDescriptor(id: id, title: title, defaultShortcut: chord, run: {})
    }

    private func hosted<View: NSView>(_ view: View) throws -> View {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 120),
            styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSView()
        window.contentView = host
        windows.append(window)
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()
        return view
    }

    private func recordingField() throws -> KeyCommandCaptureField {
        let field = try hosted(KeyCommandCaptureField())
        field.window?.makeFirstResponder(field)
        XCTAssertTrue(field.isRecording)
        return field
    }

    private func first<View: NSView>(_ type: View.Type, in view: NSView) -> View? {
        if let match = view as? View { return match }
        for sub in view.subviews {
            if let found = first(type, in: sub) { return found }
        }
        return nil
    }

    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String = ""
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: windows.first?.windowNumber ?? 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode))
    }
}
