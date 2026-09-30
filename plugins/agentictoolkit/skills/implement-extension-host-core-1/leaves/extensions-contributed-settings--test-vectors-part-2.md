<!-- leaf: implement-extension-host-core-1/extensions-contributed-settings--test-vectors-part-2 · source: extension-host-core-extensions-contributed-settings.md -->

# ContributedSettings — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| contributed-settings-028 | sendable-value-types, pure-no-side-effects | Round-trip an `ExtensionManifest.ConfigurationProperty` (union `type` included) through `JSONEncoder`/`JSONDecoder`; separately, capture a `ContributedSetting` value inside an async `Task` under `SWIFT_STRICT_CONCURRENCY: complete` | the round trip decodes back equal to the original — mirrors `propertyEncodingIsAFixedPoint`; the `Task` capture compiles with no Sendable diagnostic, since every public type in this file is declared `Sendable` |
| contributed-settings-029 | mixed-union-fallback | Classify `{ "type": ["number", null], "default": 1.5 }` and `{ "type": ["number", "null"], "default": 1.5 }` | both classify identically to `.number(default: 1.5, minimum: nil, maximum: nil)` — a JSON `null` member and the string `"null"` collapse to the same union result — mirrors `nullMemberInATypeUnionSurvives` |
