import AppKit
import Testing
@testable import AgenticToolkitScripting

@Suite("ScriptJSON")
struct ScriptJSONTests {
    @Test("frames are four doubles")
    func frame() {
        #expect(ScriptJSON.frame(NSRect(x: 1, y: 2, width: 3, height: 4))
                == ["x": 1, "y": 2, "width": 3, "height": 4])
    }

    @Test("keys are sorted so replies diff cleanly")
    func sortedKeys() {
        let text = ScriptJSON.string(from: ["b": 1, "a": 2])
        #expect(text.range(of: "\"a\"")!.lowerBound < text.range(of: "\"b\"")!.lowerBound)
    }

    @Test("an unencodable object answers {} rather than crashing")
    func invalidObject() {
        #expect(ScriptJSON.string(from: ["date": Date()]) == "{}")
    }
}
