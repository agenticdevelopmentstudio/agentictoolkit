import AppKit
import Testing
@testable import AgenticToolkitScripting

/// Review focus 3: the `window list` reply's process facts.
@Suite("WindowScriptCommands", .serialized)
@MainActor
struct WindowScriptCommandsTests {

    init() { ScriptWindows.reset() }

    private func windowList() throws -> [String: Any] {
        let reply = ScriptWindowListCommand.reply()
        let data = try #require(reply.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("with no host facts the reply still names the process")
    func noFacts() throws {
        let json = try windowList()
        #expect(json["pid"] as? Int32 == ProcessInfo.processInfo.processIdentifier
                || json["pid"] as? Int == Int(ProcessInfo.processInfo.processIdentifier))
        #expect(json["bundle_path"] as? String == Bundle.main.bundlePath)
        #expect(json["windows"] is [Any])
    }

    @Test("host facts are merged in")
    func factsMerged() throws {
        ScriptWindows.processFacts = { ["quiet_presentation": true] }
        #expect(try windowList()["quiet_presentation"] as? Bool == true)
    }

    @Test("a host fact never overwrites a built-in key")
    func builtInsWin() throws {
        ScriptWindows.processFacts = { ["pid": -1, "bundle_path": "x", "windows": "x"] }
        let json = try windowList()
        #expect(json["bundle_path"] as? String == Bundle.main.bundlePath)
        #expect(json["windows"] is [Any])
    }

    @Test("screenshot file names carry no spaces")
    func screenshotName() {
        let url = ScriptScreenshotWindowCommand.destination(
            windowName: "main",
            processName: "Agentic Developer Hub",
            stamp: "2026-09-24T10-00-00Z"
        )
        #expect(url.path == "/tmp/agentic-developer-hub-main-2026-09-24T10-00-00Z.png")
    }
}
