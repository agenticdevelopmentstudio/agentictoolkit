<!-- leaf: implement-language/services-snippets--part-3 · source: language-services-snippets.md -->

# Language Services Snippets — continued (part 3)

**Rules** (cite as `implement-language/services-snippets--part-3#<slug>`):

- `apply-declared-throwing-never-thrown-in-practice` MUST
- `withdraw-removes-snippets-and-failures` MUST
- `withdraw-is-safe-on-unknown-identifier` MUST
- `withdraw-is-per-extension` MUST
- `snippets-for-language-filters-by-applies` MUST
- `snippets-for-language-ordering` MUST

- **apply-declared-throwing-never-thrown-in-practice**: `SnippetStore.apply(_:from:at:)`'s signature MUST be able to throw, per `ContributionPoint`, but MUST NOT actually throw for any per-entry failure; every per-entry error MUST be caught and recorded as a `SnippetFileFailure` instead.
- **withdraw-removes-snippets-and-failures**: `SnippetStore.withdraw(extensionIdentifier:)` MUST remove every snippet and every `SnippetFileFailure` recorded for that identifier.
- **withdraw-is-safe-on-unknown-identifier**: `SnippetStore.withdraw(extensionIdentifier:)` MUST be safe to call for an identifier that was never applied.
- **withdraw-is-per-extension**: `SnippetStore.withdraw(extensionIdentifier:)` MUST NOT remove another extension's snippets or failures.
- **snippets-for-language-filters-by-applies**: `SnippetStore.snippets(forLanguage:)` MUST return only snippets whose own `applies(to:)` predicate holds for `language`, in addition to that language being one they were filed under.
- **snippets-for-language-ordering**: `SnippetStore.snippets(forLanguage:)` MUST order its result first by the contributing extensions' identifiers sorted ascending, then, within one extension, by the order its snippets were filed for that language.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `extensionIdentifier` | `String` | none — required | Passed to `SnippetFile.parse` and `SnippetStore.apply`; identifies which extension a snippet, or a recorded failure, came from. `SnippetStore.apply` supplies `manifest.identifier`. |
| `directory` | `URL` | none — required | Passed to `SnippetStore.apply`; the extension's own installed folder, both the base every declared `path` resolves against and the boundary it may not leave. |
| `contributions.snippets` | `[ExtensionManifest.Contributions.Snippet]` (`language: String`, `path: String` pairs) | `[]` when the manifest's `contributes.snippets` key is absent | The declared entries `SnippetStore.apply` reads; each `path` is resolved relative to `directory` and each `language` is the fallback bucket for a snippet whose own `scope` is empty. |
| `SnippetStore.init()` | initializer, no parameters | — | Constructs a store with no applied snippets and no recorded failures; `ExtensionsCoordinator` calls it once and reuses the instance. |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `SnippetFileParseError.notAnObject.errorDescription` | "The file's root is not a JSON object. A snippets file is an object whose keys are snippet names." | Recorded verbatim as a `SnippetFileFailure.reason` and shown in the extensions settings panel when a snippets file's root is not a JSON object. |

This is the only user-facing string these three files define, and it is hardcoded English with no localization table entry or lookup key of its own — `SnippetFileFailure.reason` is a plain `String`, not a localization key, so this string ships in one language regardless of the app's locale.

## Privacy

- **Data collected**: None of `ExtensionSnippet`, `SnippetFileFailure`, or `SnippetStore`'s own state defines a field for a credential or token. `ExtensionSnippet.body`/`.prefix` are values taken verbatim from a snippets file an extension bundles or a user edits by hand; `SnippetFileFailure.path`/`.reason` carry only a manifest-declared file path string and a parse-failure sentence.
- **Storage**: `SnippetStore` holds every applied extension's snippets and failures only in memory, in `snippetsByExtension` and `failures`; none of these three files writes to disk. The snippet files themselves are read from wherever the extension is installed, resolved through `ExtensionResourcePath` (agentictoolkit://recipes/extension-host-core-extensions-extension-resource-path).
- **Transmission**: Not applicable — none of `ExtensionSnippet.swift`, `SnippetFile.swift`, or `SnippetStore.swift` performs network I/O.
- **Retention**: `SnippetStore.withdraw(extensionIdentifier:)` is what removes an extension's snippets and failures from memory (withdraw-removes-snippets-and-failures); nothing here is retained beyond the store's own in-memory lifetime and that call.
- The containment check `apply-refuses-escaping-path` enforces exists precisely to stop a maliciously declared `path` — the escaping-path tests' own comments cite `../../../.ssh/config` as the motivating example — from being read as though it were a snippet and typed into a user's document; `SnippetStore.apply` records that refusal as a failure rather than reading the file.

## Platform Notes

- **SwiftUI**: none of these three files imports SwiftUI, Combine, or `Observation`. A SwiftUI-backed consumer reads `SnippetStore.snippets(forLanguage:)` as plain, already-computed data; if a view must react live to a later `withdraw` or `apply`, it needs its own observation wrapper around the store, since `SnippetStore` publishes nothing itself.
- **Compose**: a Kotlin port models `ExtensionSnippet` as a `data class` over the same six fields (its structural equality standing in for `Equatable`), `SnippetFileParseError` as a `sealed class`/exception type, and `SnippetFile` as a Kotlin `object` whose `parse` functions traverse a `JsonObject` (from `kotlinx.serialization.json` or `org.json`), applying the same string-vs-array, element-wise-vs-whole-array leniency distinctions by hand. `SnippetStore` becomes a class confined to a single coroutine dispatcher — the direct analogue of `@MainActor` — holding a `MutableMap<String, MutableMap<String, List<ExtensionSnippet>>>` for `snippetsByExtension` and a `MutableList<SnippetFileFailure>` for `failures`.
- **React/Web**: a TypeScript port models `ExtensionSnippet` as a `readonly` interface, `SnippetFile.parse` as a function that returns `ExtensionSnippet[]` or throws, operating over `JSON.parse`'s `Record<string, unknown>` output after a small JSONC-stripping step (a hand-written scanner, or a library such as `jsonc-parser`, standing in for `JSONCPreprocessor`). `SnippetStore` becomes a plain class, since JavaScript has no actor isolation to declare; the port instead documents, as a convention rather than a compiler guarantee, that every call into one `SnippetStore` instance must originate on the same event-loop turn.
- **AppKit / UIKit**: this is the source. `ExtensionSnippet.swift`, `SnippetFile.swift`, and `SnippetStore.swift` live in `packages/apple/AgenticToolkit/Language/Snippets/`, part of the `AgenticToolkitLanguage` target, which `project.yml` declares macOS-only (`platform: macOS`). `SnippetStore` is constructed once by `ExtensionsCoordinator` and read by `LSPCompletionDelegate.completionSuggestionsRequested` (`snippets?.snippets(forLanguage: languageId).map { $0.completionItem() }`), which is how a snippet's `CompletionItem` reaches the `CodeEditSourceEditor`-backed completion UI. It depends on `ExtensionResourcePath` and `JSONCPreprocessor` from the `AgenticToolkitCore` target, and on `ExtensionManifest.Contributions.Snippet` from the same target.
- **WinUI 3**: a .NET port models `ExtensionSnippet` as an immutable `record` over `Name`, `Prefix`, `Body`, `Description` (`string?`), `Scopes` (`IReadOnlyList<string>`), and `ExtensionIdentifier` (record equality standing in for `Equatable`). `SnippetFile` becomes a static class parsing with `System.Text.Json.JsonDocument`, checking each entry's `JsonElement.ValueKind` before reading it — the direct analogue of the Swift `as?` casts — with a small preprocessor ahead of it for trailing commas, since `System.Text.Json`'s `JsonCommentHandling.Skip` accepts comments but not trailing commas. `SnippetStore` becomes a `sealed class` confined to the UI thread, asserted with `Debug.Assert(DispatcherQueue.HasThreadAccess)` mirroring `@MainActor`, holding `Dictionary<string, Dictionary<string, List<ExtensionSnippet>>>` for its per-extension, per-language buckets and a `List<SnippetFileFailure>` for `Failures`; the path-containment check ports as a call into that platform's `ExtensionResourcePath` equivalent, `Path.GetFullPath` plus a canonicalized-prefix comparison being the direct analogue of `ExtensionResourcePath.resolve`.

