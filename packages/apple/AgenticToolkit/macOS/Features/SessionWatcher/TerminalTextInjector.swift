import AgenticToolkitPermissions
import AppKit
import Darwin

/// Types a line of text (e.g. `/compact`) into the live terminal pane a session is running
/// in, by scripting iTerm2 / Terminal.app. Host-app-side because only an app holds the TCC
/// Automation grant and a window-server session — a daemon can drive neither.
///
/// It targets the **exact** pane so it never types into the wrong session: iTerm2 by its
/// session id (from `TERM_SESSION_ID`) or, failing that, the pane's TTY; Terminal.app by
/// the tab's TTY. A terminal it can't precisely target fails loudly (`unsupportedTerminal`)
/// rather than guessing — typing into the wrong session is the whole hazard this guards.
///
/// The pane-resolution + AppleScript builders are pure `static` functions so the (risky)
/// string assembly and escaping are unit-tested without driving a real terminal; only
/// `inject` runs `NSAppleScript`. `SessionWatcher.SessionWatcherActionHandler` shares the
/// same builders (with `text: nil`) for its select-and-raise click actions.
public enum TerminalTextInjector {

    public enum InjectionError: Error, LocalizedError, Equatable {
        /// The terminal isn't one we can precisely target (Warp, VS Code, unknown…).
        case unsupportedTerminal(String)
        /// We couldn't build a target (e.g. iTerm with no session id and a dead pid).
        case paneUnresolvable
        /// The matching pane wasn't found among the terminal's open windows/tabs.
        case paneNotFound
        /// Automation permission is needed to control the terminal; carries the
        /// `Permission` the host should route its grant UI to.
        case permissionDenied(String, requiredPermission: AgenticToolkitPermissions.Permission)
        /// AppleScript failed for another reason.
        case scriptFailed(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedTerminal(let name):
                return "Injecting text isn't supported for \(name) yet — only iTerm2 and Terminal.app."
            case .paneUnresolvable:
                return "Couldn't identify the session's terminal pane."
            case .paneNotFound:
                return "The session's terminal pane wasn't found — it may have been closed."
            case .permissionDenied(let message, _):
                return message
            case .scriptFailed(let message):
                return "Terminal automation failed: \(message)"
            }
        }
    }

    /// Terminals this injector can precisely target. A client ANDs this with its own
    /// "should I act" gate before offering the control. Kept in lock-step with
    /// `resolveTarget`.
    public static func isSupported(termProgram: String) -> Bool {
        termProgram == "iTerm.app" || termProgram == "Apple_Terminal"
    }

    /// Inject `text` into the session's pane. Runs `NSAppleScript` on the main thread.
    ///
    /// - Parameter raising: whether to bring that terminal forward as well.
    ///   **Off by default**: sending a line to a session is not a request to go
    ///   and watch it. The sender is reading a window of their own — a merged
    ///   feed, a findings list — and a terminal that jumped in front of it took
    ///   away the thing they were looking at to show them something they can
    ///   already see. Going there is its own gesture, with its own control.
    @MainActor
    public static func inject(
        _ text: String, termProgram: String, termSessionId: String, pid: Int,
        raising: Bool = false
    ) -> Result<Void, InjectionError> {
        guard isSupported(termProgram: termProgram) else {
            return .failure(.unsupportedTerminal(termProgram.isEmpty ? "an unknown terminal" : termProgram))
        }
        guard let target = resolveTarget(termProgram: termProgram, termSessionId: termSessionId, pid: pid) else {
            return .failure(.paneUnresolvable)
        }
        return run(script: script(for: target, text: text, raising: raising), target: target)
    }

    // MARK: - Pure pieces (unit-tested)

    /// The strongest precise pane target for the session's terminal.
    public enum Target: Equatable, Sendable {
        /// iTerm2 pane matched by its session `id` (the uuid from `TERM_SESSION_ID`).
        case iTermSession(uuid: String)
        /// iTerm2 pane matched by the controlling TTY (when no session id is known).
        case iTermTTY(tty: String)
        /// Terminal.app tab matched by the controlling TTY.
        case terminalTTY(tty: String)

        /// The app + bundle id to attribute an Automation-permission failure to.
        public var app: (name: String, bundleID: String) {
            switch self {
            case .iTermSession, .iTermTTY: return ("iTerm2", "com.googlecode.iterm2")
            case .terminalTTY: return ("Terminal", "com.apple.Terminal")
            }
        }
    }

    /// Pick the target, or nil if the terminal is unsupported / unresolvable. iTerm prefers
    /// its session id (survives pane moves, needs no live pid); both fall back to the TTY.
    public static func resolveTarget(termProgram: String, termSessionId: String, pid: Int) -> Target? {
        switch termProgram {
        case "iTerm.app":
            let uuid = termSessionId.split(separator: ":").last.map(String.init) ?? ""
            if !uuid.isEmpty { return .iTermSession(uuid: uuid) }
            if let tty = ttyForPid(Int32(pid)) { return .iTermTTY(tty: tty) }
            return nil
        case "Apple_Terminal":
            if let tty = ttyForPid(Int32(pid)) { return .terminalTTY(tty: tty) }
            return nil
        default:
            return nil
        }
    }

    /// Build the AppleScript that finds `target`'s pane and — when `text` is non-nil —
    /// types it there. `text: nil` is the select-and-raise variant the session click
    /// actions use. Pure → unit-tested.
    ///
    /// - Parameter raising: whether the pane is also selected and its application
    ///   brought forward. True for going *to* a session, false for typing into
    ///   one — see ``inject(_:termProgram:termSessionId:pid:raising:)``. A pane
    ///   takes `write text` / `do script` whether or not anybody is looking at
    ///   it, so this changes who has the screen and nothing about delivery.
    public static func script(for target: Target, text: String?, raising: Bool) -> String {
        let escapedText = text.map(escape)
        switch target {
        case .iTermSession(let uuid):
            return iTermScript(
                match: "id of s is \"\(escape(uuid))\"", text: escapedText, raising: raising)
        case .iTermTTY(let tty):
            return iTermScript(
                match: "tty of s is \"\(escape(normalizeTTY(tty)))\"", text: escapedText,
                raising: raising)
        case .terminalTTY(let tty):
            return terminalScript(
                tty: escape(normalizeTTY(tty)), text: escapedText, raising: raising)
        }
    }

    /// iTerm: find the session (across all windows/tabs/panes) matching `match`, focus it
    /// when `raising`, then — when injecting — `write text` (which appends a newline —
    /// i.e. runs the line, as if typed). Addressed by bundle id, not the name
    /// "iTerm"/"iTerm2", which has varied across versions.
    private static func iTermScript(match: String, text: String?, raising: Bool) -> String {
        let write = text.map { "\n                        tell s to write text \"\($0)\"" } ?? ""
        let raise = raising
            ? "\n                        select s"
                + "\n                        select t"
                + "\n                        activate"
            : ""
        return """
        tell application id "com.googlecode.iterm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if \(match) then\(raise)\(write)
                            return "found"
                        end if
                    end repeat
                end repeat
            end repeat
            return "not_found"
        end tell
        """
    }

    /// Terminal.app: find the tab on `tty`, focus it when `raising`, then — when
    /// injecting — `do script … in <tab>` (which runs the text in that existing tab
    /// rather than opening a new window).
    private static func terminalScript(tty: String, text: String?, raising: Bool) -> String {
        let run = text.map { "\n                    do script \"\($0)\" in t" } ?? ""
        let raise = raising
            ? "\n                        set selected tab of w to t"
                + "\n                        set frontmost of w to true"
                + "\n                        activate"
            : ""
        return """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then\(raise)\(run)
                        return "found"
                    end if
                end repeat
            end repeat
            return "not_found"
        end tell
        """
    }

    /// Escape a string for interpolation inside an AppleScript double-quoted literal:
    /// backslash first (so we don't double-escape our own escapes), then the quote, and
    /// strip control characters that would break out of the line.
    public static func escape(_ string: String) -> String {
        var escaped = string
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return escaped.filter { !$0.isNewline && $0 != "\r" && $0 != "\0" }
    }

    /// Both iTerm's `tty of s` and Terminal's `tty of t` report `/dev/ttysNNN`; ensure the
    /// prefix so a bare `ttysNNN` still matches.
    public static func normalizeTTY(_ tty: String) -> String {
        tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
    }

    /// Controlling-terminal device path for a pid, via the `proc_pidinfo` libproc syscall:
    /// no subprocess, near-instant, and safe to call on the main thread (a forked `ps` +
    /// `waitUntilExit` would block the caller for the lifetime of the fork). Nil for a
    /// dead/invalid pid or a process with no controlling tty.
    public static func ttyForPid(_ pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let read = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, size)
        }
        guard read == size, info.e_tdev != 0 else { return nil }
        let device = dev_t(Int32(bitPattern: info.e_tdev))
        guard let name = devname(device, S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    /// Compile + execute a built script against `target`'s terminal, mapping the outcome
    /// (including the `not_found` sentinel and Automation denials) onto `InjectionError`.
    /// Shared by `inject` and the session click actions' select-and-raise paths.
    @MainActor
    static func run(script source: String, target: Target) -> Result<Void, InjectionError> {
        guard let apple = NSAppleScript(source: source) else {
            return .failure(.scriptFailed("could not compile the AppleScript"))
        }
        var error: NSDictionary?
        let output = apple.executeAndReturnError(&error)
        if let error {
            if let permission = permissionError(error, target: target) {
                return .failure(permission)
            }
            let message = (error[NSAppleScript.errorMessage] as? String) ?? String(describing: error)
            return .failure(.scriptFailed(message))
        }
        if output.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) == "not_found" {
            return .failure(.paneNotFound)
        }
        return .success(())
    }

    /// Map an AppleScript error dict to `.permissionDenied` when it's an Automation denial
    /// (-1743 "Not authorized to send Apple events" / -1744 "A privilege violation
    /// occurred"), else nil.
    private static func permissionError(_ error: NSDictionary, target: Target) -> InjectionError? {
        let number = error[NSAppleScript.errorNumber] as? Int
        let message = (error[NSAppleScript.errorMessage] as? String) ?? ""
        if number == -1743 || number == -1744
            || message.localizedCaseInsensitiveContains("not authorized")
            || message.localizedCaseInsensitiveContains("privilege violation") {
            return .permissionDenied(
                "Automation permission is required to control \(target.app.name)."
                + " Grant it in System Settings ▸ Privacy & Security ▸ Automation.",
                requiredPermission: .automation(targetBundleID: target.app.bundleID)
            )
        }
        return nil
    }
}
