<!-- leaf: implement-site/wordmark--test-vectors · source: site-wordmark.md -->

# SiteWordmark

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|---|---|---|---|
| T1 | render-registry-brand, accent-trailing-word | `siteId="research"` | Renders `Agentic Developer` + a gold-italic `Research`; full text reads "Agentic Developer Research" |
| T2 | default-identity-to-description | `siteId="research"` (no `tagline`) | Identity line reads "Store & review research" (the registry description) |
| T3 | honor-explicit-tagline | `siteId="research" tagline="Published research"` | Identity line reads "Published research" |
| T4 | omit-identity-when-null | `siteId="research" tagline={null}` | No identity line is rendered |
| T5 | fall-back-on-unknown-site | `siteId={'not-a-real-site' as SiteId}` | No lead segment; renders `not-a-real-site` as the accent; no identity line; does not throw |
| T6 | accent-trailing-word | `siteId="bitbag"` | `fullLabel` "Bitbag" does not start with "Agentic Developer "; no lead segment, whole label "Bitbag" is the accent; identity line reads "The Agentic Developer persona" |
| T7 | omit-identity-when-null | `siteId="research" tagline=""` | No identity line is rendered (`''` is falsy, same as `null`) |
