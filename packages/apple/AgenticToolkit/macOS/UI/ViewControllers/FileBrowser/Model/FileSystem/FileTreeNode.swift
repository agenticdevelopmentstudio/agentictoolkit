import Foundation
import Combine

/// A node in the file tree representing a file or directory.
///
/// Each node contains the file URL, display name, and lazily-loaded children
/// for directories. The tree is built by enumerating the file system starting
/// from the project's repository root directory.
///
/// Nodes are `Identifiable` (by URL path) and `Hashable` for use with
/// `OutlineGroup` and SwiftUI `List` selection.
public final class FileTreeNode: Identifiable, ObservableObject, Hashable, @unchecked Sendable {

    /// Unique identifier derived from the file URL path.
    public let id: String

    /// The file system URL for this node.
    public let url: URL

    /// The display name shown in the file tree.
    public let name: String

    /// Whether this node represents a directory.
    public let isDirectory: Bool

    /// Whether this node represents a package extension that should be shown
    /// as a single item (not expanded). Determined by caller-supplied
    /// `packageExtensions` on construction.
    public let isPackage: Bool

    /// The child nodes for directories. `nil` for files and packages, and an
    /// empty array for a directory nobody has looked inside yet — which is how
    /// the outline knows it is expandable before it has been read.
    @Published public var children: [FileTreeNode]?

    /// Whether this directory's children have been read from disk.
    ///
    /// The distinction matters because an empty array means two different
    /// things: a directory that is genuinely empty, and one that has not been
    /// opened yet.
    @Published public private(set) var childrenLoaded: Bool = false

    /// What this node's children are read with, kept so a directory can
    /// materialise its own children the first time it is shown — the view
    /// would otherwise have to carry the scan's configuration down the tree
    /// alongside every node (`dry`).
    private let ignorePatterns: [String]
    private let packageExtensions: Set<String>

    /// File size in bytes, if available. Only populated for files.
    public let fileSize: Int?

    /// Last modification date, if available.
    public let modificationDate: Date?

    /// Git status for this file or directory, if tracked.
    @Published public var gitStatus: GitFileStatus?

    // MARK: - Initialization

    /// Creates a file tree node from a file URL.
    ///
    /// - Parameters:
    ///   - url: The file system URL for this file or directory.
    ///   - isDirectory: Whether this URL points to a directory.
    ///   - loadChildren: Whether to read this directory's children now. One
    ///     level only — the children themselves are left unread until they are
    ///     shown. Pass `false` to read nothing at all.
    ///   - ignorePatterns: Wildcard patterns for filenames to exclude.
    ///   - packageExtensions: Extensions that identify directories as opaque
    ///     packages (e.g. `catnip-proj`). Packages appear as single items.
    public init(
        url: URL,
        isDirectory: Bool,
        loadChildren: Bool = false,
        ignorePatterns: [String] = [],
        packageExtensions: Set<String> = []
    ) {
        self.id = url.path
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.ignorePatterns = ignorePatterns
        self.packageExtensions = packageExtensions

        let isPkg = packageExtensions.contains(url.pathExtension)
        self.isPackage = isPkg

        // Read file attributes
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        self.fileSize = isDirectory ? nil : attributes?[.size] as? Int
        self.modificationDate = attributes?[.modificationDate] as? Date

        // Directories that are not packages get children
        if isDirectory && !isPkg {
            if loadChildren {
                self.children = FileTreeNode.loadChildren(
                    for: url,
                    ignorePatterns: ignorePatterns,
                    packageExtensions: packageExtensions
                )
                self.childrenLoaded = true
            } else {
                // Empty array signals "expandable but not yet loaded"
                self.children = []
            }
        } else {
            self.children = nil
        }
    }

    // MARK: - Lazy loading

    /// Reads this directory's children, once, the first time something needs
    /// to show them.
    ///
    /// One level at a time is the whole point: a browser that walked an entire
    /// checkout before drawing anything spent minutes and gigabytes on
    /// directories the user never opened — `node_modules` and `.git` are most
    /// of any repository, and a big monorepo has dozens of each. The tree the
    /// user can see is the tree worth reading
    /// (`make-it-work-make-it-right-make-it-fast`).
    @MainActor
    public func loadChildrenIfNeeded() {
        guard isDirectory, !isPackage, !childrenLoaded else { return }
        // Set before the read, not after: two rows appearing in the same frame
        // must not both start the same enumeration.
        childrenLoaded = true
        let url = self.url
        let patterns = ignorePatterns
        let extensions = packageExtensions
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loaded = FileTreeNode.loadChildren(
                for: url,
                ignorePatterns: patterns,
                packageExtensions: extensions
            )
            // `nil`, not an empty array, for a directory that turned out to
            // have nothing in it: the outline reads an empty array as
            // "expandable, not yet read", so keeping it would leave a
            // disclosure triangle that opens onto nothing.
            DispatchQueue.main.async { self?.children = loaded.isEmpty ? nil : loaded }
        }
    }

    /// Replaces this directory's children with a freshly read list, keeping the
    /// node objects for paths that are still there.
    ///
    /// Re-using them is what keeps an expanded subdirectory expanded — and
    /// read — when a sibling file changes underneath it.
    public func merge(children fresh: [FileTreeNode]) {
        var existing: [String: FileTreeNode] = [:]
        for child in children ?? [] { existing[child.id] = child }
        children = fresh.map { existing[$0.id] ?? $0 }
    }

    // MARK: - Ignore Patterns

    /// Returns true if the filename matches any of the given ignore patterns.
    private static func shouldIgnore(_ filename: String, patterns: [String]) -> Bool {
        for pattern in patterns where fnmatch(pattern, filename, 0) == 0 {
            return true
        }
        return false
    }

    // MARK: - Child Loading

    /// Loads and sorts one directory's immediate children.
    ///
    /// Directories are listed first (sorted alphabetically), followed by files
    /// (sorted alphabetically). Hidden files (starting with `.`) are included
    /// so that `.claude` and other dotfiles are visible. The children come back
    /// unread — see `loadChildrenIfNeeded()`.
    public static func loadChildren(
        for url: URL,
        ignorePatterns: [String] = [],
        packageExtensions: Set<String> = []
    ) -> [FileTreeNode] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [] // No options — include hidden files so .claude is visible
        ) else {
            return []
        }

        let nodes = contents.compactMap { childURL -> FileTreeNode? in
            let filename = childURL.lastPathComponent

            // Skip .DS_Store files
            if filename == ".DS_Store" {
                return nil
            }

            // Skip files matching ignore patterns
            if shouldIgnore(filename, patterns: ignorePatterns) {
                return nil
            }

            let resourceValues = try? childURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDir = resourceValues?.isDirectory ?? false
            return FileTreeNode(
                url: childURL,
                isDirectory: isDir,
                loadChildren: false,
                ignorePatterns: ignorePatterns,
                packageExtensions: packageExtensions
            )
        }

        // Sort: directories first, then alphabetically (case-insensitive)
        return nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - SF Symbol Icons

    /// The SF Symbol name appropriate for this file or directory type.
    public var systemImageName: String {
        if isPackage {
            return "shippingbox.fill"
        }
        if isDirectory {
            return directoryIconName
        }
        return fileIconName
    }

    /// SF Symbol name for directory types, with special cases for known folders.
    private var directoryIconName: String {
        switch name {
        case ".claude":
            return "brain"
        case ".git":
            return "arrow.triangle.branch"
        case "Sources", "Source", "src":
            return "folder.fill.badge.gearshape"
        case "Tests", "test", "tests":
            return "folder.fill.badge.questionmark"
        default:
            if name.hasPrefix(".") {
                return "folder.badge.gearshape"
            }
            return "folder.fill"
        }
    }

    /// SF Symbol name for file types, based on file extension.
    /// Consults user-defined custom file type mappings first.
    private var fileIconName: String {
        let ext = url.pathExtension.lowercased()

        // Check custom mappings first
        if !ext.isEmpty, let custom = CustomFileTypeMappings.mapping(for: ext) {
            return custom.iconName
        }

        // One shared table (`FileTypeIcons`), not a switch of its own: this
        // copy and the settings panel's had already drifted apart — this one
        // did not know `mkd`, `mjs` or `shtml` — and a contributed mapping now
        // reads the same table, so a third copy would be a third drift.
        return FileTypeIcons.builtInIcon(for: ext) ?? "doc"
    }

    // MARK: - Width Calculation

    /// Calculates the estimated display width needed to show the widest visible item
    /// in the tree, accounting for nesting depth, icon, and text length.
    public func maximumDisplayWidth(
        depth: Int = 0,
        characterWidth: CGFloat = 7.5,
        indentPerLevel: CGFloat = 20.0,
        baseWidth: CGFloat = 70.0
    ) -> CGFloat {
        let indent = CGFloat(depth) * indentPerLevel
        let textWidth = CGFloat(name.count) * characterWidth
        let myWidth = baseWidth + indent + textWidth

        guard let children = children else {
            return myWidth
        }

        var maxChildWidth: CGFloat = 0
        for child in children {
            let childWidth = child.maximumDisplayWidth(
                depth: depth + 1,
                characterWidth: characterWidth,
                indentPerLevel: indentPerLevel,
                baseWidth: baseWidth
            )
            maxChildWidth = max(maxChildWidth, childWidth)
        }

        return max(myWidth, maxChildWidth)
    }

    // MARK: - Hashable

    public static func == (lhs: FileTreeNode, rhs: FileTreeNode) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
