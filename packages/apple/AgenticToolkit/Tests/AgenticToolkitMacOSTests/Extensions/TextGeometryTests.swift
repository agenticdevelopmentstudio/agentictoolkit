import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitMacOS

/// `vscode.Position` and `vscode.Range` (task 5.6a-i): the installed JS
/// classes themselves (`VSCodeAPI.installTextGeometryClasses(in:)`), and the
/// Swift↔JS bridge built on top of them (`VSCodeAPI.position(from:in:)` /
/// `.positionValue(for:in:)`, `.range(from:in:)` / `.rangeValue(for:in:)`).
///
/// A bare `JSContext`, not an `ExtensionHost` — `UriTests`'s own reasoning
/// applies unchanged: every function under test here takes a `JSContext` and
/// nothing else, so this suite needs no extension, no manifest and no
/// activation.
///
/// Each `@Test`'s doc names exactly one of the fourteen mutations task
/// 5.6a-i's brief enumerates, and names no mutation an earlier test in this
/// file already kills.
///
/// **Seven further tests cover five behaviors** the 5.6a upstream addendum
/// mandates (or a pre-existing code comment already claimed) that no earlier
/// test exercised: negative-argument throws split across two tests;
/// `translate`/`with` identity-on-no-change (a code comment already claimed
/// this as tested, but no test did); the
/// touching-ranges-answer-an-empty-range-not-`undefined` fixture the
/// addendum requires, which the original intersection test's fixture could
/// not reach; equal-position comparisons across all four comparison
/// methods; and the `isEqual`/`contains` duck-typing asymmetry, split across
/// two tests. Six of the seven sit under an "Addendum mutation" `MARK`;
/// `intersectionOfTouchingRangesIsAnEmptyRangeNotUndefined` sits under
/// "Mutation 4: intersection" instead, alongside the pre-existing
/// disjoint-range test it complements.
///
/// **Task 5.6a-ii added two further tests, for `vscode.Location`'s
/// constructor dispatch** (`TextGeometry.swift`, not `DiagnosticTypes.swift`
/// — see that file's header for why): mutation 1, `new Location(uri,
/// position)` converts the position to an empty range at that position;
/// mutation 2, `new Location(uri, range)` keeps the given range, the same
/// object, unconverted. `makeContext()` now also exposes `Location` as a
/// global alongside `Position`/`Range`, for exactly the same reason those
/// two are exposed. `Diagnostic`/`DiagnosticSeverity`/`DiagnosticTag`/
/// `DiagnosticRelatedInformation` are covered separately, in
/// `DiagnosticTypesTests.swift`.
@MainActor
@Suite
struct TextGeometryTests {

    /// A fresh context with `Position` and `Range` installed and exposed as
    /// plain globals, so a test's own script can read them the way extension
    /// code would read `vscode.Position`/`vscode.Range` — without repeating
    /// the install call in every test.
    private func makeContext() throws -> JSContext {
        let context = try #require(JSContext())
        let classes = try #require(VSCodeAPI.installTextGeometryClasses(in: context))
        let positionClass = try #require(classes["Position"])
        let rangeClass = try #require(classes["Range"])
        let locationClass = try #require(classes["Location"])
        context.setObject(positionClass, forKeyedSubscript: "Position" as NSString)
        context.setObject(rangeClass, forKeyedSubscript: "Range" as NSString)
        context.setObject(locationClass, forKeyedSubscript: "Location" as NSString)
        // `Location.uri` is read through `url(from:in:)`, itself not
        // duck-typed (`Uri.swift:348-355`) — a real `vscode.Location` fixture
        // needs a real `vscode.Uri` for `uri`, hence `Uri` is exposed here
        // too, `UriTests.makeContext()`'s own reasoning.
        let uriClass = try #require(VSCodeAPI.installUriClass(in: context))
        context.setObject(uriClass, forKeyedSubscript: "Uri" as NSString)
        return context
    }

    // MARK: - Mutation 1: the constructor swap

    /// `new Range(new Position(5, 0), new Position(1, 0))` has
    /// `start.line === 1` — the constructor swapped the out-of-order pair.
    /// Deleting the swap turns this red; a fixture built with already-ordered
    /// positions could not see it, so this one is deliberately backwards.
    @Test
    func rangeConstructorSwapsOutOfOrderPositions() throws {
        let context = try makeContext()
        let script = "new Range(new Position(5, 0), new Position(1, 0))"
        let range = try #require(context.evaluateScript(script))
        #expect(range.forProperty("start")?.forProperty("line")?.toInt32() == 1)
        #expect(range.forProperty("end")?.forProperty("line")?.toInt32() == 5)
    }

    // MARK: - Mutation 2: the four-number constructor

    /// `new Range(5, 0, 1, 0)` (four numbers) produces the same range as
    /// `new Range(new Position(5, 0), new Position(1, 0))` (two positions),
    /// swap included — an implementation that swaps in one constructor form
    /// but not the other turns this red.
    @Test
    func rangeFourNumberConstructorMatchesTwoPositionConstructorIncludingSwap() throws {
        let context = try makeContext()
        let posScript = "new Range(new Position(5, 0), new Position(1, 0))"
        let fromNumbers = try #require(context.evaluateScript("new Range(5, 0, 1, 0)"))
        let fromPositions = try #require(context.evaluateScript(posScript))
        #expect(fromNumbers.forProperty("start")?.forProperty("line")?.toInt32() == 1)
        #expect(fromNumbers.forProperty("end")?.forProperty("line")?.toInt32() == 5)
        let equal = try #require(
            fromNumbers.invokeMethod("isEqual", withArguments: [fromPositions]))
        #expect(equal.isBoolean)
        #expect(equal.toBool() == true)
    }

    // MARK: - Addendum mutation: negative-argument throws, per field

    /// `new Position(-1, 0)` throws, mentioning `line`.
    ///
    /// **The addendum:** "a stub that clamps to `0`
    /// and a stub that checks only `line` are different bugs, and a test
    /// passing `(-1, 0)` alone catches only the first." This test and
    /// `positionConstructorThrowsOnANegativeCharacter` below are the pair
    /// that together catch both stubs: a clamp-to-zero stub never throws and
    /// turns this one red; a stub that validates only `line` would still
    /// pass this test while failing the paired one. Confirmed under `node`:
    /// the fixture throws `Error: line must be non-negative`. Does not kill:
    /// a stub that validates only `character`.
    @Test
    func positionConstructorThrowsOnANegativeLine() throws {
        let context = try makeContext()
        _ = context.evaluateScript("new Position(-1, 0)")
        let message = try #require(
            context.exception?.forProperty("message")?.toString())
        #expect(message.contains("line"))
    }

    /// `new Position(0, -1)` throws, mentioning `character` — the other half
    /// of the pair above. A stub that validates only `line` (never checking
    /// `character`) turns this one red while still passing the paired test.
    /// Confirmed under `node`: the fixture throws
    /// `Error: character must be non-negative`. Does not kill: a stub that
    /// validates only `line`.
    @Test
    func positionConstructorThrowsOnANegativeCharacter() throws {
        let context = try makeContext()
        _ = context.evaluateScript("new Position(0, -1)")
        let message = try #require(
            context.exception?.forProperty("message")?.toString())
        #expect(message.contains("character"))
    }

    // MARK: - Mutation 3: immutability of translate/with

    /// `p.translate(1, 1)` returns a **new** object and leaves `p` at its
    /// original `line`/`character` — an implementation that mutates `p` in
    /// place turns this red.
    @Test
    func positionTranslateReturnsNewObjectAndLeavesReceiverUnchanged() throws {
        let context = try makeContext()
        context.evaluateScript("var p = new Position(2, 3); var translated = p.translate(1, 1);")
        let originalPosition = try #require(context.objectForKeyedSubscript("p"))
        let translated = try #require(context.objectForKeyedSubscript("translated"))
        #expect(originalPosition.forProperty("line")?.toInt32() == 2)
        #expect(originalPosition.forProperty("character")?.toInt32() == 3)
        #expect(translated.forProperty("line")?.toInt32() == 3)
        #expect(translated.forProperty("character")?.toInt32() == 4)
        #expect(context.evaluateScript("p === translated")?.toBool() == false)
    }

    /// The same immutability, for `Range.prototype.with`'s single-`Position`
    /// overload (not the object-form overload mutation 9 already exercises
    /// via `Position.prototype.with`): `r.with(newStart)` returns a new
    /// object and leaves `r` at its original `start`/`end`.
    ///
    /// The first version of this test used
    /// `r.with(new Position(1, 1))` against `r = new Range((0,0), (0,5))`.
    /// `with` builds `new Range((1,1), (0,5))`, and `(1,1).isBefore((0,5))`
    /// is `false`, so the `Range` constructor's own swap branch — the
    /// correct behavior mutation 1 pins — swaps the pair, making
    /// `changed.start.line` `0`, not the `1` the old assertion required. The
    /// test was red against the correct implementation, not merely weak.
    /// Confirmed under `node`: for the fixture below,
    /// `changed.start` is `(0, 1)`, `r` is untouched at `(0, 0)`/`(0, 5)`,
    /// and `r !== changed`. Fixed by choosing a `newStart` — `(0, 1)` — that
    /// stays before `r`'s `end` of `(0, 5)`, so the swap invariant does not
    /// fire and the test does not need to work around it.
    @Test
    func rangeWithReturnsNewObjectAndLeavesReceiverUnchanged() throws {
        let context = try makeContext()
        context.evaluateScript(
            """
            var r = new Range(new Position(0, 0), new Position(0, 5));
            var changed = r.with(new Position(0, 1));
            """)
        let originalRange = try #require(context.objectForKeyedSubscript("r"))
        let changed = try #require(context.objectForKeyedSubscript("changed"))
        let originalStartLine = try #require(
            originalRange.forProperty("start")?.forProperty("line"))
        #expect(originalStartLine.isNumber)
        #expect(originalStartLine.toInt32() == 0)
        let originalStartCharacter = try #require(
            originalRange.forProperty("start")?.forProperty("character"))
        #expect(originalStartCharacter.isNumber)
        #expect(originalStartCharacter.toInt32() == 0)
        let changedStartLine = try #require(
            changed.forProperty("start")?.forProperty("line"))
        #expect(changedStartLine.isNumber)
        #expect(changedStartLine.toInt32() == 0)
        let changedStartCharacter = try #require(
            changed.forProperty("start")?.forProperty("character"))
        #expect(changedStartCharacter.isNumber)
        #expect(changedStartCharacter.toInt32() == 1)
        #expect(context.evaluateScript("r === changed")?.toBool() == false)
    }

    // MARK: - Addendum mutation: translate/with identity when nothing changes

    /// `p.translate(0, 0)` and `p.with()` both answer the receiver itself
    /// (`this`), not merely an equal copy — the addendum: "`translate` and
    /// `with` return `this` when nothing changes — identity, not a copy."
    ///
    /// `TextGeometry.swift`'s comment above
    /// `Position.prototype.translate` names this branch as what
    /// `TextGeometryTests` pins for immutability, but before this test
    /// nothing did:
    /// `positionTranslateReturnsNewObjectAndLeavesReceiverUnchanged`
    /// (mutation 3) uses a non-zero delta and asserts the *other* branch,
    /// `p !== translated`. An implementation that always constructs a new
    /// `Position`, or that uses `isEqual` instead of returning `this`, would
    /// still pass every earlier test in this file and only fails here.
    /// Confirmed under `node`: both `p.translate(0, 0) === p` and
    /// `p.with() === p` are `true`.
    @Test
    func translateAndWithReturnTheReceiverItselfWhenNothingChanges() throws {
        let context = try makeContext()
        context.evaluateScript("var p = new Position(2, 3);")
        #expect(
            context.evaluateScript("p.translate(0, 0) === p")?.toBool() == true)
        #expect(context.evaluateScript("p.with() === p")?.toBool() == true)
    }

    // MARK: - Mutation 4: intersection

    /// `intersection` of two genuinely disjoint ranges — a gap between them,
    /// not merely touching at one point — answers `undefined`.
    ///
    /// The original doc claimed this
    /// fixture also killed the "touching ranges wrongly answer `undefined`
    /// instead of an empty range" mutation the addendum requires a test for
    /// — it does not: a gapped pair is exactly the fixture the addendum
    /// rules out, because both the correct implementation and that mutant
    /// agree on it (both answer `undefined`), so it "passes against both
    /// implementations". This test's claim is narrowed to what it actually
    /// kills — an implementation that answers anything other than
    /// `undefined` for a pair with no overlap and no shared point at all.
    /// The touching-pair case the addendum mandates is covered separately by
    /// `intersectionOfTouchingRangesIsAnEmptyRangeNotUndefined` below (kept
    /// per Ruling 47 rather than deleted, since it still kills a real, if
    /// narrower, mutation).
    @Test
    func intersectionOfDisjointRangesIsUndefined() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            """
            (function () {
                var a = new Range(0, 0, 0, 5);
                var b = new Range(1, 0, 1, 5);
                return a.intersection(b);
            })()
            """))
        #expect(result.isUndefined)
    }

    /// `intersection` of two ranges that touch at exactly one point —
    /// `(0,0)-(0,5)` and `(0,5)-(0,10)` share only the point `(0,5)` —
    /// answers an **empty range**, not `undefined`. This is the fixture the
    /// addendum requires: `range.ts:98` answers
    /// `undefined` only when the computed start is *strictly after* the
    /// computed end; a touching pair's computed start equals its computed
    /// end, so `start.isAfter(end)` is `false` and a real (empty) `Range` is
    /// constructed instead. An implementation that treats "touches at one
    /// point" the same as "genuinely disjoint" — answering `undefined` for
    /// both — turns this red while still passing
    /// `intersectionOfDisjointRangesIsUndefined` above. Confirmed under
    /// `node`: the fixture below answers a `Range`, not `undefined`, with
    /// `isEmpty === true` and both endpoints at `(0, 5)`.
    @Test
    func intersectionOfTouchingRangesIsAnEmptyRangeNotUndefined() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            """
            (function () {
                var a = new Range(0, 0, 0, 5);
                var b = new Range(0, 5, 0, 10);
                return a.intersection(b);
            })()
            """))
        #expect(!result.isUndefined)
        let isEmpty = try #require(result.forProperty("isEmpty"))
        #expect(isEmpty.isBoolean)
        #expect(isEmpty.toBool() == true)
        let startCharacter = try #require(
            result.forProperty("start")?.forProperty("character"))
        #expect(startCharacter.toInt32() == 5)
        #expect(
            result.forProperty("end")?.forProperty("character")?.toInt32() == 5)
    }

    /// `intersection` of two overlapping ranges answers the overlapping span
    /// exactly.
    @Test
    func intersectionOfOverlappingRangesIsTheOverlappingSpan() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            """
            (function () {
                var a = new Range(0, 0, 0, 10);
                var b = new Range(0, 5, 0, 15);
                return a.intersection(b);
            })()
            """))
        #expect(result.forProperty("start")?.forProperty("character")?.toInt32() == 5)
        #expect(result.forProperty("end")?.forProperty("character")?.toInt32() == 10)
    }

    // MARK: - Mutation 5: union

    /// `union` of two disjoint ranges spans both, start to end.
    @Test
    func unionOfDisjointRangesSpansBoth() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            """
            (function () {
                var a = new Range(0, 0, 0, 5);
                var b = new Range(2, 0, 2, 5);
                return a.union(b);
            })()
            """))
        #expect(result.forProperty("start")?.forProperty("line")?.toInt32() == 0)
        #expect(result.forProperty("start")?.forProperty("character")?.toInt32() == 0)
        #expect(result.forProperty("end")?.forProperty("line")?.toInt32() == 2)
        #expect(result.forProperty("end")?.forProperty("character")?.toInt32() == 5)
    }

    // MARK: - Mutation 6: contains, both shapes

    /// `Range.prototype.contains` accepts a `Position` inside the range and
    /// rejects one outside — the `Position` half of mutation 6, independent
    /// of the `Range` half below: an implementation that only ever checked
    /// the `Range`-shaped branch would still pass this test and fail that
    /// one.
    @Test
    func containsAcceptsAPositionInsideAndRejectsOneOutside() throws {
        let context = try makeContext()
        context.evaluateScript("var r = new Range(0, 5, 0, 10);")
        let inside = try #require(context.evaluateScript("r.contains(new Position(0, 7))"))
        let outside = try #require(context.evaluateScript("r.contains(new Position(0, 20))"))
        #expect(inside.toBool() == true)
        #expect(outside.toBool() == false)
    }

    /// `Range.prototype.contains` accepts a `Range` fully inside the
    /// receiver and rejects one that extends outside it — the `Range` half
    /// of mutation 6, a separate mutation from the `Position` half above per
    /// the brief: an implementation handling only the `Position` branch must
    /// turn this red.
    @Test
    func containsAcceptsARangeInsideAndRejectsOneExtendingOutside() throws {
        let context = try makeContext()
        context.evaluateScript("var r = new Range(0, 0, 0, 20);")
        let inside = try #require(context.evaluateScript("r.contains(new Range(0, 5, 0, 10))"))
        let extendsOutside = try #require(context.evaluateScript("r.contains(new Range(0, 15, 0, 25))"))
        #expect(inside.toBool() == true)
        #expect(extendsOutside.toBool() == false)
    }

    // MARK: - Addendum mutation: isEqual is not duck-typed, contains is

    /// `Range.prototype.isEqual` reads `other._start`/`other._end` directly
    /// (`range.ts:92`) rather than going through `Range.isRange`, so a
    /// duck-typed plain-object argument throws instead of comparing.
    ///
    /// **The addendum:** "Do not make them
    /// uniform — the asymmetry is upstream's behaviour, and a test should
    /// pin each side." This test pins the `isEqual` side; paired with
    /// `containsIsDuckTypedAndAnswersFalseRatherThanThrowing` below, which
    /// pins the opposite behavior for `contains`. Confirmed under `node`:
    /// the fixture throws `TypeError: Cannot read properties of undefined
    /// (reading '_line')` — `other._start` is `undefined` for a plain
    /// `{ start: {...}, end: {...} }` literal, since `isEqual` never routes
    /// it through `positionOf`/`Range.isRange` the way `contains` does.
    @Test
    func isEqualIsNotDuckTypedAndThrowsOnAPlainObjectLiteral() throws {
        let context = try makeContext()
        context.evaluateScript("var r = new Range(0, 0, 0, 5);")
        _ = context.evaluateScript(
            """
            r.isEqual({ start: { line: 0, character: 0 },
                        end: { line: 0, character: 5 } })
            """)
        #expect(context.exception != nil)
    }

    /// `Range.prototype.contains` goes through `Position.isPosition`/
    /// `Range.isRange` (duck-typed) and answers `false` for a shape that is
    /// not a real `Position`/`Range`, rather than throwing — the other half
    /// of the asymmetry the addendum pins, verified to actually hold in this
    /// implementation rather than changed to make it hold.
    /// Confirmed under `node`: a plain `{ line, character }` literal outside
    /// the range answers `false`, with no exception raised.
    @Test
    func containsIsDuckTypedAndAnswersFalseRatherThanThrowing() throws {
        let context = try makeContext()
        context.evaluateScript("var r = new Range(0, 0, 0, 5);")
        let result = try #require(
            context.evaluateScript("r.contains({ line: 1, character: 2 })"))
        #expect(context.exception == nil)
        #expect(result.isBoolean)
        #expect(result.toBool() == false)
    }

    // MARK: - Mutation 7: compareTo

    /// `compareTo` orders by `line` first, then `character` — two positions
    /// on different lines whose characters order the other way, so an
    /// implementation that compares `character` first (or sums the two
    /// fields) turns this red.
    @Test
    func compareToOrdersByLineFirstThenCharacter() throws {
        let context = try makeContext()
        // Line order says "earlier"; character order alone would say "later".
        let comparison = try #require(context.evaluateScript(
            "(new Position(1, 99)).compareTo(new Position(2, 0))"))
        #expect(comparison.toInt32() == -1)
    }

    // MARK: - Addendum mutation: all four comparisons on equal positions

    /// `isBefore`, `isBeforeOrEqual`, `isAfter` and `isAfterOrEqual`, all
    /// exercised on the same pair of **equal** positions in one test.
    ///
    /// **The addendum:** "An implementation writing
    /// all four independently gets exactly one of the equal-position cases
    /// wrong, and only a test that exercises equal positions on all four can
    /// see it." An implementation that gets, say, `isAfterOrEqual` wrong for
    /// equal positions (answering `false` instead of `true`) would still
    /// pass every other test in this file, since none of them exercises
    /// equal-but-distinct `Position` objects across all four comparisons at
    /// once. Confirmed under `node`: for two positions both at `(3, 4)`,
    /// `isBefore` is `false`, `isBeforeOrEqual` is `true`, `isAfter` is
    /// `false`, `isAfterOrEqual` is `true`.
    @Test
    func comparisonMethodsAgreeOnEqualPositions() throws {
        let context = try makeContext()
        context.evaluateScript(
            "var a = new Position(3, 4); var b = new Position(3, 4);")
        let isBefore = try #require(context.evaluateScript("a.isBefore(b)"))
        #expect(isBefore.isBoolean)
        #expect(isBefore.toBool() == false)
        let isBeforeOrEqual = try #require(
            context.evaluateScript("a.isBeforeOrEqual(b)"))
        #expect(isBeforeOrEqual.isBoolean)
        #expect(isBeforeOrEqual.toBool() == true)
        let isAfter = try #require(context.evaluateScript("a.isAfter(b)"))
        #expect(isAfter.isBoolean)
        #expect(isAfter.toBool() == false)
        let isAfterOrEqual = try #require(
            context.evaluateScript("a.isAfterOrEqual(b)"))
        #expect(isAfterOrEqual.isBoolean)
        #expect(isAfterOrEqual.toBool() == true)
    }

    // MARK: - Mutation 8: translate's two forms agree

    /// `translate`'s object form (`{ lineDelta, characterDelta }`) and its
    /// two-number form produce the same result, and a field the object form
    /// omits contributes a **zero** delta rather than throwing or being
    /// treated as "unchanged" (which is `with`'s rule, not `translate`'s).
    @Test
    func translateObjectFormAgreesWithTwoNumberFormAndOmittedFieldIsZeroDelta() throws {
        let context = try makeContext()
        let objectForm = try #require(context.evaluateScript(
            "(new Position(2, 3)).translate({ lineDelta: 1, characterDelta: 1 })"))
        let numberForm = try #require(context.evaluateScript("(new Position(2, 3)).translate(1, 1)"))
        #expect(objectForm.invokeMethod("isEqual", withArguments: [numberForm])?.toBool() == true)

        let omittedCharacterDelta = try #require(context.evaluateScript(
            "(new Position(2, 3)).translate({ lineDelta: 1 })"))
        #expect(omittedCharacterDelta.forProperty("line")?.toInt32() == 3)
        #expect(omittedCharacterDelta.forProperty("character")?.toInt32() == 3)
    }

    // MARK: - Mutation 9: with's two forms agree

    /// `with`'s object form (`{ line, character }`) and its positional form
    /// produce the same result, and a field the object form omits **keeps
    /// the position's current value** rather than zeroing it — the opposite
    /// rule from `translate`'s omitted field above, per `vscode.d.ts`'s own
    /// asymmetry between the two.
    @Test
    func withObjectFormAgreesWithPositionalFormAndOmittedFieldKeepsCurrentValue() throws {
        let context = try makeContext()
        let objectForm = try #require(context.evaluateScript(
            "(new Position(2, 3)).with({ line: 5, character: 9 })"))
        let positionalForm = try #require(context.evaluateScript("(new Position(2, 3)).with(5, 9)"))
        #expect(objectForm.invokeMethod("isEqual", withArguments: [positionalForm])?.toBool() == true)

        let omittedCharacter = try #require(context.evaluateScript("(new Position(2, 3)).with({ line: 5 })"))
        #expect(omittedCharacter.forProperty("line")?.toInt32() == 5)
        #expect(omittedCharacter.forProperty("character")?.toInt32() == 3)
    }

    // MARK: - Mutation 10: frozen classes

    /// Assigning to `Range.prototype.contains` from extension-shaped code
    /// does not change what a later `contains` call does — removing the
    /// `Object.freeze` pair on `Range`/`Range.prototype` turns this red.
    ///
    /// The tampering assignment sets
    /// `contains` to a function returning the string `"tampered"`. The old
    /// assertion was `result.toBool() == true`, and `JSValue.toBool()` is
    /// JavaScript's `ToBoolean`, which is `true` for *any* non-empty
    /// string — so the assertion held whether the freeze fired or not,
    /// killing nothing (assertion-polarity part (a)). Confirmed under
    /// `node`: with the freeze intact, `contains` returns the real `true`
    /// (`typeof` `"boolean"`); with `Object.freeze(Range.prototype)` removed
    /// from the evaluated source, the identical call returns the string
    /// `"tampered"` (`typeof` `"string"`). Fixed by asserting the *type*
    /// rather than the truthiness: `result.isBoolean` is `true` only for the
    /// real, frozen implementation's answer and `false` for the mutant's
    /// string, so it distinguishes the two where `toBool()` could not.
    @Test
    func rangePrototypeReassignmentDoesNotChangeLaterContainsCalls() throws {
        let context = try makeContext()
        context.evaluateScript(
            """
            Range.prototype.contains = function () { return 'tampered'; };
            var r = new Range(0, 0, 0, 10);
            """)
        let result = try #require(context.evaluateScript("r.contains(new Position(0, 5))"))
        #expect(result.isBoolean)
        #expect(result.toBool() == true)
    }

    // MARK: - Mutation 11: the Swift reader is not duck-typed

    /// `VSCodeAPI.position(from:in:)` answers `nil` for a plain
    /// `{ line: 1, character: 2 }` object literal — it is not a real
    /// `Position` instance, and the reader must not be fooled by matching
    /// shape.
    @Test
    func positionFromRefusesADuckTypedLiteral() throws {
        let context = try makeContext()
        let literal = try #require(context.evaluateScript("({ line: 1, character: 2 })"))
        #expect(VSCodeAPI.position(from: literal, in: context) == nil)
    }

    /// `VSCodeAPI.position(from:in:)` reads a real `new Position(1, 2)`
    /// instance as `ExtensionPosition(line: 1, character: 2)` — proof the
    /// reader actually reads the real thing, which the refusal test alone
    /// does not establish.
    @Test
    func positionFromReadsARealPositionInstance() throws {
        let context = try makeContext()
        let real = try #require(context.evaluateScript("new Position(1, 2)"))
        #expect(VSCodeAPI.position(from: real, in: context) == VSCodeAPI.ExtensionPosition(line: 1, character: 2))
    }

    // MARK: - Mutation 12: the Swift writer round-trips

    /// `rangeValue(for:in:)` followed by `range(from:in:)` gives back an
    /// equal `ExtensionRange`, and the JS value the writer produced is a
    /// real `instanceof Range` — not merely an object literal shaped like
    /// one, which a reader keyed only on property names could not catch.
    @Test
    func rangeValueRoundTripsThroughTheReader() throws {
        let context = try makeContext()
        let original = VSCodeAPI.ExtensionRange(
            start: VSCodeAPI.ExtensionPosition(line: 1, character: 2),
            end: VSCodeAPI.ExtensionPosition(line: 3, character: 4))
        let jsValue = try #require(VSCodeAPI.rangeValue(for: original, in: context))
        context.setObject(jsValue, forKeyedSubscript: "roundTripped" as NSString)
        #expect(context.evaluateScript("roundTripped instanceof Range")?.toBool() == true)
        #expect(VSCodeAPI.range(from: jsValue, in: context) == original)
    }

    // MARK: - Mutation 13: the Swift-side swap invariant

    /// Building an `ExtensionRange` with `end` before `start` and writing it
    /// out with `rangeValue(for:in:)` yields a JS range whose own
    /// `start.isBeforeOrEqual(end)` holds — proof the swap invariant is
    /// actually enforced somewhere for values that arrive from the Swift
    /// side already out of order, not merely for values built directly by
    /// the JS constructor (which mutation 1 already covers).
    @Test
    func swiftSideSwapInvariantIsEnforcedWhenWritingAnOutOfOrderRange() throws {
        let context = try makeContext()
        let outOfOrder = VSCodeAPI.ExtensionRange(
            start: VSCodeAPI.ExtensionPosition(line: 5, character: 0),
            end: VSCodeAPI.ExtensionPosition(line: 1, character: 0))
        let jsValue = try #require(VSCodeAPI.rangeValue(for: outOfOrder, in: context))
        context.setObject(jsValue, forKeyedSubscript: "written" as NSString)
        let holds = try #require(context.evaluateScript("written.start.isBeforeOrEqual(written.end)"))
        #expect(holds.toBool() == true)
        #expect(jsValue.forProperty("start")?.forProperty("line")?.toInt32() == 1)
    }

    // MARK: - Mutation 14: deterministic, idempotent install

    /// Calling `installTextGeometryClasses(in:)` twice on the same context
    /// returns the same class objects (the global cache, not a
    /// re-evaluation), and a `Range` built from the first call's `Range` is
    /// `instanceof` the class the second call returns — a per-call
    /// re-evaluation would fail this second half even if it happened to
    /// answer object-identical-looking classes.
    @Test
    func installIsDeterministicAndCachedAcrossCalls() throws {
        let context = try #require(JSContext())
        let first = try #require(VSCodeAPI.installTextGeometryClasses(in: context))
        let second = try #require(VSCodeAPI.installTextGeometryClasses(in: context))
        let firstRangeClass = try #require(first["Range"])
        let secondRangeClass = try #require(second["Range"])
        #expect(firstRangeClass.isEqual(to: secondRangeClass))

        let firstPositionClass = try #require(first["Position"])
        let startPosition = try #require(firstPositionClass.construct(withArguments: [0, 0]))
        let endPosition = try #require(firstPositionClass.construct(withArguments: [0, 1]))
        let instanceFromFirst = try #require(firstRangeClass.construct(withArguments: [startPosition, endPosition]))
        #expect(instanceFromFirst.isInstance(of: secondRangeClass))
    }

    // MARK: - Task 5.6a-ii, mutation 1: Location(uri, position) is empty

    /// `new Location(uri, position)` sets `range` to an **empty** range whose
    /// `start` (and therefore `end`) equal that position — the "positions
    /// will be converted to an empty range" branch `vscode.d.ts:6976`
    /// documents. An implementation that stores the position directly, or
    /// that builds a range from some other position pair, turns this red: this
    /// checks both `range.isEmpty` and `range.start`'s fields, since an
    /// implementation could get one right without the other (e.g. answering
    /// an empty range at `(0, 0)` regardless of the position given).
    @Test
    func locationFromAPositionIsAnEmptyRangeAtThatPosition() throws {
        let context = try makeContext()
        context.evaluateScript(
            """
            var uri = Uri.file('/a.txt');
            var loc = new Location(uri, new Position(3, 7));
            """)
        let location = try #require(context.objectForKeyedSubscript("loc"))
        let range = try #require(location.forProperty("range"))
        let isEmpty = try #require(range.forProperty("isEmpty"))
        #expect(isEmpty.isBoolean)
        #expect(isEmpty.toBool() == true)
        let start = try #require(range.forProperty("start"))
        let end = try #require(range.forProperty("end"))
        #expect(start.forProperty("line")?.toInt32() == 3)
        #expect(start.forProperty("character")?.toInt32() == 7)
        #expect(end.forProperty("line")?.toInt32() == 3)
        #expect(end.forProperty("character")?.toInt32() == 7)
    }

    // MARK: - Task 5.6a-ii, mutation 2: Location(uri, range) keeps the range

    /// `new Location(uri, range)` keeps the given range **as-is** — the exact
    /// same object (`loc.range === r`), not merely one with equal fields —
    /// the other half of the constructor's dispatch, a separate mutation
    /// from the position case above: an implementation that always
    /// collapses its second argument to an empty range at its `start`
    /// (right for the position case, wrong here) turns the `isEmpty`/field
    /// assertions red, and one that copies the range instead of reusing it
    /// (right on fields, wrong on identity) turns the `===` assertion red
    /// while passing the position-case test above either way.
    @Test
    func locationFromARangeKeepsThatRange() throws {
        let context = try makeContext()
        context.evaluateScript(
            """
            var uri = Uri.file('/a.txt');
            var r = new Range(1, 0, 2, 4);
            var loc = new Location(uri, r);
            """)
        let location = try #require(context.objectForKeyedSubscript("loc"))
        let range = try #require(location.forProperty("range"))
        let isEmpty = try #require(range.forProperty("isEmpty"))
        #expect(isEmpty.isBoolean)
        #expect(isEmpty.toBool() == false)
        let start = try #require(range.forProperty("start"))
        let end = try #require(range.forProperty("end"))
        #expect(start.forProperty("line")?.toInt32() == 1)
        #expect(start.forProperty("character")?.toInt32() == 0)
        #expect(end.forProperty("line")?.toInt32() == 2)
        #expect(end.forProperty("character")?.toInt32() == 4)
        let sameR = try #require(context.evaluateScript("loc.range === r"))
        #expect(sameR.toBool() == true)
    }

    // MARK: - Task 5.6a-ii, mutation 11 (Location half): reader not duck-typed

    /// `VSCodeAPI.location(from:in:)` answers `nil` for a plain
    /// `{ uri, range }` object literal — even one whose `uri`/`range` are
    /// themselves real `Uri`/`Range` instances — because the **outer**
    /// object is not a real `Location`; the reader must not be fooled by
    /// matching shape one level up.
    @Test
    func locationFromRefusesADuckTypedLiteral() throws {
        let context = try makeContext()
        let literal = try #require(context.evaluateScript(
            "({ uri: Uri.file('/a.txt'), range: new Range(0, 0, 0, 1) })"))
        #expect(VSCodeAPI.location(from: literal, in: context) == nil)
    }

    /// `VSCodeAPI.location(from:in:)` reads a real
    /// `new Location(Uri.file(...), new Range(...))` instance back into a
    /// matching `ExtensionLocation` — proof the reader actually reads the
    /// real thing, which the refusal test alone does not establish.
    @Test
    func locationFromReadsARealLocationInstance() throws {
        let context = try makeContext()
        let real = try #require(context.evaluateScript(
            "new Location(Uri.file('/a.txt'), new Range(1, 2, 3, 4))"))
        let decoded = try #require(VSCodeAPI.location(from: real, in: context))
        #expect(decoded.uri.path == "/a.txt")
        #expect(decoded.range == VSCodeAPI.ExtensionRange(
            start: VSCodeAPI.ExtensionPosition(line: 1, character: 2),
            end: VSCodeAPI.ExtensionPosition(line: 3, character: 4)))
    }

    // MARK: - Task 5.6a-ii, mutation 12 (Location half): writer round-trips

    /// `locationValue(for:in:)` followed by `location(from:in:)` gives back
    /// an equal `ExtensionLocation`, and the JS value the writer produced is
    /// a real `instanceof Location` — not merely an object literal shaped
    /// like one, which a reader keyed only on property names could not
    /// catch (the duck-typed-refusal test above proves the reader would, in
    /// fact, reject such a literal).
    @Test
    func locationValueRoundTripsThroughTheReader() throws {
        let context = try makeContext()
        let original = VSCodeAPI.ExtensionLocation(
            uri: try #require(URL(string: "file:///a/b.txt")),
            range: VSCodeAPI.ExtensionRange(
                start: VSCodeAPI.ExtensionPosition(line: 2, character: 0),
                end: VSCodeAPI.ExtensionPosition(line: 2, character: 5)))
        let jsValue = try #require(
            VSCodeAPI.locationValue(for: original, in: context))
        context.setObject(jsValue, forKeyedSubscript: "roundTripped" as NSString)
        let isLocation = context.evaluateScript("roundTripped instanceof Location")
        #expect(isLocation?.toBool() == true)
        #expect(VSCodeAPI.location(from: jsValue, in: context) == original)
    }
}
