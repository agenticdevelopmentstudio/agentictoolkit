import AgenticToolkitCore
import XCTest
@testable import AgenticToolkitMacOS

final class ProjectCheckoutTests: XCTestCase {
    func testCheckoutsSkipBareEntriesAndKeepOrder() {
        let main = GitWorktree(
            directory: URL(fileURLWithPath: "/repo"),
            head: "abc", branch: "main", isMain: true, isBare: false, isDetached: false
        )
        let bare = GitWorktree(
            directory: URL(fileURLWithPath: "/repo.git"),
            head: "abc", branch: nil, isMain: false, isBare: true, isDetached: false
        )
        let linked = GitWorktree(
            directory: URL(fileURLWithPath: "/repo/.claude/worktrees/tabs"),
            head: "def", branch: "tabs", isMain: false, isBare: false, isDetached: false
        )
        let checkouts = ProjectCheckout.checkouts(from: [main, bare, linked])
        XCTAssertEqual(checkouts.map(\.displayName), ["main", "tabs"])
        XCTAssertEqual(checkouts.map(\.isMain), [true, false])
    }

    func testADetachedCheckoutIsNamedAfterItsFolder() {
        let checkout = ProjectCheckout(directory: URL(fileURLWithPath: "/repo/wt-spike"), branch: nil, isMain: false)
        XCTAssertEqual(checkout.displayName, "wt-spike")
    }

    func testTheIdentifierIsStableAndPathDerived() {
        let first = ProjectCheckout(directory: URL(fileURLWithPath: "/repo/a"), branch: "x", isMain: false)
        let same = ProjectCheckout(directory: URL(fileURLWithPath: "/repo/a/"), branch: "y", isMain: true)
        let other = ProjectCheckout(directory: URL(fileURLWithPath: "/repo/b"), branch: "x", isMain: false)
        XCTAssertEqual(first.identifier, same.identifier)
        XCTAssertNotEqual(first.identifier, other.identifier)
        XCTAssertTrue(first.identifier.allSatisfy { $0.isHexDigit })
    }

    /// `URL.path` already collapses a bare trailing slash, so the case above
    /// does not exercise path normalization at all. `..` segments do.
    func testTheIdentifierNormalizesDotDotSegments() {
        let first = ProjectCheckout(directory: URL(fileURLWithPath: "/repo/x/../a"), branch: "x", isMain: false)
        let same = ProjectCheckout(directory: URL(fileURLWithPath: "/repo/a"), branch: "y", isMain: true)
        XCTAssertEqual(first.identifier, same.identifier)
    }

    /// The case standardizing alone cannot handle: `git worktree list` prints
    /// a fully resolved path, a workspace's directory comes from the path the
    /// user gave, and on this platform `/var` is itself a symlink. Two URLs
    /// for one directory must be one checkout, or the project opens a
    /// duplicate tab group for it.
    func testASymlinkedPathIsTheSameCheckoutAsItsTarget() throws {
        let manager = FileManager.default
        let target = manager.temporaryDirectory
            .appendingPathComponent("checkout-symlink-test-\(UUID().uuidString)")
        try manager.createDirectory(at: target, withIntermediateDirectories: true)
        let link = target.deletingLastPathComponent()
            .appendingPathComponent(target.lastPathComponent + "-link")
        try manager.createSymbolicLink(at: link, withDestinationURL: target)
        defer {
            try? manager.removeItem(at: link)
            try? manager.removeItem(at: target)
        }

        let viaLink = ProjectCheckout(directory: link, branch: "main", isMain: true)
        let viaTarget = ProjectCheckout(directory: target, branch: "main", isMain: true)
        XCTAssertEqual(viaLink.directory, viaTarget.directory)
        XCTAssertEqual(viaLink.identifier, viaTarget.identifier)
        XCTAssertEqual(Set([viaLink, viaTarget]).count, 1)
    }
}
