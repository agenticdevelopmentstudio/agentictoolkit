import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The bridge every `MainThread*` adaptor builds its answers with.
///
/// Small enough to look obviously right, which is most of why it had no tests:
/// each member is one line. But it is the *shared* one line now — the four
/// adaptors that used to carry private copies all answer through here — so a
/// change to any of these is a change to what every extension sees, and two of
/// the rules are not visible in the one line at all. `undefined` is not
/// `null`, and `stringOptionalField` reads rather than coerces.
@MainActor
struct JSValueBridgeTests {

    private func makeContext() throws -> JSContext {
        try #require(JSContext())
    }

    /// Evaluates `expression` and hands back the value, for building the
    /// operands these members read.
    private func value(_ expression: String, in context: JSContext) throws -> JSValue {
        try #require(context.evaluateScript(expression))
    }

    // MARK: - undefined is not null

    /// The distinction the two spellings exist for. An extension that writes
    /// `if (result === undefined)` — which is what a TypeScript `T | undefined`
    /// compiles people into writing — sees nothing at all if this answers
    /// `null`, and VS Code's own API returns `undefined` from every one of
    /// these members.
    @Test("undefined is a real JavaScript undefined, not null")
    func undefinedIsUndefined() throws {
        let context = try makeContext()

        let built = try #require(JSValueBridge.undefined(in: context))

        #expect(built.isUndefined)
        #expect(!built.isNull)
    }

    /// The promise-settlement spelling has to produce the same JavaScript
    /// value as the synchronous one; the `NSNull()` in its signature is the
    /// fallback for a bridge that failed, not the ordinary answer.
    @Test("the settlement spelling of undefined is also undefined")
    func undefinedOrNullIsUndefinedInPractice() throws {
        let context = try makeContext()

        let built = JSValueBridge.undefinedOrNull(in: context)

        let asValue = try #require(built as? JSValue)
        #expect(asValue.isUndefined)
        #expect(!asValue.isNull)
    }

    // MARK: - Arrays

    @Test("an array of values bridges to a JavaScript array")
    func arrayBridgesToAJavaScriptArray() throws {
        let context = try makeContext()
        let items = [
            try value("'a'", in: context),
            try value("'b'", in: context)
        ]

        let built = try #require(JSValueBridge.array(of: items, in: context))

        context.setObject(built, forKeyedSubscript: "built" as NSString)
        #expect(try value("Array.isArray(built)", in: context).toBool())
        #expect(try value("built.length", in: context).toInt32() == 2)
        #expect(try value("built.join('')", in: context).toString() == "ab")
    }

    /// An empty result is an empty array, never `undefined`: every call site
    /// here answers a VS Code API that is typed as returning a list, and an
    /// extension doing `.map(...)` on the answer to "nothing matched" would
    /// throw rather than render nothing.
    @Test("no values is an empty array, not a missing one")
    func anEmptyArrayIsStillAnArray() throws {
        let context = try makeContext()

        let built = try #require(JSValueBridge.array(of: [], in: context))

        context.setObject(built, forKeyedSubscript: "built" as NSString)
        #expect(try value("Array.isArray(built)", in: context).toBool())
        #expect(try value("built.length", in: context).toInt32() == 0)
    }

    /// The freshness the doc comment claims. Two calls have to be two arrays,
    /// because an extension that keeps the answer to one call and pushes onto
    /// it must not be editing what the next call returns.
    @Test("each call bridges a new array")
    func eachCallBridgesItsOwnArray() throws {
        let context = try makeContext()
        let items = [try value("'a'", in: context)]

        let first = try #require(JSValueBridge.array(of: items, in: context))
        let second = try #require(JSValueBridge.array(of: items, in: context))

        context.setObject(first, forKeyedSubscript: "first" as NSString)
        context.setObject(second, forKeyedSubscript: "second" as NSString)
        _ = try value("first.push('mutated')", in: context)
        #expect(try value("first.length", in: context).toInt32() == 2)
        #expect(try value("second.length", in: context).toInt32() == 1)
        #expect(try value("first === second", in: context).toBool() == false)
    }

    // MARK: - Strings

    /// The empty string is an answer, not an absence. `showInputBox` resolving
    /// with `""` means the user pressed Return on an empty field, which is
    /// different from dismissing the box — and a builder that treated it as
    /// nothing would make those two indistinguishable.
    @Test("the empty string bridges as a string, not as null")
    func theEmptyStringIsAValue() throws {
        let context = try makeContext()

        let built = JSValueBridge.stringOrNull("", in: context)

        let asValue = try #require(built as? JSValue)
        #expect(asValue.isString)
        #expect(asValue.toString() == "")
    }

    @Test("a string bridges with its contents intact")
    func aStringKeepsItsContents() throws {
        let context = try makeContext()

        let built = JSValueBridge.stringOrNull("a'b\"c\\d\u{1F600}", in: context)

        let asValue = try #require(built as? JSValue)
        #expect(asValue.toString() == "a'b\"c\\d\u{1F600}")
    }

    // MARK: - Rejections

    /// An `Error`, not a string. An extension's `catch (e)` reads
    /// `e.message`, and `catch` blocks in the wild routinely do
    /// `e.message.includes(...)` — which throws on a rejection that handed
    /// over a bare string, turning a refusal this host explained into an
    /// unhandled exception that mentions neither.
    @Test("a rejection carries a real Error with the message on it")
    func aRejectionCarriesAnError() throws {
        let context = try makeContext()
        _ = try value("var caught = null; function reject(e) { caught = e; }", in: context)
        let reject = try #require(context.objectForKeyedSubscript("reject"))

        JSValueBridge.rejectWithError(reject, message: "the host said no")

        #expect(try value("caught instanceof Error", in: context).toBool())
        #expect(try value("caught.name", in: context).toString() == "Error")
        #expect(try value("caught.message", in: context).toString() == "the host said no")
    }

    /// And what it does *not* carry, pinned because the opposite was written
    /// down. `JSValue(newErrorFromMessage:in:)` constructs the object rather
    /// than throwing from JavaScript, so there is no frame to record and
    /// `stack` is `undefined` — an extension author who logs `e.stack` gets
    /// the string "undefined" and no clue where the refusal came from.
    ///
    /// Asserted rather than left implicit for two reasons. It is the only
    /// thing that makes `rejectTornDown`'s wording load-bearing: the message
    /// is the *whole* diagnostic, so a tidier who shortened it to "unavailable"
    /// would be removing the only context there is. And if a future WebKit
    /// starts attaching a stack here, this test failing is how anyone finds
    /// out — at which point the message can afford to be shorter.
    @Test("a rejection carries no stack, which is why the message must be whole")
    func aRejectionHasNoStack() throws {
        let context = try makeContext()
        _ = try value("var caught = null; function reject(e) { caught = e; }", in: context)
        let reject = try #require(context.objectForKeyedSubscript("reject"))

        JSValueBridge.rejectWithError(reject, message: "the host said no")

        #expect(try value("typeof caught.stack", in: context).toString() == "undefined")
    }

    /// The one wording an extension author will see from four different
    /// adaptors, so it names what happened and which member it happened to.
    @Test("a torn-down rejection names the member and the reason")
    func aTornDownRejectionNamesThePath() throws {
        let context = try makeContext()
        _ = try value("var caught = null; function reject(e) { caught = e; }", in: context)
        let reject = try #require(context.objectForKeyedSubscript("reject"))

        JSValueBridge.rejectTornDown(reject, path: "vscode.window.showInputBox")

        let message = try value("caught.message", in: context).toString() ?? ""
        #expect(message.contains("vscode.window.showInputBox"))
        #expect(message.contains("torn down"))
    }

    // MARK: - Reading a field without coercing it

    @Test("a string field is read")
    func aStringFieldIsRead() throws {
        let context = try makeContext()

        let read = JSValueBridge.stringOptionalField(try value("'hello'", in: context))

        #expect(read == "hello")
    }

    /// The empty string again, from the reading side: a field explicitly set
    /// to `""` is a constraint the extension expressed, not an absent one.
    @Test("an empty string field is read as an empty string")
    func anEmptyStringFieldIsRead() throws {
        let context = try makeContext()

        let read = JSValueBridge.stringOptionalField(try value("''", in: context))

        #expect(read == "")
    }

    /// The whole reason this member exists rather than a bare `toString()`.
    /// Every one of these coerces happily — `42`, `true` and `{}` become
    /// `"42"`, `"true"` and `"[object Object]"` — and each of those is a
    /// nonsense value silently accepted as a `placeHolder` or a `language`
    /// filter, which then matches nothing and reports no reason
    /// *(fail-fast)*.
    @Test("a non-string field is not coerced into one")
    func nonStringsAreNotCoerced() throws {
        let context = try makeContext()

        for expression in ["42", "true", "({})", "[]", "(function () {})", "null", "undefined"] {
            let read = JSValueBridge.stringOptionalField(try value(expression, in: context))
            #expect(read == nil, "\(expression) was coerced to \(read ?? "nil")")
        }
    }

    /// The property was never set. `objectForKeyedSubscript` on an absent key
    /// answers a `JSValue` holding `undefined` rather than `nil`, so this is
    /// the same case as the loop above by a different route — but it is the
    /// route every real call site takes.
    @Test("a field that was never set reads as no constraint")
    func anAbsentFieldIsNoConstraint() throws {
        let context = try makeContext()
        let options = try value("({ ignoreFocusOut: true })", in: context)

        let read = JSValueBridge.stringOptionalField(
            options.objectForKeyedSubscript("placeHolder"))

        #expect(read == nil)
    }

    /// And no operand at all, which is what a call site passes when the whole
    /// options object was omitted.
    @Test("no field at all reads as no constraint")
    func aMissingOperandIsNoConstraint() {
        #expect(JSValueBridge.stringOptionalField(nil) == nil)
    }
}
