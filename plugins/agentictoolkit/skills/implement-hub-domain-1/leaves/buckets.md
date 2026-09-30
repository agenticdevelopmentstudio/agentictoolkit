<!-- leaf: implement-hub-domain-1/buckets · source: hub-domain-buckets.md -->

**Rules** (cite as `implement-hub-domain-1/buckets#<slug>`):

- `data-source-contract` MUST
- `list-is-ecosystem-scoped` MUST
- `tables-spans-every-bucket-in-the-ecosystem` MUST
- `data-source-is-class-bound` MUST
- `bucket-metadata-shape` MUST
- `bucket-shape` MUST
- `bucket-decoding-tolerates-missing-kind-and-optionals` MUST
- `bucket-description-derivation` MUST
- `bucket-is-built-in-derivation` MUST
- `bucket-create-requires-metadata` MUST
- `bucket-update-is-a-partial-patch` MUST
- `bucket-table-shape` MUST
- `bucket-table-create-shape` MUST
- `bucket-table-update-has-no-sql-name-field` MUST

# Hub Domain: Buckets

## Overview

The Buckets domain is the Hub's storage-bucket management: buckets (rows of
`/bucket/buckets`) and the tables each one contains (rows of
`/bucket/bucket-types`). It is three cooperating pieces:

- **`BucketsDataSource`** (`BucketsDataSource.swift`) — the protocol
  through which the Buckets topic reaches the server: list/get/create/
  update/delete for buckets, and the parallel five for tables.
- **The data shapes** (`BucketsModels.swift`) — `Bucket`, `BucketMetadata`,
  `BucketCreate`, `BucketUpdate`, `BucketTable`, `BucketTableCreate`, and
  `BucketTableUpdate`, the `Codable` payloads the data source sends and
  receives.
- **`BucketsTopic`** (`BucketsTopic.swift`) — the `EcosystemTopicProvider`
  that renders this domain into the Hub's rail/detail (HTDV) navigation:
  a bucket list, each bucket's Settings and Tables panes, and the create/
  edit/delete forms for both buckets and tables. `BucketsTopic` builds on
  the HTDV navigation and Forms types (`HTDVLevel`, `HTDVChild`, `FormSpec`,
  `FormState`, and the rest) documented in the related HTDV Engine recipe;
  those types are not redescribed here.

`FormSheet`, `FormDetails`, `RailPath`, `HubError`, `EcosystemTopicProvider`,
`EcosystemRail`, and `Ecosystem` are Hub-wide helpers `BucketsTopic` is built
on but that are not among this recipe's three given sources; they are
described here only to the extent needed to state what `BucketsTopic` itself
does with them.

## Behavioral Requirements

### BucketsDataSource.swift — server data-access contract

- **data-source-contract**: `BucketsDataSource` MUST be a `Sendable`,
  `AnyObject`-constrained protocol declaring nine `async throws` operations:
  `list(ecosystemID:)`, `get(id:)`, `create(_:)`, `update(id:_:)`,
  `delete(id:)`, `tables(ecosystemID:)`, `createTable(_:)`,
  `updateTable(id:_:)`, and `deleteTable(id:)`.
- **list-is-ecosystem-scoped**: `list(ecosystemID:)` MUST return only the
  buckets belonging to the given ecosystem, per the source's own comment
  "Lists are ecosystem-scoped."
- **tables-spans-every-bucket-in-the-ecosystem**: `tables(ecosystemID:)`
  MUST return every table of every bucket in the given ecosystem in a
  single call; per the source's own comment, the topic itself is
  responsible for grouping the result "by `bucketId`" rather than the data
  source filtering per bucket.
- **data-source-is-class-bound**: `BucketsDataSource` MUST be constrained
  to `AnyObject`, so an implementation is a class or actor, never a value
  type; per the source's own comment on the concrete equivalent in the
  HTDV Engine recipe's `HTDVDataSource`, such implementations are typically
  actors or `@unchecked Sendable` classes wrapping a network client — none
  of which is among this recipe's three given sources.

### BucketsModels.swift — data shapes

- **bucket-metadata-shape**: `BucketMetadata` MUST be a `Codable`,
  `Hashable`, `Sendable` struct exposing a single optional `description:
  String?`, defaulting to `nil`.
- **bucket-shape**: `Bucket` MUST be a `Codable`, `Hashable`, `Sendable`,
  `Identifiable` struct exposing `id: String`, `ecosystemId: String`,
  `name: String`, `kind: String`, `metadata: BucketMetadata?`,
  `createdAt: String?`, and `updatedAt: String?`.
- **bucket-decoding-tolerates-missing-kind-and-optionals**: `Bucket.init(from:)`
  MUST decode `kind` via `decodeIfPresent` defaulting to the literal
  `"custom"` when the key is absent, and MUST decode `metadata`,
  `createdAt`, and `updatedAt` via `decodeIfPresent` defaulting each to
  `nil`, so a payload that omits any of these four keys decodes
  successfully rather than throwing.
- **bucket-description-derivation**: `Bucket.description` MUST return
  `metadata?.description ?? ""`, collapsing both an absent `metadata` and a
  present `metadata` with a `nil` `description` into the empty string.
- **bucket-is-built-in-derivation**: `Bucket.isBuiltIn` MUST be `true` if
  and only if `kind != "custom"`; any `kind` value other than the literal
  `"custom"` — not only a specific enumerated set — is treated as built-in.
- **bucket-create-requires-metadata**: `BucketCreate` MUST be a `Codable`,
  `Hashable`, `Sendable` struct exposing `ecosystemId: String`,
  `name: String`, and a non-optional `metadata: BucketMetadata` — unlike
  `Bucket.metadata`, a create payload always carries a metadata value
  (possibly one whose own `description` is `nil`).
- **bucket-update-is-a-partial-patch**: `BucketUpdate` MUST be a
  `Codable`, `Hashable`, `Sendable` struct exposing `name: String?` and
  `metadata: BucketMetadata?`, both defaulting to `nil`, so an update
  payload can carry either field independently of the other.
- **bucket-table-shape**: `BucketTable` MUST be a `Codable`, `Hashable`,
  `Sendable`, `Identifiable` struct exposing four non-optional fields:
  `id: String`, `bucketId: String`, `sqlTableName: String`, and
  `name: String`, with no custom decoding — every field MUST be present in
  the payload.
- **bucket-table-create-shape**: `BucketTableCreate` MUST be a `Codable`,
  `Hashable`, `Sendable` struct exposing `ecosystemId: String`,
  `bucketId: String`, `sqlTableName: String`, and `name: String`, all
  non-optional.
- **bucket-table-update-has-no-sql-name-field**: `BucketTableUpdate` MUST
  be a `Codable`, `Hashable`, `Sendable` struct exposing only
  `name: String?`, defaulting to `nil`; it exposes no field for
  `sqlTableName`, so a table's SQL identifier cannot be changed through
  this payload once the table exists.

