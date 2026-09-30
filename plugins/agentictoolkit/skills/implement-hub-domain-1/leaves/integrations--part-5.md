<!-- leaf: implement-hub-domain-1/integrations--part-5 · source: hub-domain-integrations.md -->

# Hub Domain: Integrations — continued (part 5)

**Rules** (cite as `implement-hub-domain-1/integrations--part-5#<slug>`):

- `decision` MUST — rotate-webhook-secret-requires-caller-confirmation is written as a SHOULD, not a MUST. Rationale: integrations.ts is a …

## Design Decisions

**Decision**: `configPath` (used with a `providerId`) and `configByIdPath` (used with a `configId`) are two
separate private helper functions in `integrations.ts` that produce the identical URL template.
**Rationale**: the file keeps them separate because they express two different addressing *schemes* over the
same underlying route shape — a provider slug for the legacy provider-id-addressed CRUD group, and a
uuid/rdid for the newer id/rdid-addressed CRUD group — even though nothing in the URL itself distinguishes
which scheme a given call is using; the backend must tell a provider slug apart from a config id/rdid by the
value's own shape, not by the route. This recipe records the duplication as an observed structural fact of
the source rather than "fixing" it to one helper, since collapsing them would change which named function a
port's own two addressing schemes call through.
**Approved**: pending

**Decision**: `getAuthUrl`/`getInstallUrl` build their query strings with `URLSearchParams`, while
`listConnections`'s `ecosystemId` query parameter is encoded manually via string interpolation with `enc`.
**Rationale**: both mechanisms percent-encode their values correctly, so there is no functional divergence,
but the file uses two different idioms for the same kind of task; this is recorded as an observed stylistic
inconsistency, not corrected to one convention, since a port is free to standardize on either without
changing observable behavior.
**Approved**: pending

**Decision**: `decodeOAuthStateClaims` deliberately ignores the signature half of the `state` value it
decodes, and `isOAuthStateFresh`'s window is deliberately wider than the backend's own by
`OAUTH_STATE_CLOCK_GRACE_MS` in both directions.
**Rationale**: the source's own comments are explicit on both points: nothing here is a security decision,
because every recovered claim is re-verified by the backend before `connect` persists anything, so a forged
`state` is no more dangerous decoded than undecoded; and the pre-flight window is widened, rather than
mirrored exactly, so that the two independent clocks involved (the operator's browser and the backend) never
cause this client to refuse a `state` the backend would have accepted — the reverse (this client accepting
one the backend then rejects) only ever costs the `POST` that would have happened anyway, answered by the
backend's own verdict.
**Approved**: pending

**Decision**: `AdoptedInstallationRow.warning` is declared and documented in `wire.ts`, but no given source
in `integrations.ts` reads or surfaces it.
**Rationale**: `wire.ts`'s own comment on the field states this is deliberate rather than an oversight — the
sentence an operator sees about a failed cache warm is authored by the backend's own test narrator, which
reads this field server-side; a prior client-side copy of that narration was removed once the field existed
to carry it from the server instead. This recipe documents the field as part of the wire contract (a port
must still decode it, since the response really carries it) without inventing a consumer for it that these
given sources do not have.
**Approved**: pending

**Decision**: `rotate-webhook-secret-requires-caller-confirmation` is written as a SHOULD, not a MUST.
**Rationale**: `integrations.ts` is a stateless request-builder with no UI of its own — it cannot itself
enforce a confirmation step, since confirming is a presentation-layer concern outside these two files' given
sources (the source's own comment says only that "callers must confirm before firing it"). Writing it as
MUST would describe a guarantee this module cannot make; SHOULD records the expectation for whatever
presentation layer wires a button to `rotateWebhookSecret`, without overstating what this file itself
enforces.
**Approved**: pending
