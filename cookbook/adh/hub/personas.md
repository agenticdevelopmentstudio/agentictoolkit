---
id: 4af83bb1-0178-462a-b0fc-ae009b63133f
title: Personas
domain: agentictoolkit://cookbook/adh/hub/personas
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The Personas domain: persona records and their facet-by-facet editing rail,
  demo-chat eligibility and preview, chat-status resolution, tool/may-act/approval
  grants, and special-interest research corpora.'
platforms:
- swift
- macos
- ios
- typescript
- web
tags:
- hub
- personas
- data-source
- forms
- chat-demo
- access-control
depends-on: []
related:
- agentictoolkit://cookbook/ui/navigation/htdv
references:
- packages/apple/AgenticToolkit/Hub/Features/Personas/PersonasDataSource.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Personas/PersonasModels.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Personas/PersonasModule.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/HubError.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Support/HubText.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Support/RailPath.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Support/Slug.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Support/JSONValue.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Support/FormDetails.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitHubTests/PersonasModuleTests.swift (agentictoolkit)
- packages/web/packages/data/src/personas/personas.ts (agentictoolkit)
- packages/web/packages/data/src/personas/wire.ts (agentictoolkit)
- packages/web/packages/data/src/personas/fields.ts (agentictoolkit)
- packages/web/packages/data/src/personas/canned.ts (agentictoolkit)
- packages/web/packages/data/src/personas/chat-status.ts (agentictoolkit)
- packages/web/packages/data/src/personas/demo-preview.ts (agentictoolkit)
- packages/web/packages/data/src/personas/special-interests.ts (agentictoolkit)
- packages/web/packages/data/src/personas/interest-documents.ts (agentictoolkit)
- packages/web/packages/data/src/personas/persona-abilities.ts (agentictoolkit)
- packages/web/packages/data/src/personas/persona-user-tools.ts (agentictoolkit)
- packages/web/packages/data/src/personas/__tests__/canned.test.ts (agentictoolkit)
- packages/web/packages/data/src/personas/__tests__/chat-status.test.ts (agentictoolkit)
- packages/web/packages/data/src/personas/__tests__/demo-preview.test.ts (agentictoolkit)
- packages/web/packages/data/src/personas/__tests__/fields.test.ts (agentictoolkit)
- packages/web/packages/data/src/personas/__tests__/personas.test.ts (agentictoolkit)
- packages/web/packages/data/src/personas/__tests__/special-interests.test.ts (agentictoolkit)
- agenticdevelopercookbook://guidelines/behavioral-requirements
- agenticdevelopercookbook://guidelines/completeness
- agenticdevelopercookbook://guidelines/cookbook-compliance
- agenticdevelopercookbook://guidelines/cross-recipe-consistency
- agenticdevelopercookbook://guidelines/source-fidelity
- agenticdevelopercookbook://guidelines/template-conformance
approved-by: ""
approved-date: ""
---

# Personas

## Overview

The Personas domain has two given implementations of one contract. On Apple, a navigation data
source drives a list-of-personas root level, a fixed 13-item facet rail per persona, and one form
per facet, backed by a persona data source contract the app repo implements over its own API
client. On the web, a family of hand-written clients covers a much larger surface: persona CRUD
and services, the demo-chat eligibility predicate and preview endpoint, the chat-status
word/glyph resolver, owner-level tool/may-act/approval grants, per-user tool consent, and the
special-interests research-corpus clients. Both sides agree that a persona is edited
facet-by-facet but sent as one whole payload on every update, and that everything past the core
CRUD + services surface — abilities, may-act, chat status, demo chat, special interests — is
either not yet wired into the Apple facet rail (only 5 of the 13 declared facets are currently
supported) or has no Apple client at all in the given sources.

## Behavioral Requirements

### Data shapes

- **persona-data-source-protocol**: the persona data source contract MUST expose operations to
  list personas, get one by id, create, update, delete, and list available services.
- **persona-value-shape**: a persona record MUST carry every field of a persona row: `id`, `slug`,
  `name`, `description`, `visibility`, `model`, `serviceId`, `appId`, `avatarAttachmentId`,
  `modelPrompt`, `voice`, `character`, `examples`, `cannedChat` (opaque JSON), `chatStatus` (opaque
  JSON), `createdAt`, `updatedAt`, `ownedEcosystemId`, `corpusEcosystemId`.
- **persona-body-projection**: deriving a persona's create/update payload from its full record
  MUST use exactly `slug, name, description, modelPrompt, voice, character, examples,
  avatarAttachmentId, serviceId, model, visibility, cannedChat, chatStatus` — the same fields both
  implementations send — and MUST exclude the server-owned fields `id`, `createdAt`, `updatedAt`,
  `ownedEcosystemId`, `corpusEcosystemId`.
- **persona-decode-tolerates-unknown-fields**: decoding a persona record from a payload that
  carries fields the record does not declare (e.g. `userId`, `ownerKind`, `ownerId`) MUST succeed
  and MUST silently drop those fields — a deliberate, lossy projection onto the subset this domain
  needs, not a decoding failure.
- **persona-service-shape**: a persona service record MUST carry `id`, `name`, `providerKind`,
  `baseUrl`, `connectStatus`, and a list of service-model records; a service-model record MUST
  carry `id` and an optional `displayName`.
- **canned-chat-and-chat-status-are-opaque-json**: a persona's `cannedChat` and `chatStatus`
  fields MUST be treated as opaque JSON values whose equality comparison treats an integer and an
  equal-valued floating-point number as the same value, so round-tripped data is never seen as
  changed when it is not. One implementation MAY pass this tree through untouched, without
  parsing, validating, or resolving its shape (see Chat status resolution below, which does parse
  and resolve it on another implementation) — the two need not share an internal representation.

### Facet navigation

- **personas-root-level-lists-personas**: the root level MUST list every persona as one navigation
  item per persona (label = name, sublabel = slug, an icon suggesting a person) under a navigation
  level with id `"personas"`, title `"Personas"`, empty message `"No personas yet."`, and a create
  action titled `"New Persona"` that opens the persona-creation form.
- **personas-root-level-wraps-errors**: the root-level listing MUST wrap and rethrow any error
  from the underlying list operation as a wrapped domain error.
- **persona-child-resolves-by-id**: resolving a persona's child content MUST read the first path
  segment as a persona id and MUST return an empty result when no id is present.
- **persona-child-notfound-is-empty**: resolving a persona's child content MUST treat a not-found
  error from the get-by-id operation as an empty result rather than propagate it; every other
  error MUST be wrapped and rethrown.
- **persona-topics-rail-order**: with only a persona id in the path, resolving its child content
  MUST return a facet-rail level whose items are exactly the 13 declared facets, in the fixed
  order `identity, description, personality, purpose, project, knowledge, memory, abilities,
  permissions, access, demo, chatStatus, llm`, each leading to a detail form.
- **llm-facet-fetches-services**: resolving child content MUST fetch the list of available
  services only when the resolved facet id is `"llm"`; for every other facet it MUST pass an
  empty services list without fetching.
- **unsupported-facets-show-notice**: for a facet id outside the currently supported set
  (`project, knowledge, memory, abilities, permissions, access, demo, chatStatus` — 8 of the 13
  declared facets), resolving child content MUST return a detail form whose sole value, keyed
  `"notice"`, is exactly the fixed unavailable-facet message, and the facet's form specification
  MUST be absent for that facet id.
- **create-spec-defaults**: the persona-creation form MUST offer required `name` and `slug` fields
  (`slug` pattern-validated against the slug pattern), plus optional `description` and
  `modelPrompt` fields; on save it MUST build a persona payload from the entered
  `name`/`slug`/`modelPrompt`, MUST map `description` through the blank-to-nothing helper, and
  MUST hardcode `model: ""` and `visibility: "private"` regardless of any other input.
- **identity-facet-fields**: the `"identity"` facet MUST edit exactly `name` (required), `slug`
  (required, pattern-validated against the slug pattern, with the pattern's own
  validation-failure message), and `visibility` (required select over exactly `public`, `hub`,
  `private`); it MUST offer a delete action titled `"Delete persona"` whose confirmation text is
  exactly `Delete persona "<name>"? This cannot be undone.`
- **description-facet-fields**: the `"description"` facet MUST edit exactly one optional
  `description` textarea, mapped through the blank-to-nothing helper on save.
- **personality-facet-fields**: the `"personality"` facet MUST edit exactly `character`, `voice`,
  and `examples` (all optional textareas), each mapped through the blank-to-nothing helper on
  save.
- **purpose-facet-fields**: the `"purpose"` facet MUST edit exactly one optional markdown field
  keyed `modelPrompt`, and on save MUST assign the entered value directly, defaulting to `""`
  when absent (it does not route through the blank-to-nothing helper).
- **llm-facet-service-model-options**: the `"llm"` facet's `serviceId` select MUST offer `"No
  service"` plus one option per available service; its `model` select MUST offer `"Pick a service
  first"` when no service is selected or `"No model selected"` when one is, plus one option per
  that service's models (falling back to the model's own id when its display name is absent).
- **llm-facet-clears-invalid-model**: on save, the `"llm"` facet MUST clear the `model` value to
  nothing whenever the resolved `serviceId` is absent or the chosen service's models do not
  contain a model with that id — it MUST NOT persist a `model` the selected service does not
  actually offer.
- **facet-save-composes-full-body**: every facet's save action MUST start from the persona's full
  current payload, apply only that facet's edits, and send the entire composed payload as an
  update — fields the facet does not touch MUST ride along unchanged.
- **unknown-path-is-empty**: resolving child content MUST return an empty result for an empty
  path, for a path whose first item's id matches no persona, and for a path whose second item's
  id matches no declared facet.

### CRUD and rename semantics

- **personas-list-scoped-by-workspace**: the list operation MUST forward an optional `workspace`
  slug as a query parameter; when supplied, the result MUST be scoped to that workspace's owning
  principal rather than the caller's own creator-scoped rows.
- **persona-update-is-the-rename**: the update operation MUST send the full persona payload
  (including `slug`) on every update; a changed `slug` IS the rename — the server derives the new
  rdid and cascades it onto the handle and every descendant, and callers MUST read the new `id`
  from the echoed response rather than compute one client-side.
- **persona-by-slug-owner-lookup**: looking a persona up by slug as its owner MUST query with an
  equality filter on `slug`, take the first matching row, and MUST throw a not-found error when no
  row is returned.
- **persona-draft-narrows-visibility**: converting a persona into an editable draft MUST narrow its
  loosely-typed `visibility` string to exactly `"public" | "hub" | "private"`, defaulting any
  other stored value to `"private"`.
- **persona-fields-single-source-of-truth**: a single field table MUST describe every draft key
  exactly once, enforced by an exhaustiveness check, and deriving a blank draft or a create/update
  payload MUST derive solely from that table.
- **persona-to-body-wire-strategies**: converting a draft to a create/update payload MUST apply
  exactly the wire strategy each field declares: `"omit"` fields (e.g. `id`, `serviceName`) MUST
  NOT appear in the payload; `"trimRequired"` fields MUST be trimmed and default to `""` when
  absent; `"trimOptional"` fields MUST be trimmed and omitted entirely (never sent as `""`) when
  blank; `"raw"` fields MUST pass through untrimmed and unfiltered.
- **persona-blank-chat-status-is-independent-copy**: a blank draft MUST give `chatStatus` its own
  deep copy of the blank chat-status value, not a shared reference, so mutating one draft's rows
  MUST NOT affect another draft's.

### Demo-chat eligibility and preview

- **can-demo-chat-requires-enabled-and-line**: the demo-eligibility check MUST return `true` only
  for a well-formed object with `enabled === true`, a parsing `pacing` block (or none), and at
  least one of the keyword script or the ink script both parsing AND having a line it can actually
  say; it MUST return `false` for any other input, including non-objects, `null`, and `undefined`.
- **can-demo-chat-never-compiles-ink**: the ink check MUST test only for a non-blank `source`
  string (and an optional string `signInLine`) and MUST NOT compile or otherwise validate the ink
  script's syntax — a script with a syntax error still counts as demoable.
- **can-demo-chat-malformed-sinks-whole-config**: when either the keyword script or the ink slice
  is present but malformed, the demo-eligibility check MUST return `false` even if the other
  engine would otherwise qualify.
- **demo-preview-is-server-side-only**: the client MUST NOT implement ink replay, keyword
  matching, or escalation logic itself; the demo-preview operation MUST send the draft `source`
  and optional `signInLine`/`message`/`history`/`canEscalate` to `POST /api/persona/demo-preview`
  and MUST render only what the server returns.
- **demo-preview-history-cap-not-truncated**: callers MUST NOT truncate a `history` longer than
  the maximum preview-history length (twice the maximum preview turns = 80 entries) before
  sending — the server rejects an over-length history with a 400 rather than accepting a
  truncated one, since truncating would silently replay a different point in the script.
- **demo-preview-omitted-message-lints-and-plays-opening**: calling the demo-preview operation
  with no `message` and no `history` MUST be treated as "lint the draft and show its opening,"
  using the same call path the editor's compile check and the visitor's first turn both use.

### Chat status resolution

- **parse-chat-status-drops-not-substitutes**: parsing a chat-status configuration MUST drop a
  malformed `words` or `icons` entry rather than substituting the built-in default, and MUST
  return an empty list (not the default rows) when the author has deliberately emptied that list;
  only a `null` or non-object raw input MUST fall back to the blank chat-status value.
- **parse-chat-status-draft-preserves-incomplete-rows**: parsing a chat-status configuration for
  editing MUST preserve a half-written word pair (one of `present`/`past` blank) and an icon set
  with zero frames, and MUST NOT trim text or drop empty tags — unlike the non-editing parse,
  which drops both.
- **resolve-chat-status-words-union-icons-exclusive**: resolving a chat-status configuration for a
  given kind MUST resolve `words` as the union of rows tagged with the requested kind and untagged
  rows, but MUST resolve `icons` as the first matching set only (tagged-for-kind, else untagged,
  else the built-in fallback). This asymmetry is deliberate and MUST NOT be changed to make icons
  union the way words do.
- **resolve-chat-status-never-throws**: resolving a chat-status configuration MUST NOT throw for
  any input, including non-object raw values, and MUST always return at least one word and one
  non-empty frame set via the fallback chain through the blank chat-status value.

### Ability, may-act, and approval grants

- **persona-approvals-server-narrows-by-persona**: listing approval requests MUST forward an
  optional `personaId` filter to the server and MUST NOT re-filter the response client-side.
- **persona-may-act-grant-kind-parameterized**: granting or revoking may-act permission MUST
  accept a `kind` of `"user"` or `"team"` and MUST route through the single kind-parameterized
  endpoint.
- **persona-tools-set-autonomy-is-per-tool**: setting a tool's autonomy MUST update a single named
  tool's `autonomous` flag and MUST leave every other granted tool's autonomy untouched.
- **persona-user-tools-is-layer-two-consent**: setting a user's allowed tools MUST replace the
  calling user's full allow-list for one persona's owner-granted tools in a single write; this
  consent layer is distinct from, and downstream of, the owner-level grants managed separately.

### Special interests and interest documents

- **special-interests-list-must-filter-by-persona**: listing special interests MUST always pass
  `personaId` as a query filter; omitting it would return every special interest the caller owns
  across all of their personas, not just this one.
- **special-interest-update-strips-immutable-fields**: updating a special interest MUST strip
  `personaId` and `bucketId` from the patch body before sending, even when the caller supplies
  them, since the server treats a `personaId` change as a 400 and always assigns `bucketId`
  itself.
- **interest-documents-act-as-persona**: every interest-document operation MUST include
  `?asType=persona&asId=<personaId>`, since the research-corpus bucket's access grant is held by
  the persona, not the calling user.
- **interest-documents-list-unpaginated**: listing interest documents MUST NOT send
  `limit`/`offset`; callers MUST understand this returns only the server-capped first page (500
  rows) of an interest's document corpus.
- **interest-documents-response-envelope-differs-by-verb**: listing interest documents MUST
  unwrap a `{ rows }` envelope, while creating/updating MUST treat the response as a bare row —
  the two shapes MUST NOT be assumed interchangeable.

## Appearance

Not applicable — this is a data-access and navigation-orchestration component, not a visual
component.

## States

Not applicable — this is a data-access and navigation-orchestration component, not a visual
component.

## Accessibility

Not applicable — this is a data-access and navigation-orchestration component, not a visual
component.

## Conformance Test Vectors

| Input | Expected output / effect | Traced to |
|-------|---------------------------|-----------|
| Listing the root level with personas Ada and Bob present | A navigation level whose items are labeled "Ada" and "Bob", subtitled "ada" and "bob", with empty message "No personas yet." and a create action titled "New Persona" | `testRootLevelListsPersonas` |
| Resolving child content for a path naming persona Ada | A facet-rail level with id `"persona-topics"`, title `"Ada"`, item ids exactly `identity, description, personality, purpose, project, knowledge, memory, abilities, permissions, access, demo, chatStatus, llm` | `testPersonaChildIsFacetRail` |
| Identity form: set `name` to `"Ada Lovelace"`, `visibility` to `"hub"`, save | The resulting update payload has `name == "Ada Lovelace"`, `visibility == "hub"`, `modelPrompt == "You are Ada."` (untouched, rides along) | `testIdentityFormValuesAndSave` |
| Identity slug field validated against `"Bad Slug"` | Validation fails with the slug pattern's own message | `testIdentityFormValidatesSlug` |
| Delete action performed on Ada's identity facet | The delete action's confirmation text reads exactly `Delete persona "Ada"? This cannot be undone.`; the delete request names persona `"persona.me.ada"` | `testIdentityDeleteAction` |
| Personality form: `voice = "   "`, `character = "Curious"`, save | The saved payload has `voice` absent and `character == "Curious"` | `testBlankTextBecomesNilOnSave` |
| LLM form: clear `serviceId` to `""`, save | The saved payload has `serviceId` and `model` both absent | `testLLMSaveClearsModelWhenServiceHasNoSuchModel` |
| Resolving child content for each of the 8 unsupported facet ids | The detail form's sole value, keyed `"notice"`, equals `"Not available in this version"`; no form specification exists for that facet | `testUnsupportedFacetsShowNotice` |
| Performing the persona-creation form's save action with `name: "Bob"`, `slug: "bob"`, empty `description`, and `modelPrompt: "You are Bob."` | The resulting create payload has `description` absent, `model == ""`, and `visibility == "private"` | `testCreateSpecAndPerform` |
| Decode a persona payload with extra fields `userId`/`ownerKind`/`ownerId` | Decode succeeds; the resulting record's `name == "Ada"`, the unknown fields are dropped, and `cannedChat` decodes to the opaque JSON object `{"mode": "script", "turns": []}` | `testPersonaDecodesFromWebJSON` |
| The demo-eligibility check, given `{ enabled: true, ink: { source: "* [unclosed\n", signInLine: "x" } }` | `true` — a syntax error in the ink script still advertises a demo | canned.test.ts, "does not compile the ink — a syntax error still advertises a demo" |
| The demo-eligibility check, given a well-formed but disabled config, and separately given `null` | both `false` | canned.test.ts, "is false for a parked script and for no config at all" |
| Parsing a chat-status configuration given `{ words: 7 }` | `{ words: [], icons: [] }` — malformed field dropped to an empty list, not substituted with the default | chat-status.test.ts, "drops a malformed words/icons field to an empty list rather than substituting the default" |
| Resolving a chat-status configuration for kind `"search"`, where the configuration has one word pair tagged `"search"` plus untagged defaults | `words` is the UNION of the tagged and untagged rows; `frames` resolves to the first matching icon set only | chat-status.test.ts, "unions rows tagged with the kind with untagged rows that fit anything" |

## Edge Cases

- An empty persona list renders the root level's empty message, `"No personas yet."`, rather than
  an empty items array with no explanation.
- A facet id present in the facet rail but outside the currently supported set (8 of the 13
  declared facets) MUST resolve to the fixed unavailable-facet notice, never to a broken or
  partially-rendered form.
- A path whose facet id matches nothing in the declared facet set (not merely an unsupported id,
  but an unknown one) MUST resolve to an empty result the same way an unknown persona id does.
- Every blank optional text field on a facet save (`description`, `character`, `voice`,
  `examples`) is mapped to absent through the blank-to-nothing helper, never persisted as `""`.
- Selecting the `"llm"` facet's `model` for a service that does not actually offer that model id
  (stale selection, or the service was switched) MUST clear `model` to absent on save rather than
  persist a mismatched pair.
- Any failure from the underlying data source (e.g. offline) on the root-level listing,
  child-content resolution, create, save, or delete MUST propagate as a wrapped domain error,
  never be swallowed.
- The demo-eligibility check treats a raw config that is not an object at all (`"not even an
  object"`) the same as one that is well-formed but switched off: `false`, with no thrown error.
- Listing interest documents on a corpus with more than 500 documents silently returns only the
  first (oldest-id-first) 500; the caller receives no signal that more documents exist.
- The demo-preview operation called with a `history` longer than the maximum preview-history
  length is rejected by the server with a 400; this client sends the caller's history as given and
  applies no truncation of its own.
- Updating a special interest given a patch that includes `personaId` or `bucketId` silently drops
  both from the outgoing request rather than sending (and having the server reject) them.

## Configuration

- `dataSource`: the persona data source implementation injected into this domain's navigation
  contract — supplied by the host application, typically backed by its own API client.
- `workspace` (optional, on list/create/update/delete): a workspace slug that scopes the operation
  to that workspace's owning principal instead of the caller's own rows.
- `personaId` / `bucketId` / `typeId` / `rowId`: caller-supplied identifiers threading through the
  interest-documents, special-interests, approvals, may-act, tools, and user-tools operations to
  select which persona's records or grants are being read or changed.
- `kind` (`"user" | "team"` for may-act; `"user" | "team" | "org"` on the wire body): which
  context a persona is granted or denied leave to act under.
- `status` (approvals listing, default `"pending"`): which approval queue state to list.
- Demo-preview payload fields — `source`, `signInLine`, `message`, `history`, `canEscalate` — all
  caller-supplied inputs to one preview call; `canEscalate` selects which visitor's demo (signed-in
  vs. anonymous) is being previewed.
- Each field's wire strategy (`trimRequired` / `trimOptional` / `raw` / `omit`) is compiled into
  the draft-to-payload conversion and is not caller-configurable at runtime.

## Deep Linking

Not applicable: none of the given implementations register a URL scheme, universal link, or
deep-link route; navigation is entirely through the facet-rail hierarchy on one implementation and
direct API calls on the other, neither of which registers a URL.

## Localization

The given implementations hardcode English user-facing strings rather than localizing them:

- Error messages — `"You need to sign in again."`, `"You don't have permission to do that."`,
  `"That item no longer exists."`, `"The hub can't be reached right now."`, and the templated
  `"Connection problem: <detail>"` / `"Something went wrong: <detail>"`.
- The unavailable-facet notice — `"Not available in this version"`, shown for every unsupported
  facet.
- The slug pattern's validation message — `"Use lowercase letters, numbers and hyphens."`
- The facet rail's field labels, placeholders, and confirmation text (e.g. `"New Persona"`,
  `"Delete persona"`, `Delete persona "<name>"? This cannot be undone.`, and field placeholders
  such as `"Bob"`, `"bob"`, `"A one-line summary of this persona."`) are all English literals with
  no localization mechanism in these implementations.
- The demo-preview, chat-status, and demo-eligibility logic carries no user-facing strings of its
  own — its outputs are rendered by a presentation layer this recipe does not own — except the
  built-in chat-status word presets' English word pairs (`"thinking"`, `"responding"`, etc.),
  which are persisted author-facing content, not chrome.

## Accessibility Options

Not applicable — this is a data-access and navigation-orchestration component; the given
implementations expose no accessibility-options surface of their own (icon names such as a
"person" glyph are cosmetic hints consumed by a presentation layer this recipe does not own).

## Feature Flags

Not applicable: none of the given implementations read a runtime feature flag or remote-config
value. The set of currently supported facets gates which of the 13 declared facets are editable,
but it is a fixed, compiled-in set, not a runtime flag.

## Analytics

Not applicable: none of the given implementations call an analytics or telemetry client.

## Privacy

Not applicable: the given implementations delegate network transport, authentication, and
credential storage to the host application's own API client and to the web implementation's
shared authenticated request helpers; no given implementation reads, stores, or transmits a
credential directly. The persona content these implementations do carry — name, description,
character, voice, model prompt, demo-chat script, special interests — is user-authored feature
data handled as an opaque payload, with no additional PII classification, redaction, or retention
logic applied by this component itself.

## Logging

Not applicable: none of the given implementations call a logger or any platform logging API —
confirmed by inspection of every given source file in this domain.

## Platform Notes

- **SwiftUI / AppKit / UIKit (Apple, already implemented)**: `PersonasModule` is a `@MainActor
  final class` conforming to `HTDVDataSource` — the navigation data source contract described
  neutrally above resolves here to `rootLevel()`/`child(for:)` returning `.level`/`.detail`/
  `.empty` cases, driving `FormSpec`/`FormSheet`/`FormViewController` from `AgenticToolkitHTDV`
  (see `agentictoolkit://cookbook/ui/navigation/htdv`); shared Hub support types (`HubError`,
  `HubText`, `RailPath`, `Slug`, `JSONValue`, `FormDetails`) are reused rather than reimplemented
  per feature. `PersonasDataSource` is `Sendable` and exposes `list()`, `get(id:)`, `create(_:)`,
  `update(id:_:)`, `delete(id:)`, and `listServices()`, all `async throws`; the app repo
  implements it over `HubAPI`. `Persona`/`PersonaService`/`PersonaServiceModel` are `Codable,
  Sendable, Equatable, Identifiable` structs. `Persona.cannedChat`/`.chatStatus` are typed as the
  Hub `JSONValue` (hand-written `Decodable`, `==`/`hash(into:)` that treats `.int` and `.number`
  as the same JSON number) — not the unrelated, simpler `JSONValue` under `Sync/`. Errors from the
  data source are wrapped as `HubError.wrap(error)`.
- **React / TypeScript (web, already implemented)**: the client family under
  `packages/web/packages/data/src/personas/` is the wider of the two implementations — it covers
  services, provider templates, tool/may-act/approval grants, per-user tool consent, special
  interests, interest-document corpora, and demo preview, none of which the Apple side's given
  sources implement yet.
- **Jetpack Compose / Kotlin (Android, port target)**: the rootLevel→facet-rail→form navigation
  has no existing implementation to port from directly; a Compose port would mirror
  `HTDVDataSource`'s `rootLevel()`/`child(for:)` shape with a `ViewModel` exposing `StateFlow`
  screens, `kotlinx.serialization`-annotated `Persona`/`PersonaBody` data classes matching the
  wire field names, and a `sealed class` (or the `CHAT_STATUS_KINDS`-style string literal set) for
  facet ids so an unhandled facet fails to compile rather than silently falling through.
- **WinUI 3 / .NET (Windows, port target)**: a `Persona`/`PersonaBody` record pair serialized with
  `System.Text.Json.JsonSerializer` and `[JsonPropertyName]` attributes matching the wire field
  names; the facet rail as an `ObservableCollection<PersonaFacet>` bound to a
  `Microsoft.UI.Xaml.Controls.NavigationView` (or `TreeView`) for the two-level rail; the llm
  facet's service/model pickers as `Microsoft.UI.Xaml.Controls.ComboBox` bound to the same
  `serviceOptions`/`modelOptions` derivation `llmSpec` computes; and `DispatcherQueue.TryEnqueue`
  (or a `[MainThread]`-equivalent dispatcher) to keep persona mutation on the UI thread the way
  `@MainActor` does on Apple.
- **Cross-platform (backend contract, applies to every port)**: `canDemoChat`, `parseChatStatus`
  /`resolveChatStatus`, and `demoPreviewApi` are deliberately duplicated logic that must agree
  with the backend's authoritative implementation (`backend/src/adh/src/llm/canned/config.ts`,
  `backend/src/adh/src/db/schema/persona.ts`, `docs/planning/demo-chat-ink-engine.md §10`); any
  port MUST keep its copy in lockstep with the backend rather than treating this recipe's
  TypeScript as the source of truth — "when they disagree, the backend wins," per `wire.ts`'s own
  comment.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/data/src/personas/` |
| apple | `packages/apple/AgenticToolkit/Hub/Features/Personas/` |

## Design Decisions

**Decision**: `Persona.cannedChat`/`.chatStatus` are typed as the Hub `JSONValue` (with
hand-written `Decodable`, cross-`.int`/`.number` equality, and `hash(into:)`), not the simpler,
unrelated `JSONValue` under `Sync/`.
**Rationale**: the Hub variant's hand-written equality treats an integer JSON number and a
floating-point JSON number as the same value — a documented past-bug fix for round-tripping data
that a naive synthesized `Equatable` would treat as changed when it was not. Passing the tree
through opaquely (rather than decoding it into `CannedChatConfig`/`ChatStatusConfig` structs, as
the web does) avoids maintaining a second, potentially-diverging strongly-typed mirror on the
Apple side for data this module never reads.
**Approved**: pending
**Applies to**: Apple/Swift — this decision concerns this platform's own `JSONValue`
implementation choice and equality semantics; a port only needs to preserve the observable
behavior (opaque pass-through, with numeric-type-tolerant equality if it implements equality at
all).

**Decision**: `PersonasModule.supportedFacetIDs` implements only 5 of the 13 facets declared in
`PersonasModule.facets`; the other 8 render a fixed "not available in this version" notice
instead of a form.
**Rationale**: the rail's shape (list-then-facets) is stable and worth shipping ahead of every
facet's editor being ready; showing the full rail with an honest notice on unfinished facets
avoids either hiding the facet's existence or exposing a half-built form.
**Approved**: pending
**Applies to**: Apple — describes the Apple facet rail's current rollout state; a port's own
facet coverage is a separate rollout decision.

**Decision**: `resolveChatStatus` resolves `words` as a union (tagged rows plus untagged rows)
but resolves `icons` exclusively (first matching set only), even though both fields resolve
through the same fallback-chain shape.
**Rationale**: the source's own comments record that an earlier exclusive-only word chain drew
from a one-element list forever once a kind was tagged, so words changed to union; icons stayed
exclusive because a union there would let an untagged glyph set interleave frame-by-frame with a
tagged one — exactly the continuity break the glyph exists to avoid. The asymmetry is a documented
fix on one side and a documented constraint on the other, not an oversight.
**Approved**: pending

**Decision**: `api.personas.update` always sends the full `PersonaBody` including `slug`, and a
changed `slug` IS how a persona is renamed — there is no separate rename endpoint, and the former
follow-up `identifiersApi.rename` call (and its 404-recovery branch) has been removed.
**Rationale**: the source's comment records that the follow-up rename was a SECOND rename of a
handle the update's own cascade had already moved, landing on a now-taken target and reporting a
successful rename as a 409 failure; a single call has no such half-landed window to recover from.
**Approved**: pending
**Applies to**: Web — this decision traces the web client's own evolution away from a
since-removed follow-up rename call; a port need only ensure its own persona-rename path is a
single atomic update, not two calls.

**Decision**: `InterestDocumentRow` declares every column of the backend's `content.markdown`
row (23 fields), not just the `id`/`title`/`content` this feature reads.
**Rationale**: the source's comment records that an earlier five-field fixture looked enough like
the wire to hide a real envelope bug; declaring the true shape (and true nullability) lets any
caller reaching for an undeclared field get an honest answer from the type rather than a
convenient subset that quietly diverges from what the server actually sends.
**Approved**: pending
**Applies to**: Web — this decision concerns this platform's own row-type declaration; a port
only needs to model the same true nullability of the corpus row, not this specific interface
name.

**Decision**: `canDemoChat`'s ink check tests only for a non-blank `source` string and never
compiles the ink script.
**Rationale**: there is no ink compiler on the client, and the backend's own `canClaim` also does
not compile the script before deciding a demo exists — keeping both sides at "does it have
something to say" rather than "does it compile" means a syntax error cannot make the two
implementations disagree about whether a persona demos at all.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [server-side-authorization](agenticdevelopercookbook://compliance/security#server-side-authorization) | passed | Security |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | partial | Access Patterns |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [pagination-support](agenticdevelopercookbook://compliance/access-patterns#pagination-support) | partial | Access Patterns |

`separation-of-concerns` passes: `PersonasDataSource`/`PersonasModels` hold no UI code and
`PersonasModule` holds no transport code (it depends on the injected data source); the web's
`wire.ts`/`fields.ts`/`chat-status.ts`/`canned.ts` are pure data/logic modules with, per their own
top comments, zero React or network code. `unit-test-coverage` is `partial`: `PersonasModule` is
thoroughly covered by `PersonasModuleTests.swift`, and `canned.ts`/`chat-status.ts`/
`demo-preview.ts`/`fields.ts`/`personas.ts`/`special-interests.ts` each have a matching
`__tests__/*.test.ts` file — but `persona-abilities.ts`, `persona-user-tools.ts`, and `wire.ts`
have no dedicated test file in this checkout. `server-side-authorization` passes: every grant
surface (`personaMayActApi`, `personaToolsApi`, `personaUserToolsApi`, `personaApprovalsApi`)
defers the actual authorization decision to the server and the client contains no local
permission check; `interestDocumentsApi`'s act-as-persona header is likewise checked by the
server's bucket ACL, not the client. `error-response-handling` is `partial`: `PersonasModule`
documents and tests one specific case (`HubError.notFound` on `child(for:)` becomes `.empty`),
but every other failure — on both platforms — propagates as a generic wrapped/thrown error with
no further per-status-code handling in these sources. `graceful-degradation` passes: unsupported
facets render a documented, tested notice (`FormDetails.unavailableMessage`) rather than a broken
form or a crash, and `canDemoChat`/`parseChatStatus`/`resolveChatStatus` are all documented as
never throwing on malformed input, degrading to `false`/empty/default instead. `pagination-support`
is `partial`: `api.templates` fetches one explicit, documented max-size page (`pageSize=100`),
but `interestDocumentsApi.list` sends no `limit`/`offset` at all and silently truncates any corpus
past the server's 500-row cap — a real caller of that client cannot see or page past 500 documents
with what these sources provide.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/hub/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
