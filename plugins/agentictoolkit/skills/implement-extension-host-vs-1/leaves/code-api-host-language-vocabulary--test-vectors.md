<!-- leaf: implement-extension-host-vs-1/code-api-host-language-vocabulary--test-vectors · source: extension-host-vs-code-api-host-language-vocabulary.md -->

# HostLanguageVocabulary

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hlv-001 | contributed-deduplication | `LanguageContributionPoint` with one extension contributing `{ "id": "swift", "extensions": [".notswift"] }`; `HostLanguageVocabulary(contributionPoint:).languageIdentifiers` | `.filter { $0 == "swift" }.count == 1` — source: `HostLanguageVocabularyTests.aContributedBuiltInIdentifierIsNotDuplicated` |
| hlv-002 | default-language-inclusion | `LanguageContributionPoint` with no contributions; `HostLanguageVocabulary(contributionPoint:).languageIdentifiers` | `.contains(CodeLanguage.default.id.rawValue)` is `true` — source: `HostLanguageVocabularyTests.plainTextIsPresent` |
| hlv-003 | built-ins-first-ordering, contributed-order-preservation | `LanguageContributionPoint` with one extension contributing `{ "id": "cobol", "extensions": [".cob"] }`; the resulting `languageIdentifiers`' index of `python` versus its index of `cobol` | index of `python` is less than index of `cobol` — source: `HostLanguageVocabularyTests.mergesBuiltInAndContributedIdentifiersWithBuiltInsLeading` |
| hlv-004 | computed-not-cached | call `languageIdentifiers` twice on the same `HostLanguageVocabulary` instance with no mutation of `contributionPoint` between calls | both calls return equal arrays, and neither call is served from a stored field — traced to the source's "Computed, never cached" doc comment; no dedicated test |
| hlv-005 | contributed-order-preservation | `LanguageContributionPoint` with one extension contributing languages in the manifest order `["second", "first", "third"]` (none matching a built-in) | the tail of `languageIdentifiers` reads `["second", "first", "third"]`, matching `contributedLanguageIdentifiers`'s own manifest-order guarantee — traced to `LanguageContributionPointVocabularyTests.contributedIdentifiersPreserveManifestOrderWithinOneExtension`, composed through `HostLanguageVocabulary`; no dedicated `HostLanguageVocabularyTests` case |
| hlv-006 | tsname-exclusion | `LanguageContributionPoint` with no contributions; `HostLanguageVocabulary(contributionPoint:).languageIdentifiers` | contains `javascript`, `jsx`, `typescript`, and `tsx` as four distinct entries, none collapsed into a shared `tsName` — traced to the source's "Does not use `CodeLanguage.tsName`" doc comment; no dedicated test |
| hlv-007 | main-actor-isolation, non-sendable-declaration | a non-`@MainActor` call site reading `languageIdentifiers` on a `HostLanguageVocabulary` instance without an `await` hop | fails to compile — traced to the `@MainActor` declaration with no `Sendable` conformance; compiler-enforced, no dedicated runtime test |
