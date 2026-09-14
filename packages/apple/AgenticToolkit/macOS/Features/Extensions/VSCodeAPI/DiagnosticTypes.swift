//
//  DiagnosticTypes.swift
//  AgenticToolkit
//

import Foundation
import JavaScriptCore
import OSLog
import AgenticToolkitCore

/// `vscode.DiagnosticSeverity`, `vscode.DiagnosticTag`,
/// `vscode.DiagnosticRelatedInformation` and `vscode.Diagnostic` — task
/// 5.6a-ii, ledger Ruling 23's second slice. `vscode.Location` is the fifth
/// declaration this task adds, but it lives in `TextGeometry.swift` instead:
/// see that file's header for why — `Location`'s constructor needs `Range`'s
/// constructor, which only exists inside `TextGeometry.swift`'s own
/// `evaluateScript`, and putting `Location` in a file named for diagnostics
/// would make every later task that only needs geometry import the wrong
/// thing.
///
/// Declared-surface line numbers below are against the pinned VS Code commit
/// `3addbda66f9e80c3ed1b943822ab823bb6747b02` — `vscode.d.ts:7024-7046`
/// (`DiagnosticSeverity`), `:7053-7072` (`DiagnosticRelatedInformation`),
/// `:7077-7096` (`DiagnosticTag`) and `:7102-7161` (`Diagnostic`) — whose copy
/// at `scratchpad/upstream/vscode.d.ts` hashes to
/// `4624902099d3eeb466fbb2422c09690143120e94a4cb70047c41f92058eae889`
/// (verified against `MANIFEST.txt` on 2026-09-13, the same day this file was
/// written). Two behaviors below come from the *implementation*, not from
/// `vscode.d.ts`'s prose — measured against
/// `scratchpad/upstream/extHostTypes.diagnostic.ts`
/// (`9cdd4cb0cfae247de2d7e641be59b8bde0ca82ad24950fa40d43d6ab803dd990`),
/// verified the same day, at the same pinned commit:
///
///   1. **The constructor throws `TypeError` when `range` is not a
///      range, or when `message` is falsy** (`diagnostic.ts:70-75`) — neither
///      check is stated in `vscode.d.ts`'s own prose for `Diagnostic`.
///   2. **A missing third argument defaults `severity` to
///      `DiagnosticSeverity.Error`, which is `0`** (`diagnostic.ts:69`;
///      `vscode.d.ts:7158`'s doc, `"default is {@link
///      DiagnosticSeverity.Error error}"`) — distinguished here from an
///      explicit `0` by `typeof severity === 'undefined'`, not by
///      `severity || DiagnosticSeverity.Error`, because the latter would
///      silently replace an explicitly passed `0` with itself only by
///      accident and would replace a hypothetical falsy-but-valid severity
///      incorrectly in general.
///
/// **`DiagnosticSeverity` and `DiagnosticTag` mirror `tsc`'s own compiled
/// enum shape**: both a forward mapping (`DiagnosticSeverity.Error === 0`)
/// and a reverse one (`DiagnosticSeverity[0] === "Error"`), exactly what a
/// real `enum DiagnosticSeverity { Error = 0, ... }` compiles to
/// (`diagnostic.ts:17-22`, `:12-15`). An extension built against
/// `vscode.d.ts` may legally read either direction, so leaving the reverse
/// mapping out would be an incomplete declared surface, not a harmless
/// simplification. Both are frozen plain objects, not classes — `vscode.d.ts`
/// declares them as `enum`, not `class`, and nothing here constructs an
/// instance of either.
///
/// **`Diagnostic`'s optional properties (`source`, `code`,
/// `relatedInformation`, `tags`) are left entirely unassigned by the
/// constructor when not supplied — never assigned `undefined`** —
/// matching `diagnostic.ts:76-78`, whose constructor only ever assigns
/// `range`, `message` and `severity`. `'source' in diagnostic` is `false`
/// until an extension sets it, exactly as real VS Code behaves; an
/// implementation that instead wrote `this.source = source;` unconditionally
/// would make that check always `true`.
///
/// **Neither `Diagnostic` nor `DiagnosticRelatedInformation` freezes its own
/// instances**, unlike `Position`/`Range` (`TextGeometry.swift`'s header).
/// None of `Diagnostic`'s seven properties, nor either of
/// `DiagnosticRelatedInformation`'s two, is `readonly` in `vscode.d.ts`, and
/// real extensions routinely set `diagnostic.source`/`.code`/`.tags` after
/// construction — the same reasoning `TextGeometry.swift` gives for
/// `Location`. Only the class objects and prototypes are frozen, inside the
/// same evaluation that builds them.
///
/// **`Diagnostic`'s constructor cannot check `range instanceof Range`.**
/// `Range` is a local variable inside `TextGeometry.swift`'s own
/// `evaluateScript` closure, not a global this file's separately-evaluated
/// source has any name bound to. Rather than bridge a cross-evaluation
/// identity check, this file validates `range` the same structural way
/// `TextGeometry.swift`'s own `Range.prototype.contains` already dispatches
/// on its `positionOrRange` argument: does the value have `.start`/`.end`
/// properties shaped like positions. A real `Range` instance satisfies that
/// check via its own getters, the same as any range-shaped literal would —
/// this check is a validity gate, not an identity check, exactly as
/// upstream's own `Range.isRange` (`diagnostic.ts:70`) is for the same
/// constructor.
extension VSCodeAPI {

    // MARK: - Installing the classes

    /// The global `installDiagnosticTypes(in:)` caches the container object
    /// under, once per context — `TextGeometry.swift`'s
    /// `textGeometryGlobalName` and `Uri.swift`'s `uriClassGlobalName`,
    /// generalized the same way both of those already are.
    private static nonisolated let diagnosticGlobalName = "__vscodeDiagnosticTypesClasses"

    /// `DiagnosticSeverity`, `DiagnosticTag`, `DiagnosticRelatedInformation`
    /// and `Diagnostic`'s own source, evaluated at most once per `JSContext`.
    ///
    /// ES5 idiom throughout — `var`, `function`, explicit prototypes, no
    /// `class`/`let`/arrow functions — matching `extension-runtime.js`,
    /// `Uri.swift` and `TextGeometry.swift`.
    private static nonisolated let diagnosticClassesSource = """
    (function () {
        'use strict';
        try {
            // `Range.isRange` (`TextGeometry.swift`'s own `rangeIsRangeLike`),
            // reproduced structurally here because `Range` itself is not a
            // name this evaluation has — see this file's header.
            function diagnosticPositionLooksReal(value) {
                return !!value
                    && typeof value.line === 'number'
                    && typeof value.character === 'number';
            }

            function diagnosticRangeLooksReal(value) {
                return !!value
                    && diagnosticPositionLooksReal(value.start)
                    && diagnosticPositionLooksReal(value.end);
            }

            // vscode.d.ts:7024-7046; diagnostic.ts:17-22. `tsc` compiles a
            // numeric enum to an object carrying both directions — chosen
            // here to mirror that (see this file's header) rather than the
            // forward-only mapping a hand-written object would default to.
            // `Error` is zero, which is also what a missing-argument bug
            // produces — this file's tests check all four values by number
            // for exactly that reason.
            var DiagnosticSeverity = {
                Error: 0,
                Warning: 1,
                Information: 2,
                Hint: 3
            };
            DiagnosticSeverity[0] = 'Error';
            DiagnosticSeverity[1] = 'Warning';
            DiagnosticSeverity[2] = 'Information';
            DiagnosticSeverity[3] = 'Hint';

            // vscode.d.ts:7077-7096; diagnostic.ts:12-15. Same reverse-mapping
            // choice as `DiagnosticSeverity`. There is no zero:
            // `Unnecessary` is `1`, not `0` — an implementation that indexed
            // an array by tag value starting at zero would disagree with
            // this.
            var DiagnosticTag = {
                Unnecessary: 1,
                Deprecated: 2
            };
            DiagnosticTag[1] = 'Unnecessary';
            DiagnosticTag[2] = 'Deprecated';

            // vscode.d.ts:7053-7072; diagnostic.ts:24-56. The upstream
            // constructor performs no validation beyond assignment — its
            // `static is`/`isEqual` do the checking elsewhere — so this one
            // does not either.
            function DiagnosticRelatedInformation(location, message) {
                this.location = location;
                this.message = message;
            }

            // vscode.d.ts:7102-7161; diagnostic.ts:58-107. See this file's
            // header for the constructor's two implementation-only
            // behaviors (validation, and the `severity` default) and for why
            // the optional properties below are never assigned here.
            function Diagnostic(range, message, severity) {
                if (!diagnosticRangeLooksReal(range)) {
                    throw new TypeError('range must be set');
                }
                if (!message) {
                    throw new TypeError('message must be set');
                }
                this.range = range;
                this.message = message;
                this.severity = typeof severity === 'undefined'
                    ? DiagnosticSeverity.Error
                    : severity;
                // `source`, `code`, `relatedInformation` and `tags` are
                // deliberately never assigned here — see this file's header.
            }

            // Frozen after every member is attached, inside the same
            // evaluation that built them — `Uri.swift:239-246`'s reasoning
            // (at submodule commit `c83bd261`) applied to all four
            // declarations at once: there is no window between any of them
            // existing and its being locked down.
            // Neither `DiagnosticRelatedInformation` nor `Diagnostic` freezes
            // its own *instances* — see this file's header for why.
            Object.freeze(DiagnosticSeverity);
            Object.freeze(DiagnosticTag);
            Object.freeze(DiagnosticRelatedInformation.prototype);
            Object.freeze(DiagnosticRelatedInformation);
            Object.freeze(Diagnostic.prototype);
            Object.freeze(Diagnostic);

            var result = {
                DiagnosticSeverity: DiagnosticSeverity,
                DiagnosticTag: DiagnosticTag,
                DiagnosticRelatedInformation: DiagnosticRelatedInformation,
                Diagnostic: Diagnostic
            };

            try {
                Object.defineProperty(globalThis, '\(diagnosticGlobalName)', {
                    value: result,
                    writable: false,
                    enumerable: false,
                    configurable: false
                });
            } catch (ignored) {
                // Caching is an optimisation, exactly as in
                // `textGeometryClassesSource`: a context that refuses this
                // define still gets a correct, working `result` back for
                // this one call.
            }
            return result;
        } catch (error) {
            return { installedError: error && error.message ? error.message : 'unknown error' };
        }
    })()
    """

    /// `vscode.DiagnosticSeverity`, `vscode.DiagnosticTag`,
    /// `vscode.DiagnosticRelatedInformation` and `vscode.Diagnostic` for
    /// `context`, evaluating the source the first time and reading the
    /// cached container back afterwards — `installTextGeometryClasses(in:)`'s
    /// exact pattern, generalized from three declarations read off one
    /// container object to four.
    ///
    /// Calling this twice on one context answers the **same** four objects
    /// both times — the global cache, not a re-evaluation — which is what
    /// makes a `Diagnostic` built from the first call's `Diagnostic` still
    /// `instanceof` the class the second call returns.
    ///
    /// Returns `nil` on failure, `installTextGeometryClasses(in:)`'s own
    /// failure mode: a context that cannot host these yet is not fatal to
    /// activation, and `vscode.DiagnosticSeverity`/`vscode.DiagnosticTag`/
    /// `vscode.DiagnosticRelatedInformation`/`vscode.Diagnostic` simply stay
    /// the shim's not-implemented stub.
    public static func installDiagnosticTypes(
        in context: JSContext
    ) -> [String: JSValue]? {
        let container: JSValue
        if let cached = context.objectForKeyedSubscript(diagnosticGlobalName), cached.isObject {
            container = cached
        } else {
            guard let created = context.evaluateScript(diagnosticClassesSource),
                  created.isObject else {
                logger.error(
                    """
                    Could not install the 'vscode.DiagnosticSeverity'/ \
                    'vscode.DiagnosticTag'/'vscode.DiagnosticRelatedInformation'/ \
                    'vscode.Diagnostic' classes in context \
                    '\(name(of: context), privacy: .public)'; they stay the \
                    shim's not-implemented stub
                    """)
                return nil
            }
            if let installError = created.forProperty("installedError"), !installError.isUndefined {
                logger.error(
                    """
                    Could not install the 'vscode.DiagnosticSeverity'/ \
                    'vscode.DiagnosticTag'/'vscode.DiagnosticRelatedInformation'/ \
                    'vscode.Diagnostic' classes in context \
                    '\(name(of: context), privacy: .public)': \
                    '\(installError.toString() ?? "unknown error", privacy: .public)'; \
                    they stay the shim's not-implemented stub
                    """)
                return nil
            }
            container = created
        }

        guard let severityClass = container.forProperty("DiagnosticSeverity"), severityClass.isObject,
              let tagClass = container.forProperty("DiagnosticTag"), tagClass.isObject,
              let relatedInformationClass = container.forProperty("DiagnosticRelatedInformation"),
              relatedInformationClass.isObject,
              let diagnosticClass = container.forProperty("Diagnostic"), diagnosticClass.isObject else {
            logger.error(
                """
                The 'vscode' diagnostic-types container in context \
                '\(name(of: context), privacy: .public)' is missing one of \
                'DiagnosticSeverity', 'DiagnosticTag', \
                'DiagnosticRelatedInformation' or 'Diagnostic'; all four \
                stay the shim's not-implemented stub
                """)
            return nil
        }
        return [
            "DiagnosticSeverity": severityClass,
            "DiagnosticTag": tagClass,
            "DiagnosticRelatedInformation": relatedInformationClass,
            "Diagnostic": diagnosticClass
        ]
    }

    // MARK: - Swift mirrors

    /// Swift mirror of `vscode.DiagnosticSeverity` (`vscode.d.ts:7024-7046`).
    /// A plain `Int` enum, not a reader/writer pair: every value this can
    /// hold is a JS number, not an object with its own identity to forge, so
    /// there is nothing here for `isInstance(of:)` to guard the way
    /// `location(from:in:)` guards `Location`.
    public enum ExtensionDiagnosticSeverity: Int, Sendable, Equatable {
        case error = 0
        case warning = 1
        case information = 2
        case hint = 3
    }

    /// Swift mirror of `vscode.DiagnosticTag` (`vscode.d.ts:7077-7096`). Note
    /// there is no `case` for `0` — `vscode.d.ts` does not declare one, and
    /// `ExtensionDiagnosticTag(rawValue: 0)` answers `nil`, the same way an
    /// out-of-range severity would.
    public enum ExtensionDiagnosticTag: Int, Sendable, Equatable {
        case unnecessary = 1
        case deprecated = 2
    }

    /// Swift mirror of a `vscode.Diagnostic`'s `code` when it is the scalar
    /// half of `vscode.d.ts:7129-7140`'s three-shape union — a bare `string`
    /// or a bare `number` — and also of the `value` field inside the object
    /// form, which carries the identical two-shape choice one level down.
    public enum ExtensionDiagnosticCodeValue: Sendable, Equatable {
        case string(String)
        case number(Double)
    }

    /// Swift mirror of the full three-shape `code?: string | number | {
    /// value: string | number; target: Uri }` union (`vscode.d.ts:7129-7140`).
    /// `.scalar` covers the bare `string`/`number` forms; `.link` covers the
    /// object form, whose `target` is a real `Uri` and therefore goes through
    /// `url(from:in:)`/`uriValue(for:in:)`, not a plain string.
    public enum ExtensionDiagnosticCode: Sendable, Equatable {
        case scalar(ExtensionDiagnosticCodeValue)
        case link(value: ExtensionDiagnosticCodeValue, target: URL)
    }

    /// Swift mirror of a `vscode.DiagnosticRelatedInformation`
    /// (`vscode.d.ts:7053-7072`): a `Location` paired with the message that
    /// explains it.
    public struct ExtensionDiagnosticRelatedInformation: Sendable, Equatable {
        public let location: ExtensionLocation
        public let message: String

        public init(location: ExtensionLocation, message: String) {
            self.location = location
            self.message = message
        }
    }

    /// Swift mirror of a `vscode.Diagnostic` (`vscode.d.ts:7102-7161`).
    /// `source`, `code`, `relatedInformation` and `tags` are all `nil` when
    /// the corresponding JS property is absent — see this file's header for
    /// why the JS constructor never assigns them `undefined` instead, which
    /// is what makes "absent" and "`nil`" the same case here rather than two
    /// that need distinguishing.
    public struct ExtensionDiagnostic: Sendable, Equatable {
        public let range: ExtensionRange
        public let message: String
        public let severity: ExtensionDiagnosticSeverity
        public let source: String?
        public let code: ExtensionDiagnosticCode?
        public let relatedInformation: [ExtensionDiagnosticRelatedInformation]?
        public let tags: [ExtensionDiagnosticTag]?

        public init(
            range: ExtensionRange,
            message: String,
            severity: ExtensionDiagnosticSeverity = .error,
            source: String? = nil,
            code: ExtensionDiagnosticCode? = nil,
            relatedInformation: [ExtensionDiagnosticRelatedInformation]? = nil,
            tags: [ExtensionDiagnosticTag]? = nil
        ) {
            self.range = range
            self.message = message
            self.severity = severity
            self.source = source
            self.code = code
            self.relatedInformation = relatedInformation
            self.tags = tags
        }
    }

    // MARK: - Swift ↔ JS bridging

    /// Reads `value` back into an `ExtensionDiagnosticCode` if it is a
    /// string, a number, or an object shaped like the third union member —
    /// answers `nil` for anything else, without raising. The object form is
    /// not one of this file's installed classes (`vscode.d.ts` declares it as
    /// an inline object type, not a named class), so there is no
    /// `isInstance(of:)` to check here; `target` still goes through
    /// `url(from:in:)`, which is itself not duck-typed.
    private static func diagnosticCode(
        from value: JSValue, in context: JSContext
    ) -> ExtensionDiagnosticCode? {
        if value.isString {
            guard let string = value.toString() else { return nil }
            return .scalar(.string(string))
        }
        if value.isNumber {
            return .scalar(.number(value.toDouble()))
        }
        guard value.isObject,
              let valueProperty = value.forProperty("value"),
              let codeValue = diagnosticCodeValue(from: valueProperty),
              let targetProperty = value.forProperty("target"),
              let target = url(from: targetProperty, in: context) else {
            return nil
        }
        return .link(value: codeValue, target: target)
    }

    private static func diagnosticCodeValue(
        from value: JSValue
    ) -> ExtensionDiagnosticCodeValue? {
        if value.isString {
            guard let string = value.toString() else { return nil }
            return .string(string)
        }
        if value.isNumber {
            return .number(value.toDouble())
        }
        return nil
    }

    /// Builds the JS value for an `ExtensionDiagnosticCode` — the reverse of
    /// `diagnosticCode(from:in:)`. The object form is a plain object literal,
    /// not a constructed class instance, matching `vscode.d.ts`'s own inline
    /// object type for it.
    private static func diagnosticCodeJSValue(
        for code: ExtensionDiagnosticCode, in context: JSContext
    ) -> JSValue? {
        switch code {
        case .scalar(let scalar):
            return diagnosticCodeValueJSValue(for: scalar, in: context)
        case .link(let value, let target):
            guard let valueJSValue = diagnosticCodeValueJSValue(for: value, in: context),
                  let targetJSValue = uriValue(for: target, in: context),
                  let result = JSValue(newObjectIn: context) else {
                return nil
            }
            result.setValue(valueJSValue, forProperty: "value")
            result.setValue(targetJSValue, forProperty: "target")
            return result
        }
    }

    private static func diagnosticCodeValueJSValue(
        for value: ExtensionDiagnosticCodeValue, in context: JSContext
    ) -> JSValue? {
        switch value {
        case .string(let string):
            return JSValue(object: string, in: context)
        case .number(let number):
            return JSValue(double: number, in: context)
        }
    }

    /// Reads a JS array of `DiagnosticRelatedInformation` instances into
    /// `[ExtensionDiagnosticRelatedInformation]`, answering `nil` — not a
    /// partial array — if any element fails
    /// `diagnosticRelatedInformation(from:in:)`'s own instance check.
    private static func diagnosticRelatedInformationArray(
        from value: JSValue, in context: JSContext
    ) -> [ExtensionDiagnosticRelatedInformation]? {
        guard let lengthValue = value.forProperty("length"), lengthValue.isNumber else { return nil }
        let count = Int(lengthValue.toInt32())
        var result: [ExtensionDiagnosticRelatedInformation] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            guard let element = value.atIndex(index),
                  let decoded = diagnosticRelatedInformation(from: element, in: context) else {
                return nil
            }
            result.append(decoded)
        }
        return result
    }

    /// Reads a JS array of `DiagnosticTag` numbers into
    /// `[ExtensionDiagnosticTag]`, preserving order — answering `nil`, not a
    /// partial array, if any element is not a number or is out of the
    /// declared enum's range (see `ExtensionDiagnosticTag`: there is no `0`).
    private static func diagnosticTagArray(
        from value: JSValue, in context: JSContext
    ) -> [ExtensionDiagnosticTag]? {
        guard let lengthValue = value.forProperty("length"), lengthValue.isNumber else { return nil }
        let count = Int(lengthValue.toInt32())
        var result: [ExtensionDiagnosticTag] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            guard let element = value.atIndex(index), element.isNumber,
                  let tag = ExtensionDiagnosticTag(rawValue: Int(element.toInt32())) else {
                return nil
            }
            result.append(tag)
        }
        return result
    }

    /// Reads `value` back into an `ExtensionDiagnosticRelatedInformation` if
    /// — and only if — it is a real `vscode.DiagnosticRelatedInformation`
    /// instance, the same `isInstance(of:)`-before-properties discipline
    /// `location(from:in:)` (`TextGeometry.swift`) and `url(from:in:)`
    /// (`Uri.swift:335-358` at submodule commit `c83bd261`) both use: a
    /// `{ location, message }` object literal that merely looks like one
    /// answers `nil` rather than having its properties read.
    public static func diagnosticRelatedInformation(
        from value: JSValue, in context: JSContext
    ) -> ExtensionDiagnosticRelatedInformation? {
        guard let classes = installDiagnosticTypes(in: context),
              let relatedInformationClass = classes["DiagnosticRelatedInformation"],
              value.isInstance(of: relatedInformationClass) else {
            return nil
        }
        guard let locationProperty = value.forProperty("location"),
              let decodedLocation = location(from: locationProperty, in: context),
              let messageProperty = value.forProperty("message"), messageProperty.isString,
              let message = messageProperty.toString() else {
            return nil
        }
        return ExtensionDiagnosticRelatedInformation(location: decodedLocation, message: message)
    }

    /// Builds a real `vscode.DiagnosticRelatedInformation` instance in
    /// `context` for `relatedInformation` — the reverse of
    /// `diagnosticRelatedInformation(from:in:)`. Goes through the real
    /// constructor rather than a bag of properties, so the result is
    /// genuinely `instanceof vscode.DiagnosticRelatedInformation`.
    public static func diagnosticRelatedInformationValue(
        for relatedInformation: ExtensionDiagnosticRelatedInformation, in context: JSContext
    ) -> JSValue? {
        guard let classes = installDiagnosticTypes(in: context),
              let relatedInformationClass = classes["DiagnosticRelatedInformation"] else {
            return nil
        }
        guard let locationJSValue = locationValue(for: relatedInformation.location, in: context) else {
            return nil
        }
        guard let result = relatedInformationClass.construct(
            withArguments: [locationJSValue, relatedInformation.message]
        ), !result.isUndefined, !result.isNull else {
            return nil
        }
        return result
    }

    /// Reads `value` back into an `ExtensionDiagnostic` if — and only if —
    /// it is a real `vscode.Diagnostic` instance, the same
    /// `isInstance(of:)`-before-properties discipline every reader in this
    /// file and `TextGeometry.swift` uses. `source`, `code`,
    /// `relatedInformation` and `tags` each read back `nil` only when the
    /// property is genuinely **absent** (`isUndefined`), matching the
    /// constructor's own "never assigned" behaviour (see this file's
    /// header) — a property that is *present* but fails to decode (wrong
    /// type, an out-of-union `code`, a malformed element inside
    /// `relatedInformation`/`tags`) is refused, not coerced: the whole call
    /// answers `nil` rather than silently dropping just that field (fix
    /// round 1, F3).
    public static func diagnostic(
        from value: JSValue, in context: JSContext
    ) -> ExtensionDiagnostic? {
        guard let classes = installDiagnosticTypes(in: context),
              let diagnosticClass = classes["Diagnostic"],
              value.isInstance(of: diagnosticClass) else {
            return nil
        }
        guard let rangeProperty = value.forProperty("range"),
              let decodedRange = range(from: rangeProperty, in: context),
              let messageProperty = value.forProperty("message"), messageProperty.isString,
              let message = messageProperty.toString(),
              let severityProperty = value.forProperty("severity"), severityProperty.isNumber,
              let severity = ExtensionDiagnosticSeverity(rawValue: Int(severityProperty.toInt32())) else {
            return nil
        }

        // Each of the four blocks below distinguishes *absent* from
        // *present-but-undecodable* (fix round 1, F3) — the constructor
        // above never assigns these four unless an extension sets them
        // (this file's header), so `isUndefined` alone already tells the
        // two cases apart cleanly: an undecodable-but-present value must
        // refuse the whole diagnostic instead of quietly reading back as if
        // the property were never set, matching `diagnosticRelatedInformationArray`'s
        // and `diagnosticTagArray`'s own "nil, not a partial array" contract
        // one level up.
        var source: String?
        if let sourceProperty = value.forProperty("source"), !sourceProperty.isUndefined {
            guard sourceProperty.isString, let decodedSource = sourceProperty.toString() else {
                return nil
            }
            source = decodedSource
        }

        var code: ExtensionDiagnosticCode?
        if let codeProperty = value.forProperty("code"), !codeProperty.isUndefined {
            guard let decodedCode = diagnosticCode(from: codeProperty, in: context) else {
                return nil
            }
            code = decodedCode
        }

        var relatedInformation: [ExtensionDiagnosticRelatedInformation]?
        if let relatedInformationProperty = value.forProperty("relatedInformation"),
           !relatedInformationProperty.isUndefined {
            guard relatedInformationProperty.isObject,
                  let decodedRelatedInformation = diagnosticRelatedInformationArray(
                      from: relatedInformationProperty, in: context
                  ) else {
                return nil
            }
            relatedInformation = decodedRelatedInformation
        }

        var tags: [ExtensionDiagnosticTag]?
        if let tagsProperty = value.forProperty("tags"), !tagsProperty.isUndefined {
            guard tagsProperty.isObject,
                  let decodedTags = diagnosticTagArray(from: tagsProperty, in: context) else {
                return nil
            }
            tags = decodedTags
        }

        return ExtensionDiagnostic(
            range: decodedRange,
            message: message,
            severity: severity,
            source: source,
            code: code,
            relatedInformation: relatedInformation,
            tags: tags
        )
    }

    /// Builds a real `vscode.Diagnostic` instance in `context` for
    /// `diagnostic` — the reverse of `diagnostic(from:in:)`. Goes through the
    /// three-argument constructor and then assigns the optional properties
    /// directly, exactly the two-step sequence real extension code uses
    /// (`new Diagnostic(range, message)` followed by
    /// `diagnostic.source = '…'`), which `Diagnostic`'s own instances allow
    /// because they are not frozen — see this file's header.
    public static func diagnosticValue(
        for diagnostic: ExtensionDiagnostic, in context: JSContext
    ) -> JSValue? {
        guard let classes = installDiagnosticTypes(in: context),
              let diagnosticClass = classes["Diagnostic"] else {
            return nil
        }
        guard let rangeJSValue = rangeValue(for: diagnostic.range, in: context) else {
            return nil
        }
        guard let result = diagnosticClass.construct(
            withArguments: [rangeJSValue, diagnostic.message, diagnostic.severity.rawValue]
        ), !result.isUndefined, !result.isNull else {
            return nil
        }

        if let source = diagnostic.source {
            result.setValue(source, forProperty: "source")
        }
        if let code = diagnostic.code {
            guard let codeJSValue = diagnosticCodeJSValue(for: code, in: context) else {
                return nil
            }
            result.setValue(codeJSValue, forProperty: "code")
        }
        if let relatedInformation = diagnostic.relatedInformation {
            var relatedInformationJSValues: [JSValue] = []
            relatedInformationJSValues.reserveCapacity(relatedInformation.count)
            for oneRelatedInformation in relatedInformation {
                guard let relatedInformationJSValue = diagnosticRelatedInformationValue(
                    for: oneRelatedInformation, in: context
                ) else {
                    return nil
                }
                relatedInformationJSValues.append(relatedInformationJSValue)
            }
            result.setValue(relatedInformationJSValues, forProperty: "relatedInformation")
        }
        if let tags = diagnostic.tags {
            result.setValue(tags.map { $0.rawValue }, forProperty: "tags")
        }

        return result
    }
}
