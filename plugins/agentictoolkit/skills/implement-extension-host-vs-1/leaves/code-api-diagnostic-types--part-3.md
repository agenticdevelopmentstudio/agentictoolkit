<!-- leaf: implement-extension-host-vs-1/code-api-diagnostic-types--part-3 · source: extension-host-vs-code-api-diagnostic-types.md -->

# DiagnosticTypes — continued (part 3)

**Rules** (cite as `implement-extension-host-vs-1/code-api-diagnostic-types--part-3#<slug>`):

- `related-information-value-constructs-through-real-constructor` MUST
- `swift-mirrors-are-sendable-value-types` MUST
- `no-instance-caching-of-decoded-values` MUST

- **related-information-value-constructs-through-real-constructor**: `diagnosticRelatedInformationValue(for:in:)` MUST build the result by calling the installed `DiagnosticRelatedInformation` class's constructor with `(location, message)`, so the result is genuinely `instanceof` `vscode.DiagnosticRelatedInformation`.
- **swift-mirrors-are-sendable-value-types**: `ExtensionDiagnosticSeverity`, `ExtensionDiagnosticTag`, `ExtensionDiagnosticCodeValue`, `ExtensionDiagnosticCode`, `ExtensionDiagnosticRelatedInformation`, and `ExtensionDiagnostic` MUST each be declared `Sendable` and `Equatable`, so a decoded value MAY be passed across actor boundaries once it has left the `JSContext`.
- **no-instance-caching-of-decoded-values**: `diagnostic(from:in:)` and `diagnosticRelatedInformation(from:in:)` MUST decode fresh from the given `JSValue` on every call; neither function MUST cache or reuse a prior decode for the same underlying JS object.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `context` | `JSContext` | none (required) | Every function in this file takes the target context explicitly; there is no ambient or singleton context. |
| `value` (readers) | `JSValue` | none (required) | The JS value to decode; `diagnostic(from:in:)`, `diagnosticRelatedInformation(from:in:)`, `diagnosticCode(from:in:)`, `diagnosticRelatedInformationArray(from:in:)`, and `diagnosticTagArray(from:in:)` all take one. |
| `diagnostic` / `relatedInformation` (writers) | `ExtensionDiagnostic` / `ExtensionDiagnosticRelatedInformation` | none (required) | The Swift value `diagnosticValue(for:in:)` / `diagnosticRelatedInformationValue(for:in:)` encodes back into a real JS instance. |
| `VSCodeAPI.maximumDecodableArrayLength` | `Int` | `100_000` | Declared in `VSCodeAPI.swift`; the ceiling `VSCodeAPI.arrayLength(of:)` enforces for any array this file walks (`relatedInformation`, `tags`). Not settable per call. |
| `severity` (constructor's 3rd argument) | JS number or `undefined` | `DiagnosticSeverity.Error` (`0`) when omitted | Read by `Diagnostic`'s constructor; an explicit `0` is preserved and distinguished from "omitted" via `typeof`. |
| `ExtensionDiagnostic.severity` (Swift initializer) | `ExtensionDiagnosticSeverity` | `.error` | `ExtensionDiagnostic.init`'s own default parameter value, mirroring the JS constructor's default. |

## Localization

- **hardcoded-error-messages**: The three `TypeError` messages this file's constructors throw — `"location must be a vscode.Location"`, `"range must be a vscode.Range"`, and `"message must be set"` — are hardcoded English string literals with no localization key or `String(localized:)` call. They are visible to the extension author, not to the app's own end-user UI, per the file's own doc comment framing these as validation surfaced to "the extension" that made the mistake.
- **hardcoded-log-strings**: The three `logger.error` messages in `installDiagnosticTypes(in:)` (evaluate failure, JS-side `installedError`, missing container member) are hardcoded English `Logger` interpolated strings, also unlocalized.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `location must be a vscode.Location` | `DiagnosticRelatedInformation`'s constructor, thrown when `location` fails the `instanceof` check. |
| (none — literal only) | `range must be a vscode.Range` | `Diagnostic`'s constructor, thrown when `range` fails the `instanceof` check. |
| (none — literal only) | `message must be set` | `Diagnostic`'s constructor, thrown when `message` is falsy. |
| (none — literal only) | `Could not install the 'vscode.DiagnosticSeverity'/'vscode.DiagnosticTag'/'vscode.DiagnosticRelatedInformation'/'vscode.Diagnostic' classes in context '<name>'; they stay the shim's not-implemented stub` | `installDiagnosticTypes(in:)`, logged on an evaluate failure. |
| (none — literal only) | `Could not install the 'vscode.DiagnosticSeverity'/'vscode.DiagnosticTag'/'vscode.DiagnosticRelatedInformation'/'vscode.Diagnostic' classes in context '<name>': '<error>'; they stay the shim's not-implemented stub` | `installDiagnosticTypes(in:)`, logged on a JS-side `installedError`. |
| (none — literal only) | `The 'vscode' diagnostic-types container in context '<name>' is missing one of 'DiagnosticSeverity', 'DiagnosticTag', 'DiagnosticRelatedInformation' or 'Diagnostic'; all four stay the shim's not-implemented stub` | `installDiagnosticTypes(in:)`, logged when the container is missing an expected member. |

## Privacy

- **Data collected**: `DiagnosticTypes.swift` collects no data of its own; it decodes and re-encodes whatever `range`, `message`, `severity`, `source`, `code`, `relatedInformation`, and `tags` values an extension or the host already holds, without retaining a copy beyond the return value of each call.
- **Storage**: this file performs no storage of its own; a decoded `ExtensionDiagnostic` is only as persistent as whatever the caller (outside this file's given sources) does with the returned value.
- **Transmission**: this file makes no network call; it neither sends nor receives anything over a network.
- **Retention**: nothing in this file is retained beyond the lifetime of one function call's local variables, except the per-context installed-class cache (`__vscodeDiagnosticTypesClasses`), which holds only class/prototype objects, never a diagnostic's data.

## Platform Notes

- **SwiftUI**: not applicable to this file — `DiagnosticTypes.swift` imports only `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing here renders or observes view state.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/DiagnosticTypes.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is an extension of `VSCodeAPI`, itself `@MainActor`, and its consumers among the given sources are the JS-side `vscode.languages` diagnostics collection machinery and `MainThreadDiagnostics` (not among the given sources), which reads decoded `ExtensionDiagnostic` values back through `diagnostic(from:in:)`.
- **Compose**: model the four installed declarations as Kotlin: `DiagnosticSeverity`/`DiagnosticTag` as enum classes with an explicit numeric `value` property (Kotlin enums do not compile to a bidirectional-mapping object the way `tsc` does, so a small companion-object lookup table is needed to reproduce **severity-reverse-mapping**/**tag-reverse-mapping**), and `DiagnosticRelatedInformation`/`Diagnostic` as `data class`es whose "constructor" is a factory function performing the same `range`/`location`/`message` validation and throwing an `IllegalArgumentException` in place of a JS `TypeError`. The "never assign `undefined`" contract (**diagnostic-constructor-leaves-optionals-unassigned**) has no direct Kotlin analogue on a `data class`; model it with nullable properties defaulted to `null` and treat "absent" and "explicitly null" as the same case throughout, mirroring **diagnostic-decode-optional-field-absence**.
- **React/Web**: this is closest to the actual runtime shape — extension code in the real VS Code product already runs against the genuine `vscode.d.ts` declarations these mirror. A React/Web host embedding a similar extension bridge would decode/encode the same four shapes across whatever serialization boundary (e.g. `postMessage` to a worker) replaces this file's `JSContext` boundary, and would need the same "refuse the whole value on any malformed optional field" discipline (**diagnostic-decode-optional-field-malformed-refuses-whole-value**) when deserializing untrusted extension-authored data.
- **WinUI 3**: model `DiagnosticSeverity`/`DiagnosticTag` as `public enum DiagnosticSeverity { Error = 0, Warning = 1, Information = 2, Hint = 3 }` (a real C# enum already gives the forward mapping; `Enum.GetName(typeof(DiagnosticSeverity), value)` reproduces the reverse mapping on demand rather than needing a hand-built table). Model `DiagnosticRelatedInformation` and `Diagnostic` as `sealed record`s or plain classes whose constructors validate `location`/`range` with `is Location`/`is Range` pattern-matching (WinUI 3's `Location`/`Range` equivalents) and throw `ArgumentException` in place of a JS `TypeError`, matching **diagnostic-constructor-validates-location** and **diagnostic-constructor-validates-range**. `ExtensionDiagnosticCode`'s three-shape union (`code?: string | number | { value: string | number; target: Uri }`) has no built-in C# union type; model it as a small discriminated `abstract record CodeValue` with `Scalar`/`Link` subtypes, the direct analogue of the Swift `enum ExtensionDiagnosticCode { case scalar(...); case link(...) }` this file declares. `System.Text.Json.JsonSerializer` with a custom converter is the .NET equivalent of this file's manual `diagnosticCode(from:in:)`/`diagnosticCodeJSValue(for:in:)` pair, since the WinUI host would decode extension-authored diagnostics from a JSON-shaped bridge rather than a `JSValue`. The "assign only when present, never `null`/`undefined`" contract (**diagnostic-value-optional-fields-set-only-when-present**) maps to `JsonIgnoreCondition.WhenWritingNull` combined with nullable reference types, so an absent field is omitted from serialized output rather than written as `null`.

