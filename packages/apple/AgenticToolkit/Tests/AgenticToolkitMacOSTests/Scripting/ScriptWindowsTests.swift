import AppKit
import Testing
@testable import AgenticToolkitScripting

/// `ScriptWindows` is the host's list of windows a script may name. Review
/// focus 1 and 2: how a name a human typed is matched, and what a second
/// registration under one name does.
@Suite("ScriptWindows", .serialized)
@MainActor
struct ScriptWindowsTests {

    init() { ScriptWindows.reset() }

    private func entry(_ name: String, _ window: NSWindow? = nil) -> ScriptWindow {
        ScriptWindow(name: name, window: { window }, present: {})
    }

    @Test("lookup trims and ignores case")
    func lookupTrimsAndIgnoresCase() {
        ScriptWindows.register(entry("settings"))
        #expect(ScriptWindows.named("  Settings ")?.name == "settings")
        #expect(ScriptWindows.named("SETTINGS")?.name == "settings")
    }

    @Test("unknown names and non-strings answer nil")
    func unknownAndNonString() {
        ScriptWindows.register(entry("main"))
        #expect(ScriptWindows.named("permissions") == nil)
        #expect(ScriptWindows.named(42) == nil)
        #expect(ScriptWindows.named(nil) == nil)
        #expect(ScriptWindows.named("") == nil)
    }

    @Test("names and first follow registration order")
    func orderIsRegistrationOrder() {
        ScriptWindows.register(entry("main"))
        ScriptWindows.register(entry("settings"))
        #expect(ScriptWindows.names == ["main", "settings"])
        #expect(ScriptWindows.first?.name == "main")
    }

    @Test("re-registering a name replaces it in place")
    func testReRegisteringANameReplacesInPlace() {
        let old = NSWindow()
        let new = NSWindow()
        ScriptWindows.register(entry("main", old))
        ScriptWindows.register(entry("settings"))
        ScriptWindows.register(entry("main", new))
        #expect(ScriptWindows.names == ["main", "settings"])
        #expect(ScriptWindows.named("main")?.window() === new)
    }

    @Test("valid names are lowercase kebab", arguments: [
        ("main", true), ("settings", true), ("log-viewer", true), ("pane2", true),
        ("Main", false), ("", false), ("-main", false), ("main-", false),
        ("main window", false), ("main:1", false), ("main_window", false)
    ])
    func validNames(name: String, valid: Bool) {
        #expect(ScriptWindows.isValidName(name) == valid)
    }

    @Test("process facts default to none")
    func processFactsDefaultEmpty() {
        #expect(ScriptWindows.processFacts().isEmpty)
    }
}
