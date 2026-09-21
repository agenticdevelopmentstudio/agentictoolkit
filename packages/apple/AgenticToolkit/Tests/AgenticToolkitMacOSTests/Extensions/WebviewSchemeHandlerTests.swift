import Foundation
import Testing
import WebKit
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The WebKit half of a webview panel's resource loading: what it answers,
/// what it refuses, and the one thing it must never do.
///
/// *Whether* a URL may be answered is `WebviewResourceURL`'s decision and is
/// tested without a browser. What is only testable here is everything around
/// that decision — the headers a response carries, the type a file is claimed
/// to be, and the bookkeeping that stops a task being answered after WebKit
/// has stopped it. That last one is not a tidiness rule: sending anything to a
/// stopped `WKURLSchemeTask` raises an Objective-C exception Swift cannot
/// catch, so the failure mode is the whole app going down while a user closes
/// a panel. It had no test.
@MainActor
struct WebviewSchemeHandlerTests {

    private let panelID = "panel-1"

    private func makeHandler(hostDocument: String = "<html></html>") -> WebviewSchemeHandler {
        let handler = WebviewSchemeHandler(panelID: panelID)
        handler.hostDocument = hostDocument
        return handler
    }

    /// The `WKWebView` every callback takes and none of them reads. Made once
    /// per test rather than shared, because a webview is a real object with a
    /// real process attached.
    private func makeWebView() -> WKWebView {
        WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SchemeHandler-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Waits for the task to be answered either way, or gives up.
    ///
    /// A file request is read off the main thread, so the answer arrives on a
    /// later turn. A test that read the recorder straight back would measure
    /// the dispatch rather than the response.
    private func settle(_ task: RecordingSchemeTask) async -> Bool {
        for _ in 0..<400 {
            if task.wasAnswered { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    // MARK: - The host document

    @Test("the panel's own document is served at the root of its origin")
    func theHostDocumentIsServedAtTheRoot() {
        let handler = makeHandler(hostDocument: "<h1>hello</h1>")
        let task = RecordingSchemeTask(WebviewResourceURL.hostDocumentURL(panelID: panelID))

        handler.webView(makeWebView(), start: task)

        #expect(task.failures.isEmpty)
        #expect(task.body == Data("<h1>hello</h1>".utf8))
        #expect(task.finished == 1)
        #expect(task.mimeType == "text/html; charset=utf-8")
    }

    /// The document is a property an extension reassigns whenever it likes, so
    /// what matters is that the handler serves its *current* value rather than
    /// whatever it held when the page first loaded.
    @Test("reassigning the document changes what the next request is served")
    func theDocumentServedIsTheCurrentOne() {
        let handler = makeHandler(hostDocument: "first")
        let url = WebviewResourceURL.hostDocumentURL(panelID: panelID)

        handler.webView(makeWebView(), start: RecordingSchemeTask(url))
        handler.hostDocument = "second"
        let second = RecordingSchemeTask(url)
        handler.webView(makeWebView(), start: second)

        #expect(second.body == Data("second".utf8))
    }

    // MARK: - What the response says about itself

    /// All four headers are load-bearing and none of them is visible in the
    /// page: `nosniff` is what makes naming the type from the extension mean
    /// anything, `no-store` is what stops an author's edited stylesheet being
    /// served stale, and the CSP is the panel's whole script policy.
    @Test("every response carries the type, the length, nosniff, no-store and the CSP")
    func theResponseCarriesTheHeadersThatMatter() throws {
        let handler = makeHandler(hostDocument: "<p>x</p>")
        handler.contentSecurityPolicy = "default-src 'none'"
        let task = RecordingSchemeTask(WebviewResourceURL.hostDocumentURL(panelID: panelID))

        handler.webView(makeWebView(), start: task)

        let headers = try #require(task.headers)
        #expect(headers["Content-Type"] == "text/html; charset=utf-8")
        #expect(headers["Content-Length"] == "8")
        #expect(headers["X-Content-Type-Options"] == "nosniff")
        #expect(headers["Cache-Control"] == "no-store")
        #expect(headers["Content-Security-Policy"] == "default-src 'none'")
    }

    @Test("a handler with no panel yet serves the closed content security policy")
    func theDefaultPolicyIsTheClosedOne() {
        let handler = WebviewSchemeHandler(panelID: panelID)

        #expect(handler.contentSecurityPolicy
            == WebviewPanelOptions.contentSecurityPolicy(allowingForms: false))
    }

    // MARK: - Refusals

    /// The origin boundary. Two panels are two WebKit origins precisely because
    /// the panel id is the URL's authority, and a handler that answered another
    /// panel's id would make that boundary a convention.
    @Test("a request naming another panel is refused and answered with nothing")
    func aRequestForAnotherPanelIsRefused() {
        let handler = makeHandler()
        let task = RecordingSchemeTask(
            WebviewResourceURL.hostDocumentURL(panelID: "panel-2"))

        handler.webView(makeWebView(), start: task)

        #expect(task.failures.count == 1)
        #expect(task.responses.isEmpty)
        #expect(task.finished == 0)
    }

    @Test("a request in some other scheme is refused")
    func aRequestInAnotherSchemeIsRefused() throws {
        let handler = makeHandler()
        let task = RecordingSchemeTask(try #require(URL(string: "https://example.com/x.css")))

        handler.webView(makeWebView(), start: task)

        #expect(task.failures.count == 1)
        #expect(task.responses.isEmpty)
    }

    /// The default posture: an extension that declared no roots has asked for
    /// no file access, so a request for a file that plainly exists is refused.
    @Test("with no declared roots a file that exists is still refused")
    func noRootsMeansNoFiles() async throws {
        let handler = makeHandler()
        let directory = try makeDirectory("noroots")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("style.css")
        try Data("body {}".utf8).write(to: file)
        let task = RecordingSchemeTask(
            WebviewResourceURL.url(forFile: file, panelID: panelID))

        handler.webView(makeWebView(), start: task)

        #expect(await settle(task))
        #expect(task.failures.count == 1)
        #expect(task.responses.isEmpty)
    }

    /// The roots are read at the moment of the request rather than captured
    /// when the page loaded, so an extension that gives a root up gives it up
    /// for everything that has not been asked for yet.
    @Test("narrowing the roots refuses what was being served a moment ago")
    func narrowingTheRootsTakesEffectImmediately() async throws {
        let handler = makeHandler()
        let directory = try makeDirectory("narrowing")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("style.css")
        try Data("body {}".utf8).write(to: file)
        handler.localResourceRoots = [directory]
        let url = WebviewResourceURL.url(forFile: file, panelID: panelID)

        let served = RecordingSchemeTask(url)
        handler.webView(makeWebView(), start: served)
        #expect(await settle(served))
        #expect(served.finished == 1)

        handler.localResourceRoots = []
        let refused = RecordingSchemeTask(url)
        handler.webView(makeWebView(), start: refused)

        #expect(await settle(refused))
        #expect(refused.failures.count == 1)
        #expect(refused.responses.isEmpty)
    }

    /// A file that is inside a declared root but is not there any more. The
    /// read happens off the main thread and comes back empty, and the task has
    /// to be failed rather than left hanging — an unanswered scheme task is a
    /// resource the page waits on forever.
    @Test("a file inside a root that does not exist is failed, not left hanging")
    func aMissingFileIsFailed() async throws {
        let handler = makeHandler()
        let directory = try makeDirectory("missing")
        defer { try? FileManager.default.removeItem(at: directory) }
        handler.localResourceRoots = [directory]
        let task = RecordingSchemeTask(WebviewResourceURL.url(
            forFile: directory.appendingPathComponent("gone.css"), panelID: panelID))

        handler.webView(makeWebView(), start: task)

        #expect(await settle(task))
        #expect(task.failures.count == 1)
        #expect(task.responses.isEmpty)
    }

    // MARK: - Files

    @Test("a file inside a declared root is served with its bytes")
    func aFileInsideARootIsServed() async throws {
        let handler = makeHandler()
        let directory = try makeDirectory("served")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("style.css")
        try Data("body { color: red }".utf8).write(to: file)
        handler.localResourceRoots = [directory]
        let task = RecordingSchemeTask(
            WebviewResourceURL.url(forFile: file, panelID: panelID))

        handler.webView(makeWebView(), start: task)

        #expect(await settle(task))
        #expect(task.failures.isEmpty)
        #expect(task.body == Data("body { color: red }".utf8))
        #expect(task.finished == 1)
    }

    /// Named from the file's extension and never sniffed from its bytes, which
    /// is the point of `nosniff`: a file whose contents are markup is served as
    /// the type its name claims, and a type this cannot name at all is served
    /// as something WebKit will not execute.
    @Test("the type is taken from the file's name, not from what is in it")
    func theTypeComesFromTheName() async throws {
        let handler = makeHandler()
        let directory = try makeDirectory("types")
        defer { try? FileManager.default.removeItem(at: directory) }
        handler.localResourceRoots = [directory]

        let stylesheet = directory.appendingPathComponent("looks-like-html.css")
        try Data("<script>alert(1)</script>".utf8).write(to: stylesheet)
        let mystery = directory.appendingPathComponent("payload.notatype")
        try Data("<script>alert(1)</script>".utf8).write(to: mystery)

        let css = RecordingSchemeTask(
            WebviewResourceURL.url(forFile: stylesheet, panelID: panelID))
        handler.webView(makeWebView(), start: css)
        let unknown = RecordingSchemeTask(
            WebviewResourceURL.url(forFile: mystery, panelID: panelID))
        handler.webView(makeWebView(), start: unknown)

        #expect(await settle(css))
        #expect(await settle(unknown))
        #expect(css.mimeType == "text/css; charset=utf-8")
        #expect(unknown.mimeType == "application/octet-stream")
    }

    // MARK: - A task WebKit has stopped

    /// The invariant the whole `liveTasks` set exists for, and the one this
    /// class can actually crash on. The panel is closed — WebKit stops the
    /// task — while the file is still being read on another thread; when the
    /// read lands, nothing at all may be sent.
    ///
    /// The ordering is deterministic rather than lucky: `start` schedules the
    /// read on a `Task`, and this test is already on the main actor, so the
    /// read cannot begin until this function suspends. `stop` therefore always
    /// arrives first, which is exactly the race being reproduced.
    @Test("a task stopped while its file is being read is never answered")
    func aStoppedTaskIsNotAnswered() async throws {
        let handler = makeHandler()
        let directory = try makeDirectory("stopped")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("style.css")
        try Data("body {}".utf8).write(to: file)
        handler.localResourceRoots = [directory]
        let webView = makeWebView()
        let task = RecordingSchemeTask(
            WebviewResourceURL.url(forFile: file, panelID: panelID))

        handler.webView(webView, start: task)
        handler.webView(webView, stop: task)
        try await Task.sleep(for: .milliseconds(200))

        #expect(!task.wasAnswered)
        #expect(task.responses.isEmpty)
        #expect(task.body.isEmpty)
        #expect(task.finished == 0)
        #expect(task.failures.isEmpty)
    }

    /// The same rule on the other branch. Failing a stopped task raises the
    /// same exception as finishing one, so a missing file must not be reported
    /// to a task nobody is listening to either.
    @Test("a task stopped before its missing file is reported is not failed")
    func aStoppedTaskIsNotFailedEither() async throws {
        let handler = makeHandler()
        let directory = try makeDirectory("stopped-missing")
        defer { try? FileManager.default.removeItem(at: directory) }
        handler.localResourceRoots = [directory]
        let webView = makeWebView()
        let task = RecordingSchemeTask(WebviewResourceURL.url(
            forFile: directory.appendingPathComponent("gone.css"), panelID: panelID))

        handler.webView(webView, start: task)
        handler.webView(webView, stop: task)
        try await Task.sleep(for: .milliseconds(200))

        #expect(!task.wasAnswered)
    }

    /// The bookkeeping is per task and not a flag on the handler: one panel
    /// serves a page's whole set of resources at once, and a single stylesheet
    /// being cancelled must not silence the rest of them.
    @Test("stopping one task leaves the others being served")
    func stoppingOneTaskDoesNotStopTheOthers() async throws {
        let handler = makeHandler()
        let directory = try makeDirectory("several")
        defer { try? FileManager.default.removeItem(at: directory) }
        handler.localResourceRoots = [directory]
        let webView = makeWebView()
        var tasks: [RecordingSchemeTask] = []
        for index in 0..<3 {
            let file = directory.appendingPathComponent("file\(index).css")
            try Data("body { --n: \(index) }".utf8).write(to: file)
            tasks.append(RecordingSchemeTask(
                WebviewResourceURL.url(forFile: file, panelID: panelID)))
        }

        for task in tasks { handler.webView(webView, start: task) }
        handler.webView(webView, stop: tasks[1])

        #expect(await settle(tasks[0]))
        #expect(await settle(tasks[2]))
        #expect(tasks[0].body == Data("body { --n: 0 }".utf8))
        #expect(tasks[2].body == Data("body { --n: 2 }".utf8))
        #expect(!tasks[1].wasAnswered)
    }

    /// WebKit stops tasks this handler never started — a page torn down mid
    /// navigation reaches every handler the configuration holds. Removing
    /// something that is not in the set is the whole of the right behaviour,
    /// and it must not disturb a task that *is*.
    @Test("stopping a task this handler never started changes nothing")
    func stoppingAnUnknownTaskIsHarmless() async throws {
        let handler = makeHandler()
        let directory = try makeDirectory("unknown")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("style.css")
        try Data("body {}".utf8).write(to: file)
        handler.localResourceRoots = [directory]
        let webView = makeWebView()
        let live = RecordingSchemeTask(
            WebviewResourceURL.url(forFile: file, panelID: panelID))
        let stranger = RecordingSchemeTask(
            WebviewResourceURL.hostDocumentURL(panelID: panelID))

        handler.webView(webView, start: live)
        handler.webView(webView, stop: stranger)

        #expect(await settle(live))
        #expect(live.finished == 1)
        #expect(!stranger.wasAnswered)
    }
}

/// A `WKURLSchemeTask` that records instead of rendering.
///
/// Recording rather than asserting inline is what makes "nothing was sent"
/// expressible at all: the production rule is about calls that must *not*
/// happen, and only a double that counts every call can say so.
///
/// Not a `@MainActor` class, because `WKURLSchemeTask` is not a main-actor
/// protocol — WebKit makes no promise about which thread answers a task, and a
/// double that demanded one would be asserting a guarantee the API does not
/// make. The recording therefore sits behind a lock.
private final class RecordingSchemeTask: NSObject, WKURLSchemeTask, @unchecked Sendable {

    let request: URLRequest

    private struct Record {
        var responses: [URLResponse] = []
        var body = Data()
        var finished = 0
        var failures: [any Error] = []
    }

    private let lock = NSLock()
    private var record = Record()

    init(_ url: URL) {
        self.request = URLRequest(url: url)
        super.init()
    }

    var responses: [URLResponse] { read { $0.responses } }
    var body: Data { read { $0.body } }
    var finished: Int { read { $0.finished } }
    var failures: [any Error] { read { $0.failures } }

    /// Whether anything at all reached this task — the question the
    /// stopped-task tests ask.
    var wasAnswered: Bool { read { $0.finished > 0 || !$0.failures.isEmpty } }

    var headers: [String: String]? {
        (responses.first as? HTTPURLResponse)?.allHeaderFields as? [String: String]
    }

    var mimeType: String? { headers?["Content-Type"] }

    func didReceive(_ response: URLResponse) { write { $0.responses.append(response) } }
    func didReceive(_ data: Data) { write { $0.body.append(data) } }
    func didFinish() { write { $0.finished += 1 } }
    func didFailWithError(_ error: any Error) { write { $0.failures.append(error) } }

    private func read<Answer>(_ question: (Record) -> Answer) -> Answer {
        lock.lock()
        defer { lock.unlock() }
        return question(record)
    }

    private func write(_ change: (inout Record) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        change(&record)
    }
}
