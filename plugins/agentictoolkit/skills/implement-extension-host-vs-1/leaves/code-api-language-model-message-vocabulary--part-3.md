<!-- leaf: implement-extension-host-vs-1/code-api-language-model-message-vocabulary--part-3 · source: extension-host-vs-code-api-language-model-message-vocabulary.md -->

# LanguageModelMessageVocabulary — continued (part 3)

**Rules** (cite as `implement-extension-host-vs-1/code-api-language-model-message-vocabulary--part-3#<slug>`):

- `chat-message-name-defaults-undefined` MUST
- `chat-message-name-passthrough` MUST
- `content-part-type-not-runtime-checked` MUST
- `classes-frozen-after-construction` MUST
- `instances-not-frozen` MUST
- `no-tojson-method` MUST

- **chat-message-name-defaults-undefined**: When `LanguageModelChatMessage.User`/`.Assistant` is called without a `name` argument, the constructed message's `name` MUST be `undefined` (`typeof message.name === 'undefined'`), not any other default value.
- **chat-message-name-passthrough**: When `LanguageModelChatMessage.User`/`.Assistant` is called with a `name` argument, the constructed message's `name` MUST equal that argument.
- **content-part-type-not-runtime-checked**: `LanguageModelChatMessage`'s `content` setter MUST NOT validate that array elements match the role-specific part types `vscode.d.ts` documents (a `LanguageModelToolResultPart` inside a `User` message's content, or a `LanguageModelToolCallPart` inside an `Assistant` message's, are both accepted at runtime), matching that upstream enforces this distinction only at the TypeScript type-checking layer.
- **classes-frozen-after-construction**: `LanguageModelTextPart`, `LanguageModelPromptTsxPart`, `LanguageModelToolCallPart`, `LanguageModelToolResultPart`, `LanguageModelToolResult`, `LanguageModelDataPart`, and `LanguageModelChatMessage` MUST each be frozen via `Object.freeze`, and each of their seven `.prototype` objects MUST also be frozen, all inside the same evaluation that builds them, with no window in which any of the fourteen is unfrozen.
- **instances-not-frozen**: No instance of any of the seven constructor functions MUST be frozen; `role`, `name`, `content`, `value`, `callId`, `input`, `data`, and `mimeType` MUST all remain writable on a constructed instance after construction.
- **no-tojson-method**: None of the eight installed members MUST define a `toJSON` method; `vscode.d.ts` declares none, and this host has no reader for the extension-host RPC marshalling shape (`$mid`) upstream's own `toJSON` produces.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `context` | `JSContext` | none (required) | `installLanguageModelVocabulary(in:)` takes the target context explicitly; there is no ambient or singleton context. |
| `languageModelVocabularyGlobalName` | `String` (fixed constant) | `"__vscodeLanguageModelVocabulary"` | The global key `installLanguageModelVocabulary(in:)` caches the built container under; not settable per call. |
| `languageModelVocabularyMemberNames` | `[String]` (fixed constant) | the eight names in `vscode.d.ts`'s declared order | Used both to validate the resolved container's shape and, on a missing member, to name the first one missing in the log; not settable per call. |
| `mime` (`LanguageModelDataPart.json`'s 2nd argument) | JS string or `undefined` | `'text/x-json'` when omitted | Explicit values are used verbatim, per **data-part-explicit-mime-override**. |
| `mime` (`LanguageModelDataPart.text`'s 2nd argument) | JS string or `undefined` | `'text/plain'` when omitted | Explicit values are used verbatim, per **data-part-explicit-mime-override**. |
| `mime` (`LanguageModelDataPart.image`'s 2nd argument) | JS string or `undefined` | none — passed straight through, `undefined` if omitted | Unlike `.json`/`.text`, `.image` applies no default, per **data-part-image-factory**. |
| `name` (`LanguageModelChatMessage`'s 3rd constructor argument, and `.User`/`.Assistant`'s 2nd) | JS string or `undefined` | `undefined` when omitted | Per **chat-message-name-defaults-undefined**. |

## Localization

- **hardcoded-log-strings**: The two `logger.error` messages in `installLanguageModelVocabulary(in:)` (an evaluate failure, and a missing container member) are hardcoded English `Logger` interpolated strings with no localization key or `String(localized:)` call. Unlike `DiagnosticTypes.swift`'s equivalent installer, this file's inner catch never surfaces the underlying JavaScript error's own message, so there is no third, error-message-carrying log variant to localize.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `Could not install the 'vscode' language-model message vocabulary in context '<name>'; every member stays the shim's not-implemented stub` | `installLanguageModelVocabulary(in:)`, logged when `context.evaluateScript(languageModelVocabularySource)` returns `nil` or a non-object. |
| (none — literal only) | `The 'vscode' language-model message vocabulary in context '<name>' is missing '<memberName>'; every member stays the shim's not-implemented stub` | `installLanguageModelVocabulary(in:)`, logged when the container is missing an expected member. |

## Privacy

- **Data collected**: `LanguageModelMessageVocabulary.swift` collects no data of its own; it constructs value objects out of whatever `role`, `content`, `name`, `callId`, `input`, `data`, and `mimeType` values an extension already supplies, without retaining a copy beyond the returned instance and the per-context class cache.
- **Storage**: this file performs no persistent storage of its own; a constructed `LanguageModelChatMessage`/`LanguageModelDataPart`/etc. is only as persistent as whatever the caller (outside this file's given sources) does with it.
- **Transmission**: this file makes no network call; it neither sends nor receives anything over a network. The message and part values it constructs may later be transmitted to a language model by code outside this file's scope (5.7a-ii/5.7b), which this recipe does not cover.
- **Retention**: nothing in this file is retained beyond the lifetime of one function call's local variables, except the per-context installed-class cache (`__vscodeLanguageModelVocabulary`), which holds only the eight constructor/enum objects, never a message's or part's data.

## Platform Notes

- **SwiftUI**: not applicable to this file — `LanguageModelMessageVocabulary.swift` imports only `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing here renders or observes view state.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/LanguageModelMessageVocabulary.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is an extension of the `@MainActor` `VSCodeAPI` enum; its confirmed consumers among the repository's other files are `ExtensionHost.installRuntime`, which installs the eight members eagerly on every activation via the shared, sorted `installVSCodeMembers(_:onto:)` loop, and `MainThreadLanguageModels.swift`'s `vscode.lm` adaptor, which calls `installLanguageModelVocabulary(in:)` again per streamed request to read the cached container back — both outside this recipe's scope.
- **Compose**: model the eight members as Kotlin: `LanguageModelChatMessageRole` as an enum class with an explicit numeric `value` property (Kotlin enums do not compile to the bidirectional-mapping object shape a JS numeric enum can; this type has no reverse mapping to reproduce, only the two forward values). Model the seven constructor functions as `data class`es whose constructors perform no validation, matching **tool-call-part-stores-fields** / **tool-result-part-stores-fields** / etc. Model `LanguageModelChatMessage.content` as a Kotlin property with a custom setter performing the same `is String` coercion into a single-element `LanguageModelTextPart` list, matching **chat-message-content-setter-string-coercion**; a `data class`'s freeze-after-construction is not directly reproducible on the class itself (Kotlin has no `Object.freeze` analogue for a class), so the "frozen class" contract (**classes-frozen-after-construction**) has no direct Kotlin equivalent beyond documenting it as an implementation note.
- **React/Web**: this is closest to the actual runtime shape — extension code in the real VS Code product already runs against the genuine `vscode.d.ts` declarations this file mirrors. A React/Web host embedding a similar extension bridge would construct the same eight shapes directly as plain ES classes (no `JSContext` boundary to cross), and would reproduce the "single evaluation, shared lexical scope" requirement (**single-evaluation-builds-all-eight**) simply by defining all eight in one module.
- **WinUI 3**: model `LanguageModelChatMessageRole` as `public enum LanguageModelChatMessageRole { User = 1, Assistant = 2 }` — a real C# enum gives the forward mapping directly, matching **role-enum-shape**. Model the seven constructor-function equivalents as plain mutable classes (not `init`-only `record`s, which would make properties immutable after construction and violate **instances-not-frozen**) with public settable properties and no constructor-time validation. Model `LanguageModelChatMessage.Content`'s coercing setter as an ordinary C# property setter that checks `is string` and wraps it in a single-element `List<LanguageModelTextPart>`, the direct analogue of **chat-message-content-setter-string-coercion**; `Role` and `Name` stay plain auto-properties, matching **chat-message-role-name-not-accessors**. Model `LanguageModelDataPart.Json`/`.Text` as static factory methods using `System.Text.Json.JsonSerializer.Serialize` for the payload and `System.Text.Encoding.UTF8.GetBytes` for the bytes — note that `JsonSerializerOptions.WriteIndented` defaults to two-space indentation, not tabs, so matching **data-part-json-factory-serialization** byte-for-byte requires a custom `JsonWriterOptions` with a tab `IndentCharacter`; `Encoding.UTF8.GetBytes` already replaces an unpaired surrogate with U+FFFD by default, reproducing **utf8-encoder-unpaired-surrogate** with no extra code. There is no `Object.freeze` equivalent in .NET; a WinUI 3 port has no way to reproduce **classes-frozen-after-construction**'s "the class itself is frozen" contract and would need to document that gap explicitly rather than silently drop it.

