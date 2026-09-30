<!-- leaf: implement-hub-domain-1/buckets--part-3 · source: hub-domain-buckets.md -->

# Hub Domain: Buckets — continued (part 3)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dataSource` (parameter to `BucketsTopic.init`) | `any BucketsDataSource` | none — required | The server access point this topic navigates and posts through; the host supplies its own implementation. |
| `ecosystem` (parameter to every `child(for:path:rail:)` call, and to `createSpec(for:)`/`createTableSpec(for:bucket:)`) | `Ecosystem` | none — required | Supplies the `ecosystemId` value posted with every create call and, per `list-is-ecosystem-scoped`, the scope of `list`/`tables` reads; not among this recipe's given sources beyond its `id` field. |

None of the three given sources reads an environment variable or a named
settings key; every value `BucketsTopic` needs is supplied by its `init`
parameter, the `Ecosystem`/`Bucket`/`BucketTable` values passed into its
methods, or the user's own form input.

## Localization

None of the three given sources reference a string-key or localization
table; every user-facing string `BucketsTopic` produces is a hardcoded
English literal composed inline:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no key) | `Buckets` | `BucketsTopic.entry.label` and the buckets-list level's `title`. |
| (none — literal, no key) | `Storage buckets and the tables they contain.` | `BucketsTopic.entry.description`. |
| (none — literal, no key) | `No buckets yet.` | Buckets list level's `emptyMessage`. |
| (none — literal, no key) | `New bucket` / `New table` | The two levels' `createAction.title`. |
| (none — literal, no key) | `Name and description.` / `The tables this bucket contains.` | The bucket level's fixed item sublabels. |
| (none — literal, no key) | `Tables` / `No tables yet.` | The tables level's `title`/`emptyMessage`. |
| (none — literal, no key) | `A bucket named "<name>" already exists.` | Create/settings save-action duplicate message (client precheck or server conflict). |
| (none — literal, no key) | `Every table needs a name.` | Create-table/table-detail save-action empty-name message. |
| (none — literal, no key) | `That name has no letters or digits that can be used in a SQL table name. Use at least one a–z letter or 0–9 digit.` | `BucketsTopic.unusableTableNameMessage`. |
| (none — literal, no key) | `Two tables share the name "<name>". Names must be unique.` | Create-table save-action duplicate message (client precheck or server conflict). |
| (none — literal, no key) | `Delete bucket "<name>"? Applications that granted it will lose those tables.` | Settings form's delete confirmation text. |
| (none — literal, no key) | `Remove table "<name>"? Data in it is not deleted until the bucket is.` | Table-detail form's delete confirmation text. |
| (none — literal, no key) | `Bucket` | Settings detail's fixed `title`. |
| (none — literal, no key) | `Name`, `Description`, `SQL table name` | Field labels across the four form specs. |

## Privacy

- **Data collected**: `BucketsTopic` and `BucketsDataSource` handle
  whatever bucket `name`/`description` and table `name` the user types
  into the create/settings forms, plus the server-assigned `id`,
  `ecosystemId`, `kind`, `sqlTableName`, `createdAt`, and `updatedAt`
  values `Bucket`/`BucketTable` decode; none of it is inherently
  distinguished as sensitive by these sources.
- **Storage**: None of the three given sources persist anything to disk,
  a database, or `UserDefaults`; `Bucket`/`BucketTable` values and the
  `FormState` values built from them (documented in the related HTDV
  Engine recipe) exist only in memory for the lifetime of the loaded
  level/detail.
- **Transmission**: `BucketsDataSource`'s nine operations transmit
  whatever a concrete implementation does internally (not among the given
  sources); none of the three given sources performs a network call
  directly or applies any encryption, redaction, or transformation to the
  values before handing them to `dataSource`.
- **Retention**: Not applicable at this layer — how long a bucket, a
  table, or their `description`/`name` text is retained is a server-side
  policy outside these three sources; nothing here defines a
  client-side expiry or cache.

## Platform Notes

- **SwiftUI**: A SwiftUI host would keep `BucketsDataSource`,
  `BucketsModels`, and `BucketsTopic`'s pure static helpers
  (`tableName(from:)`, `tableCount(_:)`) unchanged, since none of them
  depends on AppKit/UIKit or on `BucketsTopic`'s own `@MainActor` class,
  and would drive `createSpec`/`createTableSpec`/`settingsDetail`/`tableDetail`'s
  `FormSpec` values through the same `FormState` bridge described in the
  related HTDV Engine recipe's SwiftUI note, presenting the "New bucket"/
  "New table" forms with `.sheet` in place of `FormSheet.present`.
- **Compose**: Model `BucketsDataSource` as a suspend-function interface
  and `Bucket`/`BucketTable`/their create/update payloads as `@Serializable`
  Kotlin data classes with the same default-tolerant decoding (`kind`
  defaulting to `"custom"` via a custom deserializer or a default
  constructor parameter); reimplement `tableName(from:)` with
  `String.lowercase()` plus a manual scan keeping only ASCII letters and
  digits and collapsing runs of everything else to `"_"`, matching the
  no-leading/trailing-underscore behavior exactly; present the create
  forms as a `ModalBottomSheet`/`AlertDialog` in place of `FormSheet.present`.
- **React/Web**: Model `BucketsDataSource` as an async client interface
  returning the same shapes, with `Bucket` decoding applying the same
  `kind ?? "custom"` and optional-field defaults at the point a response
  is parsed; reimplement `tableName(from:)` as a small function that
  lowercases the input, iterates its code points keeping ASCII
  `a`-`z`/`0`-`9`, and collapses runs of other code points (including
  non-ASCII ones) into a single underscore with no leading or trailing
  underscore, exactly mirroring the Swift scan rather than using a
  locale-aware `String.replace`. Present the create/edit forms as a modal
  dialog in place of `FormSheet.present`, and keep the same
  precheck-then-server-conflict double guard for duplicate names.
- **AppKit / UIKit**: This is the source: `BucketsDataSource.swift`,
  `BucketsModels.swift`, and `BucketsTopic.swift` hold no AppKit/UIKit
  import of their own — `BucketsTopic` depends only on `Foundation` and the
  `AgenticToolkitHTDV` module (`HTDVItem`, `HTDVLevel`, `HTDVChild`,
  `HTDVCreateAction`, `FormSpec`/`FormSection`/`FormAction`/`FormDeleteAction`/
  `FormActions`), and presents its create sheets through the shared
  `FormSheet.present` rather than any AppKit/UIKit API of its own.
- **WinUI 3**: Model `BucketsDataSource` as a C# interface with nine
  `Task`-returning methods, backed by `HttpClient` and `System.Text.Json`
  for a concrete implementation (not among the given sources). Model
  `Bucket`/`BucketTable`/their create/update payloads as C# records with
  `[JsonPropertyName]` attributes; give `Bucket` a custom `JsonConverter`
  (or a `[JsonConstructor]` with nullable parameters) so a missing `kind`
  defaults to `"custom"` and a missing `metadata`/`createdAt`/`updatedAt`
  defaults to `null`, and expose `Description`/`IsBuiltIn` as computed
  read-only properties exactly mirroring `Bucket.description`/`isBuiltIn`.
  Reimplement `tableName(from:)` with `char.IsAsciiLetterOrDigit` and a
  `StringBuilder`, appending `'_'` only when a pending-separator flag is
  set and the builder is non-empty — reproducing the no-leading/trailing-
  underscore behavior exactly, including that a non-ASCII character (an
  accented letter, a CJK character) is a separator, not a candidate for
  transliteration. Use a `ContentDialog` (or a `TeachingTip`-hosted form)
  in place of `FormSheet.present` for the "New bucket"/"New table" flows,
  and compare names with `string.Equals(a, b, StringComparison.OrdinalIgnoreCase)`
  in place of `caseInsensitiveCompare`, keeping the same
  precheck-then-server-conflict double guard for both buckets and tables.

