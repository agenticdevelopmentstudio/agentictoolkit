import AgenticToolkitCore
import AgenticToolkitDatabase
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS
import AgenticToolkitPermissions

import AppKit
import ApplicationServices
import Darwin
import UserNotifications
import os

extension SessionWatcher {

    /// Errors that can occur when executing a session click action.
    public enum SessionWatcherActionError: Error, LocalizedError {
        case directoryNotFound(String)
        case transcriptNotFound(String)
        case commandFailed(String)
        case notificationFailed(String)
        case noActionConfigured
        case permissionDenied(String, requiredPermission: AgenticToolkitPermissions.Permission)

        public var errorDescription: String? {
            switch self {
            case .directoryNotFound(let path):
                return "Directory not found: \(path)"
            case .transcriptNotFound(let path):
                return "Transcript file not found: \(path)"
            case .commandFailed(let message):
                return "Command failed: \(message)"
            case .notificationFailed(let message):
                return "Notification failed: \(message)"
            case .noActionConfigured:
                return "No click action configured"
            case .permissionDenied(let message, _):
                return message
            }
        }

        /// If this is a permission error, the permission the user needs to grant.
        public var requiredPermission: AgenticToolkitPermissions.Permission? {
            if case .permissionDenied(_, let permission) = self { return permission }
            return nil
        }
    }

    /// Result of executing a session click action.
    public enum SessionWatcherActionResult {
        case success
        case failure(SessionWatcherActionError)
    }

    /// Handles execution of session click actions.
    public final class SessionWatcherActionHandler: @unchecked Sendable {

        // MARK: - Settings Keys

        public static let clickActionKey = "click_action"
        public static let customCommandKey = "custom_command_template"

        // MARK: - Accessibility

        /// Checks whether accessibility access has been granted. Does NOT prompt.
        public static var isAccessibilityTrusted: Bool {
            AXIsProcessTrusted()
        }

        // MARK: - Properties

        private let settingsStore: SettingsStore

        // MARK: - Initialization

        public init(settingsStore: SettingsStore) {
            self.settingsStore = settingsStore
        }

        // MARK: - Configuration

        public var currentAction: SessionWatcherClickAction {
            // SettingsStore is @MainActor; callers (UI clicks) run on the main actor.
            let raw: String = MainActor.assumeIsolated {
                settingsStore.get(UserSettings.clickAction)
            }
            return SessionWatcherClickAction(rawValue: raw) ?? .activateWindow
        }

        public func setAction(_ action: SessionWatcherClickAction) {
            let rawValue = action.rawValue
            MainActor.assumeIsolated {
                settingsStore.set(rawValue, for: UserSettings.clickAction)
            }
        }

        public var customCommandTemplate: String {
            let value: String = MainActor.assumeIsolated {
                settingsStore.get(UserSettings.customCommandTemplate)
            }
            return value.isEmpty ? "echo $SESSION_ID $CWD $MODEL" : value
        }

        public func setCustomCommandTemplate(_ template: String) {
            MainActor.assumeIsolated {
                settingsStore.set(template, for: UserSettings.customCommandTemplate)
            }
        }

        // MARK: - Execution

        @discardableResult
        public func execute(for session: SessionWatcherSession) -> SessionWatcherActionResult {
            let action = currentAction
            // swiftlint:disable:next line_length
            logger.info("SessionWatcherSession clicked: \(session.sessionId, privacy: .public) project=\(session.projectName, privacy: .public) cwd=\(session.cwd, privacy: .public) action=\(action.rawValue, privacy: .public)")
            return execute(action: action, for: session)
        }

        @discardableResult
        public func execute(
            action: SessionWatcherClickAction,
            for session: SessionWatcherSession
        ) -> SessionWatcherActionResult {
            // swiftlint:disable:next line_length
            logger.info("Executing action '\(action.rawValue, privacy: .public)' for session \(session.sessionId, privacy: .public)")
            let result: SessionWatcherActionResult
            switch action {
            case .openTerminal:
                result = openTerminal(at: session.cwd)
            case .activateWarp:
                result = activateWarpSession(for: session)
            case .activateWindow:
                result = activateMatchingWindow(for: session)
            case .openTranscript:
                result = openTranscript(for: session)
            case .copySessionId:
                result = copySessionId(session.sessionId)
            case .customCommand:
                result = runCustomCommand(for: session)
            case .sendNotification:
                result = sendNotification(for: session)
            }

            switch result {
            case .success:
                logger.info("Action '\(action.rawValue, privacy: .public)' succeeded")
            case .failure(let error):
                // swiftlint:disable:next line_length
                logger.error("Action '\(action.rawValue, privacy: .public)' failed: \(error.localizedDescription, privacy: .public)")
            }
            return result
        }

        // MARK: - Open Terminal

        private func openTerminal(at path: String) -> SessionWatcherActionResult {
            logger.debug("openTerminal: path='\(path, privacy: .public)'")
            guard !path.isEmpty else {
                logger.warning("openTerminal: empty path")
                return .failure(.directoryNotFound(""))
            }

            let expandedPath = (path as NSString).expandingTildeInPath
            logger.debug("openTerminal: expandedPath='\(expandedPath, privacy: .public)'")
            guard FileManager.default.fileExists(atPath: expandedPath) else {
                logger.warning("openTerminal: directory does not exist")
                return .failure(.directoryNotFound(expandedPath))
            }

            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil {
                logger.debug("openTerminal: using iTerm2")
                let escapedPath = TerminalTextInjector.escape(expandedPath)
                let script = """
                tell application id "com.googlecode.iterm2"
                    activate
                    create window with default profile command "cd \(escapedPath) && exec $SHELL -l"
                end tell
            """
                var error: NSDictionary?
                if let appleScript = NSAppleScript(source: script) {
                    appleScript.executeAndReturnError(&error)
                    if let error = error {
                        logger.warning("openTerminal: iTerm2 error: \(String(describing: error), privacy: .public)")
                        if let permError = appleScriptPermissionError(
                            error, appName: "iTerm2", bundleID: "com.googlecode.iterm2"
                        ) {
                            return .failure(permError)
                        }
                        return openTerminalApp(at: expandedPath)
                    }
                    return .success
                }
                return openTerminalApp(at: expandedPath)
            } else {
                logger.debug("openTerminal: using Terminal.app")
                return openTerminalApp(at: expandedPath)
            }
        }

        private func openTerminalApp(at path: String) -> SessionWatcherActionResult {
            let script = """
            tell application "Terminal"
                activate
                do script "cd \(TerminalTextInjector.escape(path))"
            end tell
        """
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    if let permError = appleScriptPermissionError(
                        error, appName: "Terminal", bundleID: "com.apple.Terminal"
                    ) {
                        return .failure(permError)
                    }
                    return .failure(.commandFailed("Terminal.app script error: \(error)"))
                }
                return .success
            }
            return .failure(.commandFailed("Failed to create AppleScript for Terminal.app"))
        }

        // MARK: - Activate Warp SessionWatcherSession

        private func activateWarpSession(for session: SessionWatcherSession) -> SessionWatcherActionResult {
            // swiftlint:disable:next line_length
            logger.info("activateWarp: cwd='\(session.cwd, privacy: .public)' project='\(session.projectName, privacy: .public)'")

            guard !session.cwd.isEmpty else {
                logger.warning("activateWarp: empty cwd")
                return .failure(.directoryNotFound(""))
            }

            // Check Warp is running
            let warpApps = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.warp.Warp-Stable")
            logger.info("activateWarp: found \(warpApps.count) running Warp instance(s)")
            guard let warpApp = warpApps.first else {
                logger.warning("activateWarp: Warp is not running")
                return .failure(.commandFailed("Warp is not running"))
            }

            let warpPID = warpApp.processIdentifier
            logger.debug("activateWarp: Warp PID=\(warpPID)")

            let expandedCwd = (session.cwd as NSString).expandingTildeInPath
            let projectName = session.projectName
            // swiftlint:disable:next line_length
            logger.debug("activateWarp: looking for window matching project='\(projectName, privacy: .public)' or cwd='\(expandedCwd, privacy: .public)'")

            // Strategy 1: Use CGWindowList to find Warp windows and match by title
            let windowListOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
            let cgWindows = CGWindowListCopyWindowInfo(windowListOptions, kCGNullWindowID) as? [[String: Any]]
            guard let windowList = cgWindows else {
                logger.error("activateWarp: CGWindowListCopyWindowInfo returned nil")
                return .failure(.commandFailed("Unable to read window list"))
            }

            var warpWindows: [(name: String, number: Int, layer: Int)] = []
            for entry in windowList {
                guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                      ownerPID == warpPID else { continue }

                let name = entry[kCGWindowName as String] as? String ?? "<no title>"
                let number = entry[kCGWindowNumber as String] as? Int ?? -1
                let layer = entry[kCGWindowLayer as String] as? Int ?? -1
                warpWindows.append((name: name, number: number, layer: layer))
                logger.debug("activateWarp: Warp window #\(number) layer=\(layer) title='\(name, privacy: .public)'")
            }

            logger.info("activateWarp: found \(warpWindows.count) Warp window(s) on screen")

            if warpWindows.isEmpty {
                // Warp is running but no on-screen windows — just activate it
                logger.info("activateWarp: no on-screen windows, just activating Warp")
                warpApp.activate()
                return .success
            }

            // Try to find a matching window by title
            // Warp window titles typically show: "projectName — command" or the cwd path
            let matchCandidates = [projectName, expandedCwd, (expandedCwd as NSString).lastPathComponent]
            logger.debug("activateWarp: match candidates: \(matchCandidates, privacy: .public)")

            var bestMatch: (name: String, number: Int)?
            for candidate in matchCandidates {
                guard !candidate.isEmpty else { continue }
                for entry in warpWindows where entry.layer == 0 { // layer 0 = normal windows
                    if entry.name.localizedCaseInsensitiveContains(candidate) {
                        // swiftlint:disable:next line_length
                        logger.info("activateWarp: matched window #\(entry.number) title='\(entry.name, privacy: .public)' via candidate='\(candidate, privacy: .public)'")
                        bestMatch = (name: entry.name, number: entry.number)
                        break
                    }
                }
                if bestMatch != nil { break }
            }

            // Check accessibility permission upfront — don't re-prompt if already denied
            guard Self.isAccessibilityTrusted else {
                logger.error("activateWarp: Accessibility permission not granted")
                return .failure(.permissionDenied(
                    "Accessibility access is required to raise Warp windows. Grant it in System Settings.",
                    requiredPermission: .accessibility
                ))
            }

            // Strategy 2: Use Accessibility API to find and raise the matching window
            logger.debug("activateWarp: querying Accessibility API for Warp windows")
            let axApp = AXUIElementCreateApplication(warpPID)
            var axWindowsRef: CFTypeRef?
            let axResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &axWindowsRef)

            if axResult != .success {
                logger.warning("activateWarp: AXUIElementCopyAttributeValue failed with \(axResult.rawValue)")
            }

            let axWindows = (axWindowsRef as? [AXUIElement]) ?? []
            logger.debug("activateWarp: Accessibility found \(axWindows.count) window(s)")

            for (index, window) in axWindows.enumerated() {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                let axTitle = titleRef as? String ?? "<no title>"
                logger.debug("activateWarp: AX window[\(index)] title='\(axTitle, privacy: .public)'")
            }

            // Activate Warp first
            logger.debug("activateWarp: activating Warp app")
            warpApp.activate()

            if let match = bestMatch {
                // Raise the specific window via Accessibility
                logger.info("activateWarp: raising matched window '\(match.name, privacy: .public)'")
                for window in axWindows {
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                    if let title = titleRef as? String, title == match.name {
                        let raiseResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                        logger.debug("activateWarp: AXRaise result=\(raiseResult.rawValue)")
                        return .success
                    }
                }
                // Couldn't raise via AX but we matched — Warp is activated at least
                logger.info("activateWarp: could not raise via AX, but Warp is now frontmost")
                return .success
            }

            // No title match — fall back to raising the first normal-layer window
            if let firstNormal = warpWindows.first(where: { $0.layer == 0 }) {
                // swiftlint:disable:next line_length
                logger.info("activateWarp: no title match, raising first window '\(firstNormal.name, privacy: .public)'")
                for window in axWindows {
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                    if let title = titleRef as? String, title == firstNormal.name {
                        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                        return .success
                    }
                }
            }

            logger.info("activateWarp: no match found, Warp activated without specific window")
            return .success
        }

        // MARK: - Activate Matching Window (any app)

        private func activateMatchingWindow(for session: SessionWatcherSession) -> SessionWatcherActionResult {
            let projectName = session.projectName
            let branch = session.gitBranch
            let log = ActivationTestLog.whippetShared
            log.append("activateMatchingWindow: project=\"\(projectName)\" branch=\"\(branch)\" cwd=\"\(session.cwd)\"")

            guard projectName != "Unknown" else {
                return .failure(.commandFailed("No project name to match — session has no working directory"))
            }

            // Strategy 1: For iTerm2 sessions, try TTY-based tab activation first.
            // iTerm2 window titles show Claude's session names, not project names,
            // so AX title matching won't work. TTY matching is precise. This path
            // drives iTerm2 via AppleScript, which needs Automation permission
            // (not Accessibility) — so it runs *before* the Accessibility gate, and
            // surfaces an Automation permission error if denied.
            if session.termProgram == "iTerm.app" {
                // Strongest signal: the recorded TERM_SESSION_ID maps directly to an
                // iTerm session `id` — precise, and doesn't need a live pid. That env
                // var is "<window/tab/pane>:<uuid>"; iTerm's `id of session` is the
                // uuid (an id without ":" is used whole).
                if !session.termSessionId.isEmpty {
                    log.append("  iTerm session-id strategy: \(session.termSessionId)")
                    let uuid = session.termSessionId.split(separator: ":").last.map(String.init)
                        ?? session.termSessionId
                    switch activateITerm(target: .iTermSession(uuid: uuid)) {
                    case .activated:
                        log.append("  iTerm session-id activation succeeded")
                        return .success
                    case .permissionDenied(let error):
                        log.append("  iTerm session-id activation denied — needs Automation permission")
                        return .failure(error)
                    case .notFound:
                        log.append("  iTerm session-id activation: no match")
                    }
                }
                if session.pid > 0, let tty = TerminalTextInjector.ttyForPid(session.pid) {
                    log.append("  iTerm TTY strategy: pid=\(session.pid) tty=\(tty)")
                    switch activateITerm(target: .iTermTTY(tty: tty)) {
                    case .activated:
                        log.append("  iTerm TTY activation succeeded")
                        return .success
                    case .permissionDenied(let error):
                        log.append("  iTerm TTY activation denied — needs Automation permission")
                        return .failure(error)
                    case .notFound:
                        log.append("  iTerm TTY activation: no match")
                    }
                }
                // No TTY, or no tab matched. The AX title-scan can't match iTerm2
                // (its window titles carry session names, not project names), so
                // bring iTerm2 forward — which needs no permission — rather than
                // failing the Accessibility gate below with a misleading error.
                if let iterm = NSRunningApplication.runningApplications(
                    withBundleIdentifier: "com.googlecode.iterm2"
                ).first {
                    log.append("  iTerm: no tab match — activating iTerm2 app")
                    iterm.activate()
                    return .success
                }
            }

            // Strategy 2 onward scans windows via the Accessibility API, which needs
            // Accessibility permission. Check it here — after the iTerm2 path — so an
            // iTerm2 switch isn't blocked on the wrong permission.
            guard Self.isAccessibilityTrusted else {
                return .failure(.permissionDenied(
                    "Accessibility access is required to discover windows. Grant it in System Settings.",
                    requiredPermission: .accessibility
                ))
            }

            // Strategy 2: Collect all candidate windows across all apps, scored by match quality
            struct Candidate {
                let app: NSRunningApplication
                let axApp: AXUIElement
                let axWindow: AXUIElement
                let title: String
                let score: Int
            }

            var candidates: [Candidate] = []

            let ownBundleId = Bundle.main.bundleIdentifier ?? ""
            for app in NSWorkspace.shared.runningApplications {
                guard app.activationPolicy == .regular else { continue }
                // Never match our own windows (e.g. Window Discovery panel)
                if app.bundleIdentifier == ownBundleId { continue }
                let pid = app.processIdentifier
                let axApp = AXUIElementCreateApplication(pid)
                var windowsRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                      let axWindows = windowsRef as? [AXUIElement] else { continue }

                for axWindow in axWindows {
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
                    guard let title = titleRef as? String, !title.isEmpty else { continue }

                    // Match on project name OR cwd path components
                    let cwdLastComponent = (session.cwd as NSString).lastPathComponent
                    let matchesProject = title.localizedCaseInsensitiveContains(projectName)
                    let matchesCwd = !session.cwd.isEmpty && title.localizedCaseInsensitiveContains(cwdLastComponent)
                    let matchesCwdFull = !session.cwd.isEmpty && title.localizedCaseInsensitiveContains(session.cwd)
                    guard matchesProject || matchesCwd || matchesCwdFull else { continue }

                    // Score: higher is better
                    var score = matchesProject ? 1 : 0
                    if matchesCwdFull { score += 3 }
                    if matchesCwd { score += 1 }

                    // +2 if title ends with "*" (Warp marks active/modified tabs)
                    if title.hasSuffix("*") {
                        score += 2
                    }

                    // +10 if branch also matches in the title
                    if !branch.isEmpty && title.localizedCaseInsensitiveContains(branch) {
                        score += 10
                    }

                    // +5 if the full cwd last two components match (e.g., "projects/Whippet")
                    let cwdComponents = session.cwd.split(separator: "/").suffix(2)
                    if cwdComponents.count == 2 {
                        let twoLevel = cwdComponents.joined(separator: "/")
                        if title.localizedCaseInsensitiveContains(twoLevel) {
                            score += 5
                        }
                    }

                    // +20 if this app matches the session's terminal program
                    let bundleId = app.bundleIdentifier ?? ""
                    if !session.termProgram.isEmpty {
                        if (session.termProgram == "WarpTerminal" && bundleId.contains("warp"))
                            || (session.termProgram == "Apple_Terminal" && bundleId.contains("Terminal"))
                            || (session.termProgram == "iTerm.app" && bundleId.contains("iterm"))
                            || (session.termProgram == "vscode" && bundleId.contains("VSCode")) {
                            score += 20
                        }
                    } else {
                        // No termProgram recorded — prefer known terminal apps
                        if bundleId.contains("warp") || bundleId.contains("Terminal")
                            || bundleId.contains("iterm") || bundleId.contains("VSCode") {
                            score += 10
                        }
                    }

                    candidates.append(Candidate(app: app, axApp: axApp, axWindow: axWindow, title: title, score: score))
                }
            }

            // Sort by score descending (stable sort preserves window order for ties)
            let sorted = candidates.sorted { $0.score > $1.score }

            log.append("  Candidates: \(sorted.count)")
            for (index, candidate) in sorted.enumerated() {
                log.append("    [\(index)] score=\(candidate.score) \"\(candidate.title)\"")
            }

            guard !sorted.isEmpty else {
                log.append("  No match found")
                return .failure(.commandFailed("No window found matching \"\(projectName)\""))
            }

            // If the frontmost window already matches this project, cycle to the next one.
            // This handles multiple sessions in the same project (e.g., two Whippet tabs).
            let best: Candidate
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               let firstCandidate = sorted.first,
               firstCandidate.app.processIdentifier == frontApp.processIdentifier {
                // Get the current main window's AX element for identity comparison
                let axFrontApp = AXUIElementCreateApplication(frontApp.processIdentifier)
                var mainRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axFrontApp, kAXMainWindowAttribute as CFString, &mainRef)
                let currentMain: AXUIElement? = mainRef.map { unsafeDowncast($0, to: AXUIElement.self) }
                var currentTitle = ""
                if let main = currentMain {
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(main, kAXTitleAttribute as CFString, &titleRef)
                    currentTitle = (titleRef as? String) ?? ""
                }

                if currentTitle.localizedCaseInsensitiveContains(projectName),
                   sorted.count > 1,
                   let currentMainWindow = currentMain {
                    // Current window already matches — cycle to the next AX element.
                    // Compare by AX element identity (CFEqual), not title, since
                    // multiple tabs can have identical titles.
                    if let next = sorted.first(where: { !CFEqual($0.axWindow, currentMainWindow) }) {
                        best = next
                        log.append("  Cycling: current=\"\(currentTitle)\" → next=\"\(best.title)\"")
                    } else {
                        best = sorted[0]
                        log.append("  Only one AX element, using first")
                    }
                } else {
                    best = sorted[0]
                }
            } else {
                best = sorted[0]
            }

            log.append("  Selected: score=\(best.score) \"\(best.title)\"")

            // Activate: app → pause → raise+setMain+setFocused → pause → raise
            best.app.activate()
            Thread.sleep(forTimeInterval: 0.15)

            AXUIElementPerformAction(best.axWindow, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(best.axWindow, kAXMainAttribute as CFString, true as CFTypeRef)
            AXUIElementSetAttributeValue(best.axApp, kAXFocusedWindowAttribute as CFString, best.axWindow)

            Thread.sleep(forTimeInterval: 0.15)
            AXUIElementPerformAction(best.axWindow, kAXRaiseAction as CFString)

            return .success
        }

        private func raiseWindow(pid: pid_t, windowName: String) {
            guard Self.isAccessibilityTrusted else {
                logger.debug("raiseWindow: accessibility not trusted, skipping")
                return
            }

            let appElement = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
            guard result == .success, let windows = windowsRef as? [AXUIElement] else {
                logger.debug("raiseWindow: AX query failed (\(result.rawValue)) for PID \(pid)")
                return
            }

            for window in windows {
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let title = titleRef as? String,
                   title == windowName {
                    let raiseResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                    logger.debug("raiseWindow: raised '\(windowName, privacy: .public)' result=\(raiseResult.rawValue)")
                    return
                }
            }
            logger.debug("raiseWindow: no AX window matched '\(windowName, privacy: .public)'")
        }

        // MARK: - Open Transcript

        private func openTranscript(for session: SessionWatcherSession) -> SessionWatcherActionResult {
            logger.debug("openTranscript: sessionId=\(session.sessionId, privacy: .public)")
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            let possiblePaths = [
                "\(homeDir)/.claude/projects/\(session.sessionId)/transcript.md",
                "\(homeDir)/.claude/projects/\(session.sessionId)/transcript.json",
                "\(homeDir)/.claude/sessions/\(session.sessionId)/transcript.md",
                "\(homeDir)/.claude/sessions/\(session.sessionId)/transcript.json"
            ]

            for path in possiblePaths where FileManager.default.fileExists(atPath: path) {
                logger.info("openTranscript: found at \(path, privacy: .public)")
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                return .success
            }

            logger.info("openTranscript: not found in any location")
            return .failure(.transcriptNotFound(
                "No transcript found for session \(session.sessionId)."
                + " Looked in ~/.claude/projects/ and ~/.claude/sessions/."
            ))
        }

        // MARK: - Copy SessionWatcherSession ID

        private func copySessionId(_ sessionId: String) -> SessionWatcherActionResult {
            logger.debug("copySessionId: \(sessionId, privacy: .public)")
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(sessionId, forType: .string)
            return .success
        }

        // MARK: - Custom Command

        private func runCustomCommand(for session: SessionWatcherSession) -> SessionWatcherActionResult {
            let template = customCommandTemplate
            let command = substituteVariables(in: template, session: session)
            // swiftlint:disable:next line_length
            logger.info("runCustomCommand: template='\(template, privacy: .public)' expanded='\(command, privacy: .public)'")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                DispatchQueue.global(qos: .userInitiated).async {
                    process.waitUntilExit()
                    if process.terminationStatus != 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                        // swiftlint:disable:next line_length
                        Self.logger.error("Custom command failed (exit \(process.terminationStatus)): \(output, privacy: .public)")
                    } else {
                        Self.logger.debug("Custom command completed successfully")
                    }
                }
                return .success
            } catch {
                logger.error("Custom command launch failed: \(error.localizedDescription, privacy: .public)")
                return .failure(.commandFailed(error.localizedDescription))
            }
        }

        // MARK: - Send Notification

        private func sendNotification(for session: SessionWatcherSession) -> SessionWatcherActionResult {
            logger.debug("sendNotification: \(session.projectName, privacy: .public)")
            let content = UNMutableNotificationContent()
            content.title = "\(AppStorageLocation.displayName): \(session.projectName)"
            content.body = "SessionWatcherSession: \(session.sessionId)"
                + "\nModel: \(session.model)"
                + "\nStatus: \(session.status.rawValue)"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "whippet-click-\(session.sessionId)-\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    Self.logger.error("Notification delivery failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            return .success
        }

        // MARK: - iTerm2 Pane Activation

        /// Outcome of attempting to activate an iTerm2 tab/pane.
        private enum ITermActivation {
            case activated
            case notFound
            case permissionDenied(SessionWatcherActionError)
        }

        /// Activates the iTerm2 tab/pane matching `target`, via the shared
        /// `TerminalTextInjector` script builder (`text: nil` → select-and-raise only).
        ///
        /// Driving iTerm2 via AppleScript needs Automation permission; a denial
        /// surfaces as `errAEEventNotPermitted` (-1743), which we map to a
        /// `.permissionDenied` error (pointing at the Automation pane) rather than
        /// swallowing it as a generic miss — that swallowing was why a missing
        /// Automation grant looked like a failed Accessibility check.
        private func activateITerm(target: TerminalTextInjector.Target) -> ITermActivation {
            let script = TerminalTextInjector.script(for: target, text: nil)
            // Click actions arrive on the main actor; NSAppleScript must run there.
            let result = MainActor.assumeIsolated {
                TerminalTextInjector.run(script: script, target: target)
            }
            switch result {
            case .success:
                return .activated
            case .failure(.permissionDenied(let message, let permission)):
                // swiftlint:disable:next line_length
                logger.error("AppleScript permission denied for \(target.app.name, privacy: .public): \(message, privacy: .public)")
                return .permissionDenied(.permissionDenied(message, requiredPermission: permission))
            case .failure:
                return .notFound
            }
        }

        // MARK: - Helpers

        public func substituteVariables(in template: String, session: SessionWatcherSession) -> String {
            var result = template
            result = result.replacingOccurrences(of: "$SESSION_ID", with: posixShellEscape(session.sessionId))
            result = result.replacingOccurrences(of: "$CWD", with: posixShellEscape(session.cwd))
            result = result.replacingOccurrences(of: "$MODEL", with: posixShellEscape(session.model))
            return result
        }

        private func posixShellEscape(_ string: String) -> String {
            return "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }

        /// Checks an AppleScript error dictionary for authorization/permission failures.
        /// Returns a `.permissionDenied` error (carrying the Automation permission for
        /// `bundleID`) if detected, nil otherwise.
        private func appleScriptPermissionError(
            _ error: NSDictionary,
            appName: String,
            bundleID: String
        ) -> SessionWatcherActionError? {
            let errorNumber = error[NSAppleScript.errorNumber] as? Int
            let errorMessage = error[NSAppleScript.errorMessage] as? String ?? ""

            // -1743 = "Not authorized to send Apple events"
            // -1744 = "A privilege violation occurred"
            if errorNumber == -1743 || errorNumber == -1744
                || errorMessage.localizedCaseInsensitiveContains("not authorized")
                || errorMessage.localizedCaseInsensitiveContains("privilege violation") {
                // swiftlint:disable:next line_length
                logger.error("AppleScript permission denied for \(appName, privacy: .public): \(errorMessage, privacy: .public)")
                return .permissionDenied(
                    "Automation permission is required to control \(appName)."
                    + " Grant access in System Settings > Privacy & Security > Automation.",
                    requiredPermission: .automation(targetBundleID: bundleID)
                )
            }
            return nil
        }
    }
}
extension SessionWatcher.SessionWatcherActionHandler: Loggable {
    public static nonisolated let logger = makeLogger()
}
