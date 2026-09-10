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

    /// A registered project, because `ComposableTabsViewContext` carries one
    /// and a factory cannot be reached without it.
    private func makeWorkspace() throws -> ProjectWorkspace {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViewsContributionPointTests-\(UUID().uuidString)")
            .appendingPathComponent("Test.db").path
        let repo = GitRepo(path: NSTemporaryDirectory(), name: "Test")
        let database = try ProjectDatabase(path: path)
        try database.insert(repo)
        return ProjectWorkspace(repo: repo, database: database)
    }

    private func labels(in view: NSView) -> [String] {
        var found: [String] = []
        if let label = view as? NSTextField { found.append(label.stringValue) }
        for subview in view.subviews { found.append(contentsOf: labels(in: subview)) }
        return found
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
                { "id": "test.alpha", "name": "Alpha" },
                { "id": "test.beta", "name": "Beta", "icon": "$(search)" }
            ]
        }
        """#), to: point)

        for (viewID, name) in [("test.alpha", "Alpha"), ("test.beta", "Beta")] {
            let registryID = ComposableTabsViewID("extension.test.views.\(viewID)")
            #expect(registry.isRegistered(registryID))
            #expect(registry.descriptor(for: registryID).displayName == name)
            #expect(registry.descriptor(for: registryID).isCollapsible)
        }
        #expect(registry.descriptor(for: "extension.test.views.test.beta").symbolName != nil)
        #expect(point.views(for: "test.views").count == 2)
    }

    // MARK: - 15 — withdrawal is per extension

    @Test("withdraw removes only that extension's views")
    func withdrawUnregistersOnlyThatExtension() throws {
        let registry = ComposableTabsViewRegistry()
        let point = ViewsContributionPoint(registry: registry)
        try apply(
            try manifest(name: "first", views: #"""
            { "explorer": [{ "id": "test.one", "name": "One" }] }
            """#),
            to: point)
        try apply(
            try manifest(name: "second", views: #"""
            { "explorer": [{ "id": "test.two", "name": "Two" }] }
            """#),
            to: point)

        point.withdraw(extensionIdentifier: "test.first")

        #expect(!registry.isRegistered("extension.test.first.test.one"))
        #expect(registry.isRegistered("extension.test.second.test.two"))
        #expect(registry.isRegistered(.placeholder))
        #expect(point.views(for: "test.first").isEmpty)
        #expect(point.views(for: "test.second").count == 1)
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

        let controller = registry.makeContentViewController(
            for: "extension.test.pane.test.pane",
            nodeID: UUID(),
            project: try makeWorkspace(),
            paneNumber: 1)

        let placeholder = try #require(controller as? ExtensionViewPlaceholderViewController)
        placeholder.loadViewIfNeeded()
        let text = labels(in: placeholder.view)
        #expect(text.contains("Pane Extension"))
        #expect(text.contains("Pane View"))
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
}
