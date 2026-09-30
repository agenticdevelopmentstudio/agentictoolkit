import AgenticToolkitCore
import Foundation

/// Claude Code's own login item — `Claude Code-credentials` in the login
/// keychain — read and written through `/usr/bin/security`, never in-process.
///
/// **Why a child process, when `ClaudeKeychain` goes out of its way not to use
/// one.** That rule is right for the app's own items and wrong for this
/// one. Claude Code creates this item with `security(1)`, so its partition list
/// is `apple-tool:` alone and its ACL trusts `/usr/bin/security`. The app is
/// signed by a developer team, and macOS checks the caller's `teamid:` against
/// that partition list on every access — so an in-process read asks for the
/// login password every time. "Always Allow" adds the app to the ACL, but
/// never to the partition list, so the next read asks again, forever. A switch
/// is several accesses (the read, the write, the autosave that notices the new
/// login), which is how one click became three password prompts and more.
///
/// `security(1)` already satisfies both checks, which is exactly how `claude`
/// itself reads the item without asking. Going through it means no dialog, no
/// grant to lose, and an ACL that is never touched. It is also no new exposure:
/// any process of this user could already run the same command.
///
/// The write goes through `security -i` on stdin rather than as an argument
/// when it fits: argv is visible to `ps`, and this blob holds live tokens. It
/// does not always fit — `security -i` reads at most 4095 characters a line and
/// silently runs whatever it cut off — so a longer blob goes in argv, exactly as
/// Claude Code itself writes it.
public enum ClaudeCodeKeychainItem {

    /// The item `claude` itself reads its login from. Its account attribute is
    /// the Unix user name, which is what Claude Code writes it under.
    public static let service = "Claude Code-credentials"

    public static let securityTool = "/usr/bin/security"

    /// `security` exits 44 when there is no such item.
    public static let itemNotFoundExit: Int32 = 44

    public enum ItemError: Error, LocalizedError, Sendable, Equatable {
        case failed(operation: String, message: String)

        public var errorDescription: String? {
            switch self {
            case .failed(let operation, let message):
                return message.isEmpty
                    ? "Couldn't \(operation)."
                    : "Couldn't \(operation): \(message)"
            }
        }
    }

    /// The stored blob, or nil when Claude Code has no login saved here.
    public static func read(account: String) async throws -> Data? {
        let output = try await ClaudeAuthCLI.run(
            executable: securityTool, arguments: readArguments(account: account), timeout: 30)
        if output.status == itemNotFoundExit { return nil }
        guard output.isSuccess else {
            throw ItemError.failed(
                operation: "read Claude Code's login from the keychain",
                message: output.message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return blob(fromReadOutput: output.stdout)
    }

    /// Replaces the stored blob **in place**.
    ///
    /// `-U` updates the existing item, keeping its ACL and partition list, so
    /// `claude` goes on reading it exactly as before. The caller must have read
    /// the item first: on a missing item `-U` would create one, and the login is
    /// Claude Code's to create.
    public static func update(account: String, data: Data) async throws {
        let invocation = updateInvocation(account: account, data: data)
        let output = try await ClaudeAuthCLI.run(
            executable: securityTool, arguments: invocation.arguments,
            input: invocation.input, timeout: 30)
        guard output.isSuccess else {
            throw ItemError.failed(
                operation: "switch Claude Code's login in the keychain",
                message: redacted(output.message.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }

    // MARK: - Command shapes (pure, tested)

    public static func readArguments(account: String) -> [String] {
        ["find-generic-password", "-w", "-s", service, "-a", account]
    }

    /// The longest line `security -i` reads whole: its buffer is 4096 bytes,
    /// newline included. Anything past it is cut off and the cut-off hex is
    /// still accepted, so an over-long line overwrites the item with garbage.
    public static let interactiveLineLimit = 4095

    /// How to run the update: on stdin when the line fits, in argv when not.
    public static func updateInvocation(account: String, data: Data) -> (arguments: [String], input: Data?) {
        let line = updateCommand(account: account, data: data)
        if line.utf8.count <= interactiveLineLimit {
            return (["-i"], Data(line.utf8))
        }
        return (["add-generic-password", "-U", "-s", service, "-a", account, "-X", hex(data)], nil)
    }

    /// `security`'s own message with any long hex run cut out: a failed `-X`
    /// write echoes what it was given, and that is the credential blob.
    public static func redacted(_ message: String) -> String {
        message.replacing(/[0-9a-fA-F]{33,}/, with: "<redacted>")
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// One `security -i` line. The blob goes as `-X` hex, which needs no
    /// quoting at all; the two names are quoted because the service has a
    /// space in it.
    public static func updateCommand(account: String, data: Data) -> String {
        "add-generic-password -U -s \(quoted(service)) -a \(quoted(account)) -X \(hex(data))\n"
    }

    /// `security -w` prints the password followed by a newline — as text when
    /// every byte is printable ASCII, and as **hex** otherwise, so a blob holding
    /// a single non-ASCII character (an MCP server's display name, say) comes
    /// back encoded. A JSON blob opens with `{`, so it can never be mistaken for
    /// hex.
    public static func blob(fromReadOutput stdout: String) -> Data? {
        let trimmed = stdout.hasSuffix("\n") ? String(stdout.dropLast()) : stdout
        guard !trimmed.isEmpty else { return nil }
        return decodedHex(trimmed) ?? Data(trimmed.utf8)
    }

    private static func decodedHex(_ text: String) -> Data? {
        let bytes = Array(text.utf8)
        guard bytes.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: bytes.count / 2)
        for index in stride(from: 0, to: bytes.count, by: 2) {
            guard let high = hexValue(bytes[index]), let low = hexValue(bytes[index + 1])
            else { return nil }
            data.append(high << 4 | low)
        }
        return data
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
        default: return nil
        }
    }

    private static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
