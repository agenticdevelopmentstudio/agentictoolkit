import CryptoKit
import Foundation
import os

/// A prefix put in front of every persisted window-state key, so two copies of
/// one app can each remember their own window layout.
///
/// Window state is keyed by `windowID` in a preferences domain that belongs to
/// the *bundle identifier* — so two builds of the same app, run at once out of
/// two different worktrees, write to the same keys. Whichever moved a window
/// last wins, and the layout the person at the keyboard arranged is quietly
/// replaced by one an automated session arranged behind the desktop. That is
/// the interruption arriving a launch late instead of immediately.
///
/// The namespace is empty by default, which is the on-disk format every
/// existing installation already has. A host that knows it is a second copy
/// calls `isolateToRunningBundle()` before it first touches `WindowManager`,
/// and from then on reads and writes keys nobody else uses.
///
/// Deliberately a process-wide mutable static rather than an injected
/// dependency: `WindowManager.shared` builds its storage the first time anyone
/// asks for it, from anywhere, and a namespace that only applied to storages
/// constructed after the host had a chance to inject one would apply to none of
/// the ones that matter. Read at key-composition time, not at construction, for
/// the same reason. Lock-guarded rather than `@MainActor`-isolated because
/// `UserDefaultsWindowStateStorage` is not main-actor code and composes the
/// same keys.
public enum WindowStateNamespace {

    private static let state = OSAllocatedUnfairLock(initialState: "")

    /// The current prefix. `""` — no namespace — unless a host sets one.
    public static var current: String { state.withLock { $0 } }

    /// Namespaces window state to wherever this process's bundle lives on disk.
    ///
    /// The path is the identity that actually differs between two copies of one
    /// app: the bundle identifier is shared (that is what makes them the same
    /// app to launchd and to preferences), the pid changes every launch, and a
    /// worktree's build path is both stable and unique. Hashed rather than used
    /// raw so the key stays short and does not carry a developer's directory
    /// names into a preferences file.
    public static func isolateToRunningBundle(_ bundle: Bundle = .main) {
        isolate(toPath: bundle.bundleURL.standardizedFileURL.path)
    }

    /// The path-hashing half, exposed so a test can name a path rather than
    /// having to be launched from one.
    public static func isolate(toPath path: String) {
        let digest = SHA256.hash(data: Data(path.utf8))
        let token = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        state.withLock { $0 = "Instance\(token)_" }
    }

    /// Restores the shared, un-namespaced keys.
    public static func reset() {
        state.withLock { $0 = "" }
    }

    /// `current + key`, which is how every `WindowStateStorage` composes a key.
    public static func qualify(_ key: String) -> String {
        current + key
    }
}
