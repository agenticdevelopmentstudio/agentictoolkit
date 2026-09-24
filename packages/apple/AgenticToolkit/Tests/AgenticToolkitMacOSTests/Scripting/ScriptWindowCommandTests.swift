import AppKit
import Testing
@testable import AgenticToolkitScripting

/// Review focus 1: a bad window name is a real script error that names the
/// windows a script *can* use, never a quiet `false`.
@Suite("ScriptWindowCommand", .serialized)
@MainActor
struct ScriptWindowCommandTests {

    init() { ScriptWindows.reset() }

    private static let description: NSScriptCommandDescription = {
        // Same construction MainActorScriptCommandTests uses; four-char codes
        // must be valid OSTypes.
        NSScriptCommandDescription(
            suiteName: "Test", commandName: "test",
            dictionary: ["CommandClass": "ScriptWindowCommand", "AppleEventCode": "test", "AppleEventClassCode": "Test"]
        )!
    }()

    private func command(_ direct: Any?) -> ScriptWindowCommand {
        let command = ScriptWindowCommand(commandDescription: Self.description)
        command.directParameter = direct
        return command
    }

    @Test("an unknown name fails with the known names listed")
    func unknownNameFails() {
        ScriptWindows.register(ScriptWindow(name: "main", window: { nil }, present: {}))
        ScriptWindows.register(ScriptWindow(name: "settings", window: { nil }, present: {}))
        let command = command("permissions")
        #expect(command.requireWindow() == nil)
        #expect(command.scriptErrorNumber == NSArgumentsWrongScriptError)
        #expect(command.scriptErrorString == "Unknown window name. Known windows: main, settings.")
    }

    @Test("a non-string fails the same way")
    func nonStringFails() {
        ScriptWindows.register(ScriptWindow(name: "main", window: { nil }, present: {}))
        let command = command(42)
        #expect(command.requireWindow() == nil)
        #expect(command.scriptErrorNumber == NSArgumentsWrongScriptError)
    }

    @Test("a missing parameter means the first window only when asked")
    func defaultingToFirst() {
        ScriptWindows.register(ScriptWindow(name: "main", window: { nil }, present: {}))
        #expect(command(nil).requireWindow(defaultingToFirst: true)?.name == "main")
        let strict = command(nil)
        #expect(strict.requireWindow() == nil)
        #expect(strict.scriptErrorNumber == NSArgumentsWrongScriptError)
    }

    @Test("with nothing registered the error says so")
    func nothingRegistered() {
        let command = command(nil)
        #expect(command.requireWindow(defaultingToFirst: true) == nil)
        #expect(command.scriptErrorString == "No windows are registered for scripting.")
    }

    @Test("requireText trims and rejects empty text")
    func requireText() {
        #expect(command("  hi ").requireText() == "hi")
        let empty = command("   ")
        #expect(empty.requireText() == nil)
        #expect(empty.scriptErrorString == "This command's text argument must not be empty.")
        let wrong = command(3)
        #expect(wrong.requireText() == nil)
        #expect(wrong.scriptErrorString == "This command takes a text argument.")
    }
}
