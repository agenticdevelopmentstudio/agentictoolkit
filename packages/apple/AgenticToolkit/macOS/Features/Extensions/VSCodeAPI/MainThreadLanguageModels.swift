//
//  MainThreadLanguageModels.swift
//  AgenticToolkit
//

import Foundation
import JavaScriptCore
import OSLog
import AgenticToolkitCore

// MARK: - Value types mirroring vscode.d.ts's LanguageModelChat family

/// One chat model this host can offer an extension — the data
/// `vscode.LanguageModelChat`'s six readonly properties expose
/// (`vscode.d.ts:20242-20312`, commit
/// 3addbda66f9e80c3ed1b943822ab823bb6747b02).
///
/// A plain value type, not the JS object itself: `selectChatModels` builds a
/// fresh `JSValue` per call from whichever of these match a selector
/// (`MainThreadLanguageModels.makeChatModelObject`, below), so this struct is
/// what `ExtensionLanguageModelProviding` deals in and the only thing a test
/// double needs to construct.
public struct LanguageModelChatDescriptor: Sendable, Equatable {
    /// `vscode.d.ts:20247`.
    public var name: String
    /// `vscode.d.ts:20252`.
    public var id: String
    /// `vscode.d.ts:20258`.
    public var vendor: String
    /// `vscode.d.ts:20264`.
    public var family: String
    /// `vscode.d.ts:20270`.
    public var version: String
    /// `vscode.d.ts:20275`.
    public var maxInputTokens: Int

    public init(
        name: String,
        id: String,
        vendor: String,
        family: String,
        version: String,
        maxInputTokens: Int
    ) {
        self.name = name
        self.id = id
        self.vendor = vendor
        self.family = family
        self.version = version
        self.maxInputTokens = maxInputTokens
    }
}

// MARK: - The extension language-model seam

/// Every chat model this host currently knows about, for
/// `vscode.lm.selectChatModels` (`vscode.d.ts:20769`, commit
/// 3addbda66f9e80c3ed1b943822ab823bb6747b02).
///
/// A seam rather than a direct reference to whatever eventually fronts a real
/// model provider: that type would be `@MainActor`, live production code —
/// reaching it directly from this adaptor would make every test of
/// `selectChatModels` construct a real provider, the same reason
/// `ExtensionLanguageVocabulary` exists instead of a direct reference to
/// `LanguageContributionPoint` (`MainThreadLanguages.swift:448-463`, commit
/// 6409e2de). This task writes no production conformer: no model provider
/// exists in this host yet, and inventing a placeholder that returns a
/// hardcoded model would make `selectChatModels` answer with something no
/// extension can actually use. A test hands in a double; production wires a
/// conformer when a provider exists.
///
/// One member, deliberately: `MainThreadLanguageModels` does all selector
/// matching itself (below), so the seam only has to answer what exists, not
/// what matches — keeping the selector semantics (no-selector-means-all,
/// `{}`-same-as-omitted, per-field conjunction) in one place, testable
/// against one simple double, rather than duplicated behind every future
/// conformer.
@MainActor
public protocol ExtensionLanguageModelProviding: AnyObject {
    /// Every chat model this host currently knows about, in a deterministic
    /// order, unfiltered by any selector.
    var availableChatModels: [LanguageModelChatDescriptor] { get }
}

// MARK: - vscode.lm

/// Installs `vscode.lm.selectChatModels` (`vscode.d.ts:20769`) and the
/// `vscode.LanguageModelChat` objects it hands back (`:20242-20312`) — the
/// second half of task 5.7a. 5.7a-i installed the value types an extension
/// *constructs* (`LanguageModelMessageVocabulary.swift`); this installs the
/// namespace function that *finds a model* and the object it hands back.
/// `sendRequest` is a NotImplemented stub 5.7b replaces with a real response
/// stream: it records the access into `notImplementedLedger` and throws the
/// shim's own `NotImplementedError` shape (see `raiseNotImplemented` below).
/// `vscode.lm.onDidChangeChatModels` (`:20742`) is out of scope for this task
/// entirely — nothing here installs it, so an extension reaching for it hits
/// the `vscode.lm` stub Proxy's `get` trap, which records the access and
/// throws that same shape (`extension-runtime.js:555-557`, commit 6409e2de).
@MainActor
public final class MainThreadLanguageModels {

    /// The source of chat models this member selects from.
    /// `handleSelectChatModels` reads `availableChatModels` and filters it;
    /// that property is the whole of what `ExtensionLanguageModelProviding`
    /// offers, so there is no other way in — see its own doc for why the
    /// protocol is drawn that narrowly.
    private let provider: ExtensionLanguageModelProviding

    /// Recipient of `sendRequest`'s "not implemented" access — the same
    /// ledger `MainThreadWindow`'s status-bar item setters record into
    /// (`MainThreadWindow.swift:2276`, `:2289`, commit 6409e2de).
    private let notImplementedLedger: NotImplementedLedger

    /// Whose extension is asking, for `notImplementedLedger`'s
    /// `extensionIdentifier` field. Stored, not defaulted —
    /// `MainThreadWindow` stores its own the same way and equally without a
    /// default (`MainThreadWindow.swift:881`, commit 6409e2de, which states
    /// no reason). The reason here is mine: there is no safe silent default
    /// for "whose extension," and a wrong one mislabels every ledger entry.
    private let extensionIdentifier: String

    public init(
        provider: ExtensionLanguageModelProviding,
        notImplementedLedger: NotImplementedLedger,
        extensionIdentifier: String
    ) {
        self.provider = provider
        self.notImplementedLedger = notImplementedLedger
        self.extensionIdentifier = extensionIdentifier
    }

    // MARK: - vscode.lm.selectChatModels

    /// `implementation` for `vscode.lm.selectChatModels`, handed to
    /// `ExtensionHost.defineVSCodeMember(namespacePath:name:implementation:)`
    /// as-is — the adaptor-with-owner route `MainThreadLanguages.getLanguages`
    /// uses (`MainThreadLanguages.swift:626-628`, commit 6409e2de), not
    /// 5.7a-i's host-ceremony route (`ExtensionHost.swift:990-1000`, commit
    /// 6409e2de, draws that distinction). Rejects on a torn-down adaptor, for
    /// the reason `MainThreadLanguages.getLanguages` does.
    public private(set) lazy var selectChatModels: Any = VSCodeAPI.member(
        "vscode.lm.selectChatModels", of: self, whenTornDown: .rejectedPromise
    ) { $0.handleSelectChatModels() }

    /// `vscode.d.ts:20744-20768`'s own doc block says this function "can
    /// yield multiple or no chat models" and extensions "must handle these
    /// cases, esp. when no chat model exists, gracefully" (`:20745-20746`),
    /// and `:20767` spells it out further: "can be empty!" A `provider` with
    /// nothing configured therefore resolves with `[]` — never a rejection,
    /// never a NotImplemented record, never a logged warning — because `[]`
    /// is upstream's *specified* answer for "no model," not this host's
    /// stand-in for one.
    ///
    /// `selectChatModels()` (no argument), `selectChatModels({})` and a
    /// selector with any subset of its four optional fields
    /// (`vscode.d.ts:20325`,`:20331`,`:20337`,`:20343`) set are all legal
    /// calls (`:20769` makes the whole selector optional). `currentArguments()
    /// .first` is `nil` for the first case, and reads as a criteria value with
    /// every field `nil` in `LanguageModelChatSelectorCriteria.make(from:)`
    /// through a different branch than the second case does — an empty
    /// object is `.isObject` and reads four `undefined` properties, while a
    /// missing argument never reaches property access at all. Both branches
    /// have to independently produce "match everything," which is why they
    /// are two tests, not one.
    private func handleSelectChatModels() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let selectorArgument = VSCodeAPI.currentArguments().first
        let criteria = LanguageModelChatSelectorCriteria.make(from: selectorArgument)
        let matches = provider.availableChatModels.filter(criteria.matches)
        let objects = matches.compactMap { model -> JSValue? in
            guard let object = MainThreadLanguageModels.makeChatModelObject(
                for: model, of: self, in: context) else {
                MainThreadLanguageModels.logger.error(
                    """
                    JSValue(newObjectIn:) answered nothing bridging chat \
                    model '\(model.id, privacy: .public)'; it is dropped, so \
                    selectChatModels resolves with fewer models than matched
                    """)
                return nil
            }
            return object
        }
        let arrayValue = MainThreadLanguageModels.arrayValue(of: objects, in: context)
        return VSCodeAPI.resolvedPromise(with: arrayValue, in: context)
    }

    // MARK: - The LanguageModelChat object-handback pattern

    /// Builds the JS-visible `LanguageModelChat` object for `model`
    /// (`vscode.d.ts:20242-20312`): a `defineProperty` readonly getter for
    /// each of the six data properties — never a plain `setObject`, which
    /// would produce a **writable** property and silently lose the
    /// `readonly` behaviour `vscode.d.ts` declares for every one of them —
    /// and two method blocks, `sendRequest` and `countTokens`, via
    /// `setObject(_:forKeyedSubscript:)`
    /// (`MainThreadWindow.swift:2159-2171` for the accessor descriptor shape,
    /// `:2181-2191` for the readonly-getter variant used here, `:2340-2365`
    /// for the method-block shape, all commit 6409e2de). Never constructed by
    /// an extension with `new` — this is the object-handback pattern, not
    /// 5.7a-i's class pattern, because `LanguageModelChat` is an interface an
    /// extension only ever *receives*.
    ///
    /// **No-capture evidence (Ruling 4), one sentence per block kind
    /// installed here:**
    /// - Every readonly-getter block captures `model`, a value type, **by
    ///   copy** — there is no reference to weaken and nothing here can retain
    ///   the host, because a `LanguageModelChatDescriptor` holds only
    ///   `String`s and an `Int`.
    /// - `sendRequest`'s block captures `languageModels` **weakly** and
    ///   nothing else, reaching `notImplementedLedger` and
    ///   `extensionIdentifier` only through that weak pointer; if
    ///   `languageModels` is already gone the block is a no-op. It is the
    ///   only weak capture in this file — the namespace member itself
    ///   *rejects* after teardown instead (`whenTornDown: .rejectedPromise`,
    ///   above). The no-op precedent is `MainThreadWindow`'s handed-back
    ///   `show`, `hide` and `dispose` blocks, each `[weak item, weak window]`
    ///   over a `guard let … else { return }`
    ///   (`MainThreadWindow.swift:2340-2365`, commit 6409e2de).
    /// - `countTokens`'s block captures nothing but its own arguments —
    ///   `extractedText(from:)` and `approximateTokenCount(for:)` are pure
    ///   functions of whatever `JSValue` the extension passed, so there is
    ///   nothing to weaken.
    private static func makeChatModelObject(
        for model: LanguageModelChatDescriptor,
        of languageModels: MainThreadLanguageModels,
        in context: JSContext
    ) -> JSValue? {
        guard let object = JSValue(newObjectIn: context) else { return nil }

        installReadonlyGetter(on: object, name: "name") { model.name }
        installReadonlyGetter(on: object, name: "id") { model.id }
        installReadonlyGetter(on: object, name: "vendor") { model.vendor }
        installReadonlyGetter(on: object, name: "family") { model.family }
        installReadonlyGetter(on: object, name: "version") { model.version }
        installReadonlyGetter(on: object, name: "maxInputTokens") { model.maxInputTokens }

        let sendRequest: @convention(block) () -> Void = { [weak languageModels] in
            MainActor.assumeIsolated {
                guard let languageModels, let context = JSContext.current() else { return }
                _ = languageModels.notImplementedLedger.record(
                    memberPath: "vscode.LanguageModelChat.sendRequest",
                    extensionIdentifier: languageModels.extensionIdentifier)
                MainThreadLanguageModels.raiseNotImplemented(
                    memberPath: "vscode.LanguageModelChat.sendRequest", in: context)
            }
        }
        object.setObject(sendRequest, forKeyedSubscript: "sendRequest" as NSString)

        let countTokens: @convention(block) () -> JSValue? = {
            MainActor.assumeIsolated {
                guard let context = JSContext.current() else { return UncheckedJSValueBox(value: nil) }
                let argument = VSCodeAPI.currentArguments().first
                let text = MainThreadLanguageModels.extractedText(from: argument)
                let count = MainThreadLanguageModels.approximateTokenCount(for: text)
                return UncheckedJSValueBox(value: VSCodeAPI.resolvedPromise(with: count, in: context))
            }.value
        }
        object.setObject(countTokens, forKeyedSubscript: "countTokens" as NSString)

        return object
    }

    /// Installs a `defineProperty` getter with no setter — `vscode.d.ts`
    /// declares every one of `LanguageModelChat`'s six data properties
    /// `readonly` (`:20247`,`:20252`,`:20258`,`:20264`,`:20270`,`:20275`), and
    /// assigning to one from non-strict JavaScript is then a silent no-op:
    /// JavaScript's own behaviour for writing a property whose descriptor has
    /// no setter, not a check this file performs — `MainThreadWindow.swift
    /// :2173-2180`'s doc for its own `installReadonlyGetter` (commit
    /// 6409e2de) states the same rule for `StatusBarItem.id`/`alignment`
    /// /`priority`, and this is that identical mechanism, not a reimplemented
    /// copy.
    private static func installReadonlyGetter(
        on object: JSValue,
        name: String,
        get: @escaping @convention(block) () -> Any?
    ) {
        object.defineProperty(name, descriptor: [
            "enumerable": true,
            "configurable": true,
            "get": get
        ])
    }

    // MARK: - LanguageModelChat.countTokens

    /// Extracts the text `countTokens` (`vscode.d.ts:20311`) should count
    /// from whichever of its two argument shapes arrived: a bare `string`,
    /// or a `LanguageModelChatMessage`
    /// (`LanguageModelMessageVocabulary.swift`, task 5.7a-i) whose `content`
    /// is *always* an array of parts after that class's own accessor pair
    /// coerces a bare-string assignment into
    /// `[new LanguageModelTextPart(value)]` — reading `content` as a string
    /// here would read `undefined` off an array and silently count zero for
    /// every message, string-sourced or not. Only `.value`-bearing parts
    /// (`LanguageModelTextPart`, `LanguageModelPromptTsxPart`) contribute
    /// text; a part with no string `.value` (`LanguageModelDataPart`,
    /// `LanguageModelToolCallPart`, `LanguageModelToolResultPart`) is
    /// skipped rather than guessed at, because guessing is out of this
    /// task's scope (`sendRequest`'s real implementation is 5.7b's).
    private static func extractedText(from argument: JSValue?) -> String {
        guard let argument else { return "" }
        if argument.isString, let string = argument.toString() {
            return string
        }
        guard argument.isObject,
              let content = argument.forProperty("content"),
              content.isObject,
              let lengthValue = content.forProperty("length") else {
            return ""
        }
        let count = lengthValue.toInt32()
        guard count > 0 else { return "" }
        var parts: [String] = []
        for index in 0..<count {
            guard let part = content.atIndex(Int(index)),
                  let value = part.forProperty("value"),
                  value.isString,
                  let text = value.toString() else {
                continue
            }
            parts.append(text)
        }
        return parts.joined(separator: " ")
    }

    /// The actual number `countTokens` answers with. A real tokenizer is a
    /// model provider's business, not this task's — the same "no production
    /// conformer" ruling that keeps `ExtensionLanguageModelProviding` to one
    /// member keeps this a plain, deterministic word count rather than a
    /// second protocol requirement invented to route through a provider that
    /// does not exist yet. Whitespace-delimited so an empty string counts
    /// zero, matching zero words extracted.
    private static func approximateTokenCount(for text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    // MARK: - The NotImplementedError shape

    /// Raises, on `context`, the same shape `extension-runtime.js`'s own
    /// `notImplementedError(memberPath)` builds for a member the shim's
    /// Proxy has no table entry for (`extension-runtime.js:512-520`, thrown
    /// at `:556-557`, commit 6409e2de): `name` set to `'NotImplementedError'`
    /// and `memberPath` set to the member's dotted path, on an `Error` whose
    /// message follows that function's exact template. `sendRequest` needs
    /// this built fresh rather than reached through that Proxy trap, because
    /// `sendRequest` itself *is* installed — the trap only fires for a key
    /// missing from the shim's table, and an extension should not be able to
    /// tell "installed, stub" apart from "never implemented" by the shape of
    /// the error either one throws.
    private static func raiseNotImplemented(memberPath: String, in context: JSContext) {
        let message = "\(memberPath) is not implemented yet. This extension host implements the VS Code " +
            "API one member at a time, and \(memberPath) is not available in this build."
        guard let error = JSValue(newErrorFromMessage: message, in: context) else {
            logger.error(
                """
                JSValue(newErrorFromMessage:in:) answered nothing while raising NotImplementedError for \
                '\(memberPath, privacy: .public)'; the extension sees this call return 'undefined' rather \
                than throw
                """)
            return
        }
        error.setObject("NotImplementedError", forKeyedSubscript: "name" as NSString)
        error.setObject(memberPath, forKeyedSubscript: "memberPath" as NSString)
        context.exception = error
    }

    // MARK: - Bridging a Swift array to a fresh JS array

    /// Builds a JS array from `values` via `JSValue(object:in:)`, falling
    /// back to `NSNull()` on failure — the same shape
    /// `MainThreadWindow.swift:2705-2710`'s own `arrayValue(of:in:)` uses
    /// (commit 6409e2de). That one is `private static`, so it is unreachable
    /// from here even though both files are in this module; this is a copy,
    /// not a shared helper. `JSValue(object:in:)` bridges a *new* JS array on
    /// every call, so mutating one call's result never affects the next.
    private static func arrayValue(of values: [JSValue], in context: JSContext) -> Any {
        JSValue(object: values, in: context) ?? NSNull()
    }
}

// MARK: - The parsed LanguageModelChatSelector

/// A parsed `vscode.LanguageModelChatSelector` (`vscode.d.ts:20319-20344`),
/// the plain object literal an extension passes *in* to `selectChatModels`.
/// All four fields are optional (`:20325`,`:20331`,`:20337`,`:20343`), and
/// the whole selector is optional too (`:20769`) — an absent argument and an
/// object with every field `undefined` both produce a criteria value with
/// every field `nil`, and `matches(_:)` treats a `nil` field as imposing no
/// constraint, so both mean "match everything."
private struct LanguageModelChatSelectorCriteria {
    var vendor: String?
    var family: String?
    var version: String?
    var id: String?

    /// `selector` is `currentArguments().first` — `nil` when the extension
    /// called `selectChatModels()` with no argument at all. A non-`nil`
    /// argument that is not a JS object (a number, a string) is treated the
    /// same as "no constraints" rather than crashing on `forProperty`, which
    /// upstream's own type (`selector?: LanguageModelChatSelector`) does not
    /// contemplate an extension violating in a way this host needs to
    /// diagnose.
    static func make(from selector: JSValue?) -> LanguageModelChatSelectorCriteria {
        guard let selector, selector.isObject else {
            return LanguageModelChatSelectorCriteria(vendor: nil, family: nil, version: nil, id: nil)
        }
        return LanguageModelChatSelectorCriteria(
            vendor: stringOptionalField(selector.forProperty("vendor")),
            family: stringOptionalField(selector.forProperty("family")),
            version: stringOptionalField(selector.forProperty("version")),
            id: stringOptionalField(selector.forProperty("id")))
    }

    /// A conjunction, not a disjunction: every field this criteria value
    /// actually sets must equal `model`'s corresponding property, so a
    /// selector with two fields set where only one matches excludes the
    /// model — the mutation an all-fields-match fixture cannot see.
    func matches(_ model: LanguageModelChatDescriptor) -> Bool {
        if let vendor, vendor != model.vendor { return false }
        if let family, family != model.family { return false }
        if let version, version != model.version { return false }
        if let id, id != model.id { return false }
        return true
    }

    /// `nil` unless `value` is a JS string — an `undefined` property (a field
    /// the extension left unset) and a non-string value are both read as "no
    /// constraint on this field," never as an empty-string constraint.
    private static func stringOptionalField(_ value: JSValue?) -> String? {
        guard let value, value.isString, let string = value.toString() else { return nil }
        return string
    }
}

// MARK: - Logging

extension MainThreadLanguageModels: Loggable {
    public static nonisolated let logger = makeLogger()
}

// MARK: - Carrying a JSValue? out of MainActor.assumeIsolated

/// `@unchecked Sendable`, on the same terms as `VSCodeAPI.swift`'s own
/// `private struct UncheckedJSValueBox` (that type is private to its file,
/// so this is a local equivalent, not a reuse): nothing here actually
/// crosses an isolation domain — `countTokens`'s block and the
/// `MainActor.assumeIsolated` call inside it both run on the same main
/// actor — but `assumeIsolated`'s generic return type is checked against
/// `Sendable`, and a bare `JSValue?` is not, and is not a type this module
/// can extend with a conformance. This box is the honest way to state the
/// guarantee the surrounding code already holds.
private struct UncheckedJSValueBox: @unchecked Sendable {
    let value: JSValue?
}
