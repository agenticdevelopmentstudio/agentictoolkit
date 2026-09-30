<!-- leaf: implement-extension-host-core-1/extensions-contributed-settings--edge-cases · source: extension-host-core-extensions-contributed-settings.md -->

# ContributedSettings

**Rules** (cite as `implement-extension-host-core-1/extensions-contributed-settings--edge-cases#<slug>`):

- `null-and-empty-input` MUST — an extension manifest that declares no contributes.configuration key at all MUST classify as .undeclared …
- `boundary-values-bounds-that-invert` MUST — a minimum greater than a maximum (before or, for "integer", after inward rounding) MUST be treated as no bounds at all, …
- `boundary-values-default-outside-agreeing-bounds` MUST — MUST be clamped to the nearer bound with a .defaultOutOfRange note, per default-clamped-to-bounds.
- `error-states-contributes-configuration-present-but-unreadable` MUST — MUST classify as .unreadable(reason:), not .undeclared, per unreadable-configuration.

## Edge Cases

- **Null and empty input**: an extension manifest that declares no `contributes.configuration` key at all MUST classify as `.undeclared` (`undeclared-configuration`); a declared but empty `properties` dictionary within a section MUST drop that section entirely with no note (`empty-section-dropped`); a declared `enum` containing only `null` (no retained string member) MUST fail `choice(from:)` and fall through to type-based or default-based classification exactly like an enum with a non-string member.
- **Boundary values — bounds that invert**: a `minimum` greater than a `maximum` (before or, for `"integer"`, after inward rounding) MUST be treated as no bounds at all, with a `.contradictoryBounds` note, per `bounds-contradiction-dropped`.
- **Boundary values — default outside agreeing bounds**: MUST be clamped to the nearer bound with a `.defaultOutOfRange` note, per `default-clamped-to-bounds`.
- **integer-bound-overflow**: NEEDS REVIEW: Not implemented in source. `Int(exactly: $0.rounded(.up))`/`Int(exactly: $0.rounded(.down))` (`ContributedSettings.swift`) return `nil` for a `Double` bound with magnitude larger than `Int.max`, or for `.nan`/`.infinity`, and `.flatMap` then discards that bound silently — indistinguishable from a schema that declared no bound at all, and no `ContributedSettingNote` is recorded. Every other way a declared bound cannot be honoured (`contradictoryBounds`, a default outside the representable bounds) does produce a note; this path does not. What is missing: whether an out-of-`Int`-range `minimum`/`maximum` should record a note of its own, or is deliberately meant to be treated as absent. Evidence that would settle it: a ruling from whoever maintains `ContributedSettingsBuilder`'s corpus study (see the file's own doc comments citing corpus counts), or a corpus property that exercises this path.
- **Concurrent access**: not applicable as a hazard — `ContributedSettingsBuilder` is a stateless `enum` namespace of pure static functions over `Sendable` value types (`sendable-value-types`, `pure-no-side-effects`); concurrent calls from any thread or actor produce independent results with no shared mutable state to race.
- **Error states — a property that failed to decode at all**: not this file's concern. `ExtensionManifest.Configuration.init(from:)` decodes each property individually with `try?` (`ExtensionManifest.swift`), so a property whose JSON value is not an object (e.g. a bare string) never reaches `ContributedSettingsBuilder` at all — it is simply absent from `section.properties`, with no corresponding `ContributedSettingNote`; see `contributed-settings-024`.
- **Error states — `contributes.configuration` present but unreadable**: MUST classify as `.unreadable(reason:)`, not `.undeclared`, per `unreadable-configuration`.
- **Offline or disconnected state**: not applicable — `ContributedSettings.swift` performs no network call of any kind; it imports only `Foundation` and operates entirely over values already decoded into memory.
