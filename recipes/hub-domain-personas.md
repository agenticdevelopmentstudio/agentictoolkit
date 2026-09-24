---
id: 4af83bb1-0178-462a-b0fc-ae009b63133f
title: 'Hub Domain: Personas'
domain: agentictoolkit://recipes/hub-domain-personas
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The Hub''s Personas domain: an HTDV-driven Swift feature module (list, then a 13-facet
  rail, then per-facet forms, with 5 of 13 facets implemented) plus the TypeScript client for
  persona CRUD, demo-chat eligibility and preview, chat-status resolution, tool/may-act/approval
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
- htdv
- forms
- chat-demo
- access-control
depends-on: []
related:
- agentictoolkit://recipes/htdv-engine
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

## Overview

The Personas domain has two given implementations of one contract. On Apple, `PersonasModule`
is an `HTDVDataSource` that drives a list-of-personas root level, a fixed 13-item facet rail per
persona, and one form per facet, backed by a `PersonasDataSource` protocol the app repo
implements over `HubAPI`. On the web, a family of hand-written TypeScript clients under
`packages/web/packages/data/src/personas/` covers a much larger surface: persona CRUD and
services, the demo-chat eligibility predicate and preview endpoint, the chat-status
word/glyph resolver, owner-level tool/may-act/approval grants, per-user tool consent, and the
special-interests research-corpus clients. Both sides agree that a persona is edited
facet-by-facet but PUT as one whole `PersonaBody`, and that everything past the core CRUD +
services surface — abilities, may-act, chat status, demo chat, special interests — is either
not yet wired into the Apple facet rail (`supportedFacetIDs` implements only 5 of the 13
declared facets) or has no Apple client at all in the given sources.

## Behavioral Requirements

### Data shapes (Apple)

- **persona-data-source-protocol**: `PersonasDataSource` MUST be `Sendable` and MUST expose
  `list()`, `get(id:)`, `create(_:)`, `update(id:_:)`, `delete(id:)`, and `listServices()`, all
  `async throws`; the app repo implements it over `HubAPI`.
- **persona-value-shape**: `Persona` MUST be `Codable, Sendable, Equatable, Identifiable` and
  MUST carry every field of a `/persona/personas` row: `id`, `slug`, `name`, `description`,
  `visibility`, `model`, `serviceId`, `appId`, `avatarAttachmentId`, `modelPrompt`, `voice`,
  `character`, `examples`, `cannedChat` (a `JSONValue?`), `chatStatus` (a `JSONValue?`),
  `createdAt`, `updatedAt`, `ownedEcosystemId`, `corpusEcosystemId`.
- **persona-body-projection**: `Persona.body` MUST derive a `PersonaBody` (the create/update
  payload) from exactly `slug, name, description, modelPrompt, voice, character, examples,
  avatarAttachmentId, serviceId, model, visibility, cannedChat, chatStatus` — the same fields the
  web's `personaToBody` sends — and MUST exclude the server-owned fields `id`, `createdAt`,
  `updatedAt`, `ownedEcosystemId`, `corpusEcosystemId`.
- **persona-decode-tolerates-unknown-fields**: decoding a `Persona` from a payload that carries
  fields the struct does not declare (e.g. `userId`, `ownerKind`, `ownerId`) MUST succeed and
  MUST silently drop those fields — a deliberate, lossy projection onto the subset this module
  needs, not a decoding failure.
- **persona-service-shape**: `PersonaService` MUST carry `id`, `name`, `providerKind`, `baseUrl`,
  `connectStatus`, and `models: [PersonaServiceModel]`; `PersonaServiceModel` MUST carry `id` and
  an optional `displayName`.
- **canned-chat-and-chat-status-are-opaque-json**: `Persona.cannedChat` and `Persona.chatStatus`
  MUST be typed as the Hub `JSONValue` (the variant with hand-written `Decodable`,
  `==`/`hash(into:)` that treats `.int` and `.number` as the same JSON number, and
  `parse(_:) throws`) — not the unrelated, simpler `JSONValue` under `Sync/`. The Apple side MUST
  pass this tree through untouched; it MUST NOT parse, validate, or resolve its shape the way the
  web's `parseChatStatus`/`resolveChatStatus`/`canDemoChat` do.

### HTDV integration (Apple)

- **personas-root-level-lists-personas**: `rootLevel()` MUST list every persona from
  `dataSource.list()` as one `HTDVItem` per persona (`label` = name, `sublabel` = slug, glyph
  `person.crop.circle`) under an `HTDVLevel` with id `"personas"`, title `"Personas"`, empty
  message `"No personas yet."`, and a create action titled `"New Persona"` backed by
  `createSpec()`.
- **personas-root-level-wraps-errors**: `rootLevel()` MUST rethrow any error from
  `dataSource.list()` as `HubError.wrap(error)`.
- **persona-child-resolves-by-id**: `child(for:)` MUST resolve the first path segment as a
  persona id via `RailPath.id(at: 0, in:)` and MUST return `.empty` when no id is present.
- **persona-child-notfound-is-empty**: `child(for:)` MUST catch `HubError.notFound` from
  `dataSource.get(id:)` and return `.empty` rather than rethrow it; every other error MUST be
  rethrown as `HubError.wrap(error)`.
- **persona-topics-rail-order**: with only a persona id in the path, `child(for:)` MUST return a
  `.level` whose items are exactly the 13 declared facets, in the fixed order `identity,
  description, personality, purpose, project, knowledge, memory, abilities, permissions, access,
  demo, chatStatus, llm`, each with `leadsTo: .detail`.
- **llm-facet-fetches-services**: `child(for:)` MUST call `dataSource.listServices()` only when
  the resolved facet id is `"llm"`; for every other facet it MUST pass an empty `services` array
  without calling `listServices()`.
- **unsupported-facets-show-notice**: for a facet id outside `supportedFacetIDs` (`project,
  knowledge, memory, abilities, permissions, access, demo, chatStatus` — 8 of the 13 declared
  facets), `child(for:)` MUST return a `.detail` built by `FormDetails.notice(...)` whose form
  value for key `"notice"` is exactly `FormDetails.unavailableMessage`, and
  `facetSpec(_:persona:services:)` MUST return `nil` for that facet id.
- **create-spec-defaults**: `createSpec()` MUST offer required `name` and `slug` fields (`slug`
  pattern-validated against `Slug.pattern`), plus optional `description` and `modelPrompt`
  fields; on save it MUST build a `PersonaBody` from the entered `name`/`slug`/`modelPrompt`,
  MUST map `description` through `HubText.nonBlank` (blank becomes `nil`), and MUST hardcode
  `model: ""` and `visibility: "private"` regardless of any other input.
- **identity-facet-fields**: the `"identity"` facet MUST edit exactly `name` (required),
  `slug` (required, pattern-validated against `Slug.pattern`, with `Slug.patternMessage` as the
  validation-failure message), and `visibility` (required select over exactly `public`, `hub`,
  `private`); it MUST offer a delete action titled `"Delete persona"` whose confirmation text is
  exactly `Delete persona "<name>"? This cannot be undone.`
- **description-facet-fields**: the `"description"` facet MUST edit exactly one optional
  `description` textarea, mapped through `HubText.nonBlank` on save.
- **personality-facet-fields**: the `"personality"` facet MUST edit exactly `character`, `voice`,
  and `examples` (all optional textareas), each mapped through `HubText.nonBlank` on save.
- **purpose-facet-fields**: the `"purpose"` facet MUST edit exactly one optional markdown field
  keyed `modelPrompt`, and on save MUST assign the entered value directly, defaulting to `""`
  when absent (it does not route through `HubText.nonBlank`).
- **llm-facet-service-model-options**: the `"llm"` facet's `serviceId` select MUST offer `"No
  service"` plus one option per passed-in `PersonaService`; its `model` select MUST offer `"Pick
  a service first"` when no service is selected or `"No model selected"` when one is, plus one
  option per that service's `PersonaServiceModel` (falling back to the model's own id when
  `displayName` is `nil`).
- **llm-facet-clears-invalid-model**: on save, the `"llm"` facet MUST clear the `model` value to
  `nil` whenever the resolved `serviceId` is `nil` or the chosen service's `models` does not
  contain a model with that id — it MUST NOT persist a `model` the selected service does not
  actually offer.
- **facet-save-composes-full-body**: every facet's save action MUST start from `persona.body`
  (the persona's full current `PersonaBody`), apply only that facet's edits, and PUT the entire
  composed body via `dataSource.update(id:_:)` — fields the facet does not touch MUST ride along
  unchanged.
- **unknown-path-is-empty**: `child(for:)` MUST return `.empty` for an empty path, for a path
  whose first item's id matches no persona, and for a path whose second item's id matches no
  declared facet.

### CRUD and rename semantics (web)

- **personas-list-scoped-by-workspace**: `api.personas.list` MUST forward an optional `workspace`
  slug as a query parameter; when supplied, the result MUST be scoped to that workspace's owning
  principal rather than the caller's own creator-scoped rows.
- **persona-update-is-the-rename**: `api.personas.update` MUST send the full `PersonaBody`
  (including `slug`) on every `PUT`; a changed `slug` IS the rename — the server derives the new
  rdid and cascades it onto the handle and every descendant, and callers MUST read the new `id`
  from the echoed response rather than compute one client-side.
- **persona-by-slug-owner-lookup**: `api.personas.bySlugAsOwner` MUST query generic CRUD with an
  equality filter on `slug`, take the first matching row, and MUST throw `"404 Not Found"` when
  no row is returned.
- **persona-draft-narrows-visibility**: `toPersonaDraft` MUST narrow a persona's loosely-typed
  `visibility: string` to exactly `"public" | "hub" | "private"`, defaulting any other stored
  value to `"private"`.
- **persona-fields-single-source-of-truth**: `PERSONA_FIELDS` MUST describe every `PersonaDraft`
  key exactly once (enforced by a compile-time exhaustiveness check), and `personaBlank()` /
  `personaToBody()` MUST derive solely from that table.
- **persona-to-body-wire-strategies**: `personaToBody` MUST apply exactly the wire strategy each
  field declares: `"omit"` fields (e.g. `id`, `serviceName`) MUST NOT appear in the body;
  `"trimRequired"` fields MUST be trimmed and default to `""` when absent; `"trimOptional"`
  fields MUST be trimmed and omitted entirely (never sent as `""`) when blank; `"raw"` fields
  MUST pass through untrimmed and unfiltered.
- **persona-blank-chat-status-is-independent-copy**: `personaBlank()` MUST give `chatStatus` its
  own deep copy of `chatStatusBlank()`, not a shared reference, so mutating one draft's rows MUST
  NOT affect another draft's.

### Demo-chat eligibility and preview (web)

- **can-demo-chat-requires-enabled-and-line**: `canDemoChat` MUST return `true` only for a
  well-formed object with `enabled === true`, a parsing `pacing` block (or none), and at least
  one of the keyword script or the ink script both parsing AND having a line it can actually say;
  it MUST return `false` for any other input, including non-objects, `null`, and `undefined`.
- **can-demo-chat-never-compiles-ink**: the ink check MUST test only for a non-blank `source`
  string (and an optional string `signInLine`) and MUST NOT compile or otherwise validate the
  ink script's syntax — a script with a syntax error still counts as demoable.
- **can-demo-chat-malformed-sinks-whole-config**: when either the keyword script or the ink slice
  is present but malformed, `canDemoChat` MUST return `false` even if the other engine would
  otherwise qualify.
- **demo-preview-is-server-side-only**: the client MUST NOT implement ink replay, keyword
  matching, or escalation logic itself; `demoPreviewApi.play` MUST send the draft `source` and
  optional `signInLine`/`message`/`history`/`canEscalate` to `POST /api/persona/demo-preview` and
  MUST render only what the server returns.
- **demo-preview-history-cap-not-truncated**: callers MUST NOT truncate a `history` longer than
  `MAX_PREVIEW_HISTORY_ENTRIES` (`MAX_PREVIEW_TURNS * 2` = 80 entries) before sending — the server
  rejects an over-length history with a 400 rather than accepting a truncated one, since
  truncating would silently replay a different point in the script.
- **demo-preview-omitted-message-lints-and-plays-opening**: calling `demoPreviewApi.play` with no
  `message` and no `history` MUST be treated as "lint the draft and show its opening," using the
  same call path the editor's compile check and the visitor's first turn both use.

### Chat status resolution (web)

- **parse-chat-status-drops-not-substitutes**: `parseChatStatus` MUST drop a malformed `words` or
  `icons` entry rather than substituting `CHAT_STATUS_DEFAULT`, and MUST return an empty list
  (not the default rows) when the author has deliberately emptied that list; only `null` or
  non-object raw input MUST fall back to `chatStatusBlank()`.
- **parse-chat-status-draft-preserves-incomplete-rows**: `parseChatStatusDraft` MUST preserve a
  half-written word pair (one of `present`/`past` blank) and an icon set with zero frames, and
  MUST NOT trim text or drop empty tags — unlike `parseChatStatus`, which drops both.
- **resolve-chat-status-words-union-icons-exclusive**: `resolveChatStatus` MUST resolve `words`
  as the union of rows tagged with the requested kind and untagged rows, but MUST resolve `icons`
  as the first matching set only (tagged-for-kind, else untagged, else the built-in fallback).
  This asymmetry is deliberate and MUST NOT be changed to make icons union the way words do.
- **resolve-chat-status-never-throws**: `resolveChatStatus` MUST NOT throw for any input,
  including non-object raw values, and MUST always return at least one word and one non-empty
  frame set via the fallback chain through `chatStatusBlank()`.

### Ability, may-act, and approval grants (web)

- **persona-approvals-server-narrows-by-persona**: `personaApprovalsApi.list` MUST forward an
  optional `personaId` filter to the server and MUST NOT re-filter the response client-side.
- **persona-may-act-grant-kind-parameterized**: `personaMayActApi.grant`/`revoke` MUST accept a
  `kind` of `"user"` or `"team"` and MUST route through the single kind-parameterized endpoint.
- **persona-tools-set-autonomy-is-per-tool**: `personaToolsApi.setAutonomy` MUST PATCH a single
  named tool's `autonomous` flag and MUST leave every other granted tool's autonomy untouched.
- **persona-user-tools-is-layer-two-consent**: `personaUserToolsApi.setAllowed` MUST replace the
  calling user's full allow-list for one persona's owner-granted tools in a single `PUT`; this
  consent layer is distinct from, and downstream of, the owner-level grants `personaToolsApi`
  manages.

### Special interests and interest documents (web)

- **special-interests-list-must-filter-by-persona**: `specialInterestsApi.list` MUST always pass
  `personaId` as a query filter; omitting it would return every special interest the caller owns
  across all of their personas, not just this one.
- **special-interest-update-strips-immutable-fields**: `specialInterestsApi.update` MUST strip
  `personaId` and `bucketId` from the patch body before sending, even when the caller supplies
  them, since the server treats a `personaId` change as a 400 and always assigns `bucketId`
  itself.
- **interest-documents-act-as-persona**: every `interestDocumentsApi` call MUST include
  `?asType=persona&asId=<personaId>`, since the research-corpus bucket's access grant is held by
  the persona, not the calling user.
- **interest-documents-list-unpaginated**: `interestDocumentsApi.list` MUST NOT send
  `limit`/`offset`; callers MUST understand this returns only the server-capped first page (500
  rows) of an interest's document corpus.
- **interest-documents-response-envelope-differs-by-verb**: `interestDocumentsApi.list` MUST
  unwrap a `{ rows }` envelope, while `create`/`update` MUST treat the response as a bare row —
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
| `rootLevel()` with personas Ada, Bob | `HTDVLevel` with `items.label == ["Ada","Bob"]`, `items.sublabel == ["ada","bob"]`, `emptyMessage == "No personas yet."`, `createAction.title == "New Persona"` | `testRootLevelListsPersonas` |
| `child(for:[ada])` | `.level` with `id == "persona-topics"`, `title == "Ada"`, item ids exactly `identity, description, personality, purpose, project, knowledge, memory, abilities, permissions, access, demo, chatStatus, llm` | `testPersonaChildIsFacetRail` |
| Identity form: set `name` to `"Ada Lovelace"`, `visibility` to `"hub"`, save | `source.updates[0]` has `body.name == "Ada Lovelace"`, `body.visibility == "hub"`, `body.modelPrompt == "You are Ada."` (untouched, rides along) | `testIdentityFormValuesAndSave` |
| Identity slug field validated against `"Bad Slug"` | `FormValidator.validate(...) == Slug.patternMessage` | `testIdentityFormValidatesSlug` |
| Delete action performed on Ada's identity facet | `spec.actions.delete.confirmationText == "Delete persona \"Ada\"? This cannot be undone."`; `source.deletes == ["persona.me.ada"]` | `testIdentityDeleteAction` |
| Personality form: `voice = "   "`, `character = "Curious"`, save | `body.voice == nil`, `body.character == "Curious"` | `testBlankTextBecomesNilOnSave` |
| LLM form: clear `serviceId` to `""`, save | `body.serviceId == nil`, `body.model == nil` | `testLLMSaveClearsModelWhenServiceHasNoSuchModel` |
| `child(for:)` on each of the 8 unsupported facet ids | detail form value for key `"notice"` equals `"Not available in this version"`; `facetSpec` returns `nil` | `testUnsupportedFacetsShowNotice` |
| `createSpec().actions.save.perform(name: "Bob", slug: "bob", description: "", modelPrompt: "You are Bob.")` | `source.creates[0]` has `description == nil`, `model == ""`, `visibility == "private"` | `testCreateSpecAndPerform` |
| Decode a web JSON payload with extra fields `userId`/`ownerKind`/`ownerId` | Decode succeeds; `persona.name == "Ada"`, unknown fields dropped, `persona.cannedChat == .object(["mode": .string("script"), "turns": .array([])])` | `testPersonaDecodesFromWebJSON` |
| `canDemoChat({ enabled: true, ink: { source: "* [unclosed\n", signInLine: "x" } })` | `true` — a syntax error in the ink script still advertises a demo | canned.test.ts, "does not compile the ink — a syntax error still advertises a demo" |
| `canDemoChat({ ...good, enabled: false })` and `canDemoChat(null)` | both `false` | canned.test.ts, "is false for a parked script and for no config at all" |
| `parseChatStatus({ words: 7 })` | `{ words: [], icons: [] }` — malformed field dropped to an empty list, not substituted with the default | chat-status.test.ts, "drops a malformed words/icons field to an empty list rather than substituting the default" |
| `resolveChatStatus(cfg, "search")` where `cfg` has one word pair tagged `"search"` plus untagged defaults | `words` is the UNION of the tagged and untagged rows; `frames` resolves to the first matching icon set only | chat-status.test.ts, "unions rows tagged with the kind with untagged rows that fit anything" |

## Edge Cases

- An empty persona list renders `rootLevel()`'s `emptyMessage`, `"No personas yet."`, rather than
  an empty items array with no explanation.
- A facet id present in `topicsLevel`'s rail but outside `supportedFacetIDs` (8 of the 13 declared
  facets) MUST resolve to the fixed unavailable-facet notice, never to a broken or partially-
  rendered form.
- A path whose facet id matches nothing in `Self.facets` (not merely an unsupported id, but an
  unknown one) MUST resolve to `.empty` via the same `guard let facet = ...` as an unknown persona
  id.
- Every blank optional text field on a facet save (`description`, `character`, `voice`,
  `examples`) is mapped to `nil` through `HubText.nonBlank`, never persisted as `""`.
- Selecting the `"llm"` facet's `model` for a service that does not actually offer that model id
  (stale selection, or the service was switched) MUST clear `model` to `nil` on save rather than
  persist a mismatched pair.
- Any failure from the injected `PersonasDataSource` (e.g. `.offline`) on `rootLevel()`, `child(for:)`,
  create, save, or delete MUST propagate as a `HubError`, never be swallowed.
- `canDemoChat` treats a raw config that is not an object at all (`"not even an object"`) the same
  as one that is well-formed but switched off: `false`, with no thrown error.
- `interestDocumentsApi.list` on a corpus with more than 500 documents silently returns only the
  first (oldest-id-first) 500; the caller receives no signal that more documents exist.
- `demoPreviewApi.play` called with a `history` longer than `MAX_PREVIEW_HISTORY_ENTRIES` is
  rejected by the server with a 400; this client sends the caller's history as given and applies
  no truncation of its own.
- `specialInterestsApi.update` given a patch that includes `personaId` or `bucketId` silently
  drops both from the outgoing request rather than sending (and having the server reject) them.

## Configuration

- `dataSource`: the `PersonasDataSource` implementation injected into `PersonasModule.init(dataSource:)`
  — supplied by the app repo, typically backed by `HubAPI`.
- `workspace` (optional, `api.personas.list`/`create`/`update`/`delete`): a workspace slug that
  scopes the operation to that workspace's owning principal instead of the caller's own rows.
- `personaId` / `bucketId` / `typeId` / `rowId`: caller-supplied identifiers threading through
  `interestDocumentsApi`, `specialInterestsApi`, `personaApprovalsApi`, `personaMayActApi`,
  `personaToolsApi`, and `personaUserToolsApi` to select which persona's records or grants are
  being read or changed.
- `kind` (`"user" | "team"` for may-act; `"user" | "team" | "org"` on the wire body): which
  context a persona is granted or denied leave to act under.
- `status` (`personaApprovalsApi.list`, default `"pending"`): which approval queue state to list.
- `DemoPreviewBody` fields — `source`, `signInLine`, `message`, `history`, `canEscalate` — all
  caller-supplied inputs to one preview call; `canEscalate` selects which visitor's demo (signed-in
  vs. anonymous) is being previewed.
- `PERSONA_FIELDS`' `wire` strategy per field (`trimRequired` / `trimOptional` / `raw` / `omit`)
  is compiled into `personaToBody` and is not caller-configurable at runtime.

## Deep Linking

Not applicable: none of the given sources register a URL scheme, universal link, or deep-link
route; navigation is entirely through `HTDVDataSource`'s `rootLevel()`/`child(for:)` rail on
Apple and direct API calls on the web, neither of which any given source wires to a URL.

## Localization

The given sources hardcode English user-facing strings rather than localizing them:

- `HubError.message` — `"You need to sign in again."`, `"You don't have permission to do that."`,
  `"That item no longer exists."`, `"The hub can't be reached right now."`, and the templated
  `"Connection problem: \(detail)"` / `"Something went wrong: \(detail)"`.
- `FormDetails.unavailableMessage` — `"Not available in this version"`, shown for every
  unsupported facet.
- `Slug.patternMessage` — `"Use lowercase letters, numbers and hyphens."`
- `PersonasModule`'s field labels, placeholders, and confirmation text (e.g. `"New Persona"`,
  `"Delete persona"`, `Delete persona "<name>"? This cannot be undone.`, and the field
  placeholders such as `"Bob"`, `"bob"`, `"A one-line summary of this persona."`) are all
  English literals with no localization mechanism in these sources.
- The web's `demoPreviewApi`/`chat-status`/`canned` modules carry no user-facing strings of their
  own — their outputs (`ResolvedChatStatus`, `DemoPreviewTurn`) are rendered by a presentation
  layer this recipe does not own — except `CHAT_STATUS_DEFAULT`'s and `CHAT_STATUS_WORD_PRESETS`'
  English word pairs (`"thinking"`, `"responding"`, etc.), which are persisted author-facing
  content, not chrome.

## Accessibility Options

Not applicable — this is a data-access and navigation-orchestration component; the given sources
expose no accessibility-options surface of their own (SF Symbol names such as
`"person.crop.circle"` are cosmetic hints consumed by a presentation layer this recipe does not
own).

## Feature Flags

Not applicable: none of the given sources read a runtime feature flag or remote-config value.
`PersonasModule.supportedFacetIDs` gates which of the 13 declared facets are editable, but it is
a compiled-in `Set<String>` constant, not a runtime flag.

## Analytics

Not applicable: none of the given sources call an analytics or telemetry client.

## Privacy

Not applicable: the given sources delegate network transport, authentication, and credential
storage to the app repo's `HubAPI` (per `PersonasDataSource`'s doc comment, "The app repo
implements it over `HubAPI`") and to the web's shared `authedJson`/`authedRequest` helpers; no
given source reads, stores, or transmits a credential directly. The persona content these
sources do carry — name, description, character, voice, model prompt, demo-chat script, special
interests — is user-authored feature data handled as an opaque payload, with no additional PII
classification, redaction, or retention logic applied by this component itself.

## Logging

Not applicable: none of the given sources call a logger, `console.*`, or `print` — confirmed by
inspection of every given Swift and TypeScript source file in this domain.

## Platform Notes

- **SwiftUI / AppKit / UIKit (Apple, already implemented)**: `PersonasModule` is a `@MainActor
  final class` conforming to `HTDVDataSource`, driving `FormSpec`/`FormSheet`/`FormViewController`
  from `AgenticToolkitHTDV` (see `agentictoolkit://recipes/htdv-engine`); shared Hub support types
  (`HubError`, `HubText`, `RailPath`, `Slug`, `JSONValue`, `FormDetails`) are reused rather than
  reimplemented per feature.
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

**Decision**: `PersonasModule.supportedFacetIDs` implements only 5 of the 13 facets declared in
`PersonasModule.facets`; the other 8 render a fixed "not available in this version" notice
instead of a form.
**Rationale**: the rail's shape (list-then-facets) is stable and worth shipping ahead of every
facet's editor being ready; showing the full rail with an honest notice on unfinished facets
avoids either hiding the facet's existence or exposing a half-built form.
**Approved**: pending

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

**Decision**: `InterestDocumentRow` declares every column of the backend's `content.markdown`
row (23 fields), not just the `id`/`title`/`content` this feature reads.
**Rationale**: the source's comment records that an earlier five-field fixture looked enough like
the wire to hide a real envelope bug; declaring the true shape (and true nullability) lets any
caller reaching for an undeclared field get an honest answer from the type rather than a
convenient subset that quietly diverges from what the server actually sends.
**Approved**: pending

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
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
