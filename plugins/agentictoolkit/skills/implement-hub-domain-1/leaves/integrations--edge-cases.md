<!-- leaf: implement-hub-domain-1/integrations--edge-cases · source: hub-domain-integrations.md -->

# Hub Domain: Integrations

**Rules** (cite as `implement-hub-domain-1/integrations--edge-cases#<slug>`):

- `null-and-empty-input-state` MUST — decodeOAuthStateClaims MUST return null for the empty string (no . present, per decode-state-claims-grammar) rather …
- `null-and-empty-input-createlinktoken-s-optional-body` MUST — an omitted body argument MUST be sent as {}, per create-link-token-request-shape; there is no distinct "send nothing" …
- `boundary-values-oauth-state-freshness` MUST — the widened window's both edges are inclusive per state-freshness-window; one millisecond outside either edge MUST flip …
- `concurrent-access-repeat-rotatewebhooksecret-calls` MUST — calling rotateWebhookSecret twice in succession MUST NOT be treated as idempotent — each call mints a distinct new …
- `error-states-malformed-test-request-vs-refused-credential` MUST — a malformed testProviderConfig/ testProviderCredentials request (unknown provider, undeclared field, non-testable …
- `oauthcallbackurl-outside-a-browser` MUST — calling it where window is undefined (e.g. during server-side rendering) MUST throw whatever ReferenceError accessing …

## Edge Cases

- **Null and empty input — path identifiers**: `ecosystemId`/`providerId`/`configId`/`connectionId` are typed
  `string` and are not checked for emptiness client-side; an empty value is still percent-encoded (to the
  empty string) and sent, producing a request the backend answers with its own `404`/`400` — a non-empty
  identifier is a caller precondition, per the module's own top-of-file comment naming `ecosystemId` as
  something "the caller must manage."
- **Null and empty input — `state`**: `decodeOAuthStateClaims` MUST return `null` for the empty string (no
  `.` present, per `decode-state-claims-grammar`) rather than throw.
- **Null and empty input — `createLinkToken`'s optional body**: an omitted `body` argument MUST be sent as
  `{}`, per `create-link-token-request-shape`; there is no distinct "send nothing" path.
- **Boundary values — OAuth state freshness**: the widened window's both edges are inclusive per
  `state-freshness-window`; one millisecond outside either edge MUST flip the result, as vectors 039–041
  show.
- **Boundary values — `state` grammar**: a `.` at position `0` or at the last character position are both
  rejected by `decode-state-claims-grammar`; a `.` anywhere strictly between the first and last character of
  a non-empty prefix and a non-empty suffix is the only accepted shape.
- **Concurrent access — module state**: `integrationsApi` holds no shared mutable state between calls (per
  `stateless-module`), so there is nothing for two concurrent calls to race on within this module itself.
- **Concurrent access — repeat `connect` calls**: both calls are sent; see **connect-repeat-call-ordering**
  below.
- **Concurrent access — repeat `rotateWebhookSecret` calls**: calling `rotateWebhookSecret` twice in
  succession MUST NOT be treated as idempotent — each call mints a distinct new secret and invalidates
  whatever secret the config held immediately before, by design (`rotate-webhook-secret-is-destructive`);
  this is the opposite of `adoptInstallations`'s documented safe-to-repeat behavior.
- **Error states — malformed test request vs. refused credential**: a malformed `testProviderConfig`/
  `testProviderCredentials` request (unknown provider, undeclared field, non-testable provider) MUST throw,
  while a syntactically valid request the provider simply refuses MUST resolve with `ok: false`
  (`test-result-ok-false-is-not-an-error`) — these are two distinct failure shapes a caller must not
  conflate.
- **Error states — sync with no worker**: `sync-no-worker-throws-503` is the one documented, provider-scoped
  status code this client's own comments call out by number; every other non-2xx status is handled only
  generically, via `AuthHttpError`'s `status`/`code`.
- **Offline or disconnected state**: no `integrationsApi` method catches a network-level `fetch` rejection or
  retries beyond the single inherited `401` refresh-and-retry waterfall (`session-refresh-waterfall`); a
  connectivity loss mid-call propagates as an unhandled promise rejection out of `integrationsApi` to the
  caller, with no queuing or offline-specific handling anywhere in this file.
- **No timeout**: no method in this file sets a deadline or passes an `AbortSignal`; a reachable-but-
  unresponsive backend leaves the call pending until the underlying `fetch` implementation's own limit, if
  any.
- **No cancellation**: no method accepts an `AbortSignal` parameter, so a caller cannot cancel an in-flight
  request through this module.
- **`oauthCallbackUrl` outside a browser**: calling it where `window` is undefined (e.g. during
  server-side rendering) MUST throw whatever `ReferenceError` accessing `window.location` produces in that
  environment — a documented, client-only precondition (`oauth-callback-url-is-origin-relative`), not a
  gap this client guards against.
- **connect-repeat-call-ordering**: each `connect` call issues exactly one `POST /integrations/connect` with no idempotency key and no client-side de-duplication; two calls for the same `providerId`/`serviceType`/`ecosystemId`/external account — concurrent, or one retried after a dropped response — both reach the backend, which alone decides whether the second is an upsert, a conflict, or a second connection. Unlike `adoptInstallations`, no comment documents a repeat `connect` as safe.
