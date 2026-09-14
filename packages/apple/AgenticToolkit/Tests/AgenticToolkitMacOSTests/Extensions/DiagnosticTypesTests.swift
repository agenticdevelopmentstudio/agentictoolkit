import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitMacOS

/// `vscode.DiagnosticSeverity`, `vscode.DiagnosticTag`,
/// `vscode.DiagnosticRelatedInformation` and `vscode.Diagnostic` (task
/// 5.6a-ii): the installed JS values themselves
/// (`VSCodeAPI.installDiagnosticTypes(in:)`), and the Swift↔JS bridge built
/// on top of them. `vscode.Location`'s own tests — the fifth declaration
/// this task adds — live in `TextGeometryTests.swift` instead, alongside
/// `Position`/`Range`, for the same reason `DiagnosticTypes.swift` itself
/// does not define `Location` (see that file's header).
///
/// A bare `JSContext`, not an `ExtensionHost` — `UriTests`/`TextGeometryTests`'
/// own reasoning applies unchanged: every function under test here takes a
/// `JSContext` and nothing else.
///
/// Each `@Test`'s doc names exactly one of task 5.6a-ii's brief's thirteen
/// numbered mutations (mutations 1 and 2, `Location`'s constructor dispatch,
/// are covered in `TextGeometryTests.swift`; this file covers 3 through 13),
/// and names no mutation an earlier test in this file already kills.
@MainActor
@Suite
struct DiagnosticTypesTests {

    /// A fresh context with `Uri`, `Position`, `Range`, `Location` and the
    /// four diagnostic values installed and exposed as plain globals, so a
    /// test's own script can read them the way extension code would read
    /// `vscode.*` — without repeating every install call in every test.
    /// `Uri`/`Position`/`Range`/`Location` are needed here because
    /// `Diagnostic.range` and `DiagnosticRelatedInformation.location` (in
    /// turn carrying its own `Uri`) both reach into `TextGeometry.swift`'s
    /// and `Uri.swift`'s installed classes, not just this file's four.
    private func makeContext() throws -> JSContext {
        let context = try #require(JSContext())
        let uriClass = try #require(VSCodeAPI.installUriClass(in: context))
        context.setObject(uriClass, forKeyedSubscript: "Uri" as NSString)
        let geometry = try #require(
            VSCodeAPI.installTextGeometryClasses(in: context))
        for (name, value) in geometry {
            context.setObject(value, forKeyedSubscript: name as NSString)
        }
        let diagnostics = try #require(
            VSCodeAPI.installDiagnosticTypes(in: context))
        for (name, value) in diagnostics {
            context.setObject(value, forKeyedSubscript: name as NSString)
        }
        return context
    }

    /// Evaluates `script` in `context` and answers its `Int32` value — used
    /// only by the tamper-check in mutation 10 below, where
    /// `DiagnosticSeverity`/`DiagnosticTag` are already known to exist by
    /// that point in the test, so the "member might not exist" hazard
    /// `requireInt32` guards against does not apply the
    /// same way; `nil` propagates to a failed `#expect` rather than being
    /// force-unwrapped.
    private func evalInt32(_ script: String, in ctx: JSContext) -> Int32? {
        ctx.evaluateScript(script)?.toInt32()
    }

    /// `evalInt32(_:in:)`'s boolean-valued counterpart, for the frozen-
    /// checking assertions below (mutation 10).
    private func evalBool(_ script: String, in ctx: JSContext) -> Bool? {
        ctx.evaluateScript(script)?.toBool()
    }

    /// `evalInt32(_:in:)`'s type-checked counterpart:
    /// `#require`s the script's result, `#expect`s it is actually a JS
    /// number, and only then answers the numeric value. `toInt32()` on a
    /// `JSValue` wrapping `undefined` is silently `0` — a member that does
    /// not exist would otherwise read back indistinguishable from one that
    /// exists and equals zero. Used wherever the value being checked could
    /// itself be `0` (or, for `requireBool`, `false`), so the plain value
    /// assertion alone cannot tell "missing" from "present and zero/false".
    private func requireInt32(
        _ script: String, in ctx: JSContext
    ) throws -> Int32 {
        let value = try #require(ctx.evaluateScript(script))
        #expect(value.isNumber)
        return value.toInt32()
    }

    /// `requireInt32(_:in:)`'s string-valued counterpart.
    private func requireString(
        _ script: String, in ctx: JSContext
    ) throws -> String {
        let value = try #require(ctx.evaluateScript(script))
        #expect(value.isString)
        return try #require(value.toString())
    }

    /// `requireInt32(_:in:)`'s boolean-valued counterpart, for the
    /// absence-checking assertions below (mutation 13).
    private func requireBool(
        _ script: String, in ctx: JSContext
    ) throws -> Bool {
        let value = try #require(ctx.evaluateScript(script))
        #expect(value.isBoolean)
        return value.toBool()
    }

    // MARK: - Mutation 3: DiagnosticSeverity's four values

    /// `DiagnosticSeverity.Error`/`.Warning`/`.Information`/`.Hint` are `0`,
    /// `1`, `2` and `3` respectively — all four checked by number, since
    /// `Error` alone is `0` and would pass against a stub that always
    /// answers `0` regardless of which member is read. Each read goes
    /// through `requireInt32`/`requireString`, which assert the JS type
    /// before the value: a member that does not exist at
    /// all reads back as `undefined`, and `toInt32()` on that is silently
    /// `0` too, so the `.Error`/`[0]` assertions could not otherwise tell
    /// "is `0`" from "does not exist". The reverse mapping
    /// (`DiagnosticSeverity[0] === 'Error'`, etc.) is checked too, since
    /// this file's header commits to mirroring `tsc`'s compiled enum shape
    /// in both directions, not just the forward one.
    @Test
    func diagnosticSeverityHasAllFourValuesByNumber() throws {
        let context = try makeContext()
        try #expect(requireInt32("DiagnosticSeverity.Error", in: context) == 0)
        try #expect(
            requireInt32("DiagnosticSeverity.Warning", in: context) == 1)
        try #expect(
            requireInt32("DiagnosticSeverity.Information", in: context) == 2)
        try #expect(requireInt32("DiagnosticSeverity.Hint", in: context) == 3)
        try #expect(
            requireString("DiagnosticSeverity[0]", in: context) == "Error")
        try #expect(
            requireString("DiagnosticSeverity[1]", in: context) == "Warning")
        let information = try requireString(
            "DiagnosticSeverity[2]", in: context)
        #expect(information == "Information")
        try #expect(
            requireString("DiagnosticSeverity[3]", in: context) == "Hint")
    }

    // MARK: - Mutation 4: DiagnosticTag's two values, neither zero

    /// `DiagnosticTag.Unnecessary`/`.Deprecated` are `1` and `2` — and,
    /// separately, **neither is `0`**: an off-by-one implementation (e.g.
    /// `Unnecessary: 0, Deprecated: 1`) would still have two distinct
    /// values in the right relative order, so the zero check is what turns
    /// that mutant red rather than merely checking the two values differ.
    /// Both reads go through `requireInt32`, which asserts the JS type
    /// before the value, so a missing member cannot read
    /// back as the in-range `0` a plain `toInt32()` would silently produce.
    /// The reverse mapping is checked too, for the reason
    /// `diagnosticSeverityHasAllFourValuesByNumber` gives.
    @Test
    func diagnosticTagHasBothValuesAndNeitherIsZero() throws {
        let context = try makeContext()
        let unnecessary = try requireInt32(
            "DiagnosticTag.Unnecessary", in: context)
        let deprecated = try requireInt32(
            "DiagnosticTag.Deprecated", in: context)
        #expect(unnecessary == 1)
        #expect(deprecated == 2)
        #expect(unnecessary != 0)
        #expect(deprecated != 0)
        try #expect(
            requireString("DiagnosticTag[1]", in: context) == "Unnecessary")
        try #expect(
            requireString("DiagnosticTag[2]", in: context) == "Deprecated")
    }

    // MARK: - Mutation 5: the two-arg constructor defaults severity to Error

    /// `new Diagnostic(range, message)` (no third argument) sets `severity`
    /// to `DiagnosticSeverity.Error`, distinguished here from an explicitly
    /// passed `0`: the assertion checks `typeof d.severity === 'number'`
    /// (ruling out `undefined`) **and** the value equals `0`, together —
    /// `#expect(d.severity === 0)` alone would also pass an implementation
    /// that leaves `severity` `undefined` and merely coerces at read time in
    /// some contexts, so the explicit `typeof` check is what this test
    /// relies on to tell "defaulted to the numeric `0`" apart from "never
    /// set".
    @Test
    func diagnosticTwoArgConstructorDefaultsSeverityToError() throws {
        let context = try makeContext()
        context.evaluateScript(
            """
            var d = new Diagnostic(new Range(0, 0, 0, 1), 'oops');
            """)
        let diagnostic = try #require(context.objectForKeyedSubscript("d"))
        let severity = try #require(diagnostic.forProperty("severity"))
        #expect(severity.isNumber)
        #expect(!severity.isUndefined)
        #expect(severity.toInt32() == 0)
    }

    // MARK: - Mutation 6: the three-arg constructor honours explicit severity

    /// `new Diagnostic(range, message, DiagnosticSeverity.Hint)` sets
    /// `severity` to `3` — a value no default path could produce, so this
    /// kills an implementation that ignores its third argument and always
    /// defaults, which the two-arg test above cannot distinguish from a
    /// correct implementation (both would show `severity === 0` there,
    /// since a hypothetical ignore-the-argument stub only shows itself when
    /// a non-`Error` severity is actually passed). `severity.isNumber` is
    /// asserted before its value, as `diagnosticTwoArgConstructorDefaults-
    /// SeverityToError` above already does: otherwise a
    /// constructor that threw and left `d` undefined would make `severity`
    /// itself `undefined`, whose `toInt32()` is `0`, not `3` — so this
    /// particular value assertion could not accidentally pass regardless,
    /// but the discipline is kept consistent with the sibling test.
    @Test
    func diagnosticThreeArgConstructorHonoursExplicitHintSeverity() throws {
        let context = try makeContext()
        context.evaluateScript(
            """
            var d = new Diagnostic(
                new Range(0, 0, 0, 1), 'oops', DiagnosticSeverity.Hint);
            """)
        let diagnostic = try #require(context.objectForKeyedSubscript("d"))
        let severity = try #require(diagnostic.forProperty("severity"))
        #expect(severity.isNumber)
        #expect(severity.toInt32() == 3)
    }

    // MARK: - Mutation 7: code's three shapes (three tests)

    /// `diagnostic.code` set to a bare string decodes through
    /// `VSCodeAPI.diagnostic(from:in:)` as `.scalar(.string(...))` — the
    /// first of `code`'s three shapes. A `Diagnostic` instance is
    /// deliberately not frozen and `code` is plain property assignment, so
    /// reading the JS property straight back (as this test used to) cannot
    /// fail against any implementation of this task, including one with
    /// `diagnosticCode(from:in:)` deleted outright; routing through the
    /// reader is what actually exercises its `isString` branch. An
    /// implementation that only handles the object form (or only the number
    /// form) turns this one red without necessarily failing the other two.
    @Test
    func diagnosticCodeAcceptsAPlainString() throws {
        let context = try makeContext()
        context.evaluateScript(
            """
            var d = new Diagnostic(new Range(0, 0, 0, 1), 'oops');
            d.code = 'E1234';
            """)
        let jsValue = try #require(context.objectForKeyedSubscript("d"))
        let decoded = try #require(
            VSCodeAPI.diagnostic(from: jsValue, in: context))
        #expect(decoded.code == .scalar(.string("E1234")))
    }

    /// `diagnostic.code` set to a bare number decodes through
    /// `VSCodeAPI.diagnostic(from:in:)` as `.scalar(.number(...))` — the
    /// second shape, a separate mutation from the string case above per the
    /// brief, and routed through the reader for the same reason: an
    /// implementation handling only strings (or only the object form) must
    /// turn this red.
    @Test
    func diagnosticCodeAcceptsAPlainNumber() throws {
        let context = try makeContext()
        context.evaluateScript(
            """
            var d = new Diagnostic(new Range(0, 0, 0, 1), 'oops');
            d.code = 42;
            """)
        let jsValue = try #require(context.objectForKeyedSubscript("d"))
        let decoded = try #require(
            VSCodeAPI.diagnostic(from: jsValue, in: context))
        #expect(decoded.code == .scalar(.number(42)))
    }

    /// `diagnostic.code` set to `{ value, target }` with a **real** `Uri`
    /// for `target` round-trips both fields — the third shape, exercised
    /// through `VSCodeAPI.diagnostic(from:in:)` rather than raw JS property
    /// reads, since it is this reader's handling of the object form
    /// (routing `target` through `url(from:in:)`) that this test pins: an
    /// implementation handling only the two scalar forms turns this one red
    /// while passing the string and number tests above.
    @Test
    func diagnosticCodeAcceptsAnObjectFormWithARealUriTarget() throws {
        let context = try makeContext()
        context.evaluateScript(
            """
            var d = new Diagnostic(new Range(0, 0, 0, 1), 'oops');
            var target = Uri.parse('https://example.com/e1234');
            d.code = { value: 'E1234', target: target };
            """)
        let jsValue = try #require(context.objectForKeyedSubscript("d"))
        let decoded = try #require(
            VSCodeAPI.diagnostic(from: jsValue, in: context))
        guard case .link(let value, let target) = decoded.code else {
            Issue.record("expected .link, got \(String(describing: decoded.code))")
            return
        }
        #expect(value == .string("E1234"))
        #expect(target.absoluteString == "https://example.com/e1234")
    }

    // MARK: - Mutation 8: relatedInformation round-trips a nested Location

    /// `diagnostic.relatedInformation` set to an array holding one
    /// `DiagnosticRelatedInformation`, itself holding a `Location`,
    /// round-trips through `VSCodeAPI.diagnostic(from:in:)` with the
    /// `Location`'s `uri`/`range` intact — three levels of nesting a flat
    /// reader (one that reads only `DiagnosticRelatedInformation`'s own two
    /// fields without recursing into `location(from:in:)`) would get wrong.
    @Test
    func diagnosticRelatedInformationRoundTripsANestedLocation() throws {
        let context = try makeContext()
        context.evaluateScript(
            """
            var d = new Diagnostic(new Range(0, 0, 0, 1), 'oops');
            var otherUri = Uri.file('/other.txt');
            var loc = new Location(otherUri, new Range(2, 0, 2, 3));
            d.relatedInformation = [
                new DiagnosticRelatedInformation(loc, 'see here')
            ];
            """)
        let jsValue = try #require(context.objectForKeyedSubscript("d"))
        let decoded = try #require(
            VSCodeAPI.diagnostic(from: jsValue, in: context))
        let relatedInformation = try #require(decoded.relatedInformation)
        #expect(relatedInformation.count == 1)
        let first = try #require(relatedInformation.first)
        #expect(first.message == "see here")
        #expect(first.location.uri.path == "/other.txt")
        #expect(first.location.range == VSCodeAPI.ExtensionRange(
            start: VSCodeAPI.ExtensionPosition(line: 2, character: 0),
            end: VSCodeAPI.ExtensionPosition(line: 2, character: 3)))
    }

    // MARK: - Mutation 9: tags round-trips, preserving order

    /// `diagnostic.tags` set to `[DiagnosticTag.Deprecated,
    /// DiagnosticTag.Unnecessary]` (deliberately not sorted) round-trips
    /// through `VSCodeAPI.diagnostic(from:in:)` as `[.deprecated,
    /// .unnecessary]` in that exact order — an implementation that sorts,
    /// reverses, or otherwise loses order turns this red, which a fixture
    /// using only one tag or two tags in ascending order could not catch.
    @Test
    func diagnosticTagsRoundTripPreservingOrder() throws {
        let context = try makeContext()
        context.evaluateScript(
            """
            var d = new Diagnostic(new Range(0, 0, 0, 1), 'oops');
            d.tags = [DiagnosticTag.Deprecated, DiagnosticTag.Unnecessary];
            """)
        let jsValue = try #require(context.objectForKeyedSubscript("d"))
        let decoded = try #require(
            VSCodeAPI.diagnostic(from: jsValue, in: context))
        #expect(decoded.tags == [.deprecated, .unnecessary])
    }

    // MARK: - Mutation 10: every class is frozen

    /// `DiagnosticSeverity`, `DiagnosticTag`, `DiagnosticRelatedInformation`
    /// and `Diagnostic` (and `DiagnosticRelatedInformation.prototype` /
    /// `Diagnostic.prototype`) are all frozen — `Object.isFrozen` says so
    /// directly for all six, and a tampering assignment to one of
    /// `DiagnosticSeverity`'s own values does not stick, proving the freeze
    /// is real rather than merely reported. Removing any one
    /// `Object.freeze` call in `diagnosticClassesSource` turns the matching
    /// assertion below red.
    @Test
    func everyDiagnosticClassAndPrototypeIsFrozen() throws {
        let context = try makeContext()
        func frozen(_ name: String) -> Bool? {
            evalBool("Object.isFrozen(\(name))", in: context)
        }
        #expect(frozen("DiagnosticSeverity") == true)
        #expect(frozen("DiagnosticTag") == true)
        #expect(frozen("DiagnosticRelatedInformation") == true)
        #expect(frozen("DiagnosticRelatedInformation.prototype") == true)
        #expect(frozen("Diagnostic") == true)
        #expect(frozen("Diagnostic.prototype") == true)

        context.evaluateScript("DiagnosticSeverity.Error = 99;")
        #expect(evalInt32("DiagnosticSeverity.Error", in: context) == 0)

        context.evaluateScript(
            "DiagnosticRelatedInformation.prototype.tampered = 'yes';")
        let stuck = evalBool(
            "'tampered' in DiagnosticRelatedInformation.prototype", in: context)
        #expect(stuck == false)
    }

    // MARK: - Mutation 11 (RelatedInformation half): reader not duck-typed

    /// `VSCodeAPI.diagnosticRelatedInformation(from:in:)` answers `nil` for
    /// a plain `{ location, message }` object literal — even one whose
    /// `location` is a real `Location` instance — because the outer object
    /// is not a real `DiagnosticRelatedInformation`.
    @Test
    func diagnosticRelatedInformationFromRefusesADuckTypedLiteral() throws {
        let context = try makeContext()
        let literal = try #require(context.evaluateScript(
            """
            ({
                location: new Location(Uri.file('/a.txt'), new Range(0, 0, 0, 1)),
                message: 'oops'
            })
            """))
        #expect(VSCodeAPI.diagnosticRelatedInformation(from: literal, in: context) == nil)
    }

    /// `VSCodeAPI.diagnosticRelatedInformation(from:in:)` reads a real
    /// `new DiagnosticRelatedInformation(location, message)` instance back
    /// correctly — proof the reader actually reads the real thing, which
    /// the refusal test alone does not establish.
    @Test
    func diagnosticRelatedInformationFromReadsARealInstance() throws {
        let context = try makeContext()
        let real = try #require(context.evaluateScript(
            """
            new DiagnosticRelatedInformation(
                new Location(Uri.file('/a.txt'), new Range(0, 0, 0, 1)),
                'oops')
            """))
        let decoded = try #require(
            VSCodeAPI.diagnosticRelatedInformation(from: real, in: context))
        #expect(decoded.message == "oops")
        #expect(decoded.location.uri.path == "/a.txt")
    }

    // MARK: - Mutation 11 (Diagnostic half): reader not duck-typed

    /// `VSCodeAPI.diagnostic(from:in:)` answers `nil` for a plain
    /// `{ range, message, severity }` object literal — even one whose
    /// `range` is a real `Range` instance — because the outer object is not
    /// a real `Diagnostic`.
    @Test
    func diagnosticFromRefusesADuckTypedLiteral() throws {
        let context = try makeContext()
        let literal = try #require(context.evaluateScript(
            """
            ({ range: new Range(0, 0, 0, 1), message: 'oops', severity: 0 })
            """))
        #expect(VSCodeAPI.diagnostic(from: literal, in: context) == nil)
    }

    /// `VSCodeAPI.diagnostic(from:in:)` reads a real
    /// `new Diagnostic(range, message, severity)` instance back correctly —
    /// proof the reader actually reads the real thing, which the refusal
    /// test alone does not establish.
    @Test
    func diagnosticFromReadsARealInstance() throws {
        let context = try makeContext()
        let real = try #require(context.evaluateScript(
            """
            new Diagnostic(
                new Range(0, 0, 0, 1), 'oops', DiagnosticSeverity.Warning)
            """))
        let decoded = try #require(
            VSCodeAPI.diagnostic(from: real, in: context))
        #expect(decoded.message == "oops")
        #expect(decoded.severity == .warning)
        #expect(decoded.range == VSCodeAPI.ExtensionRange(
            start: VSCodeAPI.ExtensionPosition(line: 0, character: 0),
            end: VSCodeAPI.ExtensionPosition(line: 0, character: 1)))
    }

    // MARK: - Mutation 12 (RelatedInformation half): writer round-trips

    /// `diagnosticRelatedInformationValue(for:in:)` followed by
    /// `diagnosticRelatedInformation(from:in:)` gives back an equal
    /// `ExtensionDiagnosticRelatedInformation`, and the JS value the writer
    /// produced is a real `instanceof DiagnosticRelatedInformation` — not
    /// merely an object literal shaped like one, which the duck-typed
    /// refusal test above proves the reader would otherwise reject.
    @Test
    func diagnosticRelatedInformationValueRoundTripsThroughTheReader() throws {
        let context = try makeContext()
        let original = VSCodeAPI.ExtensionDiagnosticRelatedInformation(
            location: VSCodeAPI.ExtensionLocation(
                uri: try #require(URL(string: "file:///a/b.txt")),
                range: VSCodeAPI.ExtensionRange(
                    start: VSCodeAPI.ExtensionPosition(line: 0, character: 0),
                    end: VSCodeAPI.ExtensionPosition(line: 0, character: 1))),
            message: "see here")
        let jsValue = try #require(
            VSCodeAPI.diagnosticRelatedInformationValue(for: original, in: context))
        context.setObject(jsValue, forKeyedSubscript: "roundTripped" as NSString)
        let isInstance = context.evaluateScript(
            "roundTripped instanceof DiagnosticRelatedInformation")
        #expect(isInstance?.toBool() == true)
        #expect(VSCodeAPI.diagnosticRelatedInformation(from: jsValue, in: context) == original)
    }

    // MARK: - Mutation 12 (Diagnostic half): writer round-trips

    /// `diagnosticValue(for:in:)` followed by `diagnostic(from:in:)` gives
    /// back an equal `ExtensionDiagnostic` — including `source`, the object
    /// form of `code`, `relatedInformation` and `tags`, exercised together
    /// so the writer's post-construction property assignments are all
    /// covered in one fixture — and the JS value the writer produced is a
    /// real `instanceof Diagnostic`, not merely an object literal shaped
    /// like one.
    @Test
    func diagnosticValueRoundTripsThroughTheReaderWithAllOptionalFields() throws {
        let context = try makeContext()
        let original = VSCodeAPI.ExtensionDiagnostic(
            range: VSCodeAPI.ExtensionRange(
                start: VSCodeAPI.ExtensionPosition(line: 0, character: 0),
                end: VSCodeAPI.ExtensionPosition(line: 0, character: 5)),
            message: "oops",
            severity: .warning,
            source: "my-linter",
            code: .link(
                value: .string("E1234"),
                target: try #require(URL(string: "https://example.com/e1234"))),
            relatedInformation: [
                VSCodeAPI.ExtensionDiagnosticRelatedInformation(
                    location: VSCodeAPI.ExtensionLocation(
                        uri: try #require(URL(string: "file:///a/b.txt")),
                        range: VSCodeAPI.ExtensionRange(
                            start: VSCodeAPI.ExtensionPosition(line: 1, character: 0),
                            end: VSCodeAPI.ExtensionPosition(line: 1, character: 2))),
                    message: "see here")
            ],
            tags: [.deprecated, .unnecessary])
        let jsValue = try #require(VSCodeAPI.diagnosticValue(for: original, in: context))
        context.setObject(jsValue, forKeyedSubscript: "roundTripped" as NSString)
        let isDiagnostic = context.evaluateScript("roundTripped instanceof Diagnostic")
        #expect(isDiagnostic?.toBool() == true)
        #expect(VSCodeAPI.diagnostic(from: jsValue, in: context) == original)
    }

    /// The fixture above only ever gives the writer a `.link` code, so
    /// `diagnosticCodeJSValue`'s `.scalar` branch had zero coverage in this
    /// direction. This is the same round-trip, minimal
    /// otherwise, with a bare `.scalar(.number(...))` code instead — an
    /// implementation that only writes the `.link` object form back out
    /// turns this one red without necessarily failing the fixture above.
    @Test
    func diagnosticValueRoundTripsAScalarCode() throws {
        let context = try makeContext()
        let original = VSCodeAPI.ExtensionDiagnostic(
            range: VSCodeAPI.ExtensionRange(
                start: VSCodeAPI.ExtensionPosition(line: 0, character: 0),
                end: VSCodeAPI.ExtensionPosition(line: 0, character: 5)),
            message: "oops",
            severity: .warning,
            code: .scalar(.number(42)))
        let jsValue = try #require(
            VSCodeAPI.diagnosticValue(for: original, in: context))
        context.setObject(jsValue, forKeyedSubscript: "roundTripped" as NSString)
        let isDiagnostic = context.evaluateScript(
            "roundTripped instanceof Diagnostic")
        #expect(isDiagnostic?.toBool() == true)
        #expect(VSCodeAPI.diagnostic(from: jsValue, in: context) == original)
    }

    // MARK: - Mutation 13: optional properties are absent, not undefined-valued

    /// `new Diagnostic(range, message)` leaves `source`, `code`,
    /// `relatedInformation` and `tags` **absent** — `'source' in d` is
    /// `false`, not merely `d.source === undefined` — matching this file's
    /// documented choice to never assign `undefined` to them. Both forms of
    /// the check are made: `in` (own-or-inherited-property existence) and
    /// `Object.hasOwn` (own-property existence), since an implementation
    /// that assigned `undefined` explicitly would still pass a bare
    /// `d.source === undefined` check but fail both of these. Both go
    /// through `requireBool`, which asserts the JS type before the value: if
    /// `new Diagnostic(...)` ever threw, `d` would be
    /// `undefined`, `'source' in d` would throw rather than evaluate, and a
    /// plain `toBool()` on the resulting `JSValue` would silently read back
    /// `false` — the very answer this test expects — masking the throw
    /// instead of catching it.
    @Test
    func diagnosticOptionalPropertiesAreAbsentNotUndefinedValued() throws {
        let context = try makeContext()
        context.evaluateScript(
            """
            var d = new Diagnostic(new Range(0, 0, 0, 1), 'oops');
            """)
        for propertyName in ["source", "code", "relatedInformation", "tags"] {
            try #expect(
                requireBool("'\(propertyName)' in d", in: context) == false)
            try #expect(
                requireBool("Object.hasOwn(d, '\(propertyName)')", in: context)
                    == false)
        }
    }

    // MARK: - Present-but-malformed optional properties

    /// `diagnostic(from:in:)` distinguishes *absent* from
    /// *present-but-undecodable*: a `source` that is present but not a
    /// string must refuse the whole diagnostic, not silently drop just that
    /// field and let the rest of the diagnostic through as if `source` had
    /// never been set.
    @Test
    func diagnosticRefusesAMalformedSource() throws {
        let context = try makeContext()
        context.evaluateScript(
            """
            var d = new Diagnostic(new Range(0, 0, 0, 1), 'oops');
            d.source = 42;
            """)
        let jsValue = try #require(context.objectForKeyedSubscript("d"))
        #expect(VSCodeAPI.diagnostic(from: jsValue, in: context) == nil)
    }

    /// `diagnostic(from:in:)` refuses a `code` that is present but matches
    /// none of the three union shapes (not a string, not a number, and an
    /// object missing `value`/`target`) — the whole call answers `nil`
    /// rather than dropping `code` and reading the rest back.
    @Test
    func diagnosticRefusesAMalformedCode() throws {
        let context = try makeContext()
        context.evaluateScript(
            """
            var d = new Diagnostic(new Range(0, 0, 0, 1), 'oops');
            d.code = {};
            """)
        let jsValue = try #require(context.objectForKeyedSubscript("d"))
        #expect(VSCodeAPI.diagnostic(from: jsValue, in: context) == nil)
    }

    /// `diagnostic(from:in:)` refuses a `relatedInformation` array that is
    /// present but contains one duck-typed object literal rather than a
    /// real `DiagnosticRelatedInformation` instance —
    /// `diagnosticRelatedInformationArray`'s own "`nil`, not a partial
    /// array" contract must reach all the way out to `diagnostic(from:in:)`
    /// instead of being collapsed into "absent" one level up.
    @Test
    func diagnosticRefusesAMalformedRelatedInformationElement() throws {
        let context = try makeContext()
        context.evaluateScript(
            """
            var d = new Diagnostic(new Range(0, 0, 0, 1), 'oops');
            d.relatedInformation = [
                {
                    location: new Location(
                        Uri.file('/a.txt'), new Range(0, 0, 0, 1)),
                    message: 'oops'
                }
            ];
            """)
        let jsValue = try #require(context.objectForKeyedSubscript("d"))
        #expect(VSCodeAPI.diagnostic(from: jsValue, in: context) == nil)
    }

    /// `diagnostic(from:in:)` refuses a `tags` array that is present but
    /// contains a value outside the declared enum's range (`0`, which is
    /// not a `DiagnosticTag`) — the same "refuse, not coerce" contract as
    /// the `relatedInformation` case above, for `diagnosticTagArray`.
    @Test
    func diagnosticRefusesAMalformedTagsElement() throws {
        let context = try makeContext()
        context.evaluateScript(
            """
            var d = new Diagnostic(new Range(0, 0, 0, 1), 'oops');
            d.tags = [0];
            """)
        let jsValue = try #require(context.objectForKeyedSubscript("d"))
        #expect(VSCodeAPI.diagnostic(from: jsValue, in: context) == nil)
    }
}
