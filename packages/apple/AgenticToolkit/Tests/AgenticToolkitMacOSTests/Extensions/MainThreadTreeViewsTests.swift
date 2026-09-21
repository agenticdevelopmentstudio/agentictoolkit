import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// `vscode.window.registerTreeDataProvider`, `vscode.window.createTreeView`,
/// and the `TreeView` object the second one hands back — wired onto a real
/// `ExtensionHost` and a real `CommandRegistry`.
///
/// **No double stands in for the pane.** Every assertion here goes through
/// `ExtensionTreeDataSource`, which is the seam the pane itself pulls rows
/// through, so what these tests pin is exactly what
/// `ExtensionTreeOutlineViewController` sees. A pane double would prove only
/// that the double was called.
@MainActor
@Suite
struct MainThreadTreeViewsTests {

    // MARK: - Fixtures

    private func makeTempDirectory() throws -> URL {
        try ExtensionFixtures.makeTemporaryDirectory("MainThreadTreeViewsTests")
    }

    /// The whole arrangement in one call: a temporary extension directory, a
    /// command registry with `vscode.commands.registerCommand` over it, a
    /// ledger, the adaptor, and a host running `source` with all three members
    /// installed.
    ///
    /// `registerCommand` is installed unconditionally rather than per-test: a
    /// tree row's `command` is dispatched through the registry, so the registry
    /// is part of this adaptor's arrangement and not an extra a few tests opt
    /// into.
    ///
    /// The caller disposes the host; the directory is the caller's too.
    ///
    /// `commands` is returned only so the caller keeps it alive.
    /// `VSCodeAPI.member` captures its adaptor **weakly**, so an adaptor left
    /// as a local here deallocates the moment this returns and every
    /// `registerCommand` the extension makes raises "this extension's host has
    /// been torn down" — during `activate()`, which turns it into an
    /// `activationThrew` no assertion in the test body ever reaches.
    private func makeFixture(
        source: String,
        extensionDirectory: URL
    ) throws -> (
        host: ExtensionHost,
        treeViews: MainThreadTreeViews,
        registry: CommandRegistry,
        ledger: NotImplementedLedger,
        commands: MainThreadCommands
    ) {
        let ledger = NotImplementedLedger()
        let registry = CommandRegistry()
        let commands = MainThreadCommands(registry: registry)
        let treeViews = MainThreadTreeViews(
            notImplementedLedger: ledger,
            extensionIdentifier: "acme.alpha",
            commands: registry)
        let host = try makeHost(source: source, in: extensionDirectory, ledger: ledger)
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "registerTreeDataProvider",
            implementation: treeViews.registerTreeDataProvider)
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "createTreeView",
            implementation: treeViews.createTreeView)
        try host.defineVSCodeMember(
            namespacePath: "vscode.commands", name: "registerCommand",
            implementation: commands.registerCommand)
        return (host, treeViews, registry, ledger, commands)
    }

    /// The source most tests below start from: a two-level tree whose elements
    /// are plain objects, with one row carrying every optional field.
    private static let twoLevelProvider = """
        var vscode = require('vscode');
        globalThis.__roots = [
            { key: 'fruit', label: 'Fruit', kids: [{ key: 'apple', label: 'Apple' }] },
            { key: 'veg', label: 'Vegetables', kids: [] }
        ];
        exports.activate = function () {
            vscode.window.registerTreeDataProvider('acme.tree', {
                getChildren: function (element) {
                    return element ? element.kids : globalThis.__roots;
                },
                getTreeItem: function (element) {
                    var item = new vscode.TreeItem(
                        element.label,
                        element.kids && element.kids.length
                            ? vscode.TreeItemCollapsibleState.Collapsed
                            : vscode.TreeItemCollapsibleState.None);
                    item.id = element.key;
                    item.description = element.key + ' description';
                    item.tooltip = element.key + ' tooltip';
                    item.iconPath = new vscode.ThemeIcon('folder-library');
                    return item;
                }
            });
        };
        """

    /// The data source a registered provider is reachable through, or a failed
    /// requirement — every test's first line after activation.
    private func dataSource(
        _ treeViews: MainThreadTreeViews, for viewID: String = "acme.tree"
    ) throws -> any ExtensionTreeDataSource {
        try #require(treeViews.treeDataSource(for: viewID))
    }

    // MARK: - Registering

    /// Registration is what makes a pane resolvable at all: before it, the pane
    /// shows the placeholder naming the missing provider, and after it the pane
    /// pulls rows. Nothing below can be true if this is not.
    @Test
    func registeringAProviderMakesADataSourceReachableForThatViewID() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: Self.twoLevelProvider, extensionDirectory: directory)
        defer { fixture.host.dispose() }

        #expect(fixture.treeViews.hasTreeDataProvider(for: "acme.tree") == false)
        try await fixture.host.activate()

        #expect(fixture.treeViews.hasTreeDataProvider(for: "acme.tree"))
        #expect(fixture.treeViews.treeDataSource(for: "acme.tree") != nil)
        #expect(fixture.treeViews.treeDataSource(for: "acme.other") == nil)
    }

    /// Every field the pane draws, read off one `TreeItem` — the assertion that
    /// would fail if `read(_:element:handle:in:)` reached for a property by the
    /// wrong name.
    @Test
    func rootRowsCarryTheLabelDescriptionTooltipStateAndIcon() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: Self.twoLevelProvider, extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let rows = try await dataSource(fixture.treeViews).children(of: nil)
        #expect(rows.map(\.label) == ["Fruit", "Vegetables"])
        #expect(rows.first?.description == "fruit description")
        #expect(rows.first?.tooltip == "fruit tooltip")
        #expect(rows.first?.collapsibleState == .collapsed)
        #expect(rows.last?.collapsibleState == ContributedTreeItem.CollapsibleState.none)
        // `folder-library` is in `CodiconSymbols.table`, and the symbol it maps
        // to is what the row view asks `NSImage` for.
        #expect(rows.first?.symbolName == "folder")
    }

    /// The second half of the pull: a branch is asked for by handing the
    /// provider back **its own element**, not the `ContributedTreeItem` the
    /// pane holds. Reaching for the wrong object is the failure that shows up
    /// as a tree whose branches are all empty.
    @Test
    func childrenAreAskedForWithTheProvidersOwnElement() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: Self.twoLevelProvider, extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let source = try dataSource(fixture.treeViews)
        let roots = await source.children(of: nil)
        let fruit = try #require(roots.first)
        let children = await source.children(of: fruit)
        #expect(children.map(\.label) == ["Apple"])
    }

    /// `TreeItem.id` is upstream's stable identity, and the handle is what the
    /// pane keys its rows — and therefore its disclosure — on. A declared id
    /// has to survive into the handle, or an extension that reorders its rows
    /// moves every expansion.
    @Test
    func aDeclaredTreeItemIDBecomesTheHandle() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: Self.twoLevelProvider, extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let rows = try await dataSource(fixture.treeViews).children(of: nil)
        #expect(rows.map(\.id) == ["#fruit", "#veg"])
    }

    /// The fallback, which most published extensions actually run on: no `id`,
    /// so the handle is the row's path from the root. The two spaces cannot
    /// collide — one starts with `#`, the other with `/`.
    @Test
    func anItemWithNoIDGetsAPositionalHandle() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.window.registerTreeDataProvider('acme.tree', {
                    getChildren: function (element) {
                        return element ? [] : ['one', 'two'];
                    },
                    getTreeItem: function (element) {
                        return new vscode.TreeItem(element);
                    }
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let rows = try await dataSource(fixture.treeViews).children(of: nil)
        #expect(rows.map(\.id) == ["/0", "/1"])
        #expect(rows.map(\.label) == ["one", "two"])
    }

    /// `getTreeItem` is documented as returning a `TreeItem`, and a large share
    /// of published extensions return a plain object literal instead. A host
    /// that demanded the constructor would reject them.
    @Test
    func aPlainObjectFromGetTreeItemIsReadLikeATreeItem() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.window.registerTreeDataProvider('acme.tree', {
                    getChildren: function (element) { return element ? [] : [1]; },
                    getTreeItem: function () {
                        return { label: 'Plain', description: 'literal', collapsibleState: 2 };
                    }
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let rows = try await dataSource(fixture.treeViews).children(of: nil)
        #expect(rows.first?.label == "Plain")
        #expect(rows.first?.description == "literal")
        #expect(rows.first?.collapsibleState == .expanded)
    }

    /// `ProviderResult` is `T | Thenable<T>`, and an extension that reads a
    /// directory or a network answers with a promise. Rows have to wait for it
    /// rather than reading an unsettled object as "no children".
    @Test
    func aPromiseFromGetChildrenAndGetTreeItemIsAwaited() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.window.registerTreeDataProvider('acme.tree', {
                    getChildren: function (element) {
                        return Promise.resolve(element ? [] : ['deferred']);
                    },
                    getTreeItem: function (element) {
                        return Promise.resolve(new vscode.TreeItem(element));
                    }
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let rows = try await dataSource(fixture.treeViews).children(of: nil)
        #expect(rows.map(\.label) == ["deferred"])
    }

    /// An object without the two methods is a mistake that is otherwise silent
    /// until the pane is on screen and empty (`fail-fast`).
    @Test
    func registeringSomethingThatIsNotATreeDataProviderThrows() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                try {
                    vscode.window.registerTreeDataProvider('acme.tree', { getChildren: 1 });
                    globalThis.__outcome = 'returned';
                } catch (error) {
                    globalThis.__outcome = 'threw';
                }
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let context = try #require(fixture.host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__outcome")?.toString() == "threw")
        #expect(fixture.treeViews.treeDataSource(for: "acme.tree") == nil)
    }

    /// Disposing the registration is how an extension retracts a provider, and
    /// the pane has to stop being resolvable at that moment — not at the next
    /// refresh, which may never come.
    @Test
    func disposingTheRegistrationRetractsTheDataSource() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__registration = vscode.window.registerTreeDataProvider('acme.tree', {
                    getChildren: function () { return []; },
                    getTreeItem: function () { return { label: 'x' }; }
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()
        #expect(fixture.treeViews.hasTreeDataProvider(for: "acme.tree"))

        let context = try #require(fixture.host.javaScriptContext)
        context.evaluateScript("globalThis.__registration.dispose();")
        #expect(fixture.treeViews.hasTreeDataProvider(for: "acme.tree") == false)
    }

    /// Last registration wins — the registration VS Code would refuse is the
    /// one an extension makes after a reload, and keeping the first would leave
    /// a live pane wired to a dead context.
    @Test
    func aSecondRegistrationForTheSameViewIDTakesOver() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                function provider(label) {
                    return {
                        getChildren: function (element) { return element ? [] : [label]; },
                        getTreeItem: function (element) { return { label: element }; }
                    };
                }
                vscode.window.registerTreeDataProvider('acme.tree', provider('first'));
                vscode.window.registerTreeDataProvider('acme.tree', provider('second'));
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let rows = try await dataSource(fixture.treeViews).children(of: nil)
        #expect(rows.map(\.label) == ["second"])
    }

    /// The other half of "last wins": the **first** registration's `Disposable`
    /// must not tear out the second. That is what the registration token is
    /// for, and nothing else here would notice it missing.
    @Test
    func theFirstRegistrationsDisposableCannotRetractTheSecond() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var provider = {
                    getChildren: function () { return []; },
                    getTreeItem: function () { return { label: 'x' }; }
                };
                globalThis.__first =
                    vscode.window.registerTreeDataProvider('acme.tree', provider);
                vscode.window.registerTreeDataProvider('acme.tree', provider);
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let context = try #require(fixture.host.javaScriptContext)
        context.evaluateScript("globalThis.__first.dispose();")
        #expect(fixture.treeViews.hasTreeDataProvider(for: "acme.tree"))
    }

    // MARK: - Refreshing

    /// `onDidChangeTreeData` fired with an element names one branch, and the
    /// pane reloads only that branch — which is what keeps the rest of the
    /// tree's disclosure, and the user's place in it.
    @Test
    func firingTheChangeEventWithAnElementNamesThatElementsHandle() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            globalThis.__changed = new vscode.EventEmitter();
            globalThis.__roots = [{ key: 'fruit', label: 'Fruit' }];
            exports.activate = function () {
                vscode.window.registerTreeDataProvider('acme.tree', {
                    onDidChangeTreeData: globalThis.__changed.event,
                    getChildren: function (element) {
                        return element ? [] : globalThis.__roots;
                    },
                    getTreeItem: function (element) {
                        var item = new vscode.TreeItem(element.label);
                        item.id = element.key;
                        return item;
                    }
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let source = try dataSource(fixture.treeViews)
        // An element is only resolvable to a handle once the pane has pulled
        // the row it belongs to — the real sequence, and the reason an element
        // nobody has seen refreshes everything instead.
        _ = await source.children(of: nil)

        var handles: [String?] = []
        source.onDidChangeTreeData = { handles.append($0) }
        let context = try #require(fixture.host.javaScriptContext)
        context.evaluateScript("globalThis.__changed.fire(globalThis.__roots[0]);")
        #expect(handles == ["#fruit"])
    }

    /// Fired with nothing, which is how nearly every extension says "refresh":
    /// the pane is told `nil` and re-asks every branch it has already read.
    @Test
    func firingTheChangeEventWithNothingNamesTheWholeTree() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            globalThis.__changed = new vscode.EventEmitter();
            exports.activate = function () {
                vscode.window.registerTreeDataProvider('acme.tree', {
                    onDidChangeTreeData: globalThis.__changed.event,
                    getChildren: function () { return []; },
                    getTreeItem: function () { return { label: 'x' }; }
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let source = try dataSource(fixture.treeViews)
        var handles: [String?] = []
        source.onDidChangeTreeData = { handles.append($0) }
        let context = try #require(fixture.host.javaScriptContext)
        context.evaluateScript("globalThis.__changed.fire(undefined);")
        #expect(handles == [nil])
    }

    /// An element the pane has never drawn cannot be turned into a handle, and
    /// the honest answer is the whole tree rather than nothing: over-refreshing
    /// costs a `getChildren`, under-refreshing leaves a tree that has silently
    /// stopped matching the world.
    @Test
    func firingTheChangeEventWithAnUnknownElementNamesTheWholeTree() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            globalThis.__changed = new vscode.EventEmitter();
            exports.activate = function () {
                vscode.window.registerTreeDataProvider('acme.tree', {
                    onDidChangeTreeData: globalThis.__changed.event,
                    getChildren: function () { return []; },
                    getTreeItem: function () { return { label: 'x' }; }
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let source = try dataSource(fixture.treeViews)
        var handles: [String?] = []
        source.onDidChangeTreeData = { handles.append($0) }
        let context = try #require(fixture.host.javaScriptContext)
        context.evaluateScript("globalThis.__changed.fire({ never: 'drawn' });")
        #expect(handles == [nil])
    }

    // MARK: - Activating a row

    /// A row's `command` is what a double click and a Return both end at, and
    /// it goes to the app's own `CommandRegistry` — a tree row routinely runs a
    /// command another extension, or the app itself, contributed.
    @Test
    func activatingARowRunsItsCommandThroughTheRegistryWithItsArguments() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            globalThis.__ran = null;
            exports.activate = function () {
                vscode.commands.registerCommand('acme.open', function (which) {
                    globalThis.__ran = which;
                });
                vscode.window.registerTreeDataProvider('acme.tree', {
                    getChildren: function (element) { return element ? [] : ['row']; },
                    getTreeItem: function (element) {
                        var item = new vscode.TreeItem(element);
                        item.command = { command: 'acme.open', arguments: ['argument'] };
                        return item;
                    }
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let source = try dataSource(fixture.treeViews)
        let rows = await source.children(of: nil)
        #expect(rows.first?.commandID == "acme.open")
        #expect(fixture.registry.command(id: "acme.open") != nil)
        source.activate(try #require(rows.first))

        let context = try #require(fixture.host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__ran")?.toString() == "argument")
    }

    /// A row with no command is the common case, and activating it must be a
    /// no-op rather than a dispatch of some other row's command.
    @Test
    func activatingARowWithNoCommandRunsNothing() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            globalThis.__ran = null;
            exports.activate = function () {
                vscode.commands.registerCommand('acme.open', function () {
                    globalThis.__ran = 'ran';
                });
                vscode.window.registerTreeDataProvider('acme.tree', {
                    getChildren: function (element) { return element ? [] : ['row']; },
                    getTreeItem: function (element) { return { label: element }; }
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let source = try dataSource(fixture.treeViews)
        let rows = await source.children(of: nil)
        #expect(rows.first?.commandID == nil)
        source.activate(try #require(rows.first))

        let context = try #require(fixture.host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__ran")?.isNull == true)
    }

    // MARK: - createTreeView and the TreeView object

    /// The chrome an extension writes from JavaScript has to reach the pane
    /// through the data source — the pane reads `title` and `message` there and
    /// nowhere else — and has to read back as what was written.
    @Test
    func theTreeViewObjectsTitleMessageAndCanSelectManyReachTheDataSource() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__view = vscode.window.createTreeView('acme.tree', {
                    canSelectMany: true,
                    treeDataProvider: {
                        getChildren: function () { return []; },
                        getTreeItem: function () { return { label: 'x' }; }
                    }
                });
                globalThis.__view.title = 'Written from JavaScript';
                globalThis.__view.message = 'no results';
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let source = try dataSource(fixture.treeViews)
        #expect(source.title == "Written from JavaScript")
        #expect(source.message == "no results")
        #expect(source.allowsMultipleSelection)

        let context = try #require(fixture.host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__view.title")?.toString()
            == "Written from JavaScript")
    }

    /// Chrome written later has to reach the pane as it happens: a message set
    /// a second after the view was created is the ordinary case, not an edge
    /// one. And the same value written twice is not a change — a pane that
    /// relaid out on every assignment would flicker for an extension that
    /// rewrites its own state on a timer.
    @Test
    func writingTheMessageLaterTellsThePaneOnceForEachRealChange() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__view = vscode.window.createTreeView('acme.tree', {
                    treeDataProvider: {
                        getChildren: function () { return []; },
                        getTreeItem: function () { return { label: 'x' }; }
                    }
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let source = try dataSource(fixture.treeViews)
        var chromeChanges = 0
        source.onDidChangeChrome = { chromeChanges += 1 }
        let context = try #require(fixture.host.javaScriptContext)
        context.evaluateScript("globalThis.__view.message = 'later';")
        #expect(source.message == "later")
        #expect(chromeChanges == 1)

        context.evaluateScript("globalThis.__view.message = 'later';")
        #expect(chromeChanges == 1)
    }

    /// `onDidChangeSelection` carries the extension's **own elements** back,
    /// which is the only form an extension can act on — a handle would be this
    /// host's private bookkeeping.
    @Test
    func selectingRowsFiresOnDidChangeSelectionWithTheProvidersElements() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            globalThis.__selected = [];
            exports.activate = function () {
                globalThis.__view = vscode.window.createTreeView('acme.tree', {
                    treeDataProvider: {
                        getChildren: function (element) {
                            return element ? [] : ['one', 'two'];
                        },
                        getTreeItem: function (element) { return { label: element }; }
                    }
                });
                globalThis.__view.onDidChangeSelection(function (event) {
                    globalThis.__selected = event.selection.slice();
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let source = try dataSource(fixture.treeViews)
        let rows = await source.children(of: nil)
        source.selectionDidChange(to: [try #require(rows.last)])

        let context = try #require(fixture.host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__selected.join(',')")?.toString() == "two")
        #expect(context.evaluateScript("globalThis.__view.selection.join(',')")?.toString()
            == "two")
    }

    /// Visibility is what an extension throttles its own work on, so a pane
    /// appearing and disappearing has to reach it — and a repeat of the state
    /// it is already in must not.
    @Test
    func visibilityChangesFireOnceEach() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            globalThis.__visibility = [];
            exports.activate = function () {
                globalThis.__view = vscode.window.createTreeView('acme.tree', {
                    treeDataProvider: {
                        getChildren: function () { return []; },
                        getTreeItem: function () { return { label: 'x' }; }
                    }
                });
                globalThis.__view.onDidChangeVisibility(function (event) {
                    globalThis.__visibility.push(event.visible);
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let source = try dataSource(fixture.treeViews)
        source.visibilityDidChange(to: true)
        source.visibilityDidChange(to: true)
        source.visibilityDidChange(to: false)

        let context = try #require(fixture.host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__visibility.join(',')")?.toString()
            == "true,false")
        #expect(context.evaluateScript("globalThis.__view.visible")?.toBool() == false)
    }

    /// The user's own gesture, reported the way upstream reports it —
    /// `{ element }`, with the extension's object inside.
    @Test
    func expandingAndCollapsingFireTheirEventsWithTheElement() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            globalThis.__log = [];
            exports.activate = function () {
                globalThis.__view = vscode.window.createTreeView('acme.tree', {
                    treeDataProvider: {
                        getChildren: function (element) {
                            return element ? [] : ['branch'];
                        },
                        getTreeItem: function (element) {
                            return { label: element, collapsibleState: 1 };
                        }
                    }
                });
                globalThis.__view.onDidExpandElement(function (event) {
                    globalThis.__log.push('expanded:' + event.element);
                });
                globalThis.__view.onDidCollapseElement(function (event) {
                    globalThis.__log.push('collapsed:' + event.element);
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let source = try dataSource(fixture.treeViews)
        let rows = await source.children(of: nil)
        let branch = try #require(rows.first)
        source.didExpand(branch)
        source.didCollapse(branch)

        let context = try #require(fixture.host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__log.join(',')")?.toString()
            == "expanded:branch,collapsed:branch")
    }

    // MARK: - The ledger

    /// Every member an extension can reach that this host reads and drops. A
    /// user looking at the extension's row in Settings should see what it is
    /// waiting for, rather than a capability silently discarded.
    @Test
    func membersThisHostDoesNotDrawRecordALedgerRow() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var view = vscode.window.createTreeView('acme.tree', {
                    showCollapseAll: true,
                    manageCheckboxStateManually: true,
                    dragAndDropController: { dropMimeTypes: [], dragMimeTypes: [] },
                    treeDataProvider: {
                        getChildren: function (element) { return element ? [] : [1]; },
                        getTreeItem: function () {
                            return { label: 'x', contextValue: 'file', checkboxState: 0 };
                        }
                    }
                });
                view.description = 'a subtitle this pane has nowhere to draw';
                view.reveal(1);
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()
        _ = try await dataSource(fixture.treeViews).children(of: nil)

        let paths = Set(fixture.ledger.accesses(for: "acme.alpha").map(\.memberPath))
        #expect(paths.contains("vscode.TreeViewOptions.showCollapseAll"))
        #expect(paths.contains("vscode.TreeViewOptions.manageCheckboxStateManually"))
        #expect(paths.contains("vscode.TreeViewOptions.dragAndDropController"))
        #expect(paths.contains("vscode.TreeView.description"))
        #expect(paths.contains("vscode.TreeView.reveal"))
        #expect(paths.contains("vscode.TreeItem.contextValue"))
        #expect(paths.contains("vscode.TreeItem.checkboxState"))
    }

    /// An `iconPath` naming a file is a capability that is not built. A
    /// `ThemeIcon` with no faithful SF Symbol is `CodiconSymbols`' own
    /// deliberate answer and not a gap of this adaptor's, so it draws no icon
    /// and records nothing — which is why the row's `count` is the assertion
    /// and not merely its presence.
    @Test
    func aFileIconPathRecordsARowAndAnUnmappableCodiconDoesNot() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.window.registerTreeDataProvider('acme.tree', {
                    getChildren: function (element) { return element ? [] : ['a', 'b']; },
                    getTreeItem: function (element) {
                        var item = new vscode.TreeItem(element);
                        item.iconPath = element === 'a'
                            ? new vscode.ThemeIcon('github')
                            : { fsPath: '/tmp/icon.png' };
                        return item;
                    }
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let rows = try await dataSource(fixture.treeViews).children(of: nil)
        #expect(rows.map(\.symbolName) == [nil, nil])
        let iconRows = fixture.ledger.accesses(for: "acme.alpha")
            .filter { $0.memberPath == "vscode.TreeItem.iconPath" }
        #expect(iconRows.map(\.count) == [1])
    }

    // MARK: - Teardown

    /// A torn-down host must not leave a pane pulling rows out of a dead
    /// context.
    @Test
    func disposingTheAdaptorRetractsEveryDataSource() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: Self.twoLevelProvider, extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()
        #expect(fixture.treeViews.hasTreeDataProvider(for: "acme.tree"))

        fixture.treeViews.dispose()
        #expect(fixture.treeViews.hasTreeDataProvider(for: "acme.tree") == false)
        #expect(fixture.treeViews.treeDataSource(for: "acme.tree") == nil)
    }

    /// A member called after teardown raises rather than answering an object
    /// every member of which would be a lie — `.raisedException`, the shape
    /// both these members were installed with.
    @Test
    func registeringAfterTeardownThrows() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__register = function () {
                    try {
                        vscode.window.registerTreeDataProvider('acme.late', {
                            getChildren: function () { return []; },
                            getTreeItem: function () { return { label: 'x' }; }
                        });
                        return 'returned';
                    } catch (error) {
                        return 'threw';
                    }
                };
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let context = try #require(fixture.host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__register()")?.toString() == "returned")
        fixture.treeViews.dispose()
        #expect(context.evaluateScript("globalThis.__register()")?.toString() == "threw")
    }
}

/// A flag an `AppCommand` can set from wherever `CommandRegistry` runs it.
///
/// `AppCommand.run` is a plain escaping closure, so what it captures has to be
/// `Sendable`; a lock around one `Bool` is the whole of it.
private final class CommandMarker: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var wasPressed: Bool { lock.withLock { value } }
    func press() { lock.withLock { value = true } }
}

extension MainThreadTreeViewsTests {
    // MARK: - What a shrinking branch leaves behind

    /// A row that leaves the tree stops being a row, including its command.
    ///
    /// Handles come in two spaces — `#id` when the item declared one, and
    /// `parent/index` when it did not — and only the second was ever swept.
    /// `forgetDescendants(of:)` dropped every handle with the parent's path as
    /// a prefix, which a declared handle never has: `#apple` is not under
    /// `#fruit` by string and there was nothing else that said it was.
    ///
    /// So the entry outlived the row. Two things followed, and the second is
    /// the one a user meets: the tables grew by every row an extension had ever
    /// shown, and `activate` still found a command filed under a handle whose
    /// row was gone — a double-click on a row that happened to reuse the
    /// handle ran the vanished row's command.
    ///
    /// Pinned on the command, because that is the half with a consequence.
    @Test("a declared-id row that leaves the tree takes its command with it")
    func aDeclaredHandleIsForgottenWithItsBranch() async throws {
        let extensionDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: extensionDirectory) }

        let fixture = try makeFixture(
            source: """
                var vscode = require('vscode');
                globalThis.__kids = [{ key: 'apple', label: 'Apple' }];
                exports.activate = function () {
                    vscode.window.registerTreeDataProvider('acme.tree', {
                        getChildren: function (element) {
                            return element
                                ? globalThis.__kids
                                : [{ key: 'fruit', label: 'Fruit', isRoot: true }];
                        },
                        getTreeItem: function (element) {
                            var item = new vscode.TreeItem(
                                element.label,
                                element.isRoot
                                    ? vscode.TreeItemCollapsibleState.Collapsed
                                    : vscode.TreeItemCollapsibleState.None);
                            item.id = element.key;
                            if (!element.isRoot) {
                                item.command = { command: 'test.stale', title: 'Stale' };
                            }
                            return item;
                        }
                    });
                };
                """,
            extensionDirectory: extensionDirectory)
        try await fixture.host.activate()

        let marker = CommandMarker()
        _ = fixture.registry.register(
            AppCommand(id: "test.stale", title: "Stale") { marker.press() })

        let source = try dataSource(fixture.treeViews)
        let roots = await source.children(of: nil)
        let fruit = try #require(roots.first)
        let apple = try #require(await source.children(of: fruit).first)

        // The branch shrinks: the extension drops its only child and the pane
        // asks again, which is the whole of how a row leaves a tree.
        try #require(fixture.host.javaScriptContext)
            .evaluateScript("globalThis.__kids = [];")
        #expect(await source.children(of: fruit).isEmpty)

        source.activate(apple)
        #expect(!marker.wasPressed)
    }

    // MARK: - What a refresh keeps and what it drops

    /// **A refresh of one branch must not blind the branches below it.**
    ///
    /// `onDidChangeTreeData(element)` names one branch, and the pane reloads
    /// exactly that branch — every row it had already read further down stays
    /// on screen, because from the pane's side those branches are read. So a
    /// refresh that dropped every element beneath the named branch left those
    /// rows drawn with nothing behind them: no command, no children, and
    /// nothing that would ever ask again.
    @Test
    func refreshingABranchKeepsTheRowsBelowItAlive() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            globalThis.__ran = null;
            exports.activate = function () {
                vscode.commands.registerCommand('acme.open', function (which) {
                    globalThis.__ran = which;
                });
                vscode.window.registerTreeDataProvider('acme.tree', {
                    getChildren: function (element) {
                        if (!element) { return [{ id: 'branch', depth: 0 }]; }
                        if (element.depth === 0) { return [{ id: 'child', depth: 1 }]; }
                        if (element.depth === 1) { return [{ id: 'grandchild', depth: 2 }]; }
                        return [];
                    },
                    getTreeItem: function (element) {
                        var item = new vscode.TreeItem(
                            element.id,
                            element.depth < 2
                                ? vscode.TreeItemCollapsibleState.Collapsed
                                : vscode.TreeItemCollapsibleState.None);
                        item.id = element.id;
                        item.command = { command: 'acme.open', arguments: [element.id] };
                        return item;
                    }
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let source = try dataSource(fixture.treeViews)
        let branch = try #require(await source.children(of: nil).first)
        let child = try #require(await source.children(of: branch).first)
        let grandchild = try #require(await source.children(of: child).first)

        // The targeted refresh. `branch` answers the same child, so nothing
        // below it has gone anywhere.
        _ = await source.children(of: branch)

        source.activate(grandchild)
        let context = try #require(fixture.host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__ran")?.toString() == "grandchild")
        #expect(await source.children(of: grandchild).isEmpty)
    }

    /// The other half, and the reason the refresh drops anything at all: a
    /// branch that stops naming a row has said the row is gone, and a row that
    /// is gone must not still run its command.
    @Test
    func refreshingABranchForgetsTheRowsItStoppedNaming() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            globalThis.__ran = null;
            globalThis.__both = true;
            exports.activate = function () {
                vscode.commands.registerCommand('acme.open', function (which) {
                    globalThis.__ran = which;
                });
                vscode.window.registerTreeDataProvider('acme.tree', {
                    getChildren: function (element) {
                        if (element) { return []; }
                        return globalThis.__both
                            ? [{ id: 'a' }, { id: 'b' }]
                            : [{ id: 'a' }];
                    },
                    getTreeItem: function (element) {
                        var item = new vscode.TreeItem(element.id);
                        item.id = element.id;
                        item.command = { command: 'acme.open', arguments: [element.id] };
                        return item;
                    }
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let source = try dataSource(fixture.treeViews)
        let rows = await source.children(of: nil)
        let departing = try #require(rows.last)
        #expect(departing.id == "#b")

        let context = try #require(fixture.host.javaScriptContext)
        context.evaluateScript("globalThis.__both = false;")
        #expect(await source.children(of: nil).map(\.id) == ["#a"])

        source.activate(departing)
        #expect(context.evaluateScript("globalThis.__ran")?.isNull == true)
    }

    // MARK: - Two handle spaces, one namespace

    /// **A declared id must not be able to spell a positional handle.**
    ///
    /// Positional handles are built as `<parent>/<index>`, so a row declaring
    /// `id: 'src'` gives its first unnamed child the handle `#src/0` — which is
    /// exactly what a row declaring `id: 'src/0'` would have been given. Two
    /// rows on one handle is one row as far as every table keyed by it is
    /// concerned: the second one read wins the command, and activating the
    /// other runs it.
    @Test
    func aDeclaredIDCannotCollideWithAPositionalHandle() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeFixture(
            source: """
            var vscode = require('vscode');
            globalThis.__ran = null;
            exports.activate = function () {
                vscode.commands.registerCommand('acme.open', function (which) {
                    globalThis.__ran = which;
                });
                vscode.window.registerTreeDataProvider('acme.tree', {
                    getChildren: function (element) {
                        if (!element) {
                            return [
                                { id: 'src', label: 'src', branch: true },
                                { id: 'src/0', label: 'a file called src/0' }
                            ];
                        }
                        return element.branch ? [{ label: 'unnamed child' }] : [];
                    },
                    getTreeItem: function (element) {
                        var item = new vscode.TreeItem(
                            element.label,
                            element.branch
                                ? vscode.TreeItemCollapsibleState.Collapsed
                                : vscode.TreeItemCollapsibleState.None);
                        if (element.id) { item.id = element.id; }
                        item.command = { command: 'acme.open', arguments: [element.label] };
                        return item;
                    }
                });
            };
            """,
            extensionDirectory: directory)
        defer { fixture.host.dispose() }
        try await fixture.host.activate()

        let source = try dataSource(fixture.treeViews)
        let roots = await source.children(of: nil)
        #expect(roots.count == 2)
        let namedLikeAPath = try #require(roots.last)
        let unnamedChild = try #require(await source.children(of: roots[0]).first)

        #expect(namedLikeAPath.id != unnamedChild.id)

        // And the consequence of that, which is what a user would have seen:
        // the row read second took the other's command.
        source.activate(namedLikeAPath)
        let context = try #require(fixture.host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__ran")?.toString()
            == "a file called src/0")
    }
}
