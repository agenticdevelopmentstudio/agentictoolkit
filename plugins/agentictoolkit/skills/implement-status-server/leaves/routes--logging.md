<!-- leaf: implement-status-server/routes--logging · source: status-server-routes.md -->

# Status Server Routes

## Logging

Several routes log on failure via `console.error`, and one notably does not:

- `hooks.ts` logs when `ownedBySite`'s roster read fails (the condition that
  drives the 503 fail-closed response), when `runReconcile`'s derivation
  pass fails (fail-soft — the webhook still responds normally), and when
  `upsertDeployments` fails to persist a webhook event (also fail-soft).
- `stream.ts` logs when building a fresh opening-frame snapshot fails (the
  stream still opens, with a null-data opening frame).
- `badge.ts`'s catch-all around snapshot assembly falls back to
  `overall: 'unknown'` with NO logging call at all — a documented contrast
  with the fail-soft-but-logged pattern used elsewhere; a badge render
  failure currently leaves no trace for an operator to notice.
