<!-- leaf: implement-hub-domain-2/personas--part-3 · source: hub-domain-personas.md -->

# Hub Domain: Personas — continued (part 3)

**Rules** (cite as `implement-hub-domain-2/personas--part-3#<slug>`):

- `cross-platform` MUST — canDemoChat, parseChatStatus /resolveChatStatus, and demoPreviewApi are deliberately duplicated logic that must agree …

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
