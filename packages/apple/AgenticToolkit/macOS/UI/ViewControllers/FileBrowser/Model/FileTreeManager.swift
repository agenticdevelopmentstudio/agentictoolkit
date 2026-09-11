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
        gitStatusProvider.refresh { [weak self] fileStatuses, dirStatuses in
            Task { @MainActor in
                guard let self = self, let root = self.rootNode else { return }
                self.applyGitStatuses(
                    node: root,
                    repoPath: self.repoRootURL.path,
                    fileStatuses: fileStatuses,
                    dirStatuses: dirStatuses
                )
            }
        }
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
