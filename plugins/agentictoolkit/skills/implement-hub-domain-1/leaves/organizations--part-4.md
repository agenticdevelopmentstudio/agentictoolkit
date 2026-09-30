<!-- leaf: implement-hub-domain-1/organizations--part-4 · source: hub-domain-organizations.md -->

# Hub Domain: Organizations — continued (part 4)

**Rules** (cite as `implement-hub-domain-1/organizations--part-4#<slug>`):

- `decision` SHOULD — resolve does not intercept a 404 into null. Rationale: no comment in the source explains this choice, and no other …

## Design Decisions

**Decision**: `organizationsApi.list` requires `workspaceSlug` and scopes its rows by that
workspace's kind (owned-plus-member for a personal workspace, owned-only for an organization
workspace), rather than answering a plain, workspace-independent "the caller's organizations"
question.
**Rationale**: per the module's own top-of-file comment, an earlier arrangement read
`workspacesApi.list()` and filtered `kind === "organization"` — a pure membership question,
identical under every workspace, so the workspace you had open silently appeared inside its own
organizations rail. Organizations now carry an owning workspace (`owner_kind`/`owner_id`), and this
endpoint reads it; `workspacesApi.list()` remains correct for the workspace SWITCHER, which
genuinely is asking the membership question.
**Approved**: pending

**Decision**: `create` sends `input` verbatim (no `compact`), while `rename` applies
`compact(input)` to a structurally similar patch object.
**Rationale**: `create`'s body is a fixed two-field shape (`slug` + `name`) always fully supplied
by the caller — there is nothing optional to omit. `rename`'s body has three independently optional
fields, and an untouched field must not travel as an explicit `undefined` key on the wire; `compact`
is needed only where partial updates exist.
**Approved**: pending

**Decision**: `restore`'s 409 handling is status-based (`isConflict`), while `create`/`rename`'s is
message-based (`rethrowConflict`).
**Rationale**: the source's own inline comment states the restore route's 409 message ("that
organization handle has been taken") does not match `rethrowConflict`'s "already exists" pattern
match — reusing `rethrowConflict` here would fail to produce the friendly message and let the raw
backend wording leak through. Status-based detection avoids depending on exact wording that this
one route doesn't share with the other two.
**Approved**: pending

**Decision**: `resolve` does not intercept a 404 into `null`.
**Rationale**: no comment in the source explains this choice, and no other 404-to-null pattern
exists elsewhere in these two files to compare it against (unlike the sibling Ecosystems client's
`get(id)`, which does map 404 to `null`). This is recorded as an observed fact of the current
source, not smoothed into a more convenient shape — a port SHOULD preserve it unless a future
change to the source deliberately revisits it.
**Approved**: pending

**Decision**: `create`'s authorization splits on WORKSPACE KIND (open in a personal workspace,
admin-of-the-organization required from an organization workspace), while `rename`'s splits on
WHICH FIELD is being changed (name/description need org-team-admin; slug needs site-admin).
**Rationale**: both splits are stated directly in the source's own per-method comments. `create`'s
split exists because creating from an organization workspace is a governance act — the organization
that owns the workspace ends up owning the result. `rename`'s split exists because a slug change
re-mints the organization's global rdid tree, a wider-blast-radius operation than editing a label.
**Approved**: pending

**Decision**: `ORGANIZATIONS_QUERY_KEY` is deliberately a bare prefix, not a complete cache key, and
deliberately distinct from any workspace-membership query key.
**Rationale**: directly from the export's own doc comment — a caller appends the workspace slug so
each workspace caches its own answer and switching workspaces cannot serve the previous one's rows;
invalidating the bare prefix clears every workspace at once, which is what `create`/`rename` need.
Sharing one key over the organizations question and the membership question is what made the two
lists impossible to tell apart before this endpoint existed.
**Approved**: pending
