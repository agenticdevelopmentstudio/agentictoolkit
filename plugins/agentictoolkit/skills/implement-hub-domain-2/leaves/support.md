<!-- leaf: implement-hub-domain-2/support · source: hub-domain-support.md -->

# Hub Domain: Support

## Overview

The Support group is seven small, independent pieces of non-UI logic that
every Hub feature module builds on:

- **`FormDetails`** (`FormDetails.swift`) — factories for the two detail
  panes every feature uses: an editable form (`form`) and a read-only
  notice (`notice`).
- **`HubDates`** (`HubDates.swift`) — ISO-8601 string ↔ `Date` conversion
  at the three edges a feature touches dates: forms (`value`), labels
  (`display`), and request bodies (`iso`).
- **`HubError.wrap`** (`HubError+Wrap.swift`) — the universal error
  boundary: "the rail only ever shows `HubError`," normalizing whatever a
  data source throws.
- **`HubText`** (`HubText.swift`) — one helper, `nonBlank`, that turns a
  form's `""` into `nil` so optional fields encode as absent, not empty.
- **`JSONValue`** (`JSONValue.swift`) — a `Codable` JSON-document value
  type for backend fields typed as free-form JSON (bag values, metadata,
  template vars).
- **`RailPath`** (`RailPath.swift`) — two position helpers for the
  `[HTDVItem]` path a module receives in `child(for:)`.
- **`Slug`** (`Slug.swift`) — the identifier rules shared by every feature
  that lets a user pick a slug (personas, products, buckets, users).

None of the seven files depends on any of the others. `HTDVDetail`,
`HTDVItem`, `FormSpec`, `FormSection`, `FormReadOnlyField`, `FormValue`,
`FormState`, and `FormViewController` are HTDV Engine types these files
build on or return but are not among this recipe's seven given
sources — see the related HTDV Engine recipe. `HubModules` (the
`@MainActor` injection-point enum) and the base `HubError` enum (its
cases, such as `.validation`, `.notFound`, `.conflict`) are likewise
Hub-wide types referenced here, but not redescribed beyond what
`FormDetails.form` and `HubError.wrap`/`JSONValue.parse` do with them.

