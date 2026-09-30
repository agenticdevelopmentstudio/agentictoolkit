<!-- leaf: implement-extension-host-core-2/extensions-webview-panel-state--part-2 · source: extension-host-core-extensions-webview-panel-state.md -->

# WebviewPanelState — continued (part 2)

## Platform Notes

- **SwiftUI**: the source (`WebviewPanelState.swift`) is plain
  `Foundation` — `JSONEncoder`, `JSONDecoder`, `Data`, `String` — with no
  dependency on SwiftUI or any view-layer framework. It sits in
  `AgenticToolkitCore`, alongside its sibling `WebviewPanelOptions`, and is
  consumed by the `macOS`-tier `WebviewPanelViewController` and
  `WebviewPanelSerializer`. A port that keeps this type in Swift needs
  nothing beyond `Foundation` and `Codable`.
- **Compose**: model `WebviewPanelState` as a Kotlin `data class` with the
  same four properties, and use `kotlinx.serialization`'s `@Serializable`
  with an explicit sorted-key JSON configuration (or sort the resulting
  `JsonObject`'s keys before serializing to text, since `kotlinx.serialization`
  does not sort keys by default) to reproduce `sorted-key-encoding`.
  `viewType` as a non-optional, non-defaulted constructor parameter
  reproduces `missing-view-type-refused` automatically, since
  `kotlinx.serialization` throws on a missing required field; `title`,
  `state`, and `options` need explicit default values or
  `@EncodeDefault`/nullable handling to reproduce the other three fields'
  defaulting behavior.
- **React/Web**: represent the shape as a plain TypeScript interface with
  `viewType: string`, `title: string`, `state: string | null`, and
  `options: WebviewPanelOptions`. `JSON.stringify` does not sort object keys,
  so reproducing `sorted-key-encoding` needs an explicit
  `Object.keys(value).sort()` replacer function passed to `JSON.stringify`.
  `JSON.parse` on the stored text, followed by manual field-by-field
  validation (throwing when `viewType` is missing or not a string,
  defaulting `title` to `""` and `options` to the safe posture when absent)
  reproduces the decode-side behavior, since there is no built-in decoder
  that enforces per-field presence the way Swift's `Codable` does.
- **AppKit / UIKit**: identical to the SwiftUI note — the type depends on
  neither AppKit nor UIKit, so a macOS host consumes the same
  `AgenticToolkitCore` type directly with no translation needed. (The panel
  that actually renders from a restored value, `WebviewPanelViewController`,
  is AppKit and is out of this file's own scope.)
- **WinUI 3**: use `System.Text.Json` with a `JsonSerializerOptions` whose
  `PropertyNamingPolicy` is left alone (the field names already match) and
  whose writer is configured, or whose properties are alphabetized before
  serialization, to reproduce `sorted-key-encoding` — `System.Text.Json` does
  not sort properties by declaration order by default, so an explicit
  ordering step is needed. Model `state` as a nullable `string?` mapped with
  `JsonIgnoreCondition.WhenWritingNull` on the property so a `null` state
  omits the key exactly as `encodeIfPresent` does, reproducing
  `absent-state-omits-key`. Make `viewType` a required constructor parameter
  (a C# 11 `required` property, or a positional record parameter with no
  default) so `System.Text.Json` throws `JsonException` on missing JSON
  rather than defaulting it, reproducing `missing-view-type-refused`; give
  `title` and `options` explicit fallback values in the deserializing
  constructor to reproduce their defaulting behavior. `HttpClient`,
  `Windows.Storage`, `Task`/`async`, `ObservableCollection`, and
  `INotifyPropertyChanged` all have no role here: every operation in the
  source is synchronous, non-networked, and returns a value rather than
  raising a change notification.

## Design Decisions

- **Decision**: the extension's `state` text is stored and returned exactly
  as given, never parsed as JSON or re-serialized by this type.
  **Rationale**: the source's own doc comment states that this value "goes
  straight back into a `<script>` element on restore," so re-encoding it
  would reorder keys and re-escape characters — a different value than the
  one the extension saved, produced by a layer that the doc comment states
  "has no business reading it at all."
  **Approved**: pending
- **Decision**: the owning extension's identifier is not a stored field,
  even though every caller that has one available when constructing a
  `WebviewPanelState` could easily store it.
  **Rationale**: the source's doc comment states the identifier is
  derivable from `viewType` via the `onWebviewPanel:<viewType>` activation
  event, and a second copy of a derivable fact is one that can disagree with
  the first.
  **Approved**: pending
- **Decision**: a missing `viewType` key throws rather than decoding to an
  empty string or another placeholder, while a missing `title` or `options`
  key decodes to a defined default instead of throwing.
  **Rationale**: the source's doc comment on `init(from:)` draws this
  distinction explicitly — "a missing title is survivable — an untitled tab
  is still the user's tab. A missing view type is not: it names the
  serializer that knows how to rebuild this panel, and a default would hand
  the panel to whichever provider happened to answer to the empty string."
  This is also the reasoning behind the open question on
  `empty-view-type-validation`: it applies to a `viewType` key that is
  present but empty exactly as it does to one that is absent, and only the
  absent case is currently guarded.
  **Approved**: pending
- **Decision**: options absent from stored JSON decode to the safe,
  no-scripts, no-forms, default-roots posture rather than to whatever the
  most commonly-used options happen to be.
  **Rationale**: the source's doc comment states that an entry written
  before `options` existed is still a panel the user had open and must come
  back, "but what it must not do is come back with capabilities nobody
  recorded it having" — defaulting toward permissiveness would silently
  grant a restored panel scripting or file access its extension never
  declared.
  **Approved**: pending
