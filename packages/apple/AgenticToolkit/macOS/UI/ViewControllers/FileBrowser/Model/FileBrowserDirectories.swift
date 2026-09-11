import Combine
import Foundation

/// The set of directories a file browser shows: one it always shows, plus any
/// the user has added.
///
/// The primary is separate from the rest because it is *derived* — a document's
/// own folder, a window's repository — so it cannot be missing or stale, and it
/// is the one root `−` must never take away. Only the additions are state, and
/// only the additions are what `onChange` hands a host to persist
/// (`explicit-over-implicit`).
@MainActor
public final class FileBrowserDirectories: ObservableObject {

    /// Always shown, never removable.
    public let primary: URL

    /// What the user has added, in the order they added it.
    @Published public private(set) var additional: [URL]

    /// Called with the new `additional` list whenever it changes, so a host can
    /// persist it. Injected rather than reached for: this type has no idea
    /// whether it is backed by a document, defaults, or nothing at all
    /// (`dependency-injection`).
    public var onChange: (([URL]) -> Void)?

    /// Every root, primary first.
    public var all: [URL] { [primary] + additional }

    /// Every root is normalized with `resolvingSymlinksInPath()` rather than
    /// `standardizedFileURL`, matching the rule `ProjectCheckout.swift:12`
    /// documents: the same folder reaches this object as a checkout directory
    /// that git already resolved and as a path the user picked that nothing
    /// did, and a lexical comparison would call those two different roots —
    /// two managers, two git status providers, one folder (`dry`).
    public init(primary: URL, additional: [URL] = []) {
        self.primary = primary.resolvingSymlinksInPath()
        // A stored list can name the primary (the user added the folder before
        // it became the document's own), or the same folder twice. Repairing on
        // the way in keeps every later `all` free of duplicate roots.
        var seen: Set<URL> = [self.primary]
        self.additional = additional.compactMap { url in
            let resolved = url.resolvingSymlinksInPath()
            guard seen.insert(resolved).inserted else { return nil }
            return resolved
        }
    }

    /// Adds `url` unless it is already a root. Returns whether anything changed,
    /// so a caller can tell "added" from "already there" (`fail-fast` in the
    /// small: no silent no-op that looks like success).
    @discardableResult
    public func add(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        guard !all.contains(resolved) else { return false }
        additional.append(resolved)
        onChange?(additional)
        return true
    }

    /// Removes `url` if it is one of the added roots. The primary is not
    /// removable, so passing it does nothing.
    @discardableResult
    public func remove(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        guard let index = additional.firstIndex(of: resolved) else { return false }
        additional.remove(at: index)
        onChange?(additional)
        return true
    }

    public func isRemovable(_ url: URL) -> Bool {
        additional.contains(url.resolvingSymlinksInPath())
    }

    /// The root `url` lives under, or `nil` if it lives under none of them.
    /// Longest match wins, so a directory added *inside* another one still
    /// claims its own files.
    public func root(containing url: URL) -> URL? {
        let path = url.resolvingSymlinksInPath().path
        return all
            .filter { path == $0.path || path.hasPrefix($0.path + "/") }
            .max { $0.path.count < $1.path.count }
    }
}
