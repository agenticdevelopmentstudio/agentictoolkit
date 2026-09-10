import AppKit
import Combine
import Foundation
import SwiftTerm
import os
import AgenticToolkitCore

private let kMaxProcPathSize: Int32 = 4096

public enum TerminalSessionState: Sendable {
    case running
    case terminated
}

/// Manages a single terminal session backed by a shell process via PTY.
@MainActor
public final class TerminalSession: ObservableObject, Identifiable {
    public let id = UUID()

    @Published public var name: String
    @Published public var title: String?
    @Published public var currentDirectory: String?
    @Published public var gitBranch: String?
    @Published public var foregroundProcess: String?
    @Published public var dotColor: NSColor = .green
    @Published public var customSubtitles: [TerminalSessionSubtitle] = []
    @Published public var summary: String?
    @Published public var state: TerminalSessionState = .running
    @Published public var layoutState: TerminalSessionLayoutState = TerminalSessionLayoutState()

    public var displayTitle: String {
        if let title { return title }
        if let dir = currentDirectory {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let folder = dir == home ? "~" : (dir as NSString).lastPathComponent
            if let branch = gitBranch {
                return "\(folder): \(branch)"
            }
            return folder
        }
        return name
    }

    public var tildeAbbreviatedDirectory: String? {
        guard let dir = currentDirectory else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if dir == home { return "~" }
        if dir.hasPrefix(home + "/") { return "~" + dir.dropFirst(home.count) }
        return dir
    }

    public func recentScrollbackText(lineCount: Int = 200) -> String {
        let terminal = terminalView.getTerminal()
        let data = terminal.getBufferAsData()
        guard let fullText = String(data: data, encoding: .utf8) else { return "" }

        let allLines = fullText.components(separatedBy: "\n")
        let nonEmpty = allLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let recentLines = nonEmpty.suffix(lineCount)

        var result: [String] = []
        var charCount = 0
        let charBudget = 20_000

        for line in recentLines {
            charCount += line.count
            if charCount > charBudget { break }
            result.append(line)
        }

        return result.joined(separator: "\n")
    }

    public private(set) lazy var terminalView: LocalProcessTerminalView = {
        let view = ThemedTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.processDelegate = processHandler
        startShellProcess(in: view)
        return view
    }()

    private let processHandler: TerminalSessionProcessHandler
    private var gitBranchRequestID: UUID?
    private var processPollingTimer: Timer?
    private let workingDirectory: String?
    private let gitClient: GitClient

    public init(name: String, workingDirectory: String? = nil, gitClient: GitClient = .shared) {
        self.name = name
        self.workingDirectory = workingDirectory
        self.gitClient = gitClient
        self.processHandler = TerminalSessionProcessHandler()
        self.processHandler.session = self
    }

    private func startShellProcess(in view: LocalProcessTerminalView) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let startDir = workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
        // swiftlint:disable:next line_length
        logger.info("Starting shell '\(shell, privacy: .public)' for session '\(self.name)' in \(startDir, privacy: .public)")

        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        let processEnv = ProcessInfo.processInfo.environment
        let keysToInclude = ["HOME", "USER", "LOGNAME", "PATH", "LANG", "LC_ALL", "LC_CTYPE"]
        for key in keysToInclude {
            if let value = processEnv[key] {
                if let index = env.firstIndex(where: { $0.hasPrefix("\(key)=") }) {
                    env[index] = "\(key)=\(value)"
                } else {
                    env.append("\(key)=\(value)")
                }
            }
        }

        let shellName = (shell as NSString).lastPathComponent
        view.startProcess(
            executable: shell,
            args: [],
            environment: env,
            execName: "-\(shellName)",
            currentDirectory: startDir
        )

        view.getTerminal().registerOscHandler(code: 7770) { [weak self] data in
            guard let payload = String(bytes: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.handleOsc7770(payload: payload)
            }
        }

        startProcessPolling()
    }

    private func handleOsc7770(payload: String) {
        logger.debug("OSC 7770 received: \(payload, privacy: .public)")
        if payload.hasPrefix("color=") {
            let hex = String(payload.dropFirst("color=".count))
            if let color = NSColor(hex: hex) {
                dotColor = color
            }
        } else if payload.hasPrefix("subtitle:") {
            let rest = String(payload.dropFirst("subtitle:".count))
            guard let equalsIndex = rest.firstIndex(of: "=") else { return }
            let key = String(rest[rest.startIndex..<equalsIndex])
            let value = String(rest[rest.index(after: equalsIndex)...])
            guard !key.isEmpty else { return }
            if let index = customSubtitles.firstIndex(where: { $0.key == key }) {
                customSubtitles[index] = TerminalSessionSubtitle(key: key, value: value)
            } else {
                customSubtitles.append(TerminalSessionSubtitle(key: key, value: value))
            }
        } else if payload.hasPrefix("clear-subtitle:") {
            let key = String(payload.dropFirst("clear-subtitle:".count))
            customSubtitles.removeAll { $0.key == key }
        } else if payload == "clear-all-subtitles" {
            customSubtitles.removeAll()
        }
    }

    private func startProcessPolling() {
        processPollingTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollForegroundProcess()
            }
        }
    }

    private func pollForegroundProcess() {
        guard state == .running else {
            processPollingTimer?.invalidate()
            processPollingTimer = nil
            return
        }

        let descriptor = terminalView.process.childfd
        guard descriptor >= 0 else { return }

        let fgpid = tcgetpgrp(descriptor)
        guard fgpid > 0 else { return }

        let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(kMaxProcPathSize))
        defer { pathBuffer.deallocate() }

        let pathLength = proc_pidpath(fgpid, pathBuffer, UInt32(kMaxProcPathSize))
        guard pathLength > 0 else { return }

        let fullPath = String(cString: pathBuffer)
        let processName = (fullPath as NSString).lastPathComponent

        if foregroundProcess != processName {
            foregroundProcess = processName
        }
    }

    /// Detached HEAD renders as `HEAD`, not as nothing.
    ///
    /// `GitClient.currentBranch` returns `nil` there, which is the right answer
    /// for an API whose question is "which branch?" — but this label's job is to
    /// tell the user where they are standing, and a blank label reads as "not a
    /// repository". The two cases stay distinguishable without a second call:
    /// `currentBranch` *throws* when git could not answer, and returns `nil`
    /// only when git answered `HEAD`.
    public func detectGitBranch(for directory: String) {
        let requestID = UUID()
        gitBranchRequestID = requestID
        let client = gitClient
        Task { [weak self] in
            let branch: String?
            do {
                branch = try await client.currentBranch(in: URL(fileURLWithPath: directory)) ?? "HEAD"
            } catch is CancellationError {
                // Defensive, and unreachable as written: the `Task` above is
                // unstructured and its handle is discarded, so nothing holds a
                // reference that could cancel it. It states the policy anyway,
                // because the day someone keeps that handle, a cancelled
                // detection must leave the label alone rather than blank it.
                return
            } catch {
                branch = nil
            }
            guard let self, self.gitBranchRequestID == requestID else { return }
            self.gitBranch = branch
        }
    }

    public func stopProcessPolling() {
        processPollingTimer?.invalidate()
        processPollingTimer = nil
    }

    public func terminateProcess() {
        stopProcessPolling()
        if state == .running {
            logger.info("Terminating shell process for session '\(self.name)'")
            terminalView.terminate()
        }
    }
}

extension TerminalSession: Loggable {
    public static nonisolated let logger = makeLogger()
}

/// A key/value pair shown as a subtitle line on a terminal session cell.
public struct TerminalSessionSubtitle: Sendable, Equatable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

// MARK: - Process Delegate Handler

@MainActor
private final class TerminalSessionProcessHandler: NSObject, LocalProcessTerminalViewDelegate {
    public weak var session: TerminalSession?

    public nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    public nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.session?.title = title
            }
        }
    }

    public nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory = directory else { return }
        let path: String
        if let url = URL(string: directory), url.scheme == "file" {
            path = url.path
        } else {
            path = directory
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.session?.currentDirectory = path
                self.session?.detectGitBranch(for: path)
            }
        }
    }

    public nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        let code = exitCode
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.logger.info("Shell process terminated with exit code \(code.map { String($0) } ?? "nil")")
                self.session?.stopProcessPolling()
                self.session?.state = .terminated
            }
        }
    }
}

extension TerminalSessionProcessHandler: Loggable {
    public static nonisolated let logger = makeLogger()
}
