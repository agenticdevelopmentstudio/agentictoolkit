import AppKit
import Foundation
import Testing
@testable import AgenticToolkitMacOS

/// What the pane does while an extension's `getChildren` is out, and what it
/// does with the answer when it lands.
///
/// Both rules here are about *time*, which is why they cannot be tested on
/// `ExtensionTreeRowTable`: the table is the synchronous half. A provider is an
/// extension's own code behind a promise, so a branch can be asked, left
/// waiting, asked again, and answered out of order — and the two failures that
/// causes are a branch nobody can ever re-ask, and one row drawn in two places.
@MainActor
struct ExtensionTreePaneLoadingTests {

    private func makePane(
        _ source: any ExtensionTreeDataSource, budget: TimeInterval = 30
    ) -> ExtensionTreeOutlineViewController {
        let pane = ExtensionTreeOutlineViewController(
            dataSource: source, fallbackTitle: "Tree", accessibilityPrefix: "test.tree")
        pane.childrenBudget = budget
        pane.loadViewIfNeeded()
        return pane
    }

    private let outline = NSOutlineView()

    private func rows(
        of item: Any?, in pane: ExtensionTreeOutlineViewController
    ) -> [ExtensionTreeRow] {
        let count = pane.outlineView(outline, numberOfChildrenOfItem: item)
        return (0..<count).compactMap {
            pane.outlineView(outline, child: $0, ofItem: item) as? ExtensionTreeRow
        }
    }

    /// Asks until the answer has landed, or gives up. The pane draws what it
    /// has and reloads when the provider answers, so the first ask is always
    /// empty — waiting is the test's job, exactly as it is AppKit's.
    private func rowsWhenAnswered(
        of item: Any?, in pane: ExtensionTreeOutlineViewController
    ) async -> [ExtensionTreeRow] {
        for _ in 0..<400 {
            let found = rows(of: item, in: pane)
            if !found.isEmpty { return found }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return []
    }

    /// Waits for the pane's ask to actually reach the provider, or gives up.
    ///
    /// The count is the observation, not the wait: a test that wants to say
    /// "asked exactly once" still has to see the one ask arrive first, or it
    /// is asserting against a provider nothing has called yet — which passes
    /// for the wrong reason.
    private func asks(reaching count: Int, in source: SilentTreeDataSource) async -> Int {
        for _ in 0..<400 {
            if source.asks >= count { return source.asks }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return source.asks
    }

    // MARK: - A provider that never answers

    /// The bug the budget exists for. While `getChildren` is out the handle is
    /// held as loading, which is what stops a second ask — so a provider that
    /// never answers does not leave the branch *empty*, it leaves it
    /// *unaskable*, and no refresh, recovery or reopen gets it back.
    @Test("a branch whose provider never answers can be asked again")
    func aSilentProviderDoesNotWedgeTheBranch() async throws {
        let source = SilentTreeDataSource()
        let pane = makePane(source, budget: 0.05)

        _ = rows(of: nil, in: pane)
        // **The ask has to be waited for, not read straight back.** The pane
        // spawns a `Task` for it, so the provider is reached on a later turn
        // of the main actor than the one that scheduled it; reading `asks`
        // in the same synchronous stretch measures the scheduling, not the
        // ask, and answers zero whenever the machine is busy enough not to
        // have run the task yet.
        let asked = await asks(reaching: 1, in: source)
        #expect(asked >= 1)

        try await Task.sleep(for: .milliseconds(300))
        _ = rows(of: nil, in: pane)

        #expect(await asks(reaching: asked + 1, in: source) > asked)
    }

    /// The other half, and the reason the fix is a budget rather than dropping
    /// the guard: inside the budget the branch is still considered in flight,
    /// so an outline that asks for the same rows twice in one pass does not
    /// call into the extension twice.
    @Test("a second ask inside the budget does not reach the provider twice")
    func anAskInFlightIsNotRepeated() async {
        let source = SilentTreeDataSource()
        let pane = makePane(source, budget: 30)

        _ = rows(of: nil, in: pane)
        // Seeing the first ask land is what makes the count below an
        // assertion: read synchronously it is zero, and "zero twice" is a
        // sentence about a provider nothing ever called.
        let asked = await asks(reaching: 1, in: source)
        #expect(asked == 1)

        _ = rows(of: nil, in: pane)
        _ = rows(of: nil, in: pane)
        // Long enough for a second ask to have arrived if the guard let one
        // through — the first one took a single turn of the actor.
        try? await Task.sleep(for: .milliseconds(100))

        #expect(source.asks == asked)
    }

    // MARK: - A row that moves

    /// An extension is free to answer the same item under a second parent —
    /// a "recently used" branch listing a file the folder branch also lists —
    /// and `NSOutlineView` identifies rows by object identity, so the same row
    /// in two places is a state it cannot draw. The newest answer wins and the
    /// branch it was taken from is redrawn without it.
    @Test("an item a second branch claims leaves the branch it was in")
    func aClaimedRowLeavesItsOldBranch() async throws {
        let source = ScriptedTreeDataSource(children: [
            "": [Self.item("a", expandable: true), Self.item("b", expandable: true)],
            "a": [Self.item("x")],
            "b": []
        ])
        let pane = makePane(source)

        let roots = await rowsWhenAnswered(of: nil, in: pane)
        #expect(roots.map(\.handle) == ["a", "b"])
        let branchA = try #require(roots.first { $0.handle == "a" })
        let branchB = try #require(roots.first { $0.handle == "b" })

        let underA = await rowsWhenAnswered(of: branchA, in: pane)
        #expect(underA.map(\.handle) == ["x"])
        let movedRow = try #require(underA.first)

        // `b` has not been asked yet, so this is its first read and the pane
        // goes to the provider for it. A branch it had already read would be
        // answered from the cache instead, and that is a different seam.
        source.children["b"] = [Self.item("x")]
        let underB = await rowsWhenAnswered(of: branchB, in: pane)

        #expect(underB.map(\.handle) == ["x"])
        // The same row object, because the outline tracks expansion and
        // selection by identity — a replacement would collapse the subtree.
        #expect(underB.first === movedRow)
        #expect(rows(of: branchA, in: pane).isEmpty)
    }

    // MARK: - A pane replaced by a newer one

    /// One pane per view id is the model, and a second pane for the same
    /// contributed view takes the data source's two callbacks over. The pane it
    /// replaced is still a live object the window will discard *later* — when
    /// the user finally closes that tab — and its teardown used to pull the
    /// callbacks out from under the pane that had taken them. From then on the
    /// visible tree was frozen: the extension's `_onDidChangeTreeData` reached
    /// nothing, and no refresh, command or reopen woke it up again.
    @Test("a superseded pane's teardown leaves the live pane wired")
    func aSupersededPaneDoesNotUnwireItsSuccessor() async throws {
        let source = ScriptedTreeDataSource(children: ["": [Self.item("a")]])
        let superseded = makePane(source)
        let live = makePane(source)

        let before = await rowsWhenAnswered(of: nil, in: live)
        #expect(before.map(\.handle) == ["a"])

        superseded.paneContentWillBeDiscarded()

        // The extension is not told the tree went away either: the pane the
        // user is looking at is still showing it.
        #expect(source.visibilityReports.isEmpty)

        source.children[""] = [Self.item("a"), Self.item("b")]
        source.onDidChangeTreeData?(nil)

        var handles: [String] = []
        for _ in 0..<400 {
            handles = rows(of: nil, in: live).map(\.handle)
            if handles.count == 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(handles == ["a", "b"])

        // And the live pane's own teardown still does all of it, which is what
        // stops the fix from being "never unwire".
        live.paneContentWillBeDiscarded()
        #expect(source.onDidChangeTreeData == nil)
        #expect(source.visibilityReports == [false])
    }

    private static func item(
        _ id: String, expandable: Bool = false
    ) -> ContributedTreeItem {
        ContributedTreeItem(
            id: id,
            label: id,
            description: nil,
            tooltip: nil,
            collapsibleState: expandable ? .collapsed : .none,
            symbolName: nil,
            commandID: nil)
    }
}

/// A provider that takes the question and is never heard from again — a
/// promise nothing resolves, a subprocess that hung, a network call with no
/// timeout of its own.
@MainActor
private final class SilentTreeDataSource: ExtensionTreeDataSource {

    private(set) var asks = 0

    var title: String?
    var message: String?
    var allowsMultipleSelection = false
    var onDidChangeTreeData: ((String?) -> Void)?
    var onDidChangeChrome: (() -> Void)?
    var onProviderReplaced: ((any ExtensionTreeDataSource) -> Void)?

    func children(of _: ContributedTreeItem?) async -> [ContributedTreeItem] {
        asks += 1
        // Long enough to outlast the test by any margin; the pane is expected
        // to stop waiting, not to be waited for.
        try? await Task.sleep(for: .seconds(120))
        return []
    }

    func activate(_: ContributedTreeItem) {}
    func selectionDidChange(to _: [ContributedTreeItem]) {}
    func visibilityDidChange(to _: Bool) {}
    func didExpand(_: ContributedTreeItem) {}
    func didCollapse(_: ContributedTreeItem) {}
}

/// A provider whose answers a test can rewrite between asks, which is how an
/// extension that moves an item between branches looks from here.
@MainActor
private final class ScriptedTreeDataSource: ExtensionTreeDataSource {

    var children: [String: [ContributedTreeItem]]
    private(set) var visibilityReports: [Bool] = []

    var title: String?
    var message: String?
    var allowsMultipleSelection = false
    var onDidChangeTreeData: ((String?) -> Void)?
    var onDidChangeChrome: (() -> Void)?
    var onProviderReplaced: ((any ExtensionTreeDataSource) -> Void)?

    init(children: [String: [ContributedTreeItem]]) {
        self.children = children
    }

    func children(of parent: ContributedTreeItem?) async -> [ContributedTreeItem] {
        self.children[parent?.id ?? ""] ?? []
    }

    func activate(_: ContributedTreeItem) {}
    func selectionDidChange(to _: [ContributedTreeItem]) {}
    func visibilityDidChange(to visible: Bool) { visibilityReports.append(visible) }
    func didExpand(_: ContributedTreeItem) {}
    func didCollapse(_: ContributedTreeItem) {}
}
