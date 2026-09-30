<!-- leaf: implement-status-server/config--edge-cases · source: status-server-config.md -->

# Status Server Config

**Rules** (cite as `implement-status-server/config--edge-cases#<slug>`):

- `null-and-empty-input` MUST — an unset PEER_TOKEN, CORS_ALLOWED_HOSTS, MCP_ALLOWED_HOSTS, or ADMIN_EMAILS all resolve to a defined empty value ('' or …
- `boundary-values` MUST — DEPLOY_SYNC_SECONDS='0' and GITHUB_FETCH_TIMEOUT_MS='0' MUST both resolve null, because positiveNumber requires …
- `concurrent-access` MUST — envConfig and every function in port.ts are pure with respect to their arguments and hold no module-level mutable …
- `a-malformed-numeric-env-value` MUST — PORT or PROBE_INTERVAL_SECONDS set to a non-numeric string (e.g. "abc") MUST resolve NaN with no thrown error and no …
- `a-production-deploy-whose-node-env-is-not-the-literal-production` MUST — the SEC-M5 guard MUST NOT fire, even if RAILWAY_ENVIRONMENT_NAME says otherwise — see …

## Edge Cases

- **Null and empty input**: an unset `PEER_TOKEN`, `CORS_ALLOWED_HOSTS`,
  `MCP_ALLOWED_HOSTS`, or `ADMIN_EMAILS` all resolve to a defined empty
  value (`''` or `[]`) rather than `undefined` or a thrown error, per
  peer-token-default-empty, cors-allowed-hosts-parsing,
  mcp-allowed-hosts-parsing, and admin-emails-lowercased. MUST behave this
  way; an empty `SeedRoster` MUST likewise resolve to zero created rows per
  seed-roster-empty-semantics, not an error.
- **Boundary values**: `DEPLOY_SYNC_SECONDS='0'` and
  `GITHUB_FETCH_TIMEOUT_MS='0'` MUST both resolve `null`, because
  `positiveNumber` requires strictly `n > 0`; `GLITCHTIP_PROJECTS=',,'`
  (every entry blank) MUST resolve `null`, not `[]`, per
  glitchtip-projects-parsing. By contrast, `PORT='0'` and
  `PROBE_INTERVAL_SECONDS='0'` MUST resolve the number `0` unchanged — this
  is the numeric-env-coercion/numeric-env-validation asymmetry: only the
  `positiveNumber`-routed fields reject a zero or negative boundary.
- **Concurrent access**: `envConfig` and every function in `port.ts` are
  pure with respect to their arguments and hold no module-level mutable
  state; two concurrent calls to `envConfig` with different `env` objects
  MUST NOT observe or affect each other. Because JavaScript is
  single-threaded, two logical callers sharing the *same* live `env`
  object (e.g. `process.env`) cannot interleave a read and a write —
  lazy-field-evaluation's re-read on every access is a documented,
  deterministic ordering fact, not an unordered race.
- **Error states — a dependency being unavailable**: none of `env.ts`,
  `port.ts`, or `seed.ts` performs file I/O, a database call, or a network
  request, so there is no "dependency unavailable" failure mode within
  these three files to handle; the sole failure path any of them defines
  is the synchronous, deterministic production-escape-hatch-guard throw.
- **Offline / disconnected state**: not applicable for the same reason —
  these three files never hold a network connection to lose. Their fields
  configure timeouts and URLs (`github.fetchTimeoutMs`, `heartbeatUrl`,
  `alertWebhookUrl`, the webhook secrets) that other, external modules use
  to make and retry network calls; that retry/timeout behavior is
  specified in those modules, not here.
- **A malformed numeric env value**: `PORT` or `PROBE_INTERVAL_SECONDS` set
  to a non-numeric string (e.g. `"abc"`) MUST resolve `NaN` with no thrown
  error and no fallback to the documented default — see the open question
  on numeric-env-validation.
- **A production deploy whose `NODE_ENV` is not the literal `"production"`**:
  the SEC-M5 guard MUST NOT fire, even if `RAILWAY_ENVIRONMENT_NAME` says
  otherwise — see production-guard-environment-signal.
