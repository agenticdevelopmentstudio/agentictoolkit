<!-- leaf: implement-extension-host-core-1/extensions-contributed-views--part-3 · source: extension-host-core-extensions-contributed-views.md -->

# ContributedViewsBuilder — continued (part 3)

## Localization

No string in this file is externalized through a localization key (no `NSLocalizedString`/`String(localized:)`). Every `ContributedViewNote.detail` is a hardcoded English `String`, built by interpolating manifest-supplied values into a fixed English template:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded) | `declared more than once; the declaration in "<target>" is the one registered.` | `ContributedViewNote.Kind.duplicateViewID` |
| (none — hardcoded) | `targets the container "<target>", which neither this extension nor this host declares; the pane is arranged along the horizontal axis.` | `ContributedViewNote.Kind.unknownContainer` |
| (none — hardcoded) | `declares <key> in a form this host cannot read; the pane is offered without it.` | `ContributedViewNote.Kind.malformedField` |
| (none — hardcoded) | `declares when: <clause>. This host does not evaluate when clauses, so the pane is offered whatever the condition would have said.` | `ContributedViewNote.Kind.whenNotEvaluated` |
| (none — hardcoded) | `asks for the icon $(<name>), which has no equivalent in this host's symbol set; the pane is offered without an icon.` | `ContributedViewNote.Kind.unmappedIcon` |
| (none — hardcoded) | `asks for the image <path> from inside the extension; this host does not draw extension image files, so the pane is offered without an icon.` | `ContributedViewNote.Kind.fileIcon` |

## Privacy

- **Data collected**: `ContributedViewsBuilder` reads only manifest-declared display metadata — extension identifier, view id, name, icon reference (a codicon name or a relative file path string, never opened), `when` clause text, `visibility`, and `initialSize`. It never reads, stores, or transmits a credential, token, or user-content value.
- **Storage**: This file writes nothing to disk or to any persistent store; it returns its result to the caller, which decides what to keep (see `ExtensionRegistry`/`ContributionRegistrations`, outside this file's scope).
- **Transmission**: This file performs no network communication.
- **Retention**: The returned `containers`, `views`, and `notes` arrays exist only as values the caller holds; this builder itself retains nothing between calls.

## Platform Notes

- **SwiftUI**: The source itself; `ContributedViews.swift` has no view-layer dependency at all (Foundation-only, no `@MainActor`, no observable state). A SwiftUI extension host consumes `ContributedView`/`ContributedViewContainer` values the same way any other consumer does — typically by feeding `build(from:manifest:)`'s result into an `@Observable` registry that a view observes, since the builder itself is a one-shot pure computation with nothing to observe.
- **Compose**: Kotlin equivalents: `ContributedView.Kind` as a Kotlin `enum class`; `ContributedView`/`ContributedViewContainer`/`ContributedViewNote` as `data class`es; `Map<String, List<View>>` for the keyed manifest dictionaries, decoded with `kotlinx.serialization`. Kotlin's `Map` gives no iteration-order guarantee either, so the same explicit `sortedWith(compareBy(...))` on `(location, index)`/`(target, index)` composite keys is required for the same determinism reason.
- **React/Web**: TypeScript `interface`s for the three value types and a string-literal union (`"tree" | "webview"`) for `Kind`. `Record<string, ViewEntry[]>` mirrors the Swift dictionaries; a manual tolerant-decode layer (checking each optional field's `typeof` before assignment) replaces the `unreadableKeys`/`try?` pattern, since `JSON.parse` alone gives no per-field recovery. `Array.prototype.sort` with an explicit comparator on the same composite keys reproduces the ordering; note that JavaScript's `sort` has been a stable sort since ES2019 (unlike Swift's), so a web port's ordering bug surface is narrower, but keeping the explicit composite key is still correct and clearer.
- **AppKit / UIKit**: Same note as SwiftUI — `ContributedViews.swift` has no AppKit or UIKit dependency of any kind; a platform-specific consumer (such as a tabs registry or pane controller) is what turns these values into a rendered pane, not this file.
- **WinUI 3**: `Kind` as a C# `enum`; `ContributedView`, `ContributedViewContainer`, and `ContributedViewNote` as `record` types (giving structural equality for free, matching Swift's `Equatable` synthesis). `System.Text.Json` with a custom `JsonConverter` reproduces the per-field `try`/fallback-to-`nil` decode that produces `unreadableKeys` — `System.Text.Json`'s default behavior is to throw for the whole object on one bad property, so each optional property needs its own guarded read inside the converter, the same shape as the source's local `read<T>` closure. `Dictionary<string, List<T>>` for the manifest's keyed containers. `Enumerable.OrderBy(...).ThenBy(...)` reproduces the sort; LINQ's `OrderBy` is documented as stable, so — unlike the Swift source, which states its composite key exists *because* `sort` is not stable — a WinUI 3 port could rely on `OrderBy`'s stability alone, but keeping the explicit `(location, index)`/`(target, index)` key is still recommended for parity with the source and for correctness if the sort implementation ever changes. No `Task`/`async` is needed: the source performs no I/O and this port's equivalent method should stay a plain synchronous method, matching the source's own signature.

## Design Decisions

**Decision**: A repeated `containerID` across two different `viewsContainers` locations is resolved to whichever declaration is first in the already-sorted `containers` array (alphabetical by location, then declared order within it) for the purpose of deciding a view's axis — not first in the manifest's raw text, and not deduplicated out of the returned `containers` array itself.
**Rationale**: The source's own comment states this directly: "First declaration wins for a repeated container id, and `containers` is already sorted, so 'first' is a fact about the manifest's content rather than about a dictionary's hash seed." Deduplicating the returned `containers` array was rejected because nothing currently reads that array for rendering (Ruling FD); only the axis-resolution map (`locationsByContainerID`) needs a single answer per id.
**Approved**: pending

**Decision**: A dropped duplicate view (the second-or-later declaration of a repeated `id`) contributes only its `duplicateViewID` note and no others — its own `when`, icon, or `unreadableKeys` never produce a `whenNotEvaluated`, `unmappedIcon`, `fileIcon`, or `malformedField` note, because the `continue` after recording the duplicate note skips every later check in the loop body entirely.
**Rationale**: This follows directly from the control flow in `build(from:manifest:)`: the duplicate check and its `continue` run before the icon, `when`, and `unreadableKeys` handling for that same loop iteration, so a dropped entry's other declarations are never inspected at all. This is stated here because a reader tracing only the duplicate-id branch could otherwise expect a dropped duplicate to still contribute its other notes.
**Approved**: pending

**Decision**: Codicon name matching is exact-case only; `CodiconSymbols.table`'s keys are looked up with no normalization.
**Rationale**: Traceable directly to `CodiconSymbols.symbolName(forCodicon:)`, which is a plain `table[codicon]` dictionary subscript with no `.lowercased()` or other normalization applied to `codicon` first. Every real-world codicon reference VS Code itself emits is already lowercase, so this has no observed cost in the corpus this table was built from, but a manifest that spells a codicon in a different case will see it treated as unmapped.
**Approved**: pending

**Decision**: `preferredAxisIsVertical` is `true` exactly when a view's resolved location is the literal string `"panel"`, including when a view targets the *built-in* container id `"panel"` directly with no self-declared `viewsContainers` entry at all — even though the enumerated built-in ids are otherwise all `false`.
**Rationale**: The source's own comment calls this out explicitly as a deliberate departure from a literal reading of the built-in-id enumeration: "`panel`... is the one location that means 'the bottom strip'... Ruling FD says a view's axis follows its container's *location*... `panel` is both: it is the `viewsContainers` key that means the bottom strip **and** a built-in container id... This resolves it to vertical, applying the ruling's reasoning... rather than its enumeration." The `isKnownTarget &&` conjunction in the axis computation is written out for the same reason the comment calls "unreachable today... which is exactly why it needs saying": the only string that satisfies the location-equals-`"panel"` check is `"panel"` itself, which is always a known target, so the conjunction is currently redundant but documents that the code did not silently rely on that coincidence.
**Approved**: pending
