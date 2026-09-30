<!-- leaf: implement-status-server/middleware--logging · source: status-server-middleware.md -->

# Status Server Middleware

## Logging

Subsystem: n/a (status backend) | Category: `rate-limit`

| Event | Level | Message |
|-------|-------|---------|
| Hard-cap drop | error | `` [rate-limit] bucket table exceeded ${MAX_BUCKETS} live keys — dropping it `` |

`auth.ts` contains no logging call at any level; the table above is
`rate-limit.ts`'s only log statement, and it names a bucket count and the
fixed `50_000` threshold — never a key, an IP address, or a credential.
