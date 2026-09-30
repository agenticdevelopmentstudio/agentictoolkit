<!-- leaf: implement-hub-domain-2/teams--edge-cases · source: hub-domain-teams.md -->

# Hub Domain: Teams

**Rules** (cite as `implement-hub-domain-2/teams--edge-cases#<slug>`):

- `null-empty-input` MUST — An empty identifier to validateTeamIdentifier MUST be refused with "Identifier is required." (SHOULD/MUST per …
- `boundary-malformed-values` MUST — validateTeamIdentifier MUST accept the minimal two-label form ("a.b") and MUST reject a single label ("platform", …
- `concurrent-access` MUST — Two closely-timed teamsApi.create/update calls for the same (owner, slug) MUST leave exactly one team row and MUST …

## Edge Cases

- **Null/empty input**: An empty `identifier` to `validateTeamIdentifier`
  MUST be refused with `"Identifier is required."` (SHOULD/MUST per
  `identifier-validation-empty-refused`). Neither `add`'s `email` nor
  `addPersona`'s `personaKey` is validated client-side; an empty value is
  sent to the backend unchanged, and whatever the backend does with it (a
  404 or 400) is this client's behavior too — an absent client-side check,
  not a swallowed error (no doc comment or type signature promises one).
- **Boundary/malformed values**: `validateTeamIdentifier` MUST accept the
  minimal two-label form (`"a.b"`) and MUST reject a single label
  (`"platform"`, confirmed by `hub-domain-teams-003`) — the pattern
  requires at least one dot-separated segment after the first label.
- **Concurrent access**: Two closely-timed `teamsApi.create`/`update` calls
  for the same `(owner, slug)` MUST leave exactly one team row and MUST
  present the second caller with the friendly `"already exists"` error via
  `rethrowConflict` (team-create-conflict-rethrown-friendly,
  team-update-conflict-rethrown-friendly). Two closely-timed
  `teamMembersApi.add` calls adding the same customer to the same team MUST
  leave exactly one member row, but — unlike `teamsApi` — the second caller
  sees the backend's RAW 409 message, with no friendly-message mapping
  applied by this client (member-add-duplicate-is-conflict).
- **Error states**: `teamsApi.get` resolves ANY thrown error to `null`,
  not only a 404 (see team-get-swallows-any-error-as-not-found in
  Behavioral Requirements). Every other method on both clients
  (`teamsApi.list`/`create`/`update`/`delete`, all of `teamMembersApi`)
  lets a thrown error propagate unchanged to the caller
  (member-errors-propagate-with-backend-message).
- **Offline/disconnected state**: Neither client implements a timeout,
  retry, backoff, or offline queue; a network failure mid-request surfaces
  identically to any other thrown error — an `Error` with no `.status` —
  through `authedJson`/`authedRequest`, with no built-in recovery in this
  domain's own files (an absent feature, not a swallowed signal, since no
  doc comment or type in this domain promises retry behavior).
