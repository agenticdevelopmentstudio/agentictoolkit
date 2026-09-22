import AppKit
import AgenticToolkitCore
import Foundation
import Testing
@testable import AgenticToolkitMacOS

/// The AppKit half of `contributes.views`. What a declaration *means* is
/// pinned in `ContributedViewsBuilderTests`, where it needs no window; this
/// suite is about the registry, the placeholder pane, and withdrawal.
///
/// Every publisher here is `test`, so every registry id these tests touch
/// begins `extension.test.` — a namespace no real extension can reach, since
/// the identifier is `publisher.name` and no publisher on Open VSX is called
/// `test`. Each test builds its own registry, so nothing outlives it.
@MainActor
@Suite
struct ViewsContributionPointTests {

    // MARK: - Fixtures

    /// Handed to `apply` and never opened: this point turns every manifest key
    /// that names a file into a note rather than reading it, and a directory
    /// that does not exist is the cheapest way to keep that true.
    private static let unusedDirectory = URL(fileURLWithPath: "/var/empty/agentic-tests-nonexistent")

    private func manifest(
        name: String,
        displayName: String = "Test Extension",
        views: String = "{}",
        viewsContainers: String = "{}"
    ) throws -> ExtensionManifest {
        let json = """
        {
            "name": "\(name)",
            "publisher": "test",
            "version": "1.0.0",
            "engines": { "vscode": "^1.74.0" },
            "displayName": "\(displayName)",
            "contributes": {
                "views": \(views),
                "viewsContainers": \(viewsContainers)
            }
        }
        """
        return try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
    }

    private func apply(_ manifest: ExtensionManifest, to point: ViewsContributionPoint) throws {
        let contributions = try #require(manifest.contributes)
        try point.apply(contributions, from: manifest, at: Self.unusedDirectory)
    }

    /// Names the temporary directories `ProjectWindowTestSupport` makes for
    /// this suite, and is what `removeWorkspaceDirectories` finds them by.
    private static let workspaceLabel = "ViewsContributionPointTests"

    /// A registered project, because `ComposableTabsViewContext` carries one
    /// and a factory cannot be reached without it.
    ///
    /// `ProjectWindowTestSupport.makeProject` is the bundle's one answer to
    /// this and predates this suite; a second private copy would be a second
    /// answer to a settled question (`dry`).
    private func makeWorkspace() -> ProjectWorkspace {
        ProjectWindowTestSupport.makeProject(label: Self.workspaceLabel, named: "Test")
    }

    /// The helper owns the UUID and returns only the workspace, so cleanup
    /// cannot go by a returned URL — it goes by the label prefix, which is why
    /// the label is a constant rather than a string spelled at the call site.
    private func removeWorkspaceDirectories() {
        let root = FileManager.default.temporaryDirectory
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where entry.lastPathComponent.hasPrefix(Self.workspaceLabel) {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    /// Builds one registered pane, which is the only way to reach the factory
    /// the contribution point handed the registry.
    ///
    /// A pane's working directory is its own — a worktree's, not always the
    /// project's — so the registry takes it separately. This suite has one
    /// checkout, which makes the project's directory the right answer here.
    private func pane(
        _ registryID: String,
        from registry: ComposableTabsViewRegistry,
        in workspace: ProjectWorkspace
    ) -> NSViewController {
        registry.makeContentViewController(
            for: ComposableTabsViewID(registryID),
            nodeID: UUID(),
            project: workspace,
            workingDirectory: workspace.directoryURL,
            paneNumber: 1)
    }

    private func textFields(in view: NSView) -> [NSTextField] {
        var found: [NSTextField] = []
        if let label = view as? NSTextField { found.append(label) }
        for subview in view.subviews { found.append(contentsOf: textFields(in: subview)) }
        return found
    }

    private func labels(in view: NSView) -> [String] {
        textFields(in: view).map(\.stringValue)
    }

    // MARK: - 13 — Ruling FA, the table has to resolve on this platform

    @Test("every SF Symbol name in the codicon table resolves")
    func everySymbolInTheTableResolves() {
        for (codicon, symbol) in CodiconSymbols.table {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            #expect(image != nil, "\(codicon) maps to \(symbol), which does not resolve")
        }
    }

    // MARK: - 14 — apply reaches the injected registry

    @Test("apply registers every view under its namespaced id")
    func applyRegistersEveryViewInTheInjectedRegistry() throws {
        let registry = ComposableTabsViewRegistry()
        let point = ViewsContributionPoint(registry: registry)
        try apply(try manifest(name: "views", views: #"""
        {
            "explorer": [
                { "id": "test.alpha", "name": "Alpha", "initialSize": 2 },
                { "id": "test.beta", "name": "Beta", "icon": "$(search)" }
            ]
        }
        """#), to: point)

        for (viewID, name) in [("test.alpha", "Alpha"), ("test.beta", "Beta")] {
            let registryID = ComposableTabsViewID("extension.test.views.\(viewID)")
            #expect(registry.isRegistered(registryID))
            #expect(registry.descriptor(for: registryID).displayName == name)
            #expect(registry.descriptor(for: registryID).isCollapsible)
            // Ruling FC, at the only place it can be observed. `initialSize` is
            // a VS Code *weight* among siblings, not a fraction of the window,
            // so `Alpha`'s `2` is carried on the metadata and deliberately not
            // handed to the registry as a thickness it does not mean.
            #expect(registry.descriptor(for: registryID).preferredThicknessFraction == nil)
        }
        #expect(point.views(for: "test.views").first { $0.viewID == "test.alpha" }?
            .initialSize == 2)
        #expect(registry.descriptor(for: "extension.test.views.test.beta").symbolName != nil)
        #expect(point.views(for: "test.views").count == 2)
    }

    // MARK: - 15 — withdrawal is per extension

    @Test("withdraw removes only that extension's views")
    func withdrawUnregistersOnlyThatExtension() throws {
        let registry = ComposableTabsViewRegistry()
        let point = ViewsContributionPoint(registry: registry)
        try apply(
            // Both `when`s are load-bearing: each produces one Ruling FB note,
            // so the note assertions below are over two notes rather than over
            // an empty array that satisfies anything asked of it.
            try manifest(name: "first", views: #"""
            { "explorer": [{ "id": "test.one", "name": "One", "when": "isMac" }] }
            """#),
            to: point)
        try apply(
            try manifest(name: "second", views: #"""
            { "explorer": [{ "id": "test.two", "name": "Two", "when": "isMac" }] }
            """#),
            to: point)
        try #require(point.notes.count == 2)

        point.withdraw(extensionIdentifier: "test.first")

        #expect(!registry.isRegistered("extension.test.first.test.one"))
        #expect(registry.isRegistered("extension.test.second.test.two"))
        #expect(registry.isRegistered(.placeholder))
        #expect(point.views(for: "test.first").isEmpty)
        #expect(point.views(for: "test.second").count == 1)
        // The count catches a `removeAll` that removed nothing; the predicate
        // catches one that removed the wrong extension's.
        #expect(point.notes.count == 1)
        #expect(point.notes.allSatisfy { $0.extensionIdentifier == "test.second" })
    }

    // MARK: - 16 — Ruling EZ

    @Test("unregister refuses the placeholder")
    func unregisterRefusesThePlaceholder() {
        let registry = ComposableTabsViewRegistry()
        #expect(registry.unregister(.placeholder) == false)
        #expect(registry.isRegistered(.placeholder))
    }

    @Test("unregister answers whether anything was there")
    func unregisterReportsWhatItRemoved() {
        let registry = ComposableTabsViewRegistry()
        let viewID = ComposableTabsViewID("test.sample")
        registry.register(viewID, descriptor: .init(displayName: "Sample")) { _ in
            NSViewController()
        }
        #expect(registry.unregister(viewID))
        #expect(registry.unregister(viewID) == false)
    }

    // MARK: - 17 — the pane the factory vends

    @Test("the registered factory vends the extension placeholder, naming the extension")
    func theFactoryProducesThePlaceholderController() throws {
        let registry = ComposableTabsViewRegistry()
        let point = ViewsContributionPoint(registry: registry)
        try apply(
            try manifest(name: "pane", displayName: "Pane Extension", views: #"""
            { "explorer": [{ "id": "test.pane", "name": "Pane View" }] }
            """#),
            to: point)

        defer { removeWorkspaceDirectories() }
        let workspace = makeWorkspace()
        let controller = pane("extension.test.pane.test.pane", from: registry, in: workspace)

        let placeholder = try #require(controller as? ExtensionViewPlaceholderViewController)
        placeholder.loadViewIfNeeded()
        let text = labels(in: placeholder.view)
        #expect(text.contains("Pane Extension"))
        #expect(text.contains("Pane View"))
    }

    // MARK: - N3 — the wrap width is a measurement, not a constant

    /// Drives real layout passes at three deliberate widths and asserts the
    /// width the label was *left with*, not the one it was handed. Each width
    /// is the only one that can see one of the three operations: a narrow pane
    /// has to produce something smaller than `explanationWidth` (the
    /// measurement), a wide one has to stop at it (the ceiling), and a
    /// collapsed one has to produce `0` rather than a negative (the floor).
    ///
    /// Zero is not hypothetical: these panes are registered `isCollapsible`,
    /// and a collapsed `NSSplitViewItem` is laid out at zero width.
    ///
    /// This is as close to on-screen as a headless bundle gets. It proves
    /// `viewDidLayout` runs and computes what it should; it cannot prove the
    /// sentence is legible, which needs the pane in a window.
    @Test("the explanation wraps at the pane's width when the pane is narrower than the ceiling")
    func explanationWrapWidthFollowsThePaneWidth() throws {
        let view = ContributedView(
            extensionIdentifier: "test.pane",
            viewID: "test.pane",
            registryID: "extension.test.pane.test.pane",
            targetContainerID: "explorer",
            name: "Pane View",
            kind: .tree,
            symbolName: nil,
            iconPath: nil,
            when: nil,
            visibility: nil,
            initialSize: nil,
            preferredAxisIsVertical: false)
        let controller = ExtensionViewPlaceholderViewController(
            view: view, extensionDisplayName: "Pane Extension")
        controller.loadViewIfNeeded()

        let explanation = try #require(
            textFields(in: controller.view).first { $0.stringValue.hasPrefix("This view's") })

        controller.view.frame = NSRect(x: 0, y: 0, width: 200, height: 300)
        controller.view.layoutSubtreeIfNeeded()
        #expect(explanation.preferredMaxLayoutWidth == 168)

        controller.view.frame = NSRect(x: 0, y: 0, width: 900, height: 300)
        controller.view.layoutSubtreeIfNeeded()
        #expect(explanation.preferredMaxLayoutWidth == 320)

        // A collapsed pane. `0` means "no maximum" to AppKit, which is a
        // documented value; the `-32` this computes without its floor is not
        // documented at all.
        controller.view.frame = NSRect(x: 0, y: 0, width: 0, height: 300)
        controller.view.layoutSubtreeIfNeeded()
        #expect(explanation.preferredMaxLayoutWidth == 0)
    }

    // MARK: - 18 — applying twice is applying once

    @Test("applying the same manifest twice leaves one registration and one set of notes")
    func applyIsIdempotent() throws {
        let registry = ComposableTabsViewRegistry()
        let point = ViewsContributionPoint(registry: registry)
        let sample = try manifest(name: "twice", views: #"""
        { "explorer": [{ "id": "test.once", "name": "Once", "when": "isMac" }] }
        """#)

        try apply(sample, to: point)
        let firstNotes = point.notes
        let firstIDs = registry.registeredViewIDs
        try apply(sample, to: point)

        #expect(point.notes == firstNotes)
        #expect(registry.registeredViewIDs == firstIDs)
        #expect(point.views(for: "test.twice").count == 1)
        #expect(registry.isRegistered("extension.test.twice.test.once"))
    }

    // MARK: - Ruling FD, through the registry's own vocabulary

    @Test("a panel container's view asks for the vertical axis")
    func panelContainerReachesTheDescriptorAsVertical() throws {
        let registry = ComposableTabsViewRegistry()
        let point = ViewsContributionPoint(registry: registry)
        try apply(
            try manifest(
                name: "axis",
                views: #"{ "test.strip": [{ "id": "test.bottom", "name": "Bottom" }] }"#,
                viewsContainers: #"""
                { "panel": [{ "id": "test.strip", "title": "Strip", "icon": "i.svg" }] }
                """#),
            to: point)

        #expect(registry.descriptor(for: "extension.test.axis.test.bottom")
            .preferredAxis == .vertical)
        #expect(point.containers(for: "test.axis").count == 1)
    }

    // MARK: - The factory's two live branches

    /// `resolveWebview` and `resolveTree` are `nil` until the hosts are up, and
    /// the placeholder test above is the pane that state produces. These are
    /// the other side: with a seam wired, each kind has to reach *its own*
    /// wrapper, since a tree in a webview wrapper would wait forever for an
    /// `html` nobody is going to assign.
    @Test("a tree view reaches the tree wrapper once a resolver is wired")
    func aTreeViewReachesTheTreeWrapper() throws {
        let registry = ComposableTabsViewRegistry()
        let point = ViewsContributionPoint(registry: registry)
        var asked: [ContributedView] = []
        point.resolveTree = { view, _ in asked.append(view) }
        // Wired too, and deliberately: the kinds have to be told apart by the
        // declaration, not by which seam happens to be the only one filled in.
        point.resolveWebview = { _, _ in nil }
        try apply(
            try manifest(name: "pane", displayName: "Pane Extension", views: #"""
            { "explorer": [{ "id": "test.tree", "name": "Tree View" }] }
            """#),
            to: point)

        defer { removeWorkspaceDirectories() }
        let workspace = makeWorkspace()
        let wrapper = try #require(
            pane("extension.test.pane.test.tree", from: registry, in: workspace)
                as? ExtensionTreeViewController)

        // Building the pane asks nobody: the wrapper asks in `viewDidLoad`, so
        // a pane a window never shows never wakes the extension.
        #expect(asked.isEmpty)
        wrapper.loadViewIfNeeded()
        #expect(asked.map(\.registryID) == ["extension.test.pane.test.tree"])
        #expect(asked.map(\.kind) == [.tree])
    }

    @Test("a webview view reaches the webview wrapper once a resolver is wired")
    func aWebviewViewReachesTheWebviewWrapper() throws {
        let registry = ComposableTabsViewRegistry()
        let point = ViewsContributionPoint(registry: registry)
        var asked: [ContributedView] = []
        // `nil` is the honest answer from a host with nobody to draw this, and
        // it keeps a `WKWebView` out of a headless bundle.
        point.resolveWebview = { view, _ in
            asked.append(view)
            return nil
        }
        point.resolveTree = { _, _ in }
        try apply(
            try manifest(name: "pane", displayName: "Pane Extension", views: #"""
            { "explorer": [{ "id": "test.page", "name": "Page View", "type": "webview" }] }
            """#),
            to: point)

        defer { removeWorkspaceDirectories() }
        let workspace = makeWorkspace()
        let wrapper = try #require(
            pane("extension.test.pane.test.page", from: registry, in: workspace)
                as? ExtensionWebviewViewController)

        wrapper.loadViewIfNeeded()
        #expect(asked.map(\.registryID) == ["extension.test.pane.test.page"])
        #expect(asked.map(\.kind) == [.webview])
    }

    /// The other half of the placeholder test above, which covers a tree with
    /// no `resolveTree`. A webview with no `resolveWebview` is the same state
    /// through the other branch, and both fall past the `switch` to the same
    /// return.
    @Test("a webview view with no resolver falls back to the placeholder")
    func aWebviewViewWithoutAResolverFallsBackToThePlaceholder() throws {
        let registry = ComposableTabsViewRegistry()
        let point = ViewsContributionPoint(registry: registry)
        // Only the *tree* seam is wired, so a webview still has nobody.
        point.resolveTree = { _, _ in }
        try apply(
            try manifest(name: "pane", displayName: "Pane Extension", views: #"""
            { "explorer": [{ "id": "test.page", "name": "Page View", "type": "webview" }] }
            """#),
            to: point)

        defer { removeWorkspaceDirectories() }
        let workspace = makeWorkspace()
        let placeholder = try #require(
            pane("extension.test.pane.test.page", from: registry, in: workspace)
                as? ExtensionViewPlaceholderViewController)
        placeholder.loadViewIfNeeded()
        #expect(labels(in: placeholder.view).contains("Page View"))
    }

    /// The sentence has to name the thing that did not happen, because that is
    /// the whole point of showing a sentence rather than an empty outline: a
    /// tree pane is waiting on a *provider registration*, and a webview pane on
    /// a provider actually *running*.
    @Test("the placeholder explains the kind of content that is missing")
    func thePlaceholderNamesWhatEachKindIsWaitingFor() throws {
        func explanation(for kind: ContributedView.Kind) throws -> String {
            let controller = ExtensionViewPlaceholderViewController(
                view: ContributedView(
                    extensionIdentifier: "test.pane",
                    viewID: "test.pane",
                    registryID: "extension.test.pane.test.pane",
                    targetContainerID: "explorer",
                    name: "Pane View",
                    kind: kind,
                    symbolName: nil,
                    iconPath: nil,
                    when: nil,
                    visibility: nil,
                    initialSize: nil,
                    preferredAxisIsVertical: false),
                extensionDisplayName: "Pane Extension")
            controller.loadViewIfNeeded()
            return try #require(
                labels(in: controller.view).first { $0.hasPrefix("This view's") })
        }

        #expect(try explanation(for: .tree).contains("tree data provider"))
        #expect(try explanation(for: .webview).contains("webview view provider"))
    }

    /// The broadcast is what wakes an extension whose activation event is
    /// `onView:`, and it goes out before the `switch` for a reason a tree makes
    /// visible: a tree pane never reaches a seam that can wake anyone, so if
    /// the broadcast were inside the webview branch a tree would activate
    /// nothing and then wait for rows from an extension that is still asleep.
    @Test("every pane appearing is broadcast, whatever kind it is and whoever can draw it")
    func everyPaneAppearanceIsBroadcast() throws {
        let registry = ComposableTabsViewRegistry()
        let point = ViewsContributionPoint(registry: registry)
        var appeared: [String] = []
        point.onViewWillAppear = { appeared.append($0.registryID) }
        try apply(
            try manifest(name: "pane", displayName: "Pane Extension", views: #"""
            {
                "explorer": [
                    { "id": "test.tree", "name": "Tree View" },
                    { "id": "test.page", "name": "Page View", "type": "webview" }
                ]
            }
            """#),
            to: point)

        defer { removeWorkspaceDirectories() }
        let workspace = makeWorkspace()
        // Both built with every seam still `nil` — the state an extension that
        // has never been activated is in, and the one the broadcast exists for.
        _ = pane("extension.test.pane.test.tree", from: registry, in: workspace)
        _ = pane("extension.test.pane.test.page", from: registry, in: workspace)

        #expect(appeared == [
            "extension.test.pane.test.tree",
            "extension.test.pane.test.page"
        ])
    }

    /// The swap the tree wrapper exists for, in both directions a headless
    /// bundle can see: a provider that never registers leaves the sentence up,
    /// and one that resolves takes it down.
    @Test("the tree wrapper shows the explanation until a data source arrives")
    func theTreeWrapperSwapsTheExplanationForTheTree() throws {
        let view = ContributedView(
            extensionIdentifier: "test.pane",
            viewID: "test.tree",
            registryID: "extension.test.pane.test.tree",
            targetContainerID: "explorer",
            name: "Tree View",
            kind: .tree,
            symbolName: nil,
            iconPath: nil,
            when: nil,
            visibility: nil,
            initialSize: nil,
            preferredAxisIsVertical: false)

        let waiting = ExtensionTreeViewController(
            view: view, extensionDisplayName: "Pane Extension", resolve: { _, _ in })
        waiting.loadViewIfNeeded()
        #expect(labels(in: waiting.view).contains { $0.hasPrefix("This view's") })

        let source = StubTreeDataSource(roots: [
            ContributedTreeItem(
                id: "#fruit", label: "Fruit", description: nil, tooltip: nil,
                collapsibleState: .collapsed, symbolName: nil, commandID: nil)
        ])
        let resolved = ExtensionTreeViewController(
            view: view, extensionDisplayName: "Pane Extension",
            resolve: { _, didResolve in didResolve(source) })
        resolved.loadViewIfNeeded()
        #expect(!labels(in: resolved.view).contains { $0.hasPrefix("This view's") })
    }
}

/// A registered provider, as far as a pane can tell, with no JavaScript host
/// behind it. What the adaptor makes of a *real* provider is
/// `MainThreadTreeViewsTests`; this is only enough for the wrapper to have
/// something to adopt.
@MainActor
private final class StubTreeDataSource: ExtensionTreeDataSource {

    private let roots: [ContributedTreeItem]

    private(set) var activated: [String] = []

    var title: String?
    var message: String?
    var allowsMultipleSelection = false
    var onDidChangeTreeData: ((String?) -> Void)?
    var onDidChangeChrome: (() -> Void)?
    var onProviderReplaced: ((any ExtensionTreeDataSource) -> Void)?

    init(roots: [ContributedTreeItem]) {
        self.roots = roots
    }

    func children(of parent: ContributedTreeItem?) async -> [ContributedTreeItem] {
        parent == nil ? roots : []
    }

    func activate(_ item: ContributedTreeItem) {
        activated.append(item.id)
    }

    func selectionDidChange(to _: [ContributedTreeItem]) {}
    func visibilityDidChange(to _: Bool) {}
    func didExpand(_: ContributedTreeItem) {}
    func didCollapse(_: ContributedTreeItem) {}
}
