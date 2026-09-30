<!-- leaf: implement-status-web-src-lib-2/slug--test-vectors · source: status-web-src-lib-slug.md -->

# Status Web Slug

## Conformance Test Vectors

The source has no `slug.test.ts`. Every vector below follows from the four chained steps in `slugify`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| slug-001 | lowercase-first, hyphenate-runs | `slugify("Production Sites")` | `"production-sites"` |
| slug-002 | trim, trim-hyphens | `slugify("  Hello World  ")` | `"hello-world"` |
| slug-003 | hyphenate-runs, no-double-hyphen | `slugify("a -- b__c")` | `"a-b-c"` |
| slug-004 | hyphenate-runs, shared-form | `slugify("status.example.com")` | `"status-example-com"` |
| slug-005 | trim-hyphens | `slugify("--Edge!!")` | `"edge"` |
| slug-006 | ascii-only-alphabet | `slugify("Café Menu")` | `"caf-menu"` |
| slug-007 | empty-allowed, total | `slugify("")`, `slugify("   ")`, `slugify("---")`, `slugify("日本")` | `""` each, no exception |
| slug-008 | idempotent | `slugify(slugify("My Group #1"))` | `"my-group-1"`, the same as `slugify("My Group #1")` |
| slug-009 | no-uniqueness | `slugify("A B")`, `slugify("a-b")`, `slugify("a_b")` | `"a-b"` each |
| slug-010 | ascii-only-alphabet | `slugify("Server 42")` | `"server-42"`, digits kept |
| slug-011 | signature, pure | Call `slugify("x")` twice | `"x"` both times, returned synchronously, nothing else observable changes |
