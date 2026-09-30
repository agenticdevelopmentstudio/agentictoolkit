<!-- leaf: implement-hub-domain-1/buckets--part-4 · source: hub-domain-buckets.md -->

# Hub Domain: Buckets — continued (part 4)

## Design Decisions

**Decision**: `createSpec`'s and `createTableSpec`'s save actions both
check for a duplicate name against a freshly fetched list *before* calling
`create`/`createTable`, and also catch an `HubError.conflict` the create
call itself might throw, re-throwing it as the identical duplicate-name
message either way.
**Rationale**: The precheck-then-create sequence has an unavoidable
check-then-act window — nothing in these three sources locks the ecosystem
between the list read and the create write — so a second, concurrent
create for the same name can still reach the server after the precheck
passed. Catching the server's own conflict response and re-mapping it to
the same user-facing message means a caller sees one consistent duplicate-
name error regardless of which guard actually caught it, rather than
surfacing a raw conflict detail from the second path.
**Approved**: pending

**Decision**: `createTableSpec`'s and `tableDetail`'s `"name"` field is
declared `isRequired: false` at the `FormTextField` level, and emptiness is
instead checked explicitly inside each save action with the message
`"Every table needs a name."`, unlike `createSpec`/`settingsDetail`'s
`"name"` field, which is `isRequired: true` and relies on the Forms
subsystem's own generic `"<label> is required"` validation.
**Rationale**: Per the source's own comment on `createTableSpec`'s save
action deriving a SQL name, this file needs to distinguish "no name at all"
from "a name that derives no usable SQL identifier" — two failure messages
the generic Forms required-field check cannot produce — so it takes over
required-ness checking for this one field rather than delegating it, even
though `createSpec`'s save action never needed to.
**Approved**: pending

**Decision**: `settingsDetail`'s save action performs no client-side
duplicate-name lookup before calling `update(id:_:)`, unlike `createSpec`'s
save action, which lists existing buckets first.
**Rationale**: The source does not state why; the observable effect is
that renaming a bucket to a name already in use is caught only by the
server's `HubError.conflict` response, one network round trip later than
the create path's precheck. Documented here as a real asymmetry between
the two forms, not smoothed over, since a port that unifies the two code
paths would otherwise silently add a precheck the original settings form
never had.
**Approved**: pending

**Decision**: `BucketsTopic.tableName(from:)` treats every non-ASCII
scalar as a separator rather than attempting any transliteration (for
example, folding an accented Latin letter to its unaccented form).
**Rationale**: The function's contract, per its own doc comment, is to
produce a valid SQL identifier; ASCII `a`-`z`/`0`-`9` is a safe, universally
valid identifier character set for that purpose, and folding accented or
CJK characters into their nearest ASCII equivalent would require a
transliteration table this file does not have and does not attempt — the
tradeoff is that visually similar names in different scripts, or an
accented and unaccented version of the same word, can either collide on
the same derived SQL name or both derive the empty string, depending on
how many ASCII characters survive.
**Approved**: pending
