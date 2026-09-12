import Foundation

/// A git repository the app knows about.
///
/// The identity is the `id`, not the path: a repository that moves keeps its
/// settings, its layout and its name because the row is re-pointed rather than
/// replaced. That is the whole reason the primary key is a UUID and not the
/// path (`optimize-for-change`).
public struct GitRepo: Sendable, Identifiable, Equatable {

    public let id: UUID
    /// Absolute path to the working tree.
    public var path: String
    /// What to call it. Seeded from the directory name, then the user's to change.
    public var name: String
    /// `origin`'s URL, or `nil` for a repository with no remote.
    public var remote: String?
    public var firstSeen: Date
    public var lastSeen: Date
    /// When a project window was last opened for it — what the browser sorts by.
    public var lastOpened: Date?

    public init(
        id: UUID = UUID(),
        path: String,
        name: String,
        remote: String? = nil,
        firstSeen: Date = Date(),
        lastSeen: Date = Date(),
        lastOpened: Date? = nil
    ) {
        self.id = id
        self.path = path
        self.name = name
        self.remote = remote
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.lastOpened = lastOpened
    }

    /// `isDirectory: true`, because a repository's path is one and the URL is
    /// compared for equality against checkout directories built elsewhere —
    /// left to guess, Foundation would give a repository on an unmounted
    /// volume a different URL than the same repository once it is back.
    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    /// The default name for a repository at `path` — its directory name.
    public static func defaultName(forPath path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

/// One repository as the scanner found it on disk. Deliberately not a
/// `GitRepo`: a scan result has no identity yet — deciding whether it is a new
/// repository, a moved one, or one already known is the reconciler's job.
public struct ScannedGitRepo: Sendable, Equatable {
    public let path: String
    public let remote: String?

    public init(path: String, remote: String?) {
        self.path = path
        self.remote = remote
    }

    public var leafName: String { URL(fileURLWithPath: path).lastPathComponent }
}

/// What a scan changed, for the log line and the progress window's last word.
public struct ProjectScanSummary: Sendable, Equatable {
    public var added: Int = 0
    public var moved: Int = 0
    /// Rows the scan deleted because nothing it found on disk accounts for them.
    public var removed: Int = 0
    public var unchanged: Int = 0
    /// Rows the scan did not report but which are still git repositories on
    /// disk — kept, because the scan not looking is not the same as the
    /// project being gone.
    public var skipped: Int = 0

    public init() {}

    /// Every project in the registry once the scan has been applied.
    public var found: Int { added + moved + unchanged + skipped }

    /// One line for the log, and for the progress window before it closes.
    public var summaryText: String {
        var parts: [String] = []
        if added > 0 { parts.append("\(added) new") }
        if moved > 0 { parts.append("\(moved) moved") }
        if removed > 0 { parts.append("\(removed) removed") }
        if skipped > 0 { parts.append("\(skipped) not scanned") }
        let headline = "\(found) project\(found == 1 ? "" : "s")"
        if parts.isEmpty { return headline + ", no changes" }
        return headline + " — " + parts.joined(separator: ", ")
    }
}
