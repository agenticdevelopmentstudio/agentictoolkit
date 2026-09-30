<!-- leaf: implement-hub-domain-1/ecosystems--part-6 · source: hub-domain-ecosystems.md -->

# Hub Domain: Ecosystems — continued (part 6)

## Design Decisions

**Decision**: `EcosystemSettingsTopic.values(for:)` always reports
`region` as the literal string `"coming soon"`, and its save action never
includes `region` (or `primaryDomain`) in the `EcosystemUpdate` it sends,
regardless of what the form displays.
**Rationale**: The Apple settings form has not yet built real region
editing; showing a fixed placeholder is an honest "not yet available"
signal rather than either fabricating a value from the model's real
(currently unused) `region` field or omitting the row entirely. Never
sending it on save is a direct consequence: there is nothing real to send.
**Approved**: pending

**Decision**: `EcosystemsModule.child(for ecosystem:path:)` checks
`ecosystem.isManageable` before resolving any topic, so an unmanageable
ecosystem's `child-ecosystems`/`settings`/other topics are unreachable —
never partially reachable with per-action 403s.
**Rationale**: The alternative (resolve the topic, let the eventual
mutation 403) would let a non-admin org member browse an ecosystem's full
settings/child list read-only before hitting a wall on save/delete — worse
UX than one honest, upfront notice, and it would require every downstream
topic to independently re-check manageability.
**Approved**: pending

**Decision**: `ecosystemsApi.update` sends `slug` whenever the caller
supplies `identifier` at all, never only when it differs from the stored
`id`.
**Rationale**: `id` is the stored, mutable HANDLE; what a settings form
actually edits is the address the row DERIVES to from `(parent chain,
slug)`. The two disagree on exactly the rows this matters most for — a
row whose handle still says `…mike` while its slug column already says
`chosen` — where diffing against `id` would silently drop the one save
that heals the drift (a rename back to `…mike`, which equals `id` but is
a genuine slug change). Sending an already-correct slug costs nothing:
the route's own stored-value diff rules out a true no-op before any
cascade runs.
**Approved**: pending

**Decision**: The old two-call rename sequence (a PUT of ordinary fields
followed by a `registry.identifiers` PATCH of the handle) was removed in
favor of the single `ecosystemsApi.update` PUT carrying `slug`.
**Rationale**: The address is derived from `(parent chain, slug)`, so
moving the slug IS the rename; PATCHing the handle separately retitles it
without moving the slug column, leaving the row deriving its OLD address
— and the next ancestor cascade re-leafs the handle back, silently undoing
the rename. The two-call sequence also needed a 404-recovery branch for
the case where the first call lands and the second fails; the single-PUT
shape has no such window, because a failed PUT changes nothing.
`identifiersApi.rename` remains the correct mechanism for other,
non-address-bearing entity types (or a future purely-cosmetic handle
retitle) — it is simply not the ecosystems rename path anymore.
**Approved**: pending

**Decision**: `useWorkspaceDefaultEcosystemId` is never disabled
(`enabled`) on the absence of `workspaceSlug`.
**Rationale**: A disabled query stays `isPending` forever; a caller that
treats `isPending` as "still resolving, wait for it" then waits on an
answer that never comes. Every slug-less host (a feature-site mount whose
creates are caller-owned, not workspace-owned) needs the CALLER's own
infrastructure row, which is a real, resolvable answer, not the absence
of one — so the query must actually run for that case too.
**Approved**: pending

**Decision**: The Apple `Ecosystem` model and `EcosystemSettingsTopic`'s
form expose no `primaryDomain`/`domain` field, while the web `Ecosystem`
interface and settings-equivalent panes do (`domain`, mapped from
`primaryDomain`).
**Rationale**: This is a genuine, current cross-platform divergence, not
an inconsistency in this recipe's sourcing: the Apple Hub UI for editing a
custom domain has not been built yet, while the web client already models
the field end-to-end (`EcosystemInput.domain`, `toEcosystem`,
`EcosystemPutBody.primaryDomain`). A future Apple settings field for it
should follow the same read-only-until-built pattern `region` uses today,
not invent new semantics.
**Approved**: pending

**Decision**: `ecosystem-invitations.ts`'s row-shape mappers
(`toRequest`, `toPendingUser`, `toInvite`, `toAdminNote`,
`toHistoryEntry`) and their backend types are imported from
`@agentic-toolkit/adh-ui/invitations-types` rather than defined in this
recipe.
**Rationale**: Those mappers are shared with the platform-admin
invitations hooks referenced in this file's own header comment
(`websites/main/admin/src/api/invitations.ts`) — they belong to the
Invitations feature's own contract, not to Ecosystems. This recipe
documents what the Ecosystems-owned hooks in `ecosystem-invitations.ts`
do with their query keys, endpoints, and cache invalidation, and treats
the mappers' internal field-by-field shape as a different component's
concern, out of scope here.
**Approved**: pending

**Decision**: Features are added as one plural POST per batch, while
removals are one DELETE per key, run concurrently and collected with
`Promise.allSettled`, adds first.
**Rationale**: The picker confirms a batch of adds behind one "Add N
features?" prompt and the backend runs the batch in one transaction, so a
partial failure never leaves the owner with three of five features and no
way to tell which. The DELETE route removes one key, so removals cannot
share a request; `allSettled` keeps one 5xx from silently aborting the
rest the way a sequential `for … await` would, and naming the failed keys
tells the caller which features are still provisioned. Adds go first so a
failed removal never costs the features just added.
**Approved**: pending

**Decision**: `ecosystemFeaturesApi.remove` treats a 404 as success.
**Rationale**: The caller's goal is that the row is gone; a double-click, a
stale list, or a second tab racing the same removal would otherwise report
failure for an outcome that already happened. Every other status still
throws.
**Approved**: pending

**Decision**: The feature catalog is cached under a key with no ecosystem id
and a 30-minute `staleTime`, and "Coming soon" entries stay in it.
**Rationale**: The catalog is a property of the server build, not of any
ecosystem, so one list serves the whole session; refetching it on every
picker open would re-download the same rows each time. Unbuilt features are
kept so the owner can see what is coming; the picker disables them and the
backend refuses to provision them, so the client needs no filter.
**Approved**: pending
