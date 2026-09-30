<!-- leaf: implement-hub-domain-2/personas--part-2 · source: hub-domain-personas.md -->

# Hub Domain: Personas — continued (part 2)

**Rules** (cite as `implement-hub-domain-2/personas--part-2#<slug>`):

- `can-demo-chat-requires-enabled-and-line` MUST
- `can-demo-chat-never-compiles-ink` MUST
- `can-demo-chat-malformed-sinks-whole-config` MUST
- `demo-preview-is-server-side-only` MUST
- `demo-preview-history-cap-not-truncated` MUST
- `demo-preview-omitted-message-lints-and-plays-opening` MUST
- `parse-chat-status-drops-not-substitutes` MUST
- `parse-chat-status-draft-preserves-incomplete-rows` MUST
- `resolve-chat-status-words-union-icons-exclusive` MUST
- `resolve-chat-status-never-throws` MUST
- `persona-approvals-server-narrows-by-persona` MUST
- `persona-may-act-grant-kind-parameterized` MUST
- `persona-tools-set-autonomy-is-per-tool` MUST
- `persona-user-tools-is-layer-two-consent` MUST
- `special-interests-list-must-filter-by-persona` MUST
- `special-interest-update-strips-immutable-fields` MUST
- `interest-documents-act-as-persona` MUST
- `interest-documents-list-unpaginated` MUST
- `interest-documents-response-envelope-differs-by-verb` MUST

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

