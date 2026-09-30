<!-- leaf: implement-status-server/auth · source: status-server-auth.md -->

# Status Server Auth

## Overview

This is the status backend's authentication layer: five files under
`src/auth/` that together resolve who is calling the API, mint and read the
browser session, log a caller in through GitHub, and hash passwords.
`port.ts` defines the host-implementable `AuthGate` contract (the `authenticate`
function every gate implements, and the `AuthRequest`/`AuthVars` shapes it
reads and returns). `default-adapter.ts` is the shipped `AuthGate`:
session cookie, `sts_`-prefixed API bearer tokens, a machine `PEER_TOKEN`, and
an `AUTH_DISABLED` dev/e2e escape hatch, resolved in that order against this
package's own `Storage` port. `cookie.ts` owns the one browser cookie this
package sets, `status_auth`. `github.ts` is the GitHub OAuth login flow
(`/auth/github/start` and `/auth/github/callback`), including the
upsert-or-link logic that turns a GitHub identity into a `UserRecord`.
`password.ts` hashes and verifies passwords with bcrypt and exports a
precomputed dummy hash for timing-equalized login comparisons.

The Hono binding that turns a gate's resolution into an HTTP response
(`requireAuth`, `requireAdmin` in `../middleware/auth`) and the `Storage`
implementation these files call into (`AuthStore`/`TokenStore` in
`../storage/ports`, backed by libSQL) are external to this recipe's five
files; this recipe cites their documented contracts only where the auth
files depend on them, and never specifies their internals.

