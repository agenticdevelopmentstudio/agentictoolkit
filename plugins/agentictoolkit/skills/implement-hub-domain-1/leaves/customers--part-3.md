<!-- leaf: implement-hub-domain-1/customers--part-3 · source: hub-domain-customers.md -->

# Hub Domain: Customers — continued (part 3)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dataSource` (parameter to `CustomersTopic.init`) | `any CustomersDataSource` | none — required | The server access point this topic navigates and posts through; the host supplies its own implementation. |
| `ecosystem` (parameter to every `child(for:path:rail:)` call, and to `createSpec(for:)`) | `Ecosystem` | none — required | Supplies the `ecosystemId` value posted with every create/update call and, per `list-is-ecosystem-scoped`, the scope of `list(ecosystemID:)` reads; not among this recipe's given sources beyond its `id` field. |

None of the three given sources reads an environment variable or a named
settings key; every value `CustomersTopic` needs is supplied by its
`init` parameter, the `Ecosystem`/`Customer` values passed into its
methods, or the user's own form input.

## Localization

None of the three given sources reference a string-key or localization
table; every user-facing string `CustomersTopic` produces is a hardcoded
English literal composed inline:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no key) | `Users` | `CustomersTopic.entry.label` and the users-list level's `title`. |
| (none — literal, no key) | `The people who sign in to this product.` | `CustomersTopic.entry.description`. |
| (none — literal, no key) | `No users yet.` | Users list level's `emptyMessage`. |
| (none — literal, no key) | `New user` | The list level's `createAction.title`, reused as `FormSheet.present`'s dialog title. |
| (none — literal, no key) | `Enter a valid email address.` | `CustomersTopic.emailMessage`, the shared email field's pattern-mismatch message. |
| (none — literal, no key) | `A user with email "<email>" already exists.` | Create/detail save-action duplicate message (client precheck or server conflict). |
| (none — literal, no key) | `Delete user` | Detail form's delete action `title`. |
| (none — literal, no key) | `Delete user "<label>"? This cannot be undone.` | Detail form's delete confirmation text. |
| (none — literal, no key) | `User` | Detail's fixed `title`. |
| (none — literal, no key) | `Email`, `Display name`, `External ID`, `Handle`, `Avatar URL` | The five shared field labels from `fieldSpec(isRequiredEmail:)`. |

The generic `"<label> is required"` message a blank required field
produces (for example, a blank `email`) belongs to the Forms subsystem's
own validation, documented in the related HTDV Engine recipe, not to any
of this recipe's three given sources.

## Privacy

- **Data collected**: `CustomersTopic` and `CustomersDataSource` handle
  whatever `email`, `displayName`, `externalId`, `slug`, and `avatarUrl`
  the user types into the create/detail forms, plus the server-assigned
  `id`, `ecosystemId`, `createdAt`, and `updatedAt` values `Customer`
  decodes; `email` and `externalId` in particular are personally
  identifying, though none of it is inherently distinguished as sensitive
  by these sources.
- **Storage**: None of the three given sources persist anything to disk,
  a database, or `UserDefaults`; `Customer` values and the `FormState`
  values built from them (documented in the related HTDV Engine recipe)
  exist only in memory for the lifetime of the loaded level/detail.
- **Transmission**: `CustomersDataSource`'s five operations transmit
  whatever a concrete implementation does internally (not among the given
  sources); none of the three given sources performs a network call
  directly or applies any encryption, redaction, or transformation to the
  values before handing them to `dataSource`.
- **Retention**: Not applicable at this layer — how long a customer or
  their descriptive fields are retained is a server-side policy outside
  these three sources; nothing here defines a client-side expiry or
  cache.

## Platform Notes

- **SwiftUI**: A SwiftUI host would keep `CustomersDataSource`,
  `CustomersModels`, and `CustomersTopic`'s pure static helpers
  (`fieldSpec(isRequiredEmail:)`, `input(from:ecosystemID:)`) unchanged,
  since none of them depends on AppKit/UIKit or on `CustomersTopic`'s own
  `@MainActor` class, and would drive `createSpec`/`detail`'s `FormSpec`
  values through the same `FormState` bridge described in the related
  HTDV Engine recipe's SwiftUI note, presenting the "New user" form with
  `.sheet` in place of `FormSheet.present`.
- **Compose**: Model `CustomersDataSource` as a suspend-function interface
  and `Customer`/`CustomerInput` as `@Serializable` Kotlin data classes
  with every descriptive field nullable, matching the source's own "every
  descriptive field is nullable on the wire" contract; reimplement
  `input(from:ecosystemID:)`'s asymmetry exactly — trim-only for `email`,
  blank-to-`null` for the other four — and present the "New user" form as
  a `ModalBottomSheet`/`AlertDialog` in place of `FormSheet.present`.
- **React/Web**: Model `CustomersDataSource` as an async client interface
  returning the same shapes, with a TypeScript `Customer` type whose
  descriptive fields are `string | null` and a `CustomerInput` type whose
  `email` is a required `string` and the other four are optional;
  reimplement the email-pattern check with the same regex literal
  (`emailPattern`) rather than a browser's native email input validation,
  so the user-facing message stays `"Enter a valid email address."` on
  every platform. Present the create/edit forms as a modal dialog in place
  of `FormSheet.present`, and keep the same precheck-then-server-conflict
  double guard for duplicate emails.
- **AppKit / UIKit**: This is the source: `CustomersDataSource.swift`,
  `CustomersModels.swift`, and `CustomersTopic.swift` hold no AppKit/UIKit
  import of their own — `CustomersTopic` depends only on `Foundation` and
  the `AgenticToolkitHTDV` module (`HTDVItem`, `HTDVLevel`, `HTDVChild`,
  `HTDVCreateAction`, `HTDVDetail`,
  `FormSpec`/`FormSection`/`FormAction`/`FormDeleteAction`/`FormActions`),
  and presents its create sheet through the shared `FormSheet.present`
  rather than any AppKit/UIKit API of its own.
- **WinUI 3**: Model `CustomersDataSource` as a C# interface with five
  `Task`-returning methods, backed by `HttpClient` and `System.Text.Json`
  for a concrete implementation (not among the given sources). Model
  `Customer` as a C# record with `[JsonPropertyName]` attributes and
  nullable reference types for every descriptive field, and expose
  `Label`/`Sublabel` as computed read-only properties exactly mirroring
  `Customer.label`/`sublabel`'s fallback chain, including that a
  whitespace-only value is treated as missing. Model `CustomerInput` as a
  record whose `Email` is a non-nullable `string` and whose other four
  properties are nullable, serialized with
  `JsonIgnoreCondition.WhenWritingNull` to reproduce "optional fields
  encode as absent, never `null`." Use a `ContentDialog` (or a
  `TeachingTip`-hosted form) in place of `FormSheet.present` for the
  "New user" flow, and compare emails with
  `string.Equals(a, b, StringComparison.OrdinalIgnoreCase)` in place of
  `caseInsensitiveCompare`, keeping the same
  precheck-then-server-conflict double guard.

## Design Decisions

**Decision**: `createSpec(for:)`'s save action checks for a duplicate
email against a freshly fetched customer list *before* calling
`create(_:)`, and also catches an `HubError.conflict` the create call
itself might throw, re-throwing it as the identical duplicate-email
message either way; `detail(for:)`'s save action skips the precheck and
relies on the conflict catch alone.
**Rationale**: The precheck-then-create sequence has an unavoidable
check-then-act window — nothing in these three sources locks the
ecosystem between the list read and the create write — so a second,
concurrent create for the same email can still reach the server after the
precheck passed. Catching the server's own conflict response and
re-mapping it to the same user-facing message means a caller sees one
consistent duplicate-email error regardless of which guard actually
caught it. The source does not explain why `detail`'s save skips the
precheck the create path performs; the observable effect is that renaming
an existing user's email to one already in use is caught only by the
server's response, one round trip later than the create path's own local
check.
**Approved**: pending

**Decision**: `input(from:ecosystemID:)` trims `email` but never
substitutes `nil` for it, while trimming-and-nil-substituting
(`HubText.nonBlank`) the other four fields.
**Rationale**: `CustomerInput.email` is declared non-optional, so there is
no `nil` to substitute — an absent or blank email becomes the empty
string `""`, which the shared `emailPattern` regex then rejects rather
than the Forms-required-field check rejecting it outright (since
`email`'s own `isRequired: true` already blocks an empty submission
before this function runs at all). The other four fields are genuinely
optional on the wire, so a blank value legitimately means "no value,"
which `HubText.nonBlank` expresses as `nil` rather than posting an empty
string.
**Approved**: pending

**Decision**: `fieldSpec(isRequiredEmail:)` takes a Boolean parameter that
both `createSpec` and `detail` always pass as `true`, per the source's own
comment that the parameter "keeps the create and detail specs literally
shared."
**Rationale**: Sharing one field-building function guarantees the
"email" field's label, placeholder, pattern, and pattern message stay
identical between the create dialog and the detail form without a second
field literal to drift out of sync; the parameter exists as a documented
seam for a future caller that might need an optional-email variant, even
though no such caller exists among these three sources today.
**Approved**: pending
