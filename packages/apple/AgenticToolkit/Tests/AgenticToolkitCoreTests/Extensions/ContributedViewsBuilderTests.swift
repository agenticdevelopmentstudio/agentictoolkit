import Testing
import Foundation
@testable import AgenticToolkitCore

/// What `contributes.views` and `contributes.viewsContainers` mean, tested
/// where the answer is pure — no registry, no window, no run loop. Every case
/// here pins one ruling from the corpus study.
@Suite
struct ContributedViewsBuilderTests {

    // MARK: - Fixtures

    private typealias Built = (
        containers: [ContributedViewContainer],
        views: [ContributedView],
        notes: [ContributedViewNote]
    )

    /// A manifest carrying `views` and `viewsContainers` verbatim, decoded the
    /// way the extension loader decodes one.
    private func build(
        views: String = "{}",
        viewsContainers: String = "{}",
        name: String = "sample",
        publisher: String = "acme"
    ) throws -> Built {
        let json = """
        {
            "name": "\(name)",
            "publisher": "\(publisher)",
            "version": "1.0.0",
            "engines": { "vscode": "^1.74.0" },
            "displayName": "Sample Extension",
            "contributes": {
                "views": \(views),
                "viewsContainers": \(viewsContainers)
            }
        }
        """
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
        let contributions = try #require(manifest.contributes)
        return ContributedViewsBuilder.build(from: contributions, manifest: manifest)
    }

    /// One view in one target container, the shape most of these cases need.
    private func view(
        _ entry: String,
        target: String = "explorer",
        viewsContainers: String = "{}",
        publisher: String = "acme"
    ) throws -> ContributedView {
        let built = try build(
            views: "{ \"\(target)\": [\(entry)] }",
            viewsContainers: viewsContainers,
            publisher: publisher)
        try #require(built.views.count == 1)
        return built.views[0]
    }

    private func notes(
        _ entry: String,
        target: String = "explorer",
        viewsContainers: String = "{}"
    ) throws -> [ContributedViewNote] {
        try build(
            views: "{ \"\(target)\": [\(entry)] }",
            viewsContainers: viewsContainers).notes
    }

    // MARK: - 1 — Ruling EY, the namespaced id

    @Test("two publishers declaring the same view id get different registry ids")
    func registryIDsAreNamespaced() throws {
        let entry = #"{ "id": "clangd.ast", "name": "AST" }"#
        let first = try view(entry, publisher: "llvm")
        let second = try view(entry, publisher: "fork")

        #expect(first.viewID == second.viewID)
        #expect(first.viewID == "clangd.ast")
        #expect(first.registryID == "extension.llvm.sample.clangd.ast")
        #expect(second.registryID == "extension.fork.sample.clangd.ast")
        #expect(first.registryID != second.registryID)
    }

    // MARK: - 2 — the tree/webview default

    @Test("a view with no type is a tree")
    func absentTypeIsATree() throws {
        let built = try build(views: #"{ "explorer": [{ "id": "acme.tree", "name": "Tree" }] }"#)
        try #require(built.views.count == 1)
        #expect(built.views[0].kind == .tree)
        #expect(!built.notes.contains { $0.kind == .webviewNeedsHost })
    }

    @Test("a webview is registered all the same, with a note saying why it is empty")
    func webviewIsRegisteredWithANote() throws {
        let built = try build(
            views: #"{ "explorer": [{ "id": "acme.web", "name": "Web", "type": "webview" }] }"#)
        try #require(built.views.count == 1)
        #expect(built.views[0].kind == .webview)

        let note = try #require(built.notes.first { $0.kind == .webviewNeedsHost })
        #expect(note.viewID == "acme.web")
        #expect(note.extensionIdentifier == "acme.sample")
    }

    // MARK: - 3, 4, 5 — Ruling FA, icons

    @Test("a mapped codicon becomes an SF Symbol name")
    func codiconResolvesToASymbol() throws {
        let built = try view(#"{ "id": "acme.find", "name": "Find", "icon": "$(search)" }"#)
        #expect(built.symbolName != nil)
        #expect(built.symbolName == CodiconSymbols.table["search"])
        #expect(built.iconPath == nil)

        let emitted = try notes(#"{ "id": "acme.find", "name": "Find", "icon": "$(search)" }"#)
        #expect(!emitted.contains { $0.kind == .unmappedIcon || $0.kind == .fileIcon })
    }

    @Test("a vendor-private icon name resolves to nothing, and says so")
    func vendorCodiconIsUnmapped() throws {
        let entry = #"{ "id": "acme.graph", "name": "Graph", "icon": "$(gitlens-graph)" }"#
        #expect(try view(entry).symbolName == nil)

        let note = try #require(try notes(entry).first { $0.kind == .unmappedIcon })
        #expect(note.viewID == "acme.graph")
        #expect(note.detail.contains("gitlens-graph"))
    }

    @Test("a file-path icon is recorded where it lives, not resolved")
    func filePathIconIsRecordedNotResolved() throws {
        let entry = #"{ "id": "acme.pic", "name": "Pic", "icon": "resources/tree.svg" }"#
        let built = try view(entry)
        #expect(built.symbolName == nil)
        #expect(built.iconPath == "resources/tree.svg")

        let note = try #require(try notes(entry).first { $0.kind == .fileIcon })
        #expect(note.detail.contains("resources/tree.svg"))
    }

    // MARK: - 6 — Ruling FB, `when`

    @Test("a when clause is stored verbatim and the view is built anyway")
    func whenIsRecordedAndTheViewIsStillBuilt() throws {
        let entry = #"""
        { "id": "acme.cond", "name": "Cond", "when": "resourceScheme == file" }
        """#
        let built = try view(entry)
        #expect(built.when == "resourceScheme == file")

        let note = try #require(try notes(entry).first { $0.kind == .whenNotEvaluated })
        #expect(note.detail.contains("resourceScheme == file"))
    }

    // MARK: - 7 — Ruling FD, the container decides the axis

    @Test("a view in a panel container prefers the vertical axis")
    func panelContainerMakesTheViewVertical() throws {
        let built = try view(
            #"{ "id": "acme.bottom", "name": "Bottom" }"#,
            target: "acme.strip",
            viewsContainers: #"{ "panel": [{ "id": "acme.strip", "title": "Strip", "icon": "i.svg" }] }"#)
        #expect(built.preferredAxisIsVertical)
    }

    @Test("a view in an activity-bar container prefers the horizontal axis")
    func activitybarMakesItHorizontal() throws {
        let containers = #"""
        { "activitybar": [{ "id": "acme.side", "title": "Side", "icon": "i.svg" }] }
        """#
        let built = try view(
            #"{ "id": "acme.tree", "name": "Tree" }"#,
            target: "acme.side",
            viewsContainers: containers)
        #expect(!built.preferredAxisIsVertical)
    }

    @Test("a view targeting a VS Code built-in is horizontal and unremarkable")
    func builtInTargetMakesItHorizontal() throws {
        let entry = #"{ "id": "acme.files", "name": "Files" }"#
        #expect(!(try view(entry, target: "explorer").preferredAxisIsVertical))
        #expect(!(try notes(entry, target: "explorer")).contains { $0.kind == .unknownContainer })
    }

    @Test("a view targeting a container nobody declares is noted, and horizontal")
    func unknownContainerGetsANoteAndHorizontal() throws {
        let entry = #"{ "id": "acme.orphan", "name": "Orphan" }"#
        let built = try view(entry, target: "someoneElsesContainer")
        #expect(!built.preferredAxisIsVertical)

        let emitted = try notes(entry, target: "someoneElsesContainer")
        let note = try #require(emitted.first { $0.kind == .unknownContainer })
        #expect(note.detail.contains("someoneElsesContainer"))
    }

    // MARK: - 8 — Ruling FC, carried but not mapped

    @Test("visibility and initialSize survive on the metadata")
    func visibilityAndInitialSizeSurviveOnTheMetadata() throws {
        let built = try view(#"""
        { "id": "acme.sized", "name": "Sized", "visibility": "collapsed", "initialSize": 2 }
        """#)
        #expect(built.visibility == "collapsed")
        #expect(built.initialSize == 2)
    }

    // MARK: - 9 — the manifest's own order is gone, so sort

    @Test("containers and views come back in a sorted order, not a hashed one")
    func orderingIsDeterministic() throws {
        let built = try build(
            views: #"""
            {
                "acme.p1": [
                    { "id": "acme.viewZ", "name": "Z" },
                    { "id": "acme.viewA", "name": "A" }
                ],
                "acme.a1": [
                    { "id": "acme.viewM", "name": "M" },
                    { "id": "acme.viewB", "name": "B" }
                ]
            }
            """#,
            viewsContainers: #"""
            {
                "panel": [
                    { "id": "acme.p2", "title": "P2", "icon": "i.svg" },
                    { "id": "acme.p1", "title": "P1", "icon": "i.svg" }
                ],
                "activitybar": [
                    { "id": "acme.a2", "title": "A2", "icon": "i.svg" },
                    { "id": "acme.a1", "title": "A1", "icon": "i.svg" }
                ]
            }
            """#)

        #expect(built.containers.map(\.containerID) == ["acme.a1", "acme.a2", "acme.p1", "acme.p2"])
        #expect(built.containers.map(\.location)
            == ["activitybar", "activitybar", "panel", "panel"])
        #expect(built.views.map(\.viewID)
            == ["acme.viewB", "acme.viewM", "acme.viewA", "acme.viewZ"])
        #expect(built.views.map(\.targetContainerID)
            == ["acme.a1", "acme.a1", "acme.p1", "acme.p1"])
        // The axis follows the container the view landed in, which is the one
        // thing Ruling FD uses a location for.
        #expect(built.views.map(\.preferredAxisIsVertical) == [false, false, true, true])
    }

    // MARK: - 10 — one extension, one id

    @Test("a repeated view id inside one extension is noted and the first wins")
    func duplicateViewIDInOneExtensionIsNotedAndFirstWins() throws {
        let built = try build(views: #"""
        {
            "explorer": [
                { "id": "acme.dupe", "name": "First" },
                { "id": "acme.dupe", "name": "Second" }
            ]
        }
        """#)

        try #require(built.views.count == 1)
        #expect(built.views[0].name == "First")

        let note = try #require(built.notes.first { $0.kind == .duplicateViewID })
        #expect(note.viewID == "acme.dupe")
        #expect(note.detail.contains("explorer"))
    }

    // MARK: - 11 — the regression test for the manifest fix

    @Test("a container that declares no icon still survives decoding")
    func containerWithoutAnIconIsStillRecorded() throws {
        let built = try build(
            views: #"{ "acme.plain": [{ "id": "acme.tree", "name": "Tree" }] }"#,
            viewsContainers: #"{ "activitybar": [{ "id": "acme.plain", "title": "Plain" }] }"#)

        try #require(built.containers.count == 1)
        #expect(built.containers[0].containerID == "acme.plain")
        #expect(built.containers[0].title == "Plain")
        #expect(built.containers[0].icon == nil)

        // The point of the fix: with the container gone, this view's target
        // would be nobody's and every one of them would read as an orphan.
        #expect(!built.notes.contains { $0.kind == .unknownContainer })
        try #require(built.views.count == 1)
        #expect(!built.views[0].preferredAxisIsVertical)
    }

    // MARK: - Decoding leniency the two new fields made necessary

    @Test("a mistyped optional field costs itself, not the whole view")
    func aMistypedOptionalFieldDoesNotCostTheView() throws {
        let built = try build(views: #"""
        {
            "explorer": [
                { "id": "acme.sized", "name": "Sized", "initialSize": "2", "visibility": 7 }
            ]
        }
        """#)
        try #require(built.views.count == 1)
        #expect(built.views[0].initialSize == nil)
        #expect(built.views[0].visibility == nil)
        #expect(built.views[0].name == "Sized")
    }

    @Test("a container's when clause is carried")
    func containerWhenIsCarried() throws {
        let built = try build(viewsContainers: #"""
        {
            "activitybar": [
                { "id": "acme.side", "title": "Side", "icon": "i.svg", "when": "isMac" }
            ]
        }
        """#)
        try #require(built.containers.count == 1)
        #expect(built.containers[0].when == "isMac")
        #expect(built.containers[0].icon == "i.svg")
    }
}
