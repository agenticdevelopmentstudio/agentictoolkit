//
//  LanguageModelMessageVocabulary.swift
//  AgenticToolkit
//

import Foundation
import JavaScriptCore
import OSLog
import AgenticToolkitCore

/// The value types an extension *constructs* when it talks to a language
/// model — task 5.7a-i. `vscode.LanguageModelChatMessageRole`,
/// `vscode.LanguageModelChatMessage`, `vscode.LanguageModelToolCallPart`,
/// `vscode.LanguageModelToolResultPart`, `vscode.LanguageModelTextPart`,
/// `vscode.LanguageModelPromptTsxPart`, `vscode.LanguageModelToolResult` and
/// `vscode.LanguageModelDataPart`. Nothing that *calls* a model —
/// `selectChatModels`, `LanguageModelChat`, `countTokens`, `sendRequest` —
/// is in scope here; those are 5.7a-ii and 5.7b, and they are built on top
/// of the eight members this file installs.
///
/// Same shape as `Uri.swift`, for the reason given there: an extension
/// constructs these, compares them with `instanceof`, and holds them in
/// collections, so each needs a real constructor function with a real
/// prototype — a `@convention(block)` closure cannot be `new`'d. All eight
/// are built in **one** evaluated source, in one closure, under one cached
/// global — not eight separate evaluations — because
/// `LanguageModelChatMessage`'s `content` setter constructs a
/// `LanguageModelTextPart`, and `LanguageModelDataPart.json`/`.text`
/// construct a `LanguageModelDataPart`; they need to see each other as
/// ordinary lexical bindings, not re-find one another off `globalThis`.
///
/// Line numbers below are against `vscode.d.ts`, `extHostTypes.ts` and
/// `mime.ts` at the pinned VS Code commit
/// `3addbda66f9e80c3ed1b943822ab823bb6747b02` (fetched directly from that
/// commit's raw GitHub content, so the text is fixed by the commit hash
/// itself rather than a separately-verified manifest).
extension VSCodeAPI {

    // MARK: - Installing the vocabulary

    /// The global `installLanguageModelVocabulary(in:)` caches the eight
    /// members under, once per context — `Uri.swift`'s
    /// `uriClassGlobalName`, generalised to a container object.
    private static nonisolated let languageModelVocabularyGlobalName = "__vscodeLanguageModelVocabulary"

    /// The eight members, in the order `vscode.d.ts` declares them
    /// (20130-20140, 20145-20187, 20916-20940, 20946-20964, 20969-20980,
    /// 20986-20997, 21002-21015, 21021-21065). `installLanguageModelVocabulary(in:)`
    /// returns them in this same order.
    private static nonisolated let languageModelVocabularyMemberNames: [String] = [
        "LanguageModelChatMessageRole",
        "LanguageModelChatMessage",
        "LanguageModelToolCallPart",
        "LanguageModelToolResultPart",
        "LanguageModelTextPart",
        "LanguageModelPromptTsxPart",
        "LanguageModelToolResult",
        "LanguageModelDataPart"
    ]

    /// The vocabulary's own source, evaluated at most once per `JSContext`.
    ///
    /// Written in the same ES5 idiom as `Uri.swift` and `extension-runtime.js`
    /// — `var`, `function`, explicit prototypes, no `class`/`let`/arrow
    /// functions.
    ///
    /// **What `vscode.d.ts` does not say, and this source encodes anyway —
    /// all measured against `extHostTypes.ts` at the pinned commit:**
    ///
    /// 1. **`LanguageModelChatMessage.content` is an accessor pair, and the
    ///    setter coerces a string on every assignment, not only in the
    ///    constructor** (`extHostTypes.ts:3930-3951`). The constructor
    ///    reaches the setter by assigning through `this.content = content`
    ///    (`:3950`) rather than duplicating the coercion — so does this
    ///    source. `role` and `name` stay plain, assignable data properties
    ///    (`:3928`, `:3946`) — neither is an accessor, and nothing here
    ///    freezes an instance.
    /// 2. **`LanguageModelDataPart.json`'s default mime is `'text/x-json'`**,
    ///    not `application/json` — `extHostTypes.ts:4066`. The JSON is
    ///    tab-indented (`JSON.stringify(value, undefined, '\t')`, same
    ///    line), not compact.
    /// 3. **`LanguageModelDataPart.text`'s default mime is `'text/plain'`**
    ///    (`extHostTypes.ts:4071`, `Mimes.text` measured at `mime.ts:9`).
    ///    The literal is spelled here rather than importing upstream's
    ///    constants table for one string. Both factories encode UTF-8
    ///    (`VSBuffer.fromString`, same two lines) — `utf8EncodeToUint8Array`
    ///    below is this source's own encoder, since this `JSContext` has no
    ///    `TextEncoder` global.
    /// 4. **Three members are PROPOSED API and out of scope**:
    ///    `LanguageModelChatMessageRole.System` (`extHostTypes.ts:3886-3890`,
    ///    absent from the stable `vscode.d.ts:20130-20140` enum — this
    ///    source's role object has exactly `User`/`Assistant`),
    ///    `LanguageModelToolResultPart.isError` (`:3892-3903`), and
    ///    `LanguageModelTextPart`/`LanguageModelDataPart`'s `audience`
    ///    (`:4035`, `:4056`). None of the three appear below.
    /// 5. **No `toJSON`.** Upstream's carries `$mid: MarshalledId.*` for VS
    ///    Code's own extension-host RPC marshalling, which this host has no
    ///    equivalent of and no reader for. `toJSON` is not in `vscode.d.ts`,
    ///    so it is not in scope either way.
    ///
    /// **The `LanguageModelDataPart.image`/`data` members ship because
    /// building and reading a `Uint8Array` is ordinary ECMAScript inside a
    /// `JSContext`** — `new Uint8Array(bytes)` below
    /// (`utf8EncodeToUint8Array`) builds one, and nothing in this file ever
    /// reads one back. The reads that prove the bytes are right are in
    /// evaluated JavaScript elsewhere — `bytes.length`, `bytes[i]` and
    /// `part.data`, inside `LanguageModelMessageVocabularyTests.swift`'s
    /// scripts — so they too happen entirely in JavaScript; no Swift-side
    /// typed-array call is involved on either side.
    ///
    /// The Step 0 probe (task 5.7a-i report) additionally measured a
    /// working byte round trip through the C-level `JSObjectRef`
    /// typed-array API, which nothing here uses yet — that measurement
    /// becomes load-bearing once a later task (5.7a-ii/5.7b) needs Swift
    /// itself to read `.data` to send bytes to a model.
    private static nonisolated let languageModelVocabularySource = """
    (function () {
        'use strict';
        try {
            // UTF-8 encoder for `LanguageModelDataPart.json`/`.text`
            // (`extHostTypes.ts:4066-4073` route both through
            // `VSBuffer.fromString`, which is a UTF-8 encode). Handles
            // surrogate pairs so a value outside the BMP encodes to four
            // bytes rather than two lone, invalid three-byte sequences. An
            // unpaired surrogate (a lone high unit with no low unit
            // following, or a low unit with no high unit before it) encodes
            // as U+FFFD, matching upstream's `TextEncoder` — not the raw
            // three-byte surrogate sequence, which is not valid UTF-8.
            function utf8EncodeToUint8Array(value) {
                var text = String(value);
                var bytes = [];
                var index;
                for (index = 0; index < text.length; index += 1) {
                    var codePoint = text.charCodeAt(index);
                    if (codePoint >= 0xD800 && codePoint <= 0xDBFF && index + 1 < text.length) {
                        var low = text.charCodeAt(index + 1);
                        if (low >= 0xDC00 && low <= 0xDFFF) {
                            codePoint = ((codePoint - 0xD800) << 10) + (low - 0xDC00) + 0x10000;
                            index += 1;
                        }
                    }
                    if (codePoint < 0x80) {
                        bytes.push(codePoint);
                    } else if (codePoint < 0x800) {
                        bytes.push(0xC0 | (codePoint >> 6));
                        bytes.push(0x80 | (codePoint & 0x3F));
                    } else if (codePoint < 0x10000) {
                        if (codePoint >= 0xD800 && codePoint <= 0xDFFF) {
                            // Unpaired surrogate reaching here: either a high
                            // unit the pairing check above could not join to
                            // a following low unit, or a low unit encountered
                            // on its own.
                            bytes.push(0xEF, 0xBF, 0xBD);
                        } else {
                            bytes.push(0xE0 | (codePoint >> 12));
                            bytes.push(0x80 | ((codePoint >> 6) & 0x3F));
                            bytes.push(0x80 | (codePoint & 0x3F));
                        }
                    } else {
                        bytes.push(0xF0 | (codePoint >> 18));
                        bytes.push(0x80 | ((codePoint >> 12) & 0x3F));
                        bytes.push(0x80 | ((codePoint >> 6) & 0x3F));
                        bytes.push(0x80 | (codePoint & 0x3F));
                    }
                }
                return new Uint8Array(bytes);
            }

            // vscode.d.ts:20130-20140 — stable API has User/Assistant only.
            // extHostTypes.ts:3886-3890 additionally carries System = 3,
            // which is PROPOSED and out of scope (point 4 above).
            var LanguageModelChatMessageRole = { User: 1, Assistant: 2 };
            Object.freeze(LanguageModelChatMessageRole);

            // vscode.d.ts:20969-20980 / extHostTypes.ts:4033-4040 (minus the
            // PROPOSED `audience` field at :4035, and the self-assignment
            // bug at :4039, which is upstream's and is not reproduced).
            function LanguageModelTextPart(value) {
                this.value = value;
            }

            // vscode.d.ts:20986-20997 / extHostTypes.ts:4116-4121.
            function LanguageModelPromptTsxPart(value) {
                this.value = value;
            }

            // vscode.d.ts:20916-20940 / extHostTypes.ts:4014-4025.
            // `input` is typed `object` in the declaration and `any` in the
            // implementation; the declaration wins per the brief, and since
            // neither constrains JavaScript at runtime this stores whatever
            // it is given either way.
            function LanguageModelToolCallPart(callId, name, input) {
                this.callId = callId;
                this.name = name;
                this.input = input;
            }

            // vscode.d.ts:20946-20964 / extHostTypes.ts:3892-3903 (minus the
            // PROPOSED `isError` field at :3896/:3901).
            function LanguageModelToolResultPart(callId, content) {
                this.callId = callId;
                this.content = content;
            }

            // vscode.d.ts:21002-21015 / extHostTypes.ts:4201-4202.
            function LanguageModelToolResult(content) {
                this.content = content;
            }

            // vscode.d.ts:21021-21065 / extHostTypes.ts:4051-4073.
            function LanguageModelDataPart(data, mimeType) {
                this.data = data;
                this.mimeType = mimeType;
            }

            LanguageModelDataPart.image = function (data, mime) {
                return new LanguageModelDataPart(data, mime);
            };

            // Default mime measured at extHostTypes.ts:4066 —
            // 'text/x-json', not 'application/json' (the `vscode.d.ts` doc
            // comment's prose is wrong about this; the implementation is
            // what runs). Tab-indented, same line.
            LanguageModelDataPart.json = function (value, mime) {
                var effectiveMime = mime === undefined ? 'text/x-json' : mime;
                var rawStr = JSON.stringify(value, undefined, '\\t');
                return new LanguageModelDataPart(utf8EncodeToUint8Array(rawStr), effectiveMime);
            };

            // Default mime is Mimes.text, measured at mime.ts:9 as
            // 'text/plain' (extHostTypes.ts:4071).
            LanguageModelDataPart.text = function (value, mime) {
                var effectiveMime = mime === undefined ? 'text/plain' : mime;
                return new LanguageModelDataPart(utf8EncodeToUint8Array(value), effectiveMime);
            };

            // vscode.d.ts:20145-20187 / extHostTypes.ts:3918-3953.
            function LanguageModelChatMessage(role, content, name) {
                this.role = role;
                // Through the setter below, not a duplicated coercion here —
                // extHostTypes.ts:3950 does the same, and it is what makes
                // the setter's own coercion reachable from a plain
                // `new LanguageModelChatMessage(...)` call too.
                this.content = content;
                this.name = name;
            }

            LanguageModelChatMessage.User = function (content, name) {
                return new LanguageModelChatMessage(LanguageModelChatMessageRole.User, content, name);
            };

            LanguageModelChatMessage.Assistant = function (content, name) {
                return new LanguageModelChatMessage(LanguageModelChatMessageRole.Assistant, content, name);
            };

            // The single highest-value behaviour in this task
            // (extHostTypes.ts:3930-3944): a string assigned to `.content`
            // AFTER construction is coerced exactly the same way the
            // constructor's own assignment is, because both go through this
            // one setter. `role` and `name` are deliberately left as plain
            // data properties assigned directly in the constructor above —
            // they are not accessors upstream either.
            Object.defineProperty(LanguageModelChatMessage.prototype, 'content', {
                get: function () {
                    return this._content;
                },
                set: function (value) {
                    if (typeof value === 'string') {
                        this._content = [new LanguageModelTextPart(value)];
                    } else {
                        this._content = value;
                    }
                },
                enumerable: true
            });

            // Frozen after every static and prototype member is attached,
            // inside the same evaluation that built them — `Uri.swift`'s
            // exact reasoning (`uriClassSource`'s doc comment) applies
            // verbatim to each of these. Instances are never frozen:
            // `content`, `role` and `name` stay assignable.
            Object.freeze(LanguageModelTextPart.prototype);
            Object.freeze(LanguageModelTextPart);
            Object.freeze(LanguageModelPromptTsxPart.prototype);
            Object.freeze(LanguageModelPromptTsxPart);
            Object.freeze(LanguageModelToolCallPart.prototype);
            Object.freeze(LanguageModelToolCallPart);
            Object.freeze(LanguageModelToolResultPart.prototype);
            Object.freeze(LanguageModelToolResultPart);
            Object.freeze(LanguageModelToolResult.prototype);
            Object.freeze(LanguageModelToolResult);
            Object.freeze(LanguageModelDataPart.prototype);
            Object.freeze(LanguageModelDataPart);
            Object.freeze(LanguageModelChatMessage.prototype);
            Object.freeze(LanguageModelChatMessage);

            var vocabulary = {
                LanguageModelChatMessageRole: LanguageModelChatMessageRole,
                LanguageModelChatMessage: LanguageModelChatMessage,
                LanguageModelToolCallPart: LanguageModelToolCallPart,
                LanguageModelToolResultPart: LanguageModelToolResultPart,
                LanguageModelTextPart: LanguageModelTextPart,
                LanguageModelPromptTsxPart: LanguageModelPromptTsxPart,
                LanguageModelToolResult: LanguageModelToolResult,
                LanguageModelDataPart: LanguageModelDataPart
            };

            try {
                Object.defineProperty(globalThis, '\(languageModelVocabularyGlobalName)', {
                    value: vocabulary,
                    writable: false,
                    enumerable: false,
                    configurable: false
                });
            } catch (ignored) {
                // Caching is an optimisation, exactly as in `uriClassSource`;
                // the vocabulary works without it, just re-evaluated per call.
            }
            return vocabulary;
        } catch (error) {
            return null;
        }
    })()
    """

    /// The eight `vscode.LanguageModel*` members for `context`, evaluating
    /// the source the first time and reading the cached container back
    /// afterwards — `installUriClass(in:)`'s exact pattern, generalised from
    /// one class to eight members read off one container object.
    ///
    /// Returns `nil` on failure, `installUriClass(in:)`'s own failure mode:
    /// a context that cannot host the vocabulary yet is not fatal to
    /// activation (see `ExtensionHost.installRuntime`), and every member
    /// simply stays the shim's not-implemented stub.
    ///
    /// The same residual `installUriClass(in:)` documents at length applies
    /// here unchanged: a context where `ExtensionHost.installRuntime`'s
    /// eager install did not run first can reach this function from a later,
    /// lazy caller and adopt whatever object already sits under
    /// `languageModelVocabularyGlobalName`, real or not, with no way to tell
    /// the difference.
    ///
    /// Returns a `[String: JSValue]`, not the array of `(String, JSValue)`
    /// tuples this once returned: `installTextGeometryClasses` and
    /// `installDiagnosticTypes` already returned a dictionary, and
    /// `ExtensionHost.installVSCodeMembers(_:onto:)` is one helper shared by
    /// all three install sites, so all three hand it the same shape. `languageModelVocabularyMemberNames`'s declared
    /// order no longer survives into the caller either way: the shared
    /// helper installs by sorted key (Ruling 56), where this function's own
    /// install loop previously did not.
    public static func installLanguageModelVocabulary(
        in context: JSContext
    ) -> [String: JSValue]? {
        let container: JSValue
        if let cached = context.objectForKeyedSubscript(languageModelVocabularyGlobalName), cached.isObject {
            container = cached
        } else {
            guard let created = context.evaluateScript(languageModelVocabularySource), created.isObject else {
                logger.error(
                    """
                    Could not install the 'vscode' language-model message vocabulary in context \
                    '\(name(of: context), privacy: .public)'; every member stays the shim's \
                    not-implemented stub
                    """)
                return nil
            }
            container = created
        }

        var members: [String: JSValue] = [:]
        members.reserveCapacity(languageModelVocabularyMemberNames.count)
        for memberName in languageModelVocabularyMemberNames {
            guard let member = container.forProperty(memberName), member.isObject else {
                logger.error(
                    """
                    The 'vscode' language-model message vocabulary in context \
                    '\(name(of: context), privacy: .public)' is missing '\(memberName, privacy: .public)'; \
                    every member stays the shim's not-implemented stub
                    """)
                return nil
            }
            members[memberName] = member
        }
        return members
    }
}
