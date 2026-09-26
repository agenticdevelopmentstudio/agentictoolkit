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
    /// Bridges SQLite session data to AppKit views with real-time update support.
    ///
    /// The window is one flat list of rows, but the order still knows about projects:
    /// sessions sharing a top-level git project stay adjacent, oldest first, and the
    /// projects themselves are ordered by their earliest session's start (so a
    /// newly-started project joins at the bottom rather than reshuffling the list).
    public final class SessionListViewModel: ObservableObject, @unchecked Sendable {

        // MARK: - Published Properties

        /// Every live session, in display order — one flat list, project-adjacent.
        @Published public private(set) var sessions: [SessionWatcherSession] = []

        /// Whether there are zero known projects (true only before any session is ever seen).
        @Published private(set) var isEmpty: Bool = true

        /// The total number of live (non-ended) sessions.
        @Published public private(set) var sessionCount: Int = 0

        /// The number of active sessions.
        @Published private(set) var activeSessionCount: Int = 0

        // MARK: - Properties

        private let source: SessionListSource
        private var refreshTimer: Timer?

        /// Whether the window may use the Accessibility API: to highlight the
        /// session whose terminal window is frontmost, and to find a clicked
        /// session's window. The host's to opt into — only a host that holds
        /// the grant should turn it on.
        ///
        /// Off, neither the view model nor its action handler asks TCC about
        /// Accessibility, not even to learn the answer is no. That matters
        /// because `AXIsProcessTrusted()` from an app that doesn't hold the
        /// grant wakes `universalAccessAuthWarn`, whose
        /// `TCCAccessCopyInformation` sweep holds tccd's lock for ~10s. Every
        /// other TCC check queues behind it, WindowServer's included, and the
        /// whole machine stops responding for that long.
        public let usesAccessibility: Bool

        /// The Accessibility trust check, injected so tests can count probes.
        private let isAccessibilityTrusted: () -> Bool

        /// The action handler for session click actions.
        public let actionHandler: SessionWatcherActionHandler

        /// The last error message from a click action, shown briefly in the UI.
        @Published public var lastActionError: String?

        /// If the last error was a permission issue, the permission the user must grant.
        @Published public var lastRequiredPermission: AgenticToolkitPermissions.Permission?

        /// The session summarizer for manual AI summarization.
        public var sessionSummarizer: SessionSummarizing?

        /// Whether rows show the AI-summary line at all. Which preference answers
        /// that is the host's business — Whippet summarizes in-app off
        /// `aiSummariesEnabled`, Stenographer off its own daemon-pushed toggle — so
        /// the window asks rather than reading a setting it doesn't own.
        public var summariesEnabled: @MainActor () -> Bool = { UserSettings.aiSummariesEnabled.value }

        /// SessionWatcherSession IDs currently being summarized (for UI progress indication).
        @Published private(set) var summarizingSessionIds: Set<String> = []

        /// The session ID whose terminal window is currently frontmost, if any.
        @Published public private(set) var frontmostSessionId: String?

        private var frontmostTimer: Timer?

        // MARK: - Initialization

        /// Whether real-time observation (source subscription + frontmost timer)
        /// is currently running. The hosting view controller
        /// starts it on appear and stops it on disappear so a constructed-but-
        /// hidden window (e.g. one pre-constructed for launch restore) does no
        /// background polling.
        private var isListening = false

        @MainActor
        public init(
            source: SessionListSource,
            settingsStore: SettingsStore,
            usesAccessibility: Bool = false,
            isAccessibilityTrusted: @escaping () -> Bool = { SystemAccessibilityPermission.isGranted }
        ) {
            self.source = source
            self.usesAccessibility = usesAccessibility
            self.isAccessibilityTrusted = isAccessibilityTrusted
            self.actionHandler = SessionWatcherActionHandler(
                settingsStore: settingsStore,
                usesAccessibility: usesAccessibility,
                isAccessibilityTrusted: isAccessibilityTrusted
            )
            // Observation is started by the hosting view controller on viewWillAppear,
            // not here — constructing the view model must not start timers/polling
            // for a window that may never be shown.
        }

        deinit {
            stopListening()
        }

        // MARK: - Data Loading

        /// Loads active and stale sessions from the source and orders them for display.
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

            let ordered = Self.displayOrder(for: liveSessions)
            let count = liveSessions.count
            let activeCount = liveSessions.filter { $0.status == .active }.count
            let empty = ordered.isEmpty

            await MainActor.run {
                self.sessions = ordered
                self.isEmpty = empty
                self.sessionCount = count
                self.activeSessionCount = activeCount
            }
        }

        /// The flat display order. Sessions of one project stay together — the window
        /// no longer draws a card around them, so adjacency is the only thing left
        /// saying they belong to the same tree — oldest first within a project, and
        /// the projects ordered by their earliest session's start so a project that
        /// starts now joins the bottom instead of reshuffling everything above it.
        ///
        /// `startedAt` is a fixed-width UTC timestamp, so a lexicographic string
        /// compare is chronological.
        static func displayOrder(for sessions: [SessionWatcherSession]) -> [SessionWatcherSession] {
            let byProject = Dictionary(grouping: sessions) { $0.projectGroupKey }
            return byProject
                .map { key, members in (key: key, members: members.sorted { $0.startedAt < $1.startedAt }) }
                .sorted { lhs, rhs in
                    let lhsStart = lhs.members.first?.startedAt ?? ""
                    let rhsStart = rhs.members.first?.startedAt ?? ""
                    if lhsStart != rhsStart { return lhsStart < rhsStart }
                    // Deterministic tie-break when two projects' earliest starts match.
                    return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
                }
                .flatMap(\.members)
        }

        // MARK: - Real-time Updates

        /// Starts real-time observation: an initial load, the source subscription,
        /// and — when the host opted in — the frontmost-window timer. Idempotent — a second call while
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

            // Poll the frontmost window to highlight the active session
            guard usesAccessibility else { return }
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.updateFrontmostSession()
            }
            RunLoop.main.add(timer, forMode: .common)
            frontmostTimer = timer
        }

        public func stopListening() {
            isListening = false
            source.stopObserving()
            refreshTimer?.invalidate()
            refreshTimer = nil
            frontmostTimer?.invalidate()
            frontmostTimer = nil
        }

        /// Whether the frontmost-window timer is running. `internal` for tests.
        var isTrackingFrontmostWindow: Bool { frontmostTimer != nil }

        // MARK: - Click Actions

        public func handleSessionClick(_ session: SessionWatcherSession) {
            let action = actionHandler.currentAction
            let log = ActivationTestLog.whippetShared

            // For window activation actions, try direct AX match first; show discovery panel if no match
            if action == .activateWindow || action == .activateWarp {
                let projectName = session.projectName
                log.append("Click: project=\"\(projectName)\" action=\(action.rawValue) cwd=\"\(session.cwd)\"")
                // The window titles in the log are read over Accessibility,
                // so a host that doesn't use it logs without them.
                if usesAccessibility {
                    log.append("  Before: main=\"\(Self.frontmostWindowTitle())\"")
                }

                let result = actionHandler.execute(action: .activateWindow, for: session)

                if case .success = result {
                    log.append("  execute() returned success")
                    lastActionError = nil
                    lastRequiredPermission = nil

                    // Verify activation actually worked after the target app has time to process
                    let readsTitles = usesAccessibility
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        Thread.sleep(forTimeInterval: 0.5)
                        let mainTitle = readsTitles ? Self.frontmostWindowTitle() : ""
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
                SessionWatcherActionHandler.activateTerminalApp(termProgram: session.termProgram)
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

            // The test judges each activation by the frontmost window's title,
            // which only Accessibility can read.
            guard usesAccessibility else {
                log.append("ABORT: this window doesn't use Accessibility")
                lastActionError = "Test: needs Accessibility, which this app doesn't use"
                return
            }

            // Gather unique project names from live sessions
            let projects: [(name: String, session: SessionWatcherSession)] = sessions.map {
                ($0.projectName, $0)
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

                DispatchQueue.main.async { [weak self] in
                    NSApp.activateUnlessQuiet()
                    let logPath = ActivationTestLog.whippetShared.logPath ?? "(no path)"
                    self?.lastActionError =
                        "Test: \(passCount) passed, \(failCount) failed — see \(logPath)"
                    self?.scheduleActivationTestStatusClear()
                }
            }
        }

        /// Clears the activation test's result line once it has had time to be read.
        ///
        /// Its own method rather than a closure nested in `testActivation`: a
        /// `[weak self]` capture inside a closure that already holds `self`
        /// strongly is a compile error, and holding the view model alive for the
        /// 30 seconds is not what this wants.
        private func scheduleActivationTestStatusClear() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                if self?.lastActionError?.hasPrefix("Test:") == true {
                    self?.lastActionError = nil
                }
            }
        }

        // MARK: - Frontmost Window Tracking

        /// Checks the system's frontmost window title and matches it to a session.
        private func updateFrontmostSession() {
            guard isAccessibilityTrusted() else { return }

            let title = Self.frontmostWindowTitle()
            guard !title.isEmpty else {
                if frontmostSessionId != nil { frontmostSessionId = nil }
                return
            }

            // Match against all live sessions by project name (case-insensitive substring)
            let matched = sessions.first { session in
                let project = session.projectName
                guard !project.isEmpty, project != "Unknown" else { return false }
                return title.localizedCaseInsensitiveContains(project)
            }

            let newId = matched?.sessionId
            if newId != frontmostSessionId {
                frontmostSessionId = newId
            }
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

        /// Returns the title of the frontmost application's focused window.
        /// Accessibility — call only when `usesAccessibility` is on.
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
