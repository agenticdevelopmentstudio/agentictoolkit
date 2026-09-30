<!-- leaf: implement-hub-domain-1/hooks · source: hub-domain-hooks.md -->

# Hub Domain Messaging Hooks

## Overview

`use-dms.ts` and `use-notifications.ts` are the client-side logic for the web messaging
surface: the DM inbox, a single DM thread, starting a DM, the header unread badge, and the
notification inbox list. Both files carry the same shape — a data hook backed by `authedJson`/
`authedRequest` from `@agentic-toolkit/auth/client`, kept live over the shared `connectSse`
transport (`@agentic-toolkit/data/stream`), which is SSE-with-token-in-query-string plus a
self-healing interval-and-window-focus poll fallback. `use-notifications.ts` additionally owns
ONE module-level "wake" channel — a single refcounted `/api/notifications/stream` connection and
an `emitLocalChange`/`subscribeToNotifications` pub-sub pair — that `use-dms.ts` reuses rather
than opening its own parallel signal, per both files' own top-of-file comments. It is a headless
**logic** module with no visual surface, so this recipe marks Appearance, States, and
Accessibility not applicable and carries the entire runtime contract in Behavioral Requirements,
per the non-UI component guidance this recipe was authored under.

