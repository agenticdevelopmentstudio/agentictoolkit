<!-- leaf: implement-hub-domain-1/ecosystems · source: hub-domain-ecosystems.md -->

# Hub Domain: Ecosystems

## Overview

`hub-domain-ecosystems` is the Ecosystems ("Products") domain of the hub: the
non-UI logic that lists, creates, renames, and deletes an *ecosystem* — a
reverse-domain-identified (rdid) product row that can itself own child
ecosystems, and that other domains (applications, buckets, customers) hang
off of. It has two independent, source-of-truth implementations that this
recipe covers together because they model the identical contract from
opposite ends of one system:

- **Apple** (`packages/apple/AgenticToolkit/Hub/Features/Ecosystems/`, Swift,
  macOS + iOS): `EcosystemsDataSource` (the I/O protocol an app adapter
  implements over the real hub API), `Ecosystem`/`EcosystemCreate`/
  `EcosystemUpdate` (the models), `EcosystemsModule` (the top-level
  `HTDVDataSource` that lists products and resolves each product's topics
  rail), `EcosystemTopicProvider`/`EcosystemTopicGroup`/`EcosystemNoticeTopic`
  (the topic-composition framework from `EcosystemTopic.swift`),
  `EcosystemSettingsTopic` (the product's own record — name/slug/identifier/
  description, plus delete), and `ChildEcosystemsTopic` (an ecosystem's own
  child ecosystems, recursing back through the same rail).
- **Web** (`packages/web/packages/data/src/ecosystems/`, TypeScript):
  `ecosystemsApi` (`ecosystems.ts` — list/create/update/delete/resolve
  against `/api/ecosystem/ecosystems`), `identifiersApi` (`identifiers.ts` —
  rename-in-place and availability probe against
  `/api/registry/identifiers`), `useWorkspaceDefaultEcosystemId`
  (`use-workspace-default-ecosystem.ts` — the react-query resolver every
  workspace-scoped pane and create-dialog preview shares), the
  Invitations topic's react-query hooks (`ecosystem-invitations.ts`), and
  `ecosystemFeaturesApi` plus its react-query hooks
  (`ecosystem-features.ts` — the data behind the ecosystem feature picker:
  the catalog of addable features, including "Coming soon" unbuilt ones,
  what an ecosystem is provisioned with, adding a batch, and removing one,
  against the bespoke `/api/ecosystem/features` route). The feature picker
  has no Apple counterpart in these sources.

Both sides model the same backend fact: an ecosystem's public identity is a
*stored, mutable* rdid (`id` / `identifier`), but the row's *own* address is
*derived* from `(parent chain, slug)` — `slug` is the one field a create or a
rename actually supplies, and the two names for the same value can drift
(a handle renamed by the OTHER route, `identifiers.rename`/`registry.identifiers`
PATCH, leaves the slug column behind). Every behavior below that looks like
string manipulation (`identifierPrefix`, `addressLeaf`) exists to keep a
caller on the correct side of that distinction.

