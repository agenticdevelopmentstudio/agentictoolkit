import AgenticToolkitCore
import Combine
import Foundation
import SwiftUI
import os

/// Manages the file tree for a project window, including git status overlay.
///
/// Delegates directory scanning and watching to a `DirectoryWatchCoordinator`.
/// Adds git status detection on top of the shared infrastructure.
/// Also manages IDE detection, triggering re-detection when the file tree syncs.
@MainActor
public final class FileTreeManager: ObservableObject {
    @Published public var rootNode: FileTreeNode?
    @Published public var isSyncing: Bool = false

    public let repoRootURL: URL
    public let packageURL: URL

    /// IDE detector for scanning project root for development tool markers.
    public let ideDetector: IDEDetector

    private let coordinator: DirectoryWatchCoordinator
    let gitStatusProvider: GitStatusProvider
    private var pendingGitRefresh: DispatchWorkItem?
    private var pendingIDEDetection: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    /// Keeps this manager registered with the shared provider. Releasing it
    /// unregisters, so the registration cannot outlive the manager.
    private var gitStatusObservation: GitStatusObservation?

    public init(
        repoRootURL: URL,
        packageURL: URL,
        config: FileTreeConfig,
        ignorePatterns: [String] = [],
        gitStatusProvider: GitStatusProvider? = nil
    ) {
        self.repoRootURL = repoRootURL
        self.packageURL = packageURL
        self.ideDetector = IDEDetector(rootURL: repoRootURL)
        self.gitStatusProvider = gitStatusProvider ?? GitStatusProvider(repoRoot: repoRootURL)
        self.coordinator = DirectoryWatchCoordinator(
            rootURL: repoRootURL,
            config: config,
            excludedPrefixes: [
                packageURL.path,
                repoRootURL.appendingPathComponent(".git").path
            ]
        )

        coordinator.ignorePatterns = ignorePatterns

        // One provider serves every pane of a checkout and broadcasts to all
        // of them, so this manager registers once and is told about every
        // refresh — including ones some other pane, or the `Refresh Status`
        // command, asked for.
        gitStatusObservation = self.gitStatusProvider.observe { [weak self] result in
            self?.apply(result)
        }

        // Forward coordinator's published properties
        coordinator.$rootNode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] node in
                self?.rootNode = node
            }
            .store(in: &cancellables)

        coordinator.$isSyncing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] syncing in
                self?.isSyncing = syncing
            }
            .store(in: &cancellables)
    }

    /// Updates the ignore patterns and triggers a full resync of the file tree.
    public func updateIgnorePatterns(_ patterns: [String]) {
        coordinator.ignorePatterns = patterns
        coordinator.fullSync()
    }

    public func loadInitial() {
        coordinator.fullSync()
        refreshGitStatus()
        ideDetector.detect()
    }

    public func startWatching() {
        coordinator.startWatching { [weak self] in
            self?.onCoordinatorChanged()
        }
    }

    public func stopWatching() {
        coordinator.stopWatching()
        pendingGitRefresh?.cancel()
        pendingGitRefresh = nil
        pendingIDEDetection?.cancel()
        pendingIDEDetection = nil
    }

    private func onCoordinatorChanged() {
        // Debounced git status refresh
        pendingGitRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.refreshGitStatus()
            }
        }
        pendingGitRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)

        // Debounced IDE re-detection (longer delay since IDE markers change rarely)
        pendingIDEDetection?.cancel()
        let ideWork = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.ideDetector.detect()
            }
        }
        pendingIDEDetection = ideWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: ideWork)
    }

    public func refreshGitStatus() {
        gitStatusProvider.refresh()
    }

    /// Applies one broadcast result to the tree.
    ///
    /// `unavailable` deliberately changes nothing. An empty status and a
    /// failed one are indistinguishable once they reach `applyGitStatuses`,
    /// which assigns `node.gitStatus` unconditionally and draws no badge for
    /// `nil` — so treating "we could not ask git" as "nothing is modified"
    /// repaints a whole dirty tree as clean. The last good status is the
    /// honest answer to "we do not know"; the failure is in the log.
    private func apply(_ result: GitStatusRefreshResult) {
        guard case .status(let status) = result, let root = rootNode else { return }
        applyGitStatuses(
            node: root,
            repoPath: repoRootURL.path,
            fileStatuses: status.files,
            dirStatuses: status.directories
        )
    }

    private func applyGitStatuses(
        node: FileTreeNode,
        repoPath: String,
        fileStatuses: [String: GitFileStatus],
        dirStatuses: [String: GitFileStatus]
    ) {
        let fullPath = node.url.path
        let relativePath: String
        if fullPath.hasPrefix(repoPath + "/") {
            relativePath = String(fullPath.dropFirst(repoPath.count + 1))
        } else {
            relativePath = ""
        }

        if node.isDirectory {
            node.gitStatus = dirStatuses[relativePath]
        } else {
            node.gitStatus = fileStatuses[relativePath]
        }

        if let children = node.children {
            for child in children {
                applyGitStatuses(node: child, repoPath: repoPath, fileStatuses: fileStatuses, dirStatuses: dirStatuses)
            }
        }
    }
}
