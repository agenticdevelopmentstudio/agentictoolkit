import XCTest
@testable import AgenticToolkitMacOS

/// The pure pane-resolution + AppleScript-building used to inject text into (or select)
/// a live terminal pane. Covers the risky string assembly and escaping without driving a
/// real terminal (only `inject`/`run` execute AppleScript, which has no unit-testable
/// surface).
final class TerminalTextInjectorTests: XCTestCase {

    // MARK: - isSupported

    func testSupportedTerminals() {
        XCTAssertTrue(TerminalTextInjector.isSupported(termProgram: "iTerm.app"))
        XCTAssertTrue(TerminalTextInjector.isSupported(termProgram: "Apple_Terminal"))
        XCTAssertFalse(TerminalTextInjector.isSupported(termProgram: "WarpTerminal"))
        XCTAssertFalse(TerminalTextInjector.isSupported(termProgram: ""))
    }

    // MARK: - resolveTarget

    func testResolvesITermBySessionUUID() {
        let target = TerminalTextInjector.resolveTarget(
            termProgram: "iTerm.app", termSessionId: "w0t1p0:ABC-123", pid: 0
        )
        XCTAssertEqual(target, .iTermSession(uuid: "ABC-123"), "iTerm prefers its session id (no live pid needed)")
    }

    func testITermWithoutSessionIdAndDeadPidIsUnresolvable() {
        // pid 0 → ttyForPid returns nil → nothing precise to target.
        XCTAssertNil(TerminalTextInjector.resolveTarget(termProgram: "iTerm.app", termSessionId: "", pid: 0))
    }

    func testTerminalWithoutLivePidIsUnresolvable() {
        XCTAssertNil(TerminalTextInjector.resolveTarget(termProgram: "Apple_Terminal", termSessionId: "", pid: 0))
    }

    func testUnsupportedTerminalHasNoTarget() {
        XCTAssertNil(TerminalTextInjector.resolveTarget(termProgram: "WarpTerminal", termSessionId: "x:y", pid: 4242))
    }

    // MARK: - script (inject)

    func testITermScriptWritesTextToMatchedSession() {
        let script = TerminalTextInjector.script(
            for: .iTermSession(uuid: "ABC"), text: "/compact", raising: false)
        XCTAssertTrue(script.contains("com.googlecode.iterm2"))
        XCTAssertTrue(script.contains("id of s is \"ABC\""))
        XCTAssertTrue(script.contains("write text \"/compact\""))
        XCTAssertTrue(script.contains("return \"not_found\""), "falls through to a miss signal")
    }

    func testITermTTYScriptMatchesByTTY() {
        let script = TerminalTextInjector.script(
            for: .iTermTTY(tty: "/dev/ttys003"), text: "/compact", raising: false)
        XCTAssertTrue(script.contains("tty of s is \"/dev/ttys003\""))
        XCTAssertTrue(script.contains("write text \"/compact\""))
    }

    func testTerminalScriptRunsDoScriptInMatchedTab() {
        let script = TerminalTextInjector.script(
            for: .terminalTTY(tty: "ttys004"), text: "/compact", raising: false)
        XCTAssertTrue(script.contains("tell application \"Terminal\""))
        XCTAssertTrue(script.contains("tty of t is \"/dev/ttys004\""), "a bare tty gets the /dev/ prefix")
        XCTAssertTrue(script.contains("do script \"/compact\" in t"))
    }

    func testScriptEscapesInjectedText() {
        let script = TerminalTextInjector.script(
            for: .iTermSession(uuid: "x"), text: #"say "hi""#, raising: false)
        XCTAssertTrue(script.contains(#"write text "say \"hi\"""#), script)
    }

    // MARK: - script (raising: false — typing into a session nobody asked to visit)

    func testITermInjectionDoesNotRaiseTheTerminal() {
        let script = TerminalTextInjector.script(
            for: .iTermSession(uuid: "ABC"), text: "/compact", raising: false)
        XCTAssertTrue(script.contains("write text \"/compact\""), "the line is still delivered")
        XCTAssertFalse(script.contains("activate"), "sending a line must not take the screen")
        XCTAssertFalse(script.contains("select s"))
        XCTAssertFalse(script.contains("select t"))
    }

    func testTerminalInjectionDoesNotRaiseTheTerminal() {
        let script = TerminalTextInjector.script(
            for: .terminalTTY(tty: "ttys004"), text: "/compact", raising: false)
        XCTAssertTrue(script.contains("do script \"/compact\" in t"), "the line is still delivered")
        XCTAssertFalse(script.contains("activate"), "sending a line must not take the screen")
        XCTAssertFalse(script.contains("set frontmost"))
        XCTAssertFalse(script.contains("set selected tab"))
    }

    func testITermInjectionCanRaiseWhenAsked() {
        let script = TerminalTextInjector.script(
            for: .iTermSession(uuid: "ABC"), text: "/compact", raising: true)
        XCTAssertTrue(script.contains("write text \"/compact\""))
        XCTAssertTrue(script.contains("activate"), "raising is still available to a caller that wants it")
        XCTAssertTrue(script.contains("select s"))
    }

    // MARK: - script (select-only, text: nil — the click-action variant)

    func testITermSelectOnlyScriptOmitsWriteText() {
        let script = TerminalTextInjector.script(
            for: .iTermSession(uuid: "ABC"), text: nil, raising: true)
        XCTAssertTrue(script.contains("id of s is \"ABC\""))
        XCTAssertTrue(script.contains("select s"))
        XCTAssertTrue(script.contains("activate"))
        XCTAssertFalse(script.contains("write text"), "select-only must never type into the pane")
    }

    func testTerminalSelectOnlyScriptOmitsDoScript() {
        let script = TerminalTextInjector.script(
            for: .terminalTTY(tty: "ttys004"), text: nil, raising: true)
        XCTAssertTrue(script.contains("tty of t is \"/dev/ttys004\""))
        XCTAssertTrue(script.contains("set selected tab of w to t"))
        XCTAssertFalse(script.contains("do script"), "select-only must never run anything in the tab")
    }

    // MARK: - escape / normalizeTTY

    func testEscapeQuotesAndBackslashes() {
        XCTAssertEqual(TerminalTextInjector.escape(#"a"b\c"#), #"a\"b\\c"#)
    }

    /// A newline becomes a space, not nothing. Deleting it welded the last word
    /// of one line to the first of the next — "…the fileimport it" — and the
    /// session was sent a line it was never shown. A space is what a terminal
    /// line-edit buffer can hold and what the sender meant by the break.
    func testEscapeTurnsNewlinesIntoSpaces() {
        XCTAssertEqual(TerminalTextInjector.escape("first\nsecond"), "first second")
        XCTAssertEqual(TerminalTextInjector.escape("a\nb\rc\r\nd"), "a b c d")
    }

    /// A NUL still goes: nothing can carry it, and it has no width to preserve.
    func testEscapeDropsNulls() {
        XCTAssertEqual(TerminalTextInjector.escape("a\0b"), "ab")
    }

    func testNormalizeTTYAddsDevPrefix() {
        XCTAssertEqual(TerminalTextInjector.normalizeTTY("ttys001"), "/dev/ttys001")
        XCTAssertEqual(TerminalTextInjector.normalizeTTY("/dev/ttys001"), "/dev/ttys001")
    }
}
