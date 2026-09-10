//
//  ExtensionHost.swift
//  AgenticToolkit
//

import Foundation
import JavaScriptCore
import OSLog

import AgenticToolkitCore

/// Runs one VS Code **web** extension's JavaScript in its own `JSContext`.
///
/// One host per extension, one context per host, and one `JSVirtualMachine`
/// shared by every host in the process. Contexts inside a single VM are torn
/// down independently and cost little; separate VMs would buy isolation between
/// extensions that already cannot reach each other — nothing crosses between
/// two contexts except through Swift, and Swift never carries a `JSValue` from
/// one to the other.
///
/// `@MainActor`, and not by accident. `JSContext` and `JSValue` are not
/// `Sendable`, every adaptor Stage 5 builds on top of this hangs off main-actor
/// components (the command registry, the document store, the window layout),
/// and a host that hopped executors would have to marshal JavaScript values
/// across them. The one thing that genuinely does not belong on the main thread
/// — reading a bundled extension's JavaScript off disk, which can be megabytes
/// — is the one thing `activate()` does off it.
///
/// What this host deliberately does *not* do is give the extension anything to
/// call. The `vscode` namespace it hands to `require('vscode')` is a wall of
/// recorded, throwing stubs (see `NotImplementedLedger` and
/// `Resources/extension-runtime.js`); stages 5.3 onward replace those one
/// member at a time. That is the point: an extension that reaches for an API
/// this build does not have fails loudly and by name, instead of activating
/// successfully and then doing nothing.
@MainActor
public final class ExtensionHost {

    // MARK: - Properties

    /// The extension this host runs, and the directory every path it declares
    /// resolves against.
    public let loadedExtension: LoadedExtension

    public var identifier: String { loadedExtension.identifier }

    /// Where unimplemented API members are recorded. Injected rather than owned
    /// outright so a caller running several extensions can give them all one
    /// ledger and hand the whole thing to a report; a caller with one extension
    /// gets a private one and never has to think about it.
    public let notImplementedLedger: NotImplementedLedger

    /// Every `console.*` call the extension makes, alongside the OSLog line it
    /// always produces. A host with no observer still logs; this is for a UI
    /// that wants to show the extension's own output, and for tests, which
    /// otherwise have no way to observe that the extension's code ran at all.
    public var onConsoleMessage: ((ExtensionConsoleMessage) -> Void)?

    public private(set) var isActivated = false
    public private(set) var isDisposed = false

    /// One VM for the whole process. `JSVirtualMachine` is not `Sendable`; this
    /// static is main-actor isolated with the rest of the type, which is the
    /// same confinement every host that uses it already has.
    private static let virtualMachine = JSVirtualMachine()

    /// Read once and kept: the shim is a fixed resource in this framework's
    /// bundle, and re-reading it per extension is disk work with one possible
    /// answer.
    private static var cachedRuntimeSource: String?

    private var context: JSContext?

    /// `__extensionRuntime` from the shim, captured before its global is
    /// deleted. Holding it here rather than looking it up by name is what lets
    /// the globals go away: the extension's code cannot reach an object it has
    /// no name for, and this host still can.
    private var runtime: JSValue?

    /// The clocks behind the shim's `setTimeout`/`setInterval`. `Task`, not
    /// `Timer` or a dispatch source, because cancellation is then the language
    /// primitive rather than a bookkeeping convention — `dispose()` cancels
    /// every one of these, and a cancelled task cannot reach JavaScript again.
    private var timerTasks: [Int32: Task<Void, Never>] = [:]

    /// Set by the context's `exceptionHandler`, read and cleared around every
    /// evaluation. A `JSContext` reports an uncaught exception by calling the
    /// handler and returning a nil-ish value, so `try` alone catches nothing:
    /// without this, an extension whose top-level code throws would look
    /// exactly like one that loaded cleanly and exported nothing.
    private var pendingException: String?

    // MARK: - Initialization

    public init(
        loadedExtension: LoadedExtension,
        notImplementedLedger: NotImplementedLedger = NotImplementedLedger()
    ) {
        self.loadedExtension = loadedExtension
        self.notImplementedLedger = notImplementedLedger
    }

    // MARK: - Activation

    /// Resolves the entry point, evaluates the extension's code in a fresh
    /// context, and calls its exported `activate` if it has one.
    ///
    /// Calling twice is a no-op. VS Code activates an extension once, callers
    /// re-emit activation events routinely, and re-evaluating the module would
    /// leave two sets of registrations behind that one `dispose()` cannot undo
    /// (`idempotency`).
    public func activate() async throws {
        guard !isDisposed else {
            throw ExtensionHostError.hostDisposed(identifier: identifier)
        }
        guard !isActivated else { return }

        let entryPoint = try resolveEntryPoint()
        let source = try await Self.readSource(at: entryPoint, identifier: identifier)

        let context = try makeContext()
        self.context = context

        guard let runtime = try installRuntime(into: context) else {
            throw ExtensionHostError.runtimeUnavailable(identifier: identifier)
        }
        self.runtime = runtime

        let exports = try evaluateModule(runtime: runtime, source: source, entryPoint: entryPoint)
        isActivated = true
        try callActivate(on: exports, runtime: runtime)
    }

    /// Releases the context, cancels every timer the extension scheduled, and
    /// drops the host's handle on the runtime object.
    ///
    /// Deliberately does *not* call the extension's `deactivate`. Teardown's
    /// contract here is that nothing can call back into the app afterwards, and
    /// running extension JavaScript as the last act of teardown is the opposite
    /// of that. There is also nothing yet for an extension to clean up — every
    /// `vscode` member that would let it acquire a resource is a stub — so the
    /// callback would be ceremony with a failure mode.
    ///
    /// Safe to call more than once, and safe to call on a host that never
    /// activated.
    public func dispose() {
        isDisposed = true

        for task in timerTasks.values {
            task.cancel()
        }
        timerTasks.removeAll()

        // Blocks installed into the context capture this host weakly, so there
        // is no cycle to break — but the handler is cleared anyway, because a
        // context torn down mid-evaluation would otherwise still have a route
        // to `pendingException` on a host that is no longer listening.
        context?.exceptionHandler = nil
        runtime = nil
        context = nil
    }

    // MARK: - Entry point

    /// The file this extension's code lives in, proven to be inside the
    /// extension's own directory.
    ///
    /// Only `browser` is honoured. `main` is Node's entry point and this host
    /// has no Node: a Node extension refused with a generic "could not load"
    /// is the single most likely confusion this feature can produce, so it gets
    /// its own error that says which runtime it needed and which one exists.
    func resolveEntryPoint() throws -> URL {
        let manifest = loadedExtension.manifest

        guard let browser = manifest.browser else {
            if let main = manifest.main {
                throw ExtensionHostError.requiresNodeRuntime(identifier: identifier, declaredMain: main)
            }
            throw ExtensionHostError.noEntryPoint(identifier: identifier)
        }

        // `isDirectory: true` spelled out. The single-argument initializers
        // consult the file system for that flag, and a base that lost it
        // resolves every relative path one level *up* — out of the extension
        // directory, which is precisely what the containment check below
        // exists to prevent.
        let base = URL(fileURLWithPath: loadedExtension.directory.path, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL

        // Symlinks first, then `..` removal, and the same treatment for both
        // sides: on macOS the temporary directory alone is a symlink
        // (`/var` → `/private/var`), so a base and a candidate normalized
        // differently would compare unequal for every path and the check would
        // refuse everything — or, resolved the other way round, would accept an
        // escape through a symlink planted inside the extension.
        let candidate = URL(fileURLWithPath: browser, relativeTo: base)
            .resolvingSymlinksInPath()
            .standardizedFileURL

        guard Self.url(candidate, isContainedIn: base) else {
            throw ExtensionHostError.entryPointEscapesExtensionDirectory(
                identifier: identifier,
                declared: browser,
                resolved: candidate.path
            )
        }

        return candidate
    }

    /// Whether `candidate` is strictly below `base`.
    ///
    /// Compares path *components*, not string prefixes: `/tmp/ext-evil` has
    /// `/tmp/ext` as a string prefix and is not inside it, and a check that
    /// missed that would let an attacker choose a sibling directory name.
    private static func url(_ candidate: URL, isContainedIn base: URL) -> Bool {
        let baseComponents = base.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidateComponents.count > baseComponents.count else { return false }
        return Array(candidateComponents.prefix(baseComponents.count)) == baseComponents
    }

    /// Reads the entry point off the main thread. A bundled web extension is
    /// one concatenated file and routinely megabytes; the project's standing
    /// rule is that nothing lengthy blocks the main thread, and this is the
    /// only part of activation that can honour it.
    private static func readSource(at url: URL, identifier: String) async throws -> String {
        do {
            return try await Task.detached(priority: .userInitiated) {
                try String(contentsOf: url, encoding: .utf8)
            }.value
        } catch {
            throw ExtensionHostError.entryPointUnreadable(
                identifier: identifier,
                path: url.path,
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Context

    private func makeContext() throws -> JSContext {
        guard let context = JSContext(virtualMachine: Self.virtualMachine) else {
            throw ExtensionHostError.javaScriptEngineUnavailable(identifier: identifier)
        }
        context.name = "extension:\(identifier)"
        context.exceptionHandler = { [weak self] _, exception in
            // The handler runs synchronously inside `evaluateScript` /
            // `JSValue.call`, on whatever thread made that call — and this host
            // only ever makes them from the main actor.
            MainActor.assumeIsolated {
                self?.pendingException = Self.describe(exception)
            }
        }
        return context
    }

    /// Installs the host block table, evaluates the shim, captures
    /// `__extensionRuntime`, and then removes both globals.
    ///
    /// Removing them is the difference between "the extension is given a
    /// bounded runtime" and "the extension is given a bounded runtime plus a
    /// direct line to the app": `__host` carries blocks that schedule timers
    /// and write to the log, and an extension that found it could use them
    /// without going through any of the shim's checks.
    private func installRuntime(into context: JSContext) throws -> JSValue? {
        guard let table = JSValue(newObjectIn: context) else {
            throw ExtensionHostError.javaScriptEngineUnavailable(identifier: identifier)
        }

        let console: @convention(block) (String, String) -> Void = { [weak self] level, text in
            MainActor.assumeIsolated { self?.handleConsole(level: level, text: text) }
        }
        let record: @convention(block) (String) -> Void = { [weak self] memberPath in
            MainActor.assumeIsolated { self?.handleNotImplemented(memberPath: memberPath) }
        }
        let schedule: @convention(block) (Int32, Double, Bool) -> Void = { [weak self] timerID, delay, repeats in
            MainActor.assumeIsolated {
                self?.scheduleTimer(timerID: timerID, delayMilliseconds: delay, repeats: repeats)
            }
        }
        let cancel: @convention(block) (Int32) -> Void = { [weak self] timerID in
            MainActor.assumeIsolated { self?.cancelTimer(timerID: timerID) }
        }

        table.setObject(console, forKeyedSubscript: "console" as NSString)
        table.setObject(record, forKeyedSubscript: "recordNotImplemented" as NSString)
        table.setObject(schedule, forKeyedSubscript: "scheduleTimer" as NSString)
        table.setObject(cancel, forKeyedSubscript: "cancelTimer" as NSString)
        context.setObject(table, forKeyedSubscript: "__host" as NSString)

        pendingException = nil
        let source = try Self.runtimeSource(identifier: identifier)
        context.evaluateScript(source, withSourceURL: Self.runtimeSourceURL)
        if let message = pendingException {
            pendingException = nil
            throw ExtensionHostError.runtimeShimFailed(identifier: identifier, message: message)
        }

        let runtime = context.objectForKeyedSubscript("__extensionRuntime")
        guard let runtime, !runtime.isUndefined, !runtime.isNull else { return nil }

        context.evaluateScript("delete globalThis.__extensionRuntime; delete globalThis.__host;")
        return runtime
    }

    private static let runtimeSourceURL = URL(fileURLWithPath: "/agentic-extension-runtime.js")

    private static func runtimeSource(identifier: String) throws -> String {
        if let cachedRuntimeSource { return cachedRuntimeSource }
        let bundle = Bundle(for: ExtensionHostBundleToken.self)
        guard let url = bundle.url(forResource: "extension-runtime", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            // The shim ships inside this framework. Missing means a broken
            // build, not a broken extension — and it must not be reported as
            // the extension's fault.
            throw ExtensionHostError.runtimeUnavailable(identifier: identifier)
        }
        cachedRuntimeSource = source
        return source
    }

    // MARK: - Evaluation

    private func evaluateModule(runtime: JSValue, source: String, entryPoint: URL) throws -> JSValue {
        pendingException = nil
        let exports = runtime.invokeMethod(
            "run",
            withArguments: [source, entryPoint.path, entryPoint.deletingLastPathComponent().path]
        )
        if let message = pendingException {
            pendingException = nil
            logger.error(
                "Extension '\(self.identifier, privacy: .public)' threw while loading: \(message, privacy: .public)")
            throw ExtensionHostError.entryPointThrew(identifier: identifier, message: message)
        }
        guard let exports, !exports.isUndefined, !exports.isNull else {
            throw ExtensionHostError.entryPointThrew(
                identifier: identifier,
                message: "The entry point produced no module exports."
            )
        }
        return exports
    }

    /// Calls `exports.activate(context)` when the extension exports one.
    ///
    /// An extension without `activate` is legal — a manifest can ship code that
    /// only contributes through side effects — so its absence is logged and is
    /// not an error. What it is handed *is* an error surface: the activation
    /// context is a recorded, throwing stub like every `vscode` member, so an
    /// extension that reaches for `context.subscriptions` today is told which
    /// member it wanted rather than failing later on an `undefined`.
    private func callActivate(on exports: JSValue, runtime: JSValue) throws {
        guard let activate = exports.objectForKeyedSubscript("activate"),
              !activate.isUndefined, !activate.isNull else {
            logger.info("Extension '\(self.identifier, privacy: .public)' exports no activate() function")
            return
        }

        let activationContext = runtime.invokeMethod(
            "makeStubNamespace", withArguments: ["vscode.ExtensionContext"])

        pendingException = nil
        activate.call(withArguments: [activationContext as Any])
        if let message = pendingException {
            pendingException = nil
            logger.error(
                "Extension '\(self.identifier, privacy: .public)' threw from activate(): \(message, privacy: .public)")
            throw ExtensionHostError.activationThrew(identifier: identifier, message: message)
        }
    }

    private static func describe(_ exception: JSValue?) -> String {
        guard let exception else { return "unknown JavaScript exception" }
        let message = exception.toString() ?? "unknown JavaScript exception"
        guard let stack = exception.objectForKeyedSubscript("stack"),
              !stack.isUndefined, !stack.isNull,
              let text = stack.toString(), !text.isEmpty else {
            return message
        }
        return "\(message)\n\(text)"
    }

    // MARK: - Host callbacks

    private func handleConsole(level: String, text: String) {
        let resolved = ExtensionConsoleMessage.Level(rawValue: level) ?? .log
        switch resolved {
        case .debug:
            logger.debug("[\(self.identifier, privacy: .public)] \(text, privacy: .public)")
        case .info:
            logger.info("[\(self.identifier, privacy: .public)] \(text, privacy: .public)")
        case .warn:
            logger.warning("[\(self.identifier, privacy: .public)] \(text, privacy: .public)")
        case .error:
            logger.error("[\(self.identifier, privacy: .public)] \(text, privacy: .public)")
        case .log:
            logger.log("[\(self.identifier, privacy: .public)] \(text, privacy: .public)")
        }
        onConsoleMessage?(
            ExtensionConsoleMessage(extensionIdentifier: identifier, level: resolved, text: text))
    }

    private func handleNotImplemented(memberPath: String) {
        let access = notImplementedLedger.record(memberPath: memberPath, extensionIdentifier: identifier)
        // Only the first reach is logged. The ledger already counts the rest,
        // and a member reached for inside a loop would otherwise fill the log
        // with the one line that carries no new information.
        guard access.count == 1 else { return }
        logger.notice(
            """
            Extension '\(self.identifier, privacy: .public)' reached for \
            '\(memberPath, privacy: .public)', which is not implemented yet
            """)
    }

    // MARK: - Timers

    private func scheduleTimer(timerID: Int32, delayMilliseconds: Double, repeats: Bool) {
        guard !isDisposed else { return }
        timerTasks[timerID]?.cancel()

        let seconds = max(0, delayMilliseconds) / 1000
        timerTasks[timerID] = Task { @MainActor [weak self] in
            while true {
                do {
                    try await Task.sleep(for: .seconds(seconds))
                } catch {
                    // The only throw here is cancellation, which is teardown or
                    // `clearTimeout`. Either way the callback must not run.
                    return
                }
                guard !Task.isCancelled, let self, !self.isDisposed else { return }
                if !repeats {
                    self.timerTasks[timerID] = nil
                }
                self.fireTimer(timerID: timerID)
                if !repeats { return }
            }
        }
    }

    private func cancelTimer(timerID: Int32) {
        timerTasks[timerID]?.cancel()
        timerTasks[timerID] = nil
    }

    private func fireTimer(timerID: Int32) {
        guard let runtime else { return }
        pendingException = nil
        runtime.invokeMethod("fireTimer", withArguments: [Int(timerID)])
        if let message = pendingException {
            pendingException = nil
            logger.error(
                "Extension '\(self.identifier, privacy: .public)' threw from a timer: \(message, privacy: .public)")
        }
    }
}

extension ExtensionHost: Loggable {
    public static nonisolated let logger = makeLogger()
}

/// Resolves this framework's bundle for `Bundle(for:)`. Same device as
/// `AIModelCatalog.BundleToken`: a framework's own resources are found through
/// a class it defines, never through `Bundle.main`, which is the *app*.
private final class ExtensionHostBundleToken {}

/// One `console.*` call an extension made.
public struct ExtensionConsoleMessage: Sendable, Equatable {

    public enum Level: String, Sendable, CaseIterable {
        case log
        case info
        case warn
        case error
        case debug
    }

    public let extensionIdentifier: String
    public let level: Level
    /// Already stringified by the shim, the way a developer expects — an object
    /// arrives as `{ a: 1 }`, not `[object Object]`.
    public let text: String

    public init(extensionIdentifier: String, level: Level, text: String) {
        self.extensionIdentifier = extensionIdentifier
        self.level = level
        self.text = text
    }
}

/// Why an extension's code did not run.
///
/// Every case names the extension, because a host failure reaches the user
/// through a list of extensions and "it didn't work" attached to none of them
/// is not a report. `Equatable` for the same reason `ExtensionLoadError` is: a
/// test can state the exact refusal it expects.
public enum ExtensionHostError: Error, Sendable, Equatable {

    /// The manifest declares `main` but not `browser`. The distinction matters
    /// enough to be its own case: `main` is Node's entry point, this host is a
    /// JavaScriptCore web-extension host, and an author whose extension is
    /// simply the wrong *kind* needs to be told that rather than left reading a
    /// generic load failure.
    case requiresNodeRuntime(identifier: String, declaredMain: String)

    /// Neither `main` nor `browser`. Nothing was refused — the extension
    /// declares no code at all, and everything it contributes it contributes
    /// through its manifest.
    case noEntryPoint(identifier: String)

    /// `browser` resolved outside the extension's own directory. `resolved` is
    /// carried alongside the declared string because the declared one alone
    /// (`../../../etc/passwd`) does not show what it reached.
    case entryPointEscapesExtensionDirectory(identifier: String, declared: String, resolved: String)

    case entryPointUnreadable(identifier: String, path: String, message: String)

    /// The extension's top-level code threw. Caught, not crashed on: one bad
    /// extension is one failed extension.
    case entryPointThrew(identifier: String, message: String)

    /// `activate()` itself threw — which, until stages 5.3-5.7 land, is what
    /// happens to every extension that reaches for a `vscode` member.
    case activationThrew(identifier: String, message: String)

    /// The runtime shim is missing from this framework's bundle. A build
    /// problem, not an extension problem.
    case runtimeUnavailable(identifier: String)

    /// The shim itself threw while being evaluated. Also a build problem.
    case runtimeShimFailed(identifier: String, message: String)

    case javaScriptEngineUnavailable(identifier: String)

    case hostDisposed(identifier: String)
}

extension ExtensionHostError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case let .requiresNodeRuntime(identifier, declaredMain):
            return """
                '\(identifier)' declares a Node entry point ('main': '\(declaredMain)') and no 'browser' \
                entry point. This host runs web extensions in JavaScriptCore and has no Node runtime, so \
                only extensions that declare 'browser' can be run.
                """
        case let .noEntryPoint(identifier):
            return "'\(identifier)' declares no code: its manifest has neither 'main' nor 'browser'."
        case let .entryPointEscapesExtensionDirectory(identifier, declared, resolved):
            return """
                '\(identifier)' declares a 'browser' entry point of '\(declared)', which resolves to \
                '\(resolved)' — outside the extension's own directory. Refused.
                """
        case let .entryPointUnreadable(identifier, path, message):
            return "'\(identifier)' could not read its entry point at '\(path)': \(message)"
        case let .entryPointThrew(identifier, message):
            return "'\(identifier)' threw while its code was loading: \(message)"
        case let .activationThrew(identifier, message):
            return "'\(identifier)' threw from activate(): \(message)"
        case let .runtimeUnavailable(identifier):
            return "'\(identifier)' could not be started: the extension runtime is missing from this build."
        case let .runtimeShimFailed(identifier, message):
            return "'\(identifier)' could not be started: the extension runtime failed to load: \(message)"
        case let .javaScriptEngineUnavailable(identifier):
            return "'\(identifier)' could not be started: a JavaScript context could not be created."
        case let .hostDisposed(identifier):
            return "'\(identifier)' cannot be activated: its host has already been torn down."
        }
    }
}
