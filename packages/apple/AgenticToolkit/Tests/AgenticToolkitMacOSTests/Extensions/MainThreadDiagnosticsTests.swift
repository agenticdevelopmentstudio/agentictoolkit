import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A double for `ExtensionDiagnosticSink`, standing in for `HostDiagnosticSink`
/// in the tests that are about *which* mutations notify and with which Uris.
///
/// 5.6a-iii's version of this doc said no real consumer existed yet and named
/// 5.6b's `onDidChangeDiagnostics` as the one that would; 5.6b has landed, and
/// the tests under "The `onDidChangeDiagnostics` wiring" below use the real
/// `HostDiagnosticSink` rather than this double for exactly that reason. This
/// double stays for the tests above them, which assert notification *counts*
/// and *payloads* directly: reading those back out of a debounced event would
/// put the emitter's window between the assertion and the thing asserted, and
/// a window bug would then redden eighteen tests about something else. The
/// reasoning `MainThreadWindowStatusBarTests` records for its own
/// `RecordingStatusBarPresenter`/`UnusedMessagePresenter`.
@MainActor
private final class RecordingDiagnosticSink: ExtensionDiagnosticSink {
    private(set) var calls: [[URL]] = []

    func diagnosticsChanged(for uris: [URL]) {
        calls.append(uris)
    }
}

/// `vscode.languages.createDiagnosticCollection` and `getDiagnostics` (task
/// 5.6a-iii, ledger Ruling 23's third slice), plus — as of task 5.6b —
/// `onDidChangeDiagnostics` end to end through the real
/// `HostDiagnosticSink`.
///
/// The emitter's *own* behaviour (the window, listener registration,
/// disposal, a throwing listener) is `ExtensionEventTests`'; what this suite
/// adds is the wiring: that each mutation reaches the emitter, and that the
/// diagnostics-specific mapper produces the `DiagnosticChangeEvent` of
/// `vscode.d.ts:7013-7018`.
///
/// Wired onto a real `ExtensionHost` and a real `ExtensionDiagnosticStore`,
/// never doubles for either side, on `MainThreadLanguagesTests`'s own
/// reasoning: the point of this suite is the boundary between JavaScript and
/// Swift, and a double for either side would only ever agree with itself.
/// `ExtensionDiagnosticSink` is the one seam doubled, because no real
/// conformer is consumed by anything yet (see `RecordingDiagnosticSink`).
///
/// Each `@Test`'s doc names exactly one (or, where the brief's own numbering
/// bundles several observations into a single mutation, exactly that
/// mutation's several assertions) numbered mutation, and names no mutation an
/// earlier test in this file already kills.
///
/// **Two numberings meet in this file.** The `// MARK: - Mutation N` headings
/// down to 16 are task 5.6a-iii's; the ones under "The
/// `onDidChangeDiagnostics` wiring" are task 5.6b's own 1-13 list and are
/// labelled `5.6b mutation N` to keep them apart. Renumbering either would
/// break the brief each is answerable to.
@MainActor
@Suite
struct MainThreadDiagnosticsTests {

    // MARK: - Fixtures

    private func makeTempDirectory() throws -> URL {
        try ExtensionFixtures.makeTemporaryDirectory("MainThreadDiagnosticsTests")
    }

    private func manifest(name: String, browser: String) throws -> ExtensionManifest {
        let json = """
        {
            "name": "\(name)",
            "publisher": "test",
            "version": "1.0.0",
            "engines": { "vscode": "^1.74.0" },
            "browser": "\(browser)"
        }
        """
        return try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
    }

    /// Writes `source` as the extension's `browser` entry point and returns a
    /// host over the result.
    private func makeHost(
        name: String = "alpha",
        source: String,
        entryPath: String = "dist/web.js",
        in directory: URL,
        ledger: NotImplementedLedger = NotImplementedLedger()
    ) throws -> ExtensionHost {
        try ExtensionFixtures.write(source, to: entryPath, in: directory)
        let loaded = LoadedExtension(
            manifest: try manifest(name: name, browser: entryPath),
            directory: directory
        )
        return ExtensionHost(loadedExtension: loaded, notImplementedLedger: ledger)
    }

    /// Installs `createDiagnosticCollection`, `getDiagnostics` and
    /// `onDidChangeDiagnostics` onto `host`'s `vscode.languages` namespace —
    /// the two members task 5.6a-iii added and the one task 5.6b added.
    ///
    /// All three for every test, including the eighteen that never subscribe:
    /// defining a member an extension does not call costs nothing, and a
    /// second install helper that differed only by a line would be the shape
    /// where a test silently exercises the wrong namespace.
    private func install(_ diagnostics: MainThreadDiagnostics, on host: ExtensionHost) throws {
        try host.defineVSCodeMember(
            namespacePath: "vscode.languages", name: "createDiagnosticCollection",
            implementation: diagnostics.createDiagnosticCollection)
        try host.defineVSCodeMember(
            namespacePath: "vscode.languages", name: "getDiagnostics",
            implementation: diagnostics.getDiagnostics)
        try host.defineVSCodeMember(
            namespacePath: "vscode.languages", name: "onDidChangeDiagnostics",
            implementation: diagnostics.onDidChangeDiagnostics)
    }

    /// A `MainThreadDiagnostics` over a real emitter whose window never closes
    /// on its own.
    ///
    /// `MainThreadDiagnostics.init` takes `events:` with no default, on
    /// purpose — a default is how a seam quietly stops being one — so every
    /// construction in this suite has to spell the third argument. There are
    /// exactly two, and no test constructs one itself: this helper, and
    /// `makeEventWiring` below. They are not interchangeable. This one builds
    /// a throwaway emitter for the tests that never subscribe;
    /// `makeEventWiring` builds the one *shared* emitter the event tests
    /// need, because a sink and an adaptor holding two emitters compile and
    /// then simply never hear each other. The emitter here is still genuinely
    /// live: the tests it serves have no subscribers, so every event they
    /// cause is dropped at `ExtensionEventEmitter.fire`'s zero-listener
    /// guard, and the window double means nothing they leave queued can fire
    /// later into another test.
    private func makeAdaptor(
        store: ExtensionDiagnosticStore,
        sink: ExtensionDiagnosticSink
    ) -> MainThreadDiagnostics {
        MainThreadDiagnostics(
            store: store,
            sink: sink,
            events: MainThreadDiagnostics.makeOnDidChangeDiagnosticsEmitter(
                window: ManualExtensionEventWindow()))
    }

    /// The whole `onDidChangeDiagnostics` wiring, assembled the way a host
    /// assembles it: **one** emitter, shared by the sink that fires it and the
    /// adaptor that publishes it.
    ///
    /// Sharing is the point, and it is what a test would otherwise get wrong
    /// invisibly — two emitters compile, and the listener simply never hears
    /// anything.
    private struct EventWiring {
        let window: ManualExtensionEventWindow
        let sink: HostDiagnosticSink
        let diagnostics: MainThreadDiagnostics
    }

    private func makeEventWiring(store: ExtensionDiagnosticStore) -> EventWiring {
        let window = ManualExtensionEventWindow()
        let events = MainThreadDiagnostics.makeOnDidChangeDiagnosticsEmitter(window: window)
        let sink = HostDiagnosticSink(emitter: events)
        return EventWiring(
            window: window,
            sink: sink,
            diagnostics: MainThreadDiagnostics(store: store, sink: sink, events: events))
    }

    /// The listener every wiring test installs: it records each event's
    /// `uris`, as an array of path strings, onto `globalThis.__events`.
    ///
    /// `.path` rather than `.toString()` because `Uri.file('/a.txt')`'s
    /// string form carries the `file://` scheme, and a test reading paths is
    /// clearer about what it is comparing.
    private static let recordUrisListenerSource = """
    globalThis.__events = [];
    vscode.languages.onDidChangeDiagnostics(function (event) {
        globalThis.__events.push(event.uris.map(function (u) { return u.path; }));
    });
    """

    /// `globalThis.__events` read back as one string per event, paths joined
    /// by `,`. A plain `String` comparison keeps the assertions readable and
    /// keeps every array boundary visible.
    private func recordedEvents(in host: ExtensionHost) throws -> [String] {
        let context = try #require(host.javaScriptContext)
        let value = context.evaluateScript(
            "globalThis.__events.map(function (e) { return e.join(','); }).join('|')")
        let unwrapped = try #require(value)
        let joined = try #require(unwrapped.toString())
        return joined.isEmpty ? [] : joined.components(separatedBy: "|")
    }

    // MARK: - Mutation 1

    /// A colliding name keeps `.name` and makes a distinct collection: two
    /// `createDiagnosticCollection("eslint")` calls both answer
    /// `.name === "eslint"`, and `set` on the first is not visible through the
    /// second (`extHostDiagnostics.ts:280-291`).
    @Test
    func collidingNameKeepsNameAndMakesADistinctCollection() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let sink = RecordingDiagnosticSink()
        let diagnostics = makeAdaptor(store: store, sink: sink)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var a = vscode.languages.createDiagnosticCollection('eslint');
                var b = vscode.languages.createDiagnosticCollection('eslint');
                globalThis.__aName = a.name;
                globalThis.__bName = b.name;
                a.set(vscode.Uri.file('/x.txt'),
                    [new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'm')]);
                globalThis.__bHasX = b.has(vscode.Uri.file('/x.txt'));
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(diagnostics, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__aName")?.toString() == "eslint")
        #expect(context.evaluateScript("globalThis.__bName")?.toString() == "eslint")
        // Asserts the global is actually a boolean, not merely falsy, so a
        // fixture that threw before this assignment (leaving `__bHasX`
        // `undefined`, itself falsy) cannot pass by accident (ledger fix
        // round 1, O6).
        #expect(context.evaluateScript("globalThis.__bHasX")?.isBoolean == true)
        #expect(context.evaluateScript("globalThis.__bHasX")?.toBool() == false)
    }

    // MARK: - Mutation 2

    /// A generated name when `name` is omitted matches
    /// `_generated_diagnostic_collection_name_#N`, and two omitted-name calls
    /// produce different names.
    @Test
    func omittedNameGeneratesADistinctNamePerCall() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let sink = RecordingDiagnosticSink()
        let diagnostics = makeAdaptor(store: store, sink: sink)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var a = vscode.languages.createDiagnosticCollection();
                var b = vscode.languages.createDiagnosticCollection();
                globalThis.__aName = a.name;
                globalThis.__bName = b.name;
                globalThis.__aMatches =
                    /^_generated_diagnostic_collection_name_#\\d+$/.test(a.name);
                globalThis.__bMatches =
                    /^_generated_diagnostic_collection_name_#\\d+$/.test(b.name);
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(diagnostics, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__aMatches")?.toBool() == true)
        #expect(context.evaluateScript("globalThis.__bMatches")?.toBool() == true)
        let aName = context.evaluateScript("globalThis.__aName")?.toString()
        let bName = context.evaluateScript("globalThis.__bName")?.toString()
        #expect(aName != bName)
    }

    // MARK: - Mutation 3

    /// `set(uri, undefined)` removes — `has` false, `get` undefined —
    /// distinguished from storing `[]`, which leaves `has` true and `get` an
    /// empty array.
    @Test
    func setUndefinedRemovesDistinctFromStoringEmptyArray() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let sink = RecordingDiagnosticSink()
        let diagnostics = makeAdaptor(store: store, sink: sink)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var c = vscode.languages.createDiagnosticCollection('c3');
                var uri = vscode.Uri.file('/a.txt');
                c.set(uri, []);
                globalThis.__hasEmpty = c.has(uri);
                globalThis.__getEmptyLength = c.get(uri).length;

                c.set(uri, [new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'm')]);
                c.set(uri, undefined);
                globalThis.__hasAfterUndefined = c.has(uri);
                globalThis.__getAfterUndefined = c.get(uri);
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(diagnostics, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__hasEmpty")?.toBool() == true)
        #expect(context.evaluateScript("globalThis.__getEmptyLength")?.toInt32() == 0)
        #expect(context.evaluateScript("globalThis.__hasAfterUndefined")?.toBool() == false)
        #expect(context.evaluateScript("globalThis.__getAfterUndefined")?.isUndefined == true)
    }

    // MARK: - Mutation 4

    /// `get` on an absent Uri is `undefined`, not `[]` — asserts the value
    /// itself, not its truthiness.
    @Test
    func getOnAbsentUriIsUndefinedNotEmptyArray() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let sink = RecordingDiagnosticSink()
        let diagnostics = makeAdaptor(store: store, sink: sink)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var c = vscode.languages.createDiagnosticCollection('c4');
                var absent = vscode.Uri.file('/nope.txt');
                globalThis.__isUndefined = c.get(absent) === undefined;
                globalThis.__isArray = Array.isArray(c.get(absent));
                globalThis.__hasAbsent = c.has(absent);
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(diagnostics, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__isUndefined")?.toBool() == true)
        #expect(context.evaluateScript("globalThis.__isArray")?.toBool() == false)
        // Same reasoning as `collidingNameKeepsNameAndMakesADistinctCollection`'s
        // own `__bHasX` fix: assert the global is a boolean before trusting
        // its value is `false` (ledger fix round 1, O6).
        #expect(context.evaluateScript("globalThis.__hasAbsent")?.isBoolean == true)
        #expect(context.evaluateScript("globalThis.__hasAbsent")?.toBool() == false)
    }

    // MARK: - Mutation 5

    /// The array-taking `set` overload behaves per `vscode.d.ts:7189-7198`:
    /// "multiple tuples of the same uri will be merged, e.g
    /// `[[file1, [d1]], [file1, [d2]]]` is equivalent to `[[file1, [d1,
    /// d2]]]`. If a diagnostics item is `undefined` as in `[file1,
    /// undefined]` all previous but not subsequent diagnostics are removed."
    @Test
    func arraySetOverloadMergesRepeatedUrisPerVscodeDts7189to7198() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let sink = RecordingDiagnosticSink()
        let diagnostics = makeAdaptor(store: store, sink: sink)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var c = vscode.languages.createDiagnosticCollection('c5');
                var file1 = vscode.Uri.file('/file1.txt');
                var d1 = new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'd1');
                var d2 = new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'd2');
                c.set([[file1, [d1]], [file1, [d2]]]);
                var merged = c.get(file1);
                globalThis.__mergedLength = merged.length;
                globalThis.__mergedMessages = merged.map(function (d) { return d.message; });

                var file2 = vscode.Uri.file('/file2.txt');
                var d3 = new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'd3');
                var d4 = new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'd4');
                c.set([[file2, [d3]], [file2, undefined], [file2, [d4]]]);
                var afterUndefined = c.get(file2);
                globalThis.__afterUndefinedMessages =
                    afterUndefined.map(function (d) { return d.message; });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(diagnostics, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__mergedLength")?.toInt32() == 2)
        let mergedMessages = try #require(
            context.evaluateScript("globalThis.__mergedMessages.join(',')")?.toString())
        #expect(mergedMessages == "d1,d2")
        let afterUndefinedMessages = try #require(
            context.evaluateScript("globalThis.__afterUndefinedMessages.join(',')")?.toString())
        #expect(afterUndefinedMessages == "d4")
    }

    // MARK: - Mutation 6

    /// `delete` and `clear` are two separate mutations: `delete` removes only
    /// the named Uri, leaving the rest; `clear` removes everything. A
    /// `clear`-implemented-as-`delete`-everything would still pass a
    /// `delete`-only assertion, so both are checked on a collection with two
    /// distinct Uris.
    @Test
    func deleteAndClearAreDistinctMutations() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let sink = RecordingDiagnosticSink()
        let diagnostics = makeAdaptor(store: store, sink: sink)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var c = vscode.languages.createDiagnosticCollection('c6');
                var uri1 = vscode.Uri.file('/one.txt');
                var uri2 = vscode.Uri.file('/two.txt');
                var d = new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'm');
                c.set(uri1, [d]);
                c.set(uri2, [d]);

                c.delete(uri1);
                globalThis.__hasUri1AfterDelete = c.has(uri1);
                globalThis.__hasUri2AfterDelete = c.has(uri2);

                c.clear();
                globalThis.__hasUri2AfterClear = c.has(uri2);
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(diagnostics, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__hasUri1AfterDelete")?.toBool() == false)
        #expect(context.evaluateScript("globalThis.__hasUri2AfterDelete")?.toBool() == true)
        #expect(context.evaluateScript("globalThis.__hasUri2AfterClear")?.toBool() == false)
    }

    // MARK: - Mutation 7

    /// `forEach` visits every Uri exactly once, hands the callback the
    /// collection itself as the third argument, and honours `thisArg` — three
    /// separate assertions, so an implementation that ignores `thisArg` turns
    /// exactly the third one red.
    @Test
    func forEachVisitsEveryUriOnceWithCollectionAndHonoursThisArg() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let sink = RecordingDiagnosticSink()
        let diagnostics = makeAdaptor(store: store, sink: sink)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var c = vscode.languages.createDiagnosticCollection('c7');
                var uri1 = vscode.Uri.file('/one.txt');
                var uri2 = vscode.Uri.file('/two.txt');
                var d = new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'm');
                c.set(uri1, [d]);
                c.set(uri2, [d]);

                var visited = [];
                var thisArgObject = { marker: 'expected' };
                var sawCollection = true;
                var sawThisArg = true;
                c.forEach(function (uri, ds, collection) {
                    visited.push(uri.toString());
                    if (collection !== c) { sawCollection = false; }
                    if (this !== thisArgObject) { sawThisArg = false; }
                }, thisArgObject);

                globalThis.__visitedCount = visited.length;
                globalThis.__visitedUnique = new Set(visited).size;
                globalThis.__sawCollection = sawCollection;
                globalThis.__sawThisArg = sawThisArg;
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(diagnostics, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__visitedCount")?.toInt32() == 2)
        #expect(context.evaluateScript("globalThis.__visitedUnique")?.toInt32() == 2)
        #expect(context.evaluateScript("globalThis.__sawCollection")?.toBool() == true)
        #expect(context.evaluateScript("globalThis.__sawThisArg")?.toBool() == true)
    }

    // MARK: - Mutation 8

    /// `Symbol.iterator` yields the same `[uri, diagnostics]` pairs as
    /// `forEach`, in the same order (ledger Ruling 25, `vscode.d.ts:7171`'s
    /// `extends Iterable<[uri,diagnostics]>`) — asserts no exception is
    /// thrown by iterating AND that the pairs themselves match.
    @Test
    func symbolIteratorYieldsSamePairsAsForEachInTheSameOrder() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let sink = RecordingDiagnosticSink()
        let diagnostics = makeAdaptor(store: store, sink: sink)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var c = vscode.languages.createDiagnosticCollection('c8');
                var uri1 = vscode.Uri.file('/one.txt');
                var uri2 = vscode.Uri.file('/two.txt');
                var uri3 = vscode.Uri.file('/three.txt');
                var d = new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'm');
                c.set(uri1, [d]);
                c.set(uri2, [d]);
                c.set(uri3, [d]);

                var fromForEach = [];
                c.forEach(function (uri) { fromForEach.push(uri.toString()); });

                var fromIterator = [];
                var threw = false;
                try {
                    for (var pair of c) {
                        fromIterator.push(pair[0].toString());
                    }
                } catch (e) {
                    threw = true;
                }

                globalThis.__threw = threw;
                globalThis.__matches =
                    JSON.stringify(fromForEach) === JSON.stringify(fromIterator);
                globalThis.__count = fromIterator.length;
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(diagnostics, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__threw")?.toBool() == false)
        #expect(context.evaluateScript("globalThis.__count")?.toInt32() == 3)
        #expect(context.evaluateScript("globalThis.__matches")?.toBool() == true)
    }

    // MARK: - Mutation 9

    /// `dispose()` frees the name: a new `createDiagnosticCollection("eslint")`
    /// after disposing the first is not treated as a collision. `b.name`
    /// and `b.has(uri)` alone do not kill this mutation — skipping
    /// `store.removeCollection(owner:)` in `handleCollectionDispose` still
    /// leaves both green, because `createCollection`'s own collision
    /// branch mints a distinct `"eslint0"` owner regardless and `b` is a
    /// live collection under it. `store.containsOwner("eslint0")` is the
    /// assertion that can see the owner the mutation actually changes
    /// (ledger fix round 1, B2).
    @Test
    func disposeFreesTheNameForReuse() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let sink = RecordingDiagnosticSink()
        let diagnostics = makeAdaptor(store: store, sink: sink)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var a = vscode.languages.createDiagnosticCollection('eslint');
                a.dispose();
                var b = vscode.languages.createDiagnosticCollection('eslint');
                globalThis.__bName = b.name;
                b.set(vscode.Uri.file('/x.txt'),
                    [new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'm')]);
                globalThis.__bHasX = b.has(vscode.Uri.file('/x.txt'));
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(diagnostics, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__bName")?.toString() == "eslint")
        #expect(context.evaluateScript("globalThis.__bHasX")?.toBool() == true)
        #expect(store.containsOwner("eslint0") == false)
    }

    // MARK: - Regression: disposed collection stays inert after name reuse
    // (ledger fix round 1, B3)

    /// A disposed collection's `set`/`clear`/`get` must stay inert even
    /// after its freed name is reused by a later `createDiagnosticCollection`
    /// — the case a captured `owner` string would otherwise still reach,
    /// corrupting the new collection registered under the same key. Not
    /// one of the 16 numbered mutations; a regression test for a bug this
    /// same task introduced (a `disposed` flag that guarded only
    /// `dispose()` itself, not the other method blocks).
    @Test
    func disposedCollectionStaysInertAfterItsNameIsReused() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let sink = RecordingDiagnosticSink()
        let diagnostics = makeAdaptor(store: store, sink: sink)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var a = vscode.languages.createDiagnosticCollection('regress');
                var uriX = vscode.Uri.file('/x.txt');
                var uriY = vscode.Uri.file('/y.txt');
                var original = new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'm');
                a.set(uriX, [original]);
                a.dispose();

                var b = vscode.languages.createDiagnosticCollection('regress');
                b.set(uriY, [original]);

                // Stale calls on the disposed `a`, which still captures the
                // "regress" owner `b` now also occupies. Under the bug this
                // regression test catches, these would corrupt `b`.
                var corrupt = new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'corrupt');
                a.set(uriY, [corrupt]);
                a.clear();

                globalThis.__aGetAfterDisposeIsUndefined = a.get(uriY) === undefined;
                globalThis.__bHasY = b.has(uriY);
                var bGetY = b.get(uriY);
                globalThis.__bGetYLength = bGetY ? bGetY.length : -1;
                globalThis.__bGetYMessage = bGetY ? bGetY[0].message : null;
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(diagnostics, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__aGetAfterDisposeIsUndefined")?.toBool() == true)
        #expect(context.evaluateScript("globalThis.__bHasY")?.toBool() == true)
        #expect(context.evaluateScript("globalThis.__bGetYLength")?.toInt32() == 1)
        #expect(context.evaluateScript("globalThis.__bGetYMessage")?.toString() == "m")

        // Only `a.set(uriX, ...)`, `a.dispose()`, and `b.set(uriY, ...)`
        // notify — the disposed `a`'s stale `set`/`clear` on the reused
        // owner notify no one.
        let uriX = URL(string: "file:///x.txt")!
        let uriY = URL(string: "file:///y.txt")!
        #expect(sink.calls.count == 3)
        #expect(sink.calls[0] == [uriX])
        #expect(sink.calls[1] == [uriX])
        #expect(sink.calls[2] == [uriY])
    }

    // MARK: - Mutation 10

    /// `dispose()` removes this collection's own diagnostics from
    /// `getDiagnostics()`, but leaves another collection's diagnostics
    /// alone — proved through both overloads. The resource overload
    /// (`getDiagnostics(uri)`) alone proves the same thing mutation 11
    /// already covers, so this also asserts through the no-argument
    /// overload: the disposed collection's Uri is absent from
    /// `getDiagnostics()` and the live one's is present (ledger fix
    /// round 1, O5).
    @Test
    func disposeRemovesOnlyThisCollectionsDiagnosticsFromGetDiagnostics() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let sink = RecordingDiagnosticSink()
        let diagnostics = makeAdaptor(store: store, sink: sink)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var a = vscode.languages.createDiagnosticCollection('a10');
                var b = vscode.languages.createDiagnosticCollection('b10');
                var uriA = vscode.Uri.file('/a.txt');
                var uriB = vscode.Uri.file('/b.txt');
                var d = new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'm');
                a.set(uriA, [d]);
                b.set(uriB, [d]);

                a.dispose();
                globalThis.__aGone = vscode.languages.getDiagnostics(uriA).length === 0;
                globalThis.__bStill = vscode.languages.getDiagnostics(uriB).length === 1;

                var all = vscode.languages.getDiagnostics();
                globalThis.__aAbsentFromAll = !all.some(function (p) {
                    return p[0].toString() === uriA.toString();
                });
                globalThis.__bPresentInAll = all.some(function (p) {
                    return p[0].toString() === uriB.toString();
                });
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(diagnostics, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__aGone")?.toBool() == true)
        #expect(context.evaluateScript("globalThis.__bStill")?.toBool() == true)
        #expect(context.evaluateScript("globalThis.__aAbsentFromAll")?.toBool() == true)
        #expect(context.evaluateScript("globalThis.__bPresentInAll")?.toBool() == true)
    }

    // MARK: - Mutation 11

    /// `getDiagnostics(resource)` merges across collections: the same Uri
    /// present in two collections returns both collections' diagnostics.
    @Test
    func getDiagnosticsForResourceMergesAcrossCollections() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let sink = RecordingDiagnosticSink()
        let diagnostics = makeAdaptor(store: store, sink: sink)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var a = vscode.languages.createDiagnosticCollection('a11');
                var b = vscode.languages.createDiagnosticCollection('b11');
                var uri = vscode.Uri.file('/shared.txt');
                a.set(uri, [new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'from-a')]);
                b.set(uri, [new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'from-b')]);

                var merged = vscode.languages.getDiagnostics(uri);
                globalThis.__mergedLength = merged.length;
                globalThis.__mergedMessages =
                    merged.map(function (d) { return d.message; }).sort().join(',');
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(diagnostics, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__mergedLength")?.toInt32() == 2)
        #expect(context.evaluateScript("globalThis.__mergedMessages")?.toString() == "from-a,from-b")
    }

    // MARK: - Mutation 12

    /// `getDiagnostics()` with no argument returns every Uri across every
    /// collection paired with its merged diagnostics — the overloads are
    /// dispatched on argument count, a separate mutation from either
    /// overload's own content (mutations 4/11 cover those).
    @Test
    func getDiagnosticsWithNoArgumentReturnsEveryUriMergedAcrossCollections() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let sink = RecordingDiagnosticSink()
        let diagnostics = makeAdaptor(store: store, sink: sink)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var a = vscode.languages.createDiagnosticCollection('a12');
                var b = vscode.languages.createDiagnosticCollection('b12');
                var shared = vscode.Uri.file('/shared.txt');
                var onlyA = vscode.Uri.file('/only-a.txt');
                a.set(shared, [new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'from-a')]);
                b.set(shared, [new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'from-b')]);
                a.set(onlyA, [new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'only-a')]);

                var all = vscode.languages.getDiagnostics();
                globalThis.__pairCount = all.length;
                var sharedPair = all.filter(function (p) {
                    return p[0].toString() === shared.toString();
                })[0];
                globalThis.__sharedMergedCount = sharedPair[1].length;
                var onlyAPair = all.filter(function (p) {
                    return p[0].toString() === onlyA.toString();
                })[0];
                globalThis.__onlyAMergedCount = onlyAPair[1].length;
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(diagnostics, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__pairCount")?.toInt32() == 2)
        #expect(context.evaluateScript("globalThis.__sharedMergedCount")?.toInt32() == 2)
        #expect(context.evaluateScript("globalThis.__onlyAMergedCount")?.toInt32() == 1)
    }

    // MARK: - Regression: getDiagnostics(null) (ledger fix round 1, O4)

    /// `getDiagnostics(null)` returns the same result as the no-argument
    /// call, not a raised exception — `null` is falsy under
    /// `extHostDiagnostics.ts:317`'s `if (resource)` dispatch, exactly as
    /// an omitted argument is. Not one of the 16 numbered mutations.
    @Test
    func getDiagnosticsWithExplicitNullMatchesTheNoArgumentResult() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let sink = RecordingDiagnosticSink()
        let diagnostics = makeAdaptor(store: store, sink: sink)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var c = vscode.languages.createDiagnosticCollection('cNull');
                var uri = vscode.Uri.file('/x.txt');
                c.set(uri, [new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'm')]);

                var threw = false;
                var result;
                try {
                    result = vscode.languages.getDiagnostics(null);
                } catch (e) {
                    threw = true;
                }
                globalThis.__threw = threw;
                globalThis.__matchesNoArgument = Array.isArray(result) &&
                    JSON.stringify(result) ===
                        JSON.stringify(vscode.languages.getDiagnostics());
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(diagnostics, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__threw")?.toBool() == false)
        #expect(context.evaluateScript("globalThis.__matchesNoArgument")?.toBool() == true)
    }

    // MARK: - Mutation 13

    /// The sink is notified on every mutating call, with the right Uris,
    /// across the five *kinds* of mutating operation — `set` (both
    /// overloads), `delete`, `clear`, `dispose`. The fixture below makes
    /// seven calls, not five: a fixture that clears before disposing needs
    /// a `set` after the clear for `dispose()` to have anything to notify
    /// about, and that `set` is itself a sixth mutating call, not setup
    /// (ledger fix round 1, B1 — a five-notification fixture that still
    /// exercises `dispose()`'s own notification is not constructible).
    /// Seven assertions against the same `RecordingDiagnosticSink`, read
    /// directly rather than round-tripped through JS.
    @Test
    func sinkIsNotifiedOnEveryMutatingCallWithTheRightUris() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let sink = RecordingDiagnosticSink()
        let diagnostics = makeAdaptor(store: store, sink: sink)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var c = vscode.languages.createDiagnosticCollection('c13');
                var uri1 = vscode.Uri.file('/one.txt');
                var uri2 = vscode.Uri.file('/two.txt');
                var d = new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'm');

                c.set(uri1, [d]);        // (1) single-uri set — [uri1]
                c.set([[uri2, [d]]]);    // (2) array-taking set — [uri2]
                c.delete(uri1);          // (3) delete — [uri1]
                c.set(uri2, [d]);        // (4) single-uri set — [uri2]
                c.clear();               // (5) clear — [uri2]
                c.set(uri1, [d]);        // (6) single-uri set — [uri1]
                c.dispose();             // (7) dispose — [uri1]
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(diagnostics, on: host)
        try await host.activate()

        #expect(sink.calls.count == 7)
        let uri1 = URL(string: "file:///one.txt")!
        let uri2 = URL(string: "file:///two.txt")!
        #expect(sink.calls[0] == [uri1])
        #expect(sink.calls[1] == [uri2])
        #expect(sink.calls[2] == [uri1])
        #expect(sink.calls[3] == [uri2])
        #expect(sink.calls[4] == [uri2])
        #expect(sink.calls[5] == [uri1])
        #expect(sink.calls[6] == [uri1])
    }

    // MARK: - Mutation 14

    /// The sink is NOT notified on a read — `get`, `has`, `forEach`, or
    /// iteration.
    @Test
    func sinkIsNotNotifiedOnAnyReadOperation() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let sink = RecordingDiagnosticSink()
        let diagnostics = makeAdaptor(store: store, sink: sink)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var c = vscode.languages.createDiagnosticCollection('c14');
                var uri = vscode.Uri.file('/one.txt');
                c.set(uri, [new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'm')]);
                globalThis.__setCallCount = 1; // marker so the fixture reaches this point

                c.get(uri);
                c.has(uri);
                c.forEach(function () {});
                for (var pair of c) { /* no-op */ }
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(diagnostics, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__setCallCount")?.toInt32() == 1)
        // Exactly the one notification from `set` above — none from the four
        // reads that followed it.
        #expect(sink.calls.count == 1)
    }

    // MARK: - Mutation 15

    /// `collection.name` is not writable: assigning to it leaves it
    /// unchanged, JavaScript's own silent-no-op behaviour for a property
    /// descriptor with no setter (`MainThreadWindow.installReadonlyGetter`'s
    /// own doc, now promoted for exactly this reuse).
    @Test
    func collectionNameIsNotWritable() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let sink = RecordingDiagnosticSink()
        let diagnostics = makeAdaptor(store: store, sink: sink)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var c = vscode.languages.createDiagnosticCollection('original');
                c.name = 'tampered';
                globalThis.__nameAfterAssignment = c.name;
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(diagnostics, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__nameAfterAssignment")?.toString() == "original")
    }

    // MARK: - Mutation 16

    /// The adaptor's own `dispose()` tears down only the collections it
    /// itself created — a shared `ExtensionDiagnosticStore` between two
    /// separate `MainThreadDiagnostics` instances, disposing only the first,
    /// checked directly against the store rather than through JS (there is
    /// no JS-visible way to name "the other adaptor's" collection object once
    /// this test needs to inspect the store's own bookkeeping after the
    /// fact).
    @Test
    func adaptorDisposeTearsDownOnlyItsOwnCollections() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let sinkA = RecordingDiagnosticSink()
        let sinkB = RecordingDiagnosticSink()
        let diagnosticsA = makeAdaptor(store: store, sink: sinkA)
        let diagnosticsB = makeAdaptor(store: store, sink: sinkB)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var a = vscode.languages.createA('team-a');
                var b = vscode.languages.createB('team-b');
                a.set(vscode.Uri.file('/a.txt'),
                    [new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'm')]);
                b.set(vscode.Uri.file('/b.txt'),
                    [new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'm')]);
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try host.defineVSCodeMember(
            namespacePath: "vscode.languages", name: "createA",
            implementation: diagnosticsA.createDiagnosticCollection)
        try host.defineVSCodeMember(
            namespacePath: "vscode.languages", name: "createB",
            implementation: diagnosticsB.createDiagnosticCollection)
        try await host.activate()

        #expect(store.containsOwner("team-a") == true)
        #expect(store.containsOwner("team-b") == true)

        diagnosticsA.dispose()

        #expect(store.containsOwner("team-a") == false)
        #expect(store.containsOwner("team-b") == true)
    }

    // MARK: - The `onDidChangeDiagnostics` wiring (task 5.6b)

    // Everything below here answers task 5.6b's own 1-13 mutation list, not
    // the 1-16 list the headings above use — see this suite's doc. Every one
    // of these runs the real `HostDiagnosticSink` and a real
    // `ExtensionEventEmitter`, with only the window doubled.
    //
    // **File order is load-bearing here, and it is not numerical.** 5.6b's
    // mutation 6 (a, b, a yields `[a, b]`) asserts, among other things, that
    // two mutations in one window arrive as one event carrying both Uris,
    // which is mutation 13 — so 13's test has to come first or it claims a
    // kill an earlier test already made.

    // MARK: 5.6b mutation 12

    /// **Each of 5.6a-iii's five mutating operations produces an event**,
    /// carrying the Uris that operation affected: `set(uri, diagnostics)`,
    /// `set(entries)`, `delete`, `clear`, and a collection's own `dispose`.
    ///
    /// Five separate windows, closed one at a time, so a wiring that reports
    /// only `set` turns four of the five entries red rather than one — the
    /// brief's own statement of this mutation.
    ///
    /// Not `sinkIsNotifiedOnEveryMutatingCallWithTheRightUris` again. That
    /// test reads a `RecordingDiagnosticSink` directly and stops at the
    /// `ExtensionDiagnosticSink` seam; this one runs the real
    /// `HostDiagnosticSink` and reads what arrives in *JavaScript*, so it is
    /// the half of the path that test cannot see — sink to emitter to
    /// listener. Delete `emitter.fire(uris)` from `HostDiagnosticSink` and
    /// that test still passes while this one goes empty.
    ///
    /// The two `set` calls in `activate` are seeding, and they run *before*
    /// the listener is installed so the zero-listener guard drops them: the
    /// assertion that no event has arrived before the first step is what
    /// keeps them out of the five. `clear` and `dispose` need something to
    /// clear and dispose of, which is what the seeding is for, and `dispose`
    /// is given its own collection because `clear` would otherwise have just
    /// emptied the one it was to report.
    @Test
    func eachOfTheFiveMutatingOperationsProducesAnEvent() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let wiring = makeEventWiring(store: store)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var d = [new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'm')];
                var c = vscode.languages.createDiagnosticCollection('c');
                var doomed = vscode.languages.createDiagnosticCollection('doomed');
                c.set(vscode.Uri.file('/one.txt'), d);
                doomed.set(vscode.Uri.file('/five.txt'), d);

                \(MainThreadDiagnosticsTests.recordUrisListenerSource)

                globalThis.__step1 = function () { c.set(vscode.Uri.file('/one.txt'), d); };
                globalThis.__step2 = function () { c.set([[vscode.Uri.file('/two.txt'), d]]); };
                globalThis.__step3 = function () { c.delete(vscode.Uri.file('/one.txt')); };
                globalThis.__step4 = function () { c.clear(); };
                globalThis.__step5 = function () { doomed.dispose(); };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(wiring.diagnostics, on: host)
        try await host.activate()

        // Drains the window the seeding opened. Nothing was queued into it —
        // no listener existed yet — so this is the precondition for the five
        // below being five, not a claim of its own.
        wiring.window.closeOpenWindows()
        let beforeSteps = try recordedEvents(in: host)
        #expect(beforeSteps.isEmpty)

        let context = try #require(host.javaScriptContext)
        for step in 1...5 {
            context.evaluateScript("globalThis.__step\(step)();")
            wiring.window.closeOpenWindows()
        }

        let events = try recordedEvents(in: host)
        #expect(events == ["/one.txt", "/two.txt", "/one.txt", "/two.txt", "/five.txt"])
    }

    // MARK: 5.6b mutation 13

    /// **Two mutations in one window arrive as one event carrying both
    /// Uris** — the end-to-end statement, through the real adaptor, of the
    /// fixed window (`event.ts:1606`) and the flattening mapper
    /// (`extHostDiagnostics.ts:242-248`).
    ///
    /// Mutation 12 above closes a window between every step, so it says
    /// nothing about coalescing; this leaves the window open across both.
    /// One event, two Uris: an implementation that delivers per-mutation
    /// gives two events, and one that delivers only the first or last
    /// mutation gives one Uri.
    @Test
    func twoMutationsInOneWindowArriveAsOneEventCarryingBothUris() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let wiring = makeEventWiring(store: store)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                \(MainThreadDiagnosticsTests.recordUrisListenerSource)
                var d = [new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'm')];
                var c = vscode.languages.createDiagnosticCollection('c');
                c.set(vscode.Uri.file('/a.txt'), d);
                c.delete(vscode.Uri.file('/b.txt'));
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(wiring.diagnostics, on: host)
        try await host.activate()

        wiring.window.closeOpenWindows()

        let events = try recordedEvents(in: host)
        #expect(events == ["/a.txt,/b.txt"])
    }

    // MARK: 5.6b mutation 5

    /// **Flatten before dedup, and dedup by Uri identity.** Two distinct
    /// `Uri` objects naming the same path, fired in two different mutations
    /// inside one window, arrive as **one** entry
    /// (`extHostDiagnostics.ts:242-248`'s `ResourceMap`, which keys on
    /// `uri.toString()` rather than object identity).
    ///
    /// Mutation 13 above has two different paths and so cannot see a missing
    /// dedup at all; this is the test a no-dedup implementation turns red,
    /// with two entries where there should be one.
    ///
    /// `__distinctObjects` is the assertion that keeps the claim from being
    /// vacuous: if `vscode.Uri.file` ever interned its results, the two
    /// values would be one object and the dedup would never be exercised,
    /// yet the entry count would still read 1.
    @Test
    func twoDistinctUriObjectsForOnePathArriveAsOneEntry() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let wiring = makeEventWiring(store: store)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                \(MainThreadDiagnosticsTests.recordUrisListenerSource)
                var d = [new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'm')];
                var c = vscode.languages.createDiagnosticCollection('c');
                var first = vscode.Uri.file('/same.txt');
                var second = vscode.Uri.file('/same.txt');
                globalThis.__distinctObjects = first !== second;
                c.set(first, d);
                c.set(second, d);
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(wiring.diagnostics, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let distinct = try #require(context.evaluateScript("globalThis.__distinctObjects"))
        #expect(distinct.isBoolean)
        #expect(distinct.toBool() == true)

        wiring.window.closeOpenWindows()

        let events = try recordedEvents(in: host)
        #expect(events == ["/same.txt"])
    }

    // MARK: 5.6b mutation 6

    /// **First-insertion order is preserved** across the merged window: a,
    /// b, a yields `[a, b]`, never `[b, a]`.
    ///
    /// This is the one an implementation that dedups by *last* insertion
    /// turns red, and neither test above can see it — mutation 13's two Uris
    /// each appear once, and mutation 5's repeat is of the only Uri there
    /// is. `ResourceMap` is insertion-ordered and `set` on an existing key
    /// does not move it, so the third mutation must leave the order alone.
    @Test
    func firstInsertionOrderIsPreservedAcrossTheMergedWindow() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let wiring = makeEventWiring(store: store)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                \(MainThreadDiagnosticsTests.recordUrisListenerSource)
                var d = [new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'm')];
                var c = vscode.languages.createDiagnosticCollection('c');
                c.set(vscode.Uri.file('/a.txt'), d);
                c.set(vscode.Uri.file('/b.txt'), d);
                c.set(vscode.Uri.file('/a.txt'), d);
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(wiring.diagnostics, on: host)
        try await host.activate()

        wiring.window.closeOpenWindows()

        let events = try recordedEvents(in: host)
        #expect(events == ["/a.txt,/b.txt"])
    }

    // MARK: 5.6b mutation 7

    /// **The delivered `uris` array is frozen.** `_mapper` ends in
    /// `Object.freeze` (`extHostDiagnostics.ts:242-248`), which is also what
    /// `vscode.d.ts:7018`'s `readonly uris: readonly Uri[]` promises at a
    /// type level and cannot enforce at runtime.
    ///
    /// Both of the two ways extension code could reach in: `push`, and an
    /// indexed assignment. Each is wrapped in its own `try`/`catch` and each
    /// records whether it threw — not to assert *which* (the two differ by
    /// strict mode, which is not this host's to decide), but so that an
    /// exception cannot abandon the listener before it records, which would
    /// leave the array looking untouched for the wrong reason. The
    /// `'not-attempted'` sentinels are what prove both were reached.
    ///
    /// The second window is the "does not corrupt the next event" half: a
    /// mapper that reused and mutated one array across events would deliver
    /// `/pushed.txt` or `/assigned.txt` the second time round.
    @Test
    func theDeliveredUrisArrayIsFrozenAndTamperingDoesNotAffectTheNextEvent() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExtensionDiagnosticStore()
        let wiring = makeEventWiring(store: store)
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__events = [];
                globalThis.__frozen = null;
                globalThis.__pushOutcome = 'not-attempted';
                globalThis.__assignOutcome = 'not-attempted';
                vscode.languages.onDidChangeDiagnostics(function (event) {
                    globalThis.__frozen = Object.isFrozen(event.uris);
                    try {
                        event.uris.push(vscode.Uri.file('/pushed.txt'));
                        globalThis.__pushOutcome = 'returned';
                    } catch (e) {
                        globalThis.__pushOutcome = 'threw';
                    }
                    try {
                        event.uris[0] = vscode.Uri.file('/assigned.txt');
                        globalThis.__assignOutcome = 'returned';
                    } catch (e) {
                        globalThis.__assignOutcome = 'threw';
                    }
                    globalThis.__events.push(
                        event.uris.map(function (u) { return u.path; }));
                });
                var d = [new vscode.Diagnostic(new vscode.Range(0, 0, 0, 1), 'm')];
                var c = vscode.languages.createDiagnosticCollection('c');
                c.set(vscode.Uri.file('/first.txt'), d);
                globalThis.__again = function () { c.set(vscode.Uri.file('/second.txt'), d); };
            };
            """,
            in: directory
        )
        defer { host.dispose() }
        try install(wiring.diagnostics, on: host)
        try await host.activate()

        wiring.window.closeOpenWindows()

        let context = try #require(host.javaScriptContext)
        let frozen = try #require(context.evaluateScript("globalThis.__frozen"))
        #expect(frozen.isBoolean)
        #expect(frozen.toBool() == true)
        #expect(context.evaluateScript("globalThis.__pushOutcome")?.toString() != "not-attempted")
        #expect(context.evaluateScript("globalThis.__assignOutcome")?.toString() != "not-attempted")

        context.evaluateScript("globalThis.__again();")
        wiring.window.closeOpenWindows()

        let events = try recordedEvents(in: host)
        #expect(events == ["/first.txt", "/second.txt"])
    }
}
