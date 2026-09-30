<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-provider-type-facet--part-2 · source: ai-plugin-runtime-ai-plugin-kit-provider-type-facet.md -->

# Provider Type Facet — continued (part 2)

## Design Decisions

**Decision**: `init(configType:)` matches loosely, by lowercased substring (`contains`), rather than by an exact match against a fixed dictionary of known Config Type strings.
**Rationale**: per the type's own doc comment, `configType` is descriptor copy meant to be read by a person (e.g. "OAuth Account", "Subscription Token"), and a vendor adding new but similar wording tomorrow (e.g. "OAuth 2 Account") should land in the same bucket rather than silently becoming an unbucketed fourth kind of thing. `ProviderTypeFacetTests.looseMatching` exercises exactly this: `"oauth 2 account"` still resolves to `.subscription`.
**Approved**: pending

**Decision**: the subscription/oauth/account rule is checked before the key/token rule, so a string naming both (e.g. `"Subscription Token"`) resolves to `.subscription`, not `.apiKey`.
**Rationale**: per `ProviderTypeFacetTests.subscriptionWinsOverKey`'s own comment, "OAuth Account" style strings sometimes also say "token", and the account is the thing the user actually needs to have ready, so it takes precedence over the token wording. The same fixed-order reasoning extends to the local rule being checked before the key/token rule (config-type-precedence-order, provider-type-facet-008), though no existing test exercises that specific combination.
**Approved**: pending
