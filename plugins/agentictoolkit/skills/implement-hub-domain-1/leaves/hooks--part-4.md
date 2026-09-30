<!-- leaf: implement-hub-domain-1/hooks--part-4 · source: hub-domain-hooks.md -->

# Hub Domain Messaging Hooks — continued (part 4)

**Rules** (cite as `implement-hub-domain-1/hooks--part-4#<slug>`):

- `decision` MUST — send and markRead carry no chatId-generation guard, while the thread's own history load and useDmConversations' window …

## Design Decisions

**Decision**: the shared wake channel opens exactly one `/api/notifications/stream` connection,
refcounted across every mounted messaging hook, rather than each hook opening its own.
**Rationale**: the source's own comment in `use-notifications.ts` states this directly — a page
with the header bell, the DM list, and an open inbox previously held two to three duplicate wake
connections before this refactor; refcounting on a module-level `Set` keeps one connection alive
exactly as long as at least one hook needs it.
**Approved**: pending

**Decision**: the DM conversation list grows a single window (`loadMore` widening one `pageSize`
request) instead of accumulating separate offset pages.
**Rationale**: the source's own comment explains this keeps each fetch "one consistent snapshot" —
accumulating offset pages independently would let a chat that reorders between page fetches
(`updated_at`-sorted) produce a duplicate or dropped row across the page boundary.
**Approved**: pending

**Decision**: the presence fetch failing is treated as "assume everyone offline" rather than
failing the whole conversation-list load.
**Rationale**: the source's own comment on `fetchPresenceMap` calls this out explicitly as
best-effort, because a transient presence-service blip must not blank the entire DM inbox; this
recipe records that asymmetry (the chats list is essential, presence is decorative) as intentional.
**Approved**: pending

**Decision**: `send`'s access token for the DM thread's live stream, and the shared notifications
stream's token, both ride the URL query string instead of a header, unlike every other request in
this recipe.
**Rationale**: this is `EventSource`'s own platform limitation — it cannot set request headers —
and both source files say so directly; this recipe documents the resulting exposure difference
under Security and Privacy rather than treating it as an oversight to silently correct.
**Approved**: pending

**Decision**: `send` and `markRead` carry no chatId-generation guard, while the thread's own history
load and `useDmConversations`' window load both do.
**Rationale**: recorded as observed source behavior, not smoothed over — see the
`thread-message-isolation-on-chatid-switch` marker; a port MUST decide deliberately whether to add
a matching guard to these two callbacks or to preserve the current behavior, since the current
checkout does not settle which is intended.
**Approved**: pending
