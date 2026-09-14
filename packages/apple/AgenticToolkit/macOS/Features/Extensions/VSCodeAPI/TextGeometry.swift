//
//  TextGeometry.swift
//  AgenticToolkit
//

import Foundation
import JavaScriptCore
import OSLog
import AgenticToolkitCore

/// `vscode.Position`, `vscode.Range` and `vscode.Location` — task 5.6a-i (the
/// first two classes) and task 5.6a-ii (`Location`, ledger Ruling 23's
/// second slice). No `Uri` class here — `Uri.swift` owns that — and no
/// `Diagnostic`/`DiagnosticSeverity`/`DiagnosticTag`/
/// `DiagnosticRelatedInformation`, which live in `DiagnosticTypes.swift`
/// instead; see the `Location` section below for why `Location` itself did
/// not join them there. Ledger Ruling 19 is why `Position`/`Range` exist at
/// all — there was no `vscode.Range` or `vscode.Position` anywhere in this
/// host, in Swift or in JavaScript, so an extension writing
/// `new vscode.Range(new vscode.Position(0, 0), new vscode.Position(0, 5))`
/// threw at the first `new`, before anything else in the host was reached.
///
/// **Ledger Ruling 24: `Position` and `Range` ship COMPLETE**, every member
/// `vscode.d.ts` declares for both classes, not the subset a later
/// diagnostics task happens to need — they are pure value types with no host
/// dependency and are prerequisites of `TextDocument`, of selections, and of
/// every editor API after this one. `Location` is the same kind of
/// prerequisite one task later: it is `Uri` + `Range`, and it appears in
/// `Definition`, `Reference`, `SymbolInformation` and `CallHierarchy` long
/// before any of those touch diagnostics — which is why it is built here,
/// beside the geometry it is made of, rather than in `DiagnosticTypes.swift`
/// beside the feature that first consumes it.
///
/// Same shape as `Uri.swift`, for the reason given there: an extension
/// constructs these, compares them with `instanceof`, holds them in
/// collections and passes them to host APIs by reference, so each needs a
/// real constructor function with a real prototype — a `@convention(block)`
/// closure cannot be `new`'d. Built together, in **one** evaluated source,
/// because `Range`'s constructor must be able to say `new Position(...)` and
/// `Location`'s constructor must be able to say `new Range(...)`; splitting
/// into separate evaluations would leave each later one unable to see the
/// earlier ones' declarations.
///
/// Declared-surface line numbers below are `vscode.d.ts:269-398` (`Position`)
/// and `:408-513` (`Range`), at the pinned VS Code commit
/// `3addbda66f9e80c3ed1b943822ab823bb6747b02`, whose copy at
/// `scratchpad/upstream/vscode.d.ts` hashes to
/// `4624902099d3eeb466fbb2422c09690143120e94a4cb70047c41f92058eae889`
/// (verified against `MANIFEST.txt` on 2026-09-13, the same day this file was
/// written). Three behaviors below are stated only by the *implementation*,
/// not by `vscode.d.ts`'s prose — measured against
/// `scratchpad/upstream/extHostTypes.position.ts`
/// (`0ea510e28831180e378efe9c20e8e8b666d5102b44ef1a2470905505a7ba2476`) and
/// `scratchpad/upstream/extHostTypes.range.ts`
/// (`29247138cd98d009c356155d304745d36cff0d3c4f19b1117ab364446f779a38`),
/// both hashes verified the same day, at the same pinned commit:
///
///   1. **`Range`'s constructor swaps on equal positions too.**
///      `vscode.d.ts:421-422` reads as "equal positions are not swapped";
///      the implementation's condition is `start.isBefore(end)`
///      (`range.ts:65`), which is *strict*, so two equal-but-distinct
///      `Position` objects take the `else` branch and are swapped anyway.
///      Unobservable by value, so this file follows the implementation and
///      does not add a test pinning object identity here — that would pin
///      an accident, not a contract.
///   2. **The constructor throws on a negative `line` or `character`**
///      (`position.ts:76-81`) rather than clamping to zero, and does so
///      independently for each field.
///   3. **`translate` and `with` answer the receiver itself (`this`), not a
///      copy, when nothing actually changes** (`position.ts:154-155,
///      180-181`; `range.ts:146-147`), and an explicit `null` argument
///      throws where an omitted (`undefined`) one does not
///      (`position.ts:140-141, 164-165`; `range.ts:130-131`).
///
/// **`Position.Min`, `Position.Max`, `Position.of` and `Position.isPosition`
/// exist upstream but are not in `vscode.d.ts`'s declared `Position`
/// surface**, and `Range.intersection`/`Range.union` need the first two
/// internally (`range.ts:96-97, 113-114`). Per the 5.6a upstream addendum's
/// ruling, they are implemented here as private helper functions in the
/// evaluated source — reachable from `Range`'s own methods, never attached
/// to the `Position`/`Range` objects extension code can see — because the
/// declared API is what a `tsc`-compiled extension is checked against, and a
/// static `vscode.Position.Min` a real VS Code extension can never legally
/// call would be exactly the kind of host-only surface this branch is
/// trying not to accumulate.
///
/// **Immutability, two ways, matching `Uri.swift`'s own convention:** every
/// instance is `Object.freeze`d at the end of its constructor
/// (`TextGeometry.swift:232`, `:394` below), exactly where `Uri.swift:114`
/// already does the same thing for its own instances — not a divergence
/// this task invented — closing the gap a bare getter-over-private-field
/// leaves open, since `this._line = value` from outside the class would
/// otherwise still succeed; and both classes' `prototype` and the class
/// objects themselves are frozen inside the same evaluation that builds
/// them, before this function ever hands them out, matching
/// `Uri.swift:253-254` (class freeze), for the identical reason
/// `Uri.swift:247-252`'s comment gives: there is no
/// window between a class existing and its being locked down. The instance
/// freeze is the half that actually diverges from upstream, whose
/// `Position`/`Range` are plain mutable objects: a strict-mode extension
/// that does `position.mine = 1` on a host-handed instance throws here and
/// silently succeeds in real VS Code.
///
/// **`Location` is the one exception to that instance freeze.**
/// `vscode.d.ts:6964` and `:6969` declare `uri` and `range` as plain stored
/// properties, and upstream's `Location` really is assignable:
/// `location.range = someRange` is ordinary extension code, and a frozen
/// instance would fail it — silently in sloppy mode, by throwing in strict
/// mode. So `Location`'s constructor assigns plain, writable own properties
/// and does not `Object.freeze(this)`.
///
/// A missing `readonly` is not by itself what decides this. `Range.isEmpty`
/// (`vscode.d.ts:443`) and `Range.isSingleLine` (`:448`) are declared without
/// it too, and both are installed below as read-only accessors anyway
/// (`defineRangeReadOnly`), because a value computed from `_start` and `_end`
/// has no assignment worth preserving. What separates `Location` is that its
/// two properties hold the state the object *is*.
///
/// Its class object and prototype are still frozen inside the same evaluation
/// as everything else here; only the per-instance freeze is withheld, and only
/// for this one class.
///
/// **The swap invariant lives in exactly one place: the JS `Range`
/// constructor.** Nothing on the Swift side reorders `start`/`end` before
/// constructing a JS value — `rangeValue(for:in:)`, below, always hands both
/// positions to `new Range(start, end)` and lets that constructor's own
/// `start.isBefore(end)` branch decide, so there is one swap to get right,
/// not two implementations of it that could quietly disagree.
extension VSCodeAPI {

    // MARK: - Installing the classes

    /// The global `installTextGeometryClasses(in:)` caches the container
    /// object under, once per context — `Uri.swift`'s `uriClassGlobalName`
    /// and `LanguageModelMessageVocabulary.swift`'s
    /// `languageModelVocabularyGlobalName`, generalized the same way both of
    /// those already are.
    ///
    /// Internal rather than `private`: `DiagnosticTypes.swift`'s constructors
    /// read `Range` and `Location` back out of this container to check their
    /// arguments against the real classes, and a second spelling of the name
    /// in that file is a second thing to keep in step with this one.
    static nonisolated let textGeometryGlobalName = "__vscodeTextGeometryClasses"

    /// `Position`, `Range` and `Location`'s own source, evaluated at most
    /// once per `JSContext`.
    ///
    /// ES5 idiom throughout — `var`, `function`, explicit prototypes, no
    /// `class`/`let`/arrow functions — matching `extension-runtime.js`,
    /// `Uri.swift` and `LanguageModelMessageVocabulary.swift`.
    private static nonisolated let textGeometryClassesSource = """
    (function () {
        'use strict';
        try {
            // `errors.ts`'s `illegalArgument` is not one of this branch's
            // pinned upstream files, so this reproduces only what
            // `position.ts`/`range.ts` actually observe about it: the
            // message text each call site passes, thrown as a plain `Error`.
            // Nothing here or in `vscode.d.ts` documents the thrown error's
            // class, so this file does not assert one either.
            function illegalArgument(message) {
                return new Error(message || 'Illegal argument');
            }

            // `Position.isPosition` (`position.ts:41-53`), kept as a private
            // helper rather than a static on `Position` — see this file's
            // header for why the declared statics stop at the constructor
            // and the eight methods (ten declared signatures, counting
            // `translate`/`with`'s two overloads each) `vscode.d.ts:269-398`
            // names.
            function positionIsPositionLike(value) {
                if (!value) {
                    return false;
                }
                if (value instanceof Position) {
                    return true;
                }
                return typeof value.line === 'number' && typeof value.character === 'number';
            }

            // `Position.of` (`position.ts:55-62`).
            function positionOf(value) {
                if (value instanceof Position) {
                    return value;
                }
                if (positionIsPositionLike(value)) {
                    return new Position(value.line, value.character);
                }
                throw new Error('Invalid argument, is NOT a position-like object');
            }

            // `Position.Min`/`Position.Max` (`position.ts:13-39`), reduced to
            // the two-argument case `Range.intersection`/`Range.union`
            // actually call (`range.ts:96-97, 113-114`) rather than the
            // upstream variadic form nothing here needs.
            function positionMin(first, second) {
                return first.isBefore(second) ? first : second;
            }
            function positionMax(first, second) {
                return first.isAfter(second) ? first : second;
            }

            // `Range.isRange` (`range.ts:14-23`), kept private for the same
            // reason `positionIsPositionLike` is: not in `vscode.d.ts`'s
            // declared `Range` surface.
            function rangeIsRangeLike(value) {
                if (value instanceof Range) {
                    return true;
                }
                if (!value || typeof value !== 'object') {
                    return false;
                }
                return positionIsPositionLike(value.start) && positionIsPositionLike(value.end);
            }

            // vscode.d.ts:269-398. Two readonly properties (line 274, 281),
            // a constructor (287) and eight methods in ten declared
            // signatures (:296, 305, 314, 323, 332, 342, 352, 361, 379, 388
            // — `translate` and `with` each contribute two).
            function Position(line, character) {
                if (line < 0) {
                    throw illegalArgument('line must be non-negative');
                }
                if (character < 0) {
                    throw illegalArgument('character must be non-negative');
                }
                this._line = line;
                this._character = character;
                // Closes the gap a getter-over-private-field leaves open:
                // without this, `position._line = -1` from outside the
                // class would silently succeed. See this file's header.
                Object.freeze(this);
            }

            function definePositionReadOnly(name, getter) {
                Object.defineProperty(Position.prototype, name, { get: getter, enumerable: true });
            }
            definePositionReadOnly('line', function () { return this._line; });
            definePositionReadOnly('character', function () { return this._character; });

            // vscode.d.ts:289-296.
            Position.prototype.isBefore = function (other) {
                if (this._line < other._line) {
                    return true;
                }
                if (other._line < this._line) {
                    return false;
                }
                return this._character < other._character;
            };

            // vscode.d.ts:298-305.
            Position.prototype.isBeforeOrEqual = function (other) {
                if (this._line < other._line) {
                    return true;
                }
                if (other._line < this._line) {
                    return false;
                }
                return this._character <= other._character;
            };

            // vscode.d.ts:307-314. Defined in terms of `isBeforeOrEqual`,
            // not independently — `position.ts:107` does the same, and it is
            // the only way all four comparisons agree on equal positions.
            Position.prototype.isAfter = function (other) {
                return !this.isBeforeOrEqual(other);
            };

            // vscode.d.ts:316-323. Defined in terms of `isBefore`
            // (`position.ts:111`), for the same reason as `isAfter` above.
            Position.prototype.isAfterOrEqual = function (other) {
                return !this.isBefore(other);
            };

            // vscode.d.ts:325-332.
            Position.prototype.isEqual = function (other) {
                return this._line === other._line && this._character === other._character;
            };

            // vscode.d.ts:334-342.
            Position.prototype.compareTo = function (other) {
                if (this._line < other._line) {
                    return -1;
                }
                if (this._line > other._line) {
                    return 1;
                }
                if (this._character < other._character) {
                    return -1;
                }
                if (this._character > other._character) {
                    return 1;
                }
                return 0;
            };

            // vscode.d.ts:344-370 (both overloads dispatch through this one
            // function, on the shape of the first argument — an object goes
            // through the `change` branch, everything else through the
            // `lineDelta`/`characterDelta` branch). An explicit `null` for
            // either argument throws (`position.ts:140-141`); an omitted
            // (`undefined`) one means a zero delta and does not
            // (`position.ts:145-146`, `:150-151`). Answers `this`, not a
            // copy, when the computed delta is zero in both fields
            // (`position.ts:154-155`) — the identity `TextGeometryTests`
            // pins as "immutability" is this branch, not merely "produces an
            // equal value".
            Position.prototype.translate = function (lineDeltaOrChange, characterDeltaArg) {
                if (lineDeltaOrChange === null || characterDeltaArg === null) {
                    throw illegalArgument();
                }
                var characterDelta = typeof characterDeltaArg === 'undefined' ? 0 : characterDeltaArg;
                var lineDelta;
                if (typeof lineDeltaOrChange === 'undefined') {
                    lineDelta = 0;
                } else if (typeof lineDeltaOrChange === 'number') {
                    lineDelta = lineDeltaOrChange;
                } else {
                    lineDelta = typeof lineDeltaOrChange.lineDelta === 'number' ? lineDeltaOrChange.lineDelta : 0;
                    characterDelta = typeof lineDeltaOrChange.characterDelta === 'number'
                        ? lineDeltaOrChange.characterDelta : 0;
                }
                if (lineDelta === 0 && characterDelta === 0) {
                    return this;
                }
                return new Position(this.line + lineDelta, this.character + characterDelta);
            };

            // vscode.d.ts:372-397. Same dispatch-on-shape as `translate`
            // above, but the asymmetry `vscode.d.ts` deliberately draws: an
            // *omitted* field (positional `undefined`, or a missing/`
            // non-number object field) keeps the field's **current** value,
            // never zero — `position.ts:169-170`, `:176-177`. Explicit
            // `null` throws (`position.ts:164-165`); answers `this` when
            // nothing changes (`:180-181`).
            Position.prototype.with = function (lineOrChange, characterArg) {
                if (lineOrChange === null || characterArg === null) {
                    throw illegalArgument();
                }
                var character = typeof characterArg === 'undefined' ? this.character : characterArg;
                var line;
                if (typeof lineOrChange === 'undefined') {
                    line = this.line;
                } else if (typeof lineOrChange === 'number') {
                    line = lineOrChange;
                } else {
                    line = typeof lineOrChange.line === 'number' ? lineOrChange.line : this.line;
                    character = typeof lineOrChange.character === 'number' ? lineOrChange.character : this.character;
                }
                if (line === this.line && character === this.character) {
                    return this;
                }
                return new Position(line, character);
            };

            // vscode.d.ts:408-513. Two readonly properties (413, 418), two
            // constructor overloads (427, 438), two computed properties
            // (`isEmpty` :443, `isSingleLine` :448) and five methods in six
            // declared signatures (:457, 466, 476, 484, 494, 503 — `with`
            // contributes two).
            function Range(startLineOrStart, startColumnOrEnd, endLine, endColumn) {
                var start;
                var end;
                if (typeof startLineOrStart === 'number' && typeof startColumnOrEnd === 'number'
                    && typeof endLine === 'number' && typeof endColumn === 'number') {
                    start = new Position(startLineOrStart, startColumnOrEnd);
                    end = new Position(endLine, endColumn);
                } else if (positionIsPositionLike(startLineOrStart) && positionIsPositionLike(startColumnOrEnd)) {
                    // Duck-typed, matching `range.ts:56-58` — a plain
                    // `{ line, character }` pair is legal here even though
                    // `vscode.d.ts:427` types both parameters as `Position`,
                    // because a `tsc`-compiled extension's own object
                    // literal can satisfy that type structurally.
                    start = positionOf(startLineOrStart);
                    end = positionOf(startColumnOrEnd);
                }
                if (!start || !end) {
                    throw new Error('Invalid arguments');
                }
                // vscode.d.ts:421-422 reads as "equal positions are not
                // swapped"; `isBefore` is strict, so two equal-but-distinct
                // positions take the `else` branch and ARE swapped, matching
                // `range.ts:65-71` exactly (see this file's header, point 1).
                // Unobservable by value; this file follows the
                // implementation, not the prose.
                if (start.isBefore(end)) {
                    this._start = start;
                    this._end = end;
                } else {
                    this._start = end;
                    this._end = start;
                }
                Object.freeze(this);
            }

            function defineRangeReadOnly(name, getter) {
                Object.defineProperty(Range.prototype, name, { get: getter, enumerable: true });
            }
            defineRangeReadOnly('start', function () { return this._start; });
            defineRangeReadOnly('end', function () { return this._end; });
            defineRangeReadOnly('isEmpty', function () { return this._start.isEqual(this._end); });
            defineRangeReadOnly('isSingleLine', function () { return this._start.line === this._end.line; });

            // vscode.d.ts:450-457. Accepts either a `Position` or a `Range`,
            // dispatching on shape (`range.ts:74-89`) — the `Range` half
            // recurses into two `Position` checks, so an implementation that
            // only ever compared against a `Position` argument would still
            // pass a `Position`-only test and fail a `Range`-shaped one.
            //
            // The `Position` branch below deliberately
            // diverges from `range.ts:83`: upstream compares
            // `this._end.isBefore(positionOrRange)` against the **raw**
            // argument, while this converts it through `positionOf` first
            // (`asPosition`, used both here and in the `isBefore` check
            // above it). For a duck-typed literal well past `this._end`,
            // upstream's raw comparison reads `undefined` off every field of
            // its own `_line`/`_character` lookup and every comparison
            // answers `false`, so upstream's `isBefore` call itself returns
            // `false` and `contains` incorrectly answers `true`; converting
            // first makes the fields real numbers, so this implementation
            // correctly answers `false`. The divergence is a deliberate
            // improvement over the cited lines, not an oversight.
            Range.prototype.contains = function (positionOrRange) {
                if (rangeIsRangeLike(positionOrRange)) {
                    return this.contains(positionOrRange.start) && this.contains(positionOrRange.end);
                }
                if (positionIsPositionLike(positionOrRange)) {
                    var asPosition = positionOf(positionOrRange);
                    if (asPosition.isBefore(this._start)) {
                        return false;
                    }
                    if (this._end.isBefore(asPosition)) {
                        return false;
                    }
                    return true;
                }
                return false;
            };

            // vscode.d.ts:459-466. Deliberately NOT duck-typed
            // (`range.ts:91-93` reads `other._start` directly), unlike
            // `contains` above — the asymmetry is upstream's own, not a
            // simplification made here.
            Range.prototype.isEqual = function (other) {
                return this._start.isEqual(other._start) && this._end.isEqual(other._end);
            };

            // vscode.d.ts:468-476. Returns `undefined` only when the
            // computed start is strictly *after* the computed end
            // (`range.ts:98`) — two ranges that merely touch at one point
            // produce an empty range here, not `undefined`. This file's test
            // for "no overlap" uses a genuinely disjoint pair for exactly
            // that reason.
            Range.prototype.intersection = function (other) {
                var start = positionMax(other.start, this._start);
                var end = positionMin(other.end, this._end);
                if (start.isAfter(end)) {
                    return undefined;
                }
                return new Range(start, end);
            };

            // vscode.d.ts:478-484. Answers an existing object by identity
            // when one range already contains the other (`range.ts:108-111`),
            // and only otherwise constructs a new one.
            Range.prototype.union = function (other) {
                if (this.contains(other)) {
                    return this;
                }
                if (other.contains(this)) {
                    return other;
                }
                var start = positionMin(other.start, this._start);
                var end = positionMax(other.end, this._end);
                return new Range(start, end);
            };

            // vscode.d.ts:486-512 (both overloads). `startOrChange` decides
            // the branch the same way `Position.prototype.with` does; the
            // object-form field lookups here use upstream's own `||`
            // fallback (`range.ts:142-143`), not the `typeof === 'number'`
            // check `Position.prototype.with` uses, because that is what
            // `range.ts:126-150` actually does — preserved as-is rather than
            // reconciled with `Position`'s stricter check. Explicit `null`
            // throws (`range.ts:130-131`); answers `this` when nothing
            // changes (`:146-147`).
            Range.prototype.with = function (startOrChange, endArg) {
                if (startOrChange === null || endArg === null) {
                    throw illegalArgument();
                }
                var end = typeof endArg === 'undefined' ? this.end : endArg;
                var start;
                if (!startOrChange) {
                    start = this.start;
                } else if (positionIsPositionLike(startOrChange)) {
                    start = startOrChange;
                } else {
                    start = startOrChange.start || this.start;
                    end = startOrChange.end || this.end;
                }
                if (start.isEqual(this._start) && end.isEqual(this._end)) {
                    return this;
                }
                return new Range(start, end);
            };

            // vscode.d.ts:6960-6979 (task 5.6a-ii). Built here, not in
            // `DiagnosticTypes.swift`, per this file's header: it needs
            // `Range`'s constructor, which only exists in this evaluation.
            //
            // **Deliberately mutable, unlike `Position` and `Range` above.**
            // Neither `uri` nor `range` is `readonly` in the declaration, so
            // this constructor does not `Object.freeze(this)` — adding that
            // guarantee would be exactly the defect this file's header warns
            // against: promising an immutability `vscode.d.ts` never
            // promised.
            //
            // `Location.isLocation` and `Location.prototype.toJSON`
            // (`extHostTypes.location.ts:15-24`, `:43-48`) are both
            // upstream-only — neither is in `vscode.d.ts`'s declared
            // `Location` surface, so neither is implemented here, matching
            // the declared-surface-only boundary this file already draws
            // for `Position.isPosition`/`Range.isRange`.
            function Location(uri, rangeOrPosition) {
                this.uri = uri;
                if (!rangeOrPosition) {
                    // extHostTypes.location.ts:32-33: a falsy second
                    // argument leaves `range` unset entirely. `vscode.d.ts`
                    // declares `range: Range;` at `:6970` — always present —
                    // while the implementation
                    // at `extHostTypes.location.ts:27` declares its own
                    // field `range!: Range;` (definite assignment,
                    // asserting a value arrives before any read). Leaving
                    // `range` unset here follows upstream's
                    // *implementation*, not the stricter declared surface.
                } else if (rangeIsRangeLike(rangeOrPosition)) {
                    // extHostTypes.location.ts:34-35 (`Range.of`): reuse the
                    // same instance by identity when a real `Range` was
                    // already handed in; only a duck-typed range-shaped
                    // literal gets rebuilt into a genuine one.
                    this.range = rangeOrPosition instanceof Range
                        ? rangeOrPosition
                        : new Range(rangeOrPosition.start, rangeOrPosition.end);
                } else if (positionIsPositionLike(rangeOrPosition)) {
                    // extHostTypes.location.ts:36-37; vscode.d.ts:6976:
                    // "Positions will be converted to an empty range."
                    // `new Range(p, p)` is empty because its own
                    // `start.isEqual(end)` compares one position to itself.
                    this.range = new Range(rangeOrPosition, rangeOrPosition);
                } else {
                    throw new Error('Illegal argument');
                }
            }

            // Frozen after every static and prototype member is attached,
            // inside the same evaluation that built them — `Uri.swift:247-254`'s
            // reasoning, applied to all three classes at once: there is no
            // window between any of them existing and its being locked down.
            // `Location`'s own *instances* are the one thing this block does
            // not freeze — see the header and the comment above `Location`
            // itself for why.
            Object.freeze(Position.prototype);
            Object.freeze(Position);
            Object.freeze(Range.prototype);
            Object.freeze(Range);
            Object.freeze(Location.prototype);
            Object.freeze(Location);

            var result = { Position: Position, Range: Range, Location: Location };

            try {
                Object.defineProperty(globalThis, '\(textGeometryGlobalName)', {
                    value: result,
                    writable: false,
                    enumerable: false,
                    configurable: false
                });
            } catch (ignored) {
                // Caching is an optimisation, exactly as in `uriClassSource`
                // and `languageModelVocabularySource`; both classes work
                // without it, just re-evaluated per call.
            }
            return result;
        } catch (error) {
            // Discarding `error` entirely (`return null;`) would leave the
            // Swift-side log with no way to say why the evaluation failed.
            // `Uri.swift`'s own installer does the identical
            // `catch (error) { return null; }` and is no better here — this
            // is the improvement, not a divergence from a precedent worth
            // matching. `installedError` is a distinct shape from the real
            // `{ Position, Range }` container above, so
            // `installTextGeometryClasses(in:)` below can tell failure from
            // success without a `Position`/`Range` property ever colliding
            // with it.
            return { installedError: error && error.message ? error.message : 'unknown error' };
        }
    })()
    """

    /// `vscode.Position`, `vscode.Range` and `vscode.Location` for `context`,
    /// evaluating the source the first time and reading the cached container
    /// back afterwards — `installUriClass(in:)`'s exact pattern, generalized
    /// from one class to three read off one container object, the same
    /// generalization `installLanguageModelVocabulary(in:)` already made to
    /// eight.
    ///
    /// Calling this twice on one context answers the **same** `Position`,
    /// `Range` and `Location` objects both times — the global cache, not a
    /// re-evaluation — which is what makes a `Range` built from the first
    /// call's `Range` still `instanceof` the class the second call returns.
    ///
    /// Returns `nil` on failure, `installUriClass(in:)`'s own failure mode: a
    /// context that cannot host these classes yet is not fatal to
    /// activation, and `vscode.Position`/`vscode.Range`/`vscode.Location`
    /// simply stay the shim's not-implemented stub.
    ///
    /// The same residual `installUriClass(in:)` documents at length applies
    /// here unchanged: a context where `ExtensionHost.installRuntime`'s eager
    /// install did not run first can reach this function from a later, lazy
    /// caller and adopt whatever object already sits under
    /// `textGeometryGlobalName`, real or not, with no way to tell the
    /// difference.
    public static func installTextGeometryClasses(in context: JSContext) -> [String: JSValue]? {
        let container: JSValue
        if let cached = context.objectForKeyedSubscript(textGeometryGlobalName), cached.isObject {
            container = cached
        } else {
            guard let created = context.evaluateScript(textGeometryClassesSource), created.isObject else {
                logger.error(
                    """
                    Could not install the 'vscode.Position'/'vscode.Range'/ \
                    'vscode.Location' classes in context \
                    '\(name(of: context), privacy: .public)'; they stay the \
                    shim's not-implemented stub
                    """)
                return nil
            }
            // The evaluated source's outer `catch` reports
            // failure as `{ installedError: <message> }` rather than
            // discarding it, so this can log the actual reason instead of
            // only "could not install".
            if let installError = created.forProperty("installedError"), !installError.isUndefined {
                logger.error(
                    """
                    Could not install the 'vscode.Position'/'vscode.Range'/ \
                    'vscode.Location' classes in context \
                    '\(name(of: context), privacy: .public)': \
                    '\(installError.toString() ?? "unknown error", privacy: .public)'; \
                    they stay the shim's not-implemented stub
                    """)
                return nil
            }
            container = created
        }

        guard let positionClass = container.forProperty("Position"), positionClass.isObject,
              let rangeClass = container.forProperty("Range"), rangeClass.isObject,
              let locationClass = container.forProperty("Location"),
              locationClass.isObject else {
            logger.error(
                """
                The 'vscode' text-geometry container in context \
                '\(name(of: context), privacy: .public)' is missing 'Position', \
                'Range' or 'Location'; all three stay the shim's not-implemented \
                stub
                """)
            return nil
        }
        return ["Position": positionClass, "Range": rangeClass, "Location": locationClass]
    }

    // MARK: - Swift ↔ JS bridging

    /// The extension host's own mirror of a `vscode.Position` — the
    /// `Extension` prefix `ExtensionManifest` already establishes in this
    /// tier, needed here because `Position` and `Range` are both taken in
    /// Swift's own namespace.
    public struct ExtensionPosition: Sendable, Equatable, Hashable {
        public let line: Int
        public let character: Int

        public init(line: Int, character: Int) {
            self.line = line
            self.character = character
        }
    }

    /// The extension host's own mirror of a `vscode.Range`.
    public struct ExtensionRange: Sendable, Equatable, Hashable {
        public let start: ExtensionPosition
        public let end: ExtensionPosition

        public init(start: ExtensionPosition, end: ExtensionPosition) {
            self.start = start
            self.end = end
        }
    }

    /// Reads an `ExtensionPosition` out of a JavaScript value that is a real
    /// `vscode.Position` instance — `url(from:in:)`'s shape, generalized to
    /// this type.
    ///
    /// **Deliberately not duck-typed**, for `url(from:in:)`'s own reason
    /// (`Uri.swift:348-355`): a plain `{ line: 1, character: 2 }` object
    /// literal answers `nil` here rather than being read for `line`/
    /// `character`-shaped properties, because reading properties off an
    /// object this bridge does not control can run extension-authored
    /// getters. `value.isInstance(of:)` is the same check `url(from:in:)`
    /// makes before trusting anything else about `value`.
    public static func position(from value: JSValue, in context: JSContext) -> ExtensionPosition? {
        guard let classes = installTextGeometryClasses(in: context),
              let positionClass = classes["Position"],
              value.isInstance(of: positionClass) else {
            return nil
        }
        guard let lineValue = value.forProperty("line"), lineValue.isNumber,
              let characterValue = value.forProperty("character"), characterValue.isNumber else {
            return nil
        }
        return ExtensionPosition(line: Int(lineValue.toInt32()), character: Int(characterValue.toInt32()))
    }

    /// Reads an `ExtensionRange` out of a JavaScript value that is a real
    /// `vscode.Range` instance — `position(from:in:)`'s exact reasoning,
    /// generalized to a pair of positions. Not duck-typed for the same
    /// reason; a plain `{ start: {...}, end: {...} }` object answers `nil`.
    public static func range(from value: JSValue, in context: JSContext) -> ExtensionRange? {
        guard let classes = installTextGeometryClasses(in: context),
              let rangeClass = classes["Range"],
              value.isInstance(of: rangeClass) else {
            return nil
        }
        guard let startValue = value.forProperty("start"),
              let start = position(from: startValue, in: context),
              let endValue = value.forProperty("end"),
              let end = position(from: endValue, in: context) else {
            return nil
        }
        return ExtensionRange(start: start, end: end)
    }

    /// Builds a real `vscode.Position` instance in `context` for `position`
    /// — the reverse of `position(from:in:)`, for a member that must hand a
    /// `Position` the app already has back to the extension, the same
    /// obligation `uriValue(for:in:)` documents for `Uri`: a plain object
    /// literal here would not be `instanceof vscode.Position`, which is the
    /// same defect in the other direction.
    ///
    /// Goes through the real, frozen `Position` constructor rather than
    /// building a bag of properties, so a negative `line` or `character` —
    /// which should never reach this function from real host state, but
    /// nothing here enforces that upstream of the call — throws the
    /// constructor's own `illegalArgument`, exactly as it would for
    /// extension-authored code hitting the same constructor.
    public static func positionValue(for position: ExtensionPosition, in context: JSContext) -> JSValue? {
        guard let classes = installTextGeometryClasses(in: context),
              let positionClass = classes["Position"] else {
            return nil
        }
        guard let result = positionClass.construct(withArguments: [position.line, position.character]),
              !result.isUndefined, !result.isNull else {
            return nil
        }
        return result
    }

    /// Builds a real `vscode.Range` instance in `context` for `range` — the
    /// reverse of `range(from:in:)`.
    ///
    /// **This is the one place the Swift-side swap invariant is enforced,
    /// and it enforces it by not enforcing it itself.** `start` and `end`
    /// are handed to `new Range(start, end)` in the order `range` carries
    /// them, exactly as the JS constructor built from
    /// `textGeometryClassesSource` requires; that constructor's own
    /// `start.isBefore(end)` branch (see this file's header) is what
    /// reorders them if `range.end` was before `range.start` to begin with.
    /// An `ExtensionRange` built in Swift with `end` before `start` therefore
    /// still produces a JS range satisfying `start.isBeforeOrEqual(end)` —
    /// without this function duplicating the swap logic the constructor
    /// already has.
    public static func rangeValue(for range: ExtensionRange, in context: JSContext) -> JSValue? {
        guard let classes = installTextGeometryClasses(in: context),
              let rangeClass = classes["Range"] else {
            return nil
        }
        guard let startValue = positionValue(for: range.start, in: context),
              let endValue = positionValue(for: range.end, in: context) else {
            return nil
        }
        guard let result = rangeClass.construct(withArguments: [startValue, endValue]),
              !result.isUndefined, !result.isNull else {
            return nil
        }
        return result
    }

    /// Swift mirror of a `vscode.Location` (vscode.d.ts:6960-6979): a `Uri`
    /// paired with the `Range` it names within that resource. Plain data,
    /// same as `ExtensionPosition`/`ExtensionRange` above — the JS side's
    /// `Location` is the one that is mutable (see this file's header); this
    /// struct just carries the two values across the JS/Swift boundary.
    public struct ExtensionLocation: Sendable, Equatable {
        public let uri: URL
        public let range: ExtensionRange

        public init(uri: URL, range: ExtensionRange) {
            self.uri = uri
            self.range = range
        }
    }

    /// Reads `value` back into an `ExtensionLocation` if — and only if — it
    /// is a real `vscode.Location` instance, the same
    /// `isInstance(of:)`-before-properties discipline `range(from:in:)` and
    /// `url(from:in:)` (`Uri.swift:343-366` at submodule commit
    /// `c83bd261`) both use: a `{ uri, range }`
    /// object literal that merely looks like one answers `nil` rather than
    /// having its properties read, so an extension cannot forge a `Location`
    /// out of duck-typed data.
    public static func location(from value: JSValue, in context: JSContext) -> ExtensionLocation? {
        guard let classes = installTextGeometryClasses(in: context),
              let locationClass = classes["Location"],
              value.isInstance(of: locationClass) else {
            return nil
        }
        guard let uriProperty = value.forProperty("uri"),
              let uri = url(from: uriProperty, in: context),
              let rangeProperty = value.forProperty("range"),
              let decodedRange = range(from: rangeProperty, in: context) else {
            return nil
        }
        return ExtensionLocation(uri: uri, range: decodedRange)
    }

    /// Builds a real `vscode.Location` instance in `context` for `location`
    /// — the reverse of `location(from:in:)`, following
    /// `positionValue(for:in:)` and `rangeValue(for:in:)` above: go through
    /// the real constructor rather than a bag of properties, so the result
    /// is genuinely `instanceof vscode.Location`.
    public static func locationValue(for location: ExtensionLocation, in context: JSContext) -> JSValue? {
        guard let classes = installTextGeometryClasses(in: context),
              let locationClass = classes["Location"] else {
            return nil
        }
        guard let uriJSValue = uriValue(for: location.uri, in: context),
              let rangeJSValue = rangeValue(for: location.range, in: context) else {
            return nil
        }
        guard let result = locationClass.construct(withArguments: [uriJSValue, rangeJSValue]),
              !result.isUndefined, !result.isNull else {
            return nil
        }
        return result
    }
}
