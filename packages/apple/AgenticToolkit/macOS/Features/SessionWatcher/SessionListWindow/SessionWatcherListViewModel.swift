import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS
import AgenticToolkitPermissions
import AgenticToolkitPermissionsUI

import AppKit
import ApplicationServices
import Combine
import Foundation
import os
extension SessionWatcher {
    /// Groups sessions by their top-level (non-submodule) git project.
    public struct SessionWatcherGroup: Identifiable {
        public let id: String           // project group key (project root path, or cwd)
        public let projectName: String  // display name (last path component of the key)
        public let sessions: [SessionWatcherSession]

        /// Whether any session in this group is active.
        public var hasActiveSessions: Bool {
            sessions.contains { $0.status == .active }
        }

        /// Whether any session in this group is stale (but not active).
        public var hasStaleSessions: Bool {
            !hasActiveSessions && sessions.contains { $0.status == .stale }
        }
    }

    /// Bridges SQLite session data to AppKit views with real-time update support.
    ///
    /// Sessions are grouped by their top-level git project and ordered by when they
    /// started: within a project the oldest session is first, and projects are ordered
    /// by their earliest session start (so a newly-started project joins at the bottom).
    public final class SessionListViewModel: ObservableObject, @unchecked Sendable {

        // MARK: - Published Properties

        /// All live sessions grouped by project, ordered by start time.
        @Published public private(set) var groups: [SessionWatcherGroup] = []

        /// Whether there are zero known projects (true only before any session is ever seen).
        @Published private(set) var isEmpty: Bool = true

        /// The total number of live (non-ended) sessions.
        @Published public private(set) var sessionCount: Int = 0

        /// The number of active sessions.
        @Published private(set) var activeSessionCount: Int = 0

        /// Whether the app has accessibility permission.
        @Published private(set) var isAccessibilityTrusted: Bool = AXIsProcessTrusted()

        // MARK: - Properties

        private let source: SessionListSource
        private var refreshTimer: Timer?
        private var accessibilityTimer: Timer?

        /// The action handler for session click actions.
        public let actionHandler: SessionWatcherActionHandler

        /// The last error message from a click action, shown briefly in the UI.
        @Published public var lastActionError: String?

        /// If the last error was a permission issue, the permission the user must grant.
        @Published public var lastRequiredPermission: AgenticToolkitPermissions.Permission?

        /// The session summarizer for manual AI summarization.
        public var sessionSummarizer: SessionSummarizing?

        /// SessionWatcherSession IDs currently being summarized (for UI progress indication).
        @Published private(set) var summarizingSessionIds: Set<String> = []

        /// The session ID whose terminal window is currently frontmost, if any.
        @Published public private(set) var frontmostSessionId: String?

        private var frontmostTimer: Timer?

        // MARK: - Initialization

        /// Whether real-time observation (source subscription + accessibility/
        /// frontmost timers) is currently running. The hosting view controller
        /// starts it on appear and stops it on disappear so a constructed-but-
        /// hidden window (e.g. one pre-constructed for launch restore) does no
        /// background polling.
        private var isListening = false

        @MainActor
        public init(source: SessionListSource, settingsStore: SettingsStore) {
            self.source = source
            self.actionHandler = SessionWatcherActionHandler(settingsStore: settingsStore)
            // Observation is started by the hosting view controller on viewWillAppear,
            // not here — constructing the view model must not start timers/polling
            // for a window that may never be shown.
        }

        deinit {
            stopListening()
        }

        // MARK: - Data Loading

        /// Loads active and stale sessions from the source and groups them by project.
        /// Ended sessions are excluded. Fire-and-forget: the actual work runs in
        /// ``reloadSessions()`` so production call sites stay synchronous.
        public func loadSessions() {
            Task { [weak self] in await self?.reloadSessions() }
        }

        /// Fetches from the source and republishes. The fetch is awaited off the main
        /// actor (so a network source never blocks the UI); the published state is then
        /// applied on the main actor. `internal` so tests can await a deterministic load.
        func reloadSessions() async {
            let allSessions: [SessionWatcherSession]
            do {
                allSessions = try await source.fetchSessions()
            } catch {
                logger.error("Failed to load sessions: \(error.localizedDescription, privacy: .public)")
                return
            }

            let liveSessions = allSessions.filter { $0.status != .ended && !$0.cwd.isEmpty && $0.cwd != "/" }

            // Group live sessions by their top-level git project.
            let sessionsByProject = Dictionary(grouping: liveSessions) { $0.projectGroupKey }

            // Within each group, order sessions by when they started (oldest first);
            // order the groups by their earliest session's start so a newly-started
            // project joins at the bottom. `startedAt` is a fixed-width UTC timestamp,
            // so a lexicographic string compare is chronological.
            let sortedGroups = sessionsByProject
                .compactMap { key, sessions -> SessionWatcherGroup? in
                    guard !sessions.isEmpty else { return nil }
                    let ordered = sessions.sorted { $0.startedAt < $1.startedAt }
                    return SessionWatcherGroup(
                        id: key,
                        projectName: ordered.first?.projectGroupName ?? key,
                        sessions: ordered
                    )
                }
                .sorted { lhs, rhs in
                    let lhsStart = lhs.sessions.first?.startedAt ?? ""
                    let rhsStart = rhs.sessions.first?.startedAt ?? ""
                    if lhsStart != rhsStart { return lhsStart < rhsStart }
                    // Deterministic tie-break when two projects' earliest starts match.
                    return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
                }

            let count = liveSessions.count
            let activeCount = liveSessions.filter { $0.status == .active }.count
            let empty = sortedGroups.isEmpty

            await MainActor.run {
                self.groups = sortedGroups
                self.isEmpty = empty
                self.sessionCount = count
                self.activeSessionCount = activeCount
            }
        }

        // MARK: - Real-time Updates

        /// Starts real-time observation: an initial load, the source subscription,
        /// and the accessibility/frontmost timers. Idempotent — a second call while
        /// already listening is a no-op, so balanced appear/disappear pairing can't
        /// stack duplicate observers or timers. Called by the view controller on
        /// `viewWillAppear`.
        public func startListening() {
            guard !isListening else { return }
            isListening = true

            // Load immediately so a freshly-shown window isn't blank until the first poll.
            loadSessions()

            // Reload whenever the source signals its session set may have changed.
            source.startObserving { [weak self] in
                self?.loadSessions()
            }

            // Re-check accessibility when the app comes to the foreground
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(checkAccessibility),
                name: NSApplication.didBecomeActiveNotification,
                object: nil
            )

            // Poll accessibility status every 2 seconds so the indicator updates
            // promptly after the user grants permission in System Settings.
            accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.checkAccessibility()
            }

            // Poll the frontmost window to highlight the active session
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.updateFrontmostSession()
            }
            RunLoop.main.add(timer, forMode: .common)
            frontmostTimer = timer
        }

        public func stopListening() {
            isListening = false
            source.stopObserving()
            let center = NotificationCenter.default
            center.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
            refreshTimer?.invalidate()
            refreshTimer = nil
            accessibilityTimer?.invalidate()
            accessibilityTimer = nil
            frontmostTimer?.invalidate()
            frontmostTimer = nil
        }

        @objc private func checkAccessibility() {
            let trusted = AXIsProcessTrusted()
            if trusted != isAccessibilityTrusted {
                logger.info("Accessibility status changed: \(trusted)")
                if Thread.isMainThread {
                    isAccessibilityTrusted = trusted
                } else {
                    DispatchQueue.main.async { [weak self] in
                        self?.isAccessibilityTrusted = trusted
                    }
                }
            }
        }

        // MARK: - Click Actions

        public func handleSessionClick(_ session: SessionWatcherSession) {
            let action = actionHandler.currentAction
            let log = ActivationTestLog.whippetShared

            // For window activation actions, try direct AX match first; show discovery panel if no match
            if action == .activateWindow || action == .activateWarp {
                let projectName = session.projectName
                log.append("Click: project=\"\(projectName)\" action=\(action.rawValue) cwd=\"\(session.cwd)\"")
                log.append("  Before: main=\"\(Self.frontmostWindowTitle())\"")

                let result = actionHandler.execute(action: .activateWindow, for: session)

                if case .success = result {
                    log.append("  execute() returned success")
                    lastActionError = nil
                    lastRequiredPermission = nil

                    // Verify activation actually worked after the target app has time to process
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        Thread.sleep(forTimeInterval: 0.5)
                        let mainTitle = Self.frontmostWindowTitle()
                        let frontBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""

                        // Verify: either the title matches the project name, or the correct
                        // terminal app is now frontmost (iTerm2 titles don't contain project names)
                        let titleMatches = mainTitle.localizedCaseInsensitiveContains(projectName)
                        let appMatches = Self.bundleIdMatchesTermProgram(
                            frontBundleId,
                            termProgram: session.termProgram
                        )
                        let verified = titleMatches || appMatches
                        log.append("  After:  main=\"\(mainTitle)\" front=\(frontBundleId) verified=\(verified)")
                        DispatchQueue.main.async {
                            if !verified {
                                self?.lastActionError =
                                    "Activation failed: main=\"\(mainTitle)\", "
                                    + "expected \"\(projectName)\" or \(session.termProgram)"
                                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                                    if self?.lastActionError?.hasPrefix("Activation") == true {
                                        self?.lastActionError = nil
                                    }
                                }
                            }
                        }
                    }
                    return
                }

                if case .failure(let error) = result {
                    log.append("  execute() returned failure: \(error.localizedDescription)")

                    // If it's a permission error, show it
                    if case .permissionDenied = error {
                        lastActionError = error.localizedDescription
                        lastRequiredPermission = error.requiredPermission
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                            self?.lastActionError = nil
                            self?.lastRequiredPermission = nil
                        }
                        return
                    }
                }

                // No specific window matched — just bring the terminal app to front
                log.append("  Falling back to bringing terminal app to front")
                Self.activateTerminalApp(termProgram: session.termProgram)
                lastActionError = nil
                lastRequiredPermission = nil
                return
            }

            let result = actionHandler.execute(for: session)
            switch result {
            case .success:
                lastActionError = nil
                lastRequiredPermission = nil
            case .failure(let error):
                lastActionError = error.localizedDescription
                lastRequiredPermission = error.requiredPermission
                // swiftlint:disable:next line_length
                logger.warning("Click action failed for session \(session.sessionId, privacy: .public): \(error.localizedDescription, privacy: .public)")

                let delay: TimeInterval = error.requiredPermission != nil ? 10 : 4
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.lastActionError = nil
                    self?.lastRequiredPermission = nil
                }
            }
        }

        public func openPermissionSettings() {
            guard let permission = lastRequiredPermission else { return }
            Task { @MainActor in
                // `.denied` because that is what the banner offering this
                // button is reporting: the action failed for want of exactly
                // this permission.
                await PermissionPresenter.present(
                    permission, shownAs: .denied, using: SystemPermissionChecker())
            }
        }

        // MARK: - Activation Test

        /// Tests window activation for each unique project by simulating a click
        /// and verifying the Warp main window switched. Runs on a background thread
        /// and reports results via lastActionError.
        public func testActivation() {
            let log = ActivationTestLog.whippetShared
            log.clear()
            log.append("=== Activation Test Started ===")
            log.append("Log file: \((ActivationTestLog.whippetShared.logPath ?? "(no path)"))")

            // Gather unique project names from live sessions
            let projects: [(name: String, session: SessionWatcherSession)] = groups.flatMap { group in
                group.sessions.map { ($0.projectName, $0) }
            }

            guard !projects.isEmpty else {
                log.append("ABORT: No sessions to test")
                lastActionError = "Test: No sessions to test"
                return
            }

            log.append("Projects to test: \(projects.map(\.name).joined(separator: ", "))")
            lastActionError = "Test: Running \(projects.count) activation test(s)..."

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                var passCount = 0
                var failCount = 0

                for (name, session) in projects {
                    let before = Self.frontmostWindowTitle()
                    log.append("--- Testing \"\(name)\" ---")
                    log.append("  Before: main=\"\(before)\"")

                    let result = self.actionHandler.execute(action: .activateWindow, for: session)
                    if case .success = result {
                        log.append("  execute() returned: success")
                    } else {
                        log.append("  execute() returned: failure")
                    }

                    Thread.sleep(forTimeInterval: 0.5)

                    let after = Self.frontmostWindowTitle()
                    log.append("  After:  main=\"\(after)\"")

                    let passed: Bool
                    if case .success = result {
                        passed = after.localizedCaseInsensitiveContains(name)
                    } else {
                        passed = false
                    }

                    if passed {
                        log.append("  PASS")
                        passCount += 1
                    } else {
                        log.append("  FAIL: expected title containing \"\(name)\", got \"\(after)\"")
                        failCount += 1
                    }

                    Thread.sleep(forTimeInterval: 0.5)
                }

                log.append("=== Results: \(passCount) passed, \(failCount) failed ===")

                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    let logPath = ActivationTestLog.whippetShared.logPath ?? "(no path)"
                    self.lastActionError =
                        "Test: \(passCount) passed, \(failCount) failed — see \(logPath)"

                    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                        if self?.lastActionError?.hasPrefix("Test:") == true {
                            self?.lastActionError = nil
                        }
                    }
                }
            }
        }

        // MARK: - Frontmost Window Tracking

        /// Checks the system's frontmost window title and matches it to a session.
        private func updateFrontmostSession() {
            guard AXIsProcessTrusted() else { return }

            let title = Self.frontmostWindowTitle()
            guard !title.isEmpty else {
                if frontmostSessionId != nil { frontmostSessionId = nil }
                return
            }

            // Match against all live sessions by project name (case-insensitive substring)
            let allSessions = groups.flatMap(\.sessions)
            let matched = allSessions.first { session in
                let project = session.projectName
                guard !project.isEmpty, project != "Unknown" else { return false }
                return title.localizedCaseInsensitiveContains(project)
            }

            let newId = matched?.sessionId
            if newId != frontmostSessionId {
                frontmostSessionId = newId
            }
        }

        /// Returns the title of the frontmost application's main window.
        private static let termProgramBundleIDs: [String: String] = [
            "iTerm.app": "com.googlecode.iterm2",
            "Apple_Terminal": "com.apple.Terminal",
            "WarpTerminal": "dev.warp.Warp-Stable",
            "vscode": "com.microsoft.VSCode",
            "tmux": "com.apple.Terminal"
        ]

        private static func activateTerminalApp(termProgram: String) {
            guard let bundleID = termProgramBundleIDs[termProgram],
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
                return
            }
            app.activate()
        }

        private static func bundleIdMatchesTermProgram(_ bundleId: String, termProgram: String) -> Bool {
            switch termProgram {
            case "iTerm.app": return bundleId.contains("iterm")
            case "WarpTerminal": return bundleId.contains("warp")
            case "Apple_Terminal": return bundleId == "com.apple.Terminal"
            case "vscode": return bundleId.contains("VSCode")
            case "tmux": return bundleId == "com.apple.Terminal"
            default: return false
            }
        }

        private static func frontmostWindowTitle() -> String {
            guard let frontApp = NSWorkspace.shared.frontmostApplication else { return "" }

            // Skip our own app
            if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier { return "" }

            let axApp = AXUIElementCreateApplication(frontApp.processIdentifier)
            var windowRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef)
            guard result == .success, let window = windowRef else { return "" }

            guard CFGetTypeID(window) == AXUIElementGetTypeID() else { return "" }
            let windowElement = window as! AXUIElement // swiftlint:disable:this force_cast
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef)
            return (titleRef as? String) ?? ""
        }

        // MARK: - AI Summarization

        /// Triggers AI summarization for a session. Guards against double-trigger.
        public func summarizeSession(_ session: SessionWatcherSession) {
            logger.debug("Manual summarize requested for \(session.sessionId, privacy: .public)")
            guard let summarizer = sessionSummarizer else {
                logger.error("No sessionSummarizer set on SessionListViewModel — cannot summarize")
                return
            }
            guard !summarizingSessionIds.contains(session.sessionId) else {
                logger.debug("Already summarizing \(session.sessionId, privacy: .public), skipping")
                return
            }

            summarizingSessionIds.insert(session.sessionId)

            Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    try await summarizer.summarize(sessionId: session.sessionId)
                } catch {
                    await MainActor.run {
                        self?.lastActionError = "Summarizer: \(error.localizedDescription)"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                            if self?.lastActionError?.hasPrefix("Summarizer") == true {
                                self?.lastActionError = nil
                            }
                        }
                    }
                }
                await MainActor.run {
                    self?.summarizingSessionIds.remove(session.sessionId)
                    self?.loadSessions()
                }
            }
        }
    }
}

extension SessionWatcher.SessionListViewModel: Loggable {
    public static nonisolated let logger = makeLogger()
}
