//
//  MainThreadLanguages.swift
//  AgenticToolkit
//

import Foundation
import JavaScriptCore
import OSLog
import AgenticToolkitCore

// MARK: - Value types mirroring vscode.d.ts's LanguageConfiguration

/// A `RegExp` as it crosses from JavaScript: `.source` and `.flags`, read at
/// call time and stored verbatim, never a parsed `NSRegularExpression`.
///
/// Mirrors upstream's own wire shape exactly —
/// `extHostLanguageFeatures.ts:2965-2970`'s `_serializeRegExp` builds the
/// identical two-string record before a `RegExp` ever leaves the extension
/// host's process. Storing anything else here — a compiled
/// `NSRegularExpression`, a lossy reading of `flags` — would throw away the
/// one thing a future consumer needs and cannot get back: the flags string
/// JavaScript actually gave.
public struct SerializedRegExp: Sendable, Equatable {

    /// `RegExp.prototype.source`.
    public let pattern: String

    /// `RegExp.prototype.flags`, verbatim — see this type's own doc for why
    /// it is not interpreted away at translation time.
    public let flags: String

    public init(pattern: String, flags: String) {
        self.pattern = pattern
        self.flags = flags
    }

    /// `value` read as a `RegExp`-shaped object — a `.source` string and a
    /// `.flags` string — or `nil` for anything else, including `undefined`,
    /// `null`, and an object missing either property. Absent, not refused:
    /// see `LanguageConfiguration.make(from:)`'s own doc for the shared rule
    /// this follows.
    static func make(from value: JSValue?) -> SerializedRegExp? {
        guard let value, !value.isUndefined, !value.isNull else { return nil }
        guard let sourceValue = value.forProperty("source"), sourceValue.isString,
              let pattern = sourceValue.toString(),
              let flagsValue = value.forProperty("flags"), flagsValue.isString,
              let flags = flagsValue.toString() else {
            return nil
        }
        return SerializedRegExp(pattern: pattern, flags: flags)
    }

    /// `RegExp.prototype.toString`'s own rendering, `/pattern/flags` — used
    /// only to reproduce upstream's refusal message verbatim.
    /// `extHostLanguageFeatures.ts:3011` interpolates the `RegExp` itself
    /// (`` `wordPattern '${wordPattern}' …` ``), not `.source` alone, and a
    /// JS `RegExp`'s own `toString` is exactly this shape.
    var jsRepresentation: String { "/\(pattern)/\(flags)" }

    /// This pattern's `flags` translated to the options
    /// `NSRegularExpression` understands, dropping any flag it has none for
    /// — named here, per this task's own requirement, rather than dropped
    /// silently:
    ///
    /// - `i` (ignoreCase)   -> `.caseInsensitive`
    /// - `m` (multiline)    -> `.anchorsMatchLines`
    /// - `s` (dotAll)       -> `.dotMatchesLineSeparators`
    /// - `g` (global)       -> no equivalent: `NSRegularExpression` already
    ///   finds every match when asked to enumerate them, so there is nothing
    ///   in `.Options` to opt into
    /// - `y` (sticky)       -> no equivalent
    /// - `u` (unicode)      -> no equivalent; ICU (`NSRegularExpression`'s
    ///   engine) is Unicode-aware without an opt-in
    /// - `d` (hasIndices)   -> no equivalent; changes what a JS `.exec()`
    ///   call returns, not how the pattern matches
    /// - `v` (unicodeSets)  -> no equivalent
    var nsRegularExpressionOptions: NSRegularExpression.Options {
        var options: NSRegularExpression.Options = []
        if flags.contains("i") { options.insert(.caseInsensitive) }
        if flags.contains("m") { options.insert(.anchorsMatchLines) }
        if flags.contains("s") { options.insert(.dotMatchesLineSeparators) }
        return options
    }
}

/// `vscode.d.ts:6486-6496`'s `LineCommentRule`.
public struct LineCommentRule: Sendable, Equatable {
    public let comment: String
    public let noIndent: Bool

    public init(comment: String, noIndent: Bool = false) {
        self.comment = comment
        self.noIndent = noIndent
    }
}

/// `CommentRule.lineComment`'s union (`vscode.d.ts:6501-6512`): a bare
/// string, or a `LineCommentRule` object. The one member of this whole
/// configuration where the declared type does not say which shape actually
/// arrived — both are legal, and both round-trip.
public enum LineComment: Sendable, Equatable {
    case string(String)
    case rule(LineCommentRule)

    static func make(from value: JSValue?) -> LineComment? {
        guard let value, !value.isUndefined, !value.isNull else { return nil }
        if value.isString, let string = value.toString() {
            return .string(string)
        }
        guard value.isObject, let commentValue = value.forProperty("comment"), commentValue.isString,
              let comment = commentValue.toString() else {
            return nil
        }
        let noIndent = value.forProperty("noIndent")?.toBool() ?? false
        return .rule(LineCommentRule(comment: comment, noIndent: noIndent))
    }
}

/// `vscode.d.ts:6501-6512`'s `CommentRule`. Upstream passes `comments`
/// through to the wire verbatim (`extHostLanguageFeatures.ts:3033`) rather
/// than serializing it field by field; this type reads the two fields the
/// `.d.ts` actually declares and has no representation for anything else an
/// extension might have put on the object.
public struct CommentRule: Sendable, Equatable {
    public let lineComment: LineComment?
    public let blockComment: CharacterPair?

    public init(lineComment: LineComment?, blockComment: CharacterPair?) {
        self.lineComment = lineComment
        self.blockComment = blockComment
    }

    static func make(from value: JSValue?) -> CommentRule? {
        guard let value, !value.isUndefined, !value.isNull, value.isObject else { return nil }
        let lineComment = LineComment.make(from: value.forProperty("lineComment"))
        let blockComment = CharacterPair.make(from: value.forProperty("blockComment"))
        guard lineComment != nil || blockComment != nil else { return nil }
        return CommentRule(lineComment: lineComment, blockComment: blockComment)
    }
}

/// `vscode.d.ts:6481`'s `CharacterPair` — `[string, string]` in TypeScript,
/// a struct here because a Swift tuple cannot conform to `Equatable`.
public struct CharacterPair: Sendable, Equatable {
    public let open: String
    public let close: String

    public init(open: String, close: String) {
        self.open = open
        self.close = close
    }

    static func make(from value: JSValue?) -> CharacterPair? {
        guard let value, !value.isUndefined, !value.isNull, value.isArray else { return nil }
        guard let openValue = value.atIndex(0), openValue.isString, let open = openValue.toString(),
              let closeValue = value.atIndex(1), closeValue.isString, let close = closeValue.toString() else {
            return nil
        }
        return CharacterPair(open: open, close: close)
    }

    /// Every element of `value` that reads as a `CharacterPair`, in order.
    /// An element that does not is dropped rather than failing the whole
    /// array — the same permissive rule `LanguageConfiguration.make(from:)`
    /// states for the configuration as a whole.
    static func makeArray(from value: JSValue?) -> [CharacterPair]? {
        guard let value, !value.isUndefined, !value.isNull, value.isArray else { return nil }
        let count = Int(value.forProperty("length")?.toInt32() ?? 0)
        var pairs: [CharacterPair] = []
        pairs.reserveCapacity(max(count, 0))
        for index in 0..<max(count, 0) {
            guard let element = value.atIndex(index), let pair = CharacterPair.make(from: element) else { continue }
            pairs.append(pair)
        }
        return pairs
    }
}

/// `vscode.d.ts:6517-6534`'s `IndentationRule`. The two "decrease"/"increase"
/// patterns are required upstream; the other two are optional, matched here
/// by which properties are non-optional.
public struct IndentationRule: Sendable, Equatable {
    public let decreaseIndentPattern: SerializedRegExp
    public let increaseIndentPattern: SerializedRegExp
    public let indentNextLinePattern: SerializedRegExp?
    public let unIndentedLinePattern: SerializedRegExp?

    public init(
        decreaseIndentPattern: SerializedRegExp, increaseIndentPattern: SerializedRegExp,
        indentNextLinePattern: SerializedRegExp?, unIndentedLinePattern: SerializedRegExp?
    ) {
        self.decreaseIndentPattern = decreaseIndentPattern
        self.increaseIndentPattern = increaseIndentPattern
        self.indentNextLinePattern = indentNextLinePattern
        self.unIndentedLinePattern = unIndentedLinePattern
    }

    /// `nil` — the whole rule, not just a field — when either required
    /// pattern is missing or not `RegExp`-shaped: a Swift `IndentationRule`
    /// cannot represent "decreaseIndentPattern is absent" any other way than
    /// not existing at all.
    static func make(from value: JSValue?) -> IndentationRule? {
        guard let value, !value.isUndefined, !value.isNull else { return nil }
        guard let decrease = SerializedRegExp.make(from: value.forProperty("decreaseIndentPattern")),
              let increase = SerializedRegExp.make(from: value.forProperty("increaseIndentPattern")) else {
            return nil
        }
        return IndentationRule(
            decreaseIndentPattern: decrease,
            increaseIndentPattern: increase,
            indentNextLinePattern: SerializedRegExp.make(from: value.forProperty("indentNextLinePattern")),
            unIndentedLinePattern: SerializedRegExp.make(from: value.forProperty("unIndentedLinePattern")))
    }
}

/// `vscode.d.ts:6539-6558`'s `IndentAction`, raw values quoted from upstream:
/// `None = 0, Indent = 1, IndentOutdent = 2, Outdent = 3`. A raw value that
/// silently disagreed with these would be a defect no compiler catches.
public enum IndentAction: Int, Sendable, Equatable {
    case none = 0
    case indent = 1
    case indentOutdent = 2
    case outdent = 3
}

/// `vscode.d.ts:6563-6576`'s `EnterAction`. `indentAction` is required
/// upstream; `appendText`/`removeText` are optional.
public struct EnterAction: Sendable, Equatable {
    public let indentAction: IndentAction
    public let appendText: String?
    public let removeText: Int?

    public init(indentAction: IndentAction, appendText: String?, removeText: Int?) {
        self.indentAction = indentAction
        self.appendText = appendText
        self.removeText = removeText
    }

    /// `nil` when `indentAction` is absent or not one of the four numbers
    /// `IndentAction` declares — the one required field, so an
    /// unrepresentable `indentAction` makes the whole action unrepresentable,
    /// on the same grounds as `IndentationRule.make(from:)`.
    static func make(from value: JSValue?) -> EnterAction? {
        guard let value, !value.isUndefined, !value.isNull else { return nil }
        guard let indentActionValue = value.forProperty("indentAction"), indentActionValue.isNumber,
              let indentAction = IndentAction(rawValue: Int(indentActionValue.toInt32())) else {
            return nil
        }
        let appendTextValue = value.forProperty("appendText")
        let appendText = (appendTextValue?.isString == true) ? appendTextValue?.toString() : nil
        let removeTextValue = value.forProperty("removeText")
        let removeText = (removeTextValue?.isNumber == true) ? Int(removeTextValue?.toInt32() ?? 0) : nil
        return EnterAction(indentAction: indentAction, appendText: appendText, removeText: removeText)
    }
}

/// `vscode.d.ts:6581-6598`'s `OnEnterRule`. `beforeText` and `action` are
/// required upstream; `afterText`/`previousLineText` are optional.
public struct OnEnterRule: Sendable, Equatable {
    public let beforeText: SerializedRegExp
    public let afterText: SerializedRegExp?
    public let previousLineText: SerializedRegExp?
    public let action: EnterAction

    public init(
        beforeText: SerializedRegExp, afterText: SerializedRegExp?,
        previousLineText: SerializedRegExp?, action: EnterAction
    ) {
        self.beforeText = beforeText
        self.afterText = afterText
        self.previousLineText = previousLineText
        self.action = action
    }

    /// `nil` — the whole rule — when `beforeText` or `action` cannot be
    /// read, on the same grounds `IndentationRule.make(from:)` states for its
    /// own two required patterns.
    static func make(from value: JSValue?) -> OnEnterRule? {
        guard let value, !value.isUndefined, !value.isNull else { return nil }
        guard let beforeText = SerializedRegExp.make(from: value.forProperty("beforeText")),
              let action = EnterAction.make(from: value.forProperty("action")) else {
            return nil
        }
        return OnEnterRule(
            beforeText: beforeText,
            afterText: SerializedRegExp.make(from: value.forProperty("afterText")),
            previousLineText: SerializedRegExp.make(from: value.forProperty("previousLineText")),
            action: action)
    }

    /// Every element of `value` that reads as an `OnEnterRule`, in order,
    /// dropping any that do not — `extHostLanguageFeatures.ts:2981-2988`'s
    /// `_serializeOnEnterRule` has no such fallback because upstream never
    /// meets a malformed rule (TypeScript already refused it); this side of
    /// the bridge has no such guarantee about what JavaScript handed over.
    static func makeArray(from value: JSValue?) -> [OnEnterRule]? {
        guard let value, !value.isUndefined, !value.isNull, value.isArray else { return nil }
        let count = Int(value.forProperty("length")?.toInt32() ?? 0)
        var rules: [OnEnterRule] = []
        rules.reserveCapacity(max(count, 0))
        for index in 0..<max(count, 0) {
            guard let element = value.atIndex(index), let rule = OnEnterRule.make(from: element) else { continue }
            rules.append(rule)
        }
        return rules
    }
}

/// `vscode.d.ts:6603-6620`'s `SyntaxTokenType`, raw values quoted from
/// upstream: `Other = 0, Comment = 1, String = 2, RegEx = 3`.
public enum SyntaxTokenType: Int, Sendable, Equatable {
    case other = 0
    case comment = 1
    case string = 2
    case regEx = 3

    /// Every element of `value` that is one of these four numbers, in order,
    /// dropping anything else. `AutoClosingPair.notIn` is the argument this
    /// exists for.
    static func makeArray(from value: JSValue?) -> [SyntaxTokenType]? {
        guard let value, !value.isUndefined, !value.isNull, value.isArray else { return nil }
        let count = Int(value.forProperty("length")?.toInt32() ?? 0)
        var types: [SyntaxTokenType] = []
        types.reserveCapacity(max(count, 0))
        for index in 0..<max(count, 0) {
            guard let element = value.atIndex(index), element.isNumber,
                  let type = SyntaxTokenType(rawValue: Int(element.toInt32())) else {
                continue
            }
            types.append(type)
        }
        return types
    }
}

/// `vscode.d.ts:6625-6638`'s `AutoClosingPair`. `notIn` is the one member of
/// this whole configuration that is not a straight read: upstream's own wire
/// form is strings (`extHostLanguageFeatures.ts:2994-3000`'s
/// `_serializeAutoClosingPair`), but that is a serialization upstream invents
/// for a wire this bridge does not have — the numeric enum the `.d.ts`
/// actually declares is the whole translation here, not a string encoding of
/// our own.
public struct AutoClosingPair: Sendable, Equatable {
    public let open: String
    public let close: String
    public let notIn: [SyntaxTokenType]?

    public init(open: String, close: String, notIn: [SyntaxTokenType]?) {
        self.open = open
        self.close = close
        self.notIn = notIn
    }

    static func make(from value: JSValue?) -> AutoClosingPair? {
        guard let value, !value.isUndefined, !value.isNull, value.isObject else { return nil }
        guard let openValue = value.forProperty("open"), openValue.isString, let open = openValue.toString(),
              let closeValue = value.forProperty("close"), closeValue.isString, let close = closeValue.toString()
        else {
            return nil
        }
        let notIn = SyntaxTokenType.makeArray(from: value.forProperty("notIn"))
        return AutoClosingPair(open: open, close: close, notIn: notIn)
    }

    static func makeArray(from value: JSValue?) -> [AutoClosingPair]? {
        guard let value, !value.isUndefined, !value.isNull, value.isArray else { return nil }
        let count = Int(value.forProperty("length")?.toInt32() ?? 0)
        var pairs: [AutoClosingPair] = []
        pairs.reserveCapacity(max(count, 0))
        for index in 0..<max(count, 0) {
            guard let element = value.atIndex(index), let pair = AutoClosingPair.make(from: element) else {
                continue
            }
            pairs.append(pair)
        }
        return pairs
    }
}

/// `vscode.d.ts:6644-6739`'s `LanguageConfiguration` — what
/// `vscode.languages.setLanguageConfiguration` accepts, translated into
/// Swift values and nothing more. Applies nothing to any editor (Ruling 8):
/// see `MainThreadLanguages`'s own doc for what happens to a value once it is
/// built.
///
/// **`__electricCharacterSupport` and `__characterPairSupport` are accepted
/// and dropped (Ruling 13).** Upstream reports both through
/// `_apiDeprecation.report(...)` and then passes them to the wire unchanged
/// (`extHostLanguageFeatures.ts:3021-3029`, `:3038-3039`); this bridge has
/// neither a deprecation reporter nor a wire, so a stored value nothing ever
/// reads would be worse than an honest absence. This is a deliberate
/// divergence from upstream, not a description of it — an extension that
/// still sets either member gets silence rather than the warning real VS
/// Code gives it, because there is nowhere here to send that warning.
///
/// **Permissive on shape.** A member present but the wrong shape — a string
/// where an object was expected, an object where an array was expected — is
/// read as absent rather than rejecting the call, matching how upstream's own
/// untyped JavaScript would read the same wrong-shaped property (`undefined`,
/// not a thrown `TypeError`). Every `make(from:)` above and below states this
/// once and applies it consistently rather than re-deciding it per member.
public struct LanguageConfiguration: Sendable, Equatable {
    public let comments: CommentRule?
    public let brackets: [CharacterPair]?
    public let wordPattern: SerializedRegExp?
    public let indentationRules: IndentationRule?
    public let onEnterRules: [OnEnterRule]?
    public let autoClosingPairs: [AutoClosingPair]?

    public init(
        comments: CommentRule?, brackets: [CharacterPair]?, wordPattern: SerializedRegExp?,
        indentationRules: IndentationRule?, onEnterRules: [OnEnterRule]?,
        autoClosingPairs: [AutoClosingPair]?
    ) {
        self.comments = comments
        self.brackets = brackets
        self.wordPattern = wordPattern
        self.indentationRules = indentationRules
        self.onEnterRules = onEnterRules
        self.autoClosingPairs = autoClosingPairs
    }

    /// Builds a `LanguageConfiguration` from the second argument
    /// `vscode.languages.setLanguageConfiguration` was called with. Never
    /// fails — an absent or entirely unusable `configurationValue` reads as a
    /// `LanguageConfiguration` with every member `nil`, matching upstream's
    /// own total absence of shape-checking on this parameter.
    ///
    /// Ruling 12's one refusal (a `wordPattern` that compiles and matches the
    /// empty string) is deliberately not decided here: it needs
    /// `MainThreadLanguages.logger` to report a pattern that fails to
    /// *compile*, and this type has no logger of its own — see
    /// `MainThreadLanguages.wordPatternRefusal(for:)`.
    static func make(from configurationValue: JSValue?) -> LanguageConfiguration {
        LanguageConfiguration(
            comments: CommentRule.make(from: configurationValue?.forProperty("comments")),
            brackets: CharacterPair.makeArray(from: configurationValue?.forProperty("brackets")),
            wordPattern: SerializedRegExp.make(from: configurationValue?.forProperty("wordPattern")),
            indentationRules: IndentationRule.make(from: configurationValue?.forProperty("indentationRules")),
            onEnterRules: OnEnterRule.makeArray(from: configurationValue?.forProperty("onEnterRules")),
            autoClosingPairs: AutoClosingPair.makeArray(
                from: configurationValue?.forProperty("autoClosingPairs")))
    }
}

// MARK: - The extension vocabulary seam

/// Every language identifier this host knows — for
/// `vscode.languages.getLanguages()`.
///
/// A seam rather than a direct reference to `LanguageContributionPoint`:
/// that type is `@MainActor`, live production code, and reaching it from this
/// adaptor would make every test of this member construct the real
/// contribution point. `HostLanguageVocabulary` is the production conformer,
/// composing CodeEditLanguages' built-in catalogue with
/// `LanguageContributionPoint.contributedLanguageIdentifiers`; a test hands in
/// a double instead.
@MainActor
public protocol ExtensionLanguageVocabulary: AnyObject {
    /// Every language identifier this host knows, deduplicated, in a
    /// deterministic order.
    var languageIdentifiers: [String] { get }
}

// MARK: - The store

/// Where `setLanguageConfiguration` registrations live between being minted
/// and being disposed — the store Ruling 9 says must be real: a `Disposable`
/// whose `dispose()` removes nothing from nothing is a method with an empty
/// body that no test can distinguish from a correct one, and this store is
/// what gives `dispose()` something real to undo.
///
/// **Keyed by an opaque handle, not by language id.** Upstream allows more
/// than one configuration per language, each with its own `Disposable`
/// (`extHostLanguageFeatures.ts`'s `_nextHandle()`/`_createDisposable(handle:)`
/// pair, `:3031` and `:3044`) — an id-keyed store could not express two
/// extensions configuring the same language without one silently
/// overwriting the other, and could not implement `dispose()` correctly when
/// they do.
///
/// Holds only the plain Swift values `LanguageConfiguration` is built from —
/// no `JSValue`, no `JSContext` — so nothing here is subject to the
/// no-JSValue-capture rule (`VSCodeAPI.swift:563-572`) in the first place, and
/// an entry left in this store after its owning `MainThreadLanguages` is
/// disposed leaks nothing beyond the entry itself.
///
/// `@MainActor`, matching every other type in this file: nothing here is
/// ever read off the main actor.
@MainActor
public final class LanguageConfigurationStore {

    /// One registration: which language it configures, and the configuration
    /// itself. The handle naming it is the dictionary key below, not a field
    /// here — nothing inside a registration needs to know its own handle.
    public struct Registration: Sendable, Equatable {
        public let languageId: String
        public let configuration: LanguageConfiguration
    }

    private var registrations: [Int: Registration] = [:]
    private var nextHandle = 0

    public init() {}

    /// Adds `configuration` for `languageId` and returns the handle naming
    /// it — what the returned `Disposable`'s `dispose()` block hands back to
    /// `remove(handle:)`.
    @discardableResult
    public func add(languageId: String, configuration: LanguageConfiguration) -> Int {
        let handle = nextHandle
        nextHandle += 1
        registrations[handle] = Registration(languageId: languageId, configuration: configuration)
        return handle
    }

    /// Removes the registration `handle` names. A no-op if it is already
    /// gone, so calling this twice — the wholesale-teardown path and the
    /// per-`Disposable` path can both reach the same handle — is never an
    /// error.
    public func remove(handle: Int) {
        registrations.removeValue(forKey: handle)
    }

    /// Whether `handle` still names a live registration — what a test reads
    /// on either side of a `dispose()` to confirm removal actually happened,
    /// per Ruling 9.
    public func contains(handle: Int) -> Bool {
        registrations[handle] != nil
    }

    /// Every configuration currently registered for `languageId`, oldest
    /// first. Empty when none are — this store has no separate notion of "no
    /// configuration for this language" beyond that.
    public func configurations(forLanguage languageId: String) -> [LanguageConfiguration] {
        registrations.keys.sorted().compactMap { handle in
            let registration = registrations[handle]
            guard registration?.languageId == languageId else { return nil }
            return registration?.configuration
        }
    }

    /// How many registrations are currently live, across every language.
    public var count: Int {
        registrations.count
    }
}

// MARK: - The adaptor

/// The `vscode.languages` adaptor — the fifth namespace's shell. Its first
/// member was `setLanguageConfiguration` (5.6c); this task (5.6d) adds
/// `getLanguages`.
///
/// **Ruling 8: this member validates, translates, stores and hands back. It
/// applies nothing to any editor.** A read-only consumer survey (recorded in
/// `docs/planning/vsc-extensions-stage5-ledger.md`) found nothing in this
/// framework that can receive a language configuration today — no
/// `CodeLanguage` initialiser takes one, `BracketPairs` is a fixed internal
/// enum, and word patterns, indentation rules, on-Enter rules and
/// auto-closing pairs exist nowhere else under any name. `LanguageConfiguration
/// Store` exists so `dispose()` has something real to undo (Ruling 9), not
/// because anything downstream reads it yet — nothing does, and this doc
/// comment is the honest record of that (Ruling 10): this member exists and
/// answers, so it is deliberately **not** routed through
/// `NotImplementedLedger.record(memberPath:extensionIdentifier:)`, which
/// would misreport it as absent.
///
/// **5.6a and 5.6b add further `vscode.languages` members to this same
/// class** rather than each building their own namespace shell — this type
/// is that shell, built to be added to.
///
/// **One instance per extension**, mirroring `MainThreadCommands` and
/// `MainThreadWorkspace`. `store` may be shared across instances (a test
/// constructs one and hands it to several adaptors to read its state
/// directly); `ownedHandles` is what keeps `dispose()` from removing another
/// instance's registrations, the same ownership boundary
/// `MainThreadCommands.ownedCallbacks` draws for `CommandRegistry`.
///
/// `@MainActor` for the reason every adaptor in this directory is: `JSValue`
/// is not `Sendable`, and every block below runs on the thread that made the
/// call, which for this host is always the main actor.
@MainActor
public final class MainThreadLanguages {

    /// Where every registration this adaptor makes actually lives. Not
    /// defaulted: a caller that forgot to pass the host's real store would
    /// silently get a private one nothing else can read, defeating the whole
    /// reason `MainThreadWorkspace.notImplementedLedger` is injected the same
    /// way (`MainThreadWorkspace.swift:180`) — so a test, or a future report,
    /// can construct a store, hand it in, and read it back.
    private let store: LanguageConfigurationStore

    /// The handles this adaptor itself has added to `store` — the ownership
    /// record `dispose()` walks, mirroring `MainThreadCommands.ownedCallbacks`
    /// for the same reason: `store` is not a second table this adaptor keeps
    /// to itself, so knowing what it added is the only way to tear down only
    /// its own registrations.
    private var ownedHandles: Set<Int> = []

    /// Answers `vscode.languages.getLanguages()`. Not defaulted, for the same
    /// reason `store` is not: a caller that forgot to pass the host's real
    /// vocabulary would silently get whatever a default reads as, defeating
    /// the whole reason this is injected rather than reached through a global.
    private let vocabulary: ExtensionLanguageVocabulary

    /// - Parameters:
    ///   - store: Where registrations live. Not defaulted — see this
    ///     property's own doc for why a silent default would be the wrong
    ///     failure mode.
    ///   - vocabulary: Answers `getLanguages()`. Not defaulted, for the same
    ///     reason.
    public init(store: LanguageConfigurationStore, vocabulary: ExtensionLanguageVocabulary) {
        self.store = store
        self.vocabulary = vocabulary
    }

    // MARK: - vscode.languages.getLanguages

    /// `implementation` for `vscode.languages.getLanguages`.
    ///
    /// Rejects rather than raises on a torn-down adaptor: `vscode.d.ts:14733`
    /// declares this member `Thenable<string[]>`, not a value, so
    /// `VSCodeAPI.member`'s own doc (`VSCodeAPI.swift:91-101`) says a
    /// torn-down answer here must be a rejected promise, the same choice
    /// `MainThreadCommands.getCommands` makes for the same reason.
    public private(set) lazy var getLanguages: Any = VSCodeAPI.member(
        "vscode.languages.getLanguages", of: self, whenTornDown: .rejectedPromise
    ) { $0.handleGetLanguages() }

    /// A synchronous read of `vocabulary`'s registry, wrapped in an
    /// already-resolved promise: this host has no process boundary to
    /// amortize, unlike upstream's push-and-cache
    /// (`extHostLanguages.ts`'s `_languageIds`/`$acceptLanguageIds`), so there
    /// is nothing to cache and every call reads `vocabulary` fresh. Takes no
    /// arguments and validates nothing — `vscode.d.ts:14733` declares no
    /// parameters, and a member that refused an extra argument would refuse
    /// something upstream accepts.
    private func handleGetLanguages() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        return VSCodeAPI.resolvedPromise(with: vocabulary.languageIdentifiers, in: context)
    }

    // MARK: - vscode.languages.setLanguageConfiguration

    /// `implementation` for `vscode.languages.setLanguageConfiguration`,
    /// handed to
    /// `ExtensionHost.defineVSCodeMember(namespacePath:name:implementation:)`
    /// as-is.
    ///
    /// Raises rather than rejects on a torn-down adaptor: `vscode.d.ts:15301`
    /// declares this member `Disposable`, not `Thenable` — it answers
    /// synchronously, so `VSCodeAPI.member`'s own doc
    /// (`VSCodeAPI.swift:47-54`) says a torn-down answer here must be a raised
    /// exception, the same choice `MainThreadCommands.registerCommand` and
    /// `MainThreadWorkspace.getWorkspaceFolder` make for the same reason.
    public private(set) lazy var setLanguageConfiguration: Any = VSCodeAPI.member(
        "vscode.languages.setLanguageConfiguration", of: self, whenTornDown: .raisedException
    ) { $0.handleSetLanguageConfiguration() }

    /// Four steps, mirroring `extHostLanguageFeatures.ts:3006-3045` with the
    /// two upstream steps Ruling 8 rules out (setting the word definition,
    /// reporting the two deprecated members) omitted rather than stubbed:
    /// validate the arguments, translate the configuration, store it, and
    /// hand back a `Disposable` that removes exactly this registration.
    private func handleSetLanguageConfiguration() -> JSValue? {
        guard let context = JSContext.current() else { return nil }
        let arguments = VSCodeAPI.currentArguments()

        guard let languageValue = arguments.first, languageValue.isString,
              let languageId = languageValue.toString() else {
            return VSCodeAPI.raise("setLanguageConfiguration requires a string language id.", in: context)
        }

        let configurationValue = arguments.count > 1 ? arguments[1] : nil
        let configuration = LanguageConfiguration.make(from: configurationValue)

        // Ruling 12's one refusal. Everything else about `configuration` was
        // already made permissive by `LanguageConfiguration.make(from:)`.
        if let refusal = MainThreadLanguages.wordPatternRefusal(for: configuration.wordPattern) {
            return VSCodeAPI.raise(refusal, in: context)
        }

        let handle = store.add(languageId: languageId, configuration: configuration)
        ownedHandles.insert(handle)
        return VSCodeAPI.disposable(in: context) { [weak self] in
            self?.store.remove(handle: handle)
            self?.ownedHandles.remove(handle)
        }
    }

    /// Ruling 12's one refusal — the message to raise, or `nil` when there is
    /// nothing to refuse. Two branches, deliberately not three:
    ///
    /// - No `wordPattern` at all: nothing to check, `nil`.
    /// - A `wordPattern` that does not **compile** under
    ///   `NSRegularExpression`: **not** a refusal. V8 (upstream's engine) and
    ///   ICU (`NSRegularExpression`'s) are not the same regex engine, so a
    ///   pattern real VS Code accepts can fail to compile here. Ruling 12 is
    ///   explicit that inventing a second refusal for this would reject
    ///   configurations upstream itself allows — this branch is stored
    ///   unvalidated and logged instead.
    /// - A `wordPattern` that compiles **and** matches the empty string: the
    ///   one refusal, reproducing
    ///   `extHostLanguageFeatures.ts:3009-3012`'s message shape.
    private static func wordPatternRefusal(for wordPattern: SerializedRegExp?) -> String? {
        guard let wordPattern else { return nil }
        let compiled: NSRegularExpression
        do {
            compiled = try NSRegularExpression(
                pattern: wordPattern.pattern, options: wordPattern.nsRegularExpressionOptions)
        } catch {
            logger.error(
                """
                wordPattern '\(wordPattern.jsRepresentation, privacy: .public)' does not compile under \
                NSRegularExpression (\(error.localizedDescription, privacy: .public)); stored unvalidated \
                rather than refused, per Ruling 12
                """)
            return nil
        }
        let emptyRange = NSRange(location: 0, length: 0)
        guard compiled.firstMatch(in: "", options: [], range: emptyRange) != nil else {
            return nil
        }
        return "Invalid language configuration: wordPattern '\(wordPattern.jsRepresentation)' " +
            "is not allowed to match the empty string."
    }

    // MARK: - Teardown

    /// Removes every configuration this adaptor added to `store`, and clears
    /// `ownedHandles`.
    ///
    /// **Does not touch `store` itself, and does not remove any other
    /// adaptor's registrations from it.** `store` may be shared across
    /// `MainThreadLanguages` instances — that is the whole reason it is
    /// injected rather than owned — so a wholesale teardown here is not a
    /// licence to remove somebody else's configuration, the same boundary
    /// `MainThreadCommands.dispose()` draws around `CommandRegistry`. Unlike
    /// `MainThreadCommands`, leaving a registration behind after this call
    /// leaks nothing beyond the entry itself: nothing stored here is a
    /// `JSValue` or holds one, so no `JSContext` is kept alive by a forgotten
    /// `dispose()`.
    public func dispose() {
        for handle in ownedHandles {
            store.remove(handle: handle)
        }
        ownedHandles.removeAll()
    }
}

extension MainThreadLanguages: Loggable {

    /// The adaptor's own log destination, matching `MainThreadCommands` and
    /// `MainThreadWorkspace`.
    public static nonisolated let logger = makeLogger()
}
