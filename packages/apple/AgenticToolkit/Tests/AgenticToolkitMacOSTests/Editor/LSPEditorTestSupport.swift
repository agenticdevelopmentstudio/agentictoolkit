//
//  LSPEditorTestSupport.swift
//  AgenticToolkit
//

import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import AgenticToolkitCore
@testable import AgenticToolkitCoreMacOS
@testable import AgenticToolkitLanguage
@testable import AgenticToolkitMacOS

// MARK: - The log

/// Every call the fake sessions received, in order, across all instances.
///
/// A lock rather than an actor: an ordering assertion has to be able to read
/// this without introducing a suspension of its own, and the writer is an actor
/// on some other executor.
final class EditorSessionLog: @unchecked Sendable {

    private let lock = NSLock()
    private var storage: [String] = []

    func record(_ event: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(event)
    }

    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

// MARK: - The fake session

/// What a `FakeEditorLanguageServerSession` answers with once it is running.
struct FakeEditorSessionBehavior: Sendable {

    /// What `capabilities()` returns **while running**. `nil` models a server
    /// that has not finished its handshake; every consumer has to treat that as
    /// "no feature", which is one of the paths under test.
    var capabilities: ServerCapabilities?
    var completionResponse: CompletionResponse
    var definitionResponse: DefinitionResponse
    var hoverResponse: HoverResponse
    var semanticTokensResponse: SemanticTokensResponse
    var completionError: LanguageServerSessionError?
    var definitionError: LanguageServerSessionError?
    var hoverError: LanguageServerSessionError?
    var semanticTokensError: LanguageServerSessionError?

    init(
        capabilities: ServerCapabilities? = nil,
        completionResponse: CompletionResponse = nil,
        definitionResponse: DefinitionResponse = nil,
        hoverResponse: HoverResponse = nil,
        semanticTokensResponse: SemanticTokensResponse = nil,
        completionError: LanguageServerSessionError? = nil,
        definitionError: LanguageServerSessionError? = nil,
        hoverError: LanguageServerSessionError? = nil,
        semanticTokensError: LanguageServerSessionError? = nil
    ) {
        self.capabilities = capabilities
        self.completionResponse = completionResponse
        self.definitionResponse = definitionResponse
        self.hoverResponse = hoverResponse
        self.semanticTokensResponse = semanticTokensResponse
        self.completionError = completionError
        self.definitionError = definitionError
        self.hoverError = hoverError
        self.semanticTokensError = semanticTokensError
    }
}

/// The smallest `LanguageServerSessionProtocol` the macOS editor tests need.
///
/// `AgenticToolkitLanguageTests.FakeLanguageServerSession` is internal to that
/// bundle and cannot be reached from here; this is the purpose-built stand-in
/// rather than a widening of that one.
///
/// **It models the lifecycle, not just the answers.** `capabilities()` is `nil`
/// unless the session is `.running`, every request throws `.notRunning` before
/// `start()` and after `stop()`, and `start()` is idempotent on a running
/// session and terminal on a stopped one — the same shape as the real
/// `LanguageServerSession`. A fake that answered from `.idle` would make the
/// delegates' capability gating untestable.
actor FakeEditorLanguageServerSession: LanguageServerSessionProtocol {

    nonisolated let id: UUID
    nonisolated let name: String
    nonisolated let languageIds: [String]

    private(set) var state: LanguageServerSessionState = .idle

    /// The last request each delegate made, so a test can assert what was sent
    /// rather than only what came back.
    private(set) var lastCompletionParams: CompletionParams?
    private(set) var lastDefinitionParams: TextDocumentPositionParams?
    private(set) var lastHoverParams: TextDocumentPositionParams?
    private(set) var lastSemanticTokensParams: SemanticTokensParams?

    /// The push-diagnostics half of the protocol. The test plays the server;
    /// `publish(_:)` is the wire.
    nonisolated let publishedDiagnostics: AsyncStream<PublishDiagnosticsParams>
    private nonisolated let diagnosticsContinuation: AsyncStream<PublishDiagnosticsParams>.Continuation

    private let behavior: FakeEditorSessionBehavior
    private let log: EditorSessionLog

    /// Answers for the next completion calls, one per call, in call order.
    /// Falls back to `behavior.completionResponse` once exhausted — which is
    /// what every test that only makes one request relies on.
    private var queuedCompletionResponses: [CompletionResponse] = []

    /// How many further `completion(_:)` calls park before answering, and the
    /// continuations of the ones currently parked.
    ///
    /// This is what makes two *overlapping* requests expressible. Without it a
    /// test can only ever run one request to completion before starting the
    /// next, which is precisely the interleaving that cannot go wrong.
    private var gatedCompletionsRemaining = 0
    private var heldCompletions: [CheckedContinuation<Void, Never>] = []

    /// The same two, for `capabilities()`. Trigger-character resolution never
    /// reaches `completion(_:)`, so the completion gate above cannot express
    /// two overlapping *resolutions* — which is the interleaving the
    /// trigger-cache generation exists to survive.
    private var queuedCapabilities: [ServerCapabilities?] = []
    private var gatedCapabilitiesRemaining = 0
    private var heldCapabilities: [CheckedContinuation<Void, Never>] = []

    /// And the same again for `hover(_:)`.
    private var gatedHoversRemaining = 0
    private var heldHovers: [CheckedContinuation<Void, Never>] = []

    /// And once more for `semanticTokensFull(_:)`. The queue is what makes a
    /// *superseded* fetch expressible: the provider's ordering guard is only
    /// observable when two fetches carry different token data, and a single
    /// fixed answer makes "the older one landed last" indistinguishable from
    /// "the newer one did".
    private var queuedSemanticTokensResponses: [SemanticTokensResponse] = []
    private var gatedSemanticTokensRemaining = 0
    private var heldSemanticTokens: [CheckedContinuation<Void, Never>] = []

    init(
        configuration: LanguageServerConfiguration,
        behavior: FakeEditorSessionBehavior,
        log: EditorSessionLog
    ) {
        let (stream, continuation) = AsyncStream.makeStream(of: PublishDiagnosticsParams.self)
        self.publishedDiagnostics = stream
        self.diagnosticsContinuation = continuation
        self.id = configuration.id
        self.name = configuration.name
        self.languageIds = configuration.languageIds
        self.behavior = behavior
        self.log = log
    }

    /// Pushes one `publishDiagnostics` notification, as a server would.
    /// `nonisolated` because the continuation is — see the sibling fake in
    /// `AgenticToolkitLanguageTests`.
    nonisolated func publish(_ params: PublishDiagnosticsParams) {
        diagnosticsContinuation.yield(params)
    }

    func start() async throws {
        switch state {
        case .idle:
            break
        case .starting, .running:
            // This fake's start has no suspension point, so `.starting` is
            // never observable; a second caller only ever meets a settled
            // outcome, which is where awaiting the real session's `startTask`
            // also lands.
            return
        case .failed(let failure):
            throw failure.error
        case .stopped:
            throw LanguageServerSessionError.sessionHasBeenStopped
        }
        log.record("start")
        state = .running
    }

    func stop() async {
        state = .stopped
        log.record("stop")
        diagnosticsContinuation.finish()
    }

    /// Answers the next capability calls with these, in order, before falling
    /// back to `behavior.capabilities`.
    ///
    /// A real server does not change its capabilities mid-session; this exists
    /// so a test can tell *which* of two overlapping resolutions wrote the
    /// cache, which is not observable when both read the same answer.
    func enqueueCapabilities(_ capabilities: [ServerCapabilities?]) {
        queuedCapabilities = capabilities
    }

    /// Parks the next `count` capability calls until `releaseHeldCapabilities()`.
    func holdNextCapabilities(_ count: Int) {
        gatedCapabilitiesRemaining = count
    }

    /// How many capability calls are parked right now.
    var heldCapabilityCount: Int { heldCapabilities.count }

    func releaseHeldCapabilities() {
        let held = heldCapabilities
        heldCapabilities = []
        for continuation in held {
            continuation.resume()
        }
    }

    func capabilities() async -> ServerCapabilities? {
        guard case .running = state else { return nil }
        // Chosen before parking, so the answer belongs to this call rather than
        // to whichever call happens to resume first.
        let answer = queuedCapabilities.isEmpty ? behavior.capabilities : queuedCapabilities.removeFirst()
        if gatedCapabilitiesRemaining > 0 {
            gatedCapabilitiesRemaining -= 1
            await withCheckedContinuation { continuation in
                heldCapabilities.append(continuation)
            }
        }
        return answer
    }

    func standardErrorText() async -> String { "" }

    /// The gate every traffic method goes through, as the real session does:
    /// nothing reaches a server that is not running.
    private func requireRunning() throws {
        guard case .running = state else { throw LanguageServerSessionError.notRunning }
    }

    func didOpen(_ params: DidOpenTextDocumentParams) async throws {
        try requireRunning()
        log.record("didOpen(\(params.textDocument.uri))")
    }

    func didChange(_ params: DidChangeTextDocumentParams) async throws {
        try requireRunning()
        log.record("didChange(\(params.textDocument.uri))")
    }

    func didSave(_ params: DidSaveTextDocumentParams) async throws {
        try requireRunning()
        log.record("didSave(\(params.textDocument.uri))")
    }

    func didClose(_ params: DidCloseTextDocumentParams) async throws {
        try requireRunning()
        log.record("didClose(\(params.textDocument.uri))")
    }

    /// Answers the next `count` completion calls with these, in order.
    func enqueueCompletionResponses(_ responses: [CompletionResponse]) {
        queuedCompletionResponses = responses
    }

    /// Parks the next `count` completion calls until `releaseHeldCompletions()`.
    func holdNextCompletions(_ count: Int) {
        gatedCompletionsRemaining = count
    }

    /// How many completion calls are parked right now.
    var heldCompletionCount: Int { heldCompletions.count }

    func releaseHeldCompletions() {
        let held = heldCompletions
        heldCompletions = []
        for continuation in held {
            continuation.resume()
        }
    }

    func completion(_ params: CompletionParams) async throws -> CompletionResponse {
        try requireRunning()
        log.record("completion")
        lastCompletionParams = params
        // The answer is chosen *before* parking, so it belongs to this call
        // rather than to whichever call happens to resume first.
        let response = queuedCompletionResponses.isEmpty
            ? behavior.completionResponse
            : queuedCompletionResponses.removeFirst()
        if gatedCompletionsRemaining > 0 {
            gatedCompletionsRemaining -= 1
            await withCheckedContinuation { continuation in
                heldCompletions.append(continuation)
            }
        }
        if let error = behavior.completionError { throw error }
        return response
    }

    /// Parks the next `count` hover calls until `releaseHeldHovers()`.
    ///
    /// The same gate as the completion one above, and for the same reason: the
    /// hover controller's generation guard is only observable while a request
    /// is still in flight, and a fake that answered immediately would never
    /// leave that window open.
    func holdNextHovers(_ count: Int) {
        gatedHoversRemaining = count
    }

    /// How many hover calls are parked right now.
    var heldHoverCount: Int { heldHovers.count }

    func releaseHeldHovers() {
        let held = heldHovers
        heldHovers = []
        for continuation in held {
            continuation.resume()
        }
    }

    func hover(_ params: TextDocumentPositionParams) async throws -> HoverResponse {
        try requireRunning()
        log.record("hover")
        lastHoverParams = params
        if gatedHoversRemaining > 0 {
            gatedHoversRemaining -= 1
            await withCheckedContinuation { continuation in
                heldHovers.append(continuation)
            }
        }
        if let error = behavior.hoverError { throw error }
        return behavior.hoverResponse
    }

    func definition(_ params: TextDocumentPositionParams) async throws -> DefinitionResponse {
        try requireRunning()
        log.record("definition")
        lastDefinitionParams = params
        if let error = behavior.definitionError { throw error }
        return behavior.definitionResponse
    }

    func diagnostics(_ params: DocumentDiagnosticParams) async throws -> DocumentDiagnosticReport {
        try requireRunning()
        return DocumentDiagnosticReport(kind: .full, items: [])
    }

    /// Answers the next semantic-token calls with these, in order, before
    /// falling back to `behavior.semanticTokensResponse`.
    func enqueueSemanticTokensResponses(_ responses: [SemanticTokensResponse]) {
        queuedSemanticTokensResponses = responses
    }

    /// Parks the next `count` semantic-token calls until
    /// `releaseHeldSemanticTokens()`.
    func holdNextSemanticTokens(_ count: Int) {
        gatedSemanticTokensRemaining = count
    }

    /// How many semantic-token calls are parked right now.
    var heldSemanticTokensCount: Int { heldSemanticTokens.count }

    func releaseHeldSemanticTokens() {
        let held = heldSemanticTokens
        heldSemanticTokens = []
        for continuation in held {
            continuation.resume()
        }
    }

    func semanticTokensFull(_ params: SemanticTokensParams) async throws -> SemanticTokensResponse {
        try requireRunning()
        // Recorded on the log rather than a counter of its own, because the
        // assertion that matters most is a *negative* one — that a server which
        // does not advertise the capability is never asked — and the log can be
        // read without a suspension that would give a pending request time to
        // arrive.
        log.record("semanticTokensFull(\(params.textDocument.uri))")
        lastSemanticTokensParams = params
        // Chosen before parking, so the answer belongs to this call rather than
        // to whichever call happens to resume first.
        let response = queuedSemanticTokensResponses.isEmpty
            ? behavior.semanticTokensResponse
            : queuedSemanticTokensResponses.removeFirst()
        if gatedSemanticTokensRemaining > 0 {
            gatedSemanticTokensRemaining -= 1
            await withCheckedContinuation { continuation in
                heldSemanticTokens.append(continuation)
            }
        }
        if let error = behavior.semanticTokensError { throw error }
        return response
    }
}

// MARK: - Capability fixtures

/// A server that advertises completion, with the trigger characters given.
func makeCompletingCapabilities(triggerCharacters: [String] = ["."]) -> ServerCapabilities {
    var capabilities = ServerCapabilities()
    capabilities.completionProvider = CompletionOptions(
        workDoneProgress: false,
        triggerCharacters: triggerCharacters,
        allCommitCharacters: nil,
        resolveProvider: false,
        completionItem: nil
    )
    return capabilities
}

/// A server that advertises go-to-definition.
///
/// `provides: false` is the deliberate other case — a bare `false` is a
/// declaration that the server does *not* provide definitions, which is not the
/// same as omitting the key.
func makeDefiningCapabilities(provides: Bool = true) -> ServerCapabilities {
    var capabilities = ServerCapabilities()
    capabilities.definitionProvider = .optionA(provides)
    return capabilities
}

/// A server that advertises hover.
///
/// `provides: false` is the deliberate other case, exactly as for definitions:
/// a bare `false` says the server does *not* answer hovers, which is not the
/// same as omitting the key.
func makeHoveringCapabilities(provides: Bool = true) -> ServerCapabilities {
    var capabilities = ServerCapabilities()
    capabilities.hoverProvider = .optionA(provides)
    return capabilities
}

/// A server that advertises `textDocument/semanticTokens/full`, with the legend
/// given.
///
/// The legend is a parameter and not a default the way trigger characters are,
/// because it is the whole translation table: a token's `type` field is an index
/// into `tokenTypes`, so a test that does not choose the legend is not choosing
/// what its own token data means.
///
/// - Parameter full: `false` is the deliberate other case — a bare `false` is a
///   declaration that full-document requests are *not* served, which is not the
///   same as omitting the key, and is the one shape that advertises the
///   capability while refusing the only request this editor makes.
func makeSemanticTokenCapabilities(
    legend: SemanticTokensLegend,
    full: Bool = true
) -> ServerCapabilities {
    var capabilities = ServerCapabilities()
    capabilities.semanticTokensProvider = .optionA(SemanticTokensOptions(
        legend: legend,
        full: .optionA(full)
    ))
    return capabilities
}

/// A server that opens, changes and closes documents — what the document sync
/// needs before it will forward anything.
func makeSyncingCapabilities() -> ServerCapabilities {
    var capabilities = ServerCapabilities()
    capabilities.textDocumentSync = .optionA(TextDocumentSyncOptions(
        openClose: true,
        change: .incremental,
        save: nil
    ))
    return capabilities
}

// MARK: - Registry fixture

/// A registry whose one server claims `swift` and is backed by a fake.
@MainActor
struct LSPEditorFixture {

    let settings: SettingsStore
    let registry: LanguageServerRegistry
    let log: EditorSessionLog
    let configuration: LanguageServerConfiguration

    /// - Parameter registersConfiguration: `false` leaves the registry empty,
    ///   which is how "no server serves this language" is expressed — the
    ///   registry has no other way to have no session.
    init(
        workspaceURL: URL = URL(fileURLWithPath: "/", isDirectory: true),
        languageIds: [String] = ["swift"],
        behavior: FakeEditorSessionBehavior = FakeEditorSessionBehavior(),
        registersConfiguration: Bool = true
    ) {
        let log = EditorSessionLog()
        let settings = SettingsStore(
            with: InMemorySettingsStorageProvider(),
            secureSettingsProvider: InMemorySecureSettingsStorageProvider()
        )
        let registry = LanguageServerRegistry(
            store: settings,
            workspaceURL: workspaceURL,
            builtInConfigurations: [],
            sessionFactory: { configuration, _, _ in
                FakeEditorLanguageServerSession(configuration: configuration, behavior: behavior, log: log)
            }
        )
        let configuration = LanguageServerConfiguration(
            name: "Fake",
            languageIds: languageIds,
            command: "/nonexistent/server",
            rootMarkers: [".git"]
        )
        if registersConfiguration {
            settings.set([configuration], for: UserSettings.languageServerConfigurations)
        }

        self.log = log
        self.settings = settings
        self.registry = registry
        self.configuration = configuration
    }

    /// The fake serving `languageId`, **started**.
    ///
    /// Started explicitly rather than waiting on the registry: the registry
    /// starts a new session in a `Task` of its own, so a delegate asking for
    /// capabilities can otherwise race it and see `nil` for reasons that have
    /// nothing to do with what the test is about. `start()` is idempotent on a
    /// running session, so this never contradicts the registry's own call.
    func startedSession(languageId: String = "swift") async throws -> FakeEditorLanguageServerSession {
        let session = registry.session(forLanguageId: languageId)
        let fake = try #require(session as? FakeEditorLanguageServerSession)
        try await fake.start()
        return fake
    }
}

// MARK: - Document and editor fixtures

@MainActor
func makeEditorDocument(
    uri: DocumentUri = "file:///Workspace/Sample.swift",
    text: String,
    languageId: String = "swift"
) -> TextDocument {
    TextDocument(uri: uri, languageId: languageId, text: text)
}

/// Only here so `Bundle(for:)` below resolves to *this* test bundle.
private final class EditorTestBundleFinder {}

/// Points CodeEditLanguages' `Bundle.module` at the test bundle's resources.
///
/// `CodeLanguage` evaluates `Bundle.module.resourceURL` while *constructing*,
/// and that accessor `fatalError`s when it cannot find its SwiftPM resource
/// bundle — which it cannot here: CodeEditLanguages is linked statically into
/// `AgenticToolkitMacOS.framework`, so its `Bundle(for:)` candidate is the
/// framework's own (empty) Resources, while the build copies the bundle into
/// `AgenticToolkitMacOSTests.xctest/Contents/Resources`. `Bundle.main` is
/// `xctest` itself and helps nobody.
///
/// The same workaround, for the same reason, as `LanguageDetectionTests.setUp`.
/// A global `let` rather than a `setUp`, because Swift Testing has no
/// bundle-wide hook and these suites run in parallel: `Bundle.module` is a lazy
/// static, so the override only has to be in place before the *first*
/// construction, and a `let` gives that exactly once.
private let editorLanguageResourcesLocated: Bool = {
    guard let resourceURL = Bundle(for: EditorTestBundleFinder.self).resourceURL else { return false }
    setenv("PACKAGE_RESOURCE_BUNDLE_PATH", resourceURL.path, 1)
    return true
}()

/// Puts the override above in place. Call it before anything that constructs a
/// `CodeLanguage` — which includes `LanguageDetection`, not only the editor —
/// because that construction is what evaluates `Bundle.module.resourceURL`.
@discardableResult
func ensureEditorLanguageResourcesLocated() -> Bool {
    editorLanguageResourcesLocated
}

/// A real `TextViewController`, which is what the delegates are handed and what
/// `completionWindowApplyCompletion` writes through.
///
/// `highlightProviders: []` on purpose: the default spins up a `TreeSitterClient`
/// and none of these tests assert anything about highlighting.
///
/// The view is loaded before it is returned. That is not tidiness: the
/// controller's own `TextViewDelegate` conformance touches `gutterView` on
/// every content replacement, and `gutterView` is an implicitly-unwrapped
/// optional built in `loadView()` — so an unloaded controller traps the moment
/// a completion is applied through it.
/// The `theme:` parameter exists for the one suite that reads colours back out
/// rather than text: a palette-derived theme reuses colours across its sixteen
/// fields, so an assertion about *which* field a capture lands in needs a theme
/// whose fields are all different. Everything else takes the default.
@MainActor
func makeEditorTextViewController(
    text: String,
    theme: EditorTheme = SemanticPalette(theme: BuiltInThemes.dracula).editorTheme
) -> TextViewController {
    _ = editorLanguageResourcesLocated
    let controller = TextViewController(
        string: text,
        language: .default,
        configuration: SourceEditorConfiguration(
            appearance: .init(
                theme: theme,
                font: .monospacedSystemFont(ofSize: 12, weight: .regular),
                wrapLines: false
            )
        ),
        cursorPositions: [],
        highlightProviders: []
    )
    controller.loadView()
    return controller
}

/// A caret at a UTF-16 offset, in the shape the package's trigger path uses —
/// `CursorPosition(range:)`, whose `start` is the placeholder `(-1, -1)`.
func makeCursor(atOffset offset: Int) -> CursorPosition {
    CursorPosition(range: NSRange(location: offset, length: 0))
}

// MARK: - Foreign entry

/// A `CodeSuggestionEntry` the LSP delegate did not create.
///
/// Not hypothetical: the package puts its own `JumpToDefinitionLink`s through
/// the same completion window, so `completionWindowApplyCompletion` really is
/// handed entries of other types.
struct ForeignSuggestionEntry: CodeSuggestionEntry {
    var label: String { "foreign" }
    var detail: String? { nil }
    var documentation: String? { nil }
    var pathComponents: [String]? { nil }
    var targetPosition: CursorPosition? { nil }
    var sourcePreview: String? { nil }
    var image: SwiftUI.Image { SwiftUI.Image(systemName: "questionmark") }
    var imageColor: SwiftUI.Color { SwiftUI.Color(nsColor: .systemGray) }
    var deprecated: Bool { false }
}

// MARK: - Open-file recorder

/// Stands in for the file browser's "show me this file" closure.
@MainActor
final class OpenedFileRecorder {
    private(set) var urls: [URL] = []

    var open: @MainActor (URL) -> Void {
        { [self] url in urls.append(url) }
    }
}
