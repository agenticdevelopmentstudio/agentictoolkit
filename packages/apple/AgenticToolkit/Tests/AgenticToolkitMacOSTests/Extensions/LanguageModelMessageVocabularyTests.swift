import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitMacOS

/// The eight `vscode.LanguageModel*` members task 5.7a-i installs
/// (`VSCodeAPI.installLanguageModelVocabulary(in:)`): the
/// `LanguageModelChatMessageRole` enum, `LanguageModelChatMessage`, and the
/// six content-part/result classes it and `LanguageModelToolResultPart`
/// carry (`LanguageModelToolCallPart`, `LanguageModelToolResultPart`,
/// `LanguageModelTextPart`, `LanguageModelPromptTsxPart`,
/// `LanguageModelToolResult`, `LanguageModelDataPart`).
///
/// A bare `JSContext`, not an `ExtensionHost` — `installLanguageModelVocabulary(in:)`
/// takes a `JSContext` and nothing else, matching `UriTests`'s own reasoning
/// for `installUriClass(in:)`.
///
/// Each `@Test` that maps to one of the task-5.7a-i brief's ten numbered
/// mutations names it in its doc ("mutation N"); the tests that do not map to
/// any of the ten say so instead. Deliberately left untested, stated once
/// here rather than in every test that could have covered it: the
/// type-level-only distinction between `LanguageModelChatMessage.User`
/// accepting a `LanguageModelToolResultPart` in its content array and
/// `.Assistant` accepting a `LanguageModelToolCallPart` (neither is enforced
/// at runtime, and the brief says not to add a runtime check upstream does
/// not have); and the three PROPOSED members out of scope by Ruling 1
/// (`LanguageModelChatMessageRole.System` beyond confirming the enum has
/// exactly two members and is frozen, `LanguageModelToolResultPart.isError`,
/// `LanguageModelTextPart`/`LanguageModelDataPart`'s `audience`) — there is
/// nothing installed to assert their absence against beyond the enum-size
/// check; and the absence of `toJSON` (not in `vscode.d.ts`, so nothing here
/// constructs an expectation of it).
@MainActor
@Suite
struct LanguageModelMessageVocabularyTests {

    /// A fresh context with all eight members installed and exposed as
    /// plain globals under their own names, so a test's own script can read
    /// them the way extension code reads `vscode.LanguageModelXxx` —
    /// `UriTests.makeContext()`'s exact pattern, generalised to eight names.
    private func makeContext() throws -> JSContext {
        let context = try #require(JSContext())
        let members = try #require(VSCodeAPI.installLanguageModelVocabulary(in: context))
        for (memberName, memberValue) in members {
            context.setObject(memberValue, forKeyedSubscript: memberName as NSString)
        }
        return context
    }

    // MARK: - LanguageModelChatMessage.content (mutations 1 and 2)

    /// Mutation 1: `content` coerces a string only in the constructor, not
    /// in the setter. A message is constructed with a non-string `content`
    /// (an empty array), then `.content` is assigned a string strictly
    /// *after* construction — the only place a constructor-only coercion
    /// would fail to run. `Array.isArray` on the result is enough to fail:
    /// an uncoerced setter leaves the raw string in place, and
    /// `Array.isArray` of a string is `false`.
    ///
    /// Does not kill: whether the wrapped element is the correct type —
    /// `contentCoercionWrapsAStringInATextPartWithTheGivenValue` below
    /// covers that, through the constructor's own call into the same
    /// setter, so a wrong-type bug is visible on that path too.
    @Test
    func contentSetterReCoercesAStringAfterConstruction() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            """
            (function () {
                var message = new LanguageModelChatMessage(1, [], undefined);
                message.content = 'replaced';
                var content = message.content;
                return Array.isArray(content) && content.length === 1;
            })()
            """
        ))
        #expect(result.toBool() == true)
    }

    /// Mutation 2: `content` coercion wraps a string in the wrong type, or
    /// does not wrap at all. `LanguageModelChatMessage.User('hello')` routes
    /// through the constructor's `this.content = content`, which is the
    /// same setter `contentSetterReCoercesAStringAfterConstruction` exercises
    /// after construction — so a wrong-type bug in that setter is visible on
    /// either path, and this test uses the construction path to keep the two
    /// mutations' fixtures independent of each other.
    @Test
    func contentCoercionWrapsAStringInATextPartWithTheGivenValue() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            """
            (function () {
                var message = LanguageModelChatMessage.User('hello');
                var content = message.content;
                return Array.isArray(content) &&
                    content.length === 1 &&
                    (content[0] instanceof LanguageModelTextPart) &&
                    content[0].value === 'hello';
            })()
            """
        ))
        #expect(result.toBool() == true)
    }

    // MARK: - LanguageModelChatMessage.User / .Assistant (mutation 3)

    /// Mutation 3: `.User` and `.Assistant` set the wrong role value. Both
    /// are constructed and their roles compared against the two distinct
    /// enum values (`1` and `2`) and against each other, so a stub that
    /// gives both the same role — or swaps them — fails here even though a
    /// fixture testing only one factory would not catch it.
    @Test
    func userAndAssistantSetDistinctRoleValues() throws {
        let context = try makeContext()
        let userRole = try #require(context.evaluateScript("LanguageModelChatMessage.User('hi').role"))
        let assistantRole = try #require(context.evaluateScript("LanguageModelChatMessage.Assistant('hi').role"))
        #expect(userRole.toInt32() == 1)
        #expect(assistantRole.toInt32() == 2)
    }

    // MARK: - LanguageModelDataPart.json (mutations 4, 5, part of 7)

    /// Mutation 4: `json`'s default mime is `application/json` rather than
    /// `'text/x-json'` (`extHostTypes.ts:4066`).
    @Test
    func jsonDefaultMimeIsTextXJsonNotApplicationJson() throws {
        let context = try makeContext()
        let part = try #require(context.evaluateScript("LanguageModelDataPart.json({ a: 1 })"))
        #expect(part.forProperty("mimeType")?.toString() == "text/x-json")
    }

    /// Mutation 5: `json` stringifies compactly rather than tab-indented.
    /// The bytes in `.data` are decoded back to a string (every character in
    /// this fixture's JSON output is ASCII, so one byte per `String.fromCharCode`
    /// call is a faithful decode) and compared against this same `JSContext`'s
    /// own `JSON.stringify(value, undefined, '\t')` — a compact stub produces
    /// a visibly different string (no tabs, no newlines), so this is not an
    /// assertion a compact implementation could pass by chance.
    @Test
    func jsonStringifiesTabIndentedNotCompact() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            """
            (function () {
                var value = { a: 1, b: 2 };
                var part = LanguageModelDataPart.json(value);
                var expected = JSON.stringify(value, undefined, '\\t');
                var bytes = part.data;
                var decoded = '';
                for (var i = 0; i < bytes.length; i += 1) {
                    decoded += String.fromCharCode(bytes[i]);
                }
                return decoded === expected;
            })()
            """
        ))
        #expect(result.toBool() == true)
    }

    // MARK: - LanguageModelDataPart.text (mutation 6, part of 7)

    /// Mutation 6: `text`'s default mime is anything but `'text/plain'`
    /// (`Mimes.text`, measured at `mime.ts:9`).
    @Test
    func textDefaultMimeIsTextPlain() throws {
        let context = try makeContext()
        let part = try #require(context.evaluateScript("LanguageModelDataPart.text('hello')"))
        #expect(part.forProperty("mimeType")?.toString() == "text/plain")
    }

    // MARK: - Explicit mime overrides the default (mutation 7)

    /// Mutation 7: an explicit `mime` argument is ignored in favour of the
    /// default, in `json` and in `text`. One test covering both, since both
    /// factories share the same "ignores the argument" failure shape and
    /// asserting them together does not weaken either half — each assertion
    /// still fails independently if its factory ignores the explicit mime.
    @Test
    func explicitMimeOverridesTheDefaultForJsonAndText() throws {
        let context = try makeContext()
        let jsonPart = try #require(context.evaluateScript(
            "LanguageModelDataPart.json({ a: 1 }, 'application/custom+json')"))
        #expect(jsonPart.forProperty("mimeType")?.toString() == "application/custom+json")
        let textPart = try #require(context.evaluateScript(
            "LanguageModelDataPart.text('hello', 'text/custom')"))
        #expect(textPart.forProperty("mimeType")?.toString() == "text/custom")
    }

    // MARK: - LanguageModelChatMessageRole (mutation 8)

    /// Mutation 8: the role enum carries a `System` member. The enum is
    /// implemented as a plain frozen object with no reverse mapping, so
    /// `Object.keys` names exactly its forward entries — a later
    /// well-meaning addition of `System` changes this count from two to
    /// three and turns this test red, per the brief's own framing. Also
    /// asserts the enum itself is frozen (`Object.freeze(LanguageModelChatMessageRole)`
    /// at vocab:168) — the one freeze in this file `constructedPartsAreRealInstancesAndClassesAreFrozen`
    /// does not cover, since the enum is a plain object rather than one of
    /// the seven constructor functions that test checks.
    @Test
    func roleEnumHasExactlyTwoMembers() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            """
            (function () {
                var keys = Object.keys(LanguageModelChatMessageRole);
                return keys.length === 2 &&
                    LanguageModelChatMessageRole.User === 1 &&
                    LanguageModelChatMessageRole.Assistant === 2 &&
                    typeof LanguageModelChatMessageRole.System === 'undefined' &&
                    Object.isFrozen(LanguageModelChatMessageRole);
            })()
            """
        ))
        #expect(result.toBool() == true)
    }

    // MARK: - instanceof and freezing (mutation 9)

    /// Mutation 9: `instanceof` is broken for a constructed part, or the
    /// classes are not frozen. One instance of each of the seven constructor
    /// functions (the enum is a plain object, not a class, so it is checked
    /// separately — its own freeze, by `roleEnumHasExactlyTwoMembers`) is
    /// checked against its own class with `instanceof`, and each class and
    /// its prototype is checked with `Object.isFrozen`, exactly as the
    /// mutation names both checks.
    @Test
    func constructedPartsAreRealInstancesAndClassesAreFrozen() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            """
            (function () {
                var cases = [
                    [LanguageModelTextPart, new LanguageModelTextPart('v')],
                    [LanguageModelPromptTsxPart, new LanguageModelPromptTsxPart('v')],
                    [LanguageModelToolCallPart, new LanguageModelToolCallPart('id', 'name', {})],
                    [LanguageModelToolResultPart, new LanguageModelToolResultPart('id', [])],
                    [LanguageModelToolResult, new LanguageModelToolResult([])],
                    [LanguageModelDataPart, new LanguageModelDataPart(new Uint8Array([1]), 'application/octet-stream')],
                    [LanguageModelChatMessage, new LanguageModelChatMessage(1, [], undefined)]
                ];
                for (var i = 0; i < cases.length; i += 1) {
                    var ctor = cases[i][0];
                    var instance = cases[i][1];
                    if (!(instance instanceof ctor)) { return false; }
                    if (!Object.isFrozen(ctor)) { return false; }
                    if (!Object.isFrozen(ctor.prototype)) { return false; }
                }
                return true;
            })()
            """
        ))
        #expect(result.toBool() == true)
    }

    // MARK: - name defaults to undefined (mutation 10)

    /// Mutation 10: `name` defaults to something other than `undefined`
    /// when omitted. Checked with `typeof`, since a `JSValue` comparison
    /// against Swift's own notion of "undefined" is exactly the kind of
    /// bridge detail this test should not depend on.
    @Test
    func nameDefaultsToUndefinedWhenOmitted() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            "typeof LanguageModelChatMessage.User('hi').name === 'undefined'"
        ))
        #expect(result.toBool() == true)
    }

    // MARK: - Probe-passed branch: typed-array bytes (task 5.7a-i report, Step 0)

    /// Not one of the brief's ten numbered mutations — it covers the Step 0
    /// probe's own encoding claim instead.
    ///
    /// The Step 0 probe (task-5.7a-i-report.md) measured a working typed-array
    /// round trip through this `JSContext`, so `LanguageModelDataPart.text`'s
    /// bytes must be a real UTF-8 encoding, not a one-byte-per-character
    /// encoding that happens to agree with UTF-8 on ASCII. `'€'` (U+20AC) is
    /// the fixture because its UTF-8 encoding (`0xE2 0x82 0xAC`, three bytes)
    /// differs from every naive one-byte or UTF-16-code-unit encoding
    /// (`0x20AC` truncated to `0xAC`, one byte) — so this is not an
    /// assertion a non-UTF-8 encoder could pass by coincidence.
    @Test
    func textDataBytesAreUtf8Encoded() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            """
            (function () {
                var part = LanguageModelDataPart.text('\\u20AC');
                var bytes = part.data;
                return bytes.length === 3 &&
                    bytes[0] === 0xE2 && bytes[1] === 0x82 && bytes[2] === 0xAC;
            })()
            """
        ))
        #expect(result.toBool() == true)
    }

    /// Not one of the brief's ten numbered mutations — the Step 0 probe's
    /// round-trip claim again, from the constructor's side.
    ///
    /// The Step 0 probe also measured that a `Uint8Array` handed to Swift and
    /// back survives unchanged, so a `Uint8Array` passed straight into
    /// `LanguageModelDataPart`'s constructor must come back unchanged from
    /// `.data` — both same length and same bytes, and by reference
    /// (`===`), since the constructor only assigns (`this.data = data`) and
    /// never copies.
    @Test
    func uint8ArrayRoundTripsUnchangedThroughConstructorToData() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            """
            (function () {
                var original = new Uint8Array([9, 8, 7, 6]);
                var part = new LanguageModelDataPart(original, 'application/octet-stream');
                return part.data === original &&
                    part.data.length === 4 &&
                    part.data[0] === 9 && part.data[3] === 6;
            })()
            """
        ))
        #expect(result.toBool() == true)
    }

    // MARK: - Instances are not frozen (finding 1; not one of the ten numbered mutations)

    /// Not one of the brief's ten numbered mutations, but the other half of
    /// finding 1's instruction ("do not freeze instances"): `role` and
    /// `name` are plain, assignable data properties on a constructed
    /// message, not read-only. If a future change froze instances to
    /// "match" the class/prototype freeze convention, this is the test that
    /// would catch it.
    @Test
    func chatMessageRoleAndNameRemainAssignableAfterConstruction() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            """
            (function () {
                var message = LanguageModelChatMessage.User('hello');
                message.role = 2;
                message.name = 'changed';
                return message.role === 2 && message.name === 'changed';
            })()
            """
        ))
        #expect(result.toBool() == true)
    }

    // MARK: - Property reads on the four previously-unread constructors (finding 2, not one of the ten mutations)

    /// `LanguageModelToolCallPart`'s three constructor arguments land on the
    /// correspondingly named properties, not swapped or dropped. `callId` and
    /// `name` are given distinct string values so a mutant that assigns
    /// `this.callId = name; this.name = callId;` fails this test even though
    /// `instanceof` and freeze alone (mutation 9) cannot see it — a tool call
    /// with `callId`/`name` swapped would send a model the wrong identifier
    /// and correlate its result to nothing.
    @Test
    func toolCallPartStoresItsThreeArgumentsUnderTheirOwnNames() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            """
            (function () {
                var part = new LanguageModelToolCallPart('call-1', 'the-tool', { a: 1 });
                return part.callId === 'call-1' && part.name === 'the-tool' && part.input.a === 1;
            })()
            """
        ))
        #expect(result.toBool() == true)
    }

    /// `LanguageModelToolResultPart.content` and `LanguageModelToolResult.content`
    /// each store the array they are given, not an empty one — a stub of
    /// `this.content = [];` in either constructor passes every other
    /// assertion in this suite (`instanceof` and freeze only, mutation 9) but
    /// fails here.
    @Test
    func toolResultPartAndToolResultStoreTheGivenContent() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            """
            (function () {
                var textPart = new LanguageModelTextPart('hi');
                var resultPart = new LanguageModelToolResultPart('call-1', [textPart]);
                var toolResult = new LanguageModelToolResult([textPart]);
                return resultPart.content.length === 1 && resultPart.content[0] === textPart &&
                    toolResult.content.length === 1 && toolResult.content[0] === textPart;
            })()
            """
        ))
        #expect(result.toBool() == true)
    }

    /// `LanguageModelPromptTsxPart.value` stores the given value — a stub of
    /// `this.value = undefined;` passes `instanceof` and freeze (mutation 9)
    /// but fails here.
    @Test
    func promptTsxPartStoresTheGivenValue() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            "new LanguageModelPromptTsxPart('some-tsx').value === 'some-tsx'"
        ))
        #expect(result.toBool() == true)
    }

    /// `LanguageModelChatMessage.User`/`.Assistant`'s `name` argument reaches
    /// the constructed message. `nameDefaultsToUndefinedWhenOmitted` only
    /// proves the default when the argument is omitted, and
    /// `chatMessageRoleAndNameRemainAssignableAfterConstruction` only proves
    /// `name` is assignable after construction — neither passes a name in
    /// through the factory, so a stub of `this.name = undefined;` in the
    /// constructor (ignoring the argument) passes both.
    @Test
    func userAndAssistantPassTheNameArgumentThrough() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            """
            (function () {
                return LanguageModelChatMessage.User('hi', 'bob').name === 'bob' &&
                    LanguageModelChatMessage.Assistant('hi', 'alice').name === 'alice';
            })()
            """
        ))
        #expect(result.toBool() == true)
    }

    // MARK: - Unpaired surrogates encode as U+FFFD (finding 5; not one of the ten numbered mutations)

    /// R2 (task 5.7a-i fix round 1): an unpaired surrogate — high or low —
    /// encodes as U+FFFD (`EF BF BD`), matching upstream's `TextEncoder`
    /// (`VSBuffer.fromString`), rather than the raw three-byte surrogate
    /// sequence (`ED A0 80`), which is not valid UTF-8. `'\uD800'` is a lone
    /// high surrogate with nothing following it to pair with.
    @Test
    func unpairedSurrogateEncodesAsTheReplacementCharacter() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            """
            (function () {
                var part = LanguageModelDataPart.text('\\uD800');
                var bytes = part.data;
                return bytes.length === 3 &&
                    bytes[0] === 0xEF && bytes[1] === 0xBF && bytes[2] === 0xBD;
            })()
            """
        ))
        #expect(result.toBool() == true)
    }

    // MARK: - LanguageModelDataPart.image (finding 9; not one of the ten numbered mutations)

    /// `LanguageModelDataPart.image`'s `data` and explicit `mime` arguments
    /// both reach the constructed part. This replaces the declaration this
    /// suite's doc previously carried ("correctness follows from `constructor`
    /// + `.data` alone since `.image` is a one-line pass-through") — that
    /// reasoning was unsound: a stub of
    /// `return new LanguageModelDataPart(data, 'image/png');` passes every
    /// other test in this suite because nothing else calls `.image`.
    @Test
    func imageStoresTheGivenDataAndMimeType() throws {
        let context = try makeContext()
        let result = try #require(context.evaluateScript(
            """
            (function () {
                var bytes = new Uint8Array([1]);
                var part = LanguageModelDataPart.image(bytes, 'image/jpeg');
                return part.data === bytes && part.mimeType === 'image/jpeg';
            })()
            """
        ))
        #expect(result.toBool() == true)
    }
}
