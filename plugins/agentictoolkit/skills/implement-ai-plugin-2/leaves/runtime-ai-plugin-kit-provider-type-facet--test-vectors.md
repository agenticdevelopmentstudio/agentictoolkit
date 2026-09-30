<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-provider-type-facet--test-vectors · source: ai-plugin-runtime-ai-plugin-kit-provider-type-facet.md -->

# Provider Type Facet

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| provider-type-facet-001 | config-type-subscription-match, config-type-local-match, config-type-apikey-match | `ProviderTypeFacet(configType:)` on `"OAuth Account"`, `"Subscription"`, `"API Key"`, `"Local"`, `"Local Server"` (traced to `ProviderTypeFacetTests.realConfigTypes`) | Returns `.subscription`, `.subscription`, `.apiKey`, `.local`, `.local` respectively |
| provider-type-facet-002 | config-type-case-insensitive, config-type-subscription-match, config-type-apikey-match, config-type-default-custom | `ProviderTypeFacet(configType:)` on `"oauth 2 account"`, `"Access Token"`, `""`, `"Bring your own endpoint"` (traced to `ProviderTypeFacetTests.looseMatching`) | Returns `.subscription`, `.apiKey`, `.custom`, `.custom` respectively |
| provider-type-facet-003 | config-type-precedence-order, config-type-subscription-match | `ProviderTypeFacet(configType: "Subscription Token")` (traced to `ProviderTypeFacetTests.subscriptionWinsOverKey`) | Returns `.subscription`, not `.apiKey`, even though the string also contains `"token"` |
| provider-type-facet-004 | matches-empty-selection, matches-membership | `ProviderTypeFacet.matches(type: .apiKey, selected: [])`; `matches(type: .apiKey, selected: [.apiKey, .local])`; `matches(type: .subscription, selected: [.apiKey, .local])` (traced to `ProviderTypeFacetTests.matches`) | Returns `true`, `true`, `false` respectively |
| provider-type-facet-005 | title-strings, detail-strings | For every facet in `ProviderTypeFacet.allCases` (traced to `ProviderTypeFacetTests.labels`) | `facet.title.isEmpty == false` and `facet.detail.isEmpty == false` for all four cases |
| provider-type-facet-006 | case-iterable-order, case-set | `ProviderTypeFacet.allCases` (traced to the case declaration order in `ProviderTypeFacet.swift`; no test enumerates order directly) | Returns `[.subscription, .apiKey, .local, .custom]`, in that order |
| provider-type-facet-007 | rawvalue-initializer, raw-value-identity | `ProviderTypeFacet(rawValue: "apiKey")`; `ProviderTypeFacet(rawValue: "bogus")` (traced to the compiler-synthesized `RawRepresentable` initializer that `ProviderPickerViewController.swift` calls via `compactMap(ProviderTypeFacet.init(rawValue:))`) | Returns `.apiKey` for `"apiKey"`; returns `nil` for `"bogus"` |
| provider-type-facet-008 | config-type-precedence-order, config-type-local-match, config-type-apikey-match | `ProviderTypeFacet(configType: "Local API Key")` (derived directly from the if/else-if order in `ProviderTypeFacet.swift`; not exercised by an existing test) | Returns `.local` — the local rule is checked and matches before the key/token rule is ever reached |
