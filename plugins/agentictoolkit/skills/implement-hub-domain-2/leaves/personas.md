<!-- leaf: implement-hub-domain-2/personas · source: hub-domain-personas.md -->

**Rules** (cite as `implement-hub-domain-2/personas#<slug>`):

- `persona-data-source-protocol` MUST
- `persona-value-shape` MUST
- `persona-body-projection` MUST
- `persona-decode-tolerates-unknown-fields` MUST
- `persona-service-shape` MUST
- `canned-chat-and-chat-status-are-opaque-json` MUST
- `personas-root-level-lists-personas` MUST
- `personas-root-level-wraps-errors` MUST
- `persona-child-resolves-by-id` MUST
- `persona-child-notfound-is-empty` MUST
- `persona-topics-rail-order` MUST
- `llm-facet-fetches-services` MUST
- `unsupported-facets-show-notice` MUST
- `create-spec-defaults` MUST
- `identity-facet-fields` MUST
- `description-facet-fields` MUST
- `personality-facet-fields` MUST
- `purpose-facet-fields` MUST
- `llm-facet-service-model-options` MUST
- `llm-facet-clears-invalid-model` MUST
- `facet-save-composes-full-body` MUST
- `unknown-path-is-empty` MUST
- `personas-list-scoped-by-workspace` MUST
- `persona-update-is-the-rename` MUST
- `persona-by-slug-owner-lookup` MUST
- `persona-draft-narrows-visibility` MUST
- `persona-fields-single-source-of-truth` MUST
- `persona-to-body-wire-strategies` MUST
- `persona-blank-chat-status-is-independent-copy` MUST

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

