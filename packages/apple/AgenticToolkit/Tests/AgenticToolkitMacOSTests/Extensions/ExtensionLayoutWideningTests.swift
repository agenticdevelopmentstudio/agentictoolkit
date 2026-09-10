import Testing
import AppKit
import Foundation
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// `ExtensionsCoordinator.spec(_:widenedFor:)`.
///
/// The wiring site that calls it lives in the host app, where no toolkit test
/// can reach — which is exactly why the function is pure and static, and why
/// this suite can pin its behaviour without a window or a running app.
@MainActor
@Suite
struct ExtensionLayoutWideningTests {

    // MARK: - Fixtures

    /// The document layout's shape, in miniature: a split whose root names
    /// what every pane may hold.
    private static let baseSpec = ComposableTabLayoutSpec.split(
        axis: .horizontal,
        children: [.pane(.placeholder), .pane(.placeholder)],
        allows: [.unbounded(.placeholder)]
    )

    private func contributedView(
        identifier: String = "test.pack",
        viewID: String = "test.tree",
        registryID: String = "extension.test.pack.test.tree",
        preferredAxisIsVertical: Bool = false
    ) -> ContributedView {
        ContributedView(
            extensionIdentifier: identifier,
            viewID: viewID,
            registryID: registryID,
            targetContainerID: "explorer",
            name: "Tree",
            kind: .tree,
            symbolName: nil,
            iconPath: nil,
            when: nil,
            visibility: nil,
            initialSize: nil,
            preferredAxisIsVertical: preferredAxisIsVertical
        )
    }

    private func manifest(name: String, views: String) throws -> ExtensionManifest {
        let json = """
        {
            "name": "\(name)",
            "publisher": "test",
            "version": "1.0.0",
            "displayName": "Pack",
            "engines": { "vscode": "^1.74.0" },
            "contributes": { "views": \(views) }
        }
        """
        return try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
    }

    // MARK: - Tests

    @Test("a contributed view becomes an unbounded allowance")
    func aContributedViewBecomesAnUnboundedAllowance() {
        let widened = ExtensionsCoordinator.spec(
            Self.baseSpec, widenedFor: [contributedView()])

        #expect(widened.allows.count == 2)
        let added = widened.allows[1]
        #expect(added.viewID == ComposableTabsViewID("extension.test.pack.test.tree"))
        // Unbounded, not `max: 1`: an extension view is auxiliary, and capping
        // it would stop a user opening the same view in two panes for no reason
        // this host can justify.
        #expect(added.max == nil)
        #expect(added.min == 0)
        // The base's own allowance survives untouched — widening adds, it does
        // not replace.
        #expect(widened.allows[0].viewID == .placeholder)
    }

    @Test("no contributed views leaves the spec identical")
    func noContributedViewsLeavesTheSpecIdentical() {
        let widened = ExtensionsCoordinator.spec(Self.baseSpec, widenedFor: [])

        #expect(widened.allows.count == Self.baseSpec.allows.count)
        let viewIDs = widened.allows.map(\.viewID)
        let baseViewIDs = Self.baseSpec.allows.map(\.viewID)
        #expect(viewIDs == baseViewIDs)
        #expect(widened.isFixed == Self.baseSpec.isFixed)
        // No extensions is the normal case on every install today: the wiring
        // site reinstalls the layout only when something was actually added,
        // and this is the value that decision reads.
        if case .split(let axis, let children) = widened.kind {
            #expect(axis == .horizontal)
            #expect(children.count == 2)
        } else {
            Issue.record("widening an empty view list changed the spec's kind")
        }
    }

    @Test("the widened spec validates against the registry that registered those views")
    func theWidenedSpecValidatesAgainstTheRegistryThatRegisteredThoseViews() throws {
        let registry = ComposableTabsViewRegistry()
        let point = ViewsContributionPoint(registry: registry)
        let declaration = try manifest(
            name: "pack",
            views: #"{ "explorer": [{ "id": "test.tree", "name": "Tree" }] }"#
        )
        let contributions = try #require(declaration.contributes)
        // The directory is never opened: this point turns every manifest key
        // that names a file into a note rather than reading it.
        try point.apply(contributions, from: declaration, at: URL(fileURLWithPath: "/var/empty/none"))

        let views = point.views(for: "test.pack")
        try #require(views.count == 1)
        let widened = ExtensionsCoordinator.spec(Self.baseSpec, widenedFor: views)

        // `validate(against:)` only checks that the ids a spec *names* are
        // registered, never the reverse — so a view registered by the point and
        // named by no allowance is registered and unplaceable, and this is the
        // assertion that the two halves agree.
        #expect(throws: Never.self) {
            try widened.validate(against: registry)
        }

        // And the failure mode is real: an id the registry never saw is refused.
        let strayView = contributedView(registryID: "extension.test.pack.not.registered")
        let stray = ExtensionsCoordinator.spec(Self.baseSpec, widenedFor: [strayView])
        #expect(throws: ComposableTabLayoutSpecError.self) {
            try stray.validate(against: registry)
        }
    }

    @Test("preferred axis follows the contributed view")
    func preferredAxisFollowsTheContributedView() throws {
        let vertical = ExtensionsCoordinator.spec(
            Self.baseSpec, widenedFor: [contributedView(preferredAxisIsVertical: true)])
        // A bottom-strip view splits vertically; everything else splits across.
        #expect(vertical.allows.last?.preferredAxis == .vertical)

        let horizontal = ExtensionsCoordinator.spec(
            Self.baseSpec, widenedFor: [contributedView(preferredAxisIsVertical: false)])
        #expect(horizontal.allows.last?.preferredAxis == .horizontal)

        // And end to end, because the flag is not spelled in a manifest: the
        // container id is, and `panel` is the one that means the bottom strip.
        #expect(try axis(ofViewTargeting: "panel") == .vertical)
        #expect(try axis(ofViewTargeting: "explorer") == .horizontal)
    }

    /// The axis the widened spec ends up allowing for a view contributed into
    /// `container`, taken through the real point rather than a hand-built
    /// `ContributedView`.
    private func axis(ofViewTargeting container: String) throws -> ComposableTabsAxis? {
        let point = ViewsContributionPoint(registry: ComposableTabsViewRegistry())
        let declaration = try manifest(
            name: container,
            views: #"{ "\#(container)": [{ "id": "test.tree", "name": "Tree" }] }"#
        )
        let contributions = try #require(declaration.contributes)
        try point.apply(contributions, from: declaration, at: URL(fileURLWithPath: "/var/empty/none"))
        let views = point.views(for: "test.\(container)")
        try #require(views.count == 1)
        return ExtensionsCoordinator.spec(Self.baseSpec, widenedFor: views).allows.last?.preferredAxis
    }
}
