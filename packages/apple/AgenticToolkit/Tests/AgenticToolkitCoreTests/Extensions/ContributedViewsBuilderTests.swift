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
        // A literal, not `CodiconSymbols.table["search"]`: comparing the output
        // to the table it came from moves both sides together and passes even
        // if `search` were mapped to a real-but-wrong symbol.
        #expect(built.symbolName == "magnifyingglass")
        #expect(built.iconPath == nil)

        let emitted = try notes(#"{ "id": "acme.find", "name": "Find", "icon": "$(search)" }"#)
        #expect(!emitted.contains { $0.kind == .unmappedIcon || $0.kind == .fileIcon })
    }

    @Test("an animated codicon names the same glyph as the still one")
    func codiconAnimationModifierIsIgnored() throws {
        // `$(sync~spin)` asks for an animation of the `sync` glyph, not for a
        // different glyph, so the tilde and what follows it are not part of the
        // name being looked up.
        let built = try view(#"{ "id": "acme.spin", "name": "Spin", "icon": "$(search~spin)" }"#)
        #expect(built.symbolName == "magnifyingglass")
        #expect(!(try notes(#"{ "id": "acme.spin", "name": "Spin", "icon": "$(search~spin)" }"#))
            .contains { $0.kind == .unmappedIcon })
    }

    @Test("an empty icon is neither a symbol, nor a path, nor a complaint")
    func blankIconIsNeitherSymbolNorPath() throws {
        let entry = #"{ "id": "acme.blank", "name": "Blank", "icon": "  " }"#
        let built = try view(entry)
        #expect(built.symbolName == nil)
        #expect(built.iconPath == nil)
        // Whitespace is not a file the extension ships, so a `fileIcon` note
        // here would send a reader looking for an image that never existed.
        #expect((try notes(entry)).isEmpty)

        let parens = #"{ "id": "acme.paren", "name": "Paren", "icon": "$()" }"#
        let empty = try view(parens)
        #expect(empty.symbolName == nil)
        #expect(empty.iconPath == nil)
        // The half that makes the two `nil`s mean something: `table[""]` is
        // `nil` too, so without this the same pair passes for an empty name
        // treated as a codicon — and the only visible difference would be an
        // `unmappedIcon` note complaining about `$()`.
        #expect((try notes(parens)).isEmpty)
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

    /// One case rather than four, and carrying **both** polarities, because
    /// each `!preferredAxisIsVertical` assertion standing on its own would pass
    /// with the axis logic replaced by a hard-coded `false`.
    @Test("the container the view lands in is the only thing that decides the axis")
    func axisFollowsTheContainerLocation() throws {
        let containers = #"""
        {
            "panel": [{ "id": "acme.strip", "title": "Strip", "icon": "i.svg" }],
            "activitybar": [{ "id": "acme.side", "title": "Side", "icon": "i.svg" }]
        }
        """#
        let entry = #"{ "id": "acme.view", "name": "View" }"#
        let expectations: [(target: String, isVertical: Bool)] = [
            ("acme.strip", true),           // self-declared, in the panel location
            ("acme.side", false),           // self-declared, on the activity bar
            ("explorer", false),            // a VS Code built-in
            ("someoneElsesContainer", false) // nobody declares it
        ]

        for expectation in expectations {
            let built = try view(
                entry, target: expectation.target, viewsContainers: containers)
            #expect(
                built.preferredAxisIsVertical == expectation.isVertical,
                "\(expectation.target) should be \(expectation.isVertical ? "vertical" : "horizontal")")
        }
    }

    /// Ruling FD says a view's axis follows its container's *location*, and
    /// enumerates the built-in target ids as horizontal. `panel` is both: it is
    /// the `viewsContainers` key that means the bottom strip **and** a built-in
    /// container id a view may target with no `viewsContainers` at all. This
    /// resolves it to vertical, applying the ruling's reasoning — the panel is
    /// the bottom strip — rather than its enumeration, and that departure is
    /// deliberate. Do not "fix" it back to horizontal without reading Ruling
    /// FD's justification: a bottom-strip pane laid out along the horizontal
    /// axis is the wrong shape for the surface it lives on.
    @Test("a view targeting the built-in panel id lands in the bottom strip")
    func builtInPanelTargetIsVertical() throws {
        let entry = #"{ "id": "acme.bottom", "name": "Bottom" }"#
        #expect(try view(entry, target: "panel").preferredAxisIsVertical)
        #expect(!(try notes(entry, target: "panel")).contains { $0.kind == .unknownContainer })
    }

    @Test("a view targeting a VS Code built-in is not treated as an orphan")
    func builtInTargetIsNotAnUnknownContainer() throws {
        let entry = #"{ "id": "acme.files", "name": "Files" }"#
        #expect(!(try notes(entry, target: "explorer")).contains { $0.kind == .unknownContainer })
    }

    @Test("a view targeting a container nobody declares is noted")
    func unknownContainerGetsANote() throws {
        let entry = #"{ "id": "acme.orphan", "name": "Orphan" }"#
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

    // MARK: - 9 — the location order is gone, so sort; the declared order is not

    @Test("containers and views come back grouped by location, in declared order")
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

        // Locations are dictionary keys, so their order genuinely is gone and
        // something has to fix it — hence alphabetical across locations. The
        // order *within* a location is not gone: it is the array the author
        // wrote, and it is the order the containers appear in on screen, so
        // `a2` before `a1` is preserved rather than alphabetised away (F49).
        #expect(built.containers.map(\.containerID) == ["acme.a2", "acme.a1", "acme.p2", "acme.p1"])
        #expect(built.containers.map(\.location)
            == ["activitybar", "activitybar", "panel", "panel"])
        #expect(built.views.map(\.viewID)
            == ["acme.viewM", "acme.viewB", "acme.viewZ", "acme.viewA"])
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

    @Test("across two targets, the first that wins is the sorted one, not the declared one")
    func duplicateViewIDAcrossTargetsIsResolvedInSortedOrder() throws {
        // The case above cannot tell "first wins" apart from "first in the
        // JSON wins", because both entries sit in one array. Here they sit in
        // two, `zeta` is written first, and `views` decodes into a dictionary
        // — which has no order at all to be first in. So the only thing that
        // can decide the winner is the target sort, and `explorer` sorts
        // before `zeta`. Flip that sort and this fails; delete it and it
        // becomes a coin toss that fails most runs.
        let built = try build(views: #"""
        {
            "zeta": [{ "id": "acme.dupe", "name": "FromZeta" }],
            "explorer": [{ "id": "acme.dupe", "name": "FromExplorer" }]
        }
        """#)

        try #require(built.views.count == 1)
        #expect(built.views[0].name == "FromExplorer")

        // The note names the target that won, which is the fact a reader of
        // the Extensions UI needs and the one this ordering decides.
        let note = try #require(built.notes.first { $0.kind == .duplicateViewID })
        #expect(note.detail.contains("explorer"))
        #expect(!note.detail.contains("zeta"))
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

        // Ruling GF. Keeping the view is only half the trade; the other half is
        // that the field it lost is on the record. A `nil` here has to be
        // distinguishable from a field the author never declared, and the note
        // is the only thing that distinguishes them.
        let malformed = built.notes.filter { $0.kind == .malformedField }
        #expect(malformed.count == 2)
        #expect(malformed.allSatisfy { $0.viewID == "acme.sized" })
        #expect(malformed.contains { $0.detail.contains("initialSize") })
        #expect(malformed.contains { $0.detail.contains("visibility") })
    }

    @Test("a field nobody declared is absence, not a lost declaration")
    func anAbsentOrNullFieldIsNotNoted() throws {
        // The counterweight to the case above: if every `nil` produced a note,
        // `malformedField` would say nothing, because 374 of the corpus's
        // entries omit at least one of these keys. An explicit `null` is a
        // declaration withdrawn by its author and counts as absence too.
        let built = try build(views: #"""
        {
            "explorer": [
                { "id": "acme.plain", "name": "Plain" },
                { "id": "acme.nulled", "name": "Nulled", "when": null, "initialSize": null }
            ]
        }
        """#)
        try #require(built.views.count == 2)
        #expect(!built.notes.contains { $0.kind == .malformedField })
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

    // MARK: - F49 — the manifest's order is the presentation order

    @Test("views keep the order their container declared them in")
    func viewsKeepDeclaredOrder() throws {
        let built = try build(views: """
        {
            "explorer": [
                { "id": "overview", "name": "Overview" },
                { "id": "details", "name": "Details" }
            ]
        }
        """)

        #expect(built.views.map(\.viewID) == ["overview", "details"])
    }

    @Test("view containers keep the order their location declared them in")
    func viewContainersKeepDeclaredOrder() throws {
        let built = try build(viewsContainers: """
        {
            "activitybar": [
                { "id": "zulu", "title": "Zulu", "icon": "$(beaker)" },
                { "id": "alpha", "title": "Alpha", "icon": "$(beaker)" }
            ]
        }
        """)

        #expect(built.containers.map(\.containerID) == ["zulu", "alpha"])
    }
}
