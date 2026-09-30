@testable import AgenticToolkitMacOS
import Foundation
import XCTest

/// `ClaudeCodeKeychainItem` reaches Claude Code's login item through
/// `security(1)` so that switching accounts never asks for the password. These
/// pin the command shapes it sends and the output it parses — the parts that
/// can be wrong without any dialog to show it.
final class ClaudeCodeKeychainItemTests: XCTestCase {

    func testReadAsksSecurityForThePasswordOnlyOfClaudeCodesItem() {
        XCTAssertEqual(
            ClaudeCodeKeychainItem.readArguments(account: "someone"),
            ["find-generic-password", "-w", "-s", "Claude Code-credentials", "-a", "someone"])
    }

    /// `-U` is what keeps the item's ACL and partition list — without it the
    /// write would fail on the existing item, and a delete-then-add would lock
    /// `claude` out of its own login.
    func testUpdateIsAnInPlaceUpdateCarryingTheBlobAsHex() {
        let command = ClaudeCodeKeychainItem.updateCommand(
            account: "someone", data: Data(#"{"a":"b"}"#.utf8))
        XCTAssertEqual(
            command,
            #"add-generic-password -U -s "Claude Code-credentials" -a "someone" -X 7b2261223a2262227d"#
                + "\n")
    }

    /// The secret goes as hex on stdin, so nothing in it — quotes, spaces,
    /// newlines — can break the command line or leak into argv.
    func testUpdateCommandIsOneLineWhateverTheBlobHolds() {
        let command = ClaudeCodeKeychainItem.updateCommand(
            account: "someone", data: Data("\"tricky\"\n value".utf8))
        XCTAssertEqual(command.filter { $0 == "\n" }.count, 1)
        XCTAssertFalse(command.contains("tricky"))
    }

    func testABlobThatFitsGoesOnStdin() {
        let invocation = ClaudeCodeKeychainItem.updateInvocation(
            account: "someone", data: Data(#"{"a":"b"}"#.utf8))
        XCTAssertEqual(invocation.arguments, ["-i"])
        XCTAssertNotNil(invocation.input)
    }

    /// `security -i` reads 4095 characters a line and silently runs the rest as
    /// a second command, having already written the truncated hex over the item.
    /// A blob with a couple of MCP authorizations in it is past that.
    func testABlobTooLongForOneInteractiveLineGoesInArgvWhole() {
        let data = Data(repeating: UInt8(ascii: "x"), count: 2100)
        let invocation = ClaudeCodeKeychainItem.updateInvocation(account: "someone", data: data)
        XCTAssertNil(invocation.input)
        XCTAssertEqual(
            Array(invocation.arguments.prefix(7)),
            ["add-generic-password", "-U", "-s", "Claude Code-credentials", "-a", "someone", "-X"])
        XCTAssertEqual(invocation.arguments.last?.count, 4200, "every byte, as hex")
    }

    func testTheLongestLineThatFitsStillGoesOnStdin() {
        let prefix = ClaudeCodeKeychainItem.updateCommand(account: "someone", data: Data()).utf8.count
        let fits = (ClaudeCodeKeychainItem.interactiveLineLimit - prefix) / 2
        XCTAssertEqual(
            ClaudeCodeKeychainItem.updateInvocation(
                account: "someone", data: Data(count: fits)).arguments, ["-i"])
        XCTAssertNotEqual(
            ClaudeCodeKeychainItem.updateInvocation(
                account: "someone", data: Data(count: fits + 1)).arguments, ["-i"])
    }

    func testAFailedWriteNeverEchoesTheBlobIntoTheError() {
        let hex = String(repeating: "7b22", count: 20)
        XCTAssertEqual(
            ClaudeCodeKeychainItem.redacted("unknown command \(hex)\nfailed"),
            "unknown command <redacted>\nfailed")
    }

    func testReadOutputDropsTheTrailingNewline() {
        XCTAssertEqual(
            ClaudeCodeKeychainItem.blob(fromReadOutput: "{\"a\":1}\n"), Data("{\"a\":1}".utf8))
    }

    /// `security -w` switches to hex as soon as one byte is not printable ASCII.
    func testReadOutputDecodesTheHexSecurityPrintsForNonASCII() {
        let json = #"{"name":"Zoë — café"}"#
        let hex = Data(json.utf8).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(ClaudeCodeKeychainItem.blob(fromReadOutput: hex + "\n"), Data(json.utf8))
    }

    func testEmptyReadOutputIsNoBlob() {
        XCTAssertNil(ClaudeCodeKeychainItem.blob(fromReadOutput: "\n"))
    }
}
