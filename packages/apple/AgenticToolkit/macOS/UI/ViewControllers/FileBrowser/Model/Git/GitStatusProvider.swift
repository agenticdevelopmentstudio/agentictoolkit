import AgenticToolkitCore
import Foundation
import os

public final class GitStatusProvider: @unchecked Sendable {
    private let repoRoot: URL
    private var requestID: UUID?

    public init(repoRoot: URL) {
        self.repoRoot = repoRoot
    }

    public func refresh(
        completion: @escaping @Sendable (
            _ fileStatuses: [String: GitFileStatus],
            _ dirStatuses: [String: GitFileStatus]
        ) -> Void
    ) {
        let requestID = UUID()
        self.requestID = requestID

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["status", "--porcelain=v1", "-uall", "--ignore-submodules"]
            process.currentDirectoryURL = self.repoRoot

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                self.logger.error("Failed to run git status: \(error.localizedDescription)")
                DispatchQueue.main.async { completion([:], [:]) }
                return
            }

            // 5-second timeout
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
            process.waitUntilExit()
            timeout.cancel()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            guard self.requestID == requestID else { return }  // stale

            let status = GitStatus.parse(porcelain: output)

            self.logger.info("Git status: \(status.files.count) files, \(status.directories.count) directories")

            DispatchQueue.main.async {
                guard self.requestID == requestID else { return }
                completion(status.files, status.directories)
            }
        }
    }
}

extension GitStatusProvider: Loggable {
    public static nonisolated let logger = makeLogger()
}
